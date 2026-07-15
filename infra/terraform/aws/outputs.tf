output "ecr_repository_url" {
  description = "ECR repository URL for the Spring Boot API image."
  value       = aws_ecr_repository.app.repository_url
}

output "alb_dns_name" {
  description = "Public ALB DNS name."
  value       = aws_lb.app.dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.app.name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint."
  value       = aws_db_instance.postgres.endpoint
}

output "app_secret_names" {
  description = "Secrets Manager names that must be populated before the ECS task can run successfully."
  value       = { for name, secret in aws_secretsmanager_secret.app : name => secret.name }
}

output "db_master_secret_arn" {
  description = "RDS managed master user secret ARN."
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
  sensitive   = true
}

