# Compute Module - EC2 Instance and Key Pair for Hyperliquid Validator

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  module_tags = {
    Module = "compute"
  }
  
  tags = merge(var.tags, local.module_tags)
}

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

# Create cloud-init config with all scripts
locals {
  cloud_init_config = {
    write_files = [
      {
        path        = "/var/lib/cloud/instance/scripts/01-system-setup.sh"
        permissions = "0755"
        content     = file("${path.module}/templates/scripts/01-system-setup.sh")
      },
      {
        path        = "/var/lib/cloud/instance/scripts/02-storage-setup.sh"
        permissions = "0755"
        content     = file("${path.module}/templates/scripts/02-storage-setup.sh")
      },
      {
        path        = "/var/lib/cloud/instance/scripts/03-install-hl.sh"
        permissions = "0755"
        content     = file("${path.module}/templates/scripts/03-install-hl.sh")
      },
      {
        path        = "/var/lib/cloud/instance/scripts/04-configure-hl.sh"
        permissions = "0755"
        content     = file("${path.module}/templates/scripts/04-configure-hl.sh")
      },
      {
        path        = "/var/lib/cloud/instance/scripts/05-start-service.sh"
        permissions = "0755"
        content     = file("${path.module}/templates/scripts/05-start-service.sh")
      },
      {
        path        = "/var/lib/cloud/instance/scripts/06-monitoring-setup.sh"
        permissions = "0755"
        content     = file("${path.module}/templates/scripts/06-monitoring-setup.sh")
      },
      {
        path        = "/var/lib/cloud/instance/scripts/hl-pub-key.asc"
        permissions = "0644"
        content     = file("${path.module}/templates/scripts/hl-pub-key.asc")
      }
    ]
    
    runcmd = [
      ["bash", "-c", templatefile("${path.module}/templates/user_data.sh", {
        gossip_config_json   = jsonencode(var.gossip_config)
        enable_tcpdump       = var.enable_tcpdump
        write_trades         = var.write_trades
        write_order_statuses = var.write_order_statuses
        write_events         = var.write_events
        debug_mode           = var.debug_mode
      })]
    ]
  }
  
  user_data = "#cloud-config\n${yamlencode(local.cloud_init_config)}"
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

  user_data = local.user_data

  tags = merge(local.tags, {
    Name        = "${local.name_prefix}-validator"
    Description = "Hyperliquid validator node"
  })

  lifecycle {
    ignore_changes = [
      ami,  # Prevent recreation when new AMIs are released
    ]
  }
}