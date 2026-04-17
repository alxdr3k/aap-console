# AAP Console — High-Level Design (HLD)

> **Version**: 1.12
> **Date**: 2026-04-17
> **Status**: Draft
> **References**: [PRD](./PRD.md) · [UI Spec](./ui-spec.md)

---

## 목차

1. 시스템 개요
2. 데이터베이스 스키마
3. 컴포넌트 아키텍처
4. API 설계
5. 프로비저닝 파이프라인
6. 실시간 통신 (ActionCable)
7. 외부 API 클라이언트
8. 인증/인가
9. UI 설계
10. 설계 결정
11. 의존성
12. FR 추적 매트릭스

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
│ langfuse_org_id  │   │   │ description      │
│ created_at       │   │   │ app_id      UNQ  │
│ updated_at       │   │   │ status           │  (provisioning/active/
└──────────────────┘   │   │ created_at       │   update_pending/deleting/deleted/
                       │   │                  │   provision_failed)
                       │   │ updated_at       │
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
│ action           │  │ keycloak_client_id│  │ status            │
│ resource_type    │  │ keycloak_client_  │  │ started_at        │
│ resource_id      │  │   uuid            │  │ completed_at      │
│ details (JSON)   │  │ created_at        │  │ error_message     │
│ created_at       │  │ updated_at        │  │ created_at        │
└──────────────────┘  └───────────────────┘  │ updated_at        │
                                             └────┬──────────────┘
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
                   │ completed_at     │   │ snapshot (JSON)   │
                   │ error_message    │   │ created_at        │
                   │ retry_count      │   └───────────────────┘
                   │ max_retries      │
                   │ result_snapshot  │
                   │   (JSON)         │
                   │ created_at       │
                   │ updated_at       │
                   └──────────────────┘
┌──────────────────────┐
│  org_memberships     │
├──────────────────────┤
│ id              PK   │
│ organization_id FK   │───▶ organizations
│ user_sub             │
│ role                 │
│ invited_at           │
│ joined_at            │
│ created_at           │
│ updated_at           │
└──────────┬───────────┘
           │
     ┌─────┘
     │
┌────▼─────────────────┐
│ project_permissions  │
├──────────────────────┤
│ id              PK   │
│ org_membership_id FK │───▶ org_memberships
│ project_id       FK  │───▶ projects
│ role                 │
│ created_at           │
│ updated_at           │
└──────────────────────┘
```

### 2.2 테이블 상세

#### organizations — FR-1

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | integer PK | |
| `name` | string NOT NULL | 조직 표시명 |
| `slug` | string NOT NULL UNQ | URL-safe 식별자 |
| `description` | text | 조직 설명 |
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
| `status` | string NOT NULL DEFAULT 'provisioning' | `provisioning` / `active` / `update_pending` / `deleting` / `deleted` / `provision_failed` |
| `created_at` | datetime | |
| `updated_at` | datetime | |

**app_id 생성 규칙**: `app-{SecureRandom.alphanumeric(12)}` (예: `app-a3Bf9kR2mX1q`). 충돌 시 재생성.

**status 전이 규칙**:

```
(새 레코드)
    │
    ▼
provisioning ── create 성공 ──▶ active
    │                            │
    │                            ├── update 시작 ──▶ update_pending
    │                            │                       │
    │                            │                       ├── update 성공 ──▶ active
    │                            │                       └── update 실패 + 롤백 성공 ──▶ active
    │                            │
    │                            └── delete 시작 ──▶ deleting ──▶ deleted
    │
    └── create 실패 ──▶ provision_failed
                            │
                            ├── 수동 재시도 ──▶ provisioning
                            └── 관리자 삭제 ──▶ deleting ──▶ deleted
