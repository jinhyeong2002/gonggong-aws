
# AWS Deployment Checklist

## 현재 상태

마지막 진행 위치: 루트 URL 500 수정 이미지 배포 및 ALB smoke test 완료. 현재 데모 API는 실행 중이다.

현재 상태:

- [x] ECS service: `desired=1`, `running=1`, `pending=0`
- [x] RDS: `available`
- [x] ALB: 유지
- [x] 로컬 Docker: Docker Desktop 정상 실행 확인

## 2026-07-07 루트 URL 500 이슈

사용자가 브라우저에서 아래 URL로 접근했을 때 내부 서버 오류가 발생한다고 보고했다.

```text
http://gonggong-demo-alb-1874541421.ap-northeast-2.elb.amazonaws.com/
```

확인 결과 AWS 인프라 자체는 정상이다.

- RDS `gonggong-demo-postgres`: `available`
- ECS service `gonggong-demo-api`: `desired=1`, `running=1`, `pending=0`
- Health endpoint:

  ```bash
  curl -i http://gonggong-demo-alb-1874541421.ap-northeast-2.elb.amazonaws.com/actuator/health
  ```

  응답:

  ```json
  {"groups":["liveness","readiness"],"status":"UP"}
  ```

- API endpoint:

  ```bash
  curl -i http://gonggong-demo-alb-1874541421.ap-northeast-2.elb.amazonaws.com/api/demand/priority-items/top10
  ```

  정상 JSON 응답 확인 완료.

원인:

- 애플리케이션에 `/` 루트 경로 컨트롤러가 없었다.
- CloudWatch 로그에서 아래 예외를 확인했다.

  ```text
  org.springframework.web.servlet.resource.NoResourceFoundException: No static resource  for request '/'.
  ```

- 현재 `ExceptionAdvice`가 일반 예외를 모두 `GLOBAL_001` 500으로 감싸기 때문에, 실제로는 루트 경로 미구현에 가까운 상황이 브라우저에는 내부 서버 오류처럼 보인다.

로컬 코드 조치:

- `src/main/java/com/example/gonggong/global/controller/HomeController.java` 추가
  - `GET /` 요청에 대해 API 상태 JSON 반환
  - 반환 endpoint 목록:
    - `/actuator/health`
    - `/api/demand/priority-items/top10`
    - `/api/products/analyze`
    - `/api/v1/risk-dashboard/analyze`
- `src/test/java/com/example/gonggong/global/controller/HomeControllerTest.java` 추가
- `./gradlew test --no-daemon` 성공 확인

배포 완료:

1. 로컬 Docker Desktop 정상화
   - Docker Desktop GUI 실행 확인.
   - CLI 확인:

     ```bash
     docker info
     docker desktop status
     ```

   - 결과: Docker Desktop `running`, Docker Server 응답 정상.

2. 수정 이미지 빌드

   ```bash
   scripts/deploy-aws.sh
   ```

   - Docker build 성공.
   - 최초 `buildx --push` 중 ECR registry 연결이 `EOF`로 끊겼다.
   - 조치: `docker logout` 후 ECR 재로그인, 로컬에 생성된 이미지를 `docker push`로 재시도.

3. ECR 로그인 및 push

   ```bash
   aws ecr get-login-password --region ap-northeast-2 \
     | docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-northeast-2.amazonaws.com

   docker push <account-id>.dkr.ecr.ap-northeast-2.amazonaws.com/gonggong-demo-api:latest
   ```

   - push 성공.
   - image digest: `sha256:d561809a172ad9fe90a3572d0995df8516fd222f76ff1a2f2d770d34715c581d`

4. ECS 새 배포 강제 실행

   ```bash
   aws ecs update-service \
     --region ap-northeast-2 \
     --cluster gonggong-demo-cluster \
     --service gonggong-demo-api \
     --force-new-deployment

   aws ecs wait services-stable \
     --region ap-northeast-2 \
     --cluster gonggong-demo-cluster \
     --services gonggong-demo-api
   ```

   - ECS service final state: `desired=1`, `running=1`, `pending=0`, rollout `COMPLETED`.
   - task definition: `arn:aws:ecs:ap-northeast-2:<account-id>:task-definition/gonggong-demo-api:6`

