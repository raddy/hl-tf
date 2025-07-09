#!/bin/bash
# 02-storage-setup.sh - Set up data volume and directory structure

set -euo pipefail

echo "[$(date)] Step 2: Storage setup - mounting data volume..."

# Find the data volume device
echo "[$(date)] Looking for data volume..."
DATA_DEVICE=""
for device in /dev/nvme1n1 /dev/xvdf /dev/sdf; do
    if [ -b "$device" ]; then
        DATA_DEVICE="$device"
        echo "[$(date)] Found data device: $DATA_DEVICE"
        break
    fi
done

# Wait if no device found yet
while [ -z "$DATA_DEVICE" ]; do
    echo "[$(date)] Waiting for data volume to attach..."
    sleep 2
    for device in /dev/nvme1n1 /dev/xvdf /dev/sdf; do
        if [ -b "$device" ]; then
            DATA_DEVICE="$device"
            echo "[$(date)] Found data device: $DATA_DEVICE"
            break
        fi
    done
done

# Format if needed (will fail if already formatted, which is fine)
mkfs -t xfs "$DATA_DEVICE" 2>/dev/null || true

# Create mount point
mkdir -p /var/hl

# Mount the volume (check if already mounted)
if ! mountpoint -q /var/hl; then
    mount "$DATA_DEVICE" /var/hl
else
    echo "[$(date)] Volume already mounted at /var/hl"
fi

# Add to fstab for persistence (if not already there)
if ! grep -q "$DATA_DEVICE /var/hl" /etc/fstab; then
    echo "$DATA_DEVICE /var/hl xfs defaults,nofail 0 2" >> /etc/fstab
fi

echo "[$(date)] Creating directory structure..."
mkdir -p /var/hl/data
mkdir -p /var/hl/pcap
mkdir -p /usr/local/bin

# CRITICAL FIX: hl-visor writes to /root/hl, so symlink it to our data volume
mkdir -p /root
if [ ! -L /root/hl ]; then
    ln -s /var/hl /root/hl
fi

echo "[$(date)] Storage setup completed"
echo "[$(date)] Data volume mounted at /var/hl"
df -h /var/hl