variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "scripts_bucket_arn" {
  description = "ARN of the S3 scripts bucket"
  type        = string
}

variable "backup_enabled" {
  description = "Whether backup is enabled"
  type        = bool
  default     = false
}

variable "backup_bucket_arn" {
  description = "ARN of the S3 backup bucket"
  type        = string
  default     = ""
}

variable "backup_state_bucket_arn" {
  description = "ARN of the S3 backup state bucket"
  type        = string
  default     = ""
}