```

- `update_pending` 은 사용자에게 "편집 진행 중" 을 알리는 과도 상태. 진입 시 기존 설정은 그대로 서비스 지속, 완료 후 `active` 복귀
- `deleted` 는 soft-delete. 레코드는 유지되며 `app_id`/`slug` 재사용 금지 (FK 및 감사 로그 보존용)
- `provision_failed` → `provisioning` 전이는 수동 재시도 시에만 발생 (FR-7.3)

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

#### org_memberships — FR-2

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | integer PK | |
| `organization_id` | integer FK NOT NULL | 소속 Organization |
| `user_sub` | string NOT NULL | Keycloak subject (사용자 고유 ID). 이메일/이름은 저장하지 않음 |
| `role` | string NOT NULL DEFAULT 'read' | `admin` / `write` / `read` |
| `invited_at` | datetime | 초대 시각 (미등록 사용자 사전 할당 시) |
| `joined_at` | datetime | 최초 로그인으로 멤버십 활성화된 시각 |
| `created_at` | datetime | |
| `updated_at` | datetime | |

> **유니크 제약**: `(organization_id, user_sub)`. 한 사용자는 한 Org에 하나의 멤버십만 가짐.

**역할 계층**:

| 역할 | 설명 | 포함 권한 |
|------|------|----------|
| `read` | 조회 전용 | Org/Project 조회, 설정 조회, 이력 조회 |
| `write` | 설정 변경 | `read` + Project 설정 변경, Config 수정, 롤백 |
| `admin` | Org 관리 | `write` + Project 생성/삭제, 멤버 관리, 모든 Project 접근 |

#### project_permissions — FR-2

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | integer PK | |
| `org_membership_id` | integer FK NOT NULL | 소속 Org 멤버십 |
| `project_id` | integer FK NOT NULL | 대상 Project |
| `role` | string NOT NULL DEFAULT 'read' | `write` / `read` |
| `created_at` | datetime | |
| `updated_at` | datetime | |

> **유니크 제약**: `(org_membership_id, project_id)`. 한 멤버십당 한 Project에 하나의 권한만.
> **Org admin은 이 테이블에 레코드 불필요** — admin 역할 자체가 Org 내 모든 Project에 대한 암묵적 접근 권한을 부여하므로 `project_permissions`는 `read`/`write` 사용자 전용.

**권한 결정 규칙**:

```
1. super_admin (Keycloak realm role) → 전체 접근
2. org_membership.role == admin → 해당 Org의 모든 Project 접근 (admin)
3. project_permissions 레코드 있음 → 해당 role로 접근
4. project_permissions 레코드 없음 → 접근 불가
```

#### provisioning_jobs — FR-7.1

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | integer PK | |
| `project_id` | integer FK NOT NULL | 대상 Project |
| `operation` | string NOT NULL | `create` / `update` / `delete` |
| `status` | string NOT NULL DEFAULT 'pending' | 아래 상태 값 참조 (ActiveRecord `enum`으로 관리) |
| `started_at` | datetime | 실행 시작 시각 |
| `completed_at` | datetime | 완료/실패 시각 |
| `error_message` | text | 최종 에러 메시지 |
| `warnings` | JSON | Health Check 등 비차단 실패 목록 (예: `[{step: "health_check", message: "..."}]`) |
| `created_at` | datetime | |
| `updated_at` | datetime | |

**상태 값**: `pending` → `in_progress` → `completed` / `completed_with_warnings` / `failed` → `retrying` → `in_progress` (재시도 루프) / `rolling_back` → `rolled_back` / `rollback_failed`

> Rails 구현: `enum status: { pending: 0, in_progress: 1, completed: 2, completed_with_warnings: 3, failed: 4, retrying: 5, rolling_back: 6, rolled_back: 7, rollback_failed: 8 }` (정수 컬럼 권장). 타입 안전한 전이 및 scope(`ProvisioningJob.in_progress`) 자동 제공.

**동시성 제어**: 동일 `project_id`에 대해 `pending` / `in_progress` / `retrying` / `rolling_back` 상태의 job이 있으면 새 job 생성을 거부한다 (앱 레벨 검증 + `(project_id)` 부분 인덱스로 활성 Job 유일성 보장). 상세는 §5.5 참조.

**retention**: 180일 보관 후 일일 배치 Job(`ProvisioningJobsCleanupJob`)이 `completed` / `rolled_back` / `completed_with_warnings` 레코드를 아카이빙(S3)하고 삭제. `failed` / `rollback_failed`는 관리자 확인 전까지 보존. `audit_logs`(365일)보다 짧은 이유는 프로비저닝 로그가 감사 증적이 아닌 운영 진단 목적이며, 상태 변경 이벤트 자체는 `audit_logs`에 별도로 기록되기 때문이다.

#### provisioning_steps — FR-7.2

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | integer PK | |
| `provisioning_job_id` | integer FK NOT NULL | 소속 Job |
| `name` | string NOT NULL | 단계 식별자 (예: `keycloak_client_create`) |
| `step_order` | integer NOT NULL | 실행 순서 (병렬 단계는 동일 order) |
| `status` | integer NOT NULL DEFAULT 0 | ActiveRecord `enum`: `pending` / `in_progress` / `completed` / `failed` / `retrying` / `skipped` / `rolled_back` / `rollback_failed` |
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

> `step_order=2`인 단계들은 **병렬 실행** 가능. 위 표는 Create 기준 예시이며, Update/Delete의 단계 구성은 §5.6 참조.

#### config_versions — FR-8

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | integer PK | |
| `project_id` | integer FK NOT NULL | 대상 Project |
| `provisioning_job_id` | integer FK | 연관 프로비저닝 job (있는 경우) |
| `version_id` | string NOT NULL | Config Server가 반환한 버전 식별자 |
| `change_type` | string NOT NULL | `create` / `update` / `delete` / `rollback` |
| `change_summary` | text | 변경 요약 (예: "모델 목록 변경: +claude-sonnet, -gpt-3.5") |
| `changed_by_sub` | string NOT NULL | 변경 사용자 Keycloak subject. 이름/이메일은 Keycloak API로 조회 |
| `snapshot` | JSON | 변경 시점의 설정 스냅샷. Keycloak/Langfuse 롤백 시 사용 |
| `created_at` | datetime | |

**retention**: `config_versions`는 운영상 롤백 이력이므로 기본적으로 **영구 보존**한다. Project 가 삭제되면(`projects.status = deleted`) 연관 레코드도 cascade 삭제한다. 저장 공간 문제가 되면 Project당 최근 100개 + 최근 1년 이내 레코드만 유지하는 정책으로 전환한다 (`ConfigVersionsPruneJob`).

#### audit_logs — FR-8

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | integer PK | |
| `organization_id` | integer FK | |
| `project_id` | integer FK | |
| `user_sub` | string NOT NULL | Keycloak subject. 이름/이메일은 Keycloak API로 조회 |
| `action` | string NOT NULL | `org.create`, `project.create`, `member.add`, `config.update` 등 |
| `resource_type` | string NOT NULL | `Organization`, `Project`, `Member` 등 |
| `resource_id` | string | 대상 리소스 ID |
| `details` | JSON | 액션별 추가 정보 |
| `created_at` | datetime | |

**retention**: 감사 로그는 **1년(365일)** 보관 후 일일 배치(`AuditLogsArchiveJob`)가 S3(Litestream 백업 버킷과 분리된 archive prefix)로 JSONL 형식 아카이빙 후 레코드 삭제. 규제 요구사항이 없으므로 S3 아카이브는 Lifecycle Policy로 3년 후 Glacier, 7년 후 삭제. Project/Organization 삭제 시에도 감사 로그는 유지(참조 FK를 NULL 허용으로 설계).

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

# org_memberships
add_index :org_memberships, [:organization_id, :user_sub], unique: true
add_index :org_memberships, :user_sub

# project_permissions
add_index :project_permissions, [:org_membership_id, :project_id], unique: true
add_index :project_permissions, :project_id

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
│   ├── application_controller.rb         # 세션 인증, RBAC 인가 (FR-2)
│   ├── organizations_controller.rb       # FR-1
│   ├── members_controller.rb             # FR-2
│   ├── projects_controller.rb            # FR-3
│   ├── auth_configs_controller.rb        # FR-4
│   ├── litellm_configs_controller.rb     # FR-6
│   ├── provisioning_jobs_controller.rb   # FR-7.3
│   ├── config_versions_controller.rb     # FR-8
│   ├── playgrounds_controller.rb        # FR-10: LiteLLM 프록시 + SSE
│   └── api/
│       └── v1/
│           └── apps_controller.rb        # Config Server용 App Registry API
│
├── models/
│   ├── organization.rb                   # FR-1
│   ├── project.rb                        # FR-3
│   ├── org_membership.rb                 # FR-2: Org 역할 관리
│   ├── project_permission.rb             # FR-2: Project ACL
│   ├── current_user.rb                   # FR-2: 세션 + DB 기반 인가 모델
│   ├── project_auth_config.rb            # FR-4
│   ├── provisioning_job.rb               # FR-7.1 (상태 머신)
│   ├── provisioning_step.rb              # FR-7.2
│   ├── config_version.rb                 # FR-8
│   └── audit_log.rb                      # FR-8
│
├── services/
│   ├── organizations/
│   │   ├── create_service.rb             # FR-1: Org 생성 + Langfuse Org + 초기 멤버십
│   │   └── destroy_service.rb            # FR-1: 하위 Project 전체 삭제 + 멤버십 정리 후 Org 삭제
│   │
│   ├── projects/
│   │   ├── create_service.rb             # FR-3: DB 생성 + 프로비저닝 job enqueue
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
├── clients/                              # 외부 API HTTP 클라이언트 (비즈니스 로직 없는 순수 HTTP 통신 계층이므로 services/와 분리)
│   ├── keycloak_client.rb                # FR-2, FR-4
│   ├── langfuse_client.rb                # FR-1, FR-5
│   └── config_server_client.rb           # FR-6
│
├── jobs/
│   ├── provisioning_execute_job.rb        # FR-7: SolidQueue Job
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
    ├── config_versions/                  # FR-8
    └── playgrounds/                      # FR-10: AI Chat UI
```

> **Zeitwerk 오토로딩**: 디렉토리명과 상수명은 Rails 8 기본 Zeitwerk 규약을 따른다. 즉 `app/clients/keycloak_client.rb` → `KeycloakClient` (최상위), `app/services/provisioning/orchestrator.rb` → `Provisioning::Orchestrator`. `app/clients`는 Rails 기본 autoload_paths에 포함되지 않으므로 `config/application.rb`에서 `config.autoload_lib(ignore: %w[assets tasks])` 또는 `config.autoload_paths << Rails.root.join("app/clients")` 를 명시한다. `app/services/provisioning/steps/*.rb`는 `Provisioning::Steps::*` 네임스페이스로 자동 매핑된다.

### 3.2 컴포넌트 역할

| 컴포넌트 | 역할 | 하지 않는 것 |
|----------|------|-------------|
| **Controller** | 인증/인가 검증, 파라미터 수집, Service 호출, 뷰 렌더링 | 비즈니스 로직, 외부 API 직접 호출 |
| **Service** | 비즈니스 로직 오케스트레이션, DB 트랜잭션, Job enqueue | HTTP 요청/응답 처리, 뷰 렌더링 |
| **Client** | 외부 API HTTP 호출, 인증 토큰 관리, 에러 변환 | 비즈니스 판단, DB 접근 |
| **Model** | 데이터 검증, 연관관계, 쿼리 스코프 | 외부 API 호출, 복잡한 비즈니스 로직 |
| **Job (SolidQueue)** | 비동기 작업 실행, 재시도, 동시성 제어 | 비즈니스 판단 (Orchestrator에 위임) |
| **Channel (ActionCable)** | WebSocket 구독 관리, 실시간 브로드캐스트 | DB 쓰기, 비즈니스 로직 |
| **Provisioning Step** | 단일 외부 API 호출 + 롤백 구현, 멱등성 보장 | 다른 Step 호출, 실행 순서 결정 |
| **Orchestrator** | Step 실행 순서 관리, 상태 머신 전이, 롤백 트리거 | 외부 API 직접 호출 (Step에 위임) |

