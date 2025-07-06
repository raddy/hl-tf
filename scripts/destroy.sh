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
echo -e "${RED}WARNING: This will destroy all resources managed by Terraform!${NC}"
echo -e "${YELLOW}Note: The data volume will be preserved (delete_on_termination = false)${NC}"
echo ""
echo -e "${YELLOW}Are you sure you want to destroy these resources? Type 'yes' to confirm:${NC}"
read -r response

if [ "$response" = "yes" ]; then
    echo -e "${RED}Destroying Terraform resources...${NC}"
    terraform destroy -var-file="terraform.tfvars"
    echo -e "${GREEN}Resources destroyed successfully${NC}"
    echo -e "${YELLOW}Note: Data volume was preserved. Delete it manually from AWS console if needed.${NC}"
else
    echo -e "${GREEN}Destroy cancelled${NC}"
    exit 0
fi