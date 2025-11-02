# 🌍 QuakeWatch - AWS Production Deployment Guide

Deploy QuakeWatch to AWS with a production-ready Kubernetes (K3s) cluster using Terraform, complete with GitOps (ArgoCD), and full observability stack (Prometheus & Grafana).

> **Note**: This guide is for AWS cloud deployment. For local development, see [README.md](README.md).

---

## 🏗️ Architecture

```
AWS Cloud (us-east-1)
├── VPC (10.0.0.0/16)
│   ├── Public Subnet (10.0.1.0/24)
│   │   └── EC2 Instance (t3a.medium - 2 vCPU, 4GB RAM)
│   │       └── K3s Cluster
│   │           ├── QuakeWatch App (3 replicas, NodePort 32000)
│   │           ├── ArgoCD (NodePort 30443/30080)
│   │           ├── Grafana (NodePort 30300)
│   │           └── Prometheus (NodePort 30900)
│   └── Internet Gateway
└── Security Groups (NodePort range 30000-32767 open)
```

---

## 🚀 Features

- ☁️ **Production AWS deployment** with Terraform Infrastructure as Code
- ☸️ **K3s Kubernetes** cluster on EC2 (lightweight, production-ready)
- 🔄 **GitOps deployment** with ArgoCD (auto-sync from Git)
- 📈 **Complete monitoring** with Prometheus & Grafana
- 🎯 **Direct NodePort access** - no port-forwarding needed
- 📦 **Auto-scaling** with Horizontal Pod Autoscaler (2-5 replicas)
- 🔒 **Security best practices** - VPC isolation, security groups, IAM roles
- 💰 **Cost-optimized** - ~$27-30/month for t3a.medium

---

## 📋 Prerequisites

### 1. AWS Account
- AWS account (free tier or paid)
- AWS CLI installed and configured
- Access to create EC2, VPC, and IAM resources

### 2. Tools Installation

```bash
# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure AWS CLI
aws configure
# Enter: Access Key, Secret Key, Region (us-east-1), Output (json)

# Terraform
# macOS
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Linux
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Verify installations
aws sts get-caller-identity
terraform version
```

### 3. Create SSH Key Pair

```bash
# Create key pair via AWS CLI
aws ec2 create-key-pair \
  --key-name quakewatch-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/quakewatch-key.pem

chmod 400 ~/.ssh/quakewatch-key.pem
```

---

## 🚀 Quick Start

### Step 1: Clone Repository

```bash
git clone https://github.com/gabrielrosinski/devops-course-project.git
cd devops-course-project/terraform
```

### Step 2: Configure Variables

Edit `terraform.tfvars`:

```hcl
# Your AWS SSH key pair name
key_name = "quakewatch-key"

# Your public IP (find it: curl ifconfig.me)
# IMPORTANT: Use YOUR IP/32, not 0.0.0.0/0!
allowed_ssh_cidr = "YOUR_IP/32"

# Generate secure token: openssl rand -hex 32
k3s_token = "YOUR_RANDOM_TOKEN_HERE"
```

### Step 3: Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy (takes 5-10 minutes)
terraform apply
# Type 'yes' when prompted

# Save your public IP
export PUBLIC_IP=$(terraform output -raw instance_public_ip)
echo "Your instance IP: $PUBLIC_IP"
```

### Step 4: Deploy Applications

```bash
# SSH to your EC2 instance
ssh -i ~/.ssh/quakewatch-key.pem ubuntu@$PUBLIC_IP

# Run deployment script (automatically downloaded during initialization)
./deploy-apps.sh

# This will install:
# ✅ Prometheus & Grafana (monitoring)
# ✅ ArgoCD (GitOps)
# ✅ QuakeWatch application
```

---

## 🌐 Accessing Services

**All services use NodePort - direct browser access, no port-forwarding!**

Replace `<PUBLIC_IP>` with your EC2 instance IP:

### QuakeWatch Application
```
http://<PUBLIC_IP>:32000
```

### ArgoCD (GitOps Dashboard)
```
HTTPS: https://<PUBLIC_IP>:30443
HTTP:  http://<PUBLIC_IP>:30080

