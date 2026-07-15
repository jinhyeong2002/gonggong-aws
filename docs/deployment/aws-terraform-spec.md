# AWS Terraform Infrastructure Specification

## 목적

이 문서는 `infra/terraform/aws`에 작성한 Terraform 코드가 어떤 AWS 인프라를 만들고, 왜 그런 구성을 선택했는지 설명한다.

현재 프로젝트는 Spring Boot API 서버이고, PostgreSQL과 pgvector를 사용한다. 또한 OpenAI, Safety Korea, 관세청, 화학물질 API 같은 외부 API를 호출한다. 따라서 배포 인프라는 다음 조건을 만족해야 한다.

- Spring Boot API를 컨테이너로 실행할 수 있어야 한다.
- PostgreSQL에서 pgvector 확장을 사용할 수 있어야 한다.
- API 키와 DB 비밀번호를 코드나 이미지에 넣지 않아야 한다.
- 외부 API 호출을 위한 outbound 인터넷 접근이 가능해야 한다.
- 브라우저 extension이나 외부 클라이언트가 HTTPS로 API를 호출할 수 있어야 한다.
- 처음에는 비용을 낮추고, 나중에 운영형 구조로 확장할 수 있어야 한다.

## 전체 구조

```text
User / Browser Extension
        |
        v
Application Load Balancer
        |
        v
ECS Fargate Task - Spring Boot API
        |
        +--> RDS PostgreSQL
        +--> Secrets Manager
        +--> CloudWatch Logs
        +--> External APIs
```

Terraform 코드는 다음 리소스를 만든다.

- VPC
- Public subnet
- Private app subnet
- Private DB subnet
- Optional NAT Gateway
- Application Load Balancer
- ECS Fargate cluster, task definition, service
- ECR repository
- RDS PostgreSQL
- Secrets Manager secrets
- CloudWatch log group
- Security groups
- IAM roles

## 왜 ECS Fargate를 선택했나

Spring Boot API를 AWS에 올리는 방법은 여러 가지가 있다.

- EC2에 직접 배포
- Elastic Beanstalk
- ECS Fargate
- EKS
- Lambda

이 프로젝트에는 ECS Fargate가 가장 현실적인 선택이다.

EC2에 직접 올리면 서버 패치, Docker daemon 관리, systemd 설정, 로그 수집, 배포 스크립트 등을 직접 관리해야 한다. MVP에서는 빠르게 가능하지만 운영으로 갈수록 관리 부담이 커진다.

EKS는 Kubernetes 기반이라 확장성은 좋지만, 현재 규모에는 과하다. 클러스터 운영, ingress, service account, autoscaling, Helm 같은 요소가 추가되어 초기 복잡도가 높다.

Lambda는 짧은 요청 처리에는 좋지만, 이 앱은 Spring Boot, JPA, PostgreSQL, embedding 초기화, 외부 API 호출을 포함한다. cold start와 실행 모델을 고려하면 자연스럽지 않다.

ECS Fargate는 컨테이너 이미지만 준비하면 서버를 직접 관리하지 않고 API 서비스를 실행할 수 있다. Spring Boot API처럼 장시간 떠 있는 HTTP 서버와 잘 맞고, ALB, Secrets Manager, CloudWatch, RDS와의 연결도 단순하다.

## 왜 ECR을 만들었나

ECS는 컨테이너 이미지를 실행한다. 따라서 Spring Boot jar를 Docker image로 만들고, 그 이미지를 저장할 registry가 필요하다.

Terraform에서는 `aws_ecr_repository.app`을 만든다.

```text
Spring Boot jar
    -> Docker image
    -> ECR
    -> ECS Fargate task
```

ECR을 쓰는 이유는 다음과 같다.

- ECS와 IAM 통합이 쉽다.
- private registry를 별도로 운영하지 않아도 된다.
- image scan을 켤 수 있다.
- GitHub Actions 같은 CI/CD에서 push하기 쉽다.

현재 Terraform은 ECR repository만 만든다. 실제 Dockerfile과 image push는 앱 배포 단계에서 따로 해야 한다.

## 왜 Application Load Balancer를 사용했나

ECS task는 직접 인터넷에 노출하지 않는 것이 좋다. 대신 ALB를 앞에 둔다.

ALB를 쓰는 이유는 다음과 같다.

- 외부 클라이언트의 단일 진입점이 된다.
- HTTPS 인증서를 붙일 수 있다.
- ECS task가 교체되어 IP가 바뀌어도 target group이 라우팅을 처리한다.
- health check로 죽은 task에 트래픽을 보내지 않을 수 있다.
- 나중에 path 기반 라우팅이나 blue/green 배포로 확장하기 쉽다.

