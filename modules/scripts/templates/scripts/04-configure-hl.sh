#!/bin/bash
# 04-configure-hl.sh - Create configuration files

set -euo pipefail

# Ensure proper PATH
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:$PATH"

echo "[$(date)] Step 4: Configuring Hyperliquid"

[ -z "$GOSSIP_CONFIG" ] && { echo "[$(date)] ERROR: GOSSIP_CONFIG not set"; exit 1; }
[ -z "$LOGGING_ARGS" ] && LOGGING_ARGS=""

# Create configurations
echo '{"chain": "Mainnet"}' > /usr/local/bin/visor.json
echo "$GOSSIP_CONFIG" > /var/hl/override_gossip_config.json

# Create systemd service
cat > /etc/systemd/system/hyperliquid.service <<EOF
[Unit]
Description=Hyperliquid Node Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/var/hl
ExecStart=/usr/local/bin/hl-visor run-non-validator $LOGGING_ARGS
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

# Verify files
[ ! -f /usr/local/bin/visor.json ] && { echo "[$(date)] ERROR: visor.json missing"; exit 1; }
[ ! -f /var/hl/override_gossip_config.json ] && { echo "[$(date)] ERROR: gossip config missing"; exit 1; }
[ ! -f /etc/systemd/system/hyperliquid.service ] && { echo "[$(date)] ERROR: service file missing"; exit 1; }

echo "[$(date)] ✓ Configuration completed"