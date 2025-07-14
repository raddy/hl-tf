# Hyperliquid Non-Validator Node Deployment

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_subnet" "selected" {
  id = var.public_subnet_id
}

# Scripts Module - S3 bucket for scripts
module "scripts" {
  source = "./modules/scripts"
  
  project_name    = var.project_name
  environment     = var.environment
  scripts_version = "1.0.0"
  enable_backup   = var.enable_backup
  enable_tcpdump  = var.enable_tcpdump
}

# Backup Module - S3 buckets for continuous backup
module "backup" {
  source = "./modules/backup"
  count  = var.enable_backup ? 1 : 0
  
  project_name = var.project_name
  environment  = var.environment
}

# IAM Module - Roles and permissions
module "iam" {
  source = "./modules/iam"
  
  project_name            = var.project_name
  environment             = var.environment
  scripts_bucket_arn      = module.scripts.scripts_bucket_arn
  backup_enabled          = var.enable_backup
  backup_bucket_arn       = var.enable_backup ? module.backup[0].backup_bucket_arn : ""
  backup_state_bucket_arn = var.enable_backup ? module.backup[0].backup_state_bucket_arn : ""
}

# Network Module - Security Groups and Placement Group
module "network" {
  source = "./modules/network"
  
  project_name            = var.project_name
  environment             = var.environment
  vpc_id                  = var.vpc_id
  allowed_ssh_cidr_blocks = var.allowed_ssh_cidr_blocks
  tags                    = var.tags
}

# Compute Module - EC2 Instance
module "compute" {
  source = "./modules/compute"
  
  project_name              = var.project_name
  environment               = var.environment
  subnet_id                 = var.public_subnet_id
  security_group_ids        = [module.network.security_group_id]
  placement_group_id        = module.network.placement_group_id
  instance_type             = var.instance_type
  public_key_path           = var.public_key_path
  root_volume_size          = var.root_volume_gb
  data_volume_size          = var.data_volume_gb
  scripts_bucket_name       = module.scripts.scripts_bucket_name
  scripts_version           = "latest"  # Override with specific version in production
  iam_instance_profile_name = module.iam.instance_profile_name
  backup_bucket_name        = var.enable_backup ? module.backup[0].backup_bucket_name : ""
  gossip_config = {
    chain = "Mainnet"
    root_node_ips = [
      { Ip = "20.188.6.225" },
      { Ip = "74.226.182.22" },
      { Ip = "180.189.55.18" },
      { Ip = "46.105.222.166" }
    ]
    try_new_peers = true
  }
  enable_tcpdump       = var.enable_tcpdump
  write_trades         = var.write_trades
  write_order_statuses = var.write_order_statuses
  write_events         = var.write_events
  debug_mode           = var.debug_mode
  tags                 = var.tags
}