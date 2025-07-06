# Network Module - Security Groups and Placement Group for Hyperliquid Validator

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  module_tags = {
    Module = "network"
  }
  
  tags = merge(var.tags, local.module_tags)
}

# Placement Group for low-latency clustering
resource "aws_placement_group" "this" {
  name     = "${local.name_prefix}-cluster"
  strategy = "cluster"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-cluster"
    Description = "Placement group for Hyperliquid validator nodes"
  })
}

# Security Group for Hyperliquid Validator
resource "aws_security_group" "validator" {
  name        = "${local.name_prefix}-validator-sg"
  description = "Security group for Hyperliquid validator node - controls protocol and management access"
  vpc_id      = var.vpc_id

  # Hyperliquid validator protocol ports
  ingress {
    description = "Hyperliquid validator ports"
    from_port   = 4000
    to_port     = 4010
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # TODO: Restrict this to your IP
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = merge(local.tags, {
    Name = "${local.name_prefix}-validator-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}