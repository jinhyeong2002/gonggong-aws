# Gonggong AWS Terraform

This stack creates a first AWS deployment target for the Spring Boot API:

- VPC with public, private app, and private DB subnets
- Optional NAT Gateway
- ECR repository
- ECS Fargate cluster, task definition, and service
- Public Application Load Balancer
- RDS PostgreSQL with AWS-managed master password
- Secrets Manager secrets for API keys
- CloudWatch Logs

## Cost Mode

The default `enable_nat_gateway = false` is for a low-cost MVP. ECS tasks run in public subnets but only accept inbound traffic from the ALB security group.

Set `enable_nat_gateway = true` for the production-style layout where ECS tasks run in private app subnets and use a NAT Gateway for OpenAI and public API calls.

## Usage

```bash
cd infra/terraform/aws
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

After apply, populate the app secrets. Example:

```bash
aws secretsmanager put-secret-value \
  --secret-id gonggong-demo/OPENAI_API_KEY \
  --secret-string 'replace-me'
```

Repeat for:

- `SAFETY_KOREA_API_KEY`
- `CUSTOMS_API_KEY`
- `CHEMICAL_API_KEY`
- `CUSTOMS_CONFIRMATION_SERVICE_KEY`

Then push the app image to ECR using the `ecr_repository_url` output and force a new ECS deployment.

## Important App Prerequisites

This Terraform assumes the app has:

- a container image available at `container_image` or `<created-ecr-repository>:latest`
- a production Spring profile named `prod`
- a health endpoint matching `health_check_path`, default `/actuator/health`

For the current app, add Spring Boot Actuator and a production profile before using the ALB health check in a real deployment.

After RDS is created, enable extensions in the database:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS hstore;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

