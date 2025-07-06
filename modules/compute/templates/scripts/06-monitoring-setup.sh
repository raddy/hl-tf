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
cd /var/hl/pcap
exec /usr/bin/tcpdump -i any -w "capture-$(date +%Y%m%d-%H%M%S).pcap" -G 3600
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
    
    # Enable and start tcpdump
    systemctl daemon-reload
    systemctl enable hl-tcpdump
    systemctl start hl-tcpdump
    
    if systemctl is-active --quiet hl-tcpdump; then
        echo "[$(date)] tcpdump service started successfully"
    else
        echo "[$(date)] WARNING: tcpdump service failed to start"
        journalctl -u hl-tcpdump -n 20 --no-pager
    fi
else
    echo "[$(date)] tcpdump capture disabled"
fi

echo "[$(date)] Monitoring setup completed"