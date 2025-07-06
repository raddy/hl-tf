#!/bin/bash
set -euo pipefail

# Script to initialize Terraform project

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Hyperliquid Validator Node - Terraform Setup${NC}"
echo "============================================"
echo ""

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform is not installed${NC}"
    echo "Please install Terraform >= 1.5.7 from https://www.terraform.io/downloads"
    exit 1
fi

# Check terraform version
TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || terraform version | head -n1 | cut -d' ' -f2 | sed 's/^v//')
echo -e "${GREEN}Found Terraform version: $TERRAFORM_VERSION${NC}"

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init

# Create terraform.tfvars if it doesn't exist
if [ ! -f "terraform.tfvars" ]; then
    echo ""
    echo -e "${YELLOW}Creating terraform.tfvars from example...${NC}"
    if [ -f "terraform.tfvars.example" ]; then
        cp terraform.tfvars.example terraform.tfvars
        echo -e "${GREEN}Created terraform.tfvars${NC}"
        echo ""
        echo -e "${YELLOW}Next steps:${NC}"
        echo "1. Edit terraform.tfvars with your AWS configuration"
        echo "2. Run './scripts/apply.sh' to deploy the validator node"
        echo ""
        echo -e "${YELLOW}Required values to configure:${NC}"
        echo "- vpc_id: Your AWS VPC ID"
        echo "- public_subnet_id: Your public subnet ID"
        echo "- ssh_allowed_cidr_blocks: Your IP address for SSH access"
        echo ""
    else
        echo -e "${RED}Error: terraform.tfvars.example not found${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}terraform.tfvars already exists${NC}"
    echo ""
    echo -e "${YELLOW}Ready to deploy!${NC}"
    echo "Run './scripts/apply.sh' to deploy the validator node"
fi