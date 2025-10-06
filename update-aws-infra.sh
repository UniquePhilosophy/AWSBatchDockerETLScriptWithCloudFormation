#!/bin/bash
set -e

# This script is safe to run multiple times. It will UPDATE existing stacks.
UNIQUE_SUFFIX="jr"
AWS_REGION="eu-west-2" # Set your default region here

echo "✅ Deploying/Updating network & IAM stack (Phase 1)..."
aws cloudformation deploy \
    --stack-name iac-phase1 \
    --template-file network-and-iam.yml \
    --parameter-overrides UniqueSuffix=$UNIQUE_SUFFIX \
    --capabilities CAPABILITY_NAMED_IAM \
    --region $AWS_REGION

echo "Phase 1 stack is up-to-date."

echo " fetching outputs for phase 2..."
OUTPUTS=$(aws cloudformation describe-stacks --stack-name iac-phase1 \
          --query "Stacks[0].Outputs" --output json --region $AWS_REGION)

VPC_ID=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="VPCId") | .OutputValue')
SUBNET1_ID=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="Subnet1Id") | .OutputValue')
SUBNET2_ID=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="Subnet2Id") | .OutputValue')
SECURITY_GROUP_ID=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="BatchSecurityGroupId") | .OutputValue')
BATCH_ROLE_ARN=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="BatchJobRoleArn") | .OutputValue')
ECS_EXEC_ROLE_ARN=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="ECSExecutionRoleArn") | .OutputValue')

echo "✅ Deploying/Updating Batch, Redshift, ECR, and S3 stack (Phase 2)..."
aws cloudformation deploy \
    --stack-name iac-phase2 \
    --template-file etl-batch-redshift.yml \
    --parameter-overrides UniqueSuffix=$UNIQUE_SUFFIX \
                 VPCId=$VPC_ID \
                 Subnet1Id=$SUBNET1_ID \
                 Subnet2Id=$SUBNET2_ID \
                 BatchSecurityGroupId=$SECURITY_GROUP_ID \
                 BatchJobRoleArn=$BATCH_ROLE_ARN \
                 ECSExecutionRoleArn=$ECS_EXEC_ROLE_ARN \
    --capabilities CAPABILITY_NAMED_IAM \
    --region $AWS_REGION

echo "🚀 All infrastructure is deployed and up-to-date!"