Terraform에서는 HTTP listener를 기본으로 만들고, `certificate_arn`을 넣으면 HTTPS listener도 만든다. 인증서가 없을 때도 demo 배포가 가능하게 하기 위해서다.

운영에서는 ACM 인증서를 발급하고 `certificate_arn`을 지정해서 HTTPS를 사용해야 한다.

## 왜 RDS PostgreSQL을 사용했나

이 프로젝트는 PostgreSQL과 pgvector가 필요하다. 로컬에서는 `pgvector/pgvector:pg16` Docker image를 사용하고 있다.

AWS에서는 직접 EC2에 PostgreSQL을 설치할 수도 있지만, 백업, 패치, 장애 대응, 스토리지 관리까지 직접 해야 한다. RDS를 사용하면 이런 운영 부담을 줄일 수 있다.

Terraform에서는 `aws_db_instance.postgres`를 만든다.

중요 설정은 다음과 같다.

- engine: PostgreSQL
- storage: gp3
- public access: disabled
- subnet: private DB subnet
- password: AWS managed master password
- backup retention: 기본 7일

RDS는 생성 후 DB 안에서 extension을 켜야 한다.

```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS hstore;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

Terraform만으로 DB 내부 SQL까지 실행하지 않은 이유는 Terraform이 인프라 상태 관리 도구이지 DB migration 도구가 아니기 때문이다. DB extension, schema migration, seed data는 Flyway/Liquibase나 별도 one-time task로 분리하는 편이 안전하다.

## 왜 DB 비밀번호를 Terraform 변수로 받지 않았나

DB 비밀번호를 `terraform.tfvars`에 넣으면 Terraform state에 민감값이 남을 수 있다.

그래서 RDS의 `manage_master_user_password = true`를 사용했다. 이렇게 하면 AWS가 master password를 Secrets Manager에 생성하고 관리한다.

ECS task는 RDS가 만든 secret에서 password만 읽어 `DB_PASSWORD` 환경변수로 받는다.

```text
RDS managed secret
        |
        v
ECS Task Definition secret injection
        |
        v
Spring Boot DB_PASSWORD
```

이 방식은 직접 비밀번호를 Terraform 변수로 넣는 것보다 안전하다.

## 왜 Secrets Manager를 사용했나

앱에는 여러 API 키가 필요하다.

- `OPENAI_API_KEY`
- `SAFETY_KOREA_API_KEY`
- `CUSTOMS_API_KEY`
- `CHEMICAL_API_KEY`
- `CUSTOMS_CONFIRMATION_SERVICE_KEY`

이 값들은 Git, Docker image, EC2 disk, Terraform 변수에 직접 넣으면 안 된다.

Terraform은 secret container만 만든다. 실제 secret value는 배포자가 AWS CLI나 콘솔에서 넣는다.

예:

```bash
aws secretsmanager put-secret-value \
  --secret-id gonggong-demo/OPENAI_API_KEY \
  --secret-string 'actual-key'
```

이렇게 한 이유는 API 키가 Terraform state에 저장되는 것을 피하기 위해서다. Terraform으로 `aws_secretsmanager_secret_version`까지 만들 수도 있지만, 그 경우 secret value가 state에 남을 수 있다.

## 왜 VPC를 직접 만들었나

AWS default VPC를 쓰면 빠르게 시작할 수는 있지만, 운영 환경에서는 네트워크 경계가 불명확해진다.

그래서 Terraform은 프로젝트 전용 VPC를 만든다.

```text
VPC
├─ Public subnets
│  └─ ALB
├─ Private app subnets
│  └─ ECS tasks, when NAT mode is enabled
└─ Private DB subnets
   └─ RDS
