#!/bin/bash
# 01-system-setup.sh - Update system and install required packages

set -euo pipefail

# Ensure proper PATH
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:$PATH"

echo "[$(date)] Step 1: System setup"

# Wait for apt locks to be released
echo "[$(date)] Waiting for apt locks..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo "[$(date)] Apt is locked, waiting..."
    sleep 2
done

# Update system
echo "[$(date)] Running apt-get update..."
DEBIAN_FRONTEND=noninteractive apt-get update || { echo "[$(date)] ERROR: apt-get update failed"; exit 1; }

echo "[$(date)] Running apt-get upgrade..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y || { echo "[$(date)] ERROR: apt-get upgrade failed"; exit 1; }

# Install required packages
echo "[$(date)] Installing required packages..."
PACKAGES="curl jq tcpdump gnupg lsb-release ca-certificates logrotate unzip xfsprogs"
DEBIAN_FRONTEND=noninteractive apt-get install -y $PACKAGES || { echo "[$(date)] ERROR: Package installation failed"; exit 1; }

# Install AWS CLI via snap
echo "[$(date)] Installing AWS CLI..."
if ! command -v aws &> /dev/null; then
    # Ensure snapd is ready
    if systemctl is-active --quiet snapd.socket; then
        echo "[$(date)] Snapd is ready"
    else
        echo "[$(date)] Starting snapd..."
        systemctl start snapd.socket
        sleep 5
    fi
    
    snap install aws-cli --classic
    # Create symlink for aws command if needed
    if [ -f /snap/bin/aws ]; then
        ln -sf /snap/bin/aws /usr/local/bin/aws
    fi
    echo "[$(date)] AWS CLI installed at $(which aws)"
else
    echo "[$(date)] AWS CLI already installed at $(which aws)"
fi

# Verify critical commands
echo "[$(date)] Verifying installed commands..."
for cmd in curl jq tcpdump gpg aws; do
    if command -v $cmd &> /dev/null; then
        echo "[$(date)] ✓ $cmd found at $(which $cmd)"
    else
        echo "[$(date)] ERROR: $cmd not found"
        exit 1
    fi
done

echo "[$(date)] ✓ System setup completed"