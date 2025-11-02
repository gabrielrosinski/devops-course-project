# Terraform Infrastructure - K3s on AWS

Complete Infrastructure-as-Code configuration for deploying a production-ready K3s Kubernetes cluster on AWS EC2 with monitoring, GitOps, and security best practices.

## 📋 Table of Contents

- [Architecture Overview](#architecture-overview)
- [Resources Created](#resources-created)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Accessing Services](#accessing-services)
- [Deployment Issues & Solutions](#deployment-issues--solutions)
- [File Structure](#file-structure)
- [Troubleshooting](#troubleshooting)
- [Cost Management](#cost-management)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                      AWS Cloud                          │
│                    Region: us-east-1                    │
│                                                         │
│  ┌───────────────────────────────────────────────────┐ │
│  │              VPC (10.0.0.0/16)                    │ │
│  │                                                   │ │
│  │  ┌─────────────────┐  ┌─────────────────┐        │ │
│  │  │ Public Subnet 1 │  │ Public Subnet 2 │        │ │
│  │  │  (10.0.1.0/24)  │  │  (10.0.2.0/24)  │        │ │
│  │  │   AZ: us-east-1a│  │   AZ: us-east-1b│        │ │
│  │  │                 │  │                 │        │ │
│  │  │  ┌───────────┐  │  │                 │        │ │
│  │  │  │   EC2     │  │  │  (Reserved for │        │ │
│  │  │  │ t3a.medium│  │  │   worker nodes) │        │ │
│  │  │  │ 2vCPU 4GB │  │  │                 │        │ │
│  │  │  │           │  │  │                 │        │ │
│  │  │  │ K3s Server│  │  │                 │        │ │
│  │  │  │  + Apps   │  │  │                 │        │ │
│  │  │  └─────┬─────┘  │  │                 │        │ │
│  │  │        │        │  │                 │        │ │
│  │  └────────┼────────┘  └─────────────────┘        │ │
│  │           │                                       │ │
│  │  ┌────────▼──────────┐                           │ │
│  │  │ Internet Gateway  │                           │ │
│  │  └───────────────────┘                           │ │
│  └───────────────────────────────────────────────────┘ │
│                          │                            │
└──────────────────────────┼─────────────────────────────┘
                           │
                  ┌────────▼────────┐
                  │    Internet     │
                  │   Your Browser  │
                  │                 │
                  │ Direct Access:  │
                  │ • App: 32000    │
                  │ • Grafana: 30300│
                  │ • ArgoCD: 30443 │
                  │ • Prom: 30900   │
                  └─────────────────┘
```

---

## Resources Created

### Networking

| Resource | Configuration | Purpose |
|----------|--------------|---------|
| VPC | 10.0.0.0/16 | Isolated network environment |
| Internet Gateway | 1 | Internet connectivity |
| Public Subnet 1 | 10.0.1.0/24 (us-east-1a) | K3s server node |
| Public Subnet 2 | 10.0.2.0/24 (us-east-1b) | Future worker nodes |
| Route Table | Public routes | Traffic routing to IGW |

### Compute

| Resource | Specification | Details |
|----------|--------------|---------|
| EC2 Instance | t3a.medium | 2 vCPU, 4 GB RAM |
| EBS Volume | 20 GB gp2 | Root volume |
| AMI | Ubuntu 24.04 LTS | ami-0360c520857e3138f |

### Security

| Resource | Configuration | Purpose |
|----------|--------------|---------|
| Security Group | k3s-node-sg | Firewall rules |
| IAM Role | k3s-node-role | EC2 permissions |
| IAM Instance Profile | k3s-node-profile | Attach role to instance |

### Security Group Rules

| Port Range | Protocol | Source | Purpose |
|-----------|----------|--------|---------|
| 22 | TCP | Your IP | SSH access |
| 6443 | TCP | Your IP | K3s API server |
| 80 | TCP | 0.0.0.0/0 | HTTP |
| 443 | TCP | 0.0.0.0/0 | HTTPS |
| **30000-32767** | **TCP** | **0.0.0.0/0** | **NodePort services** |
| 8472 | UDP | VPC CIDR | Flannel VXLAN |
| 10250 | TCP | VPC CIDR | Kubelet API |

---

## Prerequisites

### 1. AWS Account Setup

```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure credentials
aws configure
# Enter: Access Key ID, Secret Access Key, Region (us-east-1), Output (json)

# Verify access
aws sts get-caller-identity
```

### 2. Create SSH Key Pair

**Option A - AWS Console:**
1. EC2 Console → Key Pairs → Create Key Pair
2. Name: `quakewatch-key`
3. Type: RSA, Format: .pem
4. Download and secure:
   ```bash
   chmod 400 ~/Downloads/quakewatch-key.pem
   mv ~/Downloads/quakewatch-key.pem ~/.ssh/
   ```

**Option B - AWS CLI:**
```bash
aws ec2 create-key-pair \
  --key-name quakewatch-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/quakewatch-key.pem

chmod 400 ~/.ssh/quakewatch-key.pem
```

### 3. Install Terraform

**macOS:**
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

**Linux:**
```bash
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

**Verify:**
```bash
terraform version
```

---

## Quick Start

### 1. Configure Variables

Edit `terraform.tfvars`:

```hcl
# Your AWS SSH key pair name
key_name = "quakewatch-key"

# Your public IP address (find it: curl ifconfig.me)
# IMPORTANT: Use YOUR IP, not 0.0.0.0/0!
allowed_ssh_cidr = "203.0.113.42/32"

# Generate secure token: openssl rand -hex 32
k3s_token = "your-secure-random-token-here"

# Optional: Change instance type
# instance_type = "t3a.medium"  # Default

# Optional: Change region
# aws_region = "us-east-1"  # Default
```

### 2. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Preview changes
terraform plan

# Deploy infrastructure
terraform apply
# Type 'yes' when prompted
# Wait 5-10 minutes for:
# - AWS resources creation
# - EC2 instance boot
# - K3s installation via user-data
# - Configuration files download
```

### 3. Get Outputs

```bash
# View all outputs
terraform output

# Get specific values
terraform output instance_public_ip
terraform output k3s_api_endpoint
```

Example output:
```
instance_public_ip = "52.87.182.190"
instance_state = "running"
k3s_api_endpoint = "https://52.87.182.190:6443"
```

### 4. Deploy Applications

```bash
# SSH to instance
ssh -i ~/.ssh/quakewatch-key.pem ubuntu@$(terraform output -raw instance_public_ip)

# Run deployment script (auto-downloaded during initialization)
./deploy-apps.sh
```

The script automatically installs:
- ✅ Prometheus & Grafana (with NodePort on 30300, 30900)
- ✅ ArgoCD (with NodePort on 30443/30080)
- ✅ QuakeWatch application (NodePort 32000)

---

## Accessing Services

**All services use NodePort - direct browser access, no port-forwarding!**

### Service Access URLs

| Service | URL | Port | Credentials |
|---------|-----|------|-------------|
| **QuakeWatch App** | `http://<PUBLIC_IP>:32000` | 32000 | None |
| **ArgoCD (HTTPS)** | `https://<PUBLIC_IP>:30443` | 30443 | admin / (see below) |
| **ArgoCD (HTTP)** | `http://<PUBLIC_IP>:30080` | 30080 | admin / (see below) |
| **Grafana** | `http://<PUBLIC_IP>:30300` | 30300 | admin / (see below) |
| **Prometheus** | `http://<PUBLIC_IP>:30900` | 30900 | None |

### Get Credentials

```bash
# SSH to instance first
ssh -i ~/.ssh/quakewatch-key.pem ubuntu@<PUBLIC_IP>

# ArgoCD password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d && echo

# Grafana password
kubectl get secret kube-prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d && echo
```

### Remote kubectl Access (Optional)

```bash
# Copy kubeconfig from instance
scp -i ~/.ssh/quakewatch-key.pem \
  ubuntu@<PUBLIC_IP>:/home/ubuntu/.kube/config \
  ~/.kube/quakewatch-config

# Update server IP
export PUBLIC_IP=$(terraform output -raw instance_public_ip)
sed -i "s|https://127.0.0.1:6443|https://$PUBLIC_IP:6443|g" ~/.kube/quakewatch-config

# Use config
export KUBECONFIG=~/.kube/quakewatch-config
kubectl get nodes
kubectl get pods -A
```

---

## Deployment Issues & Solutions

During development and testing, we encountered several issues. Here's what we learned:

### 1. **Grafana Resource Constraints**

**Problem:**
- Grafana pod stuck at 2/3 ready
- Database locked errors in logs
- Readiness probe timeouts

**Root Cause:**
- Initial memory limits (64Mi/128Mi) were too low for Grafana 12.2.1
- Grafana requires more memory for API server and dashboard provisioning

**Solution:**
- Increased memory to 256Mi request / 512Mi limit
- File: `monitoring/helm-values/prometheus-minimal-values.yaml`

```yaml
grafana:
  resources:
    requests:
      memory: 256Mi  # Was: 64Mi
      cpu: 100m
    limits:
      memory: 512Mi  # Was: 128Mi
      cpu: 200m
```

### 2. **Prometheus Operator Admission Webhook Issue**

**Problem:**
- Prometheus Operator tried to mount webhook secrets
- Pod crashes due to missing webhook certificates

**Root Cause:**
- Setting `admissionWebhooks.enabled: false` wasn't sufficient
- Webhook patch job still attempted to run

**Solution:**
- Explicitly disabled all webhook components
- File: `monitoring/helm-values/prometheus-minimal-values.yaml`

```yaml
prometheusOperator:
  admissionWebhooks:
    enabled: false
    patch:
      enabled: false  # Added
  tls:
    enabled: false    # Added
```

### 3. **EC2 Metadata Service (IMDSv2) - Empty Public IP**

**Problem:**
- Deploy script showed empty IP in output: `https://:8081`
- `$PUBLIC_IP` variable was empty

**Root Cause:**
- AWS EC2 instances now require IMDSv2 tokens by default
- Old IMDSv1 curl command failed silently

**Solution:**
- Updated script to fetch IMDSv2 token first
- Added fallback to IMDSv1 for older instances
- File: `terraform/deploy-apps.sh`

```bash
# Get IMDSv2 token
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)

# Use token to fetch metadata
PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s \
  http://169.254.169.254/latest/meta-data/public-ipv4)
```

### 4. **Port-Forward Access Issues**

**Problem:**
- Users needed to run `kubectl port-forward` for each service
- Ports 3000, 8081, 9090 not in security group
- Port-forward with `--address 0.0.0.0` had binding issues

**Root Cause:**
- Services using ClusterIP (internal only)
- Custom ports not allowed in security group
- Only NodePort range (30000-32767) was open

**Solution:**
- Configured all services to use NodePort
- NodePort range already allowed in security group
- No infrastructure changes needed

**Files Modified:**
- `monitoring/helm-values/prometheus-minimal-values.yaml`
- `argocd/argocd-nodeport.yaml` (new file)
- `terraform/deploy-apps.sh` (apply NodePort configs)

### 5. **Hardcoded Instance Type in Messages**

**Problem:**
- Script always showed "Installing for t2.micro" regardless of actual instance

**Root Cause:**
- Instance type was hardcoded in deploy script

**Solution:**
- Pass instance_type from Terraform through user-data to deploy script

**Files Modified:**
- `terraform/modules/ec2/main.tf` - added instance_type to templatefile
- `terraform/user-data.sh` - receives and exports INSTANCE_TYPE
- `terraform/deploy-apps.sh` - displays actual instance type

---

## File Structure

```
terraform/
├── main.tf                  # Root module - orchestrates all modules
├── variables.tf             # Variable definitions with validation
├── terraform.tfvars         # Variable values (NOT committed to Git)
├── outputs.tf               # Output definitions
├── provider.tf              # AWS provider configuration
│
├── modules/                 # Reusable Terraform modules
│   ├── vpc/                # VPC, subnets, IGW, route tables
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── security/           # Security groups
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── iam/                # IAM roles and policies
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── ec2/                # EC2 instance configuration
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── user-data.sh            # EC2 initialization script (runs on boot)
│                           # Installs: K3s, Helm, kubectl
│                           # Downloads: deployment configs
│
├── deploy-apps.sh          # Application deployment script
│                           # Run via SSH after instance is ready
│                           # Installs: Prometheus, Grafana, ArgoCD, App
│
└── README.md               # This file

Note: .tfstate files and .terraform/ are auto-ignored by root .gitignore
```

---

## Troubleshooting

### K3s Installation Logs

```bash
# SSH to instance
ssh -i ~/.ssh/quakewatch-key.pem ubuntu@<PUBLIC_IP>

# View installation log
cat /var/log/k3s-install.log

# Check cloud-init logs
sudo cat /var/log/cloud-init-output.log

# K3s service status
sudo systemctl status k3s
sudo journalctl -u k3s -f
```

### Verify K3s Cluster

```bash
# Check nodes
kubectl get nodes -o wide

# Check all pods
kubectl get pods -A

# Check services
kubectl get svc -A

# Check deployments
kubectl get deployments -A
```

### Application Deployment Issues

```bash
# Check if deployment script completed
ls -la ~/deploy-apps.sh
ls -la ~/deploy_config/

# Re-run deployment
./deploy-apps.sh

# Check ArgoCD application sync status
kubectl get application -n argocd
kubectl describe application earthquake-app -n argocd
```

### Grafana Not Loading

```bash
# Check pod status
kubectl get pods -n monitoring | grep grafana

# View logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=100

# Check resource usage
kubectl top pod -n monitoring

# Restart Grafana
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
```

### Networking Issues

```bash
# Test NodePort services from instance
curl http://localhost:32000        # QuakeWatch app
curl http://localhost:30300        # Grafana
curl http://localhost:30900        # Prometheus

# Check security group
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw security_group_id)

# Verify public IP
curl http://169.254.169.254/latest/meta-data/public-ipv4
```

### Terraform State Issues

```bash
# View current state
terraform show

# List all resources
terraform state list

# View specific resource
terraform state show module.ec2.aws_instance.k3s_server

# Refresh state
terraform refresh

# Remove stuck resource (use with caution!)
terraform state rm aws_instance.k3s_server
```

---

## Cost Management

### Current Configuration Cost

**Instance**: t3a.medium (2 vCPU, 4GB RAM)
- **Hourly**: ~$0.0376/hour
- **Monthly**: ~$27.41/month (730 hours)
- **Daily**: ~$0.90/day
- **NOT included in AWS free tier**

**EBS Storage**: 20 GB gp2
- **Monthly**: ~$2.00/month
- **Free tier**: First 30 GB free for 12 months

**Data Transfer**:
- **Inbound**: FREE
- **Outbound**: First 100 GB/month FREE
- After free tier: $0.09/GB

**Total Estimated Monthly Cost**: ~$29-30/month

### Free Tier Alternative

To use free tier, change instance type to t2.micro:

```hcl
# terraform.tfvars
instance_type = "t2.micro"  # 1 vCPU, 1 GB RAM (free tier)
```

**Warning**: t2.micro may not have enough resources for all services to run smoothly.

### Cost Optimization

**1. Stop Instance When Not in Use:**
```bash
# Stop instance (data preserved, billing stops)
aws ec2 stop-instances --instance-ids $(terraform output -raw instance_id)

# Start later
aws ec2 start-instances --instance-ids $(terraform output -raw instance_id)

# Check status
aws ec2 describe-instances --instance-ids $(terraform output -raw instance_id) \
  --query 'Reservations[0].Instances[0].State.Name'
```

**2. Destroy EC2 Only (Keep VPC):**
```bash
# Destroy only the EC2 instance
terraform destroy -target=module.ec2

# Recreate later
terraform apply -target=module.ec2
```

**3. Destroy Everything:**
```bash
# Remove all resources
terraform destroy
# Type 'yes' to confirm
```

**4. Set Billing Alerts:**
```bash
# AWS Console → Billing → Budgets → Create Budget
# Set threshold: $10, $25, $50
# Get email alerts before overspending
```

---

## Security Best Practices

### ✅ DO:

- Use your specific IP for `allowed_ssh_cidr` (not 0.0.0.0/0)
- Keep `terraform.tfvars` out of version control (already in .gitignore)
- Use strong, random K3s tokens (`openssl rand -hex 32`)
- Enable MFA on AWS account
- Rotate SSH keys and K3s tokens periodically
- Review security group rules regularly
- Use AWS Systems Manager Session Manager as backup access
- Enable CloudTrail for audit logging

### ❌ DON'T:

- Share SSH private keys
- Commit `.tfstate` files to Git (already in .gitignore)
- Open SSH (port 22) to 0.0.0.0/0
- Use weak or predictable K3s tokens
- Leave unused resources running
- Store AWS credentials in code
- Use root AWS account for daily operations

---

## Advanced Configuration

### Change Instance Type

```hcl
# terraform.tfvars
instance_type = "t3a.small"    # 2 vCPU, 2 GB RAM
# instance_type = "t3a.medium"  # 2 vCPU, 4 GB RAM (current)
# instance_type = "t3a.large"   # 2 vCPU, 8 GB RAM
```

### Change Region

```hcl
# terraform.tfvars
aws_region = "us-west-2"

# IMPORTANT: Also update AMI ID for new region
# Find AMIs: https://cloud-images.ubuntu.com/locator/ec2/
ami_id = "ami-xxxxxxxxx"  # Ubuntu 24.04 LTS for us-west-2
```

### Add Worker Nodes

Terraform is currently configured for a single-node cluster. To add workers, modify:
1. `modules/ec2/main.tf` - add count parameter
2. `variables.tf` - add worker node configuration
3. `user-data.sh` - change from `server` to `agent` mode for workers

---

## Next Steps

1. **Deploy Applications**: Run `./deploy-apps.sh` on EC2 instance
2. **Set up Custom Domain**: Point DNS A record to instance IP
3. **Add TLS/SSL**: Use cert-manager with Let's Encrypt
4. **Configure Backups**: Set up automated snapshots
5. **Add Monitoring Alerts**: Configure Alertmanager for notifications
6. **Scale Horizontally**: Add worker nodes for high availability

---

## Support & Resources

- **Main README**: See [../README.md](../README.md) for application deployment guide
- **Terraform AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- **K3s Documentation**: https://docs.k3s.io/
- **AWS Free Tier**: https://aws.amazon.com/free/
- **Terraform Best Practices**: https://www.terraform-best-practices.com/

---

## License

This infrastructure configuration is part of the QuakeWatch DevOps learning project demonstrating production-ready cloud infrastructure patterns.
