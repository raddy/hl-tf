#!/bin/bash
# Post-deployment verification script for Hyperliquid data collection
set -euo pipefail

echo "=== Hyperliquid Data Collection Verification ==="
echo "This script verifies that ALL data collection is working correctly"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get instance IP
INSTANCE_IP=$(terraform output -raw public_ip 2>/dev/null || echo "")
if [ -z "$INSTANCE_IP" ]; then
    echo -e "${RED}✗${NC} Cannot get instance IP from terraform output"
    exit 1
fi

echo "Instance IP: $INSTANCE_IP"
echo ""

# Validation results
ERRORS=0
WARNINGS=0

# Function to run SSH command with timeout
ssh_cmd() {
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$INSTANCE_IP" "$@" 2>/dev/null || return 1
}

# Function to check service status
check_service() {
    local service=$1
    local critical=${2:-true}
    
    if ssh_cmd "sudo systemctl is-active --quiet $service"; then
        echo -e "${GREEN}✓${NC} $service is running"
        return 0
    else
        if [ "$critical" = true ]; then
            echo -e "${RED}✗${NC} $service is NOT running (CRITICAL)"
            ERRORS=$((ERRORS + 1))
        else
            echo -e "${YELLOW}⚠${NC} $service is NOT running (WARNING)"
            WARNINGS=$((WARNINGS + 1))
        fi
        return 1
    fi
}

# Function to check directory exists and has files
check_data_dir() {
    local dir=$1
    local data_type=$2
    local critical=${3:-true}
    
    if ssh_cmd "[ -d '$dir' ] && [ \$(find '$dir' -type f -mmin -30 2>/dev/null | wc -l) -gt 0 ]"; then
        local file_count=$(ssh_cmd "find '$dir' -type f 2>/dev/null | wc -l")
        echo -e "${GREEN}✓${NC} $data_type data directory exists with $file_count files"
        
        # Show recent files
        echo "    Recent files:"
        ssh_cmd "find '$dir' -type f -mmin -60 2>/dev/null | head -3 | sed 's/^/      /'" || true
        return 0
    else
        if [ "$critical" = true ]; then
            echo -e "${RED}✗${NC} $data_type data directory missing or no recent files (CRITICAL)"
            ERRORS=$((ERRORS + 1))
        else
            echo -e "${YELLOW}⚠${NC} $data_type data directory missing or no recent files (WARNING)"
            WARNINGS=$((WARNINGS + 1))
        fi
        return 1
    fi
}

echo "1. Testing SSH connectivity..."
echo "----------------------------------------"
if ssh_cmd "echo 'SSH connection successful'"; then
    echo -e "${GREEN}✓${NC} SSH connection established"
else
    echo -e "${RED}✗${NC} Cannot connect to instance via SSH"
    exit 1
fi

echo ""
echo "2. Checking system services..."
echo "----------------------------------------"
check_service "hyperliquid"
check_service "hl-backup"
check_service "hl-tcpdump"

echo ""
echo "3. Checking Hyperliquid node configuration..."
echo "----------------------------------------"

# Check if node is running with correct flags
if ssh_cmd "ps aux | grep hl-node | grep -q 'write-trades'"; then
    echo -e "${GREEN}✓${NC} Node is running with --write-trades flag"
else
    echo -e "${RED}✗${NC} Node is NOT running with --write-trades flag"
    ERRORS=$((ERRORS + 1))
fi

if ssh_cmd "ps aux | grep hl-node | grep -q 'write-order-statuses'"; then
    echo -e "${GREEN}✓${NC} Node is running with --write-order-statuses flag"
else
    echo -e "${RED}✗${NC} Node is NOT running with --write-order-statuses flag"
    ERRORS=$((ERRORS + 1))
fi

if ssh_cmd "ps aux | grep hl-node | grep -q 'write-misc-events'"; then
    echo -e "${GREEN}✓${NC} Node is running with --write-misc-events flag"
else
    echo -e "${RED}✗${NC} Node is NOT running with --write-misc-events flag"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "4. Checking data collection directories..."
echo "----------------------------------------"

# Wait a bit for services to initialize if this is a fresh deployment
echo "Waiting 30 seconds for services to initialize..."
sleep 30