```

이렇게 나누면 역할별로 접근 제어를 명확히 할 수 있
다.

- Public subnet: 인터넷에서 접근 가능한 ALB 위치
- Private app subnet: 앱 서버 위치
- Private DB subnet: DB 위치

## 왜 NAT Gateway를 optional로 뒀나

운영적으로 가장 깔끔한 구조는 ECS task를 private subnet에 두고 NAT Gateway를 통해 외부 API를 호출하게 하는 방식이다.

하지만 NAT Gateway는 시간당 비용과 데이터 처리 비용이 계속 발생한다. MVP나 demo 환경에서는 비용 부담이 불필요하게 클 수 있다.

그래서 `enable_nat_gateway` 변수를 만들었다.

### `enable_nat_gateway = false`

기본값이다.

이 경우 ECS task는 public subnet에서 실행되고 public IP를 받는다. 하지만 security group에서 ALB security group만 inbound를 허용하므로, 앱 포트는 ALB를 통해서만 접근된다.

장점:

- 비용이 낮다.
- NAT Gateway 비용이 없다.
- 초기 demo 배포가 단순하다.

단점:

- ECS task가 public subnet에 있다.
- 운영 보안 관점에서는 private subnet 배치보다 약하다.

### `enable_nat_gateway = true`

운영형에 가까운 구조다.

이 경우 ECS task는 private app subnet에서 실행되고 public IP를 받지 않는다. 외부 API 호출은 NAT Gateway를 통해 나간다.

장점:

- 앱 task가 직접 인터넷에 노출되지 않는다.
- 네트워크 경계가 더 명확하다.

단점:

- NAT Gateway 비용이 발생한다.

정리하면, 처음 AWS에 올려서 검증할 때는 `false`, 실제 운영으로 갈 때는 `true`를 권장한다.

## Security Group 설계

Terraform은 세 개의 security group을 만든다.

### ALB security group

인터넷에서 ALB로 들어오는 HTTP/HTTPS를 허용한다.

```text
Internet -> ALB: 80, 443
```

`allowed_http_cidr_blocks`로 접근 가능한 CIDR을 제한할 수 있다. 기본값은 `0.0.0.0/0`이다.

### ECS security group

ALB에서 들어오는 앱 포트만 허용한다.

```text
ALB SG -> ECS SG: 8080
```

즉, ECS task가 public subnet에 있더라도 앱 포트는 security group 기준으로 ALB에서만 접근 가능하다.

### RDS security group

ECS task에서 들어오는 PostgreSQL 포트만 허용한다.

```text
ECS SG -> RDS SG: 5432
```

DB는 public access가 꺼져 있고, private DB subnet에 있기 때문에 외부에서 직접 접근할 수 없다.

## ECS Task 환경변수 설계

현재 Spring Boot 앱은 `application.yaml`에서 환경변수를 읽는다.

Terraform은 ECS task definition에 다음 값을 plain environment로 넣는다.

- `SPRING_PROFILES_ACTIVE=prod`
- `DB_URL`
- `DB_USER`
- `OPENAI_MODEL`
- `OPENAI_EMBEDDING_MODEL`
- `HSK_EMBEDDING_INITIALIZE`
- `HSK_DATASET_INITIALIZE`
- `TARIFF_DATASET_INITIALIZE`

민감값은 ECS secrets로 넣는다.

- `DB_PASSWORD`
- `OPENAI_API_KEY`
- `SAFETY_KOREA_API_KEY`
- `CUSTOMS_API_KEY`
- `CHEMICAL_API_KEY`
- `CUSTOMS_CONFIRMATION_SERVICE_KEY`

plain environment와 secret을 나눈 이유는 값의 성격이 다르기 때문이다. 모델명, DB URL, 초기화 여부는 민감정보가 아니지만 API key와 password는 민감정보다.

## 왜 `prod` profile을 전제로 했나

현재 `src/main/resources/application.yaml`에는 운영에 그대로 쓰기 부담스러운 값이 있다.

- `spring.jpa.hibernate.ddl-auto: update`
- `spring.jpa.show-sql: true`
- `hsk.embedding.initialize: true`

로컬 개발에서는 편리하지만 운영에서는 위험하거나 비용이 커질 수 있다.

그래서 ECS task에는 `SPRING_PROFILES_ACTIVE=prod`를 넣었다. 다음 단계로 `application-prod.yaml`을 만들어 운영 설정을 분리해야 한다.

권장 prod 설정은 다음 방향이다.

```yaml
spring:
  jpa:
    hibernate:
      ddl-auto: validate
    show-sql: false

hsk:
  embedding:
    initialize: false