### 3.3 Service 계층 패턴

Service는 **외부 API 호출이나 다중 리소스 오케스트레이션이 필요한 경우에만** 도입한다. 단순 CRUD(예: Org/Project의 단일 필드 수정)는 Controller에서 Model을 직접 호출한다.

모든 Service는 동일한 패턴을 따른다:

- **초기화**: 대상 리소스, 파라미터, `current_user`를 주입받는다
- **실행** (`call`): 단일 DB 트랜잭션 내에서 레코드 생성 → 프로비저닝 Job enqueue → 감사 로그 기록
- **결과**: `Result.success(data)` 또는 `Result.failure(message)` 반환

예시: `Projects::CreateService#call` → 트랜잭션 내에서 Project 레코드 생성(status: `provisioning`) + ProvisioningJob 생성 + AuditLog 기록 + Job enqueue

#### 트랜잭션 + enqueue 순서 정책

SolidQueue는 Rails 주 DB(SQLite)에 Job을 저장하므로, 트랜잭션 **내부**에서 `perform_later`를 호출하면 다음 두 증상이 발생할 수 있다.

1. 트랜잭션이 rollback되어도 enqueue된 Job은 남아 **존재하지 않는 레코드를 참조**하며 실행됨
2. Worker가 트랜잭션 커밋보다 먼저 Job을 picking하여 **레코드 not-found** 오류 발생

이를 방지하기 위해 Rails 7.2+의 `config.active_job.enqueue_after_transaction_commit = :always`를 전역 기본값으로 설정한다. 이 설정 하에서는 ActiveJob이 **현재 트랜잭션 커밋 직후**에만 enqueue를 실제 발행한다.

| 설정 | 값 | 근거 |
|------|---|------|
| `config.active_job.enqueue_after_transaction_commit` | `:always` | 트랜잭션 롤백 시 Job 유령 방지, 커밋 전 Worker picking 방지 |
| 트랜잭션 블록 내 `perform_later` 호출 | 허용 | 위 설정이 커밋 지연을 자동 처리 |
| 트랜잭션 밖 `perform_later` | 즉시 enqueue | SolidQueue에 바로 삽입 |

**예외**: 트랜잭션 커밋과 무관하게 즉시 enqueue해야 하는 Job(예: 감사성 알림)은 호출부에서 `self.class.set(...).perform_later`를 트랜잭션 외부에서 실행한다. 예외가 빈번해지면 Job 단위로 `self.enqueue_after_transaction_commit = :never`로 override.

**브로드캐스트 순서**: §6.4의 ActionCable 브로드캐스트 규칙과 동일 원리 — DB 상태에 의존하는 외부 부수효과는 **항상 트랜잭션 커밋 이후**에 발행한다.

### 3.4 Provisioning Step 인터페이스

모든 프로비저닝 단계는 `Provisioning::Steps::BaseStep`을 상속하며 3개의 메서드를 구현한다:

| 메서드 | 역할 | 반환 |
|--------|------|------|
| `execute` | 외부 API 호출로 리소스 생성. 성공 시 `result_snapshot` (Hash) 반환, 실패 시 예외 | Hash (생성된 리소스 정보) |
| `rollback` | `step_record.result_snapshot` 기반으로 생성된 리소스 정리 | — |
| `already_completed?` | 멱등성 체크. 이미 리소스가 존재하면 `true` → skip | Boolean |

`BaseStep`은 `project`와 `step_record`를 주입받아 각 단계에서 공통으로 사용한다.

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
| GET | `/organizations/:org_slug/projects/:slug` | 상세 조회 | Project `read`+ |
| PATCH | `/organizations/:org_slug/projects/:slug` | 수정 | Project `write`+ |
| DELETE | `/organizations/:org_slug/projects/:slug` | 삭제 (→ 프로비저닝 시작) | Org `admin` |

#### 인증 설정 — FR-4

| Method | Path | 설명 | 권한 |
|--------|------|------|------|
| GET | `/organizations/:org_slug/projects/:slug/auth_config` | 인증 설정 조회 | Project `read`+ |
| PATCH | `/organizations/:org_slug/projects/:slug/auth_config` | 인증 방식 변경 | Project `write`+ |

#### LiteLLM Config — FR-6

| Method | Path | 설명 | 권한 |
|--------|------|------|------|
| GET | `/organizations/:org_slug/projects/:slug/litellm_config` | Config 조회 | Project `read`+ |
| PATCH | `/organizations/:org_slug/projects/:slug/litellm_config` | Config 변경 (→ 프로비저닝) | Project `write`+ |

#### 프로비저닝 — FR-7.3

| Method | Path | 설명 | 권한 |
|--------|------|------|------|
| GET | `/provisioning_jobs/:id` | 현황 화면 (실시간 상태) | Project `read`+ |
| POST | `/provisioning_jobs/:id/retry` | 수동 재시도 | Project `write`+ |

#### 설정 이력 / 롤백 — FR-8

| Method | Path | 설명 | 권한 |
|--------|------|------|------|
| GET | `/organizations/:org_slug/projects/:slug/config_versions` | 변경 이력 목록 | Project `read`+ |
| GET | `/config_versions/:id` | 변경 상세 + diff | Project `read`+ |
| POST | `/config_versions/:id/rollback` | 해당 버전으로 롤백 | Project `write`+ |

#### Playground — FR-10

| Method | Path | 설명 | 권한 |
|--------|------|------|------|
| GET | `/organizations/:org_slug/projects/:slug/playground` | Playground 화면 | Project `read`+ |
| POST | `/organizations/:org_slug/projects/:slug/playground/chat` | LiteLLM 프록시 (SSE 스트리밍) | Project `read`+ |

> **SSE 스트리밍 제약**:
> - Rack Hijacking(`ActionController::Live`)으로 SSE 프록시를 구현한다. 단일 요청이 Puma worker thread 하나를 점유하므로 `max_duration: 120s`를 강제하여 장시간 스트림이 worker pool을 고갈시키지 못하도록 한다.
> - `max_tokens`는 서버에서 상한 4096로 클램핑 (UI 값이 이를 초과하면 경고).
> - 클라이언트 disconnect 감지 시 LiteLLM 업스트림 요청도 즉시 취소 (`Faraday` 의 `on_complete` + `io.closed?` 체크).
> - 동시 SSE 연결 수는 Project당 3개로 제한 (`Rails.cache` 카운터). 초과 시 429 반환.

### 4.2 외부 제공 API (Config Server용)

| Method | Path | 설명 | 인증 |
|--------|------|------|------|
| GET | `/api/v1/apps?all=true` | App Registry 벌크 조회 | `Authorization: Bearer <CONSOLE_INBOUND_API_KEY>` + K8s Network Policy |

> **인증**: Network Policy는 네임스페이스 내 다른 Pod의 오남용을 막지 못하므로, Console이 사전 발급한 Bearer 토큰을 Config Server 환경변수에 주입하고 Console은 요청 헤더로 검증한다. 토큰은 `CONSOLE_INBOUND_API_KEY`로 관리하며, Config Server Admin API 호출에 사용하는 `CONFIG_SERVER_API_KEY`와 대칭을 이룬다.

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

> **`app_name` 필드**: Keycloak Client `clientId`(FR-4 네이밍 규칙 `aap-{org-id}-{project-id}-{protocol}`)와 동일한 값이다. Config Server가 인증 주체 식별에 사용한다. PAK 인증 Project는 Keycloak Client가 없으므로 `app_name`을 `null`로 반환한다.

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
      resource :playground, only: [:show] do
        post :chat, on: :member
      end
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
  │     ※ health_check 만 실패한 경우: job.status = completed_with_warnings
  │       project.status = active, job.warnings에 실패 내역 기록
  │
  └─ 4. 실패 시 →
        ├─ RollbackRunner.run(job)
        │   └─ 완료된 단계를 역순으로 rollback
        │       (result_snapshot 기반)
        │
        ├─ 롤백 성공 → job.status = rolled_back
        │     create 작업인 경우: project.status = provision_failed
        └─ 롤백 실패 → job.status = rollback_failed
              create 작업인 경우: project.status = provision_failed
              (플랫폼 관리자 수동 개입 필요)
