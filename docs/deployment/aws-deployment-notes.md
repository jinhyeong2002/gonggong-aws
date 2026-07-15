# AWS Deployment Notes

## Context

This project is a Spring Boot API service with PostgreSQL and pgvector.

- Runtime: Java 17, Spring Boot
- Build: Gradle
- Database: PostgreSQL with pgvector
- Local database: `docker-compose.yml` uses `pgvector/pgvector:pg16`
- Secrets/API keys: OpenAI, Safety Korea, Customs, Chemical API, database credentials
- Browser extension: `extension/` calls the backend API, but is deployed separately from AWS backend infrastructure

The current `application.yaml` already reads most operational settings from environment variables:

- `DB_URL`
- `DB_USER`
- `DB_PASSWORD`
- `OPENAI_API_KEY`
- `OPENAI_MODEL`
- `OPENAI_EMBEDDING_MODEL`
- `SAFETY_KOREA_API_KEY`
- `CUSTOMS_API_KEY`
- `CHEMICAL_API_KEY`
- `CUSTOMS_CONFIRMATION_API_URL`
- `CUSTOMS_CONFIRMATION_SERVICE_KEY`

Local development can use `env/local.env`, but production should not use a committed `.env` file.

## Recommended AWS Architecture

Use ECS Fargate for the Spring Boot API and RDS PostgreSQL for the database.

```text
User / Browser Extension
        |
        v
Route 53 + ACM
        |
        v
Application Load Balancer
        |
        v
ECS Fargate - Spring Boot API
        |
        +--> RDS PostgreSQL with pgvector
        +--> AWS Secrets Manager / SSM Parameter Store
        +--> CloudWatch Logs
        +--> External APIs: OpenAI, Safety Korea, Customs, Chemical API
```

Recommended services:

- ECR: store Docker images
- ECS Fargate: run the Spring Boot container
- Application Load Balancer: public HTTPS entry point
- RDS PostgreSQL: managed database
- Secrets Manager: API keys and DB password
- CloudWatch Logs: application logs
- Route 53 and ACM: domain and TLS certificate

## VPC Layout

```text
VPC
├─ Public Subnet A/B
│  └─ Application Load Balancer
├─ Private App Subnet A/B
│  └─ ECS Fargate Tasks
└─ Private DB Subnet A/B
   └─ RDS PostgreSQL
```

Security group rules:

- ALB: allow inbound `443` from the internet
- ECS task: allow inbound app port only from the ALB security group
- RDS: allow inbound `5432` only from the ECS task security group
- ECS outbound: allow external API calls through NAT Gateway

Because this service calls OpenAI and public-data APIs, ECS tasks need outbound internet access. The default production-friendly setup is private subnets plus NAT Gateway.

## Secret Handling

Do not upload production `.env` files to GitHub, Docker images, EC2 disks, or S3 buckets.

Production secrets should live in AWS Secrets Manager or SSM Parameter Store SecureString.

Recommended mapping:

```text
Secrets Manager
  ├─ OPENAI_API_KEY
  ├─ SAFETY_KOREA_API_KEY
  ├─ CUSTOMS_API_KEY
  ├─ CHEMICAL_API_KEY
  └─ DB_PASSWORD

ECS Task Definition
  └─ injects secrets as environment variables

Spring Boot
  └─ reads them through application.yaml placeholders
```

The `.env` file is not placed inside a private VPC. Instead, the app runs in a private subnet and receives secrets from AWS at runtime through IAM-authorized secret injection.

Suggested local/production split:

- Local: `env/local.env`
- Git: only `env/.env.example`
- AWS production: Secrets Manager values injected into ECS

## Environment Variables For ECS

Non-secret values can be plain environment variables:

```text
DB_URL=jdbc:postgresql://<rds-endpoint>:5432/gonggong
DB_USER=gonggong
OPENAI_MODEL=gpt-5.5
OPENAI_EMBEDDING_MODEL=text-embedding-3-small
HSK_EMBEDDING_INITIALIZE=false
HSK_EMBEDDING_BATCH_SIZE=100
SAFETY_KOREA_API_URL=https://www.safetykorea.kr/release/openapi
OPENAI_RESPONSES_API_URL=https://api.openai.com/v1/responses
UNIPASS_URL=https://unipass.customs.go.kr/
PRODUCT_SAFETY_CENTER_URL=https://www.safetykorea.kr/
```

Secret values should come from Secrets Manager:

```text
DB_PASSWORD
OPENAI_API_KEY
SAFETY_KOREA_API_KEY
CUSTOMS_API_KEY
CHEMICAL_API_KEY
CUSTOMS_CONFIRMATION_SERVICE_KEY
```

## Database Notes

RDS PostgreSQL should have pgvector enabled.

The local Docker image already uses pgvector:

```yaml
image: pgvector/pgvector:pg16
```

On AWS, use RDS PostgreSQL and enable the vector extension in the target database:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

This project currently has `spring.ai.vectorstore.pgvector.initialize-schema: true`, so the app can initialize the vector store table. Confirm this behavior in staging before production.

## Production Configuration Risks

Before production, review these settings:

- `spring.jpa.hibernate.ddl-auto: update`
  - Good for local development.
  - Risky for production.
  - Prefer Flyway or Liquibase migrations.

- `spring.jpa.show-sql: true`
  - Useful locally.
  - Should be disabled in production.

- `HSK_EMBEDDING_INITIALIZE=true`
  - Can trigger expensive or slow embedding initialization on app startup.
  - For production, prefer a separate one-time job or set this to `false` after initialization.

- API keys
  - Must not be committed.
  - Must not be baked into Docker images.
  - Must be rotated if they were ever exposed.

## Deployment Pipeline

Recommended GitHub Actions flow:

```text
push to main
  |
  v
run tests
  |
  v
build Spring Boot jar
  |
  v
build Docker image
  |
  v
push image to ECR
  |
  v
update ECS service
```

Initial deployment can be manual, but CI/CD should be added once the infrastructure shape is stable.

## MVP Setup

Use this for first working deployment:

- ECS Fargate service with 1 task
- RDS PostgreSQL single-AZ
- ALB with HTTPS
- Secrets Manager for API keys
- CloudWatch Logs
- NAT Gateway for outbound API calls

This is enough for demo or early staging.

## Production Setup

Use this when the service needs higher availability:

- ECS Fargate service with at least 2 tasks across 2 AZs
- RDS PostgreSQL Multi-AZ
- ALB health checks
- ECS autoscaling
- CloudWatch alarms
- RDS automated backups and point-in-time recovery
- Separate staging and production environments
- Database migrations through Flyway or Liquibase

## Open Questions For Next Discussion

- Which domain will point to the API?
- Is the frontend only the Chrome extension, or will there also be a web app?
- Should the first AWS environment be demo, staging, or production?
- What monthly budget should the AWS architecture target?
- Should Terraform/CDK be used, or is console/manual setup acceptable for the first deployment?
- Should embeddings be initialized during deployment, through a one-time ECS task, or ahead of time?

## Next Implementation Steps

1. Add a production Spring profile.
2. Add a Dockerfile for the Spring Boot app.
3. Confirm application port and health check endpoint.
4. Decide whether to use Flyway/Liquibase.
5. Create RDS PostgreSQL with pgvector.
6. Store API keys in Secrets Manager.
7. Create ECR repository.
8. Create ECS cluster, task definition, and service.
9. Attach ALB and configure HTTPS.
10. Update Chrome extension API base URL to the production API domain.
