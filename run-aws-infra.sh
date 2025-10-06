#!/bin/bash
set -e

UNIQUE_SUFFIX="jr"

echo "Deploying network & IAM stack..."
aws cloudformation create-stack \
    --stack-name iac-phase1 \
    --template-body file://network-and-iam.yml \
    --parameters ParameterKey=UniqueSuffix,ParameterValue=$UNIQUE_SUFFIX \
    --capabilities CAPABILITY_NAMED_IAM

echo "Waiting for phase 1 stack to complete..."
aws cloudformation wait stack-create-complete --stack-name iac-phase1
echo "Phase 1 stack complete."

echo "Fetching outputs for phase 2..."
OUTPUTS=$(aws cloudformation describe-stacks --stack-name iac-phase1 \
          --query "Stacks[0].Outputs" --output json)

VPC_ID=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="VPCId") | .OutputValue')
SUBNET1_ID=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="Subnet1Id") | .OutputValue')
SUBNET2_ID=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="Subnet2Id") | .OutputValue')
SECURITY_GROUP_ID=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="BatchSecurityGroupId") | .OutputValue')
BATCH_ROLE_ARN=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="BatchJobRoleArn") | .OutputValue')
ECS_EXEC_ROLE_ARN=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="ECSExecutionRoleArn") | .OutputValue')

echo "Deploying Batch, Redshift, ECR, and S3 stack..."
aws cloudformation create-stack \
    --stack-name iac-phase2 \
    --template-body file://etl-batch-redshift.yml \
    --parameters ParameterKey=UniqueSuffix,ParameterValue=$UNIQUE_SUFFIX \
                 ParameterKey=VPCId,ParameterValue=$VPC_ID \
                 ParameterKey=Subnet1Id,ParameterValue=$SUBNET1_ID \
                 ParameterKey=Subnet2Id,ParameterValue=$SUBNET2_ID \
                 ParameterKey=BatchSecurityGroupId,ParameterValue=$SECURITY_GROUP_ID \
                 ParameterKey=BatchJobRoleArn,ParameterValue=$BATCH_ROLE_ARN \
                 ParameterKey=ECSExecutionRoleArn,ParameterValue=$ECS_EXEC_ROLE_ARN \
    --capabilities CAPABILITY_NAMED_IAM

echo "Waiting for phase 2 stack to complete..."
aws cloudformation wait stack-create-complete --stack-name iac-phase2

echo "All infrastructure deployed successfully!"
