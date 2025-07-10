#!/bin/bash
# Full restart script - destroy, update scripts, and apply
# Auto-approves all terraform operations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "================================================"
echo "Full Restart: Destroy -> Update Scripts -> Apply"
echo "================================================"
echo ""

# Step 1: Destroy existing infrastructure
echo "Step 1/3: Destroying existing infrastructure..."
echo "----------------------------------------"
terraform destroy -auto-approve || {
    echo "Warning: Destroy failed or nothing to destroy, continuing..."
}

echo ""
echo "Step 2/3: Forcing script updates..."
echo "----------------------------------------"

# Touch all script files to force etag change
find modules/scripts/templates/scripts -name "*.sh" -exec touch {} \;
find modules/scripts/templates/scripts -name "*.asc" -exec touch {} \;

echo "Script files touched to force update"

# Show which scripts will be updated
echo ""
echo "Scripts that will be updated:"
ls -la modules/scripts/templates/scripts/*.sh | awk '{print "  - " $9}'

echo ""
echo "Step 3/3: Applying new infrastructure..."
echo "----------------------------------------"

# Initialize if needed
if [ ! -d ".terraform" ]; then
    echo "Initializing terraform..."
    terraform init
fi

# Apply with auto-approve
terraform apply -auto-approve

echo ""
echo "================================================"
echo "Full restart complete!"
echo "================================================"
echo ""
echo "To check instance status:"
echo "  aws ec2 describe-instances --filters 'Name=tag:Project,Values=hl-node' --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress,State.Name]' --output table"
echo ""
echo "To SSH to the instance (once ready):"
echo "  ssh ubuntu@<public-ip>"
echo ""
echo "To check bootstrap progress:"
echo "  ssh ubuntu@<public-ip> 'sudo tail -f /var/log/cloud-init-output.log'"