# =============================================================================
# Security Module - Security Groups
# =============================================================================
# Creates security groups for K3s cluster nodes

resource "aws_security_group" "k3s_node" {
  name        = "${var.project_name}-k3s-node-sg"
  description = "Security group for K3s nodes with public web access"
  vpc_id      = var.vpc_id

  # ===========================================================================
  # SSH Access (Port 22)
  # ===========================================================================
  ingress {
    description = "SSH access from your IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # ===========================================================================
  # K3s API Server (Port 6443)
  # ===========================================================================
  ingress {
    description = "K3s API server for kubectl access"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # ===========================================================================
  # HTTP (Port 80) - Public Web Access
  # ===========================================================================
  ingress {
    description = "HTTP access for web application"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ===========================================================================
  # HTTPS (Port 443) - Future SSL
  # ===========================================================================
  ingress {
    description = "HTTPS access for secure web application"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ===========================================================================
  # NodePort Range (30000-32767)
  # ===========================================================================
  ingress {
    description = "K3s NodePort services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ===========================================================================
  # Flannel VXLAN (Port 8472 UDP)
  # ===========================================================================
  ingress {
    description = "Flannel VXLAN for pod networking"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  # ===========================================================================
  # Kubelet API (Port 10250)
  # ===========================================================================
  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # ===========================================================================
  # Kubelet Metrics (Port 10255)
  # ===========================================================================
  ingress {
    description = "Kubelet read-only metrics"
    from_port   = 10255
    to_port     = 10255
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # ===========================================================================
  # K3s Server (Port 10251-10252)
  # ===========================================================================
  ingress {
    description = "K3s scheduler and controller metrics"
    from_port   = 10251
    to_port     = 10252
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # ===========================================================================
  # K3s Metrics Server (Port 10443)
  # ===========================================================================
  ingress {
    description = "K3s metrics server"
    from_port   = 10443
    to_port     = 10443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # ===========================================================================
  # Egress (Outbound) Rules
  # ===========================================================================
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-k3s-node-sg"
    }
  )
}
