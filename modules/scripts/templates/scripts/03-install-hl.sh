#!/bin/bash
# 03-install-hl.sh - Download and verify hl-visor binary

set -euo pipefail

echo "[$(date)] Step 3: Installing hl-visor..."

cd /usr/local/bin

# Check if hl-visor already exists
if [ -f hl-visor ]; then
    echo "[$(date)] hl-visor already exists, skipping download"
else
    # Download hl-visor
    echo "[$(date)] Downloading hl-visor binary..."
    if ! curl -L -o hl-visor https://binaries.hyperliquid.xyz/Mainnet/hl-visor; then
        echo "[$(date)] ERROR: Failed to download hl-visor"
        exit 1
    fi
fi

# Download GPG signature file
echo "[$(date)] Downloading hl-visor signature file..."
if ! curl -L -o hl-visor.asc https://binaries.hyperliquid.xyz/Mainnet/hl-visor.asc; then
    echo "[$(date)] ERROR: Failed to download signature file"
    exit 1
fi

# Import the bundled Hyperliquid public key
echo "[$(date)] Importing bundled Hyperliquid GPG key..."
KEY_ID="CF2C2EA3DC3E8F042A55FB6503254A9349F1820B"
if ! gpg --list-keys "$KEY_ID" >/dev/null 2>&1; then
    if ! gpg --import /var/lib/cloud/instance/scripts/hl-pub-key.asc; then
        echo "[$(date)] ERROR: Failed to import GPG key!"
        echo "[$(date)] Current GPG keys:"
        gpg --list-keys
        exit 1
    fi
    echo "[$(date)] GPG key imported successfully"
else
    echo "[$(date)] GPG key already imported"
fi

# Now verify the binary using the detached signature
echo "[$(date)] Verifying hl-visor binary with detached signature..."
if ! gpg --verify hl-visor.asc hl-visor; then
    echo "[$(date)] ERROR: GPG verification failed!"
    echo "[$(date)] This is a security risk - the binary may have been tampered with"
    exit 1
fi

echo "[$(date)] GPG verification successful"

# Make executable
chmod +x hl-visor

# Clean up signature files
rm -f hl-visor.asc

echo "[$(date)] hl-visor installation completed"
echo "[$(date)] Note: hl-node will be downloaded automatically by hl-visor on first run"