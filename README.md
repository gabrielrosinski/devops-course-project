# 🌍 Earthquake Dashboard – Deployment Guide

## 🚀 Features
- 📊 Real-time Earthquake Dashboard
- 🐳 Dockerized Flask Application
- ☸️ Deployed on Kubernetes with k3s
- 📁 Structured logging to `/var/log/flask-data`

---

## 🧰 Prerequisites
- [k3s](https://k3s.io/) - Lightweight Kubernetes distribution
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- Internet connection (for pulling Docker images from Docker Hub)

---

### 🪟 For Windows Users (WSL2)

1. Install and enable **WSL 2** (if not already):
   - [WSL 2 installation guide](https://learn.microsoft.com/en-us/windows/wsl/install)
2. Install Ubuntu or your preferred Linux distribution from Microsoft Store
3. Open WSL terminal and proceed with k3s installation (handled by deployment script)

---

### 🐧 For Linux Users

k3s will be automatically installed by the deployment script if not already present.

**Optional - Install Google Chrome for automatic browser opening:**
```bash
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
sudo apt update
sudo apt install google-chrome-stable -y
```

## ▶️ Quick Deployment

In the project folder simply run:

```bash
chmod +x build-deploy.sh
./build-deploy.sh
```
---

## ▶️ Accessing the Application

After deployment completes, the script automatically sets up port-forwarding and displays:

```
✅ Service available at: http://localhost:8080
ℹ️  Port-forward PID: <process-id> (to stop: kill <process-id>)
```

The application will automatically open in Google Chrome if installed, or you can manually navigate to `http://localhost:8080`

### Stopping the Port-Forward

The port-forward runs in the background. To stop it:
```bash
kill <process-id>  # Use the PID shown in deployment output
```

Or kill all port-forwards:
```bash
pkill -f "port-forward.*earthquake-app"
```  

### Link to image on docker hub
https://hub.docker.com/r/blaqr/earthquake

### Helm Chart Repository
```
oci://ghcr.io/gabrielrosinski/quackwatch-helm
```


