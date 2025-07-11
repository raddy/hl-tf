#!/bin/bash
# Wrapper script for tcpdump with manual rotation

set -euo pipefail

cd /var/hl/pcap || exit 1

# Clean up any incomplete pcap files from previous runs
rm -f capture-*.pcap.tmp 2>/dev/null || true

# Detect primary network interface
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
[ -z "$INTERFACE" ] && INTERFACE="eth0"  # fallback

echo "[$(date)] Starting tcpdump on interface $INTERFACE"

# Function to rotate capture files
rotate_capture() {
    while true; do
        # Generate filename with current timestamp
        FILENAME="capture-$(date +%Y%m%d-%H%M%S).pcap"
        echo "[$(date)] Starting new capture: $FILENAME"
        
        # Run tcpdump for 15 minutes (900 seconds) to keep file sizes manageable
        timeout 900 /usr/bin/tcpdump -i "$INTERFACE" \
            -w "$FILENAME" \
            -B 10240 \
            -s 0 \
            not host 169.254.169.254 2>&1 || true
        
        echo "[$(date)] Rotation completed for $FILENAME"
        
        # Small delay to prevent rapid restarts
        sleep 1
    done
}

# Start the rotation function
rotate_capture