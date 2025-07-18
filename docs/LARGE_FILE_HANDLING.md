# Hyperliquid Large File Handling

## Issue Description

Hyperliquid nodes can generate extremely large data files, particularly:

- **node_order_statuses**: Can generate files up to 20GB+ per hour
- **periodic_abci_states**: Consistently generates 2GB files
- **replica_cmds**: Generates 2-3GB files regularly

A single node can accumulate 200GB+ of data within hours of operation.

## Root Causes

1. **High-frequency trading data**: Order status updates are generated for every order change
2. **Complete state snapshots**: periodic_abci_states saves full blockchain state regularly
3. **Detailed command logs**: replica_cmds logs all node operations

## Mitigation Strategies

### 1. Automated Backup Sweep (Implemented)

The backup system now includes:
- **Scheduled sweeps every 4 hours** via systemd timer
- **Cron backup** in case systemd fails
- **6-hour timeout** for processing large files
- **Chunked uploads** for files >1GB (100MB chunks)

### 2. Continuous Backup Service

The main backup service runs continuously and:
- Backs up files older than 1 hour
- Compresses with gzip -6 (balanced compression)
- Deletes local files only after verified S3 upload

### 3. Storage Recommendations

For production deployments:
- **Minimum 500GB EBS volume** (current default)
- **Consider 1TB for heavy trading periods**
- **Monitor disk usage** with provided scripts

## Monitoring Commands

Check disk usage:
```bash
df -h /var/hl
du -sh /var/hl/data/* | sort -hr | head -10
```

Check backup status:
```bash
systemctl status hl-backup
systemctl status hl-backup-sweep.timer
tail -f /var/log/hl-backup.log
```

Find large files:
```bash
find /var/hl/data -type f -size +1G -exec ls -lh {} \;
```

## Emergency Cleanup

If disk space becomes critical:

1. Run manual backup sweep:
```bash
sudo /usr/local/bin/hl-backup-sweep hyperliquid-backup-ACCOUNTID
```

2. Check for stuck files:
```bash
# Files older than 6 hours that should have been backed up
find /var/hl/data -type f -mmin +360 -size +100M
```

3. Verify S3 backup before manual deletion:
```bash
aws s3 ls s3://hyperliquid-backup-ACCOUNTID/NODE_ID/
```

## Configuration Tuning

If disk usage remains problematic, consider:

1. **More frequent sweeps**: Change timer from 4h to 2h
2. **Smaller chunk size**: Reduce from 100MB to 50MB for faster uploads
3. **More aggressive compression**: Use gzip -9 (slower but smaller)

## Important Notes

- **NEVER delete files without verifying S3 backup**
- **The backup system implements zero-data-loss guarantees**
- **Large files are normal for active trading nodes**
- **Disk usage will stabilize once backup sweep catches up**