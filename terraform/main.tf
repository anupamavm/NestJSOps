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

# VPC (Network Layer)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "nestjsops-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true

  tags = {
    Name = "NestJSOps VPC"
  }
}

# Security Group for RDS (allow inbound from EKS nodes)
resource "aws_security_group" "rds_sg" {
  name_prefix = "nestjsops-rds-sg-"
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
    Name = "NestJSOps RDS SG"
  }
}

# EKS Cluster
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 19.0"
  cluster_name    = "nestjsops-eks-cluster"
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

  tags = {
    Name = "NestJSOps EKS Cluster"
  }
}

# RDS Subnet Group
resource "aws_db_subnet_group" "nestjsops_rds" {
  name       = "nestjsops-rds-subnet-group"
  subnet_ids = module.vpc.private_subnets  # Use private subnets for security

  tags = {
    Name = "NestJSOps RDS Subnet Group"
  }
}

# RDS PostgreSQL Database
resource "aws_db_instance" "nestjsops_db" {
  identifier = "nestjsops-backend-db"

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
  db_subnet_group_name   = aws_db_subnet_group.nestjsops_rds.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]  # Allow EKS access
  skip_final_snapshot    = true  # For testing; set false in prod

  # Multi-AZ for HA (optional, adds cost)
  multi_az = false

  # Backup/Maintenance
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Sun:00:00-Sun:03:00"

  tags = {
    Name = "NestJSOps Backend DB"
  }
}

# ECR Repository
resource "aws_ecr_repository" "nestjsops_backend" {
  name                 = "nestjsops-backend"
  image_tag_mutability = "MUTABLE"

  tags = {
    Name = "NestJSOps Backend Repository"
  }
}

# ===== OUTPUTS =====

# ECR
output "ecr_repository_url" {
  description = "ECR repository URL for pushing Docker images"
  value       = aws_ecr_repository.nestjsops_backend.repository_url
}

# EKS
output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_kubeconfig" {
  description = "Kubeconfig for EKS cluster"
  value       = module.eks.kubeconfig
  sensitive   = true
}

# RDS
output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.nestjsops_db.endpoint
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.nestjsops_db.port
}

output "rds_username" {
  description = "RDS master username"
  value       = aws_db_instance.nestjsops_db.username
}

output "rds_password" {
  description = "RDS master password"
  sensitive   = true
  value       = aws_db_instance.nestjsops_db.password
}

# VPC
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr_block
}