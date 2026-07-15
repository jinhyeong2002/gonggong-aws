
# AWS / Chrome Extension Final Notes

## 최종 상태

- 백엔드 API는 AWS ECS Fargate에 배포 완료.
- Chrome 확장 프로그램 이름은 `C-Entry`로 변경 완료.
- Chrome Web Store 업로드용 ZIP 생성 및 업로드 완료.
- 개인정보처리방침은 별도 GitHub Pages URL로 배포 완료.
- 로컬 Docker Desktop은 꺼도 됨. 운영 검토와 실사용 경로는 AWS에서 동작함.

## 운영 URL

백엔드 ALB:

```text
http://gonggong-demo-alb-1874541421.ap-northeast-2.elb.amazonaws.com
```

개인정보처리방침:

```text
https://jinhyeong2002.github.io/gonggong-persnalinfo/privacy.html
```

개인정보처리방침 GitHub repository:

```text
https://github.com/jinhyeong2002/gonggong-persnalinfo.git
```

## AWS 배포 결과

배포 대상:

- AWS account: `<account-id>`
- Region: `ap-northeast-2`
- ECR repository: `<account-id>.dkr.ecr.ap-northeast-2.amazonaws.com/gonggong-demo-api`
- ECS cluster: `gonggong-demo-cluster`
- ECS service: `gonggong-demo-api`
- ECS task definition: `gonggong-demo-api:6`

배포 결과:

- Docker image build 성공.
- ECR push 성공.
- ECS force new deployment 성공.
- ECS final state: `desired=1`, `running=1`, `pending=0`, rollout `COMPLETED`.
- ECR image digest:

```text
sha256:d561809a172ad9fe90a3572d0995df8516fd222f76ff1a2f2d770d34715c581d
```

검증한 endpoint:

```text
GET /                                  200 OK
GET /actuator/health                   200 OK
GET /api/demand/priority-items/top10   200 OK
GET /api/brands/test/recalls           200 OK
```

루트 URL 응답:

```json
{"service":"gonggong-api","status":"UP","endpoints":["/actuator/health","/api/demand/priority-items/top10","/api/products/analyze","/api/v1/risk-dashboard/analyze"]}
```

## 백엔드 수정 내용

루트 URL 500 오류 대응:

- `src/main/java/com/example/gonggong/global/controller/HomeController.java` 추가.
- `GET /` 요청에 대해 API 상태 JSON을 반환하도록 수정.
- `src/test/java/com/example/gonggong/global/controller/HomeControllerTest.java` 추가.
- `./gradlew test --no-daemon` 성공 확인.

운영 관련 파일:

- `Dockerfile`로 Spring Boot 앱 컨테이너 이미지 빌드.
- `src/main/resources/application-prod.yaml`로 운영 profile 분리.
- `scripts/deploy-aws.sh`로 ECR push, ECS force deployment, smoke test 자동화.

## 발생했던 오류와 원인

1. 루트 URL 500 오류

- 증상: ALB 루트 URL `/` 접속 시 내부 서버 오류처럼 보임.
- 원인: 애플리케이션에 `/` 경로 컨트롤러가 없었고, `NoResourceFoundException`이 공통 예외 처리에서 500 형태로 감싸짐.
- 조치: `HomeController`를 추가해 `/`에서 API 상태 JSON을 반환하도록 수정.

2. Docker Desktop 응답 없음

- 증상: `docker info`, `docker version`, `docker compose ps`가 `Server:` 이후 멈춤.
- 원인: Docker Desktop 백엔드 프로세스가 정상 기동 상태가 아니었음.
- 조치: 멈춘 Docker 프로세스를 정리하고 `docker desktop start`로 재기동. 이후 Docker Server 응답 정상 확인.

3. ECR push 중 EOF

- 증상: `docker buildx build --push` 중 ECR registry 요청이 `EOF`로 실패.
- 원인: 코드 문제가 아니라 Docker registry 인증/연결 handshake가 중간에 끊긴 전송 오류.
- 조치: `docker logout` 후 ECR 재로그인, 로컬에 생성된 이미지를 `docker push`로 재시도하여 성공.

4. GitHub Pages 404

- 증상: `https://jinhyeong2002.github.io/gonggong-persnalinfo/privacy.html` 최초 확인 시 404.
- 원인: GitHub Pages가 아직 활성화되지 않았거나 배포가 반영되지 않은 상태.
- 조치: GitHub Pages를 `main` branch `/` source로 활성화하고 반영 대기. 이후 `200 OK` 확인.

