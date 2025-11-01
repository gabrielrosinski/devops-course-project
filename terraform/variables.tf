# =============================================================================
# Terraform Variables for K3s on AWS
# =============================================================================
# Variables make your Terraform configuration reusable and customizable.
# Values are set in terraform.tfvars or passed via CLI.

# =============================================================================
# General Configuration
# =============================================================================

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "quakewatch"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens"
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod"
  }
}

# =============================================================================
# AWS Configuration
# =============================================================================

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

# =============================================================================
# VPC Configuration
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC (10.0.0.0/16 = 65,536 IP addresses)"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block"
  }
}

variable "public_subnet_1_cidr" {
  description = "CIDR block for public subnet 1 (10.0.1.0/24 = 256 IPs)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_2_cidr" {
  description = "CIDR block for public subnet 2 (10.0.2.0/24 = 256 IPs)"
  type        = string
  default     = "10.0.2.0/24"
}

# =============================================================================
# EC2 Configuration
# =============================================================================

variable "instance_type" {
  description = "EC2 instance type (t2.micro = free tier, 1 vCPU, 1GB RAM)"
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  description = "AMI ID for EC2 instance (Ubuntu Server 24.04 LTS in us-east-1)"
  type        = string
  default     = "ami-0360c520857e3138f"

  # NOTE: AMI IDs are region-specific!
  # This ID is for Ubuntu 24.04 LTS in us-east-1.
  # Find AMIs at: https://cloud-images.ubuntu.com/locator/ec2/
  # Or use: aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-24.04-amd64-server-*"
}

variable "key_name" {
  description = "SSH key pair name for EC2 access (must exist in AWS first)"
  type        = string

  # IMPORTANT: Create this key pair in AWS Console or CLI BEFORE running Terraform!
  # AWS Console: EC2 > Key Pairs > Create Key Pair
  # CLI: aws ec2 create-key-pair --key-name my-key --query 'KeyMaterial' --output text > my-key.pem
}

variable "root_volume_size" {
  description = "Size of root EBS volume in GB (free tier includes 30 GB)"
  type        = number
  default     = 20

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 30
    error_message = "Root volume size must be between 8 GB and 30 GB for free tier"
  }
}

# =============================================================================
# Security Configuration
# =============================================================================

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH and access K3s API (use YOUR public IP/32)"
  type        = string

  # SECURITY: Set this to YOUR public IP address!
  # Find your IP: curl ifconfig.me
  # Format: x.x.x.x/32 (the /32 means only that one IP)
  # Example: "203.0.113.42/32"
  #
  # NEVER use "0.0.0.0/0" - that opens SSH to the entire internet!

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "allowed_ssh_cidr must be a valid CIDR block (e.g., 203.0.113.42/32)"
  }
}

# =============================================================================
# K3s Configuration
# =============================================================================

variable "k3s_version" {
  description = "K3s version to install (format: v1.28.5+k3s1)"
  type        = string
  default     = "v1.28.5+k3s1"

  # Find versions at: https://github.com/k3s-io/k3s/releases
  # Use stable releases (not rc or alpha)
  # Format: v1.28.5+k3s1

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$", var.k3s_version))
    error_message = "K3s version must be in format: v1.28.5+k3s1"
  }
}

variable "k3s_token" {
  description = "K3s cluster token for node authentication (keep secret!)"
  type        = string
  sensitive   = true  # Hides value in Terraform output

  # This token is used when joining additional nodes to the cluster.
  # Generate a random token: openssl rand -hex 32
  # Or use any long random string.
  #
  # SECURITY: Keep this secret! Anyone with this token can join your cluster.

  validation {
    condition     = length(var.k3s_token) >= 16
    error_message = "K3s token must be at least 16 characters for security"
  }
}
