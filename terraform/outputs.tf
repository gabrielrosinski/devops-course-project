# =============================================================================
# Root Module Outputs
# =============================================================================
# Outputs from child modules aggregated at the root level

# =============================================================================
# VPC Outputs
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = module.vpc.public_subnet_ids
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = module.vpc.internet_gateway_id
}

# =============================================================================
# EC2 Instance Outputs
# =============================================================================

output "instance_id" {
  description = "ID of the K3s EC2 instance"
  value       = module.ec2.instance_id
}

output "instance_public_ip" {
  description = "Public IP address of K3s server"
  value       = module.ec2.instance_public_ip
}

output "instance_private_ip" {
  description = "Private IP address of K3s server"
  value       = module.ec2.instance_private_ip
}

output "instance_state" {
  description = "State of the EC2 instance"
  value       = module.ec2.instance_state
}

# =============================================================================
# IAM Outputs
# =============================================================================

output "iam_role_arn" {
  description = "ARN of the IAM role for K3s nodes"
  value       = module.iam.iam_role_arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = module.iam.iam_instance_profile_name
}

# =============================================================================
# Security Group Outputs
# =============================================================================

output "security_group_id" {
  description = "ID of the K3s security group"
  value       = module.security.security_group_id
}

# =============================================================================
# K3s Access Information
# =============================================================================

output "k3s_api_endpoint" {
  description = "K3s API endpoint URL"
  value       = "https://${module.ec2.instance_public_ip}:6443"
}

output "ssh_command" {
  description = "SSH command to connect to K3s server"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${module.ec2.instance_public_ip}"
}

output "kubeconfig_command" {
  description = "Command to retrieve kubeconfig from K3s server"
  value       = "scp -i ~/.ssh/${var.key_name}.pem ubuntu@${module.ec2.instance_public_ip}:/etc/rancher/k3s/k3s.yaml ~/.kube/config"
}

# =============================================================================
# Application Access
# =============================================================================

output "quakewatch_nodeport_url" {
  description = "URL to access QuakeWatch via NodePort (update port number after deployment)"
  value       = "http://${module.ec2.instance_public_ip}:30000"
}

output "quakewatch_http_url" {
  description = "URL to access QuakeWatch via HTTP (if using ingress or port 80)"
  value       = "http://${module.ec2.instance_public_ip}"
}

# =============================================================================
# Helpful Commands Output
# =============================================================================

output "helpful_commands" {
  description = "Helpful commands for managing your K3s cluster"
  value       = <<-EOT

    ===================================================================
    K3s Cluster Setup Complete!
    ===================================================================

    Instance Public IP: ${module.ec2.instance_public_ip}
    K3s API Endpoint:   https://${module.ec2.instance_public_ip}:6443

    -------------------------------------------------------------------
    STEP 1: Connect to Your Instance
    -------------------------------------------------------------------
    ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${module.ec2.instance_public_ip}

    -------------------------------------------------------------------
    STEP 2: Verify K3s is Running (on the instance)
    -------------------------------------------------------------------
    sudo systemctl status k3s
    kubectl get nodes
    kubectl get pods -A

    -------------------------------------------------------------------
    STEP 3: Get Kubeconfig for Local kubectl Access
    -------------------------------------------------------------------
    # Copy kubeconfig to your local machine:
    scp -i ~/.ssh/${var.key_name}.pem ubuntu@${module.ec2.instance_public_ip}:/etc/rancher/k3s/k3s.yaml ~/.kube/quakewatch-config

    # Update the server URL in the config:
    sed -i '' 's|https://127.0.0.1:6443|https://${module.ec2.instance_public_ip}:6443|g' ~/.kube/quakewatch-config

    # Use the config:
    export KUBECONFIG=~/.kube/quakewatch-config
    kubectl get nodes

    -------------------------------------------------------------------
    STEP 4: Deploy QuakeWatch Application
    -------------------------------------------------------------------
    # SSH to instance and run deployment script:
    ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${module.ec2.instance_public_ip}
    ./deploy-apps.sh

    -------------------------------------------------------------------
    STEP 5: Access Your Application
    -------------------------------------------------------------------
    NodePort:  http://${module.ec2.instance_public_ip}:30000
    HTTP:      http://${module.ec2.instance_public_ip}

    (Update port number based on your Service configuration)

    -------------------------------------------------------------------
    Useful Commands:
    -------------------------------------------------------------------
    # View K3s logs:
    ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${module.ec2.instance_public_ip} "sudo journalctl -u k3s -f"

    # Check user-data script log:
    ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${module.ec2.instance_public_ip} "cat /var/log/k3s-install.log"

    # Port forward a service (example):
    kubectl port-forward service/earthquake-service 8080:80

    ===================================================================

  EOT
}
