#!/bin/bash
# 02-storage-setup.sh - Set up data volume and directory structure

set -euo pipefail

# Ensure proper PATH for system utilities
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

echo "[$(date)] Step 2: Storage setup"
echo "[$(date)] PATH is: $PATH"
echo "[$(date)] mkfs.xfs location: $(which mkfs.xfs 2>/dev/null || echo 'not found')"

# Find the data volume device
echo "[$(date)] Looking for data volume device..."
DATA_DEVICE=""
for device in /dev/nvme1n1 /dev/xvdf /dev/sdf; do
    echo "[$(date)] Checking $device..."
    if [ -b "$device" ]; then
        DATA_DEVICE="$device"
        echo "[$(date)] Found block device: $DATA_DEVICE"
        break
    fi
done

# Wait for device with exponential backoff
WAIT=0
MAX_WAIT=300  # 5 minutes
WAIT_INTERVAL=2
while [ -z "$DATA_DEVICE" ] && [ $WAIT -lt $MAX_WAIT ]; do
    echo "[$(date)] Waiting for volume to attach... ($WAIT/${MAX_WAIT}s)"
    sleep $WAIT_INTERVAL
    WAIT=$((WAIT + WAIT_INTERVAL))
    # Increase wait interval up to 10 seconds
    [ $WAIT_INTERVAL -lt 10 ] && WAIT_INTERVAL=$((WAIT_INTERVAL + 1))
    
    for device in /dev/nvme1n1 /dev/xvdf /dev/sdf; do
        if [ -b "$device" ]; then
            DATA_DEVICE="$device"
            echo "[$(date)] Device appeared: $DATA_DEVICE"
            break
        fi
    done
done

[ -z "$DATA_DEVICE" ] && { echo "[$(date)] ERROR: No data volume found"; lsblk; exit 1; }
echo "[$(date)] Found device: $DATA_DEVICE"

# Format if needed
echo "[$(date)] Checking if $DATA_DEVICE needs formatting..."
if ! blkid "$DATA_DEVICE" &>/dev/null; then
    # Ensure xfsprogs is installed
    if ! command -v mkfs.xfs &>/dev/null; then
        echo "[$(date)] mkfs.xfs not found, installing xfsprogs..."
        DEBIAN_FRONTEND=noninteractive apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y xfsprogs || { echo "[$(date)] ERROR: Failed to install xfsprogs"; exit 1; }
    fi
    
    echo "[$(date)] Formatting $DATA_DEVICE with XFS..."
    mkfs.xfs -f "$DATA_DEVICE" || { echo "[$(date)] ERROR: Format failed"; exit 1; }
    sync
    sleep 2  # Give kernel time to update device info
else
    echo "[$(date)] Device already formatted"
fi

# Create mount point
mkdir -p /var/hl

# Mount the volume
if ! mountpoint -q /var/hl; then
    echo "[$(date)] Mounting $DATA_DEVICE to /var/hl..."
    mount "$DATA_DEVICE" /var/hl || { echo "[$(date)] ERROR: Mount failed"; exit 1; }
    
    # Verify mount succeeded
    if ! mountpoint -q /var/hl; then
        echo "[$(date)] ERROR: Mount verification failed"
        exit 1
    fi
else
    echo "[$(date)] /var/hl already mounted"
fi

# Add to fstab
if ! grep -q "/var/hl" /etc/fstab; then
    # Try to get UUID with retries
    UUID=""
    for i in 1 2 3; do
        UUID=$(blkid -o value -s UUID "$DATA_DEVICE" || true)
        [ -n "$UUID" ] && break
        sleep 1
    done
    
    if [ -n "$UUID" ]; then
        echo "UUID=$UUID /var/hl xfs defaults,nofail 0 2" >> /etc/fstab
    else
        echo "$DATA_DEVICE /var/hl xfs defaults,nofail 0 2" >> /etc/fstab
        echo "[$(date)] WARNING: Using device path instead of UUID in fstab"
    fi
fi

echo "[$(date)] Creating directory structure..."
mkdir -p /var/hl/data
mkdir -p /var/hl/pcap
mkdir -p /usr/local/bin

# CRITICAL: hl-visor writes to /root/hl, symlink to data volume
echo "[$(date)] Setting up /root/hl symlink..."
mkdir -p /root
if [ -d /root/hl ] && [ ! -L /root/hl ]; then
    echo "[$(date)] Removing existing /root/hl directory"
    rm -rf /root/hl
fi
if [ ! -L /root/hl ]; then
    echo "[$(date)] Creating symlink /root/hl -> /var/hl"
    ln -s /var/hl /root/hl
fi

echo "[$(date)] ✓ Storage setup completed ($(df -h /var/hl | tail -1 | awk '{print $2}') volume)"