5. 반영 확인

   ```bash
   curl -i http://gonggong-demo-alb-1874541421.ap-northeast-2.elb.amazonaws.com/
   curl -i http://gonggong-demo-alb-1874541421.ap-northeast-2.elb.amazonaws.com/actuator/health
   curl -i http://gonggong-demo-alb-1874541421.ap-northeast-2.elb.amazonaws.com/api/demand/priority-items/top10
   ```

   기대 결과:

   - `/`: 200 OK, `{"service":"gonggong-api","status":"UP",...}` 형태 JSON
   - `/actuator/health`: 200 OK, `status=UP`
   - `/api/demand/priority-items/top10`: 200 OK, priority items JSON
   - `/api/brands/test/recalls`: 200 OK, 리콜 이력 없음 JSON

다시 켤 때 실행할 명령:

```bash
aws rds start-db-instance \
  --region ap-northeast-2 \
  --db-instance-identifier gonggong-demo-postgres

aws ecs update-service \
  --region ap-northeast-2 \
  --cluster gonggong-demo-cluster \
  --service gonggong-demo-api \
  --desired-count 1

aws ecs wait services-stable \
  --region ap-northeast-2 \
  --cluster gonggong-demo-cluster \
  --services gonggong-demo-api
```

재개 후 확인할 명령:

```bash
curl http://gonggong-demo-alb-1874541421.ap-northeast-2.elb.amazonaws.com/actuator/health
curl http://gonggong-demo-alb-1874541421.ap-northeast-2.elb.amazonaws.com/api/demand/priority-items/top10
```

로컬 Docker를 다시 켤 때:

```bash
open -a Docker
docker compose up -d postgres
docker ps --filter name=gonggong-postgres
```

로컬 API를 다시 띄울 때:

```bash
docker run --rm -p 8080:8080 --name gonggong-api-local \
  -e SPRING_PROFILES_ACTIVE=prod \
  -e DB_URL=jdbc:postgresql://host.docker.internal:5432/gonggong \
  -e DB_USER=gonggong \
  -e DB_PASSWORD=gonggong \
  gonggong-api:local
```

재시작 체크:

- [ ] Docker Desktop 실행 확인
- [ ] `gonggong-postgres` 컨테이너 healthy 확인
- [ ] `gonggong-api:local` 실행 확인
- [ ] `curl http://127.0.0.1:8080/actuator/health`
- [ ] `aws rds start-db-instance` 실행
- [ ] `aws ecs update-service --desired-count 1` 실행
- [ ] `aws ecs wait services-stable` 실행
- [ ] ALB health 확인

완료된 first step:

- [o] Spring Boot Actuator 의존성 추가
- [o] 운영 프로파일 `application-prod.yaml` 추가
- [o] `/actuator/health` health check 노출 설정
- [o] 운영 기본값 조정
  - [o] `spring.jpa.hibernate.ddl-auto=validate`
  - [o] `spring.jpa.show-sql=false`
  - [o] `spring.ai.vectorstore.pgvector.initialize-schema=false`
  - [o] `HSK_DATASET_INITIALIZE=false`
  - [o] `HSK_EMBEDDING_INITIALIZE=false`
  - [o] `TARIFF_DATASET_INITIALIZE=false`
- [o] 루트 `Dockerfile` 추가
- [o] 루트 `.dockerignore` 추가
- [o] `gradlew` 실행 권한 추가
- [o] `./gradlew bootJar --no-daemon` 성공 확인

현재 막힌 항목:

- [o] Terraform plan/apply
  - 현재 상태: `terraform validate` 통과, `terraform plan` 성공
  - 현재 상태: `terraform plan -out=tfplan` 완료
  - 현재 상태: `terraform apply tfplan` 완료
  - 다음 조치: 운영 전환 전 비용/보안/도메인 설정 검토

이번 스텝 완료:

