#!/bin/bash
set -e  # Stop on first error

# Check if running in WSL and Google Chrome is not installed
if [[ -n "$WSL_DISTRO_NAME" ]] && ! command -v google-chrome &> /dev/null; then
  echo "📦 Installing Google Chrome for WSL environment..."
  
  # Download and add Google's signing key
  wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -

  # Add Google Chrome repository
  echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list

  # Update package list
  sudo apt update

  # Install Google Chrome
  sudo apt install -y google-chrome-stable
fi

echo "🚀 Checking k3s installation..."
if ! command -v k3s &> /dev/null; then
  echo "📦 k3s not found. Installing k3s..."
  curl -sfL https://get.k3s.io | sh -
else
  echo "✅ k3s is already installed"
fi

# Ensure k3s service is running
if ! sudo systemctl is-active --quiet k3s; then
  echo "🔧 Starting k3s service..."
  sudo systemctl start k3s
fi

# Always wait for API server to be ready (even if service was already running)
echo "⏳ Waiting for k3s API server to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if sudo k3s kubectl get --raw /readyz &>/dev/null; then
    echo "✅ k3s API server is responding"
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "❌ k3s API server failed to start after ${MAX_RETRIES} attempts"
  exit 1
fi

# Setup kubectl configuration immediately after API server is ready
echo "🔧 Setting up kubectl configuration..."
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER ~/.kube/config
sudo chmod 644 /etc/rancher/k3s/k3s.yaml

# Export for this script session
export KUBECONFIG=~/.kube/config
echo "✅ kubectl configured - will work in all terminal sessions"

# Wait for k3s nodes to be ready (now using regular kubectl with KUBECONFIG set)
echo "⏳ Waiting for k3s nodes to be ready..."
kubectl wait --for=condition=ready node --all --timeout=60s || {
  echo "❌ k3s nodes failed to become ready"
  exit 1
}

echo "✅ k3s is running"

echo "🔧 Configuring k3s components..."
# k3s includes local-path storage provisioner and default storage class by default
# Check if metrics-server is installed for HPA support
if ! kubectl get deployment metrics-server -n kube-system &> /dev/null; then
  echo "📊 Installing metrics-server for HPA support..."
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

  # Patch metrics-server for k3s (disable TLS verification for local development)
  echo "🔧 Configuring metrics-server for k3s..."
  kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' 2>/dev/null || true

  echo "⏳ Waiting for metrics-server to be ready..."
  kubectl wait --for=condition=available --timeout=60s deployment/metrics-server -n kube-system || echo "⚠️  Metrics-server may need more time to start"
else
  echo "✅ metrics-server already installed, skipping"
fi

echo "📊 Installing Prometheus & Grafana Monitoring Stack..."
# Add Prometheus Helm repository
if ! helm repo list | grep -q prometheus-community; then
  echo "📦 Adding prometheus-community Helm repository..."
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo update
else
  echo "✅ prometheus-community repo already added"
fi

# Check if kube-prometheus-stack is already installed
if ! kubectl get namespace monitoring &> /dev/null; then
  echo "📦 Creating monitoring namespace..."
  kubectl create namespace monitoring

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
# Wait for ArgoCD application to be created
kubectl wait --for=condition=Ready application/earthquake-app -n argocd --timeout=60s 2>/dev/null || echo "⚠️  ArgoCD Application created, syncing in progress..."

# Give ArgoCD time to sync and deploy
echo "⏳ Waiting for Earthquake deployment to become available..."
sleep 5  # Brief wait for ArgoCD to start syncing

# Wait for the deployment to be available
kubectl rollout status deployment/earthquake-app-quackwatch-helm --timeout=180s 2>/dev/null || {
  echo "⚠️  Deployment is still syncing. Check ArgoCD UI for status."
  echo "   You can check manually with: kubectl get pods"
}

echo "🌐 Setting up service access..."

# Wait for service to exist before port-forwarding
echo "⏳ Waiting for service to be created..."
RETRY_COUNT=0
while [ $RETRY_COUNT -lt 30 ]; do
  if kubectl get service/earthquake-app-quackwatch-helm &>/dev/null; then
    echo "✅ Service is ready"
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  sleep 2
done

if [ $RETRY_COUNT -eq 30 ]; then
  echo "❌ Service not found after 60 seconds"
  echo "   Check ArgoCD sync status: kubectl get application earthquake-app -n argocd"
  exit 1
fi

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