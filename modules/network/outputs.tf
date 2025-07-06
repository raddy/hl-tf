output "security_group_id" {
  description = "ID of the security group created for the validator"
  value       = aws_security_group.validator.id
}

output "security_group_name" {
  description = "Name of the security group created for the validator"
  value       = aws_security_group.validator.name
}

output "placement_group_id" {
  description = "ID of the placement group for clustering"
  value       = aws_placement_group.this.id
}

output "placement_group_name" {
  description = "Name of the placement group"
  value       = aws_placement_group.this.name
}