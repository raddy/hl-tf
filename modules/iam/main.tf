locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# IAM role for EC2 instance
resource "aws_iam_role" "instance" {
  name = "${local.name_prefix}-instance"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Policy for S3 script access
resource "aws_iam_role_policy" "s3_scripts" {
  name = "${local.name_prefix}-s3-scripts"
  role = aws_iam_role.instance.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.scripts_bucket_arn,
          "${var.scripts_bucket_arn}/*"
        ]
      }
    ]
  })
}

# Policy for S3 backup access - only created if backup is enabled
resource "aws_iam_role_policy" "s3_backup" {
  count = var.backup_enabled ? 1 : 0
  
  name = "${local.name_prefix}-s3-backup"
  role = aws_iam_role.instance.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          var.backup_bucket_arn,
          "${var.backup_bucket_arn}/*",
          var.backup_state_bucket_arn,
          "${var.backup_state_bucket_arn}/*"
        ]
      }
    ]
  })
}

# Policy for EC2 tags (needed for backup script to read bucket name)
resource "aws_iam_role_policy" "ec2_tags" {
  name = "${local.name_prefix}-ec2-tags"
  role = aws_iam_role.instance.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance profile
resource "aws_iam_instance_profile" "instance" {
  name = "${local.name_prefix}-instance"
  role = aws_iam_role.instance.name
}