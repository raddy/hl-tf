# Import blocks for existing S3 buckets
# This file helps handle existing buckets by importing them into Terraform state

# Import existing backup bucket if it exists
# This is conditional and will only import if the bucket exists
# To use this, run: terraform plan -generate-config-out=generated.tf

# The import blocks will be activated only when needed
# Users can uncomment these when they need to import existing buckets

# import {
#   to = aws_s3_bucket.backup
#   id = "hyperliquid-backup-916965752025"  # Replace with actual bucket name
# }

# import {
#   to = aws_s3_bucket.backup_state
#   id = "hyperliquid-backup-916965752025-state"  # Replace with actual bucket name
# }