- [o] 전체 테스트 컴파일 실패 해결
  - 시도한 명령: `./gradlew test bootJar --no-daemon`
  - 원인: 기존 테스트 코드에서 `ProductNormalizeResult`, `RiskDashboardAnalyzeRequest` 생성자 시그니처가 현재 production code와 맞지 않음
  - 조치: DTO/record 호환 생성자 추가 및 KTL action guide 문구 보정
  - 결과: `./gradlew test` 성공, 119 tests completed
- [o] Docker image build 검증
  - 확인 명령: `docker images gonggong-api`
  - 결과: `gonggong-api:local` image 확인됨
  - image id: `b13683827aa7`
  - size: `762MB`
- [o] 로컬 PostgreSQL 컨테이너 기동
  - 최초 실패: `pgvector/pgvector:pg16` pull 중 Docker content store blob 누락
  - 조치: `docker system prune -f`로 미사용 Docker 캐시 정리 후 `docker pull pgvector/pgvector:pg16` 재시도
  - 결과: `gonggong-postgres` health `healthy`
- [o] Prod profile 실행 및 health 확인
  - 사전 조치: 빈 DB에서 prod `ddl-auto=validate`가 통과하도록 기본 profile로 1회 기동해 스키마 생성
  - 실행 조건: `SPRING_PROFILES_ACTIVE=prod`, `DB_URL=jdbc:postgresql://localhost:5432/gonggong`, `DB_USER=gonggong`, `DB_PASSWORD=gonggong`
  - 확인 명령: `curl -s http://localhost:8080/actuator/health`
  - 결과: `{"groups":["liveness","readiness"],"status":"UP"}`
- [o] Docker Desktop에서 `gonggong-api:local` 실행 확인
  - 사전 조건: `gonggong-postgres` 컨테이너 health `healthy`
  - Dashboard 실행 조건: host port `8080`, container port `8080/tcp`
  - Dashboard 환경변수:
    - `SPRING_PROFILES_ACTIVE=prod`
    - `DB_URL=jdbc:postgresql://host.docker.internal:5432/gonggong`
    - `DB_USER=gonggong`
    - `DB_PASSWORD=gonggong`
  - 컨테이너 상태: `gonggong-api:local` Up, `0.0.0.0:8080->8080/tcp`
  - 확인 명령: `curl -s http://127.0.0.1:8080/actuator/health`
  - 결과: `{"groups":["liveness","readiness"],"status":"UP"}`
  - 작업 종료 시 로컬 Docker 컨테이너 중지 완료: `docker stop magical_lichterman gonggong-postgres`
  - 다음에 로컬 Docker 검증이 필요하면 아래 순서로 재기동한다.
    1. Postgres 재기동

       ```bash
       docker compose up -d postgres
       docker ps --filter name=gonggong-postgres
       ```

    2. Docker Desktop에서 `gonggong-api:local` 이미지 Run
       - Ports: host `8080`, container `8080/tcp`
       - Volumes: 비워둠
       - Environment variables:

         ```text
         SPRING_PROFILES_ACTIVE=prod
         DB_URL=jdbc:postgresql://host.docker.internal:5432/gonggong
         DB_USER=gonggong
         DB_PASSWORD=gonggong
         ```

    3. Health 확인

       ```bash
       curl -s http://127.0.0.1:8080/actuator/health
       ```
- [o] Terraform 변수 파일 준비
  - 생성 파일: `infra/terraform/aws/terraform.tfvars`
  - 기준 파일: `infra/terraform/aws/terraform.tfvars.example`
  - 초기 demo 값 유지: `environment="demo"`, `enable_nat_gateway=false`, `desired_count=1`, `certificate_arn=""`
  - 비용 절감 조정:
    - `task_cpu=512`
    - `task_memory=1024`
    - `hsk_embedding_initialize=false`
    - `hsk_dataset_initialize=false`
    - `tariff_dataset_initialize=false`
- [o] Terraform 로컬 검증
  - 실행 명령: `terraform fmt`
  - 결과: `terraform.tfvars` 포맷 정리
  - 실행 명령: `terraform validate`
  - 결과: `Success! The configuration is valid.`
