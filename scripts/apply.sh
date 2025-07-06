#!/bin/bash
set -euo pipefail

# Script to apply Terraform configuration

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
    echo -e "${YELLOW}Warning: terraform.tfvars not found${NC}"
    echo "Creating from example..."
    if [ -f "terraform.tfvars.example" ]; then
        cp terraform.tfvars.example terraform.tfvars
        echo -e "${GREEN}Created terraform.tfvars from example${NC}"
        echo "Please edit terraform.tfvars with your values before running this script again"
        exit 1
    else
        echo -e "${RED}Error: terraform.tfvars.example not found${NC}"
        exit 1
    fi
fi

# Initialize if needed
if [ ! -d ".terraform" ]; then
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init
fi

# Run plan first
echo -e "${YELLOW}Running terraform plan...${NC}"
terraform plan -var-file="terraform.tfvars"

# Ask for confirmation
echo -e "${YELLOW}Do you want to apply these changes? (yes/no)${NC}"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "${GREEN}Applying Terraform configuration...${NC}"
    terraform apply -var-file="terraform.tfvars"
else
    echo -e "${YELLOW}Apply cancelled${NC}"
    exit 0
fi