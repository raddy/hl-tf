#!/bin/bash
set -euo pipefail

# Minimal bootstrap script - downloads and executes scripts from S3

LOG_FILE="/var/log/hyperliquid-bootstrap.log"

# Simple logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting Hyperliquid node bootstrap..."
log "Running as part of cloud-init..."

# ────────────────────────────────────────────────────────────
# PATH — snap binaries live in /snap/bin
# ────────────────────────────────────────────────────────────
export PATH="/snap/bin:/usr/local/bin:/usr/bin"

# ────────────────────────────────────────────────────────────
# Install AWS CLI v2 via snap (idempotent)
# ────────────────────────────────────────────────────────────
log "snap install aws-cli --classic"
snap install aws-cli --classic

# verify
if command -v aws &> /dev/null; then
    log "AWS CLI installed successfully at $(which aws)"
else
    log "ERROR: AWS CLI installation failed"
    exit 1
fi

# Configuration from Terraform
SCRIPTS_BUCKET="${scripts_bucket}"
SCRIPTS_VERSION="${scripts_version}"

# Get instance ID (optional, don't fail if not available)
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")

log "Config: bucket=$SCRIPTS_BUCKET version=$SCRIPTS_VERSION instance=$INSTANCE_ID"

# Re-check AWS CLI after installation attempt
if ! command -v aws &> /dev/null; then
    log "ERROR: AWS CLI installation failed"
    exit 1
fi

log "AWS CLI: $(which aws)"

# Create working directory
WORK_DIR="/var/lib/cloud/instance/scripts"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
log "Working directory: $(pwd)"

# Download scripts with retry and timeout
log "Downloading scripts from s3://$SCRIPTS_BUCKET/scripts/$SCRIPTS_VERSION/"
for attempt in 1 2 3; do
    if timeout 300 aws s3 cp "s3://$SCRIPTS_BUCKET/scripts/$SCRIPTS_VERSION/" . --recursive --region ${aws_region}; then
        log "Scripts downloaded successfully"
        break
    else
        log "Download attempt $attempt failed, retrying..."
        sleep $((5 * attempt * attempt))
    fi
    if [ $attempt -eq 3 ]; then
        log "ERROR: Failed to download scripts after 3 attempts"
        exit 1
    fi
done

# Download config files with timeout
log "Downloading config files..."
timeout 120 aws s3 cp "s3://$SCRIPTS_BUCKET/config/" . --recursive --region ${aws_region} 2>/dev/null || true

# Make scripts executable
chmod +x *.sh 2>/dev/null || true

# Create logging arguments based on configuration
LOGGING_ARGS=""
if [ "${write_trades}" = "true" ]; then
  LOGGING_ARGS="$LOGGING_ARGS --write-trades"
fi
if [ "${write_events}" = "true" ]; then
  LOGGING_ARGS="$LOGGING_ARGS --write-misc-events"
fi
if [ "${write_order_statuses}" = "true" ]; then
  LOGGING_ARGS="$LOGGING_ARGS --write-order-statuses"
fi

# Create environment file
cat > env.sh <<EOF
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:\$PATH"
export EBS_VOLUME_SIZE="${ebs_volume_size}"
export WRITE_TRADES="${write_trades}"
export WRITE_EVENTS="${write_events}"
export WRITE_ORDER_STATUSES="${write_order_statuses}"
export ENABLE_TCPDUMP="${enable_tcpdump}"
export DEBUG_MODE="${debug_mode}"
export GOSSIP_CONFIG='${gossip_config}'
export LOGGING_ARGS="$LOGGING_ARGS"
EOF

# Execute scripts in order
for script in 01-*.sh 02-*.sh 03-*.sh 04-*.sh 05-*.sh 06-*.sh 07-*.sh; do
    if [ -f "$script" ]; then
        log "=== Executing $script ==="
        # Add script timeout to prevent hanging
        timeout 600 bash -c "set -a; source env.sh; set +a; bash -x '$script'"
        EXIT_CODE=$?
        if [ $EXIT_CODE -ne 0 ]; then
            log "ERROR: $script failed with exit code $EXIT_CODE"
            if [ "${debug_mode}" != "true" ]; then
                log "Debug mode disabled, shutting down in 1 minute"
                shutdown -h +1
            fi
            exit 1
        fi
    fi
done

log "Bootstrap completed successfully!"

# Create update script
cat > /usr/local/bin/hl-update <<'EOF'
#!/bin/bash
set -euo pipefail

VERSION=$${1:-latest}
BUCKET=$(aws s3 ls | grep hyperliquid-scripts | awk '{print $3}')

echo "Updating Hyperliquid scripts to version: $VERSION"

# Stop service
systemctl stop hyperliquid

# Backup current scripts
cp -r /var/lib/cloud/instance/scripts /var/lib/cloud/instance/scripts.backup

# Download new scripts
aws s3 cp "s3://$BUCKET/scripts/$VERSION/" /var/lib/cloud/instance/scripts/ --recursive

# Restart service
systemctl start hyperliquid

echo "Update complete!"
EOF

chmod +x /usr/local/bin/hl-update

log "Node setup complete. Hyperliquid service should be running."