- [o] Terraform plan
  - 실행 명령: `terraform plan`
  - 최초 결과: 실패
  - 최초 원인: `No valid credential sources found`
  - 추가 확인: AWS CLI `2.35.15` 설치 완료
  - AWS credential 설정 후 확인 계정: `arn:aws:iam::<account-id>:user/<iam-user>`
  - 최종 결과: 성공
  - Plan 요약: `34 to add, 0 to change, 0 to destroy`
  - 비용 절감 재검증 결과: 성공
  - ECS task definition 확인: `cpu="512"`, `memory="1024"`
  - 저장된 plan 파일: `infra/terraform/aws/tfplan`
  - 다음 재개 명령: `terraform apply tfplan`
  - 주요 생성 예정:
    - VPC/subnets/routes/Internet Gateway
    - ALB/listener/target group
    - ECS cluster/task definition/service
    - ECR repository/lifecycle policy
    - RDS PostgreSQL `db.t4g.micro`, 20GiB
    - Secrets Manager secret containers
    - CloudWatch log group
    - Security groups
    - IAM roles/policies
- [o] Terraform apply
  - 실행 명령: `terraform apply tfplan`
  - 결과: 성공
  - 생성 state 파일: `infra/terraform/aws/terraform.tfstate`
  - 주요 output:
    - ALB DNS: `gonggong-demo-alb-1874541421.ap-northeast-2.elb.amazonaws.com`
    - ECR repository: `<account-id>.dkr.ecr.ap-northeast-2.amazonaws.com/gonggong-demo-api`
    - ECS cluster: `gonggong-demo-cluster`
    - ECS service: `gonggong-demo-api`
    - RDS endpoint: `gonggong-demo-postgres.cj8soa2e4tzv.ap-northeast-2.rds.amazonaws.com:5432`
    - Secrets Manager:
      - `gonggong-demo/OPENAI_API_KEY`
      - `gonggong-demo/SAFETY_KOREA_API_KEY`
      - `gonggong-demo/CUSTOMS_API_KEY`
      - `gonggong-demo/CHEMICAL_API_KEY`
      - `gonggong-demo/CUSTOMS_CONFIRMATION_SERVICE_KEY`
  - 다음 재개 작업:
    1. Secrets Manager에 API key 값 입력
    2. ECS service 새 배포 강제 실행
    3. ALB health/API 응답 확인
- [o] ECR image push
  - 실행 순서:
    - ECR login 성공
    - `gonggong-api:local`을 `<account-id>.dkr.ecr.ap-northeast-2.amazonaws.com/gonggong-demo-api:latest`로 tag
    - ECR push 성공
  - pushed digest: `sha256:b13683827aa7267bb6e8b6b83e8bf2cf92e23d4a03d4c4f43d67c112f01e94a7`
  - 최초 push 문제: Mac 로컬 빌드 이미지가 `linux/arm64`라 ECS Fargate 기본 `linux/amd64`에서 pull 실패
  - 조치: `docker build --platform linux/amd64 -t <account-id>.dkr.ecr.ap-northeast-2.amazonaws.com/gonggong-demo-api:latest .`
  - amd64 pushed digest: `sha256:58c01f3dadbaa4db7a3379386cfd2f7bd8143628d5824d63a73b283223fd8772`
- [o] `CUSTOMS_CONFIRMATION_API_URL` ECS 환경변수 주입 준비
  - 추가 파일:
    - `infra/terraform/aws/variables.tf`
    - `infra/terraform/aws/ecs.tf`
    - `infra/terraform/aws/terraform.tfvars`
    - `infra/terraform/aws/terraform.tfvars.example`
  - 변수명: `customs_confirmation_api_url`
  - ECS env name: `CUSTOMS_CONFIRMATION_API_URL`
  - 기본값: `""`
  - `terraform fmt` 성공
  - `terraform validate` 성공
  - 실제 URL: `https://apis.data.go.kr/1220000/retrieveCcctLworCd/getRetrieveCcctLworCd`
  - `terraform apply` 완료
