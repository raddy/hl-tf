#!/bin/bash
set -euo pipefail

# Script to destroy Terraform resources

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform is not installed${NC}"
    exit 1
fi

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${RED}Error: terraform.tfvars not found${NC}"
    echo "Cannot destroy without knowing which resources to target"
    exit 1
fi

# Check if .terraform directory exists
if [ ! -d ".terraform" ]; then
    echo -e "${YELLOW}Terraform not initialized. Initializing...${NC}"
    terraform init
fi

# Show what will be destroyed
echo -e "${YELLOW}The following resources will be destroyed:${NC}"
terraform plan -destroy -var-file="terraform.tfvars" | grep -E "will be destroyed|# aws_" || true

echo ""
echo -e "${RED}WARNING: This will destroy EC2 and EBS resources!${NC}"
echo -e "${GREEN}Note: S3 buckets and data will be preserved${NC}"
echo ""
echo -e "${YELLOW}Are you sure you want to destroy these resources? Type 'yes' to confirm:${NC}"
read -r response

if [ "$response" = "yes" ]; then
    echo -e "${RED}Destroying resources (excluding backup module with S3 buckets)...${NC}"
    
    # Destroy everything except the backup module
    terraform destroy \
        -target=module.compute \
        -target=module.iam \
        -target=module.network \
        -target=module.security \
        -target=module.scripts \
        -target=aws_key_pair.validator \
        -target=aws_placement_group.cluster \
        -var-file="terraform.tfvars" \
        -auto-approve
    
    echo -e "${GREEN}EC2 and EBS resources destroyed successfully${NC}"
    echo -e "${GREEN}S3 buckets and data preserved${NC}"
else
    echo -e "${GREEN}Destroy cancelled${NC}"
    exit 0
fi