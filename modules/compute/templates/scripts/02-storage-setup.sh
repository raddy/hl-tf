#!/bin/bash
# 02-storage-setup.sh - Set up data volume and directory structure

set -euo pipefail

echo "[$(date)] Step 2: Storage setup - mounting data volume..."

# Wait for device to be available
while [ ! -e /dev/nvme1n1 ]; do 
    echo "[$(date)] Waiting for data volume /dev/nvme1n1..."
    sleep 1
done

# Format if needed (will fail if already formatted, which is fine)
mkfs -t xfs /dev/nvme1n1 2>/dev/null || true

# Create mount point
mkdir -p /var/hl

# Mount the volume (check if already mounted)
if ! mountpoint -q /var/hl; then
    mount /dev/nvme1n1 /var/hl
else
    echo "[$(date)] Volume already mounted at /var/hl"
fi

# Add to fstab for persistence (if not already there)
if ! grep -q "/dev/nvme1n1 /var/hl" /etc/fstab; then
    echo "/dev/nvme1n1 /var/hl xfs defaults,nofail 0 2" >> /etc/fstab
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