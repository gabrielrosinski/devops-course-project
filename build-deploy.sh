#!/bin/bash
set -e  # Stop on first error

# Detect environment
IS_WSL=false
IS_MINGW=false

# Check if running in Git Bash / MINGW (not supported for k3s)
if [[ "$(uname -s)" == MINGW* ]] || [[ "$(uname -s)" == MSYS* ]]; then
  IS_MINGW=true
  echo "❌ ERROR: This script cannot run in Git Bash or MINGW"
  echo ""
  echo "k3s requires a Linux environment. Please run this script in:"
  echo "  1. WSL2 (Windows Subsystem for Linux) - RECOMMENDED"
  echo "  2. Native Linux (Ubuntu, Debian, etc.)"
  echo ""
  echo "To use WSL2:"
  echo "  1. Open PowerShell as Administrator"
  echo "  2. Run: wsl --install"
  echo "  3. Restart your computer"
  echo "  4. Open 'Ubuntu' from Start menu"
  echo "  5. Run this script inside Ubuntu"
  exit 1
fi

# Detect if running in WSL
if grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null || [[ -n "$WSL_DISTRO_NAME" ]]; then
  IS_WSL=true
  echo "🔍 Detected WSL environment"
fi

# Check if running in WSL and Google Chrome is not installed
if [[ "$IS_WSL" == "true" ]] && ! command -v google-chrome &> /dev/null; then
  echo "📦 Installing Google Chrome for WSL environment..."

  # Download and add Google's signing key
  wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -

  # Add Google Chrome repository
  echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list

  # Update package list and install Chrome
  sudo apt update
  sudo apt install -y google-chrome-stable
fi

echo "🐳 Checking Docker Engine status..."
# Check if Docker is installed
if ! command -v docker &> /dev/null; then
  echo "📦 Docker not found. Installing Docker..."

  # Update package index and install prerequisites
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg lsb-release

  # Add Docker's official GPG key
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  # Set up the repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  # Install Docker Engine
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  echo "✅ Docker installed successfully"
fi

# Check if Docker daemon is running
if ! sudo docker info &> /dev/null; then
  echo "🔧 Docker daemon is not running. Starting Docker..."

  # Start Docker service
  if command -v systemctl &> /dev/null; then
    sudo systemctl start docker
    sudo systemctl enable docker
  elif command -v service &> /dev/null; then
    sudo service docker start
  else
    echo "❌ Unable to start Docker. Please start Docker manually."
    exit 1
  fi

  # Wait for Docker to be ready
  echo "⏳ Waiting for Docker daemon to be ready..."
  MAX_RETRIES=30
  RETRY_COUNT=0
  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if sudo docker info &> /dev/null; then
      echo "✅ Docker daemon is running"
      break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 2
  done

  if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ Docker daemon failed to start after ${MAX_RETRIES} attempts"
    exit 1
  fi
else
  echo "✅ Docker daemon is already running"
fi

echo "🔧 Setting up kubectl configuration..."
mkdir -p ~/.kube

# Check if k3s config exists
if [[ -f /etc/rancher/k3s/k3s.yaml ]]; then
  echo "📝 Found k3s configuration, setting up kubectl..."

  # Copy k3s config to kubectl config location
  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
  sudo chown $USER ~/.kube/config
  sudo chmod 644 ~/.kube/config

  # Export for this script session
  export KUBECONFIG=~/.kube/config

  echo "✅ kubectl configured with k3s"
elif [[ -f ~/.kube/config ]]; then
  echo "✅ kubectl config already exists"
  export KUBECONFIG=~/.kube/config
else
  echo "⚠️  No Kubernetes config found. Make sure k3s is installed and running."
  echo "   Run: sudo systemctl status k3s"
  exit 1
fi

echo "⏳ Waiting for k3s API server to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if kubectl cluster-info &>/dev/null; then
    echo "✅ k3s API server is responding"
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "❌ k3s API server failed to start after ${MAX_RETRIES} attempts"
  echo "🔍 Checking k3s service status..."
  sudo systemctl status k3s --no-pager || echo "k3s service not found"
  exit 1
fi

echo "⏳ Waiting for k3s nodes to register..."
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if kubectl get nodes 2>/dev/null | grep -q "Ready\|NotReady"; then
    echo "✅ Node(s) registered"
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "❌ No nodes registered after 60 seconds"
  echo "🔍 Checking k3s service status..."
  sudo systemctl status k3s --no-pager || echo "k3s service not found"
  exit 1
fi

echo "⏳ Waiting for k3s nodes to be ready..."
kubectl wait --for=condition=ready node --all --timeout=60s || {
  echo "❌ k3s nodes failed to become ready"
  kubectl get nodes
  exit 1
}

echo "✅ k3s cluster is ready"

echo "📊 Installing Prometheus & Grafana Monitoring Stack..."
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

# Check if kube-prometheus-stack helm release is actually installed
if ! helm list -n monitoring | grep -q kube-prometheus-stack; then
  echo "📥 Installing kube-prometheus-stack (Prometheus + Grafana)..."
  helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
    --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
    --wait --timeout=5m

  echo "✅ Prometheus & Grafana installed successfully"
else
  echo "✅ kube-prometheus-stack already installed, skipping"
