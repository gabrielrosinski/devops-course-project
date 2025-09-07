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
  sudo apt install google-chrome-stable
fi

echo "🚀 Starting Minikube with Docker driver..."
minikube start --driver=docker

echo "🔧 Enabling required Minikube addons..."
minikube addons enable storage-provisioner
minikube addons enable default-storageclass
minikube addons enable metrics-server

echo "📦 Applying Kubernetes secrets..."
kubectl apply -f earthquake-secret.yaml

echo "📄 Deploying application..."
kubectl apply -f deploy.yaml

echo "⏳ Waiting for Earthquake deployment to become available..."
kubectl rollout status deployment/earthquake --timeout=180s || {
  echo "❌ Deployment failed. Check pod logs with: kubectl logs -l app=earthquake"
  exit 1
}

echo "🌐 Opening service in browser..."
minikube service earthquake-service

echo "✅ Deployment completed!"