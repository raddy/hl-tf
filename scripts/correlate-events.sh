#!/bin/bash
# Script to help correlate pcap captures with Hyperliquid events
# This downloads and aligns pcaps with trading events for analysis

set -euo pipefail

# Configuration
if [ $# -lt 3 ]; then
    echo "Usage: $0 <backup-bucket> <date> <hour>"
    echo "Example: $0 hl-node-backup-123456789012 20250107 14"
    exit 1
fi

BACKUP_BUCKET=$1
DATE=$2
HOUR=$3
NODE_ID=${4:-$(hostname)}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Downloading correlated data for analysis...${NC}"
echo "Date: $DATE, Hour: $HOUR"

# Create working directory
WORK_DIR="./hl-analysis/${DATE}/${HOUR}"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Download pcaps for the hour (10-minute rotation files)
echo -e "\n${YELLOW}Downloading pcap captures for hour ${HOUR}...${NC}"
PCAP_PREFIX="${NODE_ID}/pcaps/${DATE}"
# Match all captures for the requested hour (capture_YYYYMMDD-HHMMSS format)
aws s3 ls "s3://${BACKUP_BUCKET}/${PCAP_PREFIX}/" | grep -E "capture_${DATE}-${HOUR}[0-5][0-9][0-5][0-9]\.pcap\.gz" | while read -r line; do
    file=$(echo $line | awk '{print $4}')
    echo "  Downloading $file..."
    aws s3 cp "s3://${BACKUP_BUCKET}/${PCAP_PREFIX}/$file" .
    gunzip -f "$file"
done

# List downloaded pcaps
echo -e "\n  Downloaded pcaps:"
ls -la capture_*.pcap 2>/dev/null || echo "  No pcaps found for hour ${HOUR}"

# Download corresponding trade data
echo -e "\n${YELLOW}Downloading trade data...${NC}"
TRADES_FILE="${NODE_ID}/node_trades/${DATE}/${DATE}_${HOUR}.gz"
if aws s3 cp "s3://${BACKUP_BUCKET}/${TRADES_FILE}" . 2>/dev/null; then
    gunzip -f "${DATE}_${HOUR}.gz"
    echo "  ✓ Trade data downloaded"
else
    echo "  - No trade data for this hour"
fi

# Download order status data
echo -e "\n${YELLOW}Downloading order status data...${NC}"
ORDERS_FILE="${NODE_ID}/node_order_statuses/${DATE}/${DATE}_${HOUR}.gz"
if aws s3 cp "s3://${BACKUP_BUCKET}/${ORDERS_FILE}" . 2>/dev/null; then
    gunzip -f "${DATE}_${HOUR}.gz"
    mv "${DATE}_${HOUR}" "order_statuses_${DATE}_${HOUR}"
    echo "  ✓ Order status data downloaded"
else
    echo "  - No order status data for this hour"
fi

# Download misc events
echo -e "\n${YELLOW}Downloading misc events...${NC}"
EVENTS_FILE="${NODE_ID}/misc_events/${DATE}/${DATE}_${HOUR}.gz"
if aws s3 cp "s3://${BACKUP_BUCKET}/${EVENTS_FILE}" . 2>/dev/null; then
    gunzip -f "${DATE}_${HOUR}.gz"
    mv "${DATE}_${HOUR}" "misc_events_${DATE}_${HOUR}"
    echo "  ✓ Misc events downloaded"
else
    echo "  - No misc events for this hour"
fi

echo -e "\n${GREEN}Data ready for analysis in: $(pwd)${NC}"
echo -e "\n${YELLOW}Analysis suggestions:${NC}"
echo "1. View pcap with timestamps (multiple 10-min rotation files):"
echo "   for f in capture_*.pcap; do echo \"=== \$f ===\"; tcpdump -tttt -r \$f | head -20; done"
echo ""
echo "2. Merge all pcaps for the hour:"
echo "   mergecap -w hour${HOUR}_merged.pcap capture_*.pcap"
echo ""
echo "3. Extract Hyperliquid traffic (ports 4000-4010):"
echo "   for f in capture_*.pcap; do tcpdump -r \$f 'port >= 4000 and port <= 4010' -w hl_\$f; done"
echo ""
echo "4. Correlate events with network traffic:"
echo "   # Trade events in ${DATE}_${HOUR} can be matched with packet timestamps"
echo "   # Each pcap file covers ~10 minutes of network activity"
echo ""
echo "5. Convert pcaps to CSV for analysis:"
echo "   for f in capture_*.pcap; do tshark -r \$f -T fields -e frame.time -e ip.src -e ip.dst -e tcp.port > \${f%.pcap}.csv; done"