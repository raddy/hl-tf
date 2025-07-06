output "instance_id" {
  description = "ID of the EC2 instance"
  value       = module.compute.instance_id
}

output "public_ip" {
  description = "Public IP address of the node"
  value       = module.compute.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh ubuntu@${module.compute.public_ip}"
}

output "setup_commands" {
  description = "Commands to run after SSHing in"
  value = {
    check_status = "sudo systemctl status hl-node"
    view_logs    = "sudo journalctl -u hl-node -f"
    check_data   = "df -h /var/hl && ls -la /var/hl/"
  }
}

output "deployment_info" {
  description = "Deployment summary"
  value = <<-EOT
    Instance deployed successfully!
    
    Instance ID: ${module.compute.instance_id}
    Public IP: ${module.compute.public_ip}
    
    SSH Command: ssh ubuntu@${module.compute.public_ip}
    
    Note: If instance is stopped, check /var/log/user-data.log for setup errors.
  EOT
}