# Backup Module - S3 bucket and policies for continuous data backup

locals {
  bucket_name = "${var.project_name}-backup-${data.aws_caller_identity.current.account_id}"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "backup" {
  bucket = local.bucket_name
  
  # Tags removed temporarily due to IAM permissions
  # tags = {
  #   Name        = "Hyperliquid Data Backup"
  #   Project     = var.project_name
  #   Environment = var.environment
  # }
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    id     = "archive_old_data"
    status = "Enabled"
    
    filter {}  # Apply to all objects

    transition {
      days          = 30
      storage_class = "GLACIER_IR"
    }
    
    transition {
      days          = 180
      storage_class = "DEEP_ARCHIVE"
    }
  }
  
  rule {
    id     = "delete_old_pcaps"
    status = "Enabled"
    
    filter {
      prefix = "pcaps/"
    }
    
    expiration {
      days = 180  # Keep pcaps for 6 months only
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket for storing backup state and locks
resource "aws_s3_bucket" "backup_state" {
  bucket = "${local.bucket_name}-state"
  
  # Tags removed temporarily due to IAM permissions
  # tags = {
  #   Name        = "Hyperliquid Backup State"
  #   Project     = var.project_name
  #   Environment = var.environment
  # }
}

resource "aws_s3_bucket_public_access_block" "backup_state" {
  bucket = aws_s3_bucket.backup_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}