```

### 5.2 병렬 단계 실행

동일 `step_order`의 단계들은 Ruby Thread로 병렬 실행한다. SolidQueue Job 내부에서의 병렬 처리이므로 별도 Job 분할은 하지 않는다.

- `Orchestrator#run_step_group(steps)`: 단계가 1개면 직접 실행, 복수면 Thread로 병렬 실행 후 전체 완료 대기
- 병렬 단계 중 하나라도 실패하면 `StepGroupError` 발생 → 전체 롤백 트리거

**Thread 안전성 제약**:

| 항목 | 제약 |
|------|------|
| DB 연결 | 각 Thread에서 `ActiveRecord::Base.connection_pool.with_connection { ... }` 블록으로 감싸서 사용. 병렬 Thread 수 ≤ `DB_POOL_SIZE - 2` (Orchestrator/ActionCable 확보분) |
| 외부 API 클라이언트 | Thread 간 공유 금지. Thread-local 인스턴스 또는 Mutex 보호 (§7.3 LangfuseClient 참조) |
| `ActiveSupport::CurrentAttributes` | Thread-local 저장이므로 병렬 Thread에서 읽으면 비어 있음. 필요한 값은 Thread 시작 전에 로컬 변수로 캡처하여 전달 |
| 테스트 | WebMock의 Thread-safety 모드 활성화 필요 (`WebMock::Config.instance.allow_localhost = false` + `WebMock.allow_net_connect!(net_http_connect_on_start: true)` 금지). `RSpec.configure { |c| c.threadsafe = true }` |

### 5.3 재시도 정책 — FR-7.2

| 단계 | max_retries | 재시도 간격 | 비고 |
|------|-------------|------------|------|
| `app_registry_register` | 5 | Exponential (2, 4, 8, 16, 32초) | fire-and-forget이지만 프로비저닝 내에서는 확인 |
| `keycloak_client_create` | 3 | Exponential (2, 4, 8초) | |
| `langfuse_project_create` | 3 | Exponential (2, 4, 8초) | |
| `config_server_apply` | 3 | Exponential (2, 4, 8초) | |
| `health_check` | 2 | Fixed (5초) | 검증 실패는 전체 롤백 트리거하지 않음 (경고만) |

**재시도 구현 전략**:

- **Inline sleep (≤ 8초)**: Thread.sleep으로 즉시 재시도. Worker 점유 허용
- **Scheduled retry (> 8초)**: `step.status = retrying`으로 전이 후 Job을 재시도 간격만큼 지연 재enqueue(`self.class.set(wait: interval).perform_later(job_id)`). Worker 해제 → 다른 프로비저닝 Job 진행 가능
- 재개 시 Orchestrator가 `retrying` step을 감지하여 해당 step부터 재실행 (§5.5 크래시 복구와 동일 경로 사용)

### 5.4 ActionCable 상태 브로드캐스트 — FR-7.3

`StepRunner`는 각 단계 상태 변경 시 ActionCable로 Turbo Stream을 브로드캐스트한다:

1. `execute` → 상태를 `in_progress`로 변경 + 브로드캐스트
2. 성공 시 → `completed` + `result_snapshot` 저장 + 브로드캐스트
3. 실패 시 → 재시도 가능하면 `retrying`, 불가하면 `failed` + 예외 전파
4. 모든 상태 변경은 `Turbo::StreamsChannel.broadcast_replace_to`로 해당 step의 partial을 실시간 교체

> **`after_commit` 브로드캐스트**: 상태 변경은 반드시 DB 트랜잭션 커밋 이후 브로드캐스트한다(`after_commit` 콜백 또는 `ActiveRecord::Base.transaction` 블록 종료 후 명시적 호출). 트랜잭션 내부에서 브로드캐스트하면 구독자가 아직 커밋되지 않은 상태를 읽어 오래된 데이터를 표시할 수 있다.

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
| `langfuse_project_create` | `step_record.result_snapshot`의 `langfuse_project_id` 존재 + Langfuse API로 확인 | 이전 실행의 result_snapshot 활용 |
| `config_server_apply` | Config Server에서 해당 app의 설정 존재 여부 조회 | GET API 호출 |
| `health_check` | 항상 재실행 (멱등) | 검증만 수행하므로 부작용 없음 |

멱등성 체크 동작 예시 (`KeycloakClientCreate`): `result_snapshot` 또는 네이밍 규칙으로 Keycloak에 Client가 이미 존재하는지 확인 → 존재하면 `result_snapshot` 복원 후 skip.

#### 동시성 제어

두 계층에서 이중으로 직렬 실행을 보장한다.

| 계층 | 메커니즘 | 차단 대상 | 근거 |
|------|---------|----------|------|
| **앱 레벨** | `ProvisioningJob#create` 유효성 검증 + `(project_id) WHERE status IN (...)` 부분 인덱스 | 사용자 요청 단계에서 중복 Job 생성 자체를 거부 | UI/컨트롤러에서 "이미 프로비저닝이 진행 중입니다" 즉시 피드백 |
| **Worker 레벨** | `SolidQueue` 의 `limits_concurrency(to: 1, key: project_id)` | 이미 enqueue된 Job 이 동일 `project_id` 로 동시에 실행되는 상황 | 앱 레벨 검증 경합(동시 요청 2건이 동시에 통과) 또는 수동 재시도로 생긴 중복 Job 에 대한 최종 방어선 |

앱 레벨 검증은 사용자 경험(빠른 피드백)을 위한 것이고, `limits_concurrency`는 실제 실행 격리를 위한 것이다. 둘 다 필요하며 서로 대체하지 않는다.

#### 병렬 단계 부분 실패 처리

병렬 그룹(동일 `step_order`) 내에서 일부만 실패한 경우:

1. 모든 Thread 완료 대기 (Mutex로 결과 수집)
2. 실패 감지 시 → **이 그룹에서 성공한 단계만** 먼저 롤백
3. 이후 이전 단계들을 역순으로 롤백 (일반 롤백 플로우와 동일)

#### SolidQueue Job 설정

`ProvisioningExecuteJob` (`app/jobs/provisioning_execute_job.rb`):

| 설정 | 값 | 설명 |
|------|---|------|
| `queue_as` | `:provisioning` | 전용 큐 |
| `limits_concurrency` | `to: 1, key: project_id` | 동일 Project Job 직렬 실행 보장 |
| `retry_on` | `StandardError, attempts: 2` | SolidQueue 레벨 재시도 (크래시 복구용) |
| `discard_on` | `ActiveRecord::RecordNotFound` | 삭제된 Job은 폐기 |

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
| 3 | `db_cleanup` | — (Console DB) | `project_permissions` 삭제 + Project status → `deleted` |

> 삭제 시에는 외부 리소스를 병렬로 제거 → App Registry 해제 → Console DB 정리.

#### Project Update (설정 변경)

| order | 단계 | 외부 API | 비고 |
|-------|------|---------|------|
| 1 | `keycloak_client_update` | `PUT /admin/realms/{realm}/clients/{uuid}` | 인증 설정 변경 시에만 실행 (조건부). `project_auth_configs.*` dirty일 때 포함 |
| 2 | `config_server_apply` | `POST /admin/changes` | 변경된 설정만 전달 |
| 3 | `health_check` | LiteLLM | |

> 변경 필드에 따라 해당 단계만 선별 실행된다. 예: 이름/설명만 변경 시 프로비저닝 자체가 트리거되지 않으며, LiteLLM Config만 변경 시 `config_server_apply` + `health_check`만 실행된다. 상세 트리거 규칙은 아래 표 참조.

**Update 프로비저닝 트리거 규칙**: Project의 모든 PATCH가 Update 프로비저닝을 트리거하지는 않는다. 필드 변경 유형에 따라 동작이 분기된다.

