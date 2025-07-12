# Compute Module - EC2 Instance and Key Pair for Hyperliquid Validator

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  module_tags = {
    Module = "compute"
  }
  
  tags = merge(var.tags, local.module_tags)
}

data "aws_region" "current" {}

# Get the latest Ubuntu 24.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# SSH Key Pair
resource "aws_key_pair" "validator" {
  key_name   = "${local.name_prefix}-validator"
  public_key = file(var.public_key_path)

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-validator"
  })
}


# EC2 Instance
resource "aws_instance" "validator" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.validator.key_name
  vpc_security_group_ids = var.security_group_ids
  subnet_id              = var.subnet_id
  placement_group        = var.placement_group_id
  
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
    encrypted             = true
    
    tags = merge(local.tags, {
      Name = "${local.name_prefix}-root"
      Type = "root"
    })
  }

  ebs_block_device {
    device_name           = var.data_volume_device_name
    volume_type           = "gp3"
    volume_size           = var.data_volume_size
    iops                  = 3000
    throughput            = 125
    delete_on_termination = false  # Preserve data on instance termination
    encrypted             = true
    
    tags = merge(local.tags, {
      Name = "${local.name_prefix}-data"
      Type = "data"
    })
  }

  user_data = templatefile("${path.module}/templates/bootstrap.sh", {
    scripts_bucket         = var.scripts_bucket_name
    scripts_version        = var.scripts_version
    aws_region            = data.aws_region.current.name
    ebs_volume_size       = var.data_volume_size
    write_trades          = var.write_trades
    write_events          = var.write_events  
    write_order_statuses  = var.write_order_statuses
    enable_tcpdump        = var.enable_tcpdump
    debug_mode            = var.debug_mode
    gossip_config         = jsonencode(var.gossip_config)
  })
  
  iam_instance_profile = var.iam_instance_profile_name
  
  # Enable both IMDSv1 and IMDSv2 for compatibility
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"  # Allow both v1 and v2
    http_put_response_hop_limit = 1
  }

  tags = merge(local.tags, {
    Name         = "${local.name_prefix}-validator"
    Description  = "Hyperliquid validator node"
    BackupBucket = var.backup_bucket_name != "" ? var.backup_bucket_name : "none"
  })

  lifecycle {
    ignore_changes = [
      ami,  # Prevent recreation when new AMIs are released
    ]
  }
}