terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"  # Change if needed
}

# ECR Repository
resource "aws_ecr_repository" "simple_backend" {
  name                 = "simple-backend"
  image_tag_mutability = "MUTABLE"
}

# EKS Cluster
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 19.0"
  cluster_name    = "simple-eks-cluster"
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    default = {
      min_size     = 1
      max_size     = 3
      desired_size = 2

      instance_types = ["t3.small"]
      capacity_type  = "ON_DEMAND"
    }
  }

  # Enable IAM roles for service accounts
  enable_irsa = true
}

# Basic VPC (for EKS)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "simple-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true
}

# Output ECR URL and EKS endpoint
output "ecr_repository_url" {
  value = aws_ecr_repository.simple_backend.repository_url
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_kubeconfig" {
  value = module.eks.kubeconfig
}

# RDS PostgreSQL
resource "aws_db_subnet_group" "simple_rds" {
  name       = "simple-rds-subnet-group"
  subnet_ids = module.vpc.private_subnets  # Use private subnets for security

  tags = {
    Name = "Simple RDS Subnet Group"
  }
}

resource "aws_db_instance" "simple_backend_db" {
  identifier = "simple-backend-db"

  # Engine
  engine         = "postgres"
  engine_version = "15.5"  # Latest stable as of 2025

  # Instance
  instance_class    = "db.t3.micro"  # Free tier eligible
  allocated_storage = 20
  storage_type      = "gp2"
  storage_encrypted = true

  # Credentials (generate secure password; in prod, use Secrets Manager)
  username = "admin"
  password = "SecurePass123!"  # CHANGE THIS! Use random gen or var

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.simple_rds.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]  # Allow EKS access
  skip_final_snapshot = true  # For testing; set false in prod

  # Multi-AZ for HA (optional, adds cost)
  multi_az = false

  # Backup/Maintenance
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "Sun:00:00-Sun:03:00"

  tags = {
    Name = "Simple Backend DB"
  }
}

# Security Group for RDS (allow inbound from EKS nodes)
resource "aws_security_group" "rds_sg" {
  name_prefix = "simple-rds-sg-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 5432  # Postgres port
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]  # Restrict to VPC
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Simple RDS SG"
  }
}

# Outputs
output "rds_endpoint" {
  value = aws_db_instance.simple_backend_db.endpoint
}

output "rds_port" {
  value = aws_db_instance.simple_backend_db.port
}

output "rds_username" {
  value = aws_db_instance.simple_backend_db.username
}

output "rds_password" {
  sensitive = true
  value     = aws_db_instance.simple_backend_db.password
}