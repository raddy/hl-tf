#!/bin/bash
# 03-install-hl.sh - Download and verify hl-visor binary

set -euo pipefail

# Ensure proper PATH
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:$PATH"

echo "[$(date)] Step 3: Installing hl-visor"
cd /usr/local/bin

# Download hl-visor if needed
if [ ! -f hl-visor ]; then
    echo "[$(date)] Downloading hl-visor binary..."
    for i in 1 2 3; do
        if timeout 120 curl -L -o hl-visor https://binaries.hyperliquid.xyz/Mainnet/hl-visor; then
            # Verify file size (should be > 1MB)
            SIZE=$(stat -c%s hl-visor 2>/dev/null || echo 0)
            if [ $SIZE -gt 1000000 ]; then
                echo "[$(date)] Download successful (size: $((SIZE/1024/1024))MB)"
                break
            else
                echo "[$(date)] ERROR: Downloaded file too small ($SIZE bytes)"
                rm -f hl-visor
            fi
        fi
        [ $i -lt 3 ] && { echo "[$(date)] Retry $i/3 failed, waiting..."; sleep $((5 * i)); } || { echo "[$(date)] ERROR: Download failed after 3 attempts"; exit 1; }
    done
fi

# Download signature
echo "[$(date)] Downloading signature file..."
for i in 1 2 3; do
    if timeout 60 curl -L -o hl-visor.asc https://binaries.hyperliquid.xyz/Mainnet/hl-visor.asc; then
        if [ -s hl-visor.asc ]; then
            break
        else
            echo "[$(date)] ERROR: Signature file is empty"
            rm -f hl-visor.asc
        fi
    fi
    [ $i -lt 3 ] && { echo "[$(date)] Retry $i/3 failed, waiting..."; sleep $((5 * i)); } || { echo "[$(date)] ERROR: Signature download failed"; exit 1; }
done

# Import GPG key
KEY_ID="CF2C2EA3DC3E8F042A55FB6503254A9349F1820B"
KEY_FILE="/var/lib/cloud/instance/scripts/hl-pub-key.asc"
[ ! -f "$KEY_FILE" ] && { echo "[$(date)] ERROR: GPG key not found"; exit 1; }
gpg --list-keys "$KEY_ID" &>/dev/null || gpg --import "$KEY_FILE" || exit 1

# Verify signature
gpg --verify hl-visor.asc hl-visor &>/dev/null || { echo "[$(date)] ERROR: GPG verification failed"; exit 1; }

echo "[$(date)] GPG verification successful"

chmod +x hl-visor
rm -f hl-visor.asc

echo "[$(date)] ✓ hl-visor installed (hl-node will be downloaded on first run)"