- [o] Secrets Manager 값 입력 확인
  - 확인 기준: secret 값은 출력하지 않고 `LastChangedDate` 및 `AWSCURRENT` stage만 확인
  - 확인 완료:
    - `gonggong-demo/OPENAI_API_KEY`
    - `gonggong-demo/SAFETY_KOREA_API_KEY`
    - `gonggong-demo/CUSTOMS_API_KEY`
    - `gonggong-demo/CHEMICAL_API_KEY`
    - `gonggong-demo/CUSTOMS_CONFIRMATION_SERVICE_KEY`
- [o] AWS ECS 서비스 기동 확인
  - 최초 실패 1: Secrets Manager 값 입력 전 ECS task가 `CHEMICAL_API_KEY`의 `AWSCURRENT` 값을 찾지 못함
  - 최초 실패 2: ECR image가 `linux/arm64`라 ECS Fargate 기본 `linux/amd64`에서 pull 실패
  - 최초 실패 3: 새 RDS가 빈 DB인데 prod `ddl-auto=validate`라 `essential_industry_item` 테이블 누락으로 부팅 실패
  - 최초 실패 4: 앱 부팅이 약 70초 걸리는데 ECS service health check grace period가 없어 ALB health check 실패로 task가 조기 종료됨
  - 조치:
    - Secrets Manager 값 입력 확인
    - amd64 image 재빌드 및 ECR push
    - demo bootstrap 용도로 `SPRING_JPA_HIBERNATE_DDL_AUTO=update` 1회 적용해 RDS schema 생성
    - schema 생성 후 `SPRING_JPA_HIBERNATE_DDL_AUTO=validate`로 복구
    - `ecs_health_check_grace_period_seconds=180` 추가 및 적용
  - 확인:
    - ECS task revision 3에서 schema 생성 및 Spring Boot 정상 시작 확인
    - ECS task revision 4에서 `ddl-auto=validate` 정상 부팅 확인
    - ECS service final state: desired `1`, running `1`, pending `0`, rollout `COMPLETED`
    - ALB health endpoint `HTTP/1.1 200`, body `{"groups":["liveness","readiness"],"status":"UP"}`
- [o] ALB smoke test
  - ECS service 상태: desired `1`, running `1`, pending `0`, rollout `COMPLETED`
  - `GET /api/demand/priority-items/top10`: `HTTP/1.1 200`, sample priority items 반환 확인
  - `GET /api/brands/test/recalls`: `HTTP/1.1 200`, empty recall response 반환 확인
- [o] Chrome extension CORS 설정 및 검증
  - 추가 파일: `src/main/java/com/example/gonggong/global/config/CorsConfig.java`
  - 추가 설정: `app.cors.allowed-origin-patterns`
  - 기본 허용 origin pattern:
    - `chrome-extension://*`
    - `http://localhost:*`
    - `http://127.0.0.1:*`
  - 환경변수 override: `CORS_ALLOWED_ORIGIN_PATTERNS`
  - 검증:
    - `./gradlew test --no-daemon` 성공
    - `docker build --platform linux/amd64 ...` 성공
    - ECR push digest: `sha256:2ecaf185f6624173e9aefc7f4c7be69046903a6261bc7388c40f3f6e7e1f531f`
    - ECS force deployment 실행
    - `OPTIONS /api/demand/priority-items/top10` with `Origin: chrome-extension://...`: `HTTP/1.1 200`, `Access-Control-Allow-Origin` 반환 확인
    - `GET /api/demand/priority-items/top10` with `Origin: chrome-extension://...`: `HTTP/1.1 200`, `Access-Control-Allow-Origin` 반환 확인
- [o] RDS pgvector/extension bootstrap
  - 문제: HSK vector search에서 `Unknown type vector`, `relation public.hsk_vector_store does not exist` 발생
  - 조치:
    - one-off ECS Fargate task로 RDS에 `hstore`, `uuid-ossp`, `vector` extension 생성
    - `SPRING_AI_VECTORSTORE_PGVECTOR_INITIALIZE_SCHEMA=true`, `HSK_DATASET_INITIALIZE=true`, `HSK_EMBEDDING_INITIALIZE=true`를 1회 적용해 HSK vector store 생성
    - 초기화 후 비용 방지를 위해 다시 모두 `false`로 복구
  - 결과:
    - 공식 HSK dataset `11327`건 적재
    - HSK vector embedding batch 저장 완료
    - `POST /api/seller/hsk/match`: `HTTP/1.1 200`, `matched=true`
