#!/bin/bash
# 06-monitoring-setup.sh - Set up monitoring and tcpdump if enabled

set -euo pipefail

echo "[$(date)] Step 6: Setting up monitoring..."

# Set up log rotation for hyperliquid
cat > /etc/logrotate.d/hyperliquid <<'EOF'
/var/hl/data/**/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOF

# Set up tcpdump if enabled
if [ "$ENABLE_TCPDUMP" = "true" ]; then
    echo "[$(date)] Setting up continuous tcpdump capture..."
    
    # Create pcap directory
    mkdir -p /var/hl/pcap
    
    # Create tcpdump wrapper script
    cat > /usr/local/bin/tcpdump-wrapper.sh <<'EOF'
#!/bin/bash
# Wrapper script for tcpdump with proper rotation

cd /var/hl/pcap || exit 1

# Clean up any incomplete pcap files from previous runs
rm -f capture-*.pcap.tmp 2>/dev/null

# Start tcpdump with rotation
# -G 3600: rotate every hour (3600 seconds)
# -w capture-%Y%m%d-%H%M%S.pcap: filename with strftime format
# -z gzip: compress completed files (optional, remove if you want uncompressed)
# Note: %s in filename is required for -G to work properly
exec /usr/bin/tcpdump -i any \
    -w 'capture-%Y%m%d-%H%M%S.pcap' \
    -G 3600 \
    -Z root
EOF
    chmod +x /usr/local/bin/tcpdump-wrapper.sh
    
    # Create tcpdump service
    cat > /etc/systemd/system/hl-tcpdump.service <<'EOF'
[Unit]
Description=Hyperliquid tcpdump capture
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/tcpdump-wrapper.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Set up pcap rotation (keep 7 days)
    cat > /etc/cron.daily/rotate-pcaps <<'EOF'
#!/bin/bash
# Delete pcap files older than 7 days
find /var/hl/pcap -name "*.pcap" -mtime +7 -delete
EOF
    chmod +x /etc/cron.daily/rotate-pcaps
    
    # Create pcap monitoring script
    cat > /usr/local/bin/check-pcap-rotation <<'EOF'
#!/bin/bash
# Check if pcap rotation is working properly

PCAP_DIR="/var/hl/pcap"
CURRENT_HOUR=$(date +%H)

echo "=== PCAP Rotation Status ==="
echo "Current time: $(date)"
echo ""

# Check if tcpdump is running
if systemctl is-active --quiet hl-tcpdump; then
    echo "✓ tcpdump service is running"
    
    # Get tcpdump process info
    TCPDUMP_PID=$(systemctl show -p MainPID hl-tcpdump | cut -d= -f2)
    if [ "$TCPDUMP_PID" != "0" ]; then
        echo "  PID: $TCPDUMP_PID"
        echo "  Process: $(ps -p $TCPDUMP_PID -o args= 2>/dev/null || echo "not found")"
    fi
else
    echo "✗ tcpdump service is NOT running"
fi

echo ""
echo "PCAP files in $PCAP_DIR:"
ls -lh $PCAP_DIR/*.pcap 2>/dev/null | tail -10 || echo "No pcap files found"

echo ""
echo "Disk usage:"
df -h $PCAP_DIR

# Check if current hour file is being written
CURRENT_FILE=$(ls -lt $PCAP_DIR/*.pcap 2>/dev/null | head -1 | awk '{print $NF}')
if [ -n "$CURRENT_FILE" ]; then
    echo ""
    echo "Currently writing to: $(basename $CURRENT_FILE)"
    echo "Size: $(ls -lh $CURRENT_FILE | awk '{print $5}')"
    echo "Last modified: $(stat -c %y $CURRENT_FILE)"
fi
EOF
    chmod +x /usr/local/bin/check-pcap-rotation

    # Enable and start tcpdump
    systemctl daemon-reload
    systemctl enable hl-tcpdump
    systemctl start hl-tcpdump
    
    # Wait a moment for service to start
    sleep 2
    
    if systemctl is-active --quiet hl-tcpdump; then
        echo "[$(date)] tcpdump service started successfully"
        
        # Run initial check
        echo "[$(date)] Initial pcap rotation check:"
        /usr/local/bin/check-pcap-rotation
    else
        echo "[$(date)] WARNING: tcpdump service failed to start"
        journalctl -u hl-tcpdump -n 20 --no-pager
    fi
else
    echo "[$(date)] tcpdump capture disabled"
fi

echo "[$(date)] Monitoring setup completed"