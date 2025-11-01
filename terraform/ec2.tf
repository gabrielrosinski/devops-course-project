# =============================================================================
# EC2 Instance for K3s Cluster
# =============================================================================
# This creates the actual virtual machine that will run K3s.

resource "aws_instance" "k3s_server" {
  ami           = var.ami_id  # Ubuntu Server 24.04 LTS
  instance_type = var.instance_type  # t2.micro for free tier
  key_name      = var.key_name  # Your SSH key for access

  # ============================================================================
  # Network Configuration
  # ============================================================================
  # Places instance in first public subnet with automatic public IP.
  # Security group controls what traffic is allowed in/out.

  subnet_id                   = aws_subnet.public_1.id
  vpc_security_group_ids      = [aws_security_group.k3s_node.id]
  associate_public_ip_address = true  # Ensures instance gets public IP

  # ============================================================================
  # IAM Instance Profile
  # ============================================================================
  # Attaches IAM role we created - gives instance permissions to access
  # AWS services (CloudWatch, ECR, etc.) without hardcoded credentials.

  iam_instance_profile = aws_iam_instance_profile.k3s_node.name

  # ============================================================================
  # Storage Configuration
  # ============================================================================
  # 20 GB general purpose SSD (free tier includes 30 GB).
  # gp3 is newer, faster, and same price as gp2.
  # delete_on_termination = true → disk deleted when instance terminated.

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true  # Always encrypt for security

    tags = {
      Name      = "${var.project_name}-root-volume"
      Project   = var.project_name
      ManagedBy = "Terraform"
    }
  }

  # ============================================================================
  # User Data Script - Automated K3s Installation
  # ============================================================================
  # This script runs ONCE when instance first boots.
  # It updates the OS, installs K3s, and configures it.

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    k3s_version = var.k3s_version
    k3s_token   = var.k3s_token
  }))

  # ============================================================================
  # Metadata Options (Security Hardening)
  # ============================================================================
  # IMDSv2 (Instance Metadata Service v2) is more secure.
  # Prevents SSRF attacks that could steal IAM credentials.

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # Enforce IMDSv2
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # ============================================================================
  # Monitoring
  # ============================================================================
  # Basic monitoring is free (5-minute intervals).
  # Detailed monitoring costs extra (1-minute intervals) - we skip it.

  monitoring = false  # Use free basic monitoring

  # ============================================================================
  # Tags
  # ============================================================================
  # Important for organization, cost tracking, and K3s cloud provider.

  tags = {
    Name                                        = "${var.project_name}-k3s-server"
    Project                                     = var.project_name
    ManagedBy                                   = "Terraform"
    Role                                        = "k3s-server"
    "kubernetes.io/cluster/${var.project_name}" = "owned"  # For K3s cloud provider
  }

  # ============================================================================
  # Lifecycle Rules
  # ============================================================================
  # create_before_destroy = false → destroy old instance before creating new.
  # This avoids hitting free tier limits (2 instances at once).

  lifecycle {
    create_before_destroy = false
    ignore_changes = [
      ami,  # Don't recreate if AMI ID changes (allows manual updates)
      user_data  # Don't recreate if user_data changes after initial boot
    ]
  }
}

# =============================================================================
# Elastic IP (Optional - Currently Commented Out)
# =============================================================================
# Elastic IP provides a static public IP that persists across reboots/restarts.
# Without it, you get a new public IP each time instance stops/starts.
#
# FREE TIER: Free if attached to running instance. $0.005/hr if unattached.
#
# Uncomment below if you want a static IP:

# resource "aws_eip" "k3s_server" {
#   instance = aws_instance.k3s_server.id
#   domain   = "vpc"
#
#   tags = {
#     Name      = "${var.project_name}-k3s-eip"
#     Project   = var.project_name
#     ManagedBy = "Terraform"
#   }
#
#   depends_on = [aws_internet_gateway.main]
# }
