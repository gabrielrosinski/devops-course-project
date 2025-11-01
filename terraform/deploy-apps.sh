#!/bin/bash
# =============================================================================
# Application Deployment Script for AWS K3s Cluster
# =============================================================================
# This script deploys the QuakeWatch application and monitoring stack to your
# AWS K3s cluster. Run this AFTER Terraform has created the infrastructure.
#
# Usage:
#   1. SSH to your EC2 instance
#   2. Run: ./deploy-apps.sh
#
# What it deploys:
#   - Prometheus & Grafana (monitoring)
#   - ArgoCD (GitOps deployment)
#   - QuakeWatch application (via ArgoCD)

set -e  # Exit on any error

echo "🚀 QuakeWatch Application Deployment Script"
echo "============================================="
echo ""

# =============================================================================
# Pre-flight Checks
# =============================================================================

echo "🔍 Running pre-flight checks..."

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
  echo "❌ kubectl not found. Please ensure K3s is installed."
  exit 1
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
  echo "❌ Helm not found. Please ensure Helm is installed."
  exit 1
fi

# Check if K3s cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
  echo "❌ Cannot connect to K3s cluster. Is K3s running?"
  echo "   Check: sudo systemctl status k3s"
  exit 1
fi

echo "✅ Pre-flight checks passed"
echo ""

# =============================================================================
# Step 1: Install Prometheus & Grafana Monitoring Stack
# =============================================================================

echo "📊 [1/3] Installing Prometheus & Grafana Monitoring Stack..."
echo "-------------------------------------------------------------"

# Add Prometheus Helm repository
if ! helm repo list | grep -q prometheus-community; then
  echo "📦 Adding prometheus-community Helm repository..."
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo update
else
  echo "✅ prometheus-community repo already added"
fi

# Create monitoring namespace if it doesn't exist
if ! kubectl get namespace monitoring &> /dev/null; then
  echo "📦 Creating monitoring namespace..."
  kubectl create namespace monitoring
fi

# Check if kube-prometheus-stack is already installed
if ! helm list -n monitoring | grep -q kube-prometheus-stack; then
  echo "📥 Installing kube-prometheus-stack (this may take 3-5 minutes)..."
  helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
    --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
    --wait --timeout=10m

  echo "✅ Prometheus & Grafana installed successfully"
else
  echo "✅ kube-prometheus-stack already installed, skipping"
fi

# Wait for Prometheus CRDs to be ready
echo "⏳ Waiting for Prometheus CRDs to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if kubectl get crd servicemonitors.monitoring.coreos.com &>/dev/null && \
     kubectl get crd prometheusrules.monitoring.coreos.com &>/dev/null; then
    echo "✅ Prometheus CRDs are ready"
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "⚠️  Prometheus CRDs not ready after 60 seconds"
  echo "   Continuing anyway - you may need to apply monitoring resources later"
fi

echo ""

# =============================================================================
# Step 2: Install ArgoCD
# =============================================================================

echo "🔧 [2/3] Installing ArgoCD..."
echo "-------------------------------------------------------------"

# Check if ArgoCD is already installed
if ! kubectl get namespace argocd &> /dev/null; then
  echo "📦 Creating argocd namespace..."
  kubectl create namespace argocd

  echo "📥 Installing ArgoCD (this may take 2-3 minutes)..."
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  echo "⏳ Waiting for ArgoCD to be ready..."
  kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd || {
    echo "⚠️  ArgoCD may need more time to start"
  }

  echo "✅ ArgoCD installed successfully"
else
  echo "✅ ArgoCD already installed, skipping"
fi

echo ""

# =============================================================================
# Step 3: Deploy QuakeWatch Application via ArgoCD
# =============================================================================

echo "📦 [3/3] Deploying QuakeWatch Application..."
echo "-------------------------------------------------------------"

# Clone the repository if it doesn't exist
if [ ! -d "/home/ubuntu/devops-course-project" ]; then
  echo "📥 Cloning QuakeWatch repository..."
  cd /home/ubuntu
  git clone https://github.com/YOUR_USERNAME/devops-course-project.git
  cd devops-course-project
