#!/bin/bash
# 01-system-setup.sh - Update system and install required packages

set -euo pipefail

echo "[$(date)] Step 1: System setup - updating packages..."

# Update system
apt-get update
apt-get upgrade -y

echo "[$(date)] Installing required packages..."
apt-get install -y \
    curl \
    jq \
    tcpdump \
    gnupg \
    lsb-release \
    ca-certificates \
    logrotate

echo "[$(date)] System setup completed"