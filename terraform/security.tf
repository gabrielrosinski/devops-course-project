# =============================================================================
# Security Groups for K3s Cluster
# =============================================================================
# Security Groups act as virtual firewalls controlling inbound/outbound traffic.
# Each rule defines: protocol, port range, and source/destination.

resource "aws_security_group" "k3s_node" {
  name        = "${var.project_name}-k3s-node-sg"
  description = "Security group for K3s nodes with public web access"
  vpc_id      = aws_vpc.main.id

  # ===========================================================================
  # SSH Access (Port 22)
  # ===========================================================================
  # Allows you to connect to the instance for management.
  # SECURITY: Restricted to your IP only (change var.allowed_ssh_cidr).

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
  # Kubernetes API endpoint - allows kubectl commands from your machine.
  # SECURITY: Restricted to your IP only. Don't open to 0.0.0.0/0!

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
  # For your QuakeWatch web application.
  # Open to the world (0.0.0.0/0) so users can access your app.

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
  # For secure HTTPS when you add SSL certificates later.
  # Open to the world (0.0.0.0/0).

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
  # K3s NodePort services expose apps on these ports.
  # Your QuakeWatch app will likely use a port in this range.
  # Open to the world for public app access.

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
  # Flannel is K3s's default CNI (Container Network Interface).
  # Creates overlay network for pod-to-pod communication.
  # INTERNAL ONLY: Only from within VPC (10.0.0.0/16).

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
  # Kubelet is the agent running on each node that manages pods.
  # K3s API server talks to kubelet on this port.
  # INTERNAL ONLY: Only from within VPC.

  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # ===========================================================================
  # Kubelet Metrics (Port 10255) - Optional
  # ===========================================================================
  # Read-only kubelet API for metrics.
  # Used by monitoring tools like Prometheus.
  # INTERNAL ONLY: Only from within VPC.

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
  # Port 10251: K3s scheduler metrics
  # Port 10252: K3s controller manager metrics
  # INTERNAL ONLY: Only from within VPC.

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
  # Metrics server provides CPU/memory usage for pods.
  # Used by kubectl top and Horizontal Pod Autoscaler.
  # INTERNAL ONLY: Only from within VPC.

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
  # Allow ALL outbound traffic (required for):
  # - Downloading K3s installation
  # - Pulling Docker images from Docker Hub/ECR
  # - Fetching earthquake data from USGS API
  # - OS updates (apt update/upgrade)
  # - DNS queries

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # -1 means ALL protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${var.project_name}-k3s-node-sg"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}
