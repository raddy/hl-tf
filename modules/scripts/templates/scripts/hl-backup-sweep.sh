#!/bin/bash
# Secondary sweep backup script - catches any files missed by primary backup
# Runs less frequently but checks ALL files regardless of state
set -euo pipefail

# Ensure proper PATH for systemd services (AWS CLI via snap)
export PATH="/snap/bin:/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin"

# Set AWS region from metadata
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
export AWS_DEFAULT_REGION=${AZ%?}
export AWS_REGION=$AWS_DEFAULT_REGION

BACKUP_BUCKET="$1"
if [ -z "$BACKUP_BUCKET" ]; then
    echo "Usage: $0 <backup-bucket>"
    exit 1
fi

# Configuration
NODE_ID=$(hostname)
DATA_DIR="/var/hl/data"
PCAP_DIR="/var/hl/pcap"
LOG_FILE="/var/log/hl-backup-sweep.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SWEEP] $*" | tee -a "$LOG_FILE"
}

# Debug AWS configuration
debug_aws() {
    log "Checking AWS configuration..."
    log "  AWS_DEFAULT_REGION: ${AWS_DEFAULT_REGION:-not set}"
    log "  AWS_REGION: ${AWS_REGION:-not set}"
    log "  EC2_REGION: ${EC2_REGION:-not set}"
    log "  Checking IAM identity..."
    if timeout 15 aws sts get-caller-identity 2>&1 | tee -a "$LOG_FILE"; then
        log "  AWS credentials OK"
    else
        log "  ERROR: AWS credentials not configured properly!"
        return 1
    fi
    log "  Checking S3 bucket access..."
    if timeout 30 aws s3 ls "s3://${BACKUP_BUCKET}/" --max-items 1 2>&1 | tee -a "$LOG_FILE"; then
        log "  S3 bucket access OK"
    else
        log "  ERROR: Cannot access S3 bucket ${BACKUP_BUCKET}"
        return 1
    fi
    return 0
}

# Function to check if file exists in S3
check_s3_exists() {
    local s3_path=$1
    timeout 30 aws s3 ls "$s3_path" >/dev/null 2>&1
}

