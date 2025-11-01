# =============================================================================
# Security Module Outputs
# =============================================================================

output "security_group_id" {
  description = "ID of the K3s security group"
  value       = aws_security_group.k3s_node.id
}

output "security_group_name" {
  description = "Name of the K3s security group"
  value       = aws_security_group.k3s_node.name
}
