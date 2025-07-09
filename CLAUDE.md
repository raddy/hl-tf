# Hyperliquid Node Deployment - Learnings & Context

This document captures key learnings and context from deploying a Hyperliquid non-validator node on AWS.

## Project Overview

We built a Terraform deployment for a Hyperliquid node that:
- Records all trading data (trades, orders, events)
- Captures network packets for correlation analysis
- Continuously backs up data to S3
- Uses S3-based script management for easy updates

## Key Technical Learnings

### 1. Hyperliquid Node Behavior

- **Hardcoded Path**: hl-visor writes data to `/root/hl/` (hardcoded, cannot be changed)
- **Solution**: Symlink `/root/hl` → `/var/hl` to redirect to mounted EBS volume
- **Data Volume**: Generates 100-200GB/day of data
- **Service Name**: Must be "hyperliquid" not "hl-node" to avoid process name conflicts

### 2. Ubuntu 24.04 Requirement

- **Issue**: Hyperliquid binaries require glibc 2.39+
- **Solution**: Must use Ubuntu 24.04 (not Amazon Linux or older Ubuntu)
- **AMI**: Use Canonical's official Ubuntu 24.04 AMI

### 3. GPG Verification

- **Requirement**: GPG verification is mandatory (not optional)
- **Key ID**: CF2C2EA3DC3E8F042A55FB6503254A9349F1820B
- **Solution**: Bundle the public key in the repo rather than downloading each time

### 4. Logging Configuration

- **Flag Issue**: Use `--write-misc-events` not `--write-events`
- **Data Structure**:
  - `node_trades/hourly/YYYYMMDD/HH` (single file per hour)
  - `node_order_statuses/hourly/YYYYMMDD/HH` (single file per hour)
  - `replica_cmds/YYYY-MM-DDTHH:MM:SS.sssZ/` (timestamp directories)
  - `misc_events/` (similar hourly structure)

### 5. PCAP Rotation

- **Issue**: Initial tcpdump setup didn't rotate properly
- **Fix**: Use strftime format in filename: `-w 'capture-%Y%m%d-%H%M%S.pcap'`
- **Important**: Need `-Z root` flag to handle permission issues

### 6. Backup Strategy

- **Timing**: Only backup files 65+ minutes old to avoid partial uploads
- **Current Hour**: Skip files from current hour (still being written)
- **Frequency**: Hourly backups work well with 500GB volume
- **Structure**: Organized by `{node-id}/{data-type}/{date}/{timestamp}.gz`

### 7. AWS Permissions

Required IAM permissions for deployment:
- EC2: Full access for instances, volumes, security groups, etc.
- IAM: Create roles/policies for `hyperliquid-*` resources
- S3: Full access for `hyperliquid-*` buckets

### 8. Terraform Template Issues

- **Bootstrap Scripts**: Use `$$` to escape bash variables in templatefile()
- **Example**: `${1:-latest}` → `$${1:-latest}`

### 9. S3 Lifecycle Rules

- **Constraint**: DEEP_ARCHIVE transition must be 90+ days after GLACIER_IR
- **Fix**: Use 30 days → GLACIER_IR, 180 days → DEEP_ARCHIVE

## Configuration Settings

### terraform.tfvars
```hcl
# Logging - ALL enabled for research
write_trades = true
write_order_statuses = true
write_events = true

# Network capture for correlation
enable_tcpdump = true

# Keep instance running on errors
debug_mode = true

# Continuous backup to S3
enable_backup = true

# 500GB is sufficient with hourly backups
data_volume_gb = 500
```

## Common Issues & Solutions

1. **Disk Full**: 
   - Cause: No space for updates/downloads
   - Solution: Continuous backup with file deletion after upload

2. **Memory Issues**:
   - Cause: Insufficient instance size
   - Solution: Use c6i.4xlarge minimum (was failing on c6i.2xlarge)

3. **Device Names**:
   - Issue: Device name varies by instance type
   - Solution: Check multiple paths (/dev/nvme1n1, /dev/xvdf, /dev/sdf)

4. **Service Won't Start**:
   - Check: Service name conflicts (use "hyperliquid")
   - Check: GPG verification failure
   - Check: Missing gossip config

## Project Structure

```
modules/
├── scripts/     # S3-based script management
├── backup/      # S3 backup buckets and lifecycle
├── iam/         # IAM roles and policies
├── network/     # Security groups and placement
└── compute/     # EC2 instance and bootstrap
```

## Key Commands

```bash
# Check service
sudo systemctl status hyperliquid

# View logs
sudo journalctl -u hyperliquid -f

# Check backup
sudo journalctl -u hl-backup -f

# Check pcap rotation
check-pcap-rotation

# Update scripts
sudo hl-update

# Debug bootstrap
cat /var/log/hyperliquid-bootstrap.log
```

## Data Analysis

For correlating network captures with trading events:
```bash
./scripts/correlate-events.sh <backup-bucket> <date> <hour>
```

This downloads all data for a specific hour with aligned timestamps.