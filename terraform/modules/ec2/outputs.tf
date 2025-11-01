# =============================================================================
# EC2 Module Outputs
# =============================================================================

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.k3s_server.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.k3s_server.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.k3s_server.private_ip
}

output "instance_state" {
  description = "State of the EC2 instance"
  value       = aws_instance.k3s_server.instance_state
}

output "instance_arn" {
  description = "ARN of the EC2 instance"
  value       = aws_instance.k3s_server.arn
}
