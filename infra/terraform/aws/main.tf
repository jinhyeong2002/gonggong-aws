provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  azs         = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  app_subnet_ids       = var.enable_nat_gateway ? aws_subnet.private_app[*].id : aws_subnet.public[*].id
  ecs_assign_public_ip = var.enable_nat_gateway ? false : true
  container_image      = var.container_image != "" ? var.container_image : "${aws_ecr_repository.app.repository_url}:latest"
}

