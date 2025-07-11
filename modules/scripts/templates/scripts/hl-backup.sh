#!/bin/bash
# Continuous backup script for Hyperliquid data
set -euo pipefail

BACKUP_BUCKET="$1"
if [ -z "$BACKUP_BUCKET" ]; then
    echo "Usage: $0 <backup-bucket>"
    exit 1
fi

# Configuration
NODE_ID=$(hostname)
DATA_DIR="/var/hl/data"
STATE_FILE="/var/hl/backup_state.json"
LOCK_DIR="/var/run/hl-backup"
LOG_FILE="/var/log/hl-backup.log"

# Ensure log rotation
if [ ! -f /etc/logrotate.d/hl-backup ]; then
    cat > /etc/logrotate.d/hl-backup <<LOGROTATE
/var/log/hl-backup.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
}
LOGROTATE
fi

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Create lock directory
mkdir -p "$LOCK_DIR"

# Function to get last backup time for a directory
get_last_backup() {
    local dir=$1
    if [ -f "$STATE_FILE" ]; then
        jq -r ".\"$dir\" // \"1970-01-01T00:00:00Z\"" "$STATE_FILE" 2>/dev/null || echo "1970-01-01T00:00:00Z"
    else
        echo "1970-01-01T00:00:00Z"
    fi
}

# Function to update last backup time
update_last_backup() {
    local dir=$1
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    if [ -f "$STATE_FILE" ]; then
        jq ".\"$dir\" = \"$timestamp\"" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    else
        echo "{\"$dir\": \"$timestamp\"}" > "$STATE_FILE"
    fi
    
    # Backup state file to S3
    aws s3 cp "$STATE_FILE" "s3://${BACKUP_BUCKET}-state/backup_state.json" 2>/dev/null || true
}

