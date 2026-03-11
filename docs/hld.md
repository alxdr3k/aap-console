# AAP Console — High-Level Design (HLD)

> **버전**: 1.1
> **작성일**: 2026-03-11
> **상태**: Draft
> **참조**: [PRD v1.11](./prd.md)

---

## 목차

1. [시스템 개요](#1-시스템-개요)
2. [데이터베이스 스키마](#2-데이터베이스-스키마)
3. [컴포넌트 아키텍처](#3-컴포넌트-아키텍처)
4. [API 설계](#4-api-설계)
5. [프로비저닝 파이프라인](#5-프로비저닝-파이프라인)
6. [실시간 통신 (ActionCable)](#6-실시간-통신-actioncable)
7. [외부 API 클라이언트](#7-외부-api-클라이언트)
8. [인증/인가](#8-인증인가)
9. [주요 화면 와이어프레임](#9-주요-화면-와이어프레임)
10. [설계 결정](#10-설계-결정)
11. [FR 추적 매트릭스](#11-fr-추적-매트릭스)

---

## 1. 시스템 개요

### 1.1 내부 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│  AAP Console (Rails 8)                                          │
│                                                                 │
│  ┌──────────────┐   ┌───────────────┐   ┌───────────────────┐  │
│  │  Controller   │   │   Service     │   │   External API    │  │
│  │  Layer        │   │   Layer       │   │   Clients         │  │
│  │              │   │               │   │                   │  │
│  │ Org          │──▶│ Org           │──▶│ Keycloak::Client  │──── Keycloak
│  │ Project      │   │ Project       │   │ Langfuse::Client  │──── Langfuse
│  │ AuthConfig   │   │ Provisioning  │   │ ConfigServer::    │──── Config Server
│  │ Provisioning │   │ ConfigVersion │   │   Client          │  │
│  │ ConfigVersion│   │               │   └───────────────────┘  │
│  │ Api::V1::Apps│   └───────┬───────┘                          │
│  └──────┬───────┘           │                                  │
│         │                   ▼                                  │
│  ┌──────▼───────┐   ┌───────────────┐   ┌───────────────────┐ │
│  │  View Layer  │   │  Job Layer    │   │  Channel Layer    │ │
│  │  (Hotwire)   │   │  (SolidQueue) │   │  (ActionCable)    │ │
│  │              │   │               │   │                   │ │
│  │ Turbo Frames │   │ Provisioning  │   │ Provisioning      │ │
│  │ Turbo Streams│   │   Job         │   │   Channel         │ │
│  │ Stimulus     │   │ Webhook Job   │   │                   │ │
│  │              │   │ HealthCheck   │   │                   │ │
│  └──────────────┘   │   Job         │   └───────────────────┘ │
│                     └───────────────┘                          │
│                            │                                   │
│                     ┌──────▼───────┐                           │
│                     │  SQLite DB   │                           │
│                     │  (WAL mode)  │                           │
│                     └──────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 레이어 역할

| 레이어 | 역할 | 관련 FR |
|--------|------|---------|
| **Controller** | HTTP 요청 처리, 인가 검증, 응답 렌더링 | 전체 |
| **Service** | 비즈니스 로직 캡슐화. 외부 API 호출 오케스트레이션 | FR-1~9 |
| **External API Client** | 외부 서비스 HTTP 통신 추상화 | FR-1,2,4,5,6 |
| **Job** | SolidQueue 기반 비동기 작업. 프로비저닝, webhook, health check | FR-7,9 |
| **Channel** | ActionCable WebSocket. 프로비저닝 현황 실시간 스트리밍 | FR-7.3 |
| **View** | Hotwire (Turbo + Stimulus) 기반 서버 렌더링 UI | 전체 |
| **Model** | ActiveRecord 모델. DB 스키마, 상태 머신, 유효성 검증 | 전체 |

---

## 2. 데이터베이스 스키마

### 2.1 ERD

```
┌──────────────────┐       ┌──────────────────┐
│  organizations   │       │     projects     │
├──────────────────┤       ├──────────────────┤
│ id            PK │◀──┐   │ id            PK │
│ name             │   │   │ organization_id FK│───▶ organizations
│ slug        UNQ  │   │   │ name             │
│ description      │   │   │ slug        UNQ* │  * (org_id, slug)
│ keycloak_group_id│   │   │ description      │
│ langfuse_org_id  │   │   │ app_id      UNQ  │
│ created_at       │   │   │ status           │  (active/provisioning/
│ updated_at       │   │   │ created_at       │   deleting/deleted)
└──────────────────┘   │   │ updated_at       │
                       │   └──────┬───────────┘
                       │          │
          ┌────────────┘    ┌─────┴─────────────────┐
          │                 │                       │
┌─────────┴────────┐  ┌────▼──────────────┐  ┌────▼──────────────┐
│  audit_logs      │  │ project_auth_     │  │ provisioning_     │
├──────────────────┤  │ configs           │  │ jobs              │
│ id            PK │  ├───────────────────┤  ├───────────────────┤
│ organization_id  │  │ id             PK │  │ id             PK │
│ project_id       │  │ project_id    FK  │  │ project_id    FK  │
│ user_sub         │  │ auth_type         │  │ operation         │
│ user_email       │  │ keycloak_client_id│  │ status            │
│ action           │  │ keycloak_client_  │  │ started_at        │
│ resource_type    │  │   uuid            │  │ completed_at      │
│ resource_id      │  │ created_at        │  │ error_message     │
│ details (JSON)   │  │ updated_at        │  │ created_at        │
│ created_at       │  └───────────────────┘  │ updated_at        │
└──────────────────┘                         └────┬──────────────┘
                                                  │
                         ┌────────────────────────┤
                         │                        │
                   ┌─────▼────────────┐   ┌──────▼────────────┐
                   │ provisioning_    │   │ config_versions   │
                   │ steps            │   ├───────────────────┤
                   ├──────────────────┤   │ id             PK │
                   │ id            PK │   │ project_id    FK  │
                   │ provisioning_    │   │ provisioning_     │
                   │   job_id     FK  │   │   job_id      FK  │
                   │ name             │   │ version_id        │
                   │ step_order       │   │ change_type       │
                   │ status           │   │ change_summary    │
                   │ started_at       │   │ changed_by_sub    │
                   │ completed_at     │   │ changed_by_email  │
                   │ error_message    │   │ snapshot (JSON)   │
                   │ retry_count      │   │ created_at        │
                   │ max_retries      │   └───────────────────┘
                   │ result_snapshot  │
                   │   (JSON)         │
                   │ created_at       │
                   │ updated_at       │
                   └──────────────────┘
```

### 2.2 테이블 상세

#### organizations — FR-1

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | integer PK | |
| `name` | string NOT NULL | 조직 표시명 |
| `slug` | string NOT NULL UNQ | URL-safe 식별자. Keycloak 그룹 경로에 사용 |
| `description` | text | 조직 설명 |
| `keycloak_group_id` | string | Keycloak `/console/orgs/{slug}` 그룹 ID |
| `langfuse_org_id` | string | Langfuse Organization ID |
| `created_at` | datetime | |
| `updated_at` | datetime | |

#### projects — FR-3

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | integer PK | |
| `organization_id` | integer FK NOT NULL | 소속 Organization |
| `name` | string NOT NULL | Project 표시명 |
| `slug` | string NOT NULL | URL-safe 식별자. `(organization_id, slug)` 유니크 |
| `description` | text | Project 설명 |
| `app_id` | string NOT NULL UNQ | 자동 발급. 외부 서비스 식별용 (`x-application-id`) |
| `status` | string NOT NULL DEFAULT 'provisioning' | `provisioning` / `active` / `update_pending` / `deleting` / `deleted` |
| `created_at` | datetime | |
| `updated_at` | datetime | |

**app_id 생성 규칙**: `app-{SecureRandom.alphanumeric(12)}` (예: `app-a3Bf9kR2mX1q`). 충돌 시 재생성.

#### project_auth_configs — FR-4

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | integer PK | |
| `project_id` | integer FK NOT NULL UNQ | 1:1 관계 |
| `auth_type` | string NOT NULL | `oidc` / `saml` / `oauth` / `pak` |
| `keycloak_client_id` | string | Keycloak Client의 `clientId` (예: `aap-acme-chatbot-oidc`). PAK인 경우 NULL |
| `keycloak_client_uuid` | string | Keycloak Client의 내부 UUID. API 호출에 사용 |
| `created_at` | datetime | |
| `updated_at` | datetime | |

> **시크릿 미저장 원칙**: Keycloak Client Secret, PAK 값은 이 테이블에 저장하지 않는다. 생성 시 UI에 일회성 표시 후 폐기 (PRD 6.1).

#### provisioning_jobs — FR-7.1

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | integer PK | |
| `project_id` | integer FK NOT NULL | 대상 Project |
| `operation` | string NOT NULL | `create` / `update` / `delete` |
| `status` | string NOT NULL DEFAULT 'pending' | PRD 상태 머신 참조 |
| `started_at` | datetime | 실행 시작 시각 |
| `completed_at` | datetime | 완료/실패 시각 |
| `error_message` | text | 최종 에러 메시지 |
| `created_at` | datetime | |
| `updated_at` | datetime | |

**상태 값**: `pending` → `in_progress` → `completed` / `failed` → `retrying` → `rolling_back` → `rolled_back` / `rollback_failed`

**동시성 제어**: 동일 `project_id`에 대해 `pending` 또는 `in_progress` 상태의 job이 있으면 새 job 생성을 거부한다 (DB 레벨 체크 + 앱 레벨 검증).

#### provisioning_steps — FR-7.2

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | integer PK | |
| `provisioning_job_id` | integer FK NOT NULL | 소속 Job |
| `name` | string NOT NULL | 단계 식별자 (예: `keycloak_client_create`) |
| `step_order` | integer NOT NULL | 실행 순서 (병렬 단계는 동일 order) |
| `status` | string NOT NULL DEFAULT 'pending' | `pending` / `in_progress` / `completed` / `failed` / `retrying` / `skipped` |
| `started_at` | datetime | |
| `completed_at` | datetime | |
| `error_message` | text | 실패 시 에러 상세 |
| `retry_count` | integer DEFAULT 0 | 현재 재시도 횟수 |
| `max_retries` | integer DEFAULT 3 | 최대 재시도 횟수 |
| `result_snapshot` | JSON | 생성된 리소스 정보. 롤백 시 사용 (예: `{keycloak_client_uuid: "..."}`) |
| `created_at` | datetime | |
| `updated_at` | datetime | |

**단계 정의 (Project Create)**:

| name | step_order | 설명 | 롤백 동작 |
|------|-----------|------|-----------|
| `app_registry_register` | 1 | Config Server webhook (fire-and-forget) | webhook `action: delete` |
| `keycloak_client_create` | 2 | Keycloak Client 생성 (FR-4) | Client 삭제 |
| `langfuse_project_create` | 2 | Langfuse Project + SDK Key (FR-5) | Project 삭제 |
| `config_server_apply` | 3 | Config Server 설정/시크릿 반영 (FR-6) | 설정 삭제 |
| `health_check` | 4 | 정합성 검증 (FR-9) | 없음 (검증만) |

> `step_order=2`인 단계들은 **병렬 실행** 가능.

#### config_versions — FR-8

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | integer PK | |
| `project_id` | integer FK NOT NULL | 대상 Project |
| `provisioning_job_id` | integer FK | 연관 프로비저닝 job (있는 경우) |
| `version_id` | string NOT NULL | Config Server가 반환한 버전 식별자 |
| `change_type` | string NOT NULL | `create` / `update` / `delete` / `rollback` |
| `change_summary` | text | 변경 요약 (예: "모델 목록 변경: +claude-sonnet, -gpt-3.5") |
| `changed_by_sub` | string NOT NULL | 변경 사용자 Keycloak subject |
| `changed_by_email` | string NOT NULL | 변경 사용자 이메일 |
| `snapshot` | JSON | 변경 시점의 설정 스냅샷. Keycloak/Langfuse 롤백 시 사용 |
| `created_at` | datetime | |

#### audit_logs — FR-8

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | integer PK | |
| `organization_id` | integer FK | |
| `project_id` | integer FK | |
| `user_sub` | string NOT NULL | Keycloak subject |
| `user_email` | string NOT NULL | |
| `action` | string NOT NULL | `org.create`, `project.create`, `member.add`, `config.update` 등 |
| `resource_type` | string NOT NULL | `Organization`, `Project`, `Member` 등 |
| `resource_id` | string | 대상 리소스 ID |
| `details` | JSON | 액션별 추가 정보 |
| `created_at` | datetime | |

### 2.3 인덱스

```ruby
# organizations
add_index :organizations, :slug, unique: true

# projects
add_index :projects, [:organization_id, :slug], unique: true
add_index :projects, :app_id, unique: true
add_index :projects, [:organization_id, :status]

# project_auth_configs
add_index :project_auth_configs, :project_id, unique: true

# provisioning_jobs
add_index :provisioning_jobs, [:project_id, :status]
add_index :provisioning_jobs, :status

# provisioning_steps
add_index :provisioning_steps, [:provisioning_job_id, :step_order]

# config_versions
add_index :config_versions, [:project_id, :created_at]

# audit_logs
add_index :audit_logs, [:organization_id, :created_at]
add_index :audit_logs, [:project_id, :created_at]
add_index :audit_logs, :created_at
```

---

## 3. 컴포넌트 아키텍처

### 3.1 디렉토리 구조

```
app/
├── controllers/
│   ├── application_controller.rb         # JWT 인증, RBAC 인가 (FR-2)
│   ├── organizations_controller.rb       # FR-1
│   ├── members_controller.rb             # FR-2
│   ├── projects_controller.rb            # FR-3
│   ├── auth_configs_controller.rb        # FR-4
│   ├── litellm_configs_controller.rb     # FR-6
│   ├── provisioning_jobs_controller.rb   # FR-7.3
│   ├── config_versions_controller.rb     # FR-8
│   └── api/
│       └── v1/
│           └── apps_controller.rb        # Config Server용 App Registry API
│
├── models/
│   ├── organization.rb                   # FR-1
│   ├── project.rb                        # FR-3
│   ├── project_auth_config.rb            # FR-4
│   ├── provisioning_job.rb               # FR-7.1 (상태 머신)
│   ├── provisioning_step.rb              # FR-7.2
│   ├── config_version.rb                 # FR-8
│   └── audit_log.rb                      # FR-8
│
├── services/
│   ├── organizations/
│   │   ├── create_service.rb             # FR-1: Org 생성 + Keycloak 그룹 + Langfuse Org
│   │   ├── update_service.rb             # FR-1
│   │   └── destroy_service.rb            # FR-1: 하위 Project 전체 삭제 후 Org 삭제
│   │
│   ├── projects/
│   │   ├── create_service.rb             # FR-3: DB 생성 + 프로비저닝 job enqueue
│   │   ├── update_service.rb             # FR-3
│   │   └── destroy_service.rb            # FR-3: 삭제 프로비저닝 job enqueue
│   │
│   ├── provisioning/
│   │   ├── orchestrator.rb               # FR-7: 단계 실행 오케스트레이션
│   │   ├── step_runner.rb                # FR-7.2: 개별 단계 실행 + 재시도
│   │   ├── rollback_runner.rb            # FR-7.2: 보상 트랜잭션 역순 실행
│   │   └── steps/                        # 단계별 구현
│   │       ├── base_step.rb              # 공통 인터페이스
│   │       ├── app_registry_register.rb
│   │       ├── keycloak_client_create.rb # FR-4
│   │       ├── keycloak_client_delete.rb
│   │       ├── langfuse_project_create.rb# FR-5
│   │       ├── langfuse_project_delete.rb
│   │       ├── config_server_apply.rb    # FR-6
│   │       ├── config_server_delete.rb
│   │       └── health_check.rb           # FR-9
│   │
│   └── config_versions/
│       └── rollback_service.rb           # FR-8: 버전 롤백 오케스트레이션
│
├── clients/                              # 외부 API HTTP 클라이언트
│   ├── keycloak_client.rb                # FR-2, FR-4
│   ├── langfuse_client.rb                # FR-1, FR-5
│   └── config_server_client.rb           # FR-6
│
├── jobs/
│   ├── provisioning_job.rb               # FR-7: SolidQueue Job
│   ├── app_registry_webhook_job.rb       # fire-and-forget + async retry
│   └── health_check_job.rb              # FR-9
│
├── channels/
│   └── provisioning_channel.rb           # FR-7.3: WebSocket 스트리밍
│
└── views/
    ├── layouts/
    ├── organizations/                    # FR-1
    ├── projects/                         # FR-3
    ├── provisioning_jobs/                # FR-7.3: 현황 화면
    └── config_versions/                  # FR-8
```

### 3.2 Service 계층 패턴

모든 Service는 동일한 Result 패턴을 따른다:

```ruby
class Projects::CreateService
  def initialize(organization:, params:, current_user:)
    @organization = organization
    @params = params
    @current_user = current_user
  end

  def call
    project = nil

    ActiveRecord::Base.transaction do
      project = @organization.projects.create!(
        name: @params[:name],
        slug: @params[:slug],
        description: @params[:description],
        app_id: generate_app_id,
        status: "provisioning"
      )

      job = project.provisioning_jobs.create!(
        operation: "create",
        status: "pending"
      )

      create_provisioning_steps(job)

      AuditLog.record!(
        organization: @organization,
        project: project,
        user: @current_user,
        action: "project.create"
      )

      ProvisioningJob.perform_later(job.id)
    end

    Result.success(project)
  rescue ActiveRecord::RecordInvalid => e
    Result.failure(e.message)
  end
end
```

### 3.3 Provisioning Step 인터페이스

```ruby
# app/services/provisioning/steps/base_step.rb
class Provisioning::Steps::BaseStep
  attr_reader :project, :step_record

  def initialize(project:, step_record:)
    @project = project
    @step_record = step_record
  end

  # 실행. 성공 시 result_snapshot 반환, 실패 시 예외 발생
  def execute
    raise NotImplementedError
  end

  # 롤백. step_record.result_snapshot 기반으로 생성된 리소스 정리
  def rollback
    raise NotImplementedError
  end

  # 멱등성 확인. 이미 완료된 경우 true 반환하여 skip
  def already_completed?
    false
  end
end
```

---

## 4. API 설계

### 4.1 Console 내부 API (UI용)

#### Organization — FR-1

| Method | Path | 설명 | 권한 |
|--------|------|------|------|
| GET | `/organizations` | 목록 조회 (소속 Org만) | 인증된 사용자 |
| POST | `/organizations` | 생성 | `super_admin` |
| GET | `/organizations/:slug` | 상세 조회 | Org `read`+ |
| PATCH | `/organizations/:slug` | 수정 | Org `admin` |
| DELETE | `/organizations/:slug` | 삭제 | `super_admin` |

#### 멤버 관리 — FR-2

| Method | Path | 설명 | 권한 |
|--------|------|------|------|
| GET | `/organizations/:org_slug/members` | 멤버 목록 | Org `read`+ |
| POST | `/organizations/:org_slug/members` | 멤버 추가 | Org `admin` |
| PATCH | `/organizations/:org_slug/members/:user_sub` | 권한 변경 | Org `admin` |
| DELETE | `/organizations/:org_slug/members/:user_sub` | 멤버 제거 | Org `admin` |
| GET | `/users/search?q=` | 사용자 검색 (Keycloak 프록시) | Org `admin` |

#### Project — FR-3

| Method | Path | 설명 | 권한 |
|--------|------|------|------|
| GET | `/organizations/:org_slug/projects` | 목록 조회 | Org `read`+ |
| POST | `/organizations/:org_slug/projects` | 생성 (→ 프로비저닝 시작) | Org `admin` |
| GET | `/organizations/:org_slug/projects/:slug` | 상세 조회 | Org `read`+ |
| PATCH | `/organizations/:org_slug/projects/:slug` | 수정 | Org `write`+ |
| DELETE | `/organizations/:org_slug/projects/:slug` | 삭제 (→ 프로비저닝 시작) | Org `admin` |

#### 인증 설정 — FR-4

| Method | Path | 설명 | 권한 |
|--------|------|------|------|
| GET | `/organizations/:org_slug/projects/:slug/auth_config` | 인증 설정 조회 | Org `read`+ |
| PATCH | `/organizations/:org_slug/projects/:slug/auth_config` | 인증 방식 변경 | Org `write`+ |

#### LiteLLM Config — FR-6

| Method | Path | 설명 | 권한 |
|--------|------|------|------|
| GET | `/organizations/:org_slug/projects/:slug/litellm_config` | Config 조회 | Org `read`+ |
| PATCH | `/organizations/:org_slug/projects/:slug/litellm_config` | Config 변경 (→ 프로비저닝) | Org `write`+ |

#### 프로비저닝 — FR-7.3

| Method | Path | 설명 | 권한 |
|--------|------|------|------|
| GET | `/provisioning_jobs/:id` | 현황 화면 (실시간 상태) | Org `read`+ |
| POST | `/provisioning_jobs/:id/retry` | 수동 재시도 | Org `admin` |

#### 설정 이력 / 롤백 — FR-8

| Method | Path | 설명 | 권한 |
|--------|------|------|------|
| GET | `/organizations/:org_slug/projects/:slug/config_versions` | 변경 이력 목록 | Org `read`+ |
| GET | `/config_versions/:id` | 변경 상세 + diff | Org `read`+ |
| POST | `/config_versions/:id/rollback` | 해당 버전으로 롤백 | Org `write`+ |

### 4.2 외부 제공 API (Config Server용)

| Method | Path | 설명 | 인증 |
|--------|------|------|------|
| GET | `/api/v1/apps` | App Registry 벌크 조회 | Network Policy (클러스터 내부) |

**응답 형식**:

```json
{
  "apps": [
    {
      "app_id": "app-a3Bf9kR2mX1q",
      "app_name": "aap-acme-chatbot-oidc",
      "org": "acme",
      "project": "chatbot",
      "service": "litellm",
      "permissions": {
        "config_read": true,
        "env_vars_read": true,
        "resolve_secrets": true
      },
      "created_at": "2026-03-01T00:00:00Z"
    }
  ]
}
```

### 4.3 라우팅 구조

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # 인증 콜백
  get  "auth/keycloak/callback", to: "sessions#create"
  delete "auth/logout", to: "sessions#destroy"

  # 사용자 검색
  get "users/search", to: "users#search"

  # Organization & 하위 리소스
  resources :organizations, param: :slug do
    resources :members, param: :user_sub, only: [:index, :create, :update, :destroy]

    resources :projects, param: :slug do
      resource :auth_config, only: [:show, :update]
      resource :litellm_config, only: [:show, :update]
      resources :config_versions, only: [:index]
    end
  end

  # 프로비저닝 (org/project 경로와 독립)
  resources :provisioning_jobs, only: [:show] do
    post :retry, on: :member
  end

  # 설정 버전 (롤백용)
  resources :config_versions, only: [:show] do
    post :rollback, on: :member
  end

  # Config Server용 API
  namespace :api do
    namespace :v1 do
      resources :apps, only: [:index]
    end
  end
end
```

---

## 5. 프로비저닝 파이프라인

### 5.1 Orchestrator 실행 흐름 — FR-7

```
ProvisioningJob (SolidQueue)
  │
  ▼
Orchestrator.run(job)
  │
  ├─ 1. job.status → in_progress
  │
  ├─ 2. step_order 순서대로 단계 그룹 조회
  │     │
  │     ├─ [order=1] app_registry_register
  │     │   └─ StepRunner.execute(step)
  │     │       ├─ already_completed? → skip
  │     │       ├─ step.execute → result_snapshot 저장
  │     │       └─ 실패 시 → retry (max_retries까지)
  │     │
  │     ├─ [order=2] 병렬 실행
  │     │   ├─ keycloak_client_create  ─┐
  │     │   └─ langfuse_project_create ─┤── 모두 완료 대기
  │     │                               │
  │     │   ※ 하나라도 최종 실패 시 전체 rollback
  │     │
  │     ├─ [order=3] config_server_apply
  │     │
  │     └─ [order=4] health_check
  │
  ├─ 3. 전체 성공 → job.status = completed
  │     project.status = active
  │
  └─ 4. 실패 시 →
        ├─ RollbackRunner.run(job)
        │   └─ 완료된 단계를 역순으로 rollback
        │       (result_snapshot 기반)
        │
        ├─ 롤백 성공 → job.status = rolled_back
        └─ 롤백 실패 → job.status = rollback_failed
              (플랫폼 관리자 수동 개입 필요)
```

### 5.2 병렬 단계 실행

동일 `step_order`의 단계들은 Ruby Thread로 병렬 실행한다. SolidQueue Job 내부에서의 병렬 처리이므로 별도 Job 분할은 하지 않는다.

```ruby
class Provisioning::Orchestrator
  def run_step_group(steps)
    if steps.size == 1
      StepRunner.new(steps.first).execute
    else
      # 병렬 실행
      threads = steps.map do |step|
        Thread.new { StepRunner.new(step).execute }
      end
      results = threads.map(&:value)
      # 하나라도 실패 시 예외 발생
      failed = results.select(&:failure?)
      raise StepGroupError, failed if failed.any?
    end
  end
end
```

### 5.3 재시도 정책 — FR-7.2

| 단계 | max_retries | 재시도 간격 | 비고 |
|------|-------------|------------|------|
| `app_registry_register` | 5 | Exponential (2, 4, 8, 16, 32초) | fire-and-forget이지만 프로비저닝 내에서는 확인 |
| `keycloak_client_create` | 3 | Exponential (2, 4, 8초) | |
| `langfuse_project_create` | 3 | Exponential (2, 4, 8초) | |
| `config_server_apply` | 3 | Exponential (2, 4, 8초) | |
| `health_check` | 2 | Fixed (5초) | 검증 실패는 전체 롤백 트리거하지 않음 (경고만) |

### 5.4 ActionCable 상태 브로드캐스트 — FR-7.3

각 단계 상태 변경 시 ActionCable로 Turbo Stream을 브로드캐스트한다:

```ruby
class Provisioning::StepRunner
  def execute
    update_status(:in_progress)
    result = step_instance.execute
    update_status(:completed, result_snapshot: result)
  rescue => e
    if retriable?
      update_status(:retrying)
      retry_later
    else
      update_status(:failed, error_message: e.message)
      raise
    end
  end

  private

  def update_status(status, **attrs)
    @step_record.update!(status: status, **attrs)
    broadcast_step_update
  end

  def broadcast_step_update
    Turbo::StreamsChannel.broadcast_replace_to(
      "provisioning_job_#{@step_record.provisioning_job_id}",
      target: "step_#{@step_record.id}",
      partial: "provisioning_steps/step",
      locals: { step: @step_record }
    )
  end
end
```

### 5.5 크래시 복구 및 멱등성

SolidQueue worker가 프로비저닝 도중 비정상 종료되는 경우를 대비한다.

#### 복구 전략

```
SolidQueue worker 비정상 종료 시:
  │
  ├─ SolidQueue가 job을 자동 재실행 (visibility timeout 이후)
  │
  ▼
Orchestrator.run(job)
  │
  ├─ job.status == "in_progress" 감지 → 재개 모드
  │
  ├─ 각 step 순회:
  │     ├─ step.status == "completed" → skip
  │     ├─ step.status == "in_progress" →
  │     │     └─ step.already_completed? 호출
  │     │         ├─ true  → result_snapshot 복원 후 skip
  │     │         └─ false → 재실행
  │     └─ step.status == "pending" → 정상 실행
  │
  └─ 이후 흐름은 정상 실행과 동일
```

#### Step별 멱등성 체크 (`already_completed?`)

| Step | 멱등성 확인 방법 | 비고 |
|------|-----------------|------|
| `app_registry_register` | Config Server App 목록 조회하여 app_id 존재 여부 확인 | GET API 호출 |
| `keycloak_client_create` | `GET /admin/realms/{realm}/clients?clientId={clientId}`로 Client 존재 확인 | clientId 네이밍 규칙으로 검색 |
| `langfuse_project_create` | `project_auth_config.langfuse_project_id` 존재 + Langfuse API로 확인 | step_record.result_snapshot 활용 |
| `config_server_apply` | Config Server에서 해당 app의 설정 존재 여부 조회 | GET API 호출 |
| `health_check` | 항상 재실행 (멱등) | 검증만 수행하므로 부작용 없음 |

```ruby
# 예시: keycloak_client_create의 멱등성 체크
class Provisioning::Steps::KeycloakClientCreate < BaseStep
  def already_completed?
    return false unless step_record.result_snapshot.present?

    client_id = expected_client_id
    existing = keycloak_client.find_client_by_client_id(client_id)
    if existing
      # result_snapshot 복원 (크래시 전에 저장 못한 경우 대비)
      step_record.update!(
        status: "completed",
        result_snapshot: { keycloak_client_uuid: existing["id"] }
      )
      true
    else
      false
    end
  end
end
```

#### 동시성 제어

```ruby
# app/models/provisioning_job.rb
class ProvisioningJob < ApplicationRecord
  validate :no_active_job_for_project, on: :create

  private

  def no_active_job_for_project
    active_exists = self.class
      .where(project_id: project_id)
      .where(status: %w[pending in_progress retrying rolling_back])
      .exists?

    if active_exists
      errors.add(:base, "이 Project에 진행 중인 프로비저닝이 있습니다")
    end
  end
end
```

#### 병렬 단계 부분 실패 처리

```ruby
class Provisioning::Orchestrator
  def run_step_group(steps)
    return StepRunner.new(steps.first).execute if steps.size == 1

    results = {}
    mutex = Mutex.new
    threads = steps.map do |step|
      Thread.new do
        result = StepRunner.new(step).execute
        mutex.synchronize { results[step.id] = result }
      rescue => e
        mutex.synchronize { results[step.id] = e }
      end
    end
    threads.each(&:join)

    # 실패한 단계가 있으면, 이 그룹에서 성공한 단계만 먼저 롤백
    failed = results.select { |_, v| v.is_a?(Exception) }
    if failed.any?
      succeeded_in_group = results.reject { |_, v| v.is_a?(Exception) }
      rollback_steps(steps.select { |s| succeeded_in_group.key?(s.id) })
      raise StepGroupError.new(failed.values)
    end
  end
end
```

#### SolidQueue Job 설정

```ruby
# app/jobs/provisioning_execute_job.rb
class ProvisioningExecuteJob < ApplicationJob
  queue_as :provisioning
  limits_concurrency to: 1, key: ->(job_id) {
    ProvisioningJob.find(job_id).project_id
  }

  retry_on StandardError, wait: :polynomially_longer, attempts: 2
  discard_on ActiveRecord::RecordNotFound

  def perform(job_id)
    job = ProvisioningJob.find(job_id)
    Provisioning::Orchestrator.new(job).run
  end
end
```

> `limits_concurrency`로 동일 Project에 대한 Job이 SolidQueue 레벨에서도 직렬 실행되도록 보장한다.

### 5.6 Operation별 단계 정의

#### Project Create

| order | 단계 | 외부 API | 롤백 |
|-------|------|---------|------|
| 1 | `app_registry_register` | Config Server webhook | webhook `action: delete` |
| 2 | `keycloak_client_create` | Keycloak Admin API | `DELETE /clients/{uuid}` |
| 2 | `langfuse_project_create` | Langfuse tRPC | `projects.delete` + `projectApiKeys.delete` |
| 3 | `config_server_apply` | Config Server Admin API | `DELETE /admin/changes` |
| 4 | `health_check` | Keycloak + LiteLLM + Langfuse | 없음 |

#### Project Delete

| order | 단계 | 외부 API | 비고 |
|-------|------|---------|------|
| 1 | `config_server_delete` | `DELETE /admin/changes` | 설정/시크릿 일괄 삭제 |
| 1 | `keycloak_client_delete` | `DELETE /clients/{uuid}` | |
| 1 | `langfuse_project_delete` | `projects.delete` | |
| 2 | `app_registry_deregister` | webhook `action: delete` | |

> 삭제 시에는 모든 리소스를 병렬로 제거 후 App Registry 해제.

#### Project Update (설정 변경)

| order | 단계 | 외부 API | 비고 |
|-------|------|---------|------|
| 1 | `config_server_apply` | `POST /admin/changes` | 변경된 설정만 전달 |
| 2 | `health_check` | LiteLLM | |

---

## 6. 실시간 통신 (ActionCable)

### 6.1 채널 설계 — FR-7.3

```ruby
# app/channels/provisioning_channel.rb
class ProvisioningChannel < ApplicationCable::Channel
  def subscribed
    job = ProvisioningJob.find(params[:job_id])
    # 권한 검증: 해당 Project의 Org에 대한 read 이상 권한 필요
    authorize_org!(job.project.organization)

    stream_for job
    # == Turbo::StreamsChannel 대안으로 직접 구현 시 사용
    # stream_from "provisioning_job_#{params[:job_id]}"
  end
end
```

### 6.2 Turbo Stream 연동

```erb
<%# app/views/provisioning_jobs/show.html.erb %>
<%= turbo_stream_from "provisioning_job_#{@job.id}" %>

<div id="provisioning_steps">
  <% @job.provisioning_steps.order(:step_order).each do |step| %>
    <%= render "provisioning_steps/step", step: step %>
  <% end %>
</div>
```

```erb
<%# app/views/provisioning_steps/_step.html.erb %>
<%= turbo_frame_tag dom_id(step) do %>
  <div class="step step--<%= step.status %>">
    <span class="step__icon"><%= step_status_icon(step) %></span>
    <span class="step__name"><%= step_display_name(step) %></span>
    <span class="step__status"><%= step.status.humanize %></span>
    <% if step.error_message.present? %>
      <span class="step__error"><%= step.error_message %></span>
    <% end %>
  </div>
<% end %>
```

### 6.3 Job 완료 시 알림

```ruby
# Orchestrator에서 job 완료 시
def complete_job(job, status)
  job.update!(status: status, completed_at: Time.current)

  Turbo::StreamsChannel.broadcast_replace_to(
    "provisioning_job_#{job.id}",
    target: "job_status",
    partial: "provisioning_jobs/status",
    locals: { job: job }
  )
end
```

---

## 7. 외부 API 클라이언트

### 7.1 공통 패턴

모든 외부 API 클라이언트는 동일한 에러 처리/로깅 패턴을 따른다:

```ruby
# app/clients/base_client.rb
class BaseClient
  include ActiveSupport::Configurable

  class ApiError < StandardError
    attr_reader :status, :body
    def initialize(status:, body:)
      @status, @body = status, body
      super("API error #{status}: #{body}")
    end
  end

  private

  def connection
    @connection ||= Faraday.new(url: base_url) do |f|
      f.request :json
      f.response :json
      f.response :raise_error
      f.adapter Faraday.default_adapter
    end
  end

  def with_error_handling
    yield
  rescue Faraday::Error => e
    raise ApiError.new(
      status: e.response&.dig(:status),
      body: e.response&.dig(:body)
    )
  end
end
```

### 7.2 Keycloak Client — FR-2, FR-4

```ruby
# app/clients/keycloak_client.rb
class KeycloakClient < BaseClient
  # === 그룹 관리 (FR-2) ===
  def create_group(parent_id:, name:)             # Org 생성 시
  def delete_group(group_id:)                      # Org 삭제 시
  def add_user_to_group(user_id:, group_id:)       # 멤버 추가
  def remove_user_from_group(user_id:, group_id:)  # 멤버 제거

  # === 사용자 관리 (FR-2) ===
  def search_users(query:)                         # 멤버 검색
  def create_user(email:)                          # 사전 할당

  # === Client 관리 (FR-4) ===
  def create_oidc_client(client_id:, redirect_uris:)
  def create_saml_client(client_id:, attributes:)
  def create_oauth_client(client_id:, redirect_uris:)
  def delete_client(uuid:)
  def get_client_secret(uuid:)
  def regenerate_client_secret(uuid:)
  def assign_client_scope(client_uuid:, scope_id:)

  private

  def service_account_token
    # aap-console Service Account 토큰 (캐시 + 자동 갱신)
  end
end
```

### 7.3 Langfuse Client — FR-1, FR-5

```ruby
# app/clients/langfuse_client.rb
class LangfuseClient < BaseClient
  # === Organization 관리 (FR-1) ===
  def create_organization(name:)
  def update_organization(id:, name:)
  def delete_organization(id:)

  # === Project 관리 (FR-5) ===
  def create_project(name:, org_id:)
  def delete_project(id:)

  # === API Key 관리 (FR-5) ===
  def create_api_key(project_id:)          # → {public_key, secret_key}
  def delete_api_key(id:)

  private

  def trpc_call(procedure, input = {})
    with_error_handling do
      response = connection.post("/api/trpc/#{procedure}") do |req|
        req.body = { json: input }
        req.headers["Cookie"] = session_cookie
      end
      response.body.dig("result", "data")
    end
  end

  def session_cookie
    # NextAuth 세션 쿠키 (캐시 + 만료 시 자동 갱신)
  end
end
```

### 7.4 Config Server Client — FR-6, FR-8

```ruby
# app/clients/config_server_client.rb
class ConfigServerClient < BaseClient
  # === Admin API (쓰기) ===
  def apply_changes(org:, project:, service:, config:, env_vars:, secrets:)
    # POST /api/v1/admin/changes → {version: "..."}
  end

  def delete_changes(org:, project:, service:)
    # DELETE /api/v1/admin/changes → {version: "..."}
  end

  def revert_changes(org:, project:, service:, target_version:)
    # POST /api/v1/admin/changes/revert → {version: "..."}
  end

  # === App Registry webhook ===
  def notify_app_registry(action:, app_data:)
    # POST /api/v1/admin/app-registry/webhook
  end

  # === 읽기 API (조회) ===
  def get_config(org:, project:, service:)
  def get_secrets_metadata(org:, project:, service:)
  def get_history(org:, project:, service:)

  private

  def with_app_id_header(app_id)
    # X-App-ID 헤더 설정
  end
end
```

---

## 8. 인증/인가

### 8.1 인증 플로우 (Keycloak OIDC) — FR-2

```
브라우저                   Console                    Keycloak
  │                          │                          │
  ├─ GET /organizations ───▶│                          │
  │                          ├─ 세션 없음 감지           │
  │◀── 302 /auth/keycloak ──┤                          │
  │                          │                          │
  ├─ 302 Keycloak login ──────────────────────────────▶│
  │                          │                          │
  │◀── 302 callback + code ────────────────────────────┤
  │                          │                          │
  ├─ GET /auth/keycloak/     │                          │
  │  callback?code=... ─────▶│                          │
  │                          ├─ code → token exchange ─▶│
  │                          │◀── {access_token, ...} ──┤
  │                          │                          │
  │                          ├─ JWT 검증 (groups 포함)   │
  │                          ├─ Rails 세션에 저장        │
  │◀── 302 /organizations ──┤                          │
```

### 8.2 인가 미들웨어 — FR-2

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :set_current_user

  private

  def authenticate_user!
    redirect_to auth_keycloak_path unless session[:user_token].present?
  end

  def set_current_user
    @current_user = CurrentUser.from_token(session[:user_token])
  end

  # 권한 검증 헬퍼
  def authorize_org!(organization, minimum_role: :read)
    unless @current_user.has_org_role?(organization.slug, minimum_role)
      render_forbidden
    end
  end

  def require_super_admin!
    render_forbidden unless @current_user.super_admin?
  end
end
```

### 8.3 CurrentUser 모델

```ruby
# app/models/current_user.rb
class CurrentUser
  attr_reader :sub, :email, :name, :groups

  def self.from_token(token_data)
    new(
      sub: token_data["sub"],
      email: token_data["email"],
      name: token_data["name"],
      groups: token_data["groups"] || []
    )
  end

  def super_admin?
    # Realm Role 확인
    @realm_roles&.include?("super_admin")
  end

  def has_org_role?(org_slug, minimum_role)
    role = org_role(org_slug)
    return false unless role
    ROLE_HIERARCHY[role] >= ROLE_HIERARCHY[minimum_role]
  end

  def org_role(org_slug)
    # groups에서 "/console/orgs/{org_slug}/{role}" 패턴 매칭
    groups.each do |group|
      match = group.match(%r{/console/orgs/#{Regexp.escape(org_slug)}/(\w+)})
      return match[1].to_sym if match
    end
    nil
  end

  ROLE_HIERARCHY = { read: 1, write: 2, admin: 3 }.freeze
end
```

---

## 9. 주요 화면 와이어프레임

### 9.1 Organization 목록 — FR-1

```
┌─────────────────────────────────────────────────────┐
│  AAP Console                          [사용자명 ▼]  │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Organizations                [+ 새 Organization]   │
│                                (super_admin만 표시)  │
│  ┌─────────────────────────────────────────────┐    │
│  │  Acme Corp                    3 Projects    │    │
│  │  AI 서비스 개발팀                     admin  │    │
│  └─────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────┐    │
│  │  Beta Labs                    1 Project     │    │
│  │  R&D 부서                          read     │    │
│  └─────────────────────────────────────────────┘    │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 9.2 Project 상세 — FR-3

```
┌─────────────────────────────────────────────────────┐
│  AAP Console  > Acme Corp > Chatbot                 │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Chatbot                        Status: Active ●    │
│  AI 챗봇 서비스                                      │
│                                                     │
│  App ID: app-a3Bf9kR2mX1q         [설정 변경]       │
│                                    [삭제] (admin)    │
│  ┌─ 인증 설정 (FR-4) ──────────────────────────┐    │
│  │  방식: OIDC                                  │    │
│  │  Client ID: aap-acme-chatbot-oidc           │    │
│  │  [Client Secret 재발급]                      │    │
│  └──────────────────────────────────────────────┘    │
│                                                     │
│  ┌─ LiteLLM Config (FR-6) ─────────────────────┐    │
│  │  모델: azure-gpt4, claude-sonnet            │    │
│  │  가드레일: content-filter (활성)              │    │
│  │  S3 경로: s3://bucket/acme/chatbot/          │    │
│  │  S3 Retention: 90일                          │    │
│  │  [설정 편집]                                  │    │
│  └──────────────────────────────────────────────┘    │
│                                                     │
│  ┌─ 변경 이력 (FR-8) ──────────────────────────┐    │
│  │  2026-03-11 14:30  모델 목록 변경  user@...  │    │
│  │  2026-03-10 10:00  최초 생성      user@...   │    │
│  │  [전체 이력 보기]                             │    │
│  └──────────────────────────────────────────────┘    │
│                                                     │
│  ┌─ 프로비저닝 이력 (FR-7.3) ──────────────────┐    │
│  │  2026-03-10 10:00  create  completed  [상세] │    │
│  └──────────────────────────────────────────────┘    │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 9.3 프로비저닝 현황 화면 — FR-7.3

```
┌─────────────────────────────────────────────────────┐
│  AAP Console  > Acme Corp > Chatbot > 프로비저닝    │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Project 생성 프로비저닝          Status: 진행중 ⟳   │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │  ✓  Step 1. App Registry 등록     완료 0.3s  │   │
│  ├──────────────────────────────────────────────┤   │
│  │  ✓  Step 2a. 인증 리소스 생성     완료 1.2s  │   │
│  ├──────────────────────────────────────────────┤   │
│  │  ⟳ Step 2b. Langfuse 리소스 생성  진행중...  │   │
│  ├──────────────────────────────────────────────┤   │
│  │  ○  Step 3. Config 반영           대기       │   │
│  ├──────────────────────────────────────────────┤   │
│  │  ○  Step 4. Health Check          대기       │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  시작: 2026-03-11 14:30:00                          │
│  경과: 3.5초                                        │
│                                                     │
│  ─── 실패 시 ───                                    │
│  ┌──────────────────────────────────────────────┐   │
│  │  ✗  Step 2b. Langfuse 리소스 생성   실패     │   │
│  │     Error: Connection refused                │   │
│  │     재시도: 3/3 회 소진                       │   │
│  │                                              │   │
│  │  롤백 진행중...                               │   │
│  │  ✓  Step 2a 롤백: Keycloak Client 삭제       │   │
│  │  ✓  Step 1 롤백: App Registry 해제           │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  [수동 재시도]  [Project 목록으로]                    │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 9.4 멤버 관리 — FR-2

```
┌─────────────────────────────────────────────────────┐
│  AAP Console  > Acme Corp > 멤버 관리               │
├─────────────────────────────────────────────────────┤
│                                                     │
│  멤버 목록                          [+ 멤버 추가]    │
│                                                     │
│  ┌────────────────────────────────────────────────┐ │
│  │  이메일               이름         권한   액션  │ │
│  ├────────────────────────────────────────────────┤ │
│  │  admin@acme.com      김관리자     admin  [▼]   │ │
│  │  dev1@acme.com       이개발       write  [▼]   │ │
│  │  viewer@acme.com     박조회       read   [▼]   │ │
│  │  new@acme.com        (미로그인)   read   [▼]   │ │
│  └────────────────────────────────────────────────┘ │
│                                                     │
│  ─── 멤버 추가 모달 ───                              │
│  ┌────────────────────────────────────────────────┐ │
│  │  사용자 검색: [user@exam     ]  🔍             │ │
│  │                                                │ │
│  │  검색 결과:                                     │ │
│  │    ○ user@example.com  홍길동                   │ │
│  │    ○ user2@example.com 김철수                   │ │
│  │                                                │ │
│  │  이메일 직접 입력 (미등록 사용자 사전 할당):      │ │
│  │  [new-user@company.com]                        │ │
│  │                                                │ │
│  │  권한: [admin ▼]                               │ │
│  │                                                │ │
│  │  [추가]  [취소]                                 │ │
│  └────────────────────────────────────────────────┘ │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## 10. 설계 결정

### 10.1 프로비저닝 오케스트레이션: 직접 구현 vs 외부 라이브러리

> 상세 비교는 [ADR-001](./adr-001-provisioning-orchestration.md) 참조.

| 방식 | 장점 | 단점 | 결정 |
|------|------|------|------|
| **직접 구현 (Rails Saga)** | Rails 스택 자연 통합. 완전한 제어. 의존성 최소 | 크래시 복구, 엣지 케이스 직접 처리 (~1,000줄) | **채택** |
| Terraform + Custom Provider | 선언적. Keycloak Provider 있음 | Langfuse/Config Server Provider를 Go로 작성 필요. CLI 통합 어색. State에 Secret 평문 | 미채택 |
| Dynflow | Foreman 프로덕션 검증. 병렬/상태/크래시 복구 내장 | 보상 트랜잭션은 여전히 직접 구현. 문서 부족. 4~5단계에 과도 | 미채택 |
| Temporal.io | 모든 요구사항 네이티브 충족 | Temporal Server 별도 운영 필요. 인프라 복잡도 대폭 증가 | 미채택 |

### 10.2 프로비저닝 병렬 단계: Thread vs 별도 Job

| 방식 | 장점 | 단점 | 결정 |
|------|------|------|------|
| **Thread (Job 내 병렬)** | 단순. 완료 대기 용이. 상태 일관성 보장 | Thread 안전성 주의 필요 | **채택** |
| 별도 Job (Fan-out) | 각 단계 독립 재시도 | 완료 동기화 복잡. 상태 관리 어려움 | 미채택 |

Thread 수가 2~3개로 적고, 각 Thread는 독립적인 외부 API를 호출하므로 Thread 안전성 이슈가 최소화된다.

### 10.3 RBAC: DB 테이블 vs Keycloak SSOT

| 방식 | 장점 | 단점 | 결정 |
|------|------|------|------|
| **Keycloak SSOT** | 권한 데이터 단일 원천. Console DB 동기화 불필요 | Keycloak 장애 시 멤버 관리 불가 | **채택** |
| Console DB + 동기화 | 독립적 읽기 가능 | 이중 관리. 동기화 복잡도 | 미채택 |

JWT 토큰에 `groups` 클레임이 포함되므로 인가 시 DB 조회가 불필요하다. 멤버 관리 시에만 Keycloak Admin API를 호출한다.

### 10.4 설정 스냅샷: Config Server 조회 vs Console DB 저장

| 방식 | 장점 | 단점 | 결정 |
|------|------|------|------|
| **Console DB 저장** | 롤백 시 Config Server 이력 API 불필요. 독립적 | 스냅샷 데이터 크기 | **채택** |
| Config Server 조회 | 중복 저장 없음 | Config Server 의존성 증가. 이력 API 필요 | 미채택 |

Keycloak/Langfuse 설정은 Config Server에 이력이 없으므로 Console DB에 스냅샷을 저장해야 한다. 일관성을 위해 Config Server 설정도 함께 스냅샷한다.

### 10.5 Health Check: 동기 vs 비동기

| 방식 | 장점 | 단점 | 결정 |
|------|------|------|------|
| **프로비저닝 내 동기** | 생성 완료 전 검증 보장 | 프로비저닝 시간 증가 | **채택** (기본) |
| 별도 비동기 | 프로비저닝 빠름 | 검증 실패 시 이미 active 상태 | 선택적 사용 |

Health Check 실패는 프로비저닝 전체를 롤백하지 않고 **경고(warning)** 로 처리한다. 프로비저닝은 `completed`로 마킹하되, 현황 화면에 경고를 표시한다.

---

## 11. FR 추적 매트릭스

| FR | 설명 | DB 테이블 | Controller | Service | Client | Job/Channel |
|----|------|-----------|------------|---------|--------|-------------|
| **FR-1** | Organization CRUD | `organizations` | `OrganizationsController` | `Organizations::*Service` | `KeycloakClient` (그룹), `LangfuseClient` (Org) | — |
| **FR-2** | RBAC | — (Keycloak SSOT) | `MembersController`, `ApplicationController` (인가) | — | `KeycloakClient` (그룹/사용자) | — |
| **FR-3** | Project CRUD | `projects` | `ProjectsController` | `Projects::*Service` | — | `ProvisioningJob` |
| **FR-4** | 인증 체계 자동 구성 | `project_auth_configs` | `AuthConfigsController` | `Steps::KeycloakClientCreate` | `KeycloakClient` (Client) | — |
| **FR-5** | Langfuse 프로젝트/Key | — (Console 미저장) | — | `Steps::LangfuseProjectCreate` | `LangfuseClient` | — |
| **FR-6** | LiteLLM Config | — (Config Server 위임) | `LitellmConfigsController` | `Steps::ConfigServerApply` | `ConfigServerClient` | — |
| **FR-7.1** | 상태 머신 | `provisioning_jobs` | — | `Provisioning::Orchestrator` | — | `ProvisioningJob` |
| **FR-7.2** | 실행/재시도/롤백 | `provisioning_steps` | — | `StepRunner`, `RollbackRunner` | — | `ProvisioningJob` |
| **FR-7.3** | 현황 화면 | — (jobs+steps 참조) | `ProvisioningJobsController` | — | — | `ProvisioningChannel` |
| **FR-8** | 이력/롤백 | `config_versions`, `audit_logs` | `ConfigVersionsController` | `ConfigVersions::RollbackService` | `ConfigServerClient` (revert) | — |
| **FR-9** | Health Check | — (steps에 기록) | — | `Steps::HealthCheck` | 각 Client (상태 확인) | `HealthCheckJob` |
