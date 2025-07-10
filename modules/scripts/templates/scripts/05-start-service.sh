#!/bin/bash
# 05-start-service.sh - Enable and start the hl-node service

set -euo pipefail

# Ensure proper PATH
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:$PATH"

echo "[$(date)] Step 5: Starting service"

systemctl daemon-reload || exit 1
systemctl enable hyperliquid || exit 1
systemctl start hyperliquid || { journalctl -u hyperliquid -n 50 --no-pager; exit 1; }

# Wait for hl-node download with timeout
echo "[$(date)] Waiting for hl-node download..."
MAX_WAIT=300  # 5 minutes
WAIT=0
while [ $WAIT -lt $MAX_WAIT ]; do
    if [ -f /usr/local/bin/hl-node ]; then
        echo "[$(date)] hl-node downloaded successfully"
        break
    fi
    echo "[$(date)] Still waiting for hl-node... ($WAIT/${MAX_WAIT}s)"
    sleep 10
    WAIT=$((WAIT + 10))
done

if [ ! -f /usr/local/bin/hl-node ]; then
    echo "[$(date)] ERROR: hl-node download timeout after ${MAX_WAIT}s"
    exit 1
fi

# Verify service is active
if ! systemctl is-active --quiet hyperliquid; then
    echo "[$(date)] ERROR: Service not active"
    journalctl -u hyperliquid -n 100 --no-pager
    exit 1
fi

# Verify processes are actually running
echo "[$(date)] Verifying processes..."
for i in 1 2 3; do
    if pgrep -f "hl-visor" > /dev/null && pgrep -f "hl-node" > /dev/null; then
        echo "[$(date)] ✓ Both hl-visor and hl-node processes detected"
        break
    fi
    echo "[$(date)] Waiting for processes to start (attempt $i/3)..."
    sleep 5
done

if ! pgrep -f "hl-visor" > /dev/null; then
    echo "[$(date)] ERROR: hl-visor process not found"
    ps aux | grep hl
    exit 1
fi

[ -f /usr/local/bin/hl-node ] && echo "[$(date)] ✓ hl-node downloaded"
pgrep -f "hl-visor|hl-node" > /dev/null && echo "[$(date)] ✓ Processes running"

# Final health check - ensure service stays running
echo "[$(date)] Performing final health check..."
for i in 1 2 3; do
    sleep 10
    if ! systemctl is-active --quiet hyperliquid; then
        echo "[$(date)] ERROR: Service stopped after $((i * 10)) seconds"
        journalctl -u hyperliquid -n 50 --no-pager
        exit 1
    fi
    echo "[$(date)] Service still running after $((i * 10)) seconds"
done

# Check if data is being written
if [ -d /var/hl/data ]; then
    echo "[$(date)] Checking for data generation..."
    sleep 10
    if find /var/hl/data -type f -mmin -1 | grep -q .; then
        echo "[$(date)] ✓ Data files are being generated"
    else
        echo "[$(date)] WARNING: No recent data files found"
    fi
fi

echo "[$(date)] ✓ Service started successfully"