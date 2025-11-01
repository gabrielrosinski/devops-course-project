# =============================================================================
# Root Module - Main Configuration
# =============================================================================
# This file orchestrates all the child modules to create the complete
# K3s infrastructure on AWS

# =============================================================================
# Local Variables
# =============================================================================
# Common tags applied to all resources

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# =============================================================================
# VPC Module
# =============================================================================
# Creates VPC with public subnets, Internet Gateway, and routing

module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_1_cidr = var.public_subnet_1_cidr
  public_subnet_2_cidr = var.public_subnet_2_cidr
  tags                 = local.common_tags
}

# =============================================================================
# Security Module
# =============================================================================
# Creates security groups for K3s cluster nodes

module "security" {
  source = "./modules/security"

  project_name     = var.project_name
  vpc_id           = module.vpc.vpc_id
  vpc_cidr         = module.vpc.vpc_cidr
  allowed_ssh_cidr = var.allowed_ssh_cidr
  tags             = local.common_tags
}

# =============================================================================
# IAM Module
# =============================================================================
# Creates IAM roles and policies for K3s nodes

module "iam" {
  source = "./modules/iam"

  project_name = var.project_name
  aws_region   = var.aws_region
  tags         = local.common_tags
}

# =============================================================================
# EC2 Module
# =============================================================================
# Creates EC2 instance for K3s server

module "ec2" {
  source = "./modules/ec2"

  project_name              = var.project_name
  ami_id                    = var.ami_id
  instance_type             = var.instance_type
  key_name                  = var.key_name
  subnet_id                 = module.vpc.public_subnet_1_id
  security_group_ids        = [module.security.security_group_id]
  iam_instance_profile_name = module.iam.iam_instance_profile_name
  root_volume_size          = var.root_volume_size
  k3s_version               = var.k3s_version
  k3s_token                 = var.k3s_token
  user_data_script_path     = "${path.module}/user-data.sh"
  tags                      = local.common_tags
}
