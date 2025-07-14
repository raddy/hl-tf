variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., main, test, dev)"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet where the instance will be launched"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs to attach to the instance"
  type        = list(string)
}

variable "placement_group_id" {
  description = "ID of the placement group for the instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the validator node"
  type        = string
  default     = "c6i.4xlarge"  # Bigger default to avoid memory issues
}

variable "public_key_path" {
  description = "Path to the public SSH key file"
  type        = string
  
  validation {
    condition     = can(file(var.public_key_path))
    error_message = "Public key file must exist at the specified path"
  }
}

variable "root_volume_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 30
  
  validation {
    condition     = var.root_volume_size >= 20
    error_message = "Root volume must be at least 20 GB"
  }
}

variable "data_volume_size" {
  description = "Size of the data volume in GB"
  type        = number
  default     = 100
  
  validation {
    condition     = var.data_volume_size >= 50
    error_message = "Data volume must be at least 50 GB"
  }
}

variable "data_volume_device_name" {
  description = "Device name for the data volume"
  type        = string
  default     = "/dev/sdf"
}



variable "gossip_config" {
  description = "Override gossip configuration for the node"
  type = object({
    chain = string
    root_node_ips = list(object({
      Ip = string
    }))
    try_new_peers = bool
  })
}

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
  description = "Enable writing event logs"
  type        = bool
  default     = false
}

variable "debug_mode" {
  description = "Enable debug mode (prevents auto-shutdown on failure)"
  type        = bool
  default     = false
}

variable "scripts_bucket_name" {
  description = "S3 bucket containing the scripts"
  type        = string
}

variable "scripts_version" {
  description = "Version of scripts to use"
  type        = string
  default     = "latest"
}

variable "iam_instance_profile_name" {
  description = "IAM instance profile name"
  type        = string
}

variable "backup_bucket_name" {
  description = "S3 bucket name for backups"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}