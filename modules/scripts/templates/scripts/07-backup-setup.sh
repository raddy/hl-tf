#!/bin/bash
# 07-backup-setup.sh - Set up zero data loss backup system

set -euo pipefail

echo "[$(date)] Step 7: Backup setup"

# Get backup bucket from environment or create default
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BACKUP_BUCKET="hyperliquid-backup-${ACCOUNT_ID}"

echo "[$(date)] Setting up backup to s3://$BACKUP_BUCKET"

# Copy backup scripts to system locations
cp /var/lib/cloud/instance/scripts/hl-backup.sh /usr/local/bin/hl-backup
chmod +x /usr/local/bin/hl-backup

cp /var/lib/cloud/instance/scripts/hl-backup-sweep.sh /usr/local/bin/hl-backup-sweep
chmod +x /usr/local/bin/hl-backup-sweep

# Create backup service
cat > /etc/systemd/system/hl-backup.service <<EOFSERVICE
[Unit]
Description=Hyperliquid Zero Data Loss Backup Service
After=network.target hyperliquid.service

[Service]
Type=simple
ExecStart=/usr/local/bin/hl-backup ${BACKUP_BUCKET}
Restart=always
RestartSec=30
User=root
Environment="PATH=/snap/bin:/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Start backup service
systemctl daemon-reload
systemctl enable hl-backup
systemctl start hl-backup

# Create backup sweep timer for catching missed files
echo "[$(date)] Setting up backup sweep schedule..."

# Create timer unit for backup sweep (runs every 4 hours)
cat > /etc/systemd/system/hl-backup-sweep.timer <<'EOFTIMER'
[Unit]
Description=Run backup sweep every 4 hours
Requires=hl-backup-sweep.service

[Timer]
OnBootSec=30min
OnUnitActiveSec=4h
Persistent=true

[Install]
WantedBy=timers.target
EOFTIMER

# Create one-shot service for backup sweep
cat > /etc/systemd/system/hl-backup-sweep.service <<EOFSWEEP
[Unit]
Description=Hyperliquid Backup Sweep - Catch missed files
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hl-backup-sweep ${BACKUP_BUCKET}
User=root
Environment="PATH=/snap/bin:/usr/local/bin:/usr/bin:/bin"

# Longer timeout for large file processing
TimeoutStartSec=6h
EOFSWEEP

# Enable and start the timer
systemctl daemon-reload
systemctl enable hl-backup-sweep.timer
systemctl start hl-backup-sweep.timer

# Also create a cron job as backup (in case systemd timer fails)
cat > /etc/cron.d/hl-backup-sweep <<EOFCRON
# Run backup sweep every 4 hours to catch any missed files
0 */4 * * * root /usr/local/bin/hl-backup-sweep ${BACKUP_BUCKET} >> /var/log/hl-backup-sweep-cron.log 2>&1
EOFCRON

echo "[$(date)] ✓ Backup configured (bucket: s3://$BACKUP_BUCKET)"
echo "[$(date)] ✓ Backup sweep scheduled (every 4 hours)"