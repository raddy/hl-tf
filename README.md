# Hyperliquid Non-Validator Node

Deploy a Hyperliquid non-validator node on AWS EC2 using Terraform.

## Requirements

- Terraform >= 1.5.7
- AWS account with VPC and subnet
- SSH key pair

## Quick Start

1. **Clone and configure**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your VPC and subnet IDs
   ```

2. **Deploy**
   ```bash
   terraform init
   terraform apply
   ```

3. **Connect**
   ```bash
   ssh ubuntu@<public-ip>
   
   # Check status
   sudo systemctl status hyperliquid
   
   # View logs
   sudo journalctl -u hyperliquid -f
   
   # Check data is being written to the correct volume
   df -h /var/hl
   ls -la /var/hl/
   ```

## What This Deploys

- **EC2 Instance**: c6i.4xlarge (default, configurable) with Ubuntu 24.04
- **Storage**: 50GB root volume + 500GB data volume mounted at `/var/hl`
- **Security**: Ports 4000-4010 open for Hyperliquid protocol, GPG verification of binaries
- **Service**: hl-visor running as systemd service named 'hyperliquid' with configurable logging
- **Monitoring**: Optional tcpdump capture with hourly rotation (stored in /var/hl/pcap/)

## Key Features

- **Data goes to the right place**: Symlinks `/root/hl` → `/var/hl` so all blockchain data is stored on the dedicated volume
- **Modular setup**: Separate scripts for each setup phase with proper error handling
- **Configurable logging**: Choose which data to log (trades, order statuses, events)
- **Optional packet capture**: tcpdump with hourly rotation for network research
- **Security**: GPG verification of binaries with retry logic
- **Failure handling**: Any setup error triggers instance shutdown (unless debug_mode=true)

## Security Warning

**SSH access is currently open to 0.0.0.0/0**. After deployment, update the security group to restrict SSH access to your IP only:

```bash
aws ec2 modify-security-group-rules --group-id <security-group-id> \
  --security-group-rules "SecurityGroupRuleId=<rule-id>,SecurityGroupRule={IpProtocol=tcp,FromPort=22,ToPort=22,CidrIpv4=YOUR_IP/32}"
```

## Configuration Options

### Logging Arguments
```hcl
write_trades         = true  # Log all trades
write_order_statuses = true  # Log order status updates  
write_events         = true  # Log misc events (uses --write-misc-events flag)
```

### Monitoring
```hcl
enable_tcpdump = true  # Capture network traffic (hourly rotation, 7 day retention)
```

### Debug Mode
```hcl
debug_mode = true  # Keep instance running on setup failure for debugging
```

## Data Growth Warning

Hyperliquid nodes generate 100-200GB of data per day. Plan your volume size accordingly:
- 500GB = ~2-5 days
- 1TB = ~5-10 days
- 8TB = ~40-80 days

## Destroy

```bash
terraform destroy
```

Note: The data volume is preserved by default (`delete_on_termination = false`)