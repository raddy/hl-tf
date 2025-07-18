# Script Directory Review

## Date: 2025-07-18

### Core Terraform Scripts (KEEP)

#### ✅ `init.sh`
- **Purpose**: Initialize Terraform workspace
- **Status**: Required for first-time setup
- **Usage**: Run once when setting up new environment

#### ✅ `apply.sh`
- **Purpose**: Safe Terraform apply with confirmation
- **Status**: Useful for careful deployments
- **Features**: 
  - Checks for terraform.tfvars
  - Runs plan first
  - Asks for confirmation

#### ✅ `destroy.sh`
- **Purpose**: Destroy infrastructure with safety checks
- **Status**: Keep for clean teardowns
- **Usage**: When removing all resources

#### ✅ `full-restart.sh`
- **Purpose**: Complete infrastructure recreation
- **Status**: Critical for your workflow
- **Features**:
  - Auto-approves operations
  - Forces script updates
  - Most used script

### Validation Scripts (KEEP - Recently Added)

#### ✅ `validate-deployment.sh`
- **Purpose**: Pre-deployment validation
- **Status**: Essential - created today
- **Checks**:
  - terraform.tfvars settings
  - Script syntax
  - AWS credentials
  - Instance state

#### ✅ `verify-data-collection.sh`
- **Purpose**: Post-deployment verification
- **Status**: Essential - created today
- **Verifies**:
  - All services running
  - Data collection active
  - Backup system working
  - Correct node flags

### Backup Management (KEEP)

#### ✅ `import-existing-buckets.sh`
- **Purpose**: Import existing S3 buckets to Terraform
- **Status**: Important for avoiding conflicts
- **Usage**: When "resource already exists" errors occur

#### ✅ `validate-backup-buckets.sh`
- **Purpose**: Check S3 bucket state
- **Status**: Useful for troubleshooting
- **Features**:
  - Compares AWS vs Terraform state
  - Identifies configuration drift

### Analysis Scripts (KEEP but needs update)

#### ⚠️ `correlate-events.sh`
- **Purpose**: Download and correlate pcaps with trading events
- **Status**: Needs minor update
- **Issue**: References 15-minute pcap chunks, but tcpdump creates 10-minute files
- **Fix needed**: Update line 36 pattern and comments

## Recommended Actions

1. **Keep all scripts** - Each serves a specific purpose

2. **Update correlate-events.sh**:
   ```bash
   # Line 36 - Change from:
   aws s3 ls "s3://${BACKUP_BUCKET}/${PCAP_PREFIX}/" | grep -E "capture_${DATE}-${HOUR}[0-5][0-9][0-5][0-9]\.pcap\.gz"
   # To:
   aws s3 ls "s3://${BACKUP_BUCKET}/${PCAP_PREFIX}/" | grep -E "capture_${DATE}-${HOUR}[0-5][0-9]"
   ```

3. **Consider adding**:
   - `check-disk-usage.sh` - Monitor disk usage trends
   - `manual-backup-sweep.sh` - Wrapper for emergency sweeps
   - `download-data.sh` - Download specific data types for analysis

## Script Usage Workflow

### Initial Setup
```bash
./init.sh
# Edit terraform.tfvars
./validate-deployment.sh
./apply.sh
```

### Full Restart (Most Common)
```bash
./validate-deployment.sh
./full-restart.sh
# Wait 5 minutes
./verify-data-collection.sh
```

### Troubleshooting
```bash
./validate-backup-buckets.sh  # Check S3 state
./import-existing-buckets.sh  # Fix S3 conflicts
```

### Data Analysis
```bash
./correlate-events.sh hyperliquid-backup-xxx 20250718 14
```

All scripts are current and serve important purposes in your workflow.