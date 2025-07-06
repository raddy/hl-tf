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

# Network Module - Security Groups and Placement Group
module "network" {
  source = "./modules/network"
  
  project_name = "hl-node"
  environment  = "main"
  vpc_id       = var.vpc_id
  tags         = {}
}

# Compute Module - EC2 Instance
module "compute" {
  source = "./modules/compute"
  
  project_name       = "hl-node"
  environment        = "main"
  subnet_id          = var.public_subnet_id
  security_group_ids = [module.network.security_group_id]
  placement_group_id = module.network.placement_group_id
  instance_type      = var.instance_type
  public_key_path    = var.public_key_path
  root_volume_size   = var.root_volume_gb
  data_volume_size   = var.data_volume_gb
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
  tags                 = {}
}