```

DB schema 변경은 장기적으로 Flyway나 Liquibase로 관리하는 것이 좋다.

## 왜 health check path를 `/actuator/health`로 잡았나

ALB는 target이 살아있는지 health check로 판단한다. Spring Boot에서는 Actuator의 `/actuator/health`가 표준적인 health endpoint다.

Terraform 기본값도 그래서 `/actuator/health`다.

다만 현재 앱에는 Actuator dependency가 아직 없다. 따라서 실제 배포 전에 다음 중 하나가 필요하다.

- Spring Boot Actuator 추가
- 별도 lightweight health controller 추가
- `health_check_path`를 현재 존재하는 endpoint로 임시 변경

운영 기준으로는 Actuator를 추가하는 것을 권장한다.

## 왜 CloudWatch Logs를 사용했나

ECS Fargate task의 stdout/stderr 로그는 어딘가로 보내야 한다. Terraform은 CloudWatch log group을 만들고, ECS task의 `awslogs` driver를 설정한다.

로그 그룹 이름:

```text
/ecs/gonggong-demo-api
```

기본 보관 기간은 14일이다. demo 환경에서는 충분하고, 운영에서는 비용과 감사 요건에 맞춰 늘리면 된다.

## 왜 Terraform state에 주의해야 하나

Terraform state에는 인프라의 실제 속성이 저장된다. 잘못 설계하면 secret 값도 state에 들어갈 수 있다.

이번 코드에서는 다음 원칙을 적용했다.

- API key value는 Terraform으로 만들지 않는다.
- Secrets Manager secret resource만 만든다.
- DB password는 AWS managed master password를 사용한다.
- `terraform.tfvars`는 `.gitignore`에 추가했다.
- `.terraform/`과 `*.tfstate`도 `.gitignore`에 추가했다.

따라서 실제 운영 시에도 remote backend를 쓸 때는 S3 backend encryption과 DynamoDB lock을 설정하는 것이 좋다.

현재 코드는 backend 설정을 일부러 넣지 않았다. AWS 계정, S3 bucket 이름, 팀 운영 방식이 정해지기 전에는 local backend가 더 단순하기 때문이다.

## 현재 Terraform이 하지 않는 일

이 Terraform은 AWS 인프라 골격을 만든다. 하지만 앱 배포 전체를 완성하지는 않는다.

아직 별도로 해야 하는 작업은 다음과 같다.

- 앱 `Dockerfile` 작성
- Spring Boot `prod` profile 작성
- Actuator 또는 health endpoint 추가
- Docker image build
- ECR push
- RDS extension 활성화
- Secrets Manager secret value 입력
- Route 53 domain 연결
- ACM certificate 발급
- GitHub Actions 배포 파이프라인 작성

특히 현재 Terraform은 RDS 생성 후 `CREATE EXTENSION` SQL을 자동 실행하지 않는다. 이것은 의도적인 선택이다. DB 내부 변경은 Terraform보다 migration 도구나 one-time task로 분리하는 것이 안전하다.

## 첫 배포 절차

1. 앱에 `Dockerfile`, `application-prod.yaml`, health endpoint를 추가한다.
2. Terraform 변수 파일을 만든다.

```bash
cd infra/terraform/aws
cp terraform.tfvars.example terraform.tfvars
```

3. Terraform을 실행한다.

```bash
terraform init
terraform plan
terraform apply
```

4. RDS에 접속해서 extension을 활성화한다.

```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS hstore;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

5. Secrets Manager에 API key 값을 넣는다.

```bash
aws secretsmanager put-secret-value \
  --secret-id gonggong-demo/OPENAI_API_KEY \
  --secret-string 'actual-key'
```

6. Docker image를 ECR에 push한다.
7. ECS service를 force new deployment 한다.
8. ALB DNS로 health check와 API 호출을 확인한다.
9. ACM 인증서와 Route 53을 연결한다.

## 운영 전환 시 바꿀 값

demo에서 운영으로 갈 때는 최소한 다음 값을 조정한다.

```hcl
environment        = "prod"
enable_nat_gateway = true
desired_count      = 2
skip_final_snapshot = false
certificate_arn    = "arn:aws:acm:..."
```

추가로 고려할 항목:

- RDS Multi-AZ
- ECS autoscaling
- CloudWatch alarms
- WAF
- access log 저장
- S3 + DynamoDB Terraform remote backend
- Flyway/Liquibase migration
- GitHub Actions CI/CD

## 결론

현재 Terraform은 “처음 AWS에 올려서 실제로 동작을 검증할 수 있는 MVP 인프라”를 목표로 작성했다.

핵심 방향은 다음과 같다.

- 앱 실행은 ECS Fargate
- 이미지 저장은 ECR
- DB는 RDS PostgreSQL
- secret은 Secrets Manager
- 외부 진입점은 ALB
- 로그는 CloudWatch
- 비용 절감 모드와 운영형 네트워크 모드를 변수로 전환

이 구조는 처음에는 단순하게 시작할 수 있고, 나중에 NAT Gateway, HTTPS, autoscaling, Multi-AZ, CI/CD를 붙이며 운영 환경으로 자연스럽게 확장할 수 있다.

