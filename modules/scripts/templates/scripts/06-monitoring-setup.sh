#!/bin/bash
# 06-monitoring-setup.sh - Set up monitoring and tcpdump if enabled

set -euo pipefail

# Ensure proper PATH
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:$PATH"

echo "[$(date)] Step 6: Monitoring setup"

[ -z "$ENABLE_TCPDUMP" ] && ENABLE_TCPDUMP="false"

# Log rotation
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
    
    # Copy tcpdump wrapper script from downloaded scripts
    if [ -f /var/lib/cloud/instance/scripts/tcpdump-wrapper.sh ]; then
        cp /var/lib/cloud/instance/scripts/tcpdump-wrapper.sh /usr/local/bin/
        chmod +x /usr/local/bin/tcpdump-wrapper.sh
    else
        echo "[$(date)] ERROR: tcpdump-wrapper.sh not found in scripts directory"
        exit 1
    fi
    
    # Create tcpdump service
    cat > /etc/systemd/system/hl-tcpdump.service <<'EOF'
[Unit]
Description=Hyperliquid tcpdump capture
After=network.target

[Service]
Type=simple
User=root
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
    systemctl daemon-reload || exit 1
    systemctl enable hl-tcpdump || exit 1
    systemctl start hl-tcpdump || { journalctl -u hl-tcpdump -n 20 --no-pager; exit 1; }
    sleep 3
    
    if systemctl is-active --quiet hl-tcpdump; then
        echo "[$(date)] tcpdump service started successfully"
        
        echo "[$(date)] ✓ tcpdump service started"
        /usr/local/bin/check-pcap-rotation
    else
        echo "[$(date)] WARNING: tcpdump service failed to start"
        journalctl -u hl-tcpdump -n 20 --no-pager
    fi
else
    echo "[$(date)] tcpdump disabled"
fi

# Set up monitoring helper script
echo "[$(date)] Creating monitoring helper script..."
cat > /usr/local/bin/hl-monitor <<'EOF'
#!/bin/bash
# Quick monitoring script for Hyperliquid node

echo "=== Hyperliquid Node Status ==="
echo "Time: $(date)"
echo ""

echo "Service Status:"
systemctl is-active hyperliquid && echo "✓ hyperliquid: active" || echo "✗ hyperliquid: inactive"
[ -f /etc/systemd/system/hl-tcpdump.service ] && (systemctl is-active hl-tcpdump && echo "✓ hl-tcpdump: active" || echo "✗ hl-tcpdump: inactive")
[ -f /etc/systemd/system/hl-backup.service ] && (systemctl is-active hl-backup && echo "✓ hl-backup: active" || echo "✗ hl-backup: inactive")

echo ""
echo "Data Volume Usage:"
df -h /var/hl

echo ""
echo "Data Directory:"
if [ -d /var/hl/data ]; then
    echo "Recent activity:"
    find /var/hl/data -type f -mmin -60 -name "*" 2>/dev/null | head -10
    echo ""
    echo "Data size by type:"
    du -sh /var/hl/data/* 2>/dev/null | head -10
else
    echo "No data directory found yet"
fi

if [ -d /var/hl/pcap ]; then
    echo ""
    echo "PCAP Status:"
    ls -lh /var/hl/pcap/*.pcap 2>/dev/null | tail -5 || echo "No pcap files yet"
fi

echo ""
echo "Recent Logs (last 10 lines):"
journalctl -u hyperliquid -n 10 --no-pager
EOF

chmod +x /usr/local/bin/hl-monitor
echo "[$(date)] Monitoring helper created at /usr/local/bin/hl-monitor"

echo "[$(date)] ✓ Monitoring configured (hl-monitor for status)"