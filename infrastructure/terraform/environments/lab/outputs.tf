##############################################################################
# Terraform Outputs - Lab Environment
##############################################################################

output "vm_public_ip" {
  description = "Public IP address of the VM"
  value       = module.vm.public_ip_address
}

output "vm_private_ip" {
  description = "Private IP address of the VM"
  value       = module.vm.private_ip_address
}

output "vm_name" {
  description = "Name of the VM"
  value       = module.vm.vm_name
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = "ssh ${module.vm.admin_username}@${module.vm.public_ip_address}"
}