# Function to backup hourly data (node_trades, node_order_statuses)
backup_hourly_data() {
    local dir_name=$1
    local full_path="$DATA_DIR/$dir_name/hourly"
    
    if [ ! -d "$full_path" ]; then
        return 0
    fi
    
    log "Checking $dir_name for new data..."
    
    # Lock file for this directory
    local lock_file="$LOCK_DIR/${dir_name}.lock"
    
    # Try to acquire lock
    if ! mkdir "$lock_file" 2>/dev/null; then
        log "Another backup process is running for $dir_name, skipping"
        return 0
    fi
    
    # Ensure lock is removed on exit
    trap "rmdir '$lock_file' 2>/dev/null || true" EXIT
    
    # Get current hour
    local current_date=$(date +%Y%m%d)
    local current_hour=$(date +%H)
    
    # Find files modified since last backup
    local last_backup=$(get_last_backup "$dir_name")
    local last_backup_epoch=$(date -d "$last_backup" +%s 2>/dev/null || echo 0)
    
    # Track if we backed up any files
    local backed_up_files=0
    
    # Process each date directory
    for date_dir in "$full_path"/2*; do
        [ -d "$date_dir" ] || continue
        local date_name=$(basename "$date_dir")
        
        # Process each hour file
        for hour_file in "$date_dir"/*; do
            [ -f "$hour_file" ] || continue
            
            local hour=$(basename "$hour_file")
            
            # Skip current hour file (still being written)
            if [ "$date_name" = "$current_date" ] && [ "$hour" = "$current_hour" ]; then
                log "Skipping $dir_name/$date_name/$hour (current hour, still being written)"
                continue
            fi
            
            # Check if file hasn't been modified in last 65 minutes (hour + buffer)
            local now=$(date +%s)
            local file_mtime=$(stat -c %Y "$hour_file" 2>/dev/null || echo 0)
            local age=$((now - file_mtime))
            
            if [ "$age" -lt 3900 ]; then  # 65 minutes
                log "Skipping $dir_name/$date_name/$hour (modified ${age}s ago, might still be written)"
                continue
            fi
            
            if [ "$file_mtime" -gt "$last_backup_epoch" ]; then
                local file_size=$(ls -lh "$hour_file" | awk '{print $5}')
                
                # Create S3 key with proper structure for correlation
                local s3_key="${NODE_ID}/${dir_name}/${date_name}/${date_name}_${hour}.gz"
                
                log "Backing up $dir_name/$date_name/$hour ($file_size)..."
                
                # For large files, use multipart upload with progress
                local temp_file="/tmp/${date_name}_${hour}.gz"
                log "  Compressing to $temp_file with maximum compression..."
                if gzip -9 -c "$hour_file" > "$temp_file"; then
                    local compressed_size=$(ls -lh "$temp_file" | awk '{print $5}')
                    log "  Compressed size: $compressed_size, uploading..."
                    
                    # Upload with multipart, progress, and retry
                    local upload_success=0
                    for attempt in 1 2 3; do
                        if aws s3 cp "$temp_file" "s3://${BACKUP_BUCKET}/$s3_key" \
                            --metadata "node=${NODE_ID},type=${dir_name},date=${date_name},hour=${hour}" \
                            --storage-class STANDARD_IA \
                            --no-progress; then
                            upload_success=1
                            break
                        else
                            log "  Upload attempt $attempt failed, retrying..."
                            sleep $((attempt * 10))
                        fi
                    done
                    
                    rm -f "$temp_file"
                    
                    if [ "$upload_success" -eq 1 ]; then
                        log "✓ Uploaded $s3_key"
                        backed_up_files=$((backed_up_files + 1))
                        # Delete the file after successful upload to save space
                        rm -f "$hour_file"
                        log "  Deleted local file to save space"
                    else
                        log "✗ Failed to upload $s3_key after 3 attempts"
                        rmdir "$lock_file" 2>/dev/null || true
                        return 1
                    fi
                else
                    log "✗ Failed to compress $hour_file"
                    rm -f "$temp_file"
                    rmdir "$lock_file" 2>/dev/null || true
                    return 1
                fi
            fi
        done
    done
    
    # Only update last backup time if we actually backed up files
    if [ "$backed_up_files" -gt 0 ]; then
        update_last_backup "$dir_name"
    fi
    rmdir "$lock_file" 2>/dev/null || true
    return 0
}

# Function to backup pcap files with correlation metadata
backup_pcaps() {
    local pcap_dir="/var/hl/pcap"
    
    if [ ! -d "$pcap_dir" ]; then
        return 0
    fi
    
    log "Checking pcaps for new captures..."
    
    local lock_file="$LOCK_DIR/pcaps.lock"
    if ! mkdir "$lock_file" 2>/dev/null; then
        log "Another backup process is running for pcaps, skipping"
        return 0
    fi
    
    trap "rmdir '$lock_file' 2>/dev/null || true" EXIT
    
    local last_backup=$(get_last_backup "pcaps")
    local last_backup_epoch=$(date -d "$last_backup" +%s 2>/dev/null || echo 0)
    
    # Track if we backed up any files
    local backed_up_files=0
    
    # Find completed pcap files (not the one currently being written)
    for pcap_file in "$pcap_dir"/capture-*.pcap; do
        [ -f "$pcap_file" ] || continue
        
        # Skip if file is still being written (modified in last 65 minutes)
        local now=$(date +%s)
        local file_mtime=$(stat -c %Y "$pcap_file" 2>/dev/null || echo 0)
        local age=$((now - file_mtime))
        
        if [ "$age" -lt 1200 ]; then  # 20 minutes (15 min rotation + 5 min buffer)
            log "Skipping $(basename "$pcap_file") (modified ${age}s ago, might still be written)"
            continue
        fi
        
        if [ "$file_mtime" -gt "$last_backup_epoch" ]; then
            local filename=$(basename "$pcap_file")
            # Extract timestamp from filename (capture-YYYYMMDD-HHMMSS.pcap)
            local timestamp=$(echo "$filename" | sed -n 's/capture-\([0-9]\{8\}-[0-9]\{6\}\)\.pcap/\1/p')
            local date_part=$(echo "$timestamp" | cut -d'-' -f1)
            local time_part=$(echo "$timestamp" | cut -d'-' -f2)
            
            # Create S3 key that allows correlation with events
            local s3_key="${NODE_ID}/pcaps/${date_part}/capture_${timestamp}.pcap.gz"
            
            log "Backing up $filename..."
            
            # Compress pcap with maximum compression to temp file first
            local temp_pcap="/tmp/$(basename "$pcap_file").gz"
            log "  Compressing pcap with maximum compression..."
            if gzip -9 -c "$pcap_file" > "$temp_pcap"; then
                local compressed_size=$(ls -lh "$temp_pcap" | awk '{print $5}')
                log "  Compressed size: $compressed_size, uploading..."
                
                if aws s3 cp "$temp_pcap" "s3://${BACKUP_BUCKET}/$s3_key" --metadata "node=${NODE_ID},type=pcap,date=${date_part},time=${time_part}"; then
                    rm -f "$temp_pcap"
                    log "✓ Uploaded $s3_key"
                    backed_up_files=$((backed_up_files + 1))
                    # Delete old pcap to save space
                    rm -f "$pcap_file"
                else
                    rm -f "$temp_pcap"
                    log "✗ Failed to upload $s3_key"
                    rmdir "$lock_file" 2>/dev/null || true
                    return 1
                fi
            else
                log "✗ Failed to upload $s3_key"
                rmdir "$lock_file" 2>/dev/null || true
                return 1
            fi
        fi
    done
    
    # Only update last backup time if we actually backed up files
    if [ "$backed_up_files" -gt 0 ]; then
        update_last_backup "pcaps"
    fi
    rmdir "$lock_file" 2>/dev/null || true
    return 0
}

# Function to backup replica_cmds by timestamp
backup_replica_cmds() {
    local replica_path="$DATA_DIR/replica_cmds"
    
    if [ ! -d "$replica_path" ]; then
        return 0
    fi
    
    log "Checking replica_cmds for new data..."
    
    local lock_file="$LOCK_DIR/replica_cmds.lock"
    if ! mkdir "$lock_file" 2>/dev/null; then
        log "Another backup process is running for replica_cmds, skipping"
        return 0
    fi
    
    trap "rmdir '$lock_file' 2>/dev/null || true" EXIT
    
    local last_backup=$(get_last_backup "replica_cmds")
    local last_backup_epoch=$(date -d "$last_backup" +%s 2>/dev/null || echo 0)
    
    # Track if we backed up any files
    local backed_up_files=0
    
    # Get current timestamp for comparison
    local now=$(date +%s)
    local current_time_prefix=$(date -u +"%Y-%m-%dT%H")
    
    # Process timestamp directories
    for ts_dir in "$replica_path"/2*; do
        [ -d "$ts_dir" ] || continue
        
        local ts_name=$(basename "$ts_dir")
        
        # Skip if this is from the current hour (might still be written)
        if [[ "$ts_name" == "$current_time_prefix"* ]]; then
            log "Skipping replica_cmds/$ts_name (current hour, might still be written)"
            continue
        fi
        
        # Check directory modification time
        local dir_mtime=$(stat -c %Y "$ts_dir" 2>/dev/null || echo 0)
        local age=$((now - dir_mtime))
        
        # Skip if modified recently (could still be receiving files)
        if [ "$age" -lt 3900 ]; then  # 65 minutes
            log "Skipping replica_cmds/$ts_name (modified ${age}s ago, might still be written)"
            continue
        fi
        
        # Check if any files inside were modified recently
        local newest_file_mtime=0
        while IFS= read -r -d '' file; do
            local file_mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)
            if [ "$file_mtime" -gt "$newest_file_mtime" ]; then
                newest_file_mtime=$file_mtime
            fi
        done < <(find "$ts_dir" -type f -print0 2>/dev/null)
        
        local newest_age=$((now - newest_file_mtime))
        if [ "$newest_age" -lt 3900 ]; then
            log "Skipping replica_cmds/$ts_name (contains files modified ${newest_age}s ago)"
            continue
        fi
        
        if [ "$dir_mtime" -gt "$last_backup_epoch" ]; then
            # Extract date from timestamp for organized storage
            local date_part=$(echo "$ts_name" | cut -d'T' -f1 | tr '-' '')
            local s3_key="${NODE_ID}/replica_cmds/${date_part}/${ts_name}.tar.gz"
            
            # Count files in directory
            local file_count=$(find "$ts_dir" -type f | wc -l)
            local dir_size=$(du -sh "$ts_dir" | cut -f1)
            
            log "Backing up replica_cmds/$ts_name ($file_count files, $dir_size)..."
            
            # Use maximum compression for tar
            if GZIP=-9 tar czf - -C "$replica_path" "$ts_name" | aws s3 cp - "s3://${BACKUP_BUCKET}/$s3_key" --metadata "node=${NODE_ID},type=replica_cmds,timestamp=${ts_name},files=${file_count}"; then
                log "✓ Uploaded $s3_key"
                backed_up_files=$((backed_up_files + 1))
                # Remove old data to save space
                rm -rf "$ts_dir"
                log "  Deleted local directory to save space"
            else
                log "✗ Failed to upload $s3_key"
                rmdir "$lock_file" 2>/dev/null || true
                return 1
            fi
        fi
    done
    
    # Only update last backup time if we actually backed up files
    if [ "$backed_up_files" -gt 0 ]; then
        update_last_backup "replica_cmds"
    fi
    rmdir "$lock_file" 2>/dev/null || true
    return 0
}

# Function to backup misc events
backup_misc_events() {
    local events_path="$DATA_DIR/misc_events"
    
    if [ ! -d "$events_path" ]; then
        return 0
    fi
    
    log "Checking misc_events for new data..."
    
    # Similar structure to hourly data
    backup_hourly_data "misc_events"
}

# Cleanup function for locks
cleanup_locks() {
    log "Cleaning up lock files..."
    rm -rf "$LOCK_DIR"/*.lock 2>/dev/null || true
}

# Ensure cleanup on exit
trap cleanup_locks EXIT INT TERM

# Main backup loop
log "Starting continuous backup to s3://$BACKUP_BUCKET"
log "Backup runs hourly, uploading completed files only"

# Restore state from S3 if exists
aws s3 cp "s3://${BACKUP_BUCKET}-state/backup_state.json" "$STATE_FILE" 2>/dev/null || true

while true; do
    # Backup each data type
    backup_hourly_data "node_trades"
    backup_hourly_data "node_order_statuses"
    backup_misc_events
    backup_pcaps
    backup_replica_cmds
    
    # Sleep for 1 hour before next check
    # This ensures files have finished writing before backup
    sleep 3600
done