## Chrome Extension 수정 내용

확장 프로그램 이름:

```text
C-Entry
```

수정 파일:

- `extension/manifest.json`
  - `name`: `C-Entry`
  - `default_title`: `C-Entry`
  - `version`: `0.1.1`
  - 운영 ALB host permission 유지
- `extension/popup.html`
  - 팝업 title/상단 표기를 `C-Entry`로 변경
- `scripts/package-chrome-web-store.sh`
  - manifest version을 읽어 ZIP 생성
  - ZIP 파일명: `c-entry-v0.1.1.zip`
- `docs/deployment/chrome-web-store.md`
  - 업로드 파일명과 이름을 `C-Entry` 기준으로 갱신

생성된 ZIP:

```text
dist/chrome-web-store/c-entry-v0.1.1.zip
```

ZIP 검증:

- `manifest.json` 포함.
- `background.js`, `content.js`, `popup.*`, view scripts, CSS 포함.
- `icon-16.png`, `icon-48.png`, `icon-128.png` 포함.
- manifest name: `C-Entry`
- manifest version: `0.1.1`
- backend URL:

```text
http://gonggong-demo-alb-1874541421.ap-northeast-2.elb.amazonaws.com
```

테스트:

```text
node --test extension/*.test.js
```

결과:

```text
41 tests passed
```

## Chrome Web Store 입력값

전용 목적:

```text
AliExpress와 Temu 상품 페이지를 분석해 리콜, 인증, 관세/HSK, 위해 성분 관련 위험 신호를 사용자에게 표시합니다.
```

tabs 사용 근거:

```text
현재 활성 탭이 AliExpress 또는 Temu 상품 페이지인지 확인하고, 해당 탭에 분석 결과를 표시하기 위해 사용합니다. 사용자의 전체 탐색 기록을 수집하거나 저장하지 않습니다.
```

호스트 권한 사용 근거:

```text
AliExpress와 Temu 상품 페이지에서 상품명, 설명, 판매자 정보를 읽어 안전성 분석을 수행하고, 운영 백엔드 API로 분석 요청을 보내기 위해 필요합니다. 지정된 쇼핑몰 도메인과 C-Entry 백엔드 API 외의 사이트에는 접근하지 않습니다.
```

원격 코드 사용:

```text
아니요, 원격 코드 권한을 사용하고 있지 않습니다.
```

원격 코드 근거가 필요한 경우:

```text
확장 프로그램은 패키지에 포함된 JavaScript 파일만 실행하며, 외부 서버에서 JavaScript 또는 WebAssembly 코드를 다운로드하거나 실행하지 않습니다. 백엔드 API는 JSON 분석 결과만 반환합니다.
```

사용자 데이터 사용:

- 선택: `웹사이트 콘텐츠`
- 선택하지 않음: 개인 식별 정보, 건강 정보, 금융 및 결제 정보, 인증 정보, 개인적인 커뮤니케이션, 위치, 웹 기록, 사용자 활동

확인 체크박스:

- 승인된 사용 사례를 제외하고 사용자 데이터를 제3자에 판매 또는 전송하지 않음
- 항목의 전용 목적과 관련 없는 목적으로 사용자 데이터를 사용하거나 전송하지 않음
- 신용도 판단 또는 대출을 위해 사용자 데이터를 사용하거나 전송하지 않음

테스트 안내:

```text
No login is required to use C-Entry.

Test steps:
1. Install the extension.
2. Open a supported product page on AliExpress or Temu.
3. Click the C-Entry extension icon or check the page overlay.
4. Confirm that the extension analyzes the product page and displays recall, certification, customs/HSK, and ingredient risk signals.

The extension sends product page content to the backend API only for analysis and does not require a user account.
```

## 계속 켜둬야 하는 AWS 리소스

Chrome Web Store 심사와 실제 확장 기능 동작을 위해 AWS 쪽은 유지해야 함.

켜둬야 하는 것:

- ALB
- ECS Fargate service `gonggong-demo-api`
- RDS PostgreSQL `gonggong-demo-postgres`
- ECR image
- Secrets Manager secret values

꺼도 되는 것:

- 로컬 Docker Desktop
- 로컬 `gonggong-postgres` 컨테이너
- 로컬 터미널/IDE
- 로컬 Docker image

주의:

- 로컬 Docker를 꺼도 AWS 배포본과 Chrome Web Store 심사에는 영향 없음.
- AWS 리소스는 로컬 Docker와 무관하게 비용이 계속 발생함.