# Function to backup any missing hourly data files
sweep_hourly_data() {
    local dir_name=$1
    local full_path="$DATA_DIR/$dir_name/hourly"
    
    if [ ! -d "$full_path" ]; then
        return 0
    fi
    
    log "Sweeping $dir_name for any missed files..."
    
    local current_hour=$(date +%Y%m%d%H)
    local swept_count=0
    
    # Check ALL files older than 2 hours
    for date_dir in "$full_path"/2*; do
        [ -d "$date_dir" ] || continue
        local date_name=$(basename "$date_dir")
        
        for hour_file in "$date_dir"/*; do
            [ -f "$hour_file" ] || continue
            
            local hour=$(basename "$hour_file")
            local file_age=$(($(date +%s) - $(stat -c %Y "$hour_file" 2>/dev/null || echo 0)))
            
            # Skip if too recent (less than 2 hours old)
            if [ "$file_age" -lt 7200 ]; then
                continue
            fi
            
            # Check if this file exists in S3
            local s3_key="${NODE_ID}/${dir_name}/${date_name}/${date_name}_${hour}.gz"
            
            if ! check_s3_exists "s3://${BACKUP_BUCKET}/$s3_key"; then
                log "  Found missing file: $date_name/$hour (age: $((file_age/3600))h)"
                
                # Compress and upload
                local temp_file="/tmp/sweep_${date_name}_${hour}.gz"
                if gzip -9 -c "$hour_file" > "$temp_file"; then
                    if timeout 300 aws s3 cp "$temp_file" "s3://${BACKUP_BUCKET}/$s3_key" \
                        --metadata "node=${NODE_ID},type=${dir_name},date=${date_name},hour=${hour},sweep=true" \
                        --storage-class STANDARD_IA \
                        --no-progress 2>&1 | tee -a "$LOG_FILE"; then
                        log "  ✓ Swept up $s3_key"
                        swept_count=$((swept_count + 1))
                        # Delete old file to save space
                        rm -f "$hour_file"
                    else
                        log "  ✗ Failed to upload $s3_key - AWS error above"
                    fi
                    rm -f "$temp_file"
                fi
            fi
        done
        
        # Clean up empty directories
        rmdir "$date_dir" 2>/dev/null || true
    done
    
    log "Swept $swept_count files for $dir_name"
}

# Function to sweep for missed pcap files
sweep_pcaps() {
    if [ ! -d "$PCAP_DIR" ]; then
        return 0
    fi
    
    log "Sweeping pcaps for any missed captures..."
    
    local swept_count=0
    
    # Find ALL pcap files older than 1 hour
    for pcap_file in "$PCAP_DIR"/capture-*.pcap; do
        [ -f "$pcap_file" ] || continue
        
        local file_age=$(($(date +%s) - $(stat -c %Y "$pcap_file" 2>/dev/null || echo 0)))
        
        # Skip if too recent
        if [ "$file_age" -lt 3600 ]; then
            continue
        fi
        
        local filename=$(basename "$pcap_file")
        local timestamp=$(echo "$filename" | sed -n 's/capture-\([0-9]\{8\}-[0-9]\{6\}\)\.pcap/\1/p')
        local date_part=$(echo "$timestamp" | cut -d'-' -f1)
        
        # Check if this file exists in S3
        local s3_key="${NODE_ID}/pcaps/${date_part}/capture_${timestamp}.pcap.gz"
        
        if ! check_s3_exists "s3://${BACKUP_BUCKET}/$s3_key"; then
            log "  Found missing pcap: $filename (age: $((file_age/3600))h)"
            
            # Compress and upload
            local temp_pcap="/tmp/sweep_$(basename "$pcap_file").gz"
            if gzip -9 -c "$pcap_file" > "$temp_pcap"; then
                if timeout 600 aws s3 cp "$temp_pcap" "s3://${BACKUP_BUCKET}/$s3_key" \
                    --metadata "node=${NODE_ID},type=pcap,date=${date_part},sweep=true" \
                    --storage-class STANDARD_IA \
                    --no-progress 2>&1 | tee -a "$LOG_FILE"; then
                    log "  ✓ Swept up $s3_key"
                    swept_count=$((swept_count + 1))
                    # Delete old pcap
                    rm -f "$pcap_file"
                else
                    log "  ✗ Failed to upload $s3_key - AWS error above"
                fi
                rm -f "$temp_pcap"
            fi
        else
            # File exists in S3 but still on disk - clean it up
            log "  Cleaning up already-backed-up pcap: $filename"
            rm -f "$pcap_file"
        fi
    done
    
    log "Swept $swept_count pcap files"
}

# Function to sweep replica_cmds
sweep_replica_cmds() {
    local replica_path="$DATA_DIR/replica_cmds"
    
    if [ ! -d "$replica_path" ]; then
        return 0
    fi
    
    log "Sweeping replica_cmds for any missed directories..."
    
    local swept_count=0
    local current_hour_prefix=$(date -u +"%Y-%m-%dT%H")
    
    # Find ALL directories older than 2 hours
    for ts_dir in "$replica_path"/2*; do
        [ -d "$ts_dir" ] || continue
        
        local ts_name=$(basename "$ts_dir")
        
        # Skip current hour
        if [[ "$ts_name" == "$current_hour_prefix"* ]]; then
            continue
        fi
        
        local dir_age=$(($(date +%s) - $(stat -c %Y "$ts_dir" 2>/dev/null || echo 0)))
        
        # Skip if too recent
        if [ "$dir_age" -lt 7200 ]; then
            continue
        fi
        
        # Check if this exists in S3
        local date_part=$(echo "$ts_name" | cut -d'T' -f1 | tr '-' '')
        local s3_key="${NODE_ID}/replica_cmds/${date_part}/${ts_name}.tar.gz"
        
        if ! check_s3_exists "s3://${BACKUP_BUCKET}/$s3_key"; then
            log "  Found missing replica_cmds: $ts_name (age: $((dir_age/3600))h)"
            
            # Create temp file for better error handling
            local temp_tar="/tmp/sweep_replica_${ts_name//[:\/]/_}.tar.gz"
            if GZIP=-9 tar czf "$temp_tar" -C "$replica_path" "$ts_name" 2>/dev/null; then
                if timeout 600 aws s3 cp "$temp_tar" "s3://${BACKUP_BUCKET}/$s3_key" \
                    --metadata "node=${NODE_ID},type=replica_cmds,timestamp=${ts_name},sweep=true" \
                    --no-progress 2>&1 | tee -a "$LOG_FILE"; then
                    rm -f "$temp_tar"
                    log "  ✓ Swept up $s3_key"
                    swept_count=$((swept_count + 1))
                    # Remove directory
                    rm -rf "$ts_dir"
                else
                    log "  ✗ Failed to upload $s3_key - AWS error above"
                    rm -f "$temp_tar"
                fi
            else
                log "  ✗ Failed to create tar archive for $ts_name"
            fi
        else
            # Already in S3 - clean up
            log "  Cleaning up already-backed-up replica_cmds: $ts_name"
            rm -rf "$ts_dir"
        fi
    done
    
    log "Swept $swept_count replica_cmds directories"
}

# Main sweep
log "Starting backup sweep to s3://$BACKUP_BUCKET"

# Debug AWS configuration first
if ! debug_aws; then
    log "ERROR: AWS configuration check failed - exiting"
    exit 1
fi

# Sweep all data types
sweep_hourly_data "node_trades"
sweep_hourly_data "node_order_statuses"
sweep_hourly_data "misc_events"
sweep_pcaps
sweep_replica_cmds

# Also check for orphaned compressed files in /tmp
log "Cleaning up orphaned temp files..."
find /tmp -name "sweep_*.gz" -mmin +60 -delete 2>/dev/null || true
find /tmp -name "*.pcap.gz" -mmin +60 -delete 2>/dev/null || true

log "Sweep complete"