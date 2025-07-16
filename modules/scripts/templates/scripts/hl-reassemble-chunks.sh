#!/bin/bash
# Script to reassemble chunked files from S3 backup
set -euo pipefail

# Usage: hl-reassemble-chunks.sh <bucket> <s3_key_prefix> <output_file>

BUCKET="$1"
S3_KEY_PREFIX="$2"
OUTPUT_FILE="$3"

if [ -z "$BUCKET" ] || [ -z "$S3_KEY_PREFIX" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "Usage: $0 <bucket> <s3_key_prefix> <output_file>"
    echo "Example: $0 hyperliquid-backup-123 ip-1-2-3-4/node_trades/20250714/20250714_4.gz ./reassembled_file"
    exit 1
fi

# Create temp directory for chunks
TEMP_DIR="/tmp/reassemble_$(basename "$OUTPUT_FILE")_$$"
mkdir -p "$TEMP_DIR"

# Function to clean up on exit
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "Downloading manifest..."
MANIFEST_KEY="${S3_KEY_PREFIX}.manifest"
if aws s3 cp "s3://${BUCKET}/${MANIFEST_KEY}" "$TEMP_DIR/manifest" 2>/dev/null; then
    echo "Manifest downloaded successfully"
    cat "$TEMP_DIR/manifest"
    
    # Read chunk count from manifest
    CHUNK_COUNT=$(grep "chunk_count=" "$TEMP_DIR/manifest" | cut -d'=' -f2)
    echo "Expected chunks: $CHUNK_COUNT"
else
    echo "Warning: No manifest found, attempting to discover chunks..."
    CHUNK_COUNT=999  # Will break when no more chunks found
fi

echo "Downloading and reassembling chunks..."
chunk_num=0
> "$OUTPUT_FILE"  # Create empty output file

# Download chunks in order
while [ $chunk_num -lt $CHUNK_COUNT ]; do
    # Generate chunk suffix (aa, ab, ac, etc.)
    if [ $chunk_num -lt 26 ]; then
        suffix1="a"
        suffix2=$(printf "\\$(printf '%03o' $((97 + chunk_num)))")
    else
        suffix1=$(printf "\\$(printf '%03o' $((97 + chunk_num / 26)))") 
        suffix2=$(printf "\\$(printf '%03o' $((97 + chunk_num % 26)))") 
    fi
    
    chunk_suffix="${suffix1}${suffix2}"
    chunk_key="${S3_KEY_PREFIX}.chunk_${chunk_suffix}"
    
    echo "Downloading chunk $((chunk_num + 1))/$CHUNK_COUNT: $chunk_suffix"
    
    if aws s3 cp "s3://${BUCKET}/${chunk_key}" "$TEMP_DIR/chunk_${chunk_suffix}.gz" 2>/dev/null; then
        # Decompress chunk and append to output file
        gunzip -c "$TEMP_DIR/chunk_${chunk_suffix}.gz" >> "$OUTPUT_FILE"
        rm -f "$TEMP_DIR/chunk_${chunk_suffix}.gz"
        chunk_num=$((chunk_num + 1))
    else
        if [ $chunk_num -eq 0 ]; then
            echo "Error: No chunks found for $S3_KEY_PREFIX"
            exit 1
        else
            echo "No more chunks found, stopping at chunk $chunk_num"
            break
        fi
    fi
done

echo "Reassembly complete: $OUTPUT_FILE"
echo "Final file size: $(ls -lh "$OUTPUT_FILE" | awk '{print $5}')"

# Verify file integrity if possible
if command -v file >/dev/null 2>&1; then
    echo "File type: $(file "$OUTPUT_FILE")"
fi