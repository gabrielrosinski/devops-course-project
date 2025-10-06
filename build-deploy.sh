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

# Wait for k3s to be ready using kubectl wait
echo "⏳ Waiting for k3s to be ready..."
sudo k3s kubectl wait --for=condition=ready node --all --timeout=60s || {
  echo "❌ k3s failed to become ready"
  exit 1
}

echo "✅ k3s is running"

# Set up kubeconfig for kubectl
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
sudo chmod 644 /etc/rancher/k3s/k3s.yaml

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

echo "📄 Deploying application with Helm..."
helm upgrade --install earthquake-app ./quackwatch-helm

echo "⏳ Waiting for Earthquake deployment to become available..."
kubectl rollout status deployment/earthquake-app-quackwatch-helm --timeout=180s || {
  echo "❌ Deployment failed. Check pod logs with: kubectl logs -l app.kubernetes.io/instance=earthquake-app"
  exit 1
}

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

# Open in browser (works in WSL with Chrome installed)
if command -v google-chrome &> /dev/null; then
  echo "🌐 Opening service in browser..."
  google-chrome "$SERVICE_URL" 2>/dev/null &
else
  echo "ℹ️  Open your browser and navigate to: $SERVICE_URL"
fi

echo "✅ Deployment completed!"