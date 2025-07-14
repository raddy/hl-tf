# AWS Configuration
variable "aws_region" {
  description = "AWS region where the validator node will be deployed"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "ID of the VPC where the validator node will be deployed"
  type        = string
}

variable "public_subnet_id" {
  description = "ID of the public subnet for the validator node"
  type        = string
}

# Instance Configuration
variable "instance_type" {
  description = "EC2 instance type for the validator node"
  type        = string
  default     = "c6i.4xlarge"
  
  validation {
    condition = can(regex("^(c6i|c6a|c5|c5n|m6i|m6a|m5)\\.(2x|4x|8x|16x|24x|32x)large$", var.instance_type))
    error_message = "Instance type must be a compute-optimized instance with at least 8 vCPUs. Recommended: c6i.4xlarge or larger."
  }
}

variable "public_key_path" {
  description = "Path to SSH public key file for EC2 instance access"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed SSH access to the instance. Must be specified for security."
  type        = list(string)
  validation {
    condition     = length(var.allowed_ssh_cidr_blocks) > 0
    error_message = "At least one CIDR block must be specified for SSH access. Use your IP/32 for single IP access."
  }
}

# Storage Configuration
variable "root_volume_gb" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 50
  
  validation {
    condition     = var.root_volume_gb >= 20 && var.root_volume_gb <= 1000
    error_message = "Root volume size must be between 20GB and 1000GB."
  }
}

variable "data_volume_gb" {
  description = "Size of the data EBS volume in GB (Hyperliquid generates ~100-200GB/day)"
  type        = number
  default     = 500
  
  validation {
    condition     = var.data_volume_gb >= 100 && var.data_volume_gb <= 16000
    error_message = "Data volume size must be between 100GB and 16TB. Recommended minimum: 500GB for production use."
  }
}

# Logging Configuration
variable "enable_tcpdump" {
  description = "Enable continuous tcpdump capture (for research/debugging)"
  type        = bool
  default     = false
}

variable "write_trades" {
  description = "Enable writing trade data logs"
  type        = bool
  default     = false
}

variable "write_order_statuses" {
  description = "Enable writing order status logs"
  type        = bool
  default     = false
}

variable "write_events" {
  description = "Enable writing misc event logs"
  type        = bool
  default     = false
}

variable "debug_mode" {
  description = "Enable debug mode (prevents auto-shutdown on failure)"
  type        = bool
  default     = false
}

# Backup Configuration
variable "enable_backup" {
  description = "Enable continuous backup to S3"
  type        = bool
  default     = false
}

# Project Configuration
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "hyperliquid"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "main"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Hyperliquid Configuration
variable "hyperliquid_root_nodes" {
  description = "List of Hyperliquid root node IP addresses for peer discovery"
  type        = list(string)
  default = [
    "20.188.6.225",
    "74.226.182.22", 
    "180.189.55.18",
    "46.105.222.166"
  ]
  
  validation {
    condition     = length(var.hyperliquid_root_nodes) >= 1
    error_message = "At least one root node IP must be specified."
  }
  
  validation {
    condition = alltrue([
      for ip in var.hyperliquid_root_nodes : can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", ip))
    ])
    error_message = "All root node entries must be valid IPv4 addresses."
  }
}

variable "hyperliquid_chain" {
  description = "Hyperliquid chain to connect to"
  type        = string
  default     = "Mainnet"
  
  validation {
    condition     = contains(["Mainnet", "Testnet"], var.hyperliquid_chain)
    error_message = "Chain must be either 'Mainnet' or 'Testnet'."
  }
}