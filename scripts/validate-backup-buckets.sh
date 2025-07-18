#!/bin/bash

# Script to validate the current state of backup buckets
# This helps diagnose issues and confirm everything is working correctly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Hyperliquid Backup Bucket Validation${NC}"
echo "===================================="

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
echo -e "${BLUE}Getting AWS account information...${NC}"
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

echo -e "${BLUE}Expected bucket names:${NC}"
echo "  - Backup bucket: $BACKUP_BUCKET"
echo "  - State bucket: $STATE_BUCKET"

# Function to check if bucket exists in AWS
check_bucket_exists_aws() {
    local bucket_name=$1
    if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to check if bucket exists in Terraform state
check_bucket_exists_terraform() {
    local terraform_resource=$1
    if terraform state show "$terraform_resource" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Check backup bucket
echo -e "${BLUE}Checking backup bucket...${NC}"
if check_bucket_exists_aws "$BACKUP_BUCKET"; then
    echo -e "${GREEN}✓ Backup bucket exists in AWS${NC}"
    
    if check_bucket_exists_terraform "module.backup[0].aws_s3_bucket.backup"; then
        echo -e "${GREEN}✓ Backup bucket exists in Terraform state${NC}"
    else
        echo -e "${YELLOW}⚠ Backup bucket exists in AWS but not in Terraform state${NC}"
        echo "  Run: terraform import \"module.backup[0].aws_s3_bucket.backup\" \"$BACKUP_BUCKET\""
    fi
else
    echo -e "${RED}✗ Backup bucket does not exist in AWS${NC}"
    
    if check_bucket_exists_terraform "module.backup[0].aws_s3_bucket.backup"; then
        echo -e "${YELLOW}⚠ Backup bucket exists in Terraform state but not in AWS${NC}"
        echo "  This indicates a state drift. Run terraform apply to create the bucket."
    else
        echo -e "${YELLOW}⚠ Backup bucket does not exist in Terraform state${NC}"
        echo "  This is normal for new deployments. Run terraform apply to create it."
    fi
fi

# Check backup state bucket
echo -e "${BLUE}Checking backup state bucket...${NC}"
if check_bucket_exists_aws "$STATE_BUCKET"; then
    echo -e "${GREEN}✓ Backup state bucket exists in AWS${NC}"
    
    if check_bucket_exists_terraform "module.backup[0].aws_s3_bucket.backup_state"; then
        echo -e "${GREEN}✓ Backup state bucket exists in Terraform state${NC}"
    else
        echo -e "${YELLOW}⚠ Backup state bucket exists in AWS but not in Terraform state${NC}"
        echo "  Run: terraform import \"module.backup[0].aws_s3_bucket.backup_state\" \"$STATE_BUCKET\""
    fi
else
    echo -e "${RED}✗ Backup state bucket does not exist in AWS${NC}"
    
    if check_bucket_exists_terraform "module.backup[0].aws_s3_bucket.backup_state"; then
        echo -e "${YELLOW}⚠ Backup state bucket exists in Terraform state but not in AWS${NC}"
        echo "  This indicates a state drift. Run terraform apply to create the bucket."
    else
        echo -e "${YELLOW}⚠ Backup state bucket does not exist in Terraform state${NC}"
        echo "  This is normal for new deployments. Run terraform apply to create it."
    fi
fi

# Check if backup is enabled
echo -e "${BLUE}Checking backup configuration...${NC}"
if grep -q "enable_backup.*true" terraform.tfvars 2>/dev/null; then
    echo -e "${GREEN}✓ Backup is enabled in terraform.tfvars${NC}"
else
    echo -e "${YELLOW}⚠ Backup is not enabled in terraform.tfvars${NC}"
    echo "  Add 'enable_backup = true' to terraform.tfvars to enable backup functionality"
fi

# Check Terraform state
echo -e "${BLUE}Checking Terraform state...${NC}"
if terraform state list | grep -q "module.backup"; then
    echo -e "${GREEN}✓ Backup module resources found in Terraform state${NC}"
    echo "Backup module resources:"
    terraform state list | grep "module.backup" | sed 's/^/  - /'
else
    echo -e "${YELLOW}⚠ No backup module resources found in Terraform state${NC}"
    echo "  This is normal if backup is disabled or this is a new deployment"
fi

echo ""
echo -e "${GREEN}Validation complete!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. If buckets exist in AWS but not in Terraform state, run the import script: ./import-existing-buckets.sh"
echo "2. If everything looks good, run: terraform plan"
echo "3. If plan shows no changes, your backup configuration is properly synced"
echo "4. If plan shows changes, run: terraform apply"