else
  echo "✅ Repository already exists"
  cd /home/ubuntu/devops-course-project
  git pull origin main || echo "⚠️  Could not update repository"
fi

# Apply ArgoCD application manifest
if [ -f "argocd/argocd.yaml" ]; then
  echo "📄 Deploying application via ArgoCD..."
  kubectl apply -f argocd/argocd.yaml

  echo "⏳ Waiting for ArgoCD to sync and deploy the application..."
  sleep 5

  # Wait for service to exist
  echo "⏳ Waiting for service to be created (this may take 2-3 minutes)..."
  MAX_RETRIES=60
  RETRY_COUNT=0
  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if kubectl get service/earthquake-app-quackwatch-helm &>/dev/null; then
      echo "✅ Service is ready"
      break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 2
  done

  if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "⚠️  Service not found after 120 seconds"
    echo "   Check ArgoCD sync status: kubectl get application earthquake-app -n argocd"
  fi
else
  echo "⚠️  argocd/argocd.yaml not found. Skipping application deployment."
  echo "   Please ensure the repository structure is correct."
fi

echo ""

# =============================================================================
# Deployment Summary
# =============================================================================

echo "============================================="
echo "✅ Deployment Complete!"
echo "============================================="
echo ""

# Get service information
echo "📋 Service Information:"
echo "-------------------------------------------------------------"
SERVICE_PORT=$(kubectl get service earthquake-app-quackwatch-helm -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "N/A")

if [ "$SERVICE_PORT" != "N/A" ] && [ "$PUBLIC_IP" != "N/A" ]; then
  echo "🌐 QuakeWatch Application: http://$PUBLIC_IP:$SERVICE_PORT"
else
  echo "⚠️  Service not fully deployed yet. Check status with:"
  echo "   kubectl get service earthquake-app-quackwatch-helm"
fi
echo ""

# ArgoCD credentials
echo "🔐 ArgoCD Access:"
echo "-------------------------------------------------------------"
echo "Username: admin"
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
if [ -n "$ARGOCD_PASSWORD" ]; then
  echo "Password: $ARGOCD_PASSWORD"
else
  echo "Password: (run the following to get password)"
  echo "  kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath=\"{.data.password}\" | base64 -d"
fi
echo ""
echo "To access ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8081:443 --address 0.0.0.0"
echo "  Then navigate to: https://$PUBLIC_IP:8081"
echo ""

# Grafana credentials
echo "📊 Grafana Monitoring:"
echo "-------------------------------------------------------------"
echo "Username: admin"
GRAFANA_PASSWORD=$(kubectl get secret kube-prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d)
if [ -n "$GRAFANA_PASSWORD" ]; then
  echo "Password: $GRAFANA_PASSWORD"
else
  echo "Password: (run the following to get password)"
  echo "  kubectl get secret kube-prometheus-stack-grafana -n monitoring -o jsonpath=\"{.data.admin-password}\" | base64 -d"
fi
echo ""
echo "To access Grafana UI:"
echo "  kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80 --address 0.0.0.0"
echo "  Then navigate to: http://$PUBLIC_IP:3000"
echo ""

# Prometheus access
echo "📈 Prometheus:"
echo "-------------------------------------------------------------"
echo "To access Prometheus UI:"
echo "  kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090 --address 0.0.0.0"
echo "  Then navigate to: http://$PUBLIC_IP:9090"
echo ""

# Useful commands
echo "💡 Useful Commands:"
echo "-------------------------------------------------------------"
echo "Check all pods:           kubectl get pods -A"
echo "Check deployments:        kubectl get deployments"
echo "Check services:           kubectl get services"
echo "ArgoCD app status:        kubectl get application -n argocd"
echo "View logs:                kubectl logs -f <pod-name>"
echo ""

echo "============================================="
echo "🎉 QuakeWatch is now running on AWS K3s!"
echo "============================================="
