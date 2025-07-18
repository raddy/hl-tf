locals {
  bucket_name = "${var.project_name}-scripts-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "scripts" {
  bucket = local.bucket_name

  # Tags removed temporarily due to IAM permissions
  # tags = {
  #   Name        = "Hyperliquid Scripts"
  #   Project     = var.project_name
  #   Environment = var.environment
  # }
}

resource "aws_s3_bucket_versioning" "scripts" {
  bucket = aws_s3_bucket.scripts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "scripts" {
  bucket = aws_s3_bucket.scripts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "scripts" {
  bucket = aws_s3_bucket.scripts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

locals {
  scripts = {
    "01-system-setup.sh"     = file("${path.module}/templates/scripts/01-system-setup.sh")
    "02-storage-setup.sh"    = file("${path.module}/templates/scripts/02-storage-setup.sh")
    "03-install-hl.sh"       = file("${path.module}/templates/scripts/03-install-hl.sh")
    "04-configure-hl.sh"     = file("${path.module}/templates/scripts/04-configure-hl.sh")
    "05-start-service.sh"    = file("${path.module}/templates/scripts/05-start-service.sh")
    "06-monitoring-setup.sh" = file("${path.module}/templates/scripts/06-monitoring-setup.sh")
    "07-backup-setup.sh"     = var.enable_backup ? file("${path.module}/templates/scripts/07-backup-setup.sh") : ""
    "hl-backup.sh"           = var.enable_backup ? file("${path.module}/templates/scripts/hl-backup.sh") : ""
    "hl-backup-sweep.sh"     = var.enable_backup ? file("${path.module}/templates/scripts/hl-backup-sweep.sh") : ""
    "hl-reassemble-chunks.sh" = var.enable_backup ? file("${path.module}/templates/scripts/hl-reassemble-chunks.sh") : ""
    "tcpdump-wrapper.sh"     = var.enable_tcpdump ? file("${path.module}/templates/scripts/tcpdump-wrapper.sh") : ""
  }
}

resource "aws_s3_object" "scripts" {
  for_each = { for k, v in local.scripts : k => v if v != "" }

  bucket  = aws_s3_bucket.scripts.id
  key     = "scripts/latest/${each.key}"
  content = each.value
  etag    = md5(each.value)
}

resource "aws_s3_object" "hl_pub_key" {
  bucket  = aws_s3_bucket.scripts.id
  key     = "config/hl-pub-key.asc"
  content = file("${path.module}/templates/scripts/hl-pub-key.asc")
}

resource "aws_s3_object" "manifest" {
  bucket  = aws_s3_bucket.scripts.id
  key     = "scripts/latest/manifest.json"
  content = jsonencode({
    version      = var.scripts_version
    release_date = timestamp()
    scripts = {
      for name, content in local.scripts : name => {
        sha256 = sha256(content)
        size   = length(content)
      }
    }
  })
}

data "aws_caller_identity" "current" {}