Username: admin
Password: (get from cluster - see below)
```

### Grafana (Monitoring Dashboard)
```
http://<PUBLIC_IP>:30300

Username: admin
Password: (get from cluster - see below)
```

### Prometheus (Metrics)
```
http://<PUBLIC_IP>:30900
```

### Get Passwords

SSH to your instance and run:

```bash
# ArgoCD password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Grafana password
kubectl get secret kube-prometheus-stack-grafana -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 -d && echo
```

---

## 📊 Monitoring & Observability

### Pre-configured Stack

- **Prometheus**: Metrics collection and storage
- **Grafana**: Pre-configured QuakeWatch dashboard
- **ServiceMonitor**: Automatic metrics scraping
- **7 Alert Rules**: Application health monitoring

### QuakeWatch Dashboard

Navigate to: **Grafana → Dashboards → QuakeWatch Application Metrics**

Shows:
- 📈 Request Rate (req/s)
- ⏱️ Response Time (p95 latency)
- ❌ Error Rate (4xx, 5xx)
- 📊 Total Requests

### Application Metrics

```bash
# View raw Prometheus metrics
curl http://<PUBLIC_IP>:32000/metrics
```

### Alert Rules

| Alert | Severity | Threshold | Description |
|-------|----------|-----------|-------------|
| QuakeWatchHighErrorRate | Critical | 5% error rate for 2m | High HTTP 5xx errors |
| QuakeWatchDown | Critical | Up = 0 for 1m | Application unreachable |
| QuakeWatchSlowResponse | Warning | p95 > 2s for 5m | Slow response times |
| QuakeWatchPodRestarting | Warning | Restarts > 0 for 5m | Pod restart loop |
| QuakeWatchNoTraffic | Warning | 0 req/s for 10m | No incoming traffic |
| QuakeWatchHighMemory | Warning | Memory > 90% for 5m | High memory usage |
| QuakeWatchHighCPU | Warning | CPU > 0.8 cores for 5m | High CPU usage |

---

## 🔄 GitOps with ArgoCD

ArgoCD automatically monitors your Git repository and deploys changes:

- **Auto-Sync**: Deploys changes from `main` branch automatically
- **Self-Healing**: Corrects manual changes to match Git state
- **Rollback**: Easy rollback through Git history
- **Visual Dashboard**: Track deployments in real-time

To deploy changes:
1. Push changes to `main` branch
2. ArgoCD automatically detects and deploys
3. Monitor deployment in ArgoCD UI

---

## 🛠️ Infrastructure Management

### View Cluster Status

```bash
# SSH to instance
ssh -i ~/.ssh/quakewatch-key.pem ubuntu@$PUBLIC_IP

# Check pods
kubectl get pods -A

# Check services
kubectl get svc -A

# Check deployments
kubectl get deployments

# View logs
kubectl logs -l app.kubernetes.io/instance=quackwatch-helm -f
```

### Scale Application

```bash
# Manual scaling
kubectl scale deployment earthquake-app-quackwatch-helm --replicas=5

# Check HPA status
kubectl get hpa
```

### Update Monitoring Configuration

```bash
# Upgrade Grafana with more resources
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values /home/ubuntu/deploy_config/monitoring/helm-values/prometheus-minimal-values.yaml
```

---

## 💰 Cost Management

### Current Configuration Cost

**Instance**: t3a.medium (2 vCPU, 4GB RAM)
- Hourly: ~$0.0376/hour
- Monthly: ~$27.41/month
- Daily: ~$0.90/day
- **NOT in AWS free tier**

**EBS Storage**: 20 GB
- Monthly: ~$2.00/month

**Total**: ~$29-30/month

### Cost Optimization

**Stop instance when not in use:**
```bash
# Stop instance (data preserved, billing stops)
cd terraform
aws ec2 stop-instances --instance-ids $(terraform output -raw instance_id)

