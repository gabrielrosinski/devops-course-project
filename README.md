# 🌍 Earthquake Dashboard – Deployment Guide

## 🚀 Features
- 📊 Real-time Earthquake Dashboard
- 🐳 Dockerized Flask Application
- ☸️ Ready for Kubernetes with Minikube
- 📁 Structured logging to `/var/log/flask-data`

---

## 🧰 Prerequisites
- [Docker](https://www.docker.com/products/docker-desktop)
- [Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

---

### 🪟 For Windows Users

1. Install **Docker Desktop for Windows**
2. Install and enable **WSL 2** (if not already):
   - [WSL 2 installation guide](https://learn.microsoft.com/en-us/windows/wsl/install)
3. Enable WSL integration in Docker Desktop:
   - **Settings → Resources → WSL Integration → Enable for your distro (e.g., Ubuntu)**
4. Restart Docker Desktop and your terminal

---

### 🐧 For Linux Users

1. **Enable and start Docker Engine and Docker Compose:**
   ```bash
   sudo apt update
   sudo apt install docker.io docker-compose -y
   sudo systemctl enable docker
   sudo systemctl start docker
   sudo usermod -aG docker $USER
   ```

## ▶️ Quick Deployment

In the project folder simply run:

```bash
chmod +x build-deploy.sh
./build-deploy.sh
```
---

## ▶️ Running in browser

It will say (example):

Opening service default/earthquake-service in default browser...
👉 http://127.0.0.1:33263

- The port might be different  
- You can access the web page via this address.  

### Link to image on docker hub
https://hub.docker.com/r/blaqr/earthquake