- [o] 외부 API key 입력 오류 방어 및 운영 재배포
  - 발견:
    - `SAFETY_KOREA_API_KEY`가 실제 키 대신 `실제_...` placeholder 형태일 때 HTTP header 생성에서 500 발생
    - `CUSTOMS_CONFIRMATION_SERVICE_KEY` 앞뒤에 스마트 따옴표가 저장되어 query param 생성 실패
  - 조치:
    - SafetyKorea recall/certification client에서 placeholder/non-ASCII/control char 키를 미설정으로 처리
    - SafetyKorea 상세 조회 실패 시 상품 분석 전체가 500으로 죽지 않고 목록 정보로 진행
    - Customs/Chemical service key setter에서 일반 따옴표 및 스마트 따옴표 제거
  - 검증:
    - `./gradlew test --no-daemon`: 성공
    - ECR push digest 1: `sha256:0bd87671e8a792c0c44817405a6fb995ee7e2199ce98ac5b13f82c0742f43e59`
    - ECR push digest 2: `sha256:68cd22d75f29ecddd97554ae43d49d3bf601c1cd74f93f6f074b6da94c354f3f`
    - ECS final state: desired `1`, running `1`, pending `0`, rollout `COMPLETED`
    - `GET /api/demand/priority-items/top10`: `HTTP/1.1 200`
    - `POST /api/products/analyze` with Chrome extension origin: `HTTP/1.1 200`, `Access-Control-Allow-Origin` 반환
    - `POST /api/v1/risk-dashboard/analyze` with Chrome extension origin: `HTTP/1.1 200`, `Access-Control-Allow-Origin` 반환
    - `POST /api/seller/hsk/match` with Chrome extension origin: `HTTP/1.1 200`, `matched=true`
    - CloudWatch 확인: 관세청 `Invalid character` 오류 사라짐, `Customs confirmation API parsed ... itemCount=0`까지 진행
  - 남은 상태:
    - SafetyKorea 실제 API key는 아직 placeholder로 판단됨. 현재 API는 500 대신 리콜 정보를 `UNAVAILABLE` 또는 빈 결과로 낮춰 반환함
    - 루트(`/`), `/favicon.ico`, `/robots.txt`, `/sitemap.xml` 요청이 404인데 ERROR 로그로 찍히는 노이즈가 있음
- [o] Chrome extension 운영 ALB 연결
  - 변경:
    - `extension/background.js` API base URL을 운영 ALB로 변경
    - `extension/manifest.json` host permission에 운영 ALB 추가
    - `extension/popup.html` 백엔드 표시 문구를 운영 ALB로 변경
  - API base URL: `http://gonggong-demo-alb-1874541421.ap-northeast-2.elb.amazonaws.com`
  - 검증:
    - `node --test extension/*.test.js`: 41 tests pass
    - `unzip -l dist/import-safety-guard-0.1.0.zip`: runtime file 11개 포함 확인
    - manifest version: `0.1.0`
  - 배포용 압축본: `dist/import-safety-guard-0.1.0.zip`

## 이후 단계

### 1. 운영 비용/보안 기준 결정

- [ ] demo 유지 여부 결정
  - 현재: `environment="demo"`, `enable_nat_gateway=false`, `desired_count=1`, HTTP only
  - 장점: 비용 낮음
  - 단점: ECS task가 public subnet에서 public IP를 사용함
- [ ] 운영 전환 시 권장값 검토
  - `environment="prod"`
  - `enable_nat_gateway=true`
  - `desired_count=2`
  - `skip_final_snapshot=false`
  - ACM certificate ARN 설정

### 2. 도메인/HTTPS 연결

- [ ] Route 53 또는 외부 DNS에서 도메인 결정
- [ ] ACM 인증서 발급
- [ ] `certificate_arn` 설정 후 Terraform apply
- [ ] HTTP -> HTTPS redirect 및 HTTPS health/API 확인

### 3. API 기능 smoke test 확대

