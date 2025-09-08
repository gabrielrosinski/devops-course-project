# 🌍 QuakeWatch - Earthquake Monitoring Dashboard

A Flask-based web application that displays real-time and historical earthquake data from the USGS API, containerized with Docker and deployed to Kubernetes using Helm.

## 🚀 Features

- 📊 Real-time earthquake data visualization
- 🗺️ Interactive maps and charts using Matplotlib  
- 🐳 Containerized Flask application
- ☸️ Production-ready Kubernetes deployment with Helm
- 📈 Horizontal Pod Autoscaler (HPA) for scaling
- 🔄 Automated CI/CD with GitHub Actions
- 📊 Health monitoring endpoints

---

## 🧰 Prerequisites

- [Docker](https://www.docker.com/products/docker-desktop)
- [Minikube](https://minikube.sigs.k8s.io/docs/start/) or any Kubernetes cluster
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/) v3.12+

---

## 🚀 Quick Start with Helm

### 1. Start your Kubernetes cluster
```bash
# For local development with Minikube
minikube start --driver=docker --memory=4096 --cpus=2

# Enable required addons
minikube addons enable storage-provisioner
minikube addons enable default-storageclass  
minikube addons enable metrics-server
```

### 2. Deploy with Helm
```bash
# Install the application
helm upgrade --install quackwatch-helm ./quackwatch-helm/ \
  --namespace default \
  --create-namespace \
  --wait --timeout=5m

# Access the application
minikube service quackwatch-helm --url
```

### 3. Access the Dashboard
Open the URL provided by the service command in your browser to access the earthquake dashboard.

---

## 📦 Application Components

### API Endpoints
- `/` - Main dashboard page
- `/graph-earthquakes` - Interactive graphs and data
- `/graph-earthquakes.png` - Dynamic graph image generation  
- `/telaviv-earthquakes` - Regional earthquake data
- `/ping`, `/health`, `/status`, `/info` - Health check endpoints

### Kubernetes Resources
- **Deployment**: 3 replicas with resource limits and health checks
- **Service**: NodePort service on port 32000
- **ConfigMap**: Application configuration
- **Secret**: API keys and sensitive data
- **PVC**: Persistent storage for logs (1Gi)
- **HPA**: Auto-scaling (2-5 replicas based on CPU usage)
- **CronJob**: Automated logging every minute

---

## 🔧 Development

### Local Development (Flask only)
```bash
cd QuakeWatch
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
python app.py
```
Application runs on http://127.0.0.1:5000

### Docker Development
```bash
docker-compose up --build
```
Application runs on http://localhost:8000

### Testing
```bash
# Install test dependencies
pip install -r requirements-test.txt

# Run Helm deployment tests
python test_helm_deployment.py --release-name quackwatch-test --namespace default

# Run with pytest
pytest test_helm_deployment.py::TestHelmDeployment -v
```

---

## 🤖 CI/CD Pipeline

The project uses GitHub Actions for automated testing across multiple Kubernetes versions:

### Workflow Features
- **Multi-version testing**: Tests against Kubernetes 1.27, 1.28, and 1.29
- **Automated deployment**: Deploys Helm chart to Minikube
- **Comprehensive testing**: Health checks, scaling, and functionality tests
- **Parallel execution**: Matrix strategy for faster testing
- **Auto cleanup**: Resources cleaned up after tests

### Trigger Events
- Push to `main`, `develop`, or `feature/*` branches
- Pull requests to `main` or `develop`
- Manual workflow dispatch

---

## 📊 Monitoring & Scaling

### Health Checks
The application includes comprehensive health monitoring:
```bash
curl http://your-service/health
curl http://your-service/ping
curl http://your-service/status
```

### Horizontal Pod Autoscaler
Automatically scales between 2-5 replicas based on CPU usage:
```bash
kubectl get hpa quackwatch-helm
```

### View Logs
```bash
kubectl logs -l app.kubernetes.io/instance=quackwatch-helm -f
```

---

## 🐳 Container Registry

**Docker Hub**: `blaqr/earthquake:latest`
```bash
docker pull blaqr/earthquake:latest
```

**Helm Chart**: [Available in this repository at](https://github.com/users/gabrielrosinski/packages/container/package/quackwatch-helm)

---

## 🗂️ Project Structure

```
.
├── QuakeWatch/                 # Flask application source
│   ├── app.py                 # Application factory
│   ├── dashboard.py           # Main dashboard blueprint  
│   ├── utils.py               # Helper functions
│   ├── templates/             # Jinja2 templates
│   └── static/                # Static assets
├── quackwatch-helm/           # Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/             # Kubernetes manifests
├── test_helm_deployment.py    # Deployment tests
├── .github/workflows/ci.yml   # CI/CD pipeline
└── docker-compose.yml         # Local development
```

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `pytest test_helm_deployment.py -v`
5. Submit a pull request

The CI pipeline will automatically test your changes across multiple Kubernetes versions.

---

## 📄 License

This project is part of a DevOps course demonstrating modern containerization and orchestration practices.