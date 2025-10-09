#  resource "aws_vpc" "main" {
#     cidr_block           = "10.0.0.0/16"
#     enable_dns_hostnames = true
#     enable_dns_support   = true

#     tags = {
#       Name = "earthquake-vpc"
#     }
#   }

#   # Internet Gateway
#   resource "aws_internet_gateway" "main" {
#     vpc_id = aws_vpc.main.id

#     tags = {
#       Name = "earthquake-igw"
#     }
#   }

#   # Public Subnet 1 (us-east-1a)
#   resource "aws_subnet" "public_1" {
#     vpc_id                  = aws_vpc.main.id
#     cidr_block              = "10.0.1.0/24"
#     availability_zone       = "us-east-1a"
#     map_public_ip_on_launch = true

#     tags = {
#       Name = "public-subnet-1a"
#     }
#   }

#   # Public Subnet 2 (us-east-1b) - For high availability
#   resource "aws_subnet" "public_2" {
#     vpc_id                  = aws_vpc.main.id
#     cidr_block              = "10.0.2.0/24"
#     availability_zone       = "us-east-1b"
#     map_public_ip_on_launch = true

#     tags = {
#       Name = "public-subnet-1b"
#     }
#   }

#   # Private Subnet 1 (future use - databases, internal services)
#   resource "aws_subnet" "private_1" {
#     vpc_id            = aws_vpc.main.id
#     cidr_block        = "10.0.10.0/24"
#     availability_zone = "us-east-1a"

#     tags = {
#       Name = "private-subnet-1a"
#     }
#   }

#   # Private Subnet 2
#   resource "aws_subnet" "private_2" {
#     vpc_id            = aws_vpc.main.id
#     cidr_block        = "10.0.11.0/24"
#     availability_zone = "us-east-1b"

#     tags = {
#       Name = "private-subnet-1b"
#     }
#   }

#   # Route Table for Public Subnets
#   resource "aws_route_table" "public" {
#     vpc_id = aws_vpc.main.id

#     route {
#       cidr_block = "0.0.0.0/0"
#       gateway_id = aws_internet_gateway.main.id
#     }

#     tags = {
#       Name = "public-route-table"
#     }
#   }

#   # Associate Public Subnet 1 with Route Table
#   resource "aws_route_table_association" "public_1" {
#     subnet_id      = aws_subnet.public_1.id
#     route_table_id = aws_route_table.public.id
#   }

#   # Associate Public Subnet 2 with Route Table
#   resource "aws_route_table_association" "public_2" {
#     subnet_id      = aws_subnet.public_2.id
#     route_table_id = aws_route_table.public.id
#   }

#   Then update ec2.tf:
#   resource "aws_instance" "web" {
#     ami           = "ami-0360c520857e3138f"
#     instance_type = var.instance_type
#     key_name      = var.key_name
    
#     subnet_id              = aws_subnet.public_1.id  # Add this line
#     vpc_security_group_ids = [aws_security_group.web_sg.id]

#     tags = {
#       Name = "earthquake-web"
#     }
#   }

#   Update security.tf - Add VPC ID:
#   resource "aws_security_group" "web_sg" {
#     name        = "earthquake-web-sg"
#     description = "Allow SSH, HTTP, Docker, Flask"
#     vpc_id      = aws_vpc.main.id  # Add this line
    
#     # ... rest of your ingress/egress rules
#   }

#   Add to outputs.tf:
#   output "vpc_id" {
#     value = aws_vpc.main.id
#   }

#   output "public_subnet_ids" {
#     value = [aws_subnet.public_1.id, aws_subnet.public_2.id]
#   }


# also check if there are other vpc configc in other files that needs to be removed