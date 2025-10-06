#!/bin/bash

# Enhanced teardown script for full AWS cleanup with automatic recovery
# Handles DELETE_FAILED gracefully and logs root causes

set -euo pipefail

UNIQUE_SUFFIX="jr"
PHASE2_STACK_NAME="iac-phase2"
PHASE1_STACK_NAME="iac-phase1"
GITHUB_ROLE_STACK_NAME="disguise-github-role-stack"
ECR_REPO_NAME="iac-etl-repo-${UNIQUE_SUFFIX}"
LOG_FILE="teardown_$(date +%Y%m%d_%H%M%S).log"

log() {
  echo -e "$@" | tee -a "$LOG_FILE"
}

handle_delete_failed() {
  local stack_name=$1
  log "⚠️  Stack ${stack_name} deletion failed. Checking for root cause..."

  aws cloudformation describe-stack-events \
    --stack-name "$stack_name" \
    --query "StackEvents[?ResourceStatus=='DELETE_FAILED'].{LogicalResourceId:LogicalResourceId, ResourceType:ResourceType, StatusReason:ResourceStatusReason}" \
    --output table | tee -a "$LOG_FILE"

  log ""
  log "🧹 Attempting cleanup of known blocking resources..."

  # --- Empty S3 buckets that block deletion ---
  local BUCKETS
  BUCKETS=$(aws cloudformation describe-stack-resources \
    --stack-name "$stack_name" \
    --query "StackResources[?ResourceType=='AWS::S3::Bucket'].PhysicalResourceId" \
    --output text)

  for bucket in $BUCKETS; do
    if aws s3 ls "s3://${bucket}" >/dev/null 2>&1; then
      log "Emptying and deleting S3 bucket: ${bucket}..."
      aws s3 rm "s3://${bucket}" --recursive || true
      aws s3 rb "s3://${bucket}" --force || true
    fi
  done

  # --- Delete ECR repositories that still contain images ---
  local ECR_REPOS
  ECR_REPOS=$(aws cloudformation describe-stack-resources \
    --stack-name "$stack_name" \
    --query "StackResources[?ResourceType=='AWS::ECR::Repository'].PhysicalResourceId" \
    --output text)

  for repo in $ECR_REPOS; do
    if aws ecr describe-repositories --repository-names "$repo" >/dev/null 2>&1; then
      log "Cleaning up ECR repository: ${repo}..."
      IMAGE_IDS=$(aws ecr list-images --repository-name "$repo" --query 'imageIds[*]' --output json)
      if [ "$IMAGE_IDS" != "[]" ]; then
        aws ecr batch-delete-image --repository-name "$repo" --image-ids "$IMAGE_IDS" || true
      fi
      aws ecr delete-repository --repository-name "$repo" --force || true
      log "✅ ECR repository ${repo} cleaned up."
    fi
  done

  # --- Redshift Serverless cleanup (no --no-final-snapshot flag) ---
  local RS_WORKGROUPS
  RS_WORKGROUPS=$(aws cloudformation describe-stack-resources \
    --stack-name "$stack_name" \
    --query "StackResources[?ResourceType=='AWS::RedshiftServerless::Workgroup'].PhysicalResourceId" \
    --output text)
  for wg in $RS_WORKGROUPS; do
    log "Deleting Redshift workgroup: ${wg}..."
    aws redshift-serverless delete-workgroup --workgroup-name "$wg" || true
  done

  local RS_NAMESPACES
  RS_NAMESPACES=$(aws cloudformation describe-stack-resources \
    --stack-name "$stack_name" \
    --query "StackResources[?ResourceType=='AWS::RedshiftServerless::Namespace'].PhysicalResourceId" \
    --output text)
  for ns in $RS_NAMESPACES; do
    log "Deleting Redshift namespace: ${ns}..."
    aws redshift-serverless delete-namespace --namespace-name "$ns" || true
  done

  log "🔁 Retrying deletion of ${stack_name} after cleanup..."
  aws cloudformation delete-stack --stack-name "$stack_name"
  aws cloudformation wait stack-delete-complete --stack-name "$stack_name" \
    && log "✅ ${stack_name} stack successfully deleted on retry." \
    || log "❌ ${stack_name} still failed to delete after retry. Check ${LOG_FILE} for details."
}

delete_stack_safely() {
  local stack_name=$1
  if aws cloudformation describe-stacks --stack-name "$stack_name" >/dev/null 2>&1; then
    log "🔥 Deleting stack ${stack_name}..."
    aws cloudformation delete-stack --stack-name "$stack_name"
    set +e
    aws cloudformation wait stack-delete-complete --stack-name "$stack_name"
    local exit_code=$?
    set -e
    if [ $exit_code -ne 0 ]; then
      handle_delete_failed "$stack_name"
    else
      log "✅ ${stack_name} deleted successfully."
    fi
  else
    log "⚠️  Stack ${stack_name} does not exist. Skipping."
  fi
  log ""
}

log "🚀 Starting full teardown of all project infrastructure..."
log "--------------------------------------------------------"

# --- Delete stacks in reverse order ---
delete_stack_safely "$PHASE2_STACK_NAME"
delete_stack_safely "$PHASE1_STACK_NAME"
delete_stack_safely "$GITHUB_ROLE_STACK_NAME"

# --- Delete ECR repo ---
log "🔥 Deleting ECR repository (${ECR_REPO_NAME})..."
if aws ecr describe-repositories --repository-names "${ECR_REPO_NAME}" >/dev/null 2>&1; then
  aws ecr delete-repository --repository-name "${ECR_REPO_NAME}" --force
  log "✅ ECR repository ${ECR_REPO_NAME} deleted."
else
  log "⚠️  ECR repository ${ECR_REPO_NAME} not found. Skipping."
fi
log ""

# --- Delete GitHub OIDC provider ---
log "🔥 Deleting GitHub OIDC Identity Provider..."
OIDC_PROVIDER_ARN=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?Arn.contains(@, 'token.actions.githubusercontent.com')].Arn" --output text)
if [ -n "$OIDC_PROVIDER_ARN" ]; then
  log "Found OIDC Provider ARN: ${OIDC_PROVIDER_ARN}. Deleting..."
  aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "${OIDC_PROVIDER_ARN}"
  log "✅ GitHub OIDC Identity Provider deleted."
else
  log "⚠️  No GitHub OIDC Identity Provider found."
fi

log "--------------------------------------------------------"
log "🎉 Full teardown complete. Check ${LOG_FILE} for full details."