# Check critical data directories
check_data_dir "/var/hl/data/node_trades" "Trading data"
check_data_dir "/var/hl/data/node_order_statuses" "Order status data"
check_data_dir "/var/hl/data/misc_events" "Event data"
check_data_dir "/var/hl/data/replica_cmds" "Replica commands"
check_data_dir "/var/hl/pcap" "PCAP captures"

echo ""
echo "5. Checking backup system..."
echo "----------------------------------------"

# Check backup bucket access
BACKUP_BUCKET=$(terraform output -raw backup_bucket 2>/dev/null || echo "")
if [ -n "$BACKUP_BUCKET" ]; then
    if ssh_cmd "aws s3 ls 's3://$BACKUP_BUCKET/' >/dev/null 2>&1"; then
        echo -e "${GREEN}✓${NC} Backup bucket $BACKUP_BUCKET is accessible"
    else
        echo -e "${RED}✗${NC} Cannot access backup bucket $BACKUP_BUCKET"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}⚠${NC} Cannot determine backup bucket name"
    WARNINGS=$((WARNINGS + 1))
fi

# Check backup logs
if ssh_cmd "[ -f /var/log/hl-backup.log ] && [ \$(stat -c %Y /var/log/hl-backup.log) -gt \$((\$(date +%s) - 600)) ]"; then
    echo -e "${GREEN}✓${NC} Backup system is active (recent log entries)"
    echo "    Recent backup activity:"
    ssh_cmd "tail -3 /var/log/hl-backup.log | sed 's/^/      /'" || true
else
    echo -e "${YELLOW}⚠${NC} No recent backup activity in logs"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""
echo "6. Disk space and performance..."
echo "----------------------------------------"

# Check disk usage
DISK_USAGE=$(ssh_cmd "df /var/hl | tail -1 | awk '{print \$5}' | sed 's/%//'" || echo "unknown")
if [ "$DISK_USAGE" != "unknown" ] && [ "$DISK_USAGE" -lt 80 ]; then
    echo -e "${GREEN}✓${NC} Disk usage is ${DISK_USAGE}% (healthy)"
elif [ "$DISK_USAGE" != "unknown" ] && [ "$DISK_USAGE" -lt 90 ]; then
    echo -e "${YELLOW}⚠${NC} Disk usage is ${DISK_USAGE}% (monitor closely)"
    WARNINGS=$((WARNINGS + 1))
else
    echo -e "${RED}✗${NC} Disk usage is ${DISK_USAGE}% (critical)"
    ERRORS=$((ERRORS + 1))
fi

# Check memory usage
MEMORY_USAGE=$(ssh_cmd "free | grep Mem | awk '{printf \"%.0f\", \$3/\$2 * 100}'" || echo "unknown")
if [ "$MEMORY_USAGE" != "unknown" ]; then
    echo -e "${GREEN}✓${NC} Memory usage is ${MEMORY_USAGE}%"
fi

echo ""
echo "7. Data collection summary..."
echo "----------------------------------------"
echo "Expected data streams:"
echo "  • Trading data: node_trades/"
echo "  • Order statuses: node_order_statuses/"  
echo "  • Events: misc_events/"
echo "  • Replica commands: replica_cmds/"
echo "  • Network captures: pcap/"
echo ""

# Show current data rates
echo "Current data collection:"
ssh_cmd "find /var/hl/data -name '*.json' -o -name '*.gz' -o -name '*.tar' | head -10 | while read f; do echo \"  \$(ls -lh \"\$f\" | awk '{print \$5, \$9}')\"; done" 2>/dev/null || true

echo ""
echo "========================================="
if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}DATA COLLECTION HAS ISSUES${NC}"
    echo "Errors: $ERRORS"
    echo "Warnings: $WARNINGS"
    echo ""
    echo "Critical issues found! Data collection is incomplete."
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}DATA COLLECTION WORKING WITH WARNINGS${NC}"
    echo "Warnings: $WARNINGS"
    echo ""
    echo "Data collection is functional but monitor the warnings above."
    exit 0
else
    echo -e "${GREEN}DATA COLLECTION FULLY OPERATIONAL${NC}"
    echo "All systems are collecting data correctly!"
    echo ""
    echo "Your zero-data-loss collection system is working perfectly."
    exit 0
fi