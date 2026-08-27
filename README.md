## 프로젝트 개요

Gonggong은 AliExpress, Temu 같은 해외 쇼핑몰 상품 페이지를 분석해 사용자에게 리콜, 인증, 관세/HSK, 위해 성분 관련 위험 신호를 제공하는 서비스입니다.

사용자는 Chrome Extension인 `C-Entry`를 통해 상품 페이지에서 분석 결과를 확인할 수 있으며, 백엔드 API는 상품 정보와 공공 데이터, 외부 API를 조합해 상품 리스크를 계산합니다.

이 저장소는 Gonggong 백엔드 API를 AWS 환경에 배포하기 위한 Terraform 인프라 코드와 배포 기록을 정리한 프로젝트입니다.

## 주요 기능

- Spring Boot 백엔드 API를 AWS ECS Fargate에 배포
- Application Load Balancer를 통한 공개 API endpoint 제공
- RDS PostgreSQL 및 pgvector 기반 데이터 저장
- AWS Secrets Manager를 통한 API Key 및 DB 비밀번호 관리
- CloudWatch Logs를 통한 운영 로그 확인
- ECR 기반 Docker 이미지 저장 및 ECS 배포
- Chrome Extension에서 호출 가능한 운영 API 환경 구성

## 아키텍처

```text
Chrome Extension / Browser
        |
        v
Application Load Balancer
        |
        v
ECS Fargate Service - Spring Boot API
        |
        +--> RDS PostgreSQL
        +--> Secrets Manager
        +--> CloudWatch Logs
        +--> External APIs
             - OpenAI
             - Safety Korea
             - Korea Customs Service
             - Chemical API
기술 스택
Application
Java 17
Spring Boot
Gradle
PostgreSQL
pgvector
Spring AI / OpenAI API
Chrome Extension Manifest V3
Infrastructure
Terraform
AWS ECS Fargate
Amazon ECR
Application Load Balancer
Amazon RDS for PostgreSQL
AWS Secrets Manager
AWS CloudWatch Logs
IAM
VPC / Subnet / Security Group
AWS 구성
항목	값
Region	ap-northeast-2
ECS Cluster	gonggong-demo-cluster
ECS Service	gonggong-demo-api
ECR Repository	gonggong-demo-api
ALB	gonggong-demo-alb
RDS	gonggong-demo-postgres
CloudWatch Log Group	/ecs/gonggong-demo-api


운영 검증 당시 ECS 서비스는 desired=1, running=1, pending=0 상태로 정상 배포를 완료했습니다.
Terraform 구성
Terraform 코드는 infra/terraform/aws 디렉터리에 작성했습니다.
파일	역할
network.tf	VPC, Subnet, Route Table, Internet Gateway, NAT Gateway 구성
security.tf	ALB, ECS, RDS Security Group 구성
alb.tf	Application Load Balancer, Listener, Target Group 구성
ecs.tf	ECS Cluster, Task Definition, Service, IAM Role, CloudWatch Logs 구성
ecr.tf	ECR Repository 및 Lifecycle Policy 구성
rds.tf	RDS PostgreSQL 구성
secrets.tf	Secrets Manager Secret Container 구성
variables.tf	환경별 설정 변수 정의
outputs.tf	배포 후 주요 리소스 정보 출력


배포 흐름
배포는 다음 순서로 진행했습니다.
Gradle Test
    -> Spring Boot Jar Build
    -> Docker Image Build
    -> ECR Login
    -> ECR Push
    -> ECS Force New Deployment
    -> ECS Stable 대기
    -> ALB Smoke Test
검증한 주요 endpoint는 다음과 같습니다.
GET /                                  200 OK
GET /actuator/health                   200 OK
GET /api/demand/priority-items/top10   200 OK
GET /api/brands/test/recalls           200 OK
루트 endpoint는 다음과 같은 API 상태 정보를 반환하도록 구성했습니다.
{
  "service": "gonggong-api",
  "status": "UP",
  "endpoints": [
    "/actuator/health",
    "/api/demand/priority-items/top10",
    "/api/products/analyze",
    "/api/v1/risk-dashboard/analyze"
  ]
}
