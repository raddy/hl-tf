#!/bin/bash
# Pre-deployment validation script for Hyperliquid Terraform
set -euo pipefail

echo "=== Hyperliquid Deployment Validation ==="
echo "This script validates your configuration BEFORE deployment"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validation results
ERRORS=0
WARNINGS=0

# Function to check a setting
check_setting() {
    local setting=$1
    local expected=$2
    local file=$3
    local critical=${4:-true}
    
    if grep -q "^${setting}.*=.*${expected}" "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $setting = $expected"
        return 0
    else
        if [ "$critical" = true ]; then
            echo -e "${RED}✗${NC} $setting is NOT set to $expected (CRITICAL)"
            ERRORS=$((ERRORS + 1))
        else
            echo -e "${YELLOW}⚠${NC} $setting is NOT set to $expected (WARNING)"
            WARNINGS=$((WARNINGS + 1))
        fi
        return 1
    fi
}

echo "1. Checking terraform.tfvars configuration..."
echo "----------------------------------------"

# Check critical data collection settings
check_setting "write_trades" "true" "terraform.tfvars"
check_setting "write_order_statuses" "true" "terraform.tfvars"
check_setting "write_events" "true" "terraform.tfvars"
check_setting "enable_backup" "true" "terraform.tfvars"
check_setting "enable_tcpdump" "true" "terraform.tfvars"

echo ""
echo "2. Checking required script files..."
echo "----------------------------------------"

# Check all required scripts exist
REQUIRED_SCRIPTS=(
    "modules/scripts/templates/scripts/01-system-setup.sh"
    "modules/scripts/templates/scripts/02-storage-setup.sh"
    "modules/scripts/templates/scripts/03-install-hl.sh"
    "modules/scripts/templates/scripts/04-configure-hl.sh"
    "modules/scripts/templates/scripts/05-start-service.sh"
    "modules/scripts/templates/scripts/06-monitoring-setup.sh"
    "modules/scripts/templates/scripts/07-backup-setup.sh"
    "modules/scripts/templates/scripts/hl-backup.sh"
    "modules/scripts/templates/scripts/hl-backup-sweep.sh"
    "modules/scripts/templates/scripts/tcpdump-wrapper.sh"
)

for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        echo -e "${GREEN}✓${NC} $script exists"
    else
        echo -e "${RED}✗${NC} $script is MISSING"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
echo "3. Checking script syntax..."
echo "----------------------------------------"

# Check bash syntax for all scripts
for script in modules/scripts/templates/scripts/*.sh; do
    if [ -f "$script" ]; then
        if bash -n "$script" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} $(basename "$script") - syntax OK"
        else
            echo -e "${RED}✗${NC} $(basename "$script") - SYNTAX ERROR"
            bash -n "$script" 2>&1 | sed 's/^/    /'
            ERRORS=$((ERRORS + 1))
        fi
    fi
done

echo ""
echo "4. Checking Terraform state..."
echo "----------------------------------------"

# Check if instance is tainted
if terraform state list | grep -q "module.compute.aws_instance.validator"; then
    if terraform show -json | jq -r '.values.root_module.child_modules[].resources[] | select(.address == "module.compute.aws_instance.validator") | .tainted' | grep -q "true"; then
        echo -e "${GREEN}✓${NC} Instance is marked for recreation (tainted)"
    else
        echo -e "${YELLOW}⚠${NC} Instance exists and is NOT tainted - run 'terraform taint module.compute.aws_instance.validator' to force recreation"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "${GREEN}✓${NC} No existing instance found"
fi

echo ""
echo "5. Checking AWS credentials..."
echo "----------------------------------------"

if aws sts get-caller-identity >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} AWS credentials are configured"
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo "   Account ID: $ACCOUNT_ID"
else
    echo -e "${RED}✗${NC} AWS credentials are NOT configured"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "6. Expected data collection after deployment:"
echo "----------------------------------------"
echo "The following data will be collected:"
echo "  • /var/hl/data/node_trades/ - Trading data"
echo "  • /var/hl/data/node_order_statuses/ - Order status updates"
echo "  • /var/hl/data/misc_events/ - Miscellaneous events"
echo "  • /var/hl/data/replica_cmds/ - Replica commands"
echo "  • /var/hl/pcap/ - Network packet captures (10-minute rotations)"
echo ""
echo "All data will be backed up to S3 with zero data loss guarantee"

echo ""
echo "========================================="
if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}VALIDATION FAILED${NC}"
    echo "Errors: $ERRORS"
    echo "Warnings: $WARNINGS"
    echo ""
    echo "Fix the errors above before deploying!"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}VALIDATION PASSED WITH WARNINGS${NC}"
    echo "Warnings: $WARNINGS"
    echo ""
    echo "Review warnings above. Deployment will work but may not be optimal."
    exit 0
else
    echo -e "${GREEN}VALIDATION PASSED${NC}"
    echo "All checks passed! Ready to deploy."
    echo ""
    echo "Run: ./full-restart.sh"
    exit 0
fi