- [o] Chrome extension에서 호출할 API base URL 1차 확정: `http://gonggong-demo-alb-1874541421.ap-northeast-2.elb.amazonaws.com`
- [o] `POST /api/seller/hsk/match`
- [o] `POST /api/products/analyze`
- [o] `POST /api/v1/risk-dashboard/analyze`
- [ ] SafetyKorea 실제 API key 재입력 후 리콜/인증 실데이터 조회 확인
- [o] Chrome extension API base URL 운영 ALB 적용
- [o] Chrome extension 실브라우저 호출 확인

#### 브라우저 확인 항목

- 확장 프로그램을 새 빌드로 다시 로드한다.
- 상품 페이지에서 우측 오버레이가 뜨는지 확인한다.
- `HSK 매칭`, `상품 분석`, `리스크 대시보드`가 각각 `200`으로 응답하는지 확인한다.
- Chrome DevTools에서 `background.js` 요청이 `http://gonggong-demo-alb-1874541421.ap-northeast-2.elb.amazonaws.com`으로 나가는지 확인한다.
- 콘솔에 `CORS`, `Mixed Content`, `Failed to fetch`가 없는지 확인한다.
- 리콜 결과가 실제 SafetyKorea 데이터로 바뀌었는지 확인한다.
- Safari로 `extension/popup.html`과 `extension/risk-view.preview.html`을 직접 열어 팝업 문구와 카드 레이아웃을 시각 확인했다.

### 4. 배포 자동화

- [o] amd64 Docker build/push 명령 스크립트화
- [o] ECS force deployment 명령 스크립트화
- [o] 배포 로그 파일 저장
  - 스크립트: `scripts/deploy-aws.sh`
  - 로그: `logs/deploy-aws-YYYYMMDD-HHMMSS.log`
- [ ] GitHub Actions 또는 수동 release 절차 정리

### 5. DB schema 관리 정리

- [ ] 현재 demo bootstrap은 Hibernate `update` 1회로 schema 생성
- [ ] 운영 전 Flyway/Liquibase 등 migration 도입 검토
- [ ] prod 기본값은 `ddl-auto=validate` 유지

### 6. 관측/운영 점검

- [ ] CloudWatch log 확인 절차 정리
- [ ] ALB/ECS/RDS 비용 알람 설정
- [ ] RDS backup/final snapshot 정책 확정
- [ ] Secrets rotation 또는 교체 절차 정리

## 다음 작업 순서

### 1. Docker image build 확인

- [o] Docker Desktop 실행
- [o] 로컬 Docker image build

```bash
docker build -t gonggong-api:local .
```

- [o] image 생성 확인

```bash
docker images gonggong-api
```

### 2. Prod profile 실행 확인

- [o] 로컬 또는 Docker 환경에서 `SPRING_PROFILES_ACTIVE=prod`로 앱 실행
- [o] `/actuator/health` 응답 확인

예상 확인 대상:

```bash
curl http://localhost:8080/actuator/health
```

주의:

- prod profile은 PostgreSQL 접속을 전제로 한다.
- 로컬 검증 시 `DB_URL`, `DB_USER`, `DB_PASSWORD`, `OPENAI_API_KEY` 등 필요한 환경변수를 준비해야 한다.

### 3. Terraform 변수 파일 준비

- [o] Terraform AWS 디렉터리로 이동

```bash
cd infra/terraform/aws
```

- [o] 변수 파일 생성

```bash
cp terraform.tfvars.example terraform.tfvars
```

- [o] `terraform.tfvars` 값 확인 및 수정
  - [o] `aws_region`
  - [o] `project_name`
  - [o] `environment`
  - [o] `desired_count`
  - [o] `enable_nat_gateway`
  - [o] `certificate_arn`
  - [o] 초기화 플래그들

초기 demo 권장값:

```hcl
environment        = "demo"
enable_nat_gateway = false
desired_count      = 1
certificate_arn    = ""
task_cpu           = 512
task_memory        = 1024
```

운영 전환 권장값:

```hcl
environment         = "prod"
enable_nat_gateway  = true
desired_count       = 2
skip_final_snapshot = false
certificate_arn     = "arn:aws:acm:..."
```

### 4. Terraform plan/apply

