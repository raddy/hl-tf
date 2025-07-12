variable "scripts_version" {
  description = "Version of the scripts"
  type        = string
  default     = "1.0.0"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "hl-node"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "main"
}

variable "enable_backup" {
  description = "Enable continuous backup to S3"
  type        = bool
  default     = false
}

variable "enable_tcpdump" {
  description = "Enable continuous tcpdump capture (for research/debugging)"
  type        = bool
  default     = false
}