fi

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
  echo "⚠️  Prometheus CRDs not ready after 60 seconds, cannot apply monitoring resources"
  exit 1
fi

echo "📊 Applying monitoring resources..."
if [ -d "monitoring/standalone" ]; then
  kubectl apply -f monitoring/standalone/
  echo "✅ All monitoring resources applied (ServiceMonitor, alerts, dashboard)"
else
  echo "⚠️  monitoring/standalone/ directory not found, skipping"
fi

echo "🔧 Installing ArgoCD..."
# Check if ArgoCD is already installed
if ! kubectl get namespace argocd &> /dev/null; then
  echo "📦 Creating argocd namespace..."
  kubectl create namespace argocd

  echo "📥 Installing ArgoCD..."
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  echo "⏳ Waiting for ArgoCD to be ready..."
  kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd || {
    echo "⚠️  ArgoCD may need more time to start"
  }
else
  echo "✅ ArgoCD already installed, skipping"
fi

echo "📄 Deploying application via ArgoCD..."
kubectl apply --validate=false -f argocd/argocd.yaml

echo "⏳ Waiting for ArgoCD to sync and deploy the application..."
# Wait for ArgoCD application to be created (reduced timeout - should be quick if ArgoCD is ready)
kubectl wait --for=condition=Ready application/earthquake-app -n argocd --timeout=30s 2>/dev/null || echo "⚠️  ArgoCD Application created, syncing in progress..."

# Wait for service to exist (this confirms deployment is progressing)
echo "⏳ Waiting for service to be created..."
MAX_RETRIES=45  # 45 retries × 2s = 90s total
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
  echo "❌ Service not found after 90 seconds"
  echo "   Checking ArgoCD sync status..."
  kubectl get application earthquake-app -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unable to get sync status"
  echo ""
  echo "   Checking deployment status..."
  kubectl get deployment earthquake-app-quackwatch-helm 2>/dev/null || echo "Deployment not found"
  exit 1
fi

echo "🌐 Setting up service access..."

# Kill any existing port-forward on port 8080
pkill -f "port-forward.*earthquake-app" 2>/dev/null || true

# Start port-forward in background (using KUBECONFIG already set above)
echo "🔧 Starting kubectl port-forward on localhost:8080..."
kubectl port-forward service/earthquake-app-quackwatch-helm 8080:5000 > /dev/null 2>&1 &
PORT_FORWARD_PID=$!

# Wait for port-forward to establish with retry loop
echo "⏳ Waiting for port-forward to be ready..."
MAX_RETRIES=10
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  # Check if process is still running
  if ! ps -p $PORT_FORWARD_PID > /dev/null 2>&1; then
    echo "❌ Port-forward process died"
    exit 1
  fi

  # Check if port is listening
  if netcat -z localhost 8080 2>/dev/null || curl -s http://localhost:8080 > /dev/null 2>&1; then
    break
  fi

  RETRY_COUNT=$((RETRY_COUNT + 1))
  sleep 0.5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "❌ Port-forward failed to become ready"
  kill $PORT_FORWARD_PID 2>/dev/null || true
  exit 1
fi

SERVICE_URL="http://localhost:8080"
echo "✅ Service available at: $SERVICE_URL"
echo "ℹ️  Port-forward PID: $PORT_FORWARD_PID (to stop: kill $PORT_FORWARD_PID)"
echo ""

# Display ArgoCD credentials
echo "🔐 ArgoCD Credentials:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Username: admin"

# Get ArgoCD admin password
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

if [ -n "$ARGOCD_PASSWORD" ]; then
  echo "Password: $ARGOCD_PASSWORD"
else
  echo "Password: (not available yet - ArgoCD may still be starting)"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ℹ️  To access ArgoCD UI, run: kubectl port-forward svc/argocd-server -n argocd 8081:443"
echo "   Then navigate to: https://localhost:8081"
echo ""

# Display Grafana credentials
echo "📊 Grafana Monitoring:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Username: admin"

# Get Grafana admin password
GRAFANA_PASSWORD=$(kubectl get secret kube-prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d)

if [ -n "$GRAFANA_PASSWORD" ]; then
  echo "Password: $GRAFANA_PASSWORD"
else
  echo "Password: (not available yet - Grafana may still be starting)"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ℹ️  To access Grafana UI, run: kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80"
echo "   Then navigate to: http://localhost:3000"
echo ""
echo "ℹ️  To access Prometheus UI, run: kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090"
echo "   Then navigate to: http://localhost:9090"
echo ""
echo "ℹ️  To access Alertmanager UI, run: kubectl port-forward svc/kube-prometheus-stack-alertmanager -n monitoring 9093:9093"
echo "   Then navigate to: http://localhost:9093"
echo ""
echo "💡 Alert Configuration:"
echo "   - 7 alert rules are active (view in Prometheus UI → Alerts)"
echo "   - To configure email notifications, see: monitoring/helm-values/alertmanager-values.yaml"
echo ""

# Open in browser (works in WSL with Chrome installed)
if command -v google-chrome &> /dev/null; then
  echo "🌐 Opening service in browser..."
  google-chrome "$SERVICE_URL" 2>/dev/null &
else
  echo "ℹ️  Open your browser and navigate to: $SERVICE_URL"
fi

echo "✅ Deployment completed!"