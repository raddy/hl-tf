#!/bin/bash

# Script to import existing S3 buckets into Terraform state
# This is useful when buckets were created manually or from previous deployments

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Hyperliquid Terraform S3 Bucket Import Script${NC}"
echo "=============================================="

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform is not installed or not in PATH${NC}"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed or not in PATH${NC}"
    exit 1
fi

# Get AWS account ID
echo -e "${YELLOW}Getting AWS account information...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to get AWS account ID. Please check your AWS credentials.${NC}"
    exit 1
fi

echo "AWS Account ID: $ACCOUNT_ID"

# Get project name from terraform.tfvars or use default
PROJECT_NAME="hyperliquid"
if [ -f "terraform.tfvars" ]; then
    # Try to extract project_name from terraform.tfvars, fallback to default
    EXTRACTED_NAME=$(grep -E "^project_name\s*=" terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "")
    if [ -n "$EXTRACTED_NAME" ]; then
        PROJECT_NAME="$EXTRACTED_NAME"
    fi
fi

echo "Project name: $PROJECT_NAME"

# Construct bucket names
BACKUP_BUCKET="${PROJECT_NAME}-backup-${ACCOUNT_ID}"
STATE_BUCKET="${PROJECT_NAME}-backup-${ACCOUNT_ID}-state"

echo -e "${YELLOW}Expected bucket names:${NC}"
echo "  - Backup bucket: $BACKUP_BUCKET"
echo "  - State bucket: $STATE_BUCKET"

# Function to check if bucket exists
check_bucket_exists() {
    local bucket_name=$1
    if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to import bucket if it exists
import_bucket() {
    local bucket_name=$1
    local terraform_resource=$2
    
    if check_bucket_exists "$bucket_name"; then
        echo -e "${GREEN}Found existing bucket: $bucket_name${NC}"
        echo "Importing into Terraform state..."
        
        if terraform import "$terraform_resource" "$bucket_name"; then
            echo -e "${GREEN}Successfully imported $bucket_name${NC}"
            return 0
        else
            echo -e "${RED}Failed to import $bucket_name${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}Bucket $bucket_name does not exist - will be created by Terraform${NC}"
        return 0
    fi
}

# Initialize Terraform if needed
if [ ! -f ".terraform/terraform.tfstate" ]; then
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init
fi

# Check if backup is enabled
BACKUP_ENABLED=$(grep -E "^enable_backup\s*=" terraform.tfvars | grep -i true || echo "")

if [ -z "$BACKUP_ENABLED" ]; then
    echo -e "${RED}Error: Backup is not enabled in terraform.tfvars${NC}"
    echo "Please set 'enable_backup = true' in terraform.tfvars"
    exit 1
fi

echo -e "${YELLOW}Starting import process...${NC}"

# Import backup bucket
import_bucket "$BACKUP_BUCKET" "module.backup[0].aws_s3_bucket.backup"

# Import backup state bucket  
import_bucket "$STATE_BUCKET" "module.backup[0].aws_s3_bucket.backup_state"

echo -e "${GREEN}Import process completed!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Run 'terraform plan' to see what changes will be made"
echo "2. Run 'terraform apply' to apply any necessary configuration changes"
echo ""
echo -e "${GREEN}Note: The updated backup module will now check for existing buckets${NC}"
echo "and only create them if they don't exist, preventing future conflicts."