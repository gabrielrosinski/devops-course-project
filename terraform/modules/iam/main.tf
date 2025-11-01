# =============================================================================
# IAM Module - Roles and Policies for K3s Nodes
# =============================================================================
# Creates IAM role with necessary permissions for K3s EC2 instances

# =============================================================================
# IAM Role
# =============================================================================

resource "aws_iam_role" "k3s_node" {
  name = "${var.project_name}-k3s-node-role"

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

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-k3s-node-role"
    }
  )
}

# =============================================================================
# IAM Policy: CloudWatch Logs
# =============================================================================

resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "${var.project_name}-cloudwatch-logs-policy"
  role = aws_iam_role.k3s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/k3s/*"
      }
    ]
  })
}

# =============================================================================
# IAM Policy: EC2 Describe (for K3s Cloud Provider)
# =============================================================================

resource "aws_iam_role_policy" "ec2_describe" {
  name = "${var.project_name}-ec2-describe-policy"
  role = aws_iam_role.k3s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "ec2:DescribeVolumes",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# Attach AWS Managed Policy: SSM (Systems Manager)
# =============================================================================

resource "aws_iam_role_policy_attachment" "ssm_managed_policy" {
  role       = aws_iam_role.k3s_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# =============================================================================
# Instance Profile
# =============================================================================

resource "aws_iam_instance_profile" "k3s_node" {
  name = "${var.project_name}-k3s-node-profile"
  role = aws_iam_role.k3s_node.name

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-k3s-node-profile"
    }
  )
}