# Start later
aws ec2 start-instances --instance-ids $(terraform output -raw instance_id)
```

**Destroy everything:**
```bash
cd terraform
terraform destroy
# Type 'yes' to confirm
# WARNING: Permanently deletes all resources!
```

**Use smaller instance (free tier):**
```hcl
# terraform.tfvars
instance_type = "t2.micro"  # 1 vCPU, 1GB RAM (free tier)
# Warning: May not have enough resources for all services
```

---

## 🔧 Troubleshooting

### Can't Access Services

1. Check instance is running:
   ```bash
   aws ec2 describe-instances --instance-ids $(terraform output -raw instance_id)
   ```

2. Verify security group allows NodePort range:
   ```bash
   terraform output security_group_id
   ```

3. Check services are ready:
   ```bash
   ssh -i ~/.ssh/quakewatch-key.pem ubuntu@$PUBLIC_IP
   kubectl get pods -A
   kubectl get svc -A
   ```

### Grafana Won't Load

```bash
# Check Grafana pod status
kubectl get pods -n monitoring | grep grafana

# View logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=100

# Restart if needed
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
```

### K3s Installation Issues

```bash
# View installation logs
ssh -i ~/.ssh/quakewatch-key.pem ubuntu@$PUBLIC_IP
cat /var/log/k3s-install.log

# Check K3s status
sudo systemctl status k3s
```

### Common Deployment Issues

See [terraform/README.md#deployment-issues--solutions](terraform/README.md#deployment-issues--solutions) for detailed solutions to:
- Grafana resource constraints
- Prometheus webhook issues
- IMDSv2 metadata access
- Port-forwarding problems
- Instance type configuration

---

## 📚 Documentation

- **Local Development**: [README.md](README.md)
- **Terraform Details**: [terraform/README.md](terraform/README.md)
- **K3s Docs**: https://docs.k3s.io/
- **ArgoCD Docs**: https://argo-cd.readthedocs.io/
- **Terraform AWS**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs

---

## 🔒 Security Best Practices

### ✅ DO:
- Use your specific IP for SSH access (not 0.0.0.0/0)
- Keep `terraform.tfvars` out of Git (already in .gitignore)
- Use strong K3s tokens (`openssl rand -hex 32`)
- Enable MFA on AWS account
- Rotate SSH keys and tokens periodically
- Set up billing alerts

### ❌ DON'T:
- Share SSH private keys
- Commit `.tfstate` files to Git
- Open SSH to entire internet
- Use weak passwords or tokens
- Leave unused resources running

---

## 🎯 What You'll Learn

This deployment demonstrates:
- ✅ Infrastructure as Code (Terraform)
- ✅ Container Orchestration (Kubernetes/K3s)
- ✅ GitOps (ArgoCD)
- ✅ Observability (Prometheus/Grafana)
- ✅ Cloud Deployment (AWS EC2)
- ✅ Security Best Practices (VPC, Security Groups, IAM)
- ✅ Production-Ready Patterns (Health checks, auto-scaling, monitoring)

---

## 🗂️ Project Structure

```
.
├── README.md                      # Local development guide
├── README-AWS.md                  # This file (AWS deployment)
├── terraform/                     # Infrastructure as Code
│   ├── main.tf                   # Root configuration
│   ├── variables.tf              # Variable definitions
│   ├── modules/                  # Terraform modules (VPC, EC2, IAM)
│   ├── user-data.sh             # EC2 initialization script
│   ├── deploy-apps.sh           # Application deployment script
│   └── README.md                # Detailed Terraform docs
├── monitoring/                    # Monitoring configuration
│   ├── helm-values/
│   │   └── prometheus-minimal-values.yaml
│   └── standalone/
│       ├── prometheus-alerts.yaml
│       ├── grafana-dashboard.yaml
│       └── servicemonitor.yaml
├── argocd/                       # ArgoCD configuration
│   ├── argocd.yaml              # Application manifest
│   └── argocd-nodeport.yaml     # NodePort service config
├── quackwatch-helm/              # Helm chart
└── QuakeWatch/                   # Flask application
```

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test locally and on AWS
5. Submit a pull request

---

## 📄 License

This project is part of a DevOps course demonstrating modern cloud infrastructure and GitOps practices.
