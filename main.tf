###############################################################
# main.tf – Root module
# Cloud Computing Project – Scalable & Highly-Available AWS App
###############################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

###############################################################
# Random suffix – keeps globally-unique names unique
###############################################################
resource "random_id" "suffix" {
  byte_length = 4
}

###############################################################
# Modules
###############################################################

module "networking" {
  source = "./modules/networking"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  public_subnets     = var.public_subnets
  private_subnets    = var.private_subnets
}

module "security" {
  source = "./modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.networking.vpc_id
  vpc_cidr     = var.vpc_cidr
}

module "iam" {
  source = "./modules/iam"

  project_name = var.project_name
  environment  = var.environment
  s3_bucket_arn = module.s3.bucket_arn
}

module "s3" {
  source = "./modules/s3"

  project_name = var.project_name
  environment  = var.environment
  suffix       = random_id.suffix.hex
}

module "rds" {
  source = "./modules/rds"

  project_name       = var.project_name
  environment        = var.environment
  db_subnet_group    = module.networking.db_subnet_group_name
  db_security_group  = module.security.rds_sg_id
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  db_instance_class  = var.db_instance_class
}

module "compute" {
  source = "./modules/compute"

  project_name         = var.project_name
  environment          = var.environment
  aws_region           = var.aws_region
  ami_id               = var.ami_id
  instance_type        = var.instance_type
  key_name             = var.key_name
  public_subnet_ids    = module.networking.public_subnet_ids
  private_subnet_ids   = module.networking.private_subnet_ids
  ec2_sg_id            = module.security.ec2_sg_id
  alb_sg_id            = module.security.alb_sg_id
  iam_instance_profile = module.iam.ec2_instance_profile_name
  s3_bucket_name       = module.s3.bucket_name
  rds_endpoint         = module.rds.db_endpoint
  db_name              = var.db_name
  db_username          = var.db_username
  db_password          = var.db_password
  asg_min_size         = var.asg_min_size
  asg_max_size         = var.asg_max_size
  asg_desired_capacity = var.asg_desired_capacity
  health_check_path    = var.health_check_path
  certificate_arn      = var.certificate_arn
}

module "monitoring" {
  source = "./modules/monitoring"

  project_name     = var.project_name
  environment      = var.environment
  asg_name         = module.compute.asg_name
  alb_arn_suffix   = module.compute.alb_arn_suffix
  tg_arn_suffix    = module.compute.tg_arn_suffix
  rds_identifier   = module.rds.db_identifier
  alarm_email      = var.alarm_email
  s3_log_bucket    = module.s3.log_bucket_name
}
