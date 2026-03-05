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
7. [신규 App 생성 워크플로우](#7-신규-app-생성-워크플로우)
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

타 부서 사용자가 **셀프서비스 방식**으로 프로젝트(App)를 등록하고, 필요한 인프라 자원(인증, 관측성, LLM 게이트웨이, 스토리지)을 **자동으로 프로비저닝** 받을 수 있는 관리 콘솔을 구축한다.

### 1.3 대상 사용자

| 역할 | 설명 |
|------|------|
| **팀 관리자** | 신규 App을 생성하고 인프라 설정을 관리하는 타 부서 담당자 |
| **플랫폼 관리자** | AAP 전체 Organization을 관리하고 정책을 설정하는 운영팀 |
| **개발자** | 발급된 인증 정보 및 SDK Key를 활용하여 서비스를 개발하는 사용자 |

---

## 2. 용어 정의

| 용어 | 설명 |
|------|------|
| **AAP** | AI Assistant Platform. AI/LLM 서비스 구축을 위한 공통 플랫폼 |
| **App (App ID)** | 타 팀이 등록하는 프로젝트 단위. 모든 인프라 자원의 격리 단위 |
| **Organization** | 최상위 관리 단위. 복수의 App을 포함 |
| **PAK** | Project API Key. 간편 인증을 위한 프로젝트 전용 API 키 |
| **LiteLLM** | LLM 모델 라우팅 및 프록시 게이트웨이 |
| **Langfuse** | LLM 호출에 대한 관측성(Observability) 및 트레이싱 플랫폼 |
| **SealedSecret** | GitOps 환경에서 Secret을 안전하게 저장하기 위한 암호화된 Kubernetes Secret |
| **Terraform Workspace** | App별 독립적인 Terraform 실행 및 상태 관리 단위 |

---

## 3. 시스템 아키텍처 개요

```
┌─────────────────────────────────────────────────────────┐
│                    AAP Console (Rails)                   │
│  ┌───────────────┐  ┌───────────────┐  ┌─────────────┐  │
│  │   Console UI  │  │   API Server  │  │  Background  │  │
│  │  (Rails View/ │──│  (Rails API)  │──│    Jobs      │  │
│  │   Hotwire)    │  │               │  │  (Sidekiq)   │  │
│  └───────────────┘  └───────┬───────┘  └──────┬──────┘  │
└─────────────────────────────┼─────────────────┼─────────┘
                              │                 │
                    ┌─────────▼─────────────────▼──────┐
                    │      Terraform Orchestrator      │
                    │  (Workspace 생성/실행/상태 관리)    │
                    └─────────┬────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
     ┌────────▼──────┐ ┌─────▼──────┐ ┌──────▼───────┐
     │   Keycloak    │ │  Langfuse  │ │   LiteLLM    │
     │  (인증 체계)   │ │ (관측성)    │ │ (LLM 게이트웨이)│
     └───────────────┘ └────────────┘ └──────────────┘
              │               │               │
     ┌────────▼──────┐ ┌─────▼──────┐ ┌──────▼───────┐
     │  AWS S3       │ │  GitOps    │ │  SealedSecret│
     │  (스토리지)    │ │  (버전관리)  │ │  (비밀 관리)  │
     └───────────────┘ └────────────┘ └──────────────┘
```

---

## 4. 리소스 계층 구조

```
Organization (조직)
 └── Project / App ID (프로젝트)
      ├── Auth Config (인증 설정)
      │    └── SAML / OIDC / OAuth / PAK
      ├── Langfuse Project (관측성)
      │    └── Public Key / Secret Key
      ├── S3 Storage (스토리지)
      │    └── bucket/prefix + Retention Policy
      ├── LiteLLM Config (LLM 게이트웨이)
      │    └── Model Routing + Guardrails
      ├── SealedSecrets (비밀 관리)
      └── Terraform State (인프라 상태)
```

- **격리 원칙**: 각 App ID는 독립적인 인프라 자원과 보안 정책을 가진다.
- **생명주기**: App 생성 → 운영 → (설정 변경) → 삭제(자원 회수) 전체 주기를 관리한다.

---

## 5. 핵심 기능 요구사항

### FR-1. App 관리 (CRUD)

| 항목 | 상세 |
|------|------|
| **생성** | Organization 하위에 신규 App 등록. App 이름, 설명, 소유 팀 정보 입력 |
| **조회** | App 목록 및 상세 정보(발급된 인프라 정보 포함) 확인 |
| **수정** | App 설정 변경 (인증 방식, 모델 라우팅, Retention 정책 등) |
| **삭제** | App 삭제 시 연관된 모든 인프라 자원 자동 회수 (Terraform destroy) |

### FR-2. 인증 체계 자동 구성

사용자가 App 생성 시 인증 방식을 선택하면 자동으로 구성된다.

| 인증 방식 | 구성 내용 |
|-----------|-----------|
| **SAML** | Keycloak에 SAML Client 자동 생성, SP 메타데이터 제공 |
| **OIDC** | Keycloak에 OIDC Client 자동 생성, Client ID/Secret 발급 |
| **OAuth** | Keycloak OAuth Client 구성 및 Redirect URI 설정 |
| **PAK (Project API Key)** | Console에서 API Key 자동 생성 및 발급 |

- Keycloak Terraform Provider를 활용하여 Client 생성을 자동화한다.
- PAK 선택 시에는 Terraform 없이 Console 자체에서 키를 생성한다.

### FR-3. Langfuse 프로젝트 생성 및 SDK Key 발급

| 항목 | 상세 |
|------|------|
| **프로젝트 생성** | Langfuse API를 통해 App별 독립 프로젝트 자동 생성 |
| **SDK Key 발급** | Public Key, Secret Key 자동 발급 후 Console에 표시 |
| **트레이싱 연동** | LiteLLM과 Langfuse 간 트레이싱 자동 설정 (LiteLLM 환경변수 업데이트) |

### FR-4. S3 스토리지 경로 및 Retention 정책 설정

| 항목 | 상세 |
|------|------|
| **경로 생성** | App 전용 S3 경로 (bucket/prefix) 자동 생성 |
| **Retention 정책** | App 생성 시 Console에서 데이터 보관 주기 설정 가능 |
| **정책 적용** | S3 Lifecycle Rule로 Retention 정책 자동 반영 |

### FR-5. LiteLLM Config 자동 생성

| 항목 | 상세 |
|------|------|
| **모델 라우팅** | 사용할 LLM 목록 선택 및 모델별 정책(Rate Limit 등) 구성 |
| **가드레일** | 사용자 선택 기반의 보안 가드레일 적용 (컨텐츠 필터링, 토큰 제한 등) |
| **Config 반영** | 생성된 설정을 LiteLLM 서버의 config.yaml에 동적 반영 |

### FR-6. SealedSecret 자동 생성 및 GitOps 연동

| 항목 | 상세 |
|------|------|
| **자동 생성** | 발급된 모든 키/시크릿을 SealedSecret 형태로 자동 변환 |
| **GitOps 저장** | 생성된 SealedSecret을 GitOps 레포지토리에 자동 커밋 |
| **키 대상** | Keycloak Client Secret, Langfuse SDK Key, PAK 등 |

### FR-7. 실시간 Terraform 실행 로그 시각화

| 항목 | 상세 |
|------|------|
| **로그 스트리밍** | Terraform plan/apply 실행 중 발생하는 로그를 실시간 전송 |
| **UI 표시** | Console에서 배포 진행 상황을 실시간으로 확인 가능 |
| **구현 방식** | ActionCable(WebSocket) 기반 실시간 스트리밍 |
| **이력 보관** | 완료된 실행 로그는 저장하여 사후 조회 가능 |

### FR-8. 설정 변경 이력 관리 및 버전 롤백

| 항목 | 상세 |
|------|------|
| **이력 관리** | App별 인프라 설정 변경 시마다 버전 기록 (GitOps 커밋 기반) |
| **버전 조회** | Console에서 변경 이력 목록 및 diff 확인 |
| **롤백** | 이전 안정 버전의 Terraform 구성으로 즉시 복구 가능 |
| **감사 로그** | 누가, 언제, 어떤 설정을 변경했는지 추적 |

### FR-9. Health Check 및 정합성 검증

| 항목 | 상세 |
|------|------|
| **Keycloak 검증** | 인증 Client 생성 후 로그인 테스트 자동 실행 |
| **LiteLLM 검증** | Config 적용 후 API 호출 정상 여부 확인 |
| **Langfuse 검증** | 프로젝트 생성 후 SDK Key로 연결 테스트 |
| **종합 리포트** | 검증 결과를 Console에 표시하고, 실패 시 알림 |

---

## 6. 비기능 요구사항

### 6.1 보안

- 모든 발급된 시크릿은 SealedSecret으로 암호화하여 관리
- Console 접근은 조직 SSO를 통한 인증 필수
- App 간 인프라 자원 완전 격리 (테넌트 격리)
- API 통신 시 TLS 필수

### 6.2 성능

- App 생성 요청 후 전체 프로비저닝 완료까지 목표: 5분 이내
- Console UI 페이지 로드 시간: 2초 이내
- 실시간 로그 스트리밍 지연: 1초 이내

### 6.3 확장성

- 동시 다수 App 프로비저닝 요청 처리 가능 (Background Job 큐 기반)
- Organization 및 App 수 증가에 따른 수평 확장 고려

### 6.4 가용성

- Terraform 실행 실패 시 자동 재시도 및 롤백 메커니즘
- 외부 시스템(Keycloak, Langfuse, LiteLLM) 장애 시 부분 실패 처리 및 재시도

### 6.5 관측성

- 프로비저닝 작업 상태 모니터링 (성공/실패/진행중)
- 외부 시스템 연동 상태 대시보드

---

## 7. 신규 App 생성 워크플로우

사용자가 Console에서 App을 생성하면 아래 프로세스가 순차적으로 실행된다.

```
사용자: App 생성 요청 (이름, 인증 방식, 모델 목록, Retention 등 입력)
  │
  ▼
Step 1. App 레코드 생성 (DB)
  │
  ▼
Step 2. Terraform Workspace 초기화 (App ID 기반)
  │
  ├──▶ Step 3a. 인증 체계 구성 (Auth)
  │     └─ 선택한 인증 방식에 따라 Keycloak Client 생성 또는 PAK 발급
  │
  ├──▶ Step 3b. 관측성 환경 구축 (Langfuse)
  │     ├─ Langfuse 프로젝트 생성
  │     ├─ SDK Key (Public/Secret) 발급
  │     └─ LiteLLM ↔ Langfuse 트레이싱 연동 설정
  │
  ├──▶ Step 3c. 스토리지 구성 (S3)
  │     ├─ App 전용 S3 경로 생성
  │     └─ Retention 정책 (Lifecycle Rule) 적용
  │
  └──▶ Step 3d. LLM 게이트웨이 설정 (LiteLLM)
        ├─ 모델 라우팅 Config 생성
        └─ 가드레일 설정 적용
  │
  ▼
Step 4. SealedSecret 생성 및 GitOps 커밋
  │
  ▼
Step 5. Health Check 실행 (정합성 검증)
  │
  ▼
Step 6. 프로비저닝 완료 → Console에 결과 표시
```

**병렬 처리**: Step 3a ~ 3d는 상호 독립적이므로 병렬 실행하여 프로비저닝 시간을 단축한다.

---

## 8. Terraform State 관리 전략

### 8.1 State 분리 원칙

- **App 단위 State**: 각 App ID마다 독립적인 Terraform State 파일 유지
- **영향도 최소화**: 한 App의 변경이 다른 App에 영향을 주지 않음
- **Backend**: S3 + DynamoDB를 활용한 Remote State 관리

### 8.2 State 경로 규칙

```
s3://aap-terraform-state/{organization_id}/{app_id}/terraform.tfstate
```

### 8.3 자원 회수 (Destroy)

- App 삭제 요청 시 해당 App의 Terraform Workspace에 대해 `terraform destroy` 자동 실행
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
| **Background Job** | Sidekiq + Redis | Terraform 실행, 비동기 프로비저닝 |
| **Database** | PostgreSQL | App 메타데이터, 실행 이력, 감사 로그 |
| **IaC** | Terraform | 인프라 프로비저닝 핵심 도구 |
| **인증** | Keycloak (Terraform Provider) | SAML/OIDC/OAuth Client 자동 구성 |
| **관측성** | Langfuse (API 연동) | LLM 트레이싱 프로젝트 및 키 관리 |
| **LLM 게이트웨이** | LiteLLM | 모델 라우팅, 가드레일, Rate Limit |
| **스토리지** | AWS S3 (Terraform Provider) | App별 전용 경로 및 Lifecycle 관리 |
| **비밀 관리** | SealedSecret + GitOps | 암호화된 시크릿의 버전 관리 |
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
- App CRUD (생성/조회/수정/삭제)
- Terraform Workspace 기본 연동 (생성/실행/상태 조회)
- Keycloak 인증 체계 자동 구성 (OIDC 우선)
- 기본 UI (App 목록, 상세, 생성 폼)

### Phase 2: 인프라 자동화 확장

- Langfuse 프로젝트 생성 및 SDK Key 발급
- S3 스토리지 경로 및 Retention 정책
- LiteLLM Config 자동 생성
- SealedSecret 생성 및 GitOps 연동

### Phase 3: 운영 안정성 강화

- 실시간 Terraform 로그 스트리밍 (ActionCable)
- 설정 변경 이력 관리 및 버전 롤백
- Health Check 자동화
- App 삭제 시 자원 회수 (destroy) 자동화

### Phase 4: 고도화

- 다중 인증 방식 전체 지원 (SAML, OAuth, PAK)
- 관리자 대시보드 (전체 App 현황, 인프라 상태)
- 알림 시스템 (프로비저닝 완료/실패, 이상 감지)
- 성능 최적화 및 부하 테스트

---

## 11. 리스크 및 의존성

### 11.1 리스크

| 리스크 | 영향도 | 완화 방안 |
|--------|--------|-----------|
| Terraform 실행 시간 초과 | 높음 | 타임아웃 설정, 부분 실패 처리, 재시도 로직 |
| 외부 시스템(Keycloak/Langfuse/LiteLLM) 장애 | 높음 | Circuit Breaker 패턴, 부분 프로비저닝 허용 |
| Terraform State 충돌 | 중간 | DynamoDB Lock, 직렬 실행 보장 |
| SealedSecret 인증서 만료 | 중간 | 인증서 갱신 자동화, 모니터링 알림 |
| GitOps 레포 충돌 | 낮음 | Retry with rebase, 충돌 감지 및 알림 |

### 11.2 외부 의존성

| 시스템 | 의존 유형 | 비고 |
|--------|-----------|------|
| Keycloak | Terraform Provider + Admin API | 인증 체계 구성 |
| Langfuse | REST API | 프로젝트/키 관리 |
| LiteLLM | Config 파일 + API | 모델 라우팅 설정 |
| AWS S3 | Terraform Provider | 스토리지 관리 |
| GitOps Repository | Git API | SealedSecret 및 설정 버전 관리 |

---

## 12. 부록

- **업무 목표 상세**: [docs/business-objectives.md](./business-objectives.md)
