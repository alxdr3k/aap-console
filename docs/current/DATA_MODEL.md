# AAP Console — Data Model

Code, migrations, schemas, generated references가 authoritative source다. 이 문서는
사람이 빠르게 읽기 위한 map이다.

## Source Of Truth

| Source | Role |
|---|---|
| `db/schema.rb` | 현재 main application schema |
| `db/migrate/` | Schema evolution history |
| `app/models/*.rb` | Validation, association, enum, lifecycle helper |
| `spec/factories/*.rb` | Test object construction |

## Current Entities

| Entity | Purpose | Source |
|---|---|---|
| `Organization` | 최상위 tenant boundary. Project와 membership을 소유 | `app/models/organization.rb`, `organizations` table |
| `Project` | Generated `app_id`와 provisioning lifecycle status를 가진 managed app/project | `app/models/project.rb`, `projects` table |
| `OrgMembership` | Keycloak `user_sub` 기준 organization role | `app/models/org_membership.rb`, `org_memberships` table |
| `ProjectPermission` | Membership별 project-specific read/write permission | `app/models/project_permission.rb`, `project_permissions` table |
| `ProjectAuthConfig` | Project별 main auth mode와 Keycloak client identifier | `app/models/project_auth_config.rb`, `project_auth_configs` table |
| `ProjectApiKey` | PAK metadata/digest storage. Plaintext token은 발급 응답에만 포함하고 저장하지 않음 | `app/models/project_api_key.rb`, `project_api_keys` table |
| `ProvisioningJob` | Async create/update/delete saga instance | `app/models/provisioning_job.rb`, `provisioning_jobs` table |
| `ProvisioningStep` | Individual provisioning step과 retry/rollback state | `app/models/provisioning_step.rb`, `provisioning_steps` table |
| `ConfigVersion` | Config version history와 rollback anchor | `app/models/config_version.rb`, `config_versions` table |
| `AuditLog` | User/resource action audit event | `app/models/audit_log.rb`, `audit_logs` table |
| `Authorization` | Persisted model이 아닌 authorization policy helper | `app/models/authorization.rb` |
| `Current` | Per-request current user context | `app/models/current.rb` |

## Storage

| Store | Purpose | Source |
|---|---|---|
| SQLite main DB | App domain data와 audit/config/provisioning state | `config/database.yml`, `db/schema.rb` |
| SolidQueue schema | Background job persistence | `db/queue_schema.rb`, `config/queue.yml` |
| SolidCache schema | Cache persistence | `db/cache_schema.rb`, `config/cache.yml` |
| SolidCable schema | ActionCable backing store | `db/cable_schema.rb`, `config/cable.yml` |

## Lifecycle States

| Entity | States | Notes |
|---|---|---|
| `Project.status` | `provisioning`, `active`, `update_pending`, `deleting`, `deleted`, `provision_failed` | `deleted`는 보존되는 soft-delete style state |
| `ProvisioningJob.status` | `pending`, `in_progress`, `completed`, `completed_with_warnings`, `failed`, `retrying`, `rolling_back`, `rolled_back`, `rollback_failed` | Active job unique index는 `pending`, `in_progress`, `retrying`, `rolling_back`을 포함. Retention cleanup은 180일이 지난 `completed`, `completed_with_warnings`, `rolled_back`만 삭제하고 `failed`, `rollback_failed`는 보존 |
| `ProvisioningStep.status` | `pending`, `in_progress`, `completed`, `failed`, `retrying`, `skipped`, `rolled_back`, `rollback_failed` | Step name은 `Provisioning::StepSeeder`가 seed |
| `OrgMembership.role` | `admin`, `write`, `read` | Org role의 source of truth는 Console DB |
| `ProjectPermission.role` | `write`, `read` | Org admin은 implicit project access를 가진다 |
| `ProjectAuthConfig.auth_type` | `oidc`, `saml`, `oauth`, `pak` | OIDC/SAML/OAuth backend path와 PAK API path는 구현됨. PAK auth-config UI는 landed, SAML/OAuth UI는 `DEC-003` 후속 |

## Current Gaps

| Area | Gap |
|---|---|
| Organization/member completion | Backend/API completion is landed in `CORE-5A.*` / `AC-018`; member management and org/project UI remain tracked by `UI-5A.*` |
| Auth UI | OIDC auth config HTML edit/reveal path와 PAK issue/revoke/reveal auth-config surface는 landed. SAML/OAuth UI/metadata 입력 범위는 아직 구현되지 않음 |
| Secret reveal | OIDC client secrets and PAK plaintext are stored only in transient server-side stores: provisioning completion uses `Provisioning::SecretCache` keyed by provisioning job, auth-config regeneration uses `AuthConfigs::SecretRevealCache` keyed by project, and browser PAK issuance uses `ProjectApiKeys::RevealCache` keyed by project with same-browser session fallback if shared cache persistence fails. Primary paths keep a 10-minute TTL and metadata guard |
| LiteLLM / config-version UI | Current `ConfigVersion.snapshot` is the editable source for models, guardrails, `s3_retention_days`, and derived `s3_path` in the server-rendered LiteLLM config page, and the same snapshot powers the config-version diff/detail browser UI |
| Config rollback snapshots | Current `ConfigVersion` snapshot does not carry Keycloak/Langfuse mutable config required for full FR-8 restore; tracked by `OPS-7A.5` / `AC-022` |
| Audit archive | `audit_logs` retention archive job is a target design item, not current code |
| Generated docs | `docs/generated/`는 있으나 active generator는 아직 없음 |
