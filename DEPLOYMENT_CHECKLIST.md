# Hyperliquid Node Deployment Checklist

## ✅ Pre-Deployment Checks

### 1. **Critical Fixes Applied**
- [x] GOSSIP_CONFIG passed to bootstrap script
- [x] LOGGING_ARGS properly defined
- [x] Device detection for data volume (handles /dev/nvme1n1, /dev/xvdf, /dev/sdf)
- [x] Lock cleanup in backup script
- [x] Project name standardized to "hyperliquid"

### 2. **Module Structure**
- [x] **Scripts Module**: S3 bucket for script storage
- [x] **Backup Module**: S3 buckets for continuous backup (conditional)
- [x] **IAM Module**: Roles and permissions
- [x] **Network Module**: Security groups and placement group
- [x] **Compute Module**: EC2 instance with bootstrap

### 3. **Key Features Verified**
- [x] **S3 Script Management**: Scripts uploaded to S3, downloaded on boot
- [x] **Continuous Backup**: Hourly backup with 65-min age check
- [x] **Data Redirection**: Symlink /root/hl → /var/hl
- [x] **PCAP Rotation**: Fixed with proper strftime format
- [x] **GPG Verification**: hl-pub-key.asc bundled and used
- [x] **Service Name**: "hyperliquid" (not hl-node)

### 4. **Configuration in terraform.tfvars**
```hcl
# All logging enabled
write_trades = true
write_order_statuses = true
write_events = true

# Network capture enabled
enable_tcpdump = true

# Debug mode for troubleshooting
debug_mode = true

# Continuous backup enabled
enable_backup = true

# Large data volume (500GB)
data_volume_gb = 500
```

### 5. **Scripts Execution Order**
1. `01-system-setup.sh` - System updates and limits
2. `02-storage-setup.sh` - Mount data volume
3. `03-install-hl.sh` - Download and verify binaries
4. `04-configure-hl.sh` - Create systemd service
5. `05-start-service.sh` - Start hyperliquid service
6. `06-monitoring-setup.sh` - Setup tcpdump if enabled
7. `07-backup-setup.sh` - Setup continuous backup if enabled

### 6. **Data Flow**
- **Hyperliquid writes to**: `/root/hl/` (hardcoded)
- **Symlinked to**: `/var/hl/` (mounted data volume)
- **Backup structure**: `{node-id}/{data-type}/{date}/{timestamp}.gz`
- **PCAP files**: `/var/hl/pcap/capture-YYYYMMDD-HHMMSS.pcap`

### 7. **Monitoring Commands**
```bash
# Service status
sudo systemctl status hyperliquid

# View logs
sudo journalctl -u hyperliquid -f

# Check backup
sudo journalctl -u hl-backup -f

# Check pcap rotation
check-pcap-rotation

# Update scripts
sudo hl-update
```

## 🚀 Deployment Steps

1. **Initialize Terraform**
   ```bash
   terraform init
   ```

2. **Review Plan**
   ```bash
   terraform plan
   ```

3. **Deploy**
   ```bash
   terraform apply
   ```

4. **Connect and Verify**
   ```bash
   ssh ubuntu@<public-ip>
   sudo systemctl status hyperliquid
   df -h /var/hl
   ```

## ⚠️ Post-Deployment

1. **Restrict SSH Access**: Update security group to limit SSH to your IP
2. **Monitor Disk Usage**: ~100-200GB/day data growth
3. **Check Backups**: Verify S3 uploads are working
4. **Watch Logs**: Ensure node is syncing properly

## 🔍 Troubleshooting

If the instance stops after deployment:
1. Check `/var/log/hyperliquid-bootstrap.log`
2. If debug_mode=true, instance stays running for debugging
3. Common issues:
   - GPG verification failure
   - Network connectivity
   - Disk space
   - Service configuration

## ✅ Ready to Deploy!

All critical issues have been fixed. The deployment should now:
- Download scripts from S3
- Mount data volume correctly
- Start Hyperliquid node with proper configuration
- Enable continuous backup to S3
- Capture network traffic with hourly rotation