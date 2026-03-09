# AAP Console — Product Requirements Document (PRD)

> 버전: 1.0
> 작성일: 2026-03-05
> 상태: Draft

---

## 목차

1. [개요](#1-개요)
2. [용어 정의](#2-용어-정의)
3. [시스템 아키텍처 개요](#3-시스템-아키텍처-개요)
4. [리소스 계층 구조](#4-리소스-계층-구조)
5. [핵심 기능 요구사항](#5-핵심-기능-요구사항)
6. [비기능 요구사항](#6-비기능-요구사항)
7. [신규 Project 생성 워크플로우](#7-신규-project-생성-워크플로우)
8. [Terraform State 관리 전략](#8-terraform-state-관리-전략)
9. [기술 스택](#9-기술-스택)
10. [마일스톤 및 우선순위](#10-마일스톤-및-우선순위)
11. [리스크 및 의존성](#11-리스크-및-의존성)
12. [부록](#12-부록)

---

## 1. 개요

### 1.1 배경

조직 내 다양한 팀이 AI/LLM 기반 서비스를 구축하기 위해 공통 인프라(인증, 모델 게이트웨이, 관측성 등)를 필요로 한다. 현재는 각 팀의 온보딩 시 수동으로 인프라를 구성하고 있어 시간 소요가 크고, 설정 오류 및 보안 누수 위험이 존재한다.

### 1.2 목적

타 부서 사용자가 **셀프서비스 방식**으로 Organization과 Project를 등록하면, AAP의 공유 서비스들(Keycloak, LiteLLM, Langfuse 등)에 해당 Project를 지원하기 위한 **설정이 자동으로 추가**되는 관리 콘솔을 구축한다.

### 1.3 대상 사용자

| 역할 | 설명 |
|------|------|
| **팀 관리자** | Organization 하위에 Project를 생성하고 서비스 설정을 관리하는 타 부서 담당자 |
| **플랫폼 관리자** | AAP 전체 Organization을 관리하고 정책을 설정하는 운영팀 |
| **개발자** | 발급된 인증 정보 및 SDK Key를 활용하여 서비스를 개발하는 사용자 |

---

## 2. 용어 정의

| 용어 | 설명 |
|------|------|
| **AAP** | AI Assistant Platform. AI/LLM 서비스 구축을 위한 공통 플랫폼 |
| **Organization** | 최상위 관리 단위. 복수의 Project를 포함 |
| **Project** | Organization 하위의 관리 단위. Console에서 생성/관리하는 서비스 설정의 격리 단위 |
| **App (App ID)** | Project의 구현 단에서의 식별자. 공유 서비스들이 `x-application-id` 헤더로 Project를 식별할 때 사용하는 ID |
| **PAK** | Project API Key. 간편 인증을 위한 프로젝트 전용 API 키 |
| **LiteLLM** | LLM 모델 라우팅 및 프록시 게이트웨이. App ID로 Project별 요청을 식별 |
| **Langfuse** | LLM 호출에 대한 관측성(Observability) 및 트레이싱 플랫폼 |
| **SealedSecret** | K8s 클러스터에서 Secret을 안전하게 관리하기 위한 암호화된 Kubernetes Secret. SS Controller가 복호화하여 각 서비스에 주입 |
| **aap-helm-charts** | AAP 서비스들의 K8s 배포용 Helm Chart 레포. SealedSecret YAML 파일 포함 |
| **Config Server** | Nginx 기반의 설정 파일 서빙 서버. Git으로 데이터와 이력을 관리하며, LiteLLM이 동적으로 Config를 가져가는 출처. 별도 레포(`aap-config-server`)로 관리 |
| **Terraform Workspace** | Project(App ID)별 독립적인 Terraform 실행 및 상태 관리 단위 |

---

## 3. 시스템 아키텍처 개요

```
                         ┌──────────────┐
                         │  사내 SSO IdP │
                         └──────┬───────┘
                                │
                         ┌──────▼───────┐
                         │   Keycloak   │
                         │ (SSO Broker) │
                         └──────┬───────┘
                       인증 후   │
               ┌────────────────┼────────────────┐
               ▼                ▼                ▼
        ┌────────────┐  ┌────────────┐  ┌──────────────┐
        │ AAP Console│  │  LiteLLM   │  │   Langfuse   │──▶ S3
        │  (Rails)   │  │ (LLM G/W)  │  │  (관측성)     │
        └─────┬──────┘  └─────┬──────┘  └──────────────┘
              │        config │▲ reload
              │         fetch ▼│  webhook
    ┌─────────▼─────┐  ┌──────┴──────────┐
    │ Terraform     │  │  Config Server  │  Nginx + Git (aap-config-server)
    │ Orchestrator  ├─▶│  · LiteLLM Config│  모델 라우팅, 가드레일, S3 경로
    │ (Bg Jobs)     │  │  · Langfuse SK/PK│  LiteLLM→Langfuse 트레이싱 인증
    └──┬────────────┘  └─────────────────┘
       │
       │ SealedSecret / Chart 값 업데이트
       ▼
    ┌────────────────────┐
    │  aap-helm-charts   │
    │  (Helm Repo)       │
    │  · Langfuse Chart  │ ← Retention 정책 (환경변수)
    │  · Config Server   │ ← Config Server 배포 Chart
    │  · SealedSecrets   │ ← Keycloak Client Secret, PAK 등
    └─────────┬──────────┘
              │ 배포
              ▼
┌─ K8s Cluster ──────────────────────────────────────────┐
│                                                         │
│  ┌──────────────────┐                                   │
│  │ SealedSecret     │───▶ 각 서비스 Pod에 Secret 주입   │
│  │ Controller       │                                   │
│  └──────────────────┘                                   │
│                                                         │
│  Keycloak · LiteLLM · Langfuse · Config Server · ...   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**흐름 설명**:
- **사용자 인증**: 사용자 → Keycloak(SSO IdP 브로커) → 인증 후 AAP Console / LiteLLM / Langfuse 접근
- **Project 설정 반영** (3경로):
  1. **리소스 생성 (Terraform)**: Keycloak Client 생성 등 Terraform Provider 기반 리소스
  2. **동적 Config 반영 (Config Server)**: LiteLLM Config(모델 라우팅, 가드레일, S3 경로, Langfuse SK/PK)를 Config Server Git에 커밋 → Console이 LiteLLM에 reload webhook 전송 → LiteLLM이 Config Server에서 fetch하여 즉시 반영 (재배포 불필요)
  3. **Helm Chart 반영 (aap-helm-charts)**: SealedSecret, Langfuse Retention 환경변수 등 배포 시 반영이 필요한 설정

**Config Server 동작 방식**:
- Nginx 기반으로 Git 레포의 config 파일을 static file로 서빙
- DB 없이 Git으로만 데이터와 변경 이력을 관리
- LiteLLM은 webhook(즉시 반영) + polling(5분 주기 fallback)으로 config를 동적 reload

**Helm Chart별 업데이트 내용**:

| Helm Chart | Project 생성 시 업데이트되는 내용 | 비고 |
|------------|-------------------------------|------|
| **LiteLLM Chart** | (해당 없음 — 동적 설정은 Config Server에서 로드) | 모델 Config, Langfuse SK/PK 등은 Config Server에서 동적 관리 |
| **Langfuse Chart** | Retention 정책 (환경변수) | 데이터 보관 주기 설정 |
| **Config Server Chart** | Config Server 배포 설정 | `aap-config-server` 레포의 서버 코드를 배포 |

---

## 4. 리소스 계층 구조

```
Organization (조직)
 └── Project (App ID 발급)
      │
      ├── Keycloak 설정 ─────────── [Terraform]
      │    └── Client 생성 (SAML / OIDC / OAuth / PAK)
      │
      ├── Langfuse 설정 ─────────── [Langfuse API]
      │    ├── Langfuse Org/Project 생성
      │    ├── SDK Key 발급 (PK/SK) → Config Server (LiteLLM 동적 로드)
      │    └── Retention 정책 → Langfuse Chart (환경변수)
      │
      ├── LiteLLM 설정 ──────────── [Config Server]
      │    ├── 모델 라우팅 Config
      │    ├── 가드레일 설정
      │    ├── App별 S3 경로 (prefix)
      │    └── App별 S3 Retention 설정
      │
      └── Terraform State (App ID별 분리)
```

- **생명주기**: Project 생성(설정 추가) → 운영 → 설정 변경 → 삭제(전체 롤백)

---

## 5. 핵심 기능 요구사항

### FR-1. Organization 관리 (CRUD)

| 항목 | 상세 |
|------|------|
| **생성** | 신규 Organization 등록. 조직명, 설명 입력. 생성 시 멤버 목록 관리 (초기 관리자 지정) |
| **조회** | Organization 목록 및 상세 정보 (소속 Project 현황, 멤버 목록 포함) 확인 |
| **수정** | Organization 정보 변경 (이름, 설명) 및 멤버 추가/제거/권한 변경 |
| **삭제** | Organization 삭제 시 하위 모든 Project의 설정도 함께 제거 |

### FR-2. 접근제어 (RBAC)

Organization 단위로 사용자 접근 권한을 관리한다. 하위 Project에 대한 접근 범위도 Organization 멤버십에 의해 결정된다.

| 항목 | 상세 |
|------|------|
| **권한 수준** | `admin` — Org 설정 및 멤버 관리, Project 생성/삭제 가능 <br> `write` — Project 설정 변경 가능 <br> `read` — Project 조회만 가능 |
| **멤버 관리** | Organization 생성/수정 시 사용자별 권한 수준을 지정하여 멤버 목록 관리 |
| **권한 상속** | Organization 멤버십이 하위 모든 Project에 동일하게 적용 |
| **Console UI 제어** | 권한 수준에 따라 UI 요소(버튼, 메뉴 등) 활성/비활성 처리 |
| **API 제어** | 모든 API 엔드포인트에서 요청자의 권한 수준을 검증 |

### FR-3. Project 관리 (CRUD)

| 항목 | 상세 |
|------|------|
| **생성** | Organization 하위에 신규 Project 등록. 이름, 설명 입력. 생성 시 App ID 자동 발급 |
| **조회** | Project 목록 및 상세 정보 (각 서비스에 추가된 설정 현황, 발급된 App ID) 확인 |
| **수정** | Project 설정 변경 (인증 방식, 모델 라우팅, Retention 정책 등) |
| **삭제** | Project 삭제 시 생성/수정 과정에서 추가된 **모든** 내역을 롤백. 아래 전체 대상 참고 |

**삭제 시 롤백 대상**:

| 대상 | 롤백 내용 |
|------|-----------|
| **Terraform 리소스** | `terraform destroy` 실행 (Keycloak Client 등) |
| **Langfuse 리소스** | Langfuse API를 통해 프로젝트 및 SDK Key 삭제 |
| **Config Server** | 해당 App의 LiteLLM Config, Langfuse SK/PK 설정을 Git에서 제거 후 커밋 → reload webhook |
| **aap-helm-charts** | 해당 App 관련 SealedSecret, Retention 환경변수 등을 Git에서 제거 후 커밋 |
| **K8s SealedSecret** | 클러스터에 생성된 해당 App의 SealedSecret 리소스 및 복호화된 Secret 삭제 |

> **구현 고려사항**: 동일 파일 내에서 여러 Project의 설정이 공존할 수 있으므로, Project별 설정 격리 전략이 필요하다. 삭제 시 다른 Project의 설정을 훼손하지 않도록 App ID 기반의 섹션 분리 또는 파일 분리 방식을 설계해야 한다.

### FR-4. 인증 체계 자동 구성

사용자가 Project 생성 시 인증 방식을 선택하면 자동으로 구성된다.

| 인증 방식 | 구성 내용 |
|-----------|-----------|
| **SAML** | Keycloak에 SAML Client 자동 생성, SP 메타데이터 제공 |
| **OIDC** | Keycloak에 OIDC Client 자동 생성, Client ID/Secret 발급 |
| **OAuth** | Keycloak OAuth Client 구성 및 Redirect URI 설정 |
| **PAK (Project API Key)** | Console에서 API Key 자동 생성 및 발급 |

- Keycloak Terraform Provider를 활용하여 Client 생성을 자동화한다.
- PAK 선택 시에는 Terraform 없이 Console 자체에서 키를 생성한다.

### FR-5. Langfuse 프로젝트 생성 및 SDK Key 발급

| 항목 | 상세 |
|------|------|
| **프로젝트 생성** | Langfuse API를 통해 Project별 독립 Langfuse 프로젝트 자동 생성 |
| **SDK Key 발급** | Public Key, Secret Key 자동 발급. Console에서의 조회는 **플랫폼 관리자만 가능** |
| **트레이싱 연동** | 발급된 Langfuse SK/PK를 Config Server에 반영하여 LiteLLM이 동적으로 로드, 트레이싱 자동 연동 |
| **Retention 정책** | Project 생성 시 Console에서 데이터 보관 주기 설정. Langfuse Chart의 환경변수로 반영 |

### FR-6. LiteLLM Config 자동 생성 및 동적 반영

| 항목 | 상세 |
|------|------|
| **모델 라우팅** | 사용할 LLM 목록 선택 및 모델별 정책(Rate Limit 등) 구성 |
| **가드레일** | 사용자 선택 기반의 보안 가드레일 적용 (컨텐츠 필터링, 토큰 제한 등) |
| **S3 경로** | App별 S3 버킷 경로 (prefix)를 Config에 포함. 기존 공유 버킷을 사용하며 별도 버킷 생성 불필요 |
| **S3 Retention** | App별 S3 데이터 보관 주기를 LiteLLM Config에 설정 |
| **Config 반영** | 생성된 Config를 Config Server Git 레포에 커밋. LiteLLM 재배포 없이 동적 반영 |
| **Reload 방식** | Console → LiteLLM에 reload webhook 전송 → LiteLLM이 Config Server에서 fetch. Polling(5분 주기)을 fallback으로 운용 |

### FR-7. SealedSecret 자동 생성 및 Helm Chart 레포 연동

| 항목 | 상세 |
|------|------|
| **자동 생성** | 발급된 모든 키/시크릿을 SealedSecret YAML로 자동 변환 |
| **레포 저장** | 생성된 SealedSecret YAML을 `aap-helm-charts` 레포에 자동 커밋 |
| **K8s 반영** | K8s 클러스터의 SealedSecret Controller가 복호화하여 각 서비스에 Secret 주입 |
| **키 대상** | Keycloak Client Secret, PAK 등 (Langfuse SK/PK는 Config Server에서 관리) |

### FR-8. 실시간 Terraform 실행 로그 시각화

| 항목 | 상세 |
|------|------|
| **로그 스트리밍** | Terraform plan/apply 실행 중 발생하는 로그를 실시간 전송 |
| **UI 표시** | Console에서 배포 진행 상황을 실시간으로 확인 가능 |
| **구현 방식** | ActionCable(WebSocket) 기반 실시간 스트리밍 |
| **이력 보관** | 완료된 실행 로그는 저장하여 사후 조회 가능 |

### FR-9. 설정 변경 이력 관리 및 버전 롤백

| 항목 | 상세 |
|------|------|
| **이력 관리** | Project별 설정 변경 시마다 버전 기록 (aap-helm-charts 및 Config Server Git 커밋 기반) |
| **버전 조회** | Console에서 변경 이력 목록 및 diff 확인 |
| **롤백** | 이전 안정 버전의 Terraform 구성으로 즉시 복구 가능 |
| **감사 로그** | 누가, 언제, 어떤 설정을 변경했는지 추적 |

### FR-10. Health Check 및 정합성 검증

| 항목 | 상세 |
|------|------|
| **Keycloak 검증** | 인증 Client 생성 후 로그인 테스트 자동 실행 |
| **LiteLLM 검증** | Config 적용 후 API 호출 정상 여부 확인 |
| **Langfuse 검증** | 프로젝트 생성 후 SDK Key로 연결 테스트 |
| **종합 리포트** | 검증 결과를 Console에 표시하고, 실패 시 알림 |

---

## 6. 비기능 요구사항

### 6.1 보안

- 발급된 시크릿(Keycloak Client Secret, PAK 등)은 SealedSecret으로 암호화하여 관리
- Langfuse SK/PK는 Config Server Git에서 관리 (LiteLLM이 동적 로드)
- Console 접근은 조직 SSO를 통한 인증 필수
- Organization 단위 RBAC (admin/write/read) 기반 접근제어
- Project 간 서비스 설정 격리 (테넌트 격리)
- API 통신 시 TLS 필수

### 6.2 성능

- Project 생성 요청 후 전체 설정 완료까지 목표: 5분 이내
- Console UI 페이지 로드 시간: 2초 이내
- 실시간 로그 스트리밍 지연: 1초 이내

### 6.3 확장성

- 동시 다수 Project 생성 요청 처리 가능 (Background Job 큐 기반)
- Organization 및 Project 수 증가에 따른 수평 확장 고려

### 6.4 가용성

- Terraform 실행 실패 시 자동 재시도 및 롤백 메커니즘
- 공유 서비스(Keycloak, Langfuse, LiteLLM) 장애 시 부분 실패 처리 및 재시도

### 6.5 관측성

- Project 설정 작업 상태 모니터링 (성공/실패/진행중)
- 공유 서비스 연동 상태 대시보드

---

## 7. 신규 Project 생성 워크플로우

사용자가 Console에서 Project를 생성하면, 각 공유 서비스에 리소스가 생성되고 Config Server와 Helm Chart에 반영된다.

```
사용자: Project 생성 요청 (이름, 인증 방식, 모델 목록, Retention 등 입력)
  │
  ▼
Step 1. Project 레코드 생성 (DB) + App ID 발급
  │
  ▼
Step 2. Terraform Workspace 초기화 (App ID 기반)
  │
  │ ── 리소스 생성 (각 서비스 Provider/API) ──
  │
  ├──▶ Step 3a. Keycloak 리소스 생성 [Terraform]
  │     └─ 선택한 인증 방식에 따라 Client 생성 또는 PAK 발급
  │
  └──▶ Step 3b. Langfuse 리소스 생성 [Langfuse API]
        ├─ Langfuse Org/Project 생성
        └─ SDK Key (PK/SK) 발급
  │
  │ ── 설정 반영 ──
  │
  ├──▶ Step 4a. Config Server 반영 [Git 커밋 + Webhook]
  │     ├─ LiteLLM Config (모델 라우팅, 가드레일, S3 경로) → Git 커밋
  │     ├─ Langfuse SK/PK → Git 커밋 (LiteLLM이 동적 로드)
  │     └─ Console → LiteLLM reload webhook → 즉시 반영
  │
  └──▶ Step 4b. aap-helm-charts 반영 [Git 커밋]
        ├─ Retention 정책 → Langfuse Chart (환경변수)
        └─ 기타 Secret → 해당 Chart (SealedSecret: Keycloak Client Secret, PAK 등)
  │
  ▼
Step 5. Health Check 실행 (정합성 검증)
  │
  ▼
Step 6. 완료 → Console에 결과 표시
```

**병렬 처리**: Step 3a ~ 3b는 상호 독립적이므로 병렬 실행. Step 4a ~ 4b도 병렬 실행 가능.

---

## 8. Terraform State 관리 전략

### 8.1 State 분리 원칙

- **Project(App ID) 단위 State**: 각 App ID마다 독립적인 Terraform State 파일 유지
- **영향도 최소화**: 한 Project의 변경이 다른 Project에 영향을 주지 않음
- **Backend**: S3 + DynamoDB를 활용한 Remote State 관리

### 8.2 State 경로 규칙

```
s3://aap-terraform-state/{organization_id}/{app_id}/terraform.tfstate
```

### 8.3 자원 회수 (Destroy)

- Project 삭제 요청 시 해당 App ID의 Terraform Workspace에 대해 `terraform destroy` 자동 실행 (각 서비스에서 관련 설정 제거)
- Destroy 완료 후 State 파일 아카이브 처리 (감사 목적 보관)
- Destroy 실패 시 관리자 알림 및 수동 개입 프로세스 제공

### 8.4 Locking

- DynamoDB 기반 State Lock으로 동시 변경 방지
- Lock Timeout 설정을 통한 교착 상태 방지

---

## 9. 기술 스택

| 영역 | 기술 | 비고 |
|------|------|------|
| **Backend** | Ruby on Rails 7+ | API 서버, 비즈니스 로직, Background Job 처리 |
| **Frontend** | Rails View + Hotwire (Turbo/Stimulus) | SPA 없이 실시간 UI 업데이트 |
| **실시간 통신** | ActionCable (WebSocket) | Terraform 로그 스트리밍 |
| **Background Job** | Sidekiq + Redis | Terraform 실행, 비동기 설정 처리 |
| **Database** | PostgreSQL | Organization/Project 메타데이터, 실행 이력, 감사 로그 |
| **IaC** | Terraform | aap-helm-charts 업데이트를 통한 서비스 설정 자동화 |
| **인증** | Keycloak (Terraform Provider) | SAML/OIDC/OAuth Client 자동 구성 |
| **관측성** | Langfuse (API 연동) | LLM 트레이싱 프로젝트 및 키 관리 |
| **LLM 게이트웨이** | LiteLLM | 모델 라우팅, 가드레일, Rate Limit. Config Server에서 동적 config reload |
| **Config Server** | Nginx + Git (`aap-config-server`) | LiteLLM Config 서빙. DB 없이 Git으로 데이터/이력 관리. Helm Chart는 `aap-helm-charts`에 포함 |
| **비밀 관리** | SealedSecret (K8s Controller) | K8s 클러스터 내 서비스별 시크릿 암호화 관리 |
| **K8s 배포** | aap-helm-charts (Helm Repo) | AAP 서비스 배포용 Chart 및 SealedSecret YAML 저장소 |
| **테스트** | RSpec + FactoryBot | TDD 기반 개발. 단위/통합/시스템 테스트 |
| **CI/CD** | (미정) | GitOps 기반 배포 파이프라인 |

### 9.1 개발 방법론

- **TDD (Test-Driven Development)**: 모든 기능은 테스트 코드 선행 작성 후 구현
- **테스트 커버리지 목표**: 90% 이상
- **테스트 유형**:
  - Unit Test: 모델, 서비스 객체 단위 테스트
  - Integration Test: Terraform 연동, 외부 API 연동 테스트 (Mock 활용)
  - System Test: E2E 워크플로우 테스트

---

## 10. 마일스톤 및 우선순위

### Phase 1: 핵심 기반 구축 (MVP)

- Rails 프로젝트 초기 설정 및 인증 연동
- Organization CRUD + 멤버십 관리 (FR-1)
- 접근제어 RBAC 기본 구현 (FR-2)
- Project CRUD + App ID 자동 발급 (FR-3)
- Terraform Workspace 기본 연동 (생성/실행/상태 조회)
- Keycloak 인증 체계 자동 구성 — OIDC 우선 (FR-4)
- 기본 UI (Organization/Project 목록, 상세, 생성 폼)

### Phase 2: 서비스 설정 자동화 확장

- Config Server 구축 (`aap-config-server`) 및 Helm Chart 배포
- LiteLLM Config 자동 생성 및 동적 반영 — S3 경로/Retention 포함 (FR-6)
- Langfuse 프로젝트 생성, SDK Key 발급 및 Retention 정책 설정 (FR-5)
- SealedSecret 생성 및 aap-helm-charts 연동 (FR-7)

### Phase 3: 운영 안정성 강화

- 실시간 Terraform 로그 스트리밍 — ActionCable (FR-8)
- 설정 변경 이력 관리 및 버전 롤백 (FR-9)
- Health Check 자동화 (FR-10)
- Project 삭제 시 전체 롤백 자동화 (FR-3 삭제 요구사항)

### Phase 4: 고도화

- 다중 인증 방식 전체 지원 (SAML, OAuth, PAK)
- 관리자 대시보드 (전체 Organization/Project 현황, 서비스 설정 상태)
- 알림 시스템 (설정 완료/실패, 이상 감지)
- 성능 최적화 및 부하 테스트

---

## 11. 리스크 및 의존성

### 11.1 리스크

| 리스크 | 영향도 | 완화 방안 |
|--------|--------|-----------|
| Terraform 실행 시간 초과 | 높음 | 타임아웃 설정, 부분 실패 처리, 재시도 로직 |
| 공유 서비스(Keycloak/Langfuse/LiteLLM) 장애 | 높음 | Circuit Breaker 패턴, 부분 설정 허용 |
| Terraform State 충돌 | 중간 | DynamoDB Lock, 직렬 실행 보장 |
| SealedSecret 인증서 만료 | 중간 | 인증서 갱신 자동화, 모니터링 알림 |
| Config Server 장애 시 LiteLLM config 갱신 불가 | 중간 | LiteLLM이 마지막 config를 캐싱하여 운영 지속. Polling fallback으로 복구 시 자동 동기화 |
| aap-helm-charts 레포 충돌 | 낮음 | Retry with rebase, 충돌 감지 및 알림 |

### 11.2 외부 의존성

| 시스템 | 의존 유형 | 비고 |
|--------|-----------|------|
| Keycloak | Terraform Provider + Admin API | 인증 체계 구성 |
| Langfuse | REST API | 프로젝트/키 관리 |
| LiteLLM | Config Server + Reload Webhook | 모델 라우팅, 가드레일, S3 경로 설정 |
| Config Server | Nginx + Git (`aap-config-server`) | LiteLLM Config 서빙 |
| aap-helm-charts | Git API | SealedSecret YAML 및 Helm Chart 관리 |

---

## 12. 부록

- **업무 목표 상세**: [docs/business-objectives.md](./business-objectives.md)
