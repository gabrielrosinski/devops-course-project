#!/bin/bash
# =============================================================================
# K3s Installation Script for EC2 Instance
# =============================================================================
# This script runs automatically when the EC2 instance first boots.
# It performs the following tasks:
# 1. Updates the operating system
# 2. Installs required dependencies
# 3. Installs K3s (lightweight Kubernetes)
# 4. Configures K3s for external access
# 5. Sets up kubectl access

set -e  # Exit on any error
set -x  # Print commands as they execute (useful for debugging in cloud-init logs)

# =============================================================================
# Variables (passed from Terraform)
# =============================================================================
K3S_VERSION="${k3s_version}"
K3S_TOKEN="${k3s_token}"

# =============================================================================
# Logging Setup
# =============================================================================
# All output goes to /var/log/k3s-install.log for troubleshooting
exec > >(tee /var/log/k3s-install.log)
exec 2>&1

echo "==================================================================="
echo "K3s Installation Started at $(date)"
echo "==================================================================="
echo "K3s Version: $K3S_VERSION"
echo "Instance Type: $(ec2-metadata --instance-type | cut -d ' ' -f 2)"
echo "Availability Zone: $(ec2-metadata --availability-zone | cut -d ' ' -f 2)"
echo "==================================================================="

# =============================================================================
# Step 1: System Updates
# =============================================================================
# Update package lists and upgrade existing packages.
# This ensures we have the latest security patches.

echo "[1/8] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# =============================================================================
# Step 2: Install Dependencies
# =============================================================================
# Install tools needed for K3s and general system management.

echo "[2/8] Installing dependencies..."
apt-get install -y \
    curl \
    wget \
    git \
    jq \
    unzip \
    htop \
    net-tools \
    ca-certificates \
    gnupg \
    lsb-release

# =============================================================================
# Step 3: Configure System for K3s
# =============================================================================
# Enable kernel modules and sysctl settings required by Kubernetes.

echo "[3/8] Configuring system for K3s..."

# Enable IP forwarding (required for pod networking)
cat <<EOF > /etc/sysctl.d/k3s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Load br_netfilter module (required for bridge networking)
modprobe br_netfilter
echo "br_netfilter" > /etc/modules-load.d/br_netfilter.conf

# Apply sysctl settings
sysctl --system

# =============================================================================
# Step 4: Install K3s
# =============================================================================
# Download and install K3s from official installation script.
# Configuration options:
# - INSTALL_K3S_VERSION: Specific K3s version to install
# - K3S_TOKEN: Cluster token (for joining additional nodes later)
# - --write-kubeconfig-mode 644: Makes kubeconfig readable by all users
# - --disable traefik: We'll use our own ingress later
# - --tls-san: Adds EC2 public IP to TLS certificate (for external kubectl)

echo "[4/8] Installing K3s $K3S_VERSION..."

# Get EC2 instance's public IP
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-ipv4)
PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/local-ipv4)
echo "Instance Public IP: $PUBLIC_IP"
echo "Instance Private IP: $PRIVATE_IP"

# Install K3s
curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION="$K3S_VERSION" \
    K3S_TOKEN="$K3S_TOKEN" \
    sh -s - server \
    --write-kubeconfig-mode 644 \
    --tls-san "$PUBLIC_IP" \
    --node-external-ip "$PUBLIC_IP" \
    --advertise-address "$PRIVATE_IP" \
    --flannel-backend=vxlan

# Wait for K3s to be ready
echo "Waiting for K3s to become ready..."
until systemctl is-active --quiet k3s; do
    echo "K3s not ready yet, waiting..."
    sleep 5
done

echo "K3s service is active!"

# =============================================================================
# Step 5: Configure kubectl for Ubuntu User
# =============================================================================
# Copy kubeconfig to ubuntu user's home directory for easy kubectl access.

echo "[5/8] Configuring kubectl for ubuntu user..."

mkdir -p /home/ubuntu/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube
chmod 600 /home/ubuntu/.kube/config

# Keep config using localhost - works for on-instance use and SSH tunneling
# No modifications needed!

# =============================================================================
# Step 6: Install Helm
# =============================================================================
# Helm is the package manager for Kubernetes - needed for deploying charts.

echo "[6/8] Installing Helm..."

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify Helm installation
helm version

echo "✅ Helm installed successfully"

# =============================================================================
# Step 7: Install kubectl Aliases and Tools
# =============================================================================
# Add helpful aliases for the ubuntu user.

echo "[7/8] Setting up kubectl aliases..."

cat <<'EOF' >> /home/ubuntu/.bashrc

# Kubectl aliases
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias ka='kubectl apply -f'
alias kl='kubectl logs'
alias ke='kubectl exec -it'

