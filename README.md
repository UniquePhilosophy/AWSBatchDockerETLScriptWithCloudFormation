# AWS Batch Docker ETL Script with IaC/CI/CD
With CloudFormation and GitHub Actions

## Description

CloudFormation was used to spin up an AWS infrastructure responsible for running a containerised (Docker) ETL Script in AWS Batch. GitHub actions were configured with OIDC in order to secure the GitHub/Amazon connection and then used to automate the development/deployment lifecycle.

## Security

OIDC is used to provide access to AWS for GitHub actions. Then, in the IAM GitHub Role yaml file, we assign a condition to the RolePolicyDocument to specify only the required GitHub repository with access to AWS.