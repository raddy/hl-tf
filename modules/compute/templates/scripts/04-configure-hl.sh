#!/bin/bash
# 04-configure-hl.sh - Create configuration files

set -euo pipefail

echo "[$(date)] Step 4: Configuring Hyperliquid node..."

# Create visor configuration
echo "[$(date)] Creating visor configuration..."
echo '{"chain": "Mainnet"}' > /usr/local/bin/visor.json

# Create gossip configuration
echo "[$(date)] Creating gossip configuration..."
echo "$GOSSIP_CONFIG" > /var/hl/override_gossip_config.json

# Create systemd service
echo "[$(date)] Creating systemd service..."
cat > /etc/systemd/system/hyperliquid.service <<EOF
[Unit]
Description=Hyperliquid Node Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/var/hl
ExecStart=/usr/local/bin/hl-visor run-non-validator${LOGGING_ARGS}
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=hyperliquid

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

# Environment
Environment="RUST_BACKTRACE=1"

[Install]
WantedBy=multi-user.target
EOF

echo "[$(date)] Configuration completed"