# K3s shortcuts
alias k3s-status='sudo systemctl status k3s'
alias k3s-logs='sudo journalctl -u k3s -f'

# Show cluster info on login
echo "==================================="
echo "K3s Cluster Information"
echo "==================================="
kubectl cluster-info
echo ""
kubectl get nodes
echo "==================================="
EOF

chown ubuntu:ubuntu /home/ubuntu/.bashrc

# =============================================================================
# Step 8: Download Deployment Configuration Files
# =============================================================================
# Download deployment script and all required config files from GitHub.
# This avoids cloning the entire repository.

echo "[8/8] Downloading deployment configuration files..."

# Create deployment config directory structure
mkdir -p /home/ubuntu/deploy_config/monitoring/helm-values
mkdir -p /home/ubuntu/deploy_config/monitoring/standalone
mkdir -p /home/ubuntu/deploy_config/argocd

# Download deployment script
echo "📥 Downloading deploy-apps.sh..."
curl -fsSL -o /home/ubuntu/deploy-apps.sh \
  https://raw.githubusercontent.com/gabrielrosinski/devops-course-project/main/terraform/deploy-apps.sh
chmod +x /home/ubuntu/deploy-apps.sh

# Download Prometheus Helm values
echo "📥 Downloading Prometheus configuration..."
curl -fsSL -o /home/ubuntu/deploy_config/monitoring/helm-values/prometheus-minimal-values.yaml \
  https://raw.githubusercontent.com/gabrielrosinski/devops-course-project/main/monitoring/helm-values/prometheus-minimal-values.yaml

curl -fsSL -o /home/ubuntu/deploy_config/monitoring/helm-values/alertmanager-values.yaml \
  https://raw.githubusercontent.com/gabrielrosinski/devops-course-project/main/monitoring/helm-values/alertmanager-values.yaml

# Download standalone monitoring configs
echo "📥 Downloading monitoring configurations..."
curl -fsSL -o /home/ubuntu/deploy_config/monitoring/standalone/prometheus-alerts.yaml \
  https://raw.githubusercontent.com/gabrielrosinski/devops-course-project/main/monitoring/standalone/prometheus-alerts.yaml

curl -fsSL -o /home/ubuntu/deploy_config/monitoring/standalone/grafana-dashboard.yaml \
  https://raw.githubusercontent.com/gabrielrosinski/devops-course-project/main/monitoring/standalone/grafana-dashboard.yaml

curl -fsSL -o /home/ubuntu/deploy_config/monitoring/standalone/servicemonitor.yaml \
  https://raw.githubusercontent.com/gabrielrosinski/devops-course-project/main/monitoring/standalone/servicemonitor.yaml

# Download ArgoCD application manifest
echo "📥 Downloading ArgoCD configuration..."
curl -fsSL -o /home/ubuntu/deploy_config/argocd/argocd.yaml \
  https://raw.githubusercontent.com/gabrielrosinski/devops-course-project/main/argocd/argocd.yaml

# Set ownership
chown -R ubuntu:ubuntu /home/ubuntu/deploy-apps.sh /home/ubuntu/deploy_config

echo "✅ All deployment files downloaded to /home/ubuntu/deploy_config"
echo "   Files ready:"
echo "   - deploy-apps.sh"
echo "   - 2 Helm values files"
echo "   - 3 monitoring configs"
echo "   - 1 ArgoCD manifest"

# =============================================================================
# Completion Message
# =============================================================================

echo "==================================================================="
echo "K3s Installation Completed Successfully at $(date)"
echo "==================================================================="
echo ""
echo "Cluster Information:"
echo "-------------------"
kubectl cluster-info
echo ""
echo "Node Status:"
echo "------------"
kubectl get nodes -o wide
echo ""
echo "System Pods:"
echo "------------"
kubectl get pods -A
echo ""
echo "Installed Tools:"
echo "----------------"
echo "kubectl: $(kubectl version --client --short 2>/dev/null || echo 'installed')"
echo "helm: $(helm version --short)"
echo ""
echo "==================================================================="
echo "To use kubectl ON this instance:"
echo "  kubectl get nodes"
echo ""
echo "To access the cluster remotely from your local machine:"
echo "  1. Set up SSH tunnel:"
echo "     ssh -L 6443:localhost:6443 -i <key> ubuntu@$PUBLIC_IP"
echo "  2. Copy config and use it:"
echo "     scp -i <key> ubuntu@$PUBLIC_IP:~/.kube/config ~/.kube/k3s-config"
echo "     export KUBECONFIG=~/.kube/k3s-config"
echo "     kubectl get nodes"
echo ""
echo "To deploy applications, run: ./deploy-apps.sh"
echo "==================================================================="
