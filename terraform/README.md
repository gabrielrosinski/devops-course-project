# Terraform Configuration for K3s on AWS

Complete infrastructure-as-code setup for deploying K3s (lightweight Kubernetes) on AWS EC2 with proper VPC, IAM, and security configurations.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                      AWS Cloud                          │
│                                                         │
│  ┌───────────────────────────────────────────────────┐ │
│  │              VPC (10.0.0.0/16)                    │ │
│  │                                                   │ │
│  │  ┌─────────────────┐  ┌─────────────────┐        │ │
│  │  │ Public Subnet 1 │  │ Public Subnet 2 │        │ │
│  │  │  (10.0.1.0/24)  │  │  (10.0.2.0/24)  │        │ │
│  │  │                 │  │                 │        │ │
│  │  │  ┌───────────┐  │  │                 │        │ │
│  │  │  │   EC2     │  │  │  (Future nodes) │        │ │
│  │  │  │ t2.micro  │  │  │                 │        │ │
│  │  │  │           │  │  │                 │        │ │
│  │  │  │ K3s Server│  │  │                 │        │ │
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
                  │   (Your PC)     │
                  └─────────────────┘
```

## Resources Created

| Resource | Type | Purpose | Cost |
|----------|------|---------|------|
| VPC | Network | Isolated network environment | FREE |
| Internet Gateway | Network | Internet connectivity | FREE |
| 2 Public Subnets | Network | High availability zones | FREE |
| Route Tables | Network | Traffic routing | FREE |
| Security Group | Security | Firewall rules | FREE |
| IAM Role + Profile | Security | AWS permissions | FREE |
| EC2 Instance | Compute | K3s server node | FREE (t2.micro) |
| EBS Volume | Storage | 20 GB disk | FREE (30 GB limit) |

**Total Monthly Cost: $0** (within free tier limits)

## Prerequisites

### 1. AWS Account Setup
- [ ] AWS account with free tier eligibility
- [ ] AWS CLI installed and configured
  ```bash
  aws configure
  # Enter: Access Key ID, Secret Access Key, Region (us-east-1), Output format (json)
  ```
- [ ] Verify access:
  ```bash
  aws sts get-caller-identity
  ```

### 2. SSH Key Pair
Create an EC2 key pair for SSH access:

**Option A: AWS Console**
1. Go to AWS Console > EC2 > Key Pairs
2. Click "Create Key Pair"
3. Name: `quakewatch-key`
4. Type: RSA
5. Format: `.pem`
6. Download and save securely
7. Set permissions: `chmod 400 ~/Downloads/quakewatch-key.pem`

**Option B: AWS CLI**
```bash
aws ec2 create-key-pair \
  --key-name quakewatch-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/quakewatch-key.pem

chmod 400 ~/.ssh/quakewatch-key.pem
```

### 3. Terraform Installation
**macOS:**
```bash
brew install terraform
```

**Linux:**
```bash
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

