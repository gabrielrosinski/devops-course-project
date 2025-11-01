# =============================================================================
# VPC Configuration for K3s Cluster
# =============================================================================
# This VPC provides isolated networking for our K3s cluster.
# CIDR 10.0.0.0/16 gives us 65,536 IP addresses to work with.

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true  # Required: K3s needs DNS for service discovery
  enable_dns_support   = true  # Required: Enables DNS resolution within VPC

  tags = {
    Name        = "${var.project_name}-vpc"
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Environment = var.environment
  }
}

# =============================================================================
# Internet Gateway
# =============================================================================
# Allows communication between VPC and the internet.
# Required for: downloading K3s, pulling container images, public app access.

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name      = "${var.project_name}-igw"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# =============================================================================
# Public Subnets
# =============================================================================
# Public subnets have direct route to Internet Gateway.
# map_public_ip_on_launch = true → instances get public IPs automatically.
# We create 2 subnets in different AZs for high availability (future-proof).

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.project_name}-public-subnet-1"
    Project                  = var.project_name
    ManagedBy                = "Terraform"
    "kubernetes.io/role/elb" = "1"  # Tag for future K8s Load Balancer integration
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.project_name}-public-subnet-2"
    Project                  = var.project_name
    ManagedBy                = "Terraform"
    "kubernetes.io/role/elb" = "1" //This tells Kubernetes "you can create Load Balancers in this subnet"
  }
}

# =============================================================================
# Route Table for Public Subnets
# =============================================================================
# Routes all outbound traffic (0.0.0.0/0) through Internet Gateway.
# This makes the subnets "public" - they can reach the internet.

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name      = "${var.project_name}-public-rt"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# =============================================================================
# Route Table Associations
# =============================================================================
# Links our public subnets to the public route table.
# Without this, subnets would use the default (private) route table.

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# =============================================================================
# Data Source: Availability Zones
# =============================================================================
# Dynamically fetches available AZs in the selected region.
# Makes our config portable across different AWS regions.

data "aws_availability_zones" "available" {
  state = "available"
}
