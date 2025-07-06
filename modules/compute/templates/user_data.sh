#!/bin/bash
# Main user data script that orchestrates the setup

set -euo pipefail

# Log all output
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

echo "[$(date)] Starting Hyperliquid node setup..."

# Export variables for scripts to use
export GOSSIP_CONFIG='${gossip_config_json}'
export ENABLE_TCPDUMP='${enable_tcpdump}'
export WRITE_TRADES='${write_trades}'
export WRITE_ORDER_STATUSES='${write_order_statuses}'
export WRITE_EVENTS='${write_events}'
export DEBUG_MODE='${debug_mode}'

# Build logging args
LOGGING_ARGS=""
if [ "$WRITE_TRADES" = "true" ]; then
    LOGGING_ARGS="$LOGGING_ARGS --write-trades"
fi
if [ "$WRITE_ORDER_STATUSES" = "true" ]; then
    LOGGING_ARGS="$LOGGING_ARGS --write-order-statuses"
fi
if [ "$WRITE_EVENTS" = "true" ]; then
    LOGGING_ARGS="$LOGGING_ARGS --write-misc-events"
fi
export LOGGING_ARGS

# Execute each script in order
SCRIPTS=(
    "01-system-setup.sh"
    "02-storage-setup.sh"
    "03-install-hl.sh"
    "04-configure-hl.sh"
    "05-start-service.sh"
    "06-monitoring-setup.sh"
)

# Write environment variables to a file that scripts can source
cat > /var/lib/cloud/instance/scripts/env.sh <<EOF
export GOSSIP_CONFIG='${gossip_config_json}'
export ENABLE_TCPDUMP='${enable_tcpdump}'
export WRITE_TRADES='${write_trades}'
export WRITE_ORDER_STATUSES='${write_order_statuses}'
export WRITE_EVENTS='${write_events}'
export DEBUG_MODE='${debug_mode}'
export LOGGING_ARGS="$LOGGING_ARGS"
EOF

for script in "$${SCRIPTS[@]}"; do
    echo "[$(date)] Running $script..."
    
    # Run the script with environment
    if ! bash -c "source /var/lib/cloud/instance/scripts/env.sh && bash /var/lib/cloud/instance/scripts/$script"; then
        echo "[$(date)] ERROR: $script failed!"
        echo "[$(date)] Deployment failed. Check /var/log/user-data.log for details."
        
        if [ "$DEBUG_MODE" = "true" ]; then
            echo "[$(date)] ERROR: Deployment failed but keeping instance running for debugging"
            echo "[$(date)] SSH in to debug: check /var/log/user-data.log"
        else
            echo "[$(date)] ERROR: Deployment failed. Shutting down instance."
            shutdown -h now
        fi
        exit 1
    fi
    
    echo "[$(date)] $script completed successfully"
done

echo "[$(date)] Hyperliquid node setup completed successfully!"
echo "[$(date)] Check status with: sudo systemctl status hyperliquid"
echo "[$(date)] View logs with: sudo journalctl -u hyperliquid -f"