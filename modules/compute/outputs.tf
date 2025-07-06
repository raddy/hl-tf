output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.validator.id
}

output "instance_arn" {
  description = "ARN of the EC2 instance"
  value       = aws_instance.validator.arn
}

output "public_ip" {
  description = "Public IP address of the instance"
  value       = aws_instance.validator.public_ip
}

output "private_ip" {
  description = "Private IP address of the instance"
  value       = aws_instance.validator.private_ip
}

output "public_dns" {
  description = "Public DNS name of the instance"
  value       = aws_instance.validator.public_dns
}

output "key_pair_name" {
  description = "Name of the SSH key pair"
  value       = aws_key_pair.validator.key_name
}

output "root_volume_id" {
  description = "ID of the root EBS volume"
  value       = aws_instance.validator.root_block_device[0].volume_id
}

output "data_volume_id" {
  description = "ID of the data EBS volume"
  value       = [for vol in aws_instance.validator.ebs_block_device : vol.volume_id if vol.device_name == var.data_volume_device_name][0]
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh ubuntu@${aws_instance.validator.public_ip}"
}

output "status_commands" {
  description = "Useful commands for checking node status"
  value = {
    service_status = "sudo systemctl status hl-node"
    view_logs      = "sudo journalctl -u hl-node -f"
    node_status    = "curl localhost:4000/status"
    disk_usage     = "df -h /var/hl"
  }
}