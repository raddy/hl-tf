#!/bin/bash
# 05-start-service.sh - Enable and start the hl-node service

set -euo pipefail

echo "[$(date)] Step 5: Starting hl-node service..."

# Reload systemd
systemctl daemon-reload

# Enable the service
systemctl enable hyperliquid

# Start the service
systemctl start hyperliquid

# Wait for hl-visor to download the hl-node binary
echo "[$(date)] Waiting for hl-visor to initialize and download hl-node binary..."
sleep 20

# Check if service is running
if systemctl is-active --quiet hyperliquid; then
    echo "[$(date)] hyperliquid service is active"
    
    # Check if hl-node binary exists
    if [ -f /usr/local/bin/hl-node ]; then
        echo "[$(date)] hl-node binary found at /usr/local/bin/hl-node"
        ls -la /usr/local/bin/hl-node
    else
        echo "[$(date)] WARNING: hl-node binary not found, checking logs..."
    fi
    
    # Show recent logs
    echo "[$(date)] Recent service logs:"
    journalctl -u hyperliquid -n 20 --no-pager
else
    echo "[$(date)] ERROR: hyperliquid service failed to start"
    journalctl -u hyperliquid -n 50 --no-pager
    exit 1
fi

echo "[$(date)] Service startup completed"