# =============================================================================
# IAM Role for K3s EC2 Instances
# =============================================================================
# IAM (Identity and Access Management) allows EC2 instances to access AWS
# services without hardcoded credentials. This is CRITICAL for security.

# =============================================================================
# IAM Role
# =============================================================================
# The role defines WHO can assume it (EC2 service in this case).
# Think of it as a "hat" that EC2 instances can wear to get permissions.

resource "aws_iam_role" "k3s_node" {
  name = "${var.project_name}-k3s-node-role"

  # Trust policy: allows EC2 service to "assume" (use) this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name      = "${var.project_name}-k3s-node-role"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# =============================================================================
# IAM Policy: CloudWatch Logs
# =============================================================================
# Allows K3s and your apps to send logs to CloudWatch for monitoring.
# CloudWatch is AWS's logging/monitoring service (free tier: 5GB/month).

resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "${var.project_name}-cloudwatch-logs-policy"
  role = aws_iam_role.k3s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",       # Create log groups for different apps
          "logs:CreateLogStream",      # Create log streams within groups
          "logs:PutLogEvents",         # Send actual log entries
          "logs:DescribeLogStreams"    # Query existing log streams
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/k3s/*"
      }
    ]
  })
}

# =============================================================================
# IAM Policy: EC2 Describe (for K3s Cloud Provider)
# =============================================================================
# K3s can integrate with AWS cloud provider to auto-provision Load Balancers,
# persistent volumes, etc. Requires EC2 describe permissions.

resource "aws_iam_role_policy" "ec2_describe" {
  name = "${var.project_name}-ec2-describe-policy"
  role = aws_iam_role.k3s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",      # Query instance information
          "ec2:DescribeRegions",        # List available AWS regions
          "ec2:DescribeVolumes",        # Query EBS volumes
          "ec2:DescribeSecurityGroups", # Query security groups
          "ec2:DescribeSubnets",        # Query subnet information
          "ec2:DescribeVpcs"            # Query VPC information
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# Attach AWS Managed Policy: SSM (Systems Manager)
# =============================================================================
# SSM allows connecting to EC2 via AWS Console without SSH keys.
# Great backup if you lose your SSH key or for additional security.
# This is a pre-built AWS policy (we don't define it, just attach it).

resource "aws_iam_role_policy_attachment" "ssm_managed_policy" {
  role       = aws_iam_role.k3s_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# =============================================================================
# Instance Profile
# =============================================================================
# Instance Profile is the "bridge" between IAM Role and EC2.
# EC2 instances don't use roles directly - they use instance profiles.
# Think of it as the "adapter" that connects the role to the instance.

resource "aws_iam_instance_profile" "k3s_node" {
  name = "${var.project_name}-k3s-node-profile"
  role = aws_iam_role.k3s_node.name

  tags = {
    Name      = "${var.project_name}-k3s-node-profile"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}
