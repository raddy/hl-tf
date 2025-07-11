# Hyperliquid Node - Terraform Deployment

Terraform deployment for running a Hyperliquid non-validator node on AWS with optional backups and packet capture.

## Requirements

- Terraform >= 1.0
- AWS account with VPC/subnet
- Ubuntu 24.04 (required for glibc 2.39+)
- SSH key pair

## Quick Start

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your VPC/subnet IDs

./scripts/init.sh
./scripts/apply.sh

# Get IP and SSH in
terraform output instance_public_ip
ssh ubuntu@<ip>

# Check logs
sudo journalctl -u hyperliquid -f
```

## Configuration

Key variables in `terraform.tfvars`:

```hcl
# Required
vpc_id           = "vpc-xxx"
public_subnet_id = "subnet-xxx"

# Instance
instance_type  = "c6i.4xlarge"  # 16 vCPU minimum
data_volume_gb = 500            # ~2-5 days of data

# Features
enable_backup  = true   # S3 backups
enable_tcpdump = false  # Packet capture (warning: generates tons of data)
```

## Architecture

- EC2 instance running `hl-visor` 
- Dedicated EBS volume at `/var/hl` (symlinked from `/root/hl`)
- Scripts managed via S3 for easy updates
- Optional hourly S3 backups with compression
- Optional tcpdump with 15-minute rotation

## Data Volumes

Expect:
- Trading/events: 100-200GB/day
- PCAPs: 500GB-1TB/day if enabled
- Compression reduces by 70-90%

With backups enabled, you need 15-50 Mbps upload bandwidth or backups will fall behind.

## Operations

```bash
# On the instance
hl-monitor              # Quick status check
hl-backup-status        # Backup status
sudo hl-update          # Update scripts from S3

# Emergency disk cleanup
find /var/hl/pcap -name "*.pcap" -mmin +120 -delete
```

## Common Issues

**Disk fills up**: Either disable pcaps or increase volume size. The backup script deletes local files after upload.

**Backup state wrong**: S3 state file tracks last backup time. Reset with:
```bash
echo '{"node_trades":"2020-01-01T00:00:00Z"}' | sudo tee /var/hl/backup_state.json
```

**Terraform bucket exists**: Import existing resources:
```bash
terraform import "module.backup[0].aws_s3_bucket.backup" bucket-name
```

**tcpdump crashes**: Known issue with strftime on Ubuntu 24.04, we use manual rotation as workaround.

## Scripts

- `./scripts/full-restart.sh` - Destroy and recreate everything
- `./scripts/force-update-scripts.sh` - Force S3 script update
- `./scripts/correlate-events.sh` - Download backup data for analysis

## Costs

- c6i.4xlarge: ~$500/month
- 500GB EBS: ~$40/month  
- S3: Variable based on retention

## Notes

- Service must be named "hyperliquid" not "hl-node" 
- GPG verification is mandatory
- Use `--write-misc-events` not `--write-events`
- Backups use gzip -9 for max compression