**Windows:**
Download from [terraform.io](https://www.terraform.io/downloads)

Verify installation:
```bash
terraform version
```

## Configuration

### 1. Update terraform.tfvars

Edit `terraform.tfvars` and replace these values:

```hcl
# Your AWS SSH key pair name
key_name = "quakewatch-key"  # Replace with your actual key name

# Your public IP address (find it: curl ifconfig.me)
allowed_ssh_cidr = "203.0.113.42/32"  # Replace with YOUR IP

# Generate a secure K3s token (run: openssl rand -hex 32)
k3s_token = "abc123..."  # Replace with random token
```

### 2. Generate K3s Token

```bash
# Generate a secure random token
openssl rand -hex 32

# Copy the output to terraform.tfvars
```

## Deployment Steps

### Step 1: Initialize Terraform

```bash
cd terraform
terraform init
```

This downloads required AWS provider plugins.

### Step 2: Validate Configuration

```bash
terraform validate
```

Check for syntax errors.

### Step 3: Plan Infrastructure

```bash
terraform plan
```

Review what will be created:
- 1 VPC
- 2 Subnets
- 1 Internet Gateway
- 1 Route Table
- 1 Security Group
- 1 IAM Role + Profile
- 1 EC2 Instance

### Step 4: Apply Configuration

```bash
terraform apply
```

- Type `yes` when prompted
- Wait 5-10 minutes for:
  - AWS resources to be created
  - EC2 instance to boot
  - K3s to install (via user-data script)

### Step 5: Get Outputs

```bash
# View all outputs
terraform output

# View specific output
terraform output instance_public_ip
terraform output helpful_commands
```

## Accessing Your K3s Cluster

### Option 1: SSH to Instance

```bash
# Replace with your key name and IP (from terraform output)
ssh -i ~/.ssh/quakewatch-key.pem ubuntu@<INSTANCE_PUBLIC_IP>

# Once connected, verify K3s:
kubectl get nodes
kubectl get pods -A
```

### Option 2: Remote kubectl Access

```bash
# Copy kubeconfig to your local machine
scp -i ~/.ssh/quakewatch-key.pem ubuntu@<IP>:/etc/rancher/k3s/k3s.yaml ~/.kube/quakewatch-config

# Update server IP in config
sed -i 's|https://127.0.0.1:6443|https://<IP>:6443|g' ~/.kube/quakewatch-config

# Use the config
export KUBECONFIG=~/.kube/quakewatch-config
kubectl get nodes
```

## Deploying QuakeWatch Application

Once K3s is running, SSH to your instance and run the deployment script:

```bash
# SSH to instance
ssh -i ~/.ssh/quakewatch-key.pem ubuntu@<INSTANCE_PUBLIC_IP>

# Run the deployment script (included in the repo)
./deploy-apps.sh
```

The script will automatically:
1. Install Prometheus & Grafana monitoring stack
2. Install ArgoCD for GitOps deployment
3. Deploy QuakeWatch application via ArgoCD
4. Display access credentials and URLs

### Manual Deployment (Alternative)

If you prefer manual deployment:

```bash
# Apply Kubernetes manifests
kubectl apply -f ../k8s/

# Check deployment
kubectl get deployments
kubectl get pods
kubectl get services

# Get service URL (update port based on your service)
terraform output quakewatch_nodeport_url
```

## Troubleshooting

### K3s Installation Logs

```bash
ssh -i ~/.ssh/quakewatch-key.pem ubuntu@<IP>
cat /var/log/k3s-install.log
```

### K3s Service Status

```bash
ssh -i ~/.ssh/quakewatch-key.pem ubuntu@<IP>
sudo systemctl status k3s
sudo journalctl -u k3s -f
```

### Terraform State Issues

```bash
# View current state
terraform show

# List resources
terraform state list

# Remove stuck resource
terraform state rm aws_instance.k3s_server
```

## Cost Management

### Monitor AWS Free Tier Usage

1. AWS Console > Billing > Free Tier
2. Check usage for:
   - EC2 (750 hours/month limit)
   - EBS (30 GB limit)
   - Data transfer (15 GB/month out)

### Stop Instance (Save Hours)

```bash
# Stop instance (keeps data, stops hourly billing)
aws ec2 stop-instances --instance-ids $(terraform output -raw instance_id)

# Start instance later
aws ec2 start-instances --instance-ids $(terraform output -raw instance_id)
```

### Destroy Everything

```bash
# Remove all resources (irreversible!)
terraform destroy
```

Type `yes` to confirm. This deletes:
- EC2 instance and disk
- VPC and networking
- Security groups
- IAM roles

## File Structure

```
terraform/
├── provider.tf          # AWS provider configuration
├── vpc.tf               # VPC, subnets, IGW, route tables
├── security.tf          # Security groups (firewall rules)
├── iam.tf               # IAM roles and policies
├── ec2.tf               # EC2 instance configuration
├── variables.tf         # Variable definitions
├── terraform.tfvars     # Variable values (DO NOT COMMIT!)
├── output.tf            # Output definitions
├── user-data.sh         # K3s + Helm installation script (runs on boot)
├── deploy-apps.sh       # Application deployment script (run via SSH)
└── README.md            # This file

Note: Terraform-specific files (*.tfstate, *.tfvars, .terraform/) are
ignored by the root .gitignore file.
```

## Security Best Practices

✅ **DO:**
- Keep `terraform.tfvars` out of Git (handled by root `.gitignore`)
- Use your specific IP for `allowed_ssh_cidr` (not 0.0.0.0/0)
- Rotate your K3s token periodically
- Enable MFA on your AWS account
- Use AWS SSM Session Manager as backup access

❌ **DON'T:**
- Share your SSH private key
- Commit `.tfstate` files to Git (auto-ignored by root `.gitignore`)
- Open SSH to 0.0.0.0/0 (entire internet)
- Use weak K3s tokens

## Next Steps

1. **Deploy QuakeWatch**: Apply your Kubernetes manifests
2. **Set up DNS**: Point domain to instance IP
3. **Add SSL**: Use Let's Encrypt with cert-manager
4. **Scale**: Add worker nodes by adjusting configuration
5. **Monitor**: Set up CloudWatch alarms for CPU/memory

## Support

- **Terraform Docs**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- **K3s Docs**: https://docs.k3s.io/
- **AWS Free Tier**: https://aws.amazon.com/free/

## License

This configuration is part of the QuakeWatch DevOps learning project.
