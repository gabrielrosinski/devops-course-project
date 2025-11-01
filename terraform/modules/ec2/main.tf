# =============================================================================
# EC2 Module - K3s Server Instance
# =============================================================================
# Creates EC2 instance for K3s cluster

resource "aws_instance" "k3s_server" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  # Network Configuration
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids
  associate_public_ip_address = true

  # IAM Instance Profile
  iam_instance_profile = var.iam_instance_profile_name

  # Storage Configuration
  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true

    tags = merge(
      var.tags,
      {
        Name = "${var.project_name}-root-volume"
      }
    )
  }

  # User Data Script - Automated K3s Installation
  user_data = base64encode(templatefile("${var.user_data_script_path}", {
    k3s_version = var.k3s_version
    k3s_token   = var.k3s_token
  }))

  # Metadata Options (Security Hardening)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # Monitoring
  monitoring = false

  # Tags
  tags = merge(
    var.tags,
    {
      Name                         = "${var.project_name}-k3s-server"
      Role                         = "k3s-server"
      "KubernetesCluster"          = var.project_name
      "kubernetes.io-cluster-name" = var.project_name
      "kubernetes.io-cluster-role" = "owned"
    }
  )

  # Lifecycle Rules
  lifecycle {
    create_before_destroy = false
    ignore_changes = [
      ami,
      user_data
    ]
  }
}
