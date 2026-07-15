variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name used for AWS resource names."
  type        = string
  default     = "gonggong"
}

variable "environment" {
  description = "Environment name, for example demo, staging, or prod."
  type        = string
  default     = "demo"
}

variable "az_count" {
  description = "Number of availability zones to use."
  type        = number
  default     = 2
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "enable_nat_gateway" {
  description = "When true, ECS tasks run in private subnets with outbound internet through one NAT Gateway. When false, tasks run in public subnets to reduce MVP cost."
  type        = bool
  default     = false
}

variable "container_image" {
  description = "Full container image URI. Leave empty to use the ECR repository created by this stack with the latest tag."
  type        = string
  default     = ""
}

variable "container_port" {
  description = "Spring Boot container port."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "ALB health check path. Add Spring Boot Actuator before using the default in production."
  type        = string
  default     = "/actuator/health"
}

variable "ecs_health_check_grace_period_seconds" {
  description = "Seconds ECS should ignore load balancer health checks after task start."
  type        = number
  default     = 180
}

variable "desired_count" {
  description = "Number of ECS tasks."
  type        = number
  default     = 1
}

variable "task_cpu" {
  description = "ECS task CPU units."
  type        = number
  default     = 1024
}

variable "task_memory" {
  description = "ECS task memory in MiB."
  type        = number
  default     = 2048
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "gonggong"
}

variable "db_username" {
  description = "RDS master username."
  type        = string
  default     = "gonggong"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GiB."
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16"
}

variable "db_backup_retention_period" {
  description = "RDS backup retention period in days."
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying RDS. Keep true only for demo/staging."
  type        = bool
  default     = true
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener. Leave empty to expose only HTTP."
  type        = string
  default     = ""
}

variable "allowed_http_cidr_blocks" {
  description = "CIDR blocks allowed to reach the public ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "openai_model" {
  description = "OpenAI chat/reasoning model name passed to the app."
  type        = string
  default     = "gpt-5.5"
}

variable "openai_embedding_model" {
  description = "OpenAI embedding model name passed to the app."
  type        = string
  default     = "text-embedding-3-small"
}

variable "pgvector_initialize_schema" {
  description = "Whether Spring AI PgVectorStore should initialize its schema on startup."
  type        = bool
  default     = false
}

variable "customs_confirmation_api_url" {
  description = "Customs confirmation API URL passed to the app. Leave empty to disable the optional customs confirmation lookup."
  type        = string
  default     = ""
}

variable "spring_jpa_hibernate_ddl_auto" {
  description = "Hibernate ddl-auto mode passed to the app. Use update for demo bootstrap and validate after schema is managed."
  type        = string
  default     = "validate"
}

variable "hsk_embedding_initialize" {
  description = "Whether the ECS service should initialize HSK embeddings on startup. Prefer false for long-running services."
  type        = bool
  default     = false
}

variable "hsk_dataset_initialize" {
  description = "Whether the ECS service should initialize the HSK dataset on startup."
  type        = bool
  default     = true
}

variable "tariff_dataset_initialize" {
  description = "Whether the ECS service should initialize the tariff dataset on startup."
  type        = bool
  default     = true
}
