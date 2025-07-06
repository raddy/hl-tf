variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., main, test, dev)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where resources will be created"
  type        = string
}




variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}