| 변경 필드 | 동작 | 근거 |
|----------|------|------|
| `projects.name`, `projects.description` | **프로비저닝 없음** — 트랜잭션 내 UPDATE + AuditLog | 외부 서비스에 전파되지 않는 순수 메타데이터 |
| `project_auth_configs.*` (Redirect URI, Protocol Mapper 등) | **Update 프로비저닝 트리거** — `keycloak_client_update` + `config_server_apply` + `health_check` | Keycloak Client 동기화 필요 |
| `auth_type` 변경 (예: OIDC → SAML) | **변경 금지** (UI `readonly`, Controller 레벨 rejection) | Client 재생성이 필요 — Project를 재생성하는 것이 안전 |
| LiteLLM Config (모델, 가드레일, S3 Retention) | **Update 프로비저닝 트리거** — `config_server_apply` + `health_check` | Config Server 반영 필요 |
| `project_permissions` (멤버 권한) | **프로비저닝 없음** — DB만 갱신 | Console DB 내부 인가만 사용 |

변경 유형 판별은 `Projects::UpdateService`가 담당한다. `dirty_attributes`에 외부 전파 대상 필드가 포함된 경우에만 ProvisioningJob(`operation: update`)을 enqueue한다.

> **서로 다른 Project의 동시 설정 변경**: Console은 Project별 동시성 제어만 담당한다. 서로 다른 Project가 동시에 `config_server_apply`를 호출하는 것은 허용되며, 이로 인한 LiteLLM pod 재시작 순서 제어는 Config Server 측 책임이다.
>
> **동일 Project에 대한 연속 Update 요청**: §5.5 동시성 제어에 따라 앱 레벨 검증이 이미 `in_progress`/`retrying` Job이 있으면 새 Update 요청을 거부한다. UI는 [ui-spec §6.8 동시 설정 변경 경고](./ui-spec.md#68-동시-설정-변경-경고)로 사용자에게 재시도를 유도한다.

---

## 6. 실시간 통신 (ActionCable)

### 6.1 채널 설계 — FR-7.3

`ProvisioningChannel` (`app/channels/provisioning_channel.rb`):

- `subscribed`: `job_id` 파라미터로 Job 조회 → 해당 Project에 대한 `read`+ 권한 검증 → `stream_for job`
- 클라이언트는 `turbo_stream_from "provisioning_job_#{@job.id}"`로 구독

### 6.2 Turbo Stream 연동

| 뷰 | 역할 |
|----|------|
| `provisioning_jobs/show.html.erb` | `turbo_stream_from`으로 채널 구독 + step 목록 렌더링 |
| `provisioning_steps/_step.html.erb` | `turbo_frame_tag dom_id(step)`으로 개별 step 렌더링. 상태 아이콘/이름/상태/에러 표시 |

Step 상태 변경 시 서버에서 `broadcast_replace_to`로 해당 step의 partial을 실시간 교체한다.

### 6.3 Job 완료 시 알림

Job 완료 시 `Orchestrator`가 `job.status`를 갱신하고 `broadcast_replace_to`로 전체 상태 partial을 교체한다.

### 6.4 SolidCable 폴링 주기

ActionCable의 pub/sub adapter로 `SolidCable`(SQLite 기반)을 사용한다. SolidCable은 단일 폴링 기반이므로 상태 전파 지연은 폴링 주기에 의해 결정된다.

| 파라미터 | 기본값 | Console 설정 | 근거 |
|---------|-------|-------------|------|
| `polling_interval` | `0.1s` | `0.1s` 유지 | 프로비저닝 현황 실시간성(PRD 6.2 목표 ≤1초) 충족. SQLite WAL 모드에서 100ms 폴링의 부하는 무시할 수준 |
| `message_retention` | `1.day` | `1.hour` | 프로비저닝 Job 평균 수명이 분 단위이므로 1시간이면 충분. 저장 공간 절약 |
| `connect_timeout` | `20s` | 기본값 | ActionCable 연결 실패 시 UI가 빠르게 재연결 배너를 띄우도록 |

`config/cable.yml`에 production 환경으로 명시한다.

### 6.5 시크릿 전달 채널

프로비저닝 완료 후 일회성 시크릿(Keycloak Client Secret, PAK)을 브라우저에 전달하는 경로는 **ActionCable을 경유하지 않는다**. ActionCable 브로드캐스트는 다중 구독자가 동일 메시지를 수신하므로 동일 Project에 대한 다른 세션(예: 다른 관리자의 탭)에도 시크릿이 유출될 수 있다.

대신 다음 경로를 사용한다:

1. `ConfigServerApply` / `KeycloakClientCreate` 단계가 성공하면, 생성된 시크릿은 Rails 프로세스 메모리의 **단기 캐시**(`Rails.cache` with `expires_in: 10.minutes`)에 `provisioning_job_id` 키로 저장한다.
2. 브라우저는 현황 페이지가 `completed` 상태를 감지하면 `GET /provisioning_jobs/:id/secrets` 를 one-shot 으로 호출한다.
3. 컨트롤러는 해당 Job의 `project_id`에 대한 `write`+ 권한을 검증하고, 캐시에서 값을 읽어 응답한 뒤 즉시 캐시 키를 삭제한다.
4. 시크릿 화면을 떠난 후 재조회는 불가 — 사용자가 "확인" 버튼을 누르면 Stimulus 컨트롤러가 fetch → 응답 표시 → 10분 TTL 내라도 재조회 방지 플래그를 로컬에 기록.

캐시 저장소는 Rails 8 `solid_cache_store` 기본값을 사용한다 (SQLite 기반). Pod 재시작 시 캐시가 소실되면 시크릿 재발급 플로우(인증 설정 편집 → Secret 재발급)로 복구한다.

---

## 7. 외부 API 클라이언트

### 7.1 공통 패턴

모든 외부 API 클라이언트는 `BaseClient`를 상속하며 동일한 패턴을 따른다:

- **HTTP 클라이언트**: Faraday (JSON 요청/응답, 에러 자동 raise)
- **에러 처리**: `Faraday::Error` → `ApiError` (status, body 포함) 변환
- **설정**: `ActiveSupport::Configurable`로 base_url 등 환경별 설정 관리
- **타임아웃 기본값**: `open_timeout: 5s`, `timeout: 30s`. 단계별 재시도 정책(§5.3)과 결합되어 전체 Step 실행 시간의 상한을 제공한다. Keycloak Admin API처럼 응답이 빠른 경우 클라이언트 레벨에서 `timeout: 10s`로 축소 가능
- **Retry Middleware**: `Faraday::Retry` 미들웨어를 탑재한다. 대상은 idempotent 요청(GET, HEAD)과 `Retry-After` 헤더가 있는 429 응답만. 쓰기 요청의 재시도는 Step 레벨(§5.3 + `X-Idempotency-Key`)에서 제어

#### Circuit Breaker 방침

프로비저닝 파이프라인은 재시도 + 보상 트랜잭션으로 이미 장애 격리가 이루어지므로, 별도 Circuit Breaker 라이브러리(예: `stoplight`)는 기본적으로 도입하지 않는다. 아래 경우에만 재검토한다.

- 동일 외부 서비스의 연속 실패율이 장기간 높아 단계별 재시도가 리소스를 소모하는 경우
- Keycloak/Langfuse 장애 시에도 Console UI의 무관한 화면(멤버 목록, 사용자 검색)이 느려지는 경우 — 이 경우 `KeycloakClient`에만 회로 차단기를 선택적으로 도입

### 7.2 KeycloakClient — FR-2, FR-4

`app/clients/keycloak_client.rb` — Service Account 토큰으로 인증 (캐시 + 자동 갱신)

| 메서드 | 용도 | 관련 FR |
|--------|------|---------|
| `search_users(query:)` | 이메일/이름으로 사용자 검색 | FR-2 |
| `get_user(user_sub:)` | 사용자 상세 조회 (이름/이메일) | FR-2 |
| `get_users_by_ids(user_subs:)` | 배치 조회 (멤버 목록용) | FR-2 |
| `create_user(email:)` | 미등록 사용자 사전 생성 | FR-2 |
| `create_oidc_client(client_id:, redirect_uris:)` | OIDC Client 생성 | FR-4 |
| `create_saml_client(client_id:, attributes:)` | SAML Client 생성 | FR-4 |
| `create_oauth_client(client_id:, redirect_uris:)` | OAuth Client 생성 (PKCE) | FR-4 |
| `delete_client(uuid:)` | Client 삭제 | FR-4 |
| `get_client_secret(uuid:)` / `regenerate_client_secret(uuid:)` | Secret 조회/재발급 | FR-4 |
| `assign_client_scope(client_uuid:, scope_id:)` | Client Scope 할당 | FR-4 |

### 7.3 LangfuseClient — FR-1, FR-5

`app/clients/langfuse_client.rb` — Langfuse 웹 UI의 내부 tRPC API를 호출. `POST /api/trpc/{procedure}` 형식.

**인증 방식**: NextAuth credentials 로그인으로 세션 쿠키 획득 → 쿠키로 tRPC 호출.

```
1. POST /api/auth/callback/credentials (email + password)
   → Set-Cookie: next-auth.session-token=...
2. POST /api/trpc/{procedure} (Cookie: next-auth.session-token=...)
```

- Langfuse에 Console 전용 서비스 계정(email/password) 생성 필요
- 세션 쿠키를 인스턴스 변수로 캐시, 만료/401 시 재로그인
- 환경변수: `LANGFUSE_URL`, `LANGFUSE_SERVICE_EMAIL`, `LANGFUSE_SERVICE_PASSWORD`

> **⚠ 비공식 API**: tRPC는 Langfuse 내부 API로 업그레이드 시 breaking change 가능. 리스크 완화 전략은 [ADR-002](./adr-002-langfuse-api-strategy.md) 참조.

**Thread 안전성**: §5.2 병렬 단계 실행에서 `LangfuseClient` 인스턴스가 Thread 간 공유될 수 있다. 세션 쿠키 상태는 `Mutex#synchronize`로 보호하고, 쿠키 갱신(401 감지 → 재로그인)도 Mutex 하에서 수행한다. 대안으로 Thread-local 인스턴스(`Thread.current[:langfuse_client] ||= ...`)를 사용해도 된다 — 각 Thread가 독립 세션을 보유하므로 동시성 제어가 불필요하지만 Langfuse 측 세션 수가 늘어난다. 기본 채택은 **Mutex 보호 싱글톤**.

**SDK Key 메모리 생명주기**: `create_api_key`가 반환하는 `{public_key, secret_key}`는 **평문 시크릿**이며 Console DB에 저장되지 않는다 (PRD 6.1 Secret Zero-Store). 생명주기는 다음과 같이 제한된다.

| 단계 | 보관 위치 | 수명 |
|------|----------|------|
| `LangfuseProjectCreate#execute` 반환값 | `provisioning_step.result_snapshot` (DB) 의 `public_key`만. `secret_key`는 DB 미저장 | result_snapshot: step 수명 |
| 다음 단계 `ConfigServerApply` 로 전달 | Ruby 프로세스 메모리 (`secrets:` 파라미터) | 해당 step 실행 완료까지 |
| Config Server Admin API 전송 후 | Ruby 변수 참조 해제 | 즉시 GC 대상 |

`secret_key`는 `inspect`, 예외 backtrace, 로그에 포함되지 않도록 `LangfuseClient` 응답 객체에 `to_s`/`inspect` 오버라이드를 적용한다. 프로비저닝 실패로 롤백 시 `delete_api_key`로 Langfuse 측 키를 제거한다 — Console 측에는 이미 값이 없으므로 별도 정리 불필요.

| 메서드 | tRPC Procedure | 관련 FR |
|--------|---------------|---------|
| `create_organization(name:)` | `organizations.create` | FR-1 |
| `update_organization(id:, name:)` | `organizations.update` | FR-1 |
| `delete_organization(id:)` | `organizations.delete` | FR-1 |
| `create_project(name:, org_id:)` | `projects.create` | FR-5 |
| `delete_project(id:)` | `projects.delete` | FR-5 |
| `create_api_key(project_id:)` → `{public_key, secret_key}` | `projectApiKeys.create` | FR-5 |
| `list_api_keys(project_id:)` | `projectApiKeys.byProjectId` | FR-5 |
| `delete_api_key(id:)` | `projectApiKeys.delete` | FR-5 |

### 7.4 ConfigServerClient — FR-6, FR-8

`app/clients/config_server_client.rb` — `Authorization: Bearer <API_KEY>` 헤더로 인증.

- 환경변수: `CONFIG_SERVER_URL`, `CONFIG_SERVER_API_KEY`

| 메서드 | Config Server API | 관련 FR |
|--------|------------------|---------|
| `apply_changes(org:, project:, service:, config:, env_vars:, secrets:, idempotency_key:)` | `POST /api/v1/admin/changes` → `{version}` | FR-6 |
| `delete_changes(org:, project:, service:, idempotency_key:)` | `DELETE /api/v1/admin/changes` → `{version}` | FR-3 |
| `revert_changes(org:, project:, service:, target_version:, idempotency_key:)` | `POST /api/v1/admin/changes/revert` → `{version}` | FR-8 |
| `notify_app_registry(action:, app_data:, idempotency_key:)` | `POST /api/v1/admin/app-registry/webhook` | FR-7 |
| `get_config(org:, project:, service:)` | `GET /api/v1/config` | FR-6 |
| `get_secrets_metadata(org:, project:, service:)` | `GET /api/v1/secrets/metadata` | FR-6 |
| `get_history(org:, project:, service:)` | `GET /api/v1/history` | FR-8 |

> **Idempotency**: 쓰기 계열 엔드포인트(`apply_changes`, `delete_changes`, `revert_changes`, `notify_app_registry`)는 `X-Idempotency-Key` 헤더를 필수로 송신한다. 키는 호출 주체 단계(`provisioning_step.id` 기반)에서 생성하여 네트워크 타임아웃 후 재시도 시 중복 적용을 방지한다. Config Server가 동일 키의 요청을 수신하면 최초 처리 결과(버전 식별자)를 그대로 반환한다.

---

## 8. 인증/인가

### 8.1 역할 분담: Keycloak vs Console DB

> 상세 결정 근거는 [ADR-004](./adr-004-auth-authz-separation.md) 참조.

```
┌───────────────────────────────────────────────────────────────┐
│  Keycloak (순수 인증)                                          │
│                                                               │
│  ● 인증: OIDC Authorization Code Flow                         │
│  ● JWT 클레임: sub, email, name, realm_access.roles           │
│  ● super_admin: realm role로 판별                              │
│  ● 사용자 검색/조회: Admin API (멤버 추가, 목록 표시)           │
│  ● 그룹/역할: 미사용 (Console이 자체 관리)                      │
└────────────────────────┬──────────────────────────────────────┘
                         │ JWT (sub + super_admin 여부)
                         ▼
┌───────────────────────────────────────────────────────────────┐
│  Console DB (전체 인가)                                        │
│                                                               │
│  ● Org 소속 + 역할: org_memberships (user_sub + role)          │
│  ● Project ACL: project_permissions (role)                     │
│  ● 사용자 식별: user_sub만 저장 (이메일 미저장)                  │
│  ● 사용자 정보 표시: Keycloak API로 실시간 조회                  │
└───────────────────────────────────────────────────────────────┘
```

**Keycloak 팀 요청 사항 (최소)**:

| 항목 | 설명 |
|------|------|
| OIDC Client 등록 | Console 앱용 Confidential Client |
| JWT `realm_access.roles` 클레임 | `super_admin` 역할 판별용 |
| Console Service Account | Admin API 접근 (사용자 검색/조회 + Client 관리) |

### 8.2 인증 플로우 (Keycloak OIDC)

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
  │                          ├─ JWT 검증                 │
  │                          ├─ sub, email, name 추출    │
  │                          ├─ realm_roles → super_admin│
  │                          ├─ Rails 세션에 저장        │
  │◀── 302 /organizations ──┤                          │
```

> **세션에 저장하는 정보**: `sub` (사용자 고유 ID), `realm_roles` (super_admin 판별). 이메일/이름은 세션에만 보관하고 **Console DB에는 저장하지 않는다**. 멤버 목록 등 UI 표시 시 Keycloak Admin API로 실시간 조회한다.

#### `invited_at` / `joined_at` 채움 규칙

`org_memberships`의 두 타임스탬프는 서로 다른 이벤트에 바인딩되며, 둘 중 하나만 채워진 상태도 정상이다.

| 컬럼 | 채워지는 시점 | 주체 |
|------|---------------|------|
| `invited_at` | 멤버십 레코드 생성 시점 (Org `admin`이 멤버 추가) | `MembersController#create` |
| `joined_at` | 해당 `user_sub`가 **Console에 최초 로그인**하여 세션을 획득한 시점 | `SessionsController#create` (OIDC 콜백) |

**흐름**:

```
1. Org admin이 "dev@example.com"을 write 권한으로 추가
   └─ Keycloak에 사용자 없으면 KeycloakClient#create_user로 사전 생성
   └─ org_memberships INSERT (user_sub, role, invited_at = now, joined_at = NULL)

2. dev@example.com이 최초로 SSO 로그인
   └─ Keycloak First Broker Login이 이메일 매칭으로 기존 user 레코드에 link
   └─ SessionsController가 JWT의 sub로 org_memberships 조회
   └─ joined_at IS NULL이면 joined_at = now UPDATE (idempotent)
```

- `joined_at` 업데이트는 매 로그인이 아니라 **최초 1회**만 수행 (`WHERE joined_at IS NULL`)
- `invited_at`이 NULL인 경우는 발생하지 않음 (레코드 생성 시점에 반드시 설정). 데이터 마이그레이션이 필요하면 backfill로 처리
- 로그인한 사용자에게 해당 Org에 멤버십이 없으면 `joined_at` 업데이트 자체가 발생하지 않는다 — UI는 "접근 가능한 리소스 없음" 상태로 렌더
- `joined_at`은 UI의 "초대 대기 중" 배지(§8.4 UI Spec 참조) 표시 조건(`joined_at IS NULL`)으로도 사용된다

### 8.3 인가 모델

#### 권한 결정 흐름

```
요청: PATCH /organizations/acme/projects/chatbot/litellm_config

  1. 인증 확인
     └─ 세션에 JWT 정보 있는지?
         ├─ 없음 → 302 로그인
         └─ 있음 → Current 속성 설정 + Authorization 생성

  2. super_admin 확인
     └─ realm_roles에 "super_admin" 있는지?
         ├─ 있음 → 허용 (모든 리소스 접근 가능)
         └─ 없음 → 계속

  3. Org 멤버십 확인
     └─ org_memberships에서 (org=acme, user_sub) 조회
         ├─ 없음 → 403 Forbidden
         └─ 있음 → membership.role 확인

  4. Org 역할 기반 판단
     └─ membership.role?
         ├─ admin → 허용 (Org 내 모든 Project 접근)
         └─ read/write → Project ACL 확인

  5. Project ACL 확인
     └─ project_permissions에서 (membership, project=chatbot) 조회
         ├─ 없음 → 403 Forbidden
         └─ 있음 → permission.role ≥ 요구 역할?
             ├─ 예 → 허용
             └─ 아니오 → 403 Forbidden
```

#### 리소스별 최소 역할

| 리소스 | 액션 | 최소 역할 | 범위 |
|--------|------|----------|------|
| Organization | 생성/삭제 | `super_admin` | 전역 |
| Organization | 조회 | `read` | Org |
| Organization | 수정 | `admin` | Org |
| 멤버 | 조회 | `read` | Org |
| 멤버 | 추가/변경/제거 | `admin` | Org |
| Project | 조회 | `read` | Project |
| Project | 생성/삭제 | `admin` | Org |
| Project | 설정 변경 | `write` | Project |
| 인증 설정 | 조회 | `read` | Project |
| 인증 설정 | 변경 | `write` | Project |
| LiteLLM Config | 조회 | `read` | Project |
| LiteLLM Config | 변경 | `write` | Project |
| Config 이력 | 조회 | `read` | Project |
| Config 이력 | 롤백 | `write` | Project |
| 프로비저닝 | 현황 조회 | `read` | Project |
| 프로비저닝 | 수동 재시도 | `write` | Project |

### 8.4 구현 상세

#### ApplicationController (인가 미들웨어)

`before_action`으로 모든 요청에 인증/인가를 적용한다:

| 메서드 | 역할 |
|--------|------|
| `authenticate_user!` | 세션에 사용자 정보 없으면 Keycloak 로그인으로 리다이렉트 |
| `set_current_user` | 세션 데이터(`sub`, `realm_roles`)로 `Current` 속성 설정 |
| `authorize_org!(org, minimum_role:)` | `super_admin` → 허용. 아니면 `org_memberships`에서 역할 확인 |
| `authorize_project!(project, minimum_role:)` | `super_admin` → 허용. 아니면 `project_role()` 결과로 판단 |
| `require_super_admin!` | `super_admin`이 아니면 403 |

**역할 계층**: `read(1) < write(2) < admin(3)`. 요청된 최소 역할 이상이면 허용.

#### Current (ActiveSupport::CurrentAttributes)

`app/models/current.rb` — `ActiveSupport::CurrentAttributes` 서브클래스로 요청 단위 전역 저장소를 제공한다. 요청 종료 시 자동 리셋되며, 로그 태그(`sub`)와 감사 로그(`changed_by_sub`)에서도 동일 객체를 참조한다.

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :user_sub, :realm_roles
  attribute :request_id

  def super_admin?
    realm_roles&.include?("super_admin")
  end
end
```

`ApplicationController#set_current_user`에서 세션 데이터로 `Current.user_sub`/`Current.realm_roles`를 채우고, 컨트롤러 헬퍼/서비스/모델 어디서든 `Current.user_sub`로 접근한다.

인가 판단은 별도 PORO `Authorization`(`app/models/authorization.rb`)에 캡슐화한다.

| 메서드 | 역할 |
|--------|------|
| `Authorization.new(user_sub)` | 주입된 `user_sub`로 인스턴스 생성 (테스트 용이성) |
| `super_admin?` | `Current.realm_roles`에 `super_admin` 포함 여부 |
| `org_membership(org)` | `org_memberships` 테이블 조회 (인스턴스 수명 내 캐싱) |
| `organizations` | 소속 Org 목록 |
| `project_role(project)` | Org `admin` → `:admin`. 아니면 `project_permissions` 조회 → 해당 role 반환 |
| `accessible_projects(org)` | Org `admin`이면 전체 Project. 아니면 `project_permissions`에 있는 Project만 |

> **Thread 안전성 주의**: `Current`는 Thread-local 저장소다. §5.2에서 기술했듯 병렬 프로비저닝 Thread는 상위 요청 컨텍스트를 상속받지 못하므로, Thread 시작 전에 필요한 값(`user_sub`)을 로컬 변수로 캡처하여 `Thread.new { |sub| Current.set(user_sub: sub) { ... } }` 블록으로 전달해야 한다.

#### 사용자 정보 조회 (Keycloak API)

Console DB에 이메일/이름을 저장하지 않으므로, 멤버 목록 등 UI 표시 시 `KeycloakClient`의 사용자 조회 메서드(Section 7.2)를 사용한다.

**배치 조회 패턴**: 멤버 목록처럼 N개의 `user_sub`에 대한 정보를 한 번에 조회할 때는 `get_users_by_ids(user_subs:)`를 사용한다. 이 메서드는 내부적으로 Keycloak Admin API `GET /users?q=id:{sub1}+id:{sub2}+...`로 단일 요청을 보낸다. Keycloak이 쿼리 길이 제한으로 거부하는 경우 50개 단위 청크로 분할 호출한다.

> **캐싱**: 사용자 정보는 요청 단위 캐싱(`Current` 에 `user_cache` 속성 추가 또는 컨트롤러 인스턴스 변수). 필요 시 `Rails.cache`로 단기 캐싱 (TTL 5분) 추가 가능.

---

## 9. UI 설계

> 화면 와이어프레임, 상태 표시 규칙, 접근제어 UI 등은 [UI Spec](./ui-spec.md) 참조.

---

## 10. 설계 결정

주요 아키텍처 결정은 ADR 문서에 상세 기록되어 있다. 여기서는 ADR이 없는 결정만 기술한다.

**ADR 참조**:
- [ADR-001: 프로비저닝 오케스트레이션](./adr-001-provisioning-orchestration.md) — 직접 구현 (Rails Saga) 채택
- [ADR-002: Langfuse API 연동](./adr-002-langfuse-api-strategy.md) — tRPC (세션 쿠키) 채택
- [ADR-003: 외부 API 연동](./adr-003-external-api-integration-strategy.md) — 직접 API 호출 채택
- [ADR-004: 인증/인가 분리](./adr-004-auth-authz-separation.md) — Console DB 전량 인가 채택
- [ADR-005: 데이터베이스](./adr-005-sqlite-litestream.md) — SQLite + Litestream 채택
- [ADR-006: 프론트엔드](./adr-006-hotwire-server-rendering.md) — Hotwire 채택

### 10.1 왜 Thread(Job 내 병렬)인가

| 방식 | 장점 | 단점 | 결정 |
|------|------|------|------|
| **Thread (Job 내 병렬)** | 단순. 완료 대기 용이. 상태 일관성 보장 | Thread 안전성 주의 필요 | **채택** |
| 별도 Job (Fan-out) | 각 단계 독립 재시도 | 완료 동기화 복잡. 상태 관리 어려움 | 미채택 |

Thread 수가 2~3개로 적고, 각 Thread는 독립적인 외부 API를 호출하므로 Thread 안전성 이슈가 최소화된다.

### 10.2 왜 Console DB 스냅샷인가

| 방식 | 장점 | 단점 | 결정 |
|------|------|------|------|
| **Console DB 저장** | 롤백 시 Config Server 이력 API 불필요. 독립적 | 스냅샷 데이터 크기 | **채택** |
| Config Server 조회 | 중복 저장 없음 | Config Server 의존성 증가. 이력 API 필요 | 미채택 |

Keycloak/Langfuse 설정은 Config Server에 이력이 없으므로 Console DB에 스냅샷을 저장해야 한다. 일관성을 위해 Config Server 설정도 함께 스냅샷한다.

### 10.3 왜 동기 Health Check인가

| 방식 | 장점 | 단점 | 결정 |
|------|------|------|------|
| **프로비저닝 내 동기** | 생성 완료 전 검증 보장 | 프로비저닝 시간 증가 | **채택** (기본) |
| 별도 비동기 | 프로비저닝 빠름 | 검증 실패 시 이미 active 상태 | 선택적 사용 |

Health Check 실패는 프로비저닝 전체를 롤백하지 않고 **경고(warning)** 로 처리한다. Job의 최종 상태를 별도 상태값 `completed_with_warnings`으로 기록하고(§2.2 provisioning_jobs) 실패 내역은 `warnings` JSON 컬럼에 누적한다. Project의 `status`는 `active`로 전이하며, 현황 화면(FR-7.3)과 Project 상세(UI Spec §8.5)에 경고 배너를 노출한다. `completed`와 `completed_with_warnings`를 구분하여 저장하면 사후 분석·알림·자동 재검사 트리거에 활용할 수 있다.

---

## 11. 의존성

### 11.1 외부 시스템 의존성

| 컴포넌트 | 용도 | 필수 여부 | 장애 시 영향 |
|----------|------|----------|-------------|
| **Keycloak** | OIDC 인증, Service Account (Admin API), Client 자동 구성 | 필수 | 로그인 불가, Client 생성 불가 |
| **Langfuse** | tRPC API로 Org/Project/API Key CRUD | 필수 | 프로비저닝 실패 (Langfuse 단계) |
| **Config Server** (`aap-config-server`) | Admin API로 설정/시크릿 CRUD, App Registry webhook | 필수 | 설정 반영 불가 (Console DB CRUD는 정상) |
| **S3** | Litestream 백업 대상 | 필수 | 백업 실패 (서비스 자체는 정상) |

### 11.2 인프라 사전 요구사항

| 컴포넌트 | 용도 | 필수 여부 |
|----------|------|----------|
| **K8s Cluster** | Console Deployment, PVC | 필수 |
| **PersistentVolumeClaim** | SQLite 파일 저장 | 필수 |
| **K8s Network Policy** (Calico/Cilium) | Pod 간 접근 제어 | 권장 |
| **Litestream S3 버킷** | SQLite 실시간 백업 | 필수 |

### 11.3 Console → 외부 API 요약

| 방향 | 대상 | API | 인증 방식 |
|------|------|-----|----------|
| Console → Keycloak | 사용자 검색/조회 | Admin REST API | Service Account Token |
| Console → Keycloak | Client CRUD | Admin REST API | Service Account Token |
| Console → Langfuse | Org/Project/Key CRUD | tRPC (`/api/trpc/*`) | NextAuth 세션 쿠키 |
| Console → Config Server | 설정/시크릿 CRUD | Admin API (`/api/v1/admin/*`) | `Authorization: Bearer <API_KEY>` |
| Console → Config Server | App Registry 알림 | Webhook (`/api/v1/admin/app-registry/webhook`) | `Authorization: Bearer <API_KEY>` |
| Config Server → Console | App Registry 벌크 조회 | `GET /api/v1/apps?all=true` | (클러스터 내부) |

---

## 12. FR 추적 매트릭스

| FR | 설명 | DB 테이블 | Controller | Service | Client | Job/Channel |
|----|------|-----------|------------|---------|--------|-------------|
| **FR-1** | Organization CRUD | `organizations`, `org_memberships` | `OrganizationsController` | `Organizations::*Service` | `LangfuseClient` (Org) | — |
| **FR-2** | RBAC | `org_memberships`, `project_permissions` | `MembersController`, `ApplicationController` (인가) | — | `KeycloakClient` (사용자 검색/조회) | — |
| **FR-3** | Project CRUD | `projects`, `project_auth_configs`, `project_permissions` | `ProjectsController` | `Projects::*Service` | — | `ProvisioningJob` |
| **FR-4** | 인증 체계 자동 구성 | `project_auth_configs` | `AuthConfigsController` | `Steps::KeycloakClientCreate` | `KeycloakClient` (Client) | — |
| **FR-5** | Langfuse 프로젝트/Key | — (Console 미저장) | — | `Steps::LangfuseProjectCreate` | `LangfuseClient` | — |
| **FR-6** | LiteLLM Config | — (Config Server 위임) | `LitellmConfigsController` | `Steps::ConfigServerApply` | `ConfigServerClient` | — |
| **FR-7.1** | 상태 머신 | `provisioning_jobs` | — | `Provisioning::Orchestrator` | — | `ProvisioningJob` |
| **FR-7.2** | 실행/재시도/롤백 | `provisioning_steps` | — | `StepRunner`, `RollbackRunner` | — | `ProvisioningJob` |
| **FR-7.3** | 현황 화면 | — (jobs+steps 참조) | `ProvisioningJobsController` | — | — | `ProvisioningChannel` |
| **FR-8** | 이력/롤백 | `config_versions`, `audit_logs` | `ConfigVersionsController` | `ConfigVersions::RollbackService` | `ConfigServerClient` (revert) | — |
| **FR-9** | Health Check | — (steps에 기록) | — | `Steps::HealthCheck` | 각 Client (상태 확인) | `HealthCheckJob` |
| **FR-10** | Playground | — (서버 미저장) | `PlaygroundsController` | — | LiteLLM API (프록시) | — |
