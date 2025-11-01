# =============================================================================
# IAM Module Outputs
# =============================================================================

output "iam_role_arn" {
  description = "ARN of the IAM role for K3s nodes"
  value       = aws_iam_role.k3s_node.arn
}

output "iam_role_name" {
  description = "Name of the IAM role for K3s nodes"
  value       = aws_iam_role.k3s_node.name
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.k3s_node.name
}

output "iam_instance_profile_arn" {
  description = "ARN of the IAM instance profile"
  value       = aws_iam_instance_profile.k3s_node.arn
}
