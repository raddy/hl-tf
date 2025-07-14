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
}

variable "data_volume_gb" {
  description = "Size of the data EBS volume in GB (Hyperliquid generates ~100-200GB/day)"
  type        = number
  default     = 500
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