- [o] Terraform 초기화

```bash
terraform init
```

- [o] Terraform 구성 검증

```bash
terraform validate
```

- [o] 변경 계획 확인

```bash
terraform plan
```

Plan 결과:

```text
Plan: 34 to add, 0 to change, 0 to destroy.
```

- [o] 변경 계획 파일 저장

```bash
terraform plan -out=tfplan
```

저장 파일:

```text
infra/terraform/aws/tfplan
```

- [o] 인프라 생성

```bash
terraform apply tfplan
```

생성 대상:

- [o] VPC/subnets/routes
- [o] ALB/listeners/target group
- [o] ECS cluster/task definition/service
- [o] ECR repository
- [o] RDS PostgreSQL
- [o] Secrets Manager secret containers
- [o] CloudWatch log group
- [o] Security groups
- [o] IAM roles/policies

### 5. RDS extension 활성화

- [o] RDS 접속 경로 확보
- [o] PostgreSQL extension 활성화

```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS hstore;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

주의:

- Terraform은 DB 내부 SQL을 실행하지 않는다.
- 장기적으로 Flyway 또는 Liquibase로 migration을 분리한다.

### 6. Secrets Manager 값 입력

- [o] `OPENAI_API_KEY`
- [o] `SAFETY_KOREA_API_KEY`
- [o] `CUSTOMS_API_KEY`
- [o] `CHEMICAL_API_KEY`
- [o] `CUSTOMS_CONFIRMATION_SERVICE_KEY`

예시:

```bash
aws secretsmanager put-secret-value \
  --secret-id gonggong-demo/OPENAI_API_KEY \
  --secret-string 'actual-key'
```

주의:

- secret value를 Terraform 변수나 `terraform.tfvars`에 넣지 않는다.
- secret value를 Git에 커밋하지 않는다.

### 7. ECR push

- [o] Terraform output에서 ECR repository URL 확인
- [o] AWS ECR login
- [o] Docker image tag
- [o] Docker image push

예상 흐름:

```bash
aws ecr get-login-password --region <region> \
  | docker login --username AWS --password-stdin <account-id>.dkr.ecr.<region>.amazonaws.com

docker tag gonggong-api:local <ecr-repository-url>:latest
docker push <ecr-repository-url>:latest
```

### 8. ECS 배포 확인

- [o] ECS service force new deployment
  - 권장 명령: `scripts/deploy-aws.sh`

- [o] ECS task가 RUNNING 상태인지 확인
- [o] CloudWatch Logs에서 startup error 확인
- [o] ALB target group health 확인
- [o] ALB DNS로 health endpoint 확인

```bash
curl http://<alb-dns-name>/actuator/health
```

### 9. HTTPS/domain 연결

- [ ] ACM certificate 발급
- [ ] `certificate_arn`을 `terraform.tfvars`에 반영
- [ ] `terraform plan`
- [ ] `terraform apply`
- [ ] Route 53 record 연결
- [ ] HTTPS health check 확인

```bash
curl https://<domain>/actuator/health
```

## 운영 전환 전에 해야 할 일

- [o] 기존 테스트 컴파일 실패 수정
- [ ] GitHub Actions CI/CD 작성
- [ ] Terraform remote backend 구성
  - [ ] S3 state bucket
  - [ ] DynamoDB lock table
  - [ ] encryption
- [ ] RDS final snapshot 정책 확인
- [ ] RDS Multi-AZ 검토
- [ ] ECS autoscaling 추가
- [ ] CloudWatch alarms 추가
- [ ] ALB access log 저장 검토
- [ ] WAF 검토
- [ ] DB migration 도구 도입

## 변경된 파일

- `build.gradle`
- `src/main/resources/application-prod.yaml`
- `Dockerfile`
- `.dockerignore`
- `gradlew`
- `src/main/java/com/example/gonggong/domain/analysis/openai/ProductNormalizeResult.java`
- `src/main/java/com/example/gonggong/domain/risk/dto/request/RiskDashboardAnalyzeRequest.java`
- `src/main/java/com/example/gonggong/domain/risk/provider/JpaKtlCertificationGuideProvider.java`
