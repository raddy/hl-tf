#!/bin/bash
set -euo pipefail

# Minimal bootstrap script - downloads and executes scripts from S3

LOG_FILE="/var/log/hyperliquid-bootstrap.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "[$(date)] Starting Hyperliquid node bootstrap..."

# Configuration from Terraform
SCRIPTS_BUCKET="${scripts_bucket}"
SCRIPTS_VERSION="${scripts_version}"
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Install AWS CLI if not present
if ! command -v aws &> /dev/null; then
    echo "[$(date)] Installing AWS CLI..."
    snap install aws-cli --classic
    export PATH=$PATH:/snap/bin
fi

# Create working directory
WORK_DIR="/var/lib/cloud/instance/scripts"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Download scripts with retry
echo "[$(date)] Downloading scripts from s3://$SCRIPTS_BUCKET/scripts/$SCRIPTS_VERSION/"
for attempt in 1 2 3; do
    if aws s3 cp "s3://$SCRIPTS_BUCKET/scripts/$SCRIPTS_VERSION/" . --recursive --region ${aws_region}; then
        echo "[$(date)] Scripts downloaded successfully"
        break
    else
        echo "[$(date)] Download attempt $attempt failed, retrying..."
        sleep 5
    fi
    if [ $attempt -eq 3 ]; then
        echo "[$(date)] ERROR: Failed to download scripts after 3 attempts"
        exit 1
    fi
done

# Download config files
echo "[$(date)] Downloading config files..."
aws s3 cp "s3://$SCRIPTS_BUCKET/config/" . --recursive --region ${aws_region} || echo "[$(date)] WARNING: Config download failed"

# Verify manifest
if [ -f manifest.json ]; then
    echo "[$(date)] Verifying script integrity..."
    while IFS= read -r script; do
        if [ -f "$script" ]; then
            expected_hash=$(jq -r ".scripts[\"$script\"].sha256" manifest.json 2>/dev/null || echo "")
            if [ -z "$expected_hash" ] || [ "$expected_hash" = "null" ]; then
                echo "[$(date)] WARNING: No hash found for $script in manifest"
                continue
            fi
            actual_hash=$(sha256sum "$script" | cut -d' ' -f1)
            if [ "$expected_hash" != "$actual_hash" ]; then
                echo "[$(date)] ERROR: Hash mismatch for $script"
                echo "[$(date)] Expected: $expected_hash"
                echo "[$(date)] Actual: $actual_hash"
                exit 1
            fi
        fi
    done < <(jq -r '.scripts | keys[]' manifest.json 2>/dev/null || find . -name "*.sh" -type f -printf "%f\n")
    echo "[$(date)] All scripts verified successfully"
else
    echo "[$(date)] WARNING: No manifest.json found, skipping integrity verification"
fi

# Make scripts executable
chmod +x *.sh

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
        echo "[$(date)] Executing $script..."
        if ! bash "$script"; then
            echo "[$(date)] ERROR: $script failed with exit code $?"
            
            if [ "${debug_mode}" != "true" ]; then
                echo "[$(date)] Shutting down instance due to setup failure..."
                shutdown -h +1
            fi
            exit 1
        fi
    fi
done

echo "[$(date)] Bootstrap completed successfully!"

# Create update script
cat > /usr/local/bin/hl-update <<'EOF'
#!/bin/bash
set -euo pipefail

VERSION=$${1:-latest}
BUCKET=$$(aws s3 ls | grep hyperliquid-scripts | awk '{print $$3}')

echo "Updating Hyperliquid scripts to version: $$VERSION"

# Stop service
systemctl stop hyperliquid

# Backup current scripts
cp -r /var/lib/cloud/instance/scripts /var/lib/cloud/instance/scripts.backup

# Download new scripts
aws s3 cp "s3://$$BUCKET/scripts/$$VERSION/" /var/lib/cloud/instance/scripts/ --recursive

# Restart service
systemctl start hyperliquid

echo "Update complete!"
EOF

chmod +x /usr/local/bin/hl-update

echo "[$(date)] Node setup complete. Hyperliquid service should be running."