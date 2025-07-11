# Hyperliquid Node Deployment - Development Notes

This document contains development notes, learnings, and issues encountered while building and debugging the Hyperliquid node deployment.

## Key Learnings

### 1. Ubuntu 24.04 Requirement
- **Issue**: Hyperliquid binaries require glibc 2.39+
- **Solution**: Must use Ubuntu 24.04, not Amazon Linux or older Ubuntu
- **AMI**: Use Canonical's official Ubuntu 24.04 AMI

### 2. Hardcoded Path Issue
- **Problem**: hl-visor writes to `/root/hl/` (hardcoded)
- **Solution**: Symlink `/root/hl` → `/var/hl` to use mounted EBS volume
- **Implementation**: Done in storage setup script

### 3. GPG Verification
- **Requirement**: GPG verification is mandatory
- **Key ID**: CF2C2EA3DC3E8F042A55FB6503254A9349F1820B
- **Solution**: Bundle the public key in the repo

### 4. Service Name Conflict
- **Issue**: Service must be named "hyperliquid" not "hl-node"
- **Reason**: Avoids process name conflicts with hl-visor

### 5. Correct Logging Flags
- **Wrong**: `--write-events`
- **Correct**: `--write-misc-events`

## Major Issues Encountered

### 1. Backup State Bug
**Problem**: Backup script was updating state even when no files were uploaded
```bash
# Bug: This ran even if all files were skipped
update_last_backup "$dir_name"
```

**Impact**: 
- State showed "backed up at 11:20" but nothing was actually uploaded
- Old files (hours 7-9) were ignored because they were "already backed up"
- Disk filled up with unuploaded data

**Fix**: Only update state after successful uploads
```bash
if [ "$backed_up_files" -gt 0 ]; then
    update_last_backup "$dir_name"
fi
```

### 2. tcpdump Segmentation Fault
**Problem**: tcpdump crashes with SEGV when using strftime format
```bash
# This causes segfault on Ubuntu 24.04
tcpdump -w 'capture-%Y%m%d-%H%M%S.pcap' -G 3600
```

**Solution**: Manual rotation with timeout
```bash
while true; do
    FILENAME="capture-$(date +%Y%m%d-%H%M%S).pcap"
    timeout 900 tcpdump -w "$FILENAME" ...
done
```

### 3. Metadata Endpoint Issues
**Problem**: EC2 metadata endpoint returning empty for region
```bash
# This returns empty sometimes
curl http://169.254.169.254/latest/meta-data/placement/region
```

**Fix**: Get AZ and strip last character
```bash
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
export AWS_DEFAULT_REGION=${AZ%?}
```

### 4. Massive PCAP Files
**Problem**: Single PCAP files growing to 100GB+
- One hour of capture = 100GB+
- Impossible to upload before next rotation
- Disk fills up rapidly

**Solution**: 
- Rotate every 15 minutes instead of hourly
- Use maximum compression (gzip -9)
- Delete after successful upload

### 5. Bootstrap Template Escaping
**Problem**: Terraform templatefile() breaks bash variables
```bash
VERSION=${1:-latest}  # Becomes ${1:-latest} (terraform tries to interpolate)
```

**Solution**: Double dollar signs
```bash
VERSION=$${1:-latest}  # Becomes ${1:-latest} in rendered file
```

## Data Volumes

Real-world data generation rates observed:
- **Trading data**: ~100-200GB/day raw
- **PCAP data**: 100GB+ per hour (1-2TB/day possible)
- **Compression ratios**:
  - JSON data: 85-95% reduction
  - PCAP data: 70-85% reduction

## Network Bandwidth Requirements

With compression:
- Trading/events: ~20-40GB/day compressed
- PCAP: ~200-400GB/day compressed
- **Total upload needed**: 15-50 Mbps continuous

Without sufficient bandwidth, backups will queue and disk will fill.

## Cost Considerations

1. **Storage**: 
   - 500GB might only last 6-12 hours with PCAP enabled
   - Consider 2-4TB for multi-day retention

2. **S3 Transfer Acceleration**: 
   - $0.04/GB = $8/day for 200GB
   - NOT recommended due to cost

3. **Instance Type**:
   - c6i.4xlarge minimum (16 vCPU, 32GB RAM)
   - Consider c6in for better network performance

## Debugging Commands

```bash
# Check what's consuming disk
du -sh /var/hl/* | sort -h

# Force backup run
sudo /usr/local/bin/hl-backup $(aws ec2 describe-tags --filters "Name=resource-id,Values=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)" "Name=key,Values=BackupBucket" --query 'Tags[0].Value' --output text)

# Reset backup state
echo '{"node_trades":"2020-01-01T00:00:00Z","node_order_statuses":"2020-01-01T00:00:00Z","misc_events":"2020-01-01T00:00:00Z","pcaps":"2020-01-01T00:00:00Z","replica_cmds":"2020-01-01T00:00:00Z"}' | sudo tee /var/hl/backup_state.json

# Check tcpdump issues
sudo journalctl -u hl-tcpdump -n 50 --no-pager | grep -v "Starting"

# Emergency space recovery
find /var/hl/data -type f -mmin +120 -name "*" -delete
find /var/hl/pcap -name "*.pcap" -mmin +30 -delete
```

## Terraform State Issues

When getting "BucketAlreadyOwnedByYou" errors:
```bash
# Import existing resources (escape brackets in zsh)
terraform import "module.backup[0].aws_s3_bucket.backup" bucket-name
terraform import "module.backup[0].aws_s3_bucket_versioning.backup" bucket-name
# etc...
```

## Future Improvements

1. **Backup Optimization**:
   - Parallel uploads for different data types
   - Incremental backups for large files
   - Compression pipeline optimization

2. **Monitoring**:
   - CloudWatch metrics for backup lag
   - Disk space alerts
   - Upload bandwidth monitoring

3. **Cost Optimization**:
   - Lifecycle rules for PCAP data (delete after X days)
   - Selective PCAP capture (only Hyperliquid ports)
   - Regional S3 endpoints to avoid transfer costs

## Important File Locations

- Bootstrap script: `/workspace/modules/compute/templates/bootstrap.sh`
- Backup script: `/workspace/modules/scripts/templates/scripts/hl-backup.sh`
- tcpdump wrapper: `/workspace/modules/scripts/templates/scripts/tcpdump-wrapper.sh`
- On instance: `/var/lib/cloud/instance/scripts/` (downloaded from S3)

## Testing Improvements

Always test with:
```bash
# Force script updates
./scripts/force-update-scripts.sh

# Full restart
./scripts/full-restart.sh

# Then SSH and check
sudo journalctl -u hl-backup -f
sudo journalctl -u hl-tcpdump -f
hl-monitor
```