# AAP Console — Acceptance Tests

요구사항이 만족되었는지 검증하는 기준이다.

Implementation status는 `docs/04_IMPLEMENTATION_PLAN.md`가 관리한다. 이 문서는
gate / acceptance 상태만 관리한다.

## Status Vocabulary

| Status | Meaning |
|---|---|
| `defined` | 기준은 정의됐지만 아직 실행하지 않음 |
| `not_run` | 실행 대상이지만 아직 실행하지 않음 |
| `passing` | 통과 |
| `failing` | 실패 |
| `waived` | 명시적 사유로 면제 |

`pending`처럼 모호한 상태는 쓰지 않는다. 기능 구현 상태와 acceptance 실행 상태를 분리한다.

## Criteria

| ID | REQ/NFR | Scenario | Verification | Status |
|---|---|---|---|---|
| `AC-001` | FR-1 | Given a signed-in authorized user, when they create/read/update/delete organizations, then persisted organization state and authorization checks behave as expected | automated `TEST-001` | `passing` |
| `AC-002` | FR-2 | Given org roles and project permissions, when users access member/project/user-search resources, then RBAC, last-admin guard, and self-demotion guard are enforced | automated `TEST-002` | `passing` |
| `AC-003` | FR-3 | Given an organization, when a project is created/updated/deleted, then app ID, slug uniqueness, status transitions, and provisioning job creation are correct | automated `TEST-003` | `passing` |
| `AC-004` | FR-4 | Given an OIDC auth config, when provisioning runs, then Keycloak client create/update/delete paths are called through mocked Admin API and server-owned identifiers are persisted | automated `TEST-004` | `passing` |
| `AC-005` | FR-5 / FR-6 | Given a provisioning job, when Langfuse and Config Server steps run, then Langfuse project keys are handed off ephemerally and LiteLLM config is applied via Config Server | automated `TEST-005` | `passing` |
| `AC-006` | FR-7.1 / FR-7.2 | Given create/update/delete jobs, when steps succeed, fail, retry, or rollback, then job/step/project states transition according to the saga contract | automated `TEST-006`, `TEST-007` | `passing` |
| `AC-007` | FR-7.3 | Given an authorized subscriber, when a provisioning job changes state, then ActionCable streams only the authorized job status | automated `TEST-008`; ERB timeline/retry UX remains tracked outside this gate | `passing` |
| `AC-008` | Release gate | Given the current dev branch, when full smoke validation is run, then RSpec/lint/security checks pass and docs status remains consistent | manual + automated command set in `docs/current/TESTING.md`; last run 2026-04-29 | `passing` |
| `AC-009` | FR-9 | Given configured external services, when health check runs, then it verifies service-specific post-provisioning consistency rather than only placeholder reachability | automated `TEST-009` | `passing` |
| `AC-010` | FR-8 | Given a config version rollback request, when rollback completes, then Config Server, Keycloak, Langfuse, and Console snapshot state are restored or diagnosed | automated `TEST-010` | `passing` |
| `AC-011` | FR-4 | Given SAML/OAuth/PAK scope decision, when enabled, then auth selection, provisioning, PAK issuance, revocation, and verification paths are covered | automated `TEST-011A`, `TEST-011B`; UI follow-up is non-gating per `DEC-003` | `passing` |
| `AC-012` | FR-10 | Given an authorized project user, when Playground is enabled, then chat streaming, request inspection, session-only transcript, parameter controls, guardrail responses, JSON export, usage metadata, and trace links work without exposing secrets | future `TEST-012` | `defined` |
| `AC-013` | OPS retention | Given completed provisioning jobs older than the retention window, when retention cleanup runs, then terminal job/step records are archived or deleted while failed/manual-intervention records remain available | automated `TEST-013` | `passing` |
| `AC-014` | FR-1 / FR-2 / FR-3 UI | Given signed-in users with different roles, when they use the server-rendered organization, member, and project pages, then visible actions, empty states, form errors, and redirects match their permissions | future `TEST-014` | `defined` |
| `AC-015` | FR-7.3 / secret zero-store | Given a provisioning job changes state, when a user opens the detail page, then the ERB/Hotwire timeline, retry controls, manual-intervention states, and authorized one-time secret reveal work without broadcasting secrets | future `TEST-015` | `defined` |
| `AC-016` | FR-4 / FR-6 / FR-8 UI | Given a project user with read/write access, when they view or change auth config, LiteLLM config, and config versions, then update provisioning, diff display, rollback diagnostics, and disabled future controls behave as designed | future `TEST-016` | `defined` |
| `AC-017` | FR-4 auth UI | Given SAML/OAuth/PAK backend/API support, when the auth UI is enabled, then SAML metadata, OAuth/PKCE settings, PAK issue/revoke/reveal, and disabled-to-enabled state transitions are covered | partial `TEST-017`; PAK request coverage exists, SAML/OAuth follow-up remains | `defined` |
| `AC-018` | FR-1 / FR-2 completion | Given super_admin and org admins manage organizations and members, when they create/update/delete organizations or assign users, then designated initial admins, Keycloak pre-assignment, project permission CRUD, Langfuse org sync, and org delete completion behave correctly | automated `TEST-018` | `passing` |
| `AC-019` | NFR availability / deploy | Given a release owner, when deployment, rollback, Litestream restore, and ConfigVersion storage-policy procedures are exercised, then exact commands, evidence, and rollback/restore results are recorded in the runbook | future `TEST-019` | `defined` |
| `AC-020` | Audit retention | Given audit logs older than the retention window, when the archive job runs, then JSONL archive output is written to the configured S3 prefix and archived rows are removed without losing recent audit records | future `TEST-020` | `defined` |
| `AC-021` | Admin observability | Given a super_admin, when they open the operations dashboard, then organization/project status, external service health, and failed/manual-intervention provisioning work queues are visible without exposing tenant secrets | future `TEST-021` | `defined` |
| `AC-022` | FR-8 full rollback | Given Keycloak and Langfuse mutable config snapshots exist, when a user rolls back a config version, then Console restores Config Server, Keycloak, Langfuse, Console snapshots, and diagnostics atomically or reports a recoverable failure without silent drift | future `TEST-022` | `defined` |
| `AC-023` | FR-4 auth migration | Given an existing project with active auth_type, when an operator runs the dual-client migration (`auth_binding_add` → `auth_binding_promote` → `auth_binding_remove`), then both bindings coexist during transition, role swap is reversible up to remove, retiring sessions expire naturally, and Keycloak `aap-` prefix guard is enforced | future `TEST-023`; per `ADR-007` | `defined` |
| `AC-024` | FR-3 / FR-4 / FR-6 unified edit | Given a project with `write`+ access, when the operator submits a single PATCH on `/projects/:slug` containing any combination of metadata, auth-config, and LiteLLM-config fields, then exactly one Update provisioning job is enqueued whose runtime steps short-circuit on fields that did not change (e.g., `keycloak_client_update` is a no-op when only LiteLLM fields are dirty); when only metadata is dirty, no provisioning job is enqueued; concurrency lock is enforced at the form level. Persisted-step pruning by dirty subset is tracked under `PROV-5C.6` and is out of scope for this AC | future `TEST-024` | `defined` |
| `AC-DOC-001` | DOC-M1 | Given a new session or PR, when an agent follows repo guidance, then it reaches `current-state`, `04_IMPLEMENTATION_PLAN`, `current/*`, canonical PRD/HLD paths, and the PR template/doc-freshness guidance without stale doc-only guidance | link check + doc review | `passing` |

## Tests

| ID | Name | Location | Covers |
|---|---|---|---|
| `TEST-001` | Organization request specs | `spec/requests/organizations_spec.rb`, `spec/services/organizations/*_spec.rb`, `spec/models/organization_spec.rb` | `AC-001` |
| `TEST-002` | RBAC/member specs | `spec/requests/members_spec.rb`, `spec/requests/users_spec.rb`, `spec/models/authorization_spec.rb`, `spec/models/org_membership_spec.rb` | `AC-002` |
| `TEST-003` | Project lifecycle specs | `spec/requests/projects_spec.rb`, `spec/services/projects/*_spec.rb`, `spec/models/project_spec.rb` | `AC-003` |
| `TEST-004` | Keycloak/auth config specs | `spec/requests/auth_configs_spec.rb`, `spec/clients/keycloak_client_spec.rb`, `spec/services/provisioning/steps/keycloak_client_*_spec.rb` | `AC-004` |
| `TEST-005` | Langfuse/Config Server specs | `spec/clients/langfuse_client_spec.rb`, `spec/clients/config_server_client_spec.rb`, `spec/services/provisioning/steps/langfuse_project_create_spec.rb`, `spec/services/provisioning/steps/config_server_apply_spec.rb` | `AC-005` |
| `TEST-006` | Provisioning orchestration specs | `spec/services/provisioning/orchestrator_spec.rb`, `spec/services/provisioning/step_seeder_spec.rb`, `spec/jobs/provisioning_execute_job_spec.rb` | `AC-006` |
| `TEST-007` | Retry/rollback specs | `spec/services/provisioning/step_runner_spec.rb`, `spec/services/provisioning/rollback_runner_spec.rb`, step specs under `spec/services/provisioning/steps/` | `AC-006` |
| `TEST-008` | Realtime provisioning specs | `spec/channels/provisioning_channel_spec.rb`, `spec/channels/application_cable/connection_spec.rb`, `spec/requests/provisioning_jobs_spec.rb` | `AC-007` |
| `TEST-009` | Health check consistency specs | `spec/services/provisioning/steps/health_check_spec.rb` | `AC-009` |
| `TEST-010` | Config version rollback specs | `spec/requests/config_versions_spec.rb` | `AC-010` |
| `TEST-011A` | PAK issue/revoke/verify specs | `spec/requests/project_api_keys_spec.rb`, `spec/requests/api/v1/project_api_keys_spec.rb`, `spec/models/project_api_key_spec.rb` | `AC-011` PAK subset |
| `TEST-011B` | SAML/OAuth backend provisioning specs | `spec/clients/keycloak_client_spec.rb`, `spec/services/provisioning/steps/keycloak_client_create_spec.rb`, `spec/services/projects/create_service_spec.rb` | `AC-011` SAML/OAuth subset |
| `TEST-012` | Playground request/system specs | planned `spec/requests/playgrounds_spec.rb`, planned system specs for streaming chat, inspector, trace links, and session-only export | `AC-012` |
| `TEST-013` | Provisioning retention cleanup specs | `spec/jobs/provisioning_jobs_cleanup_job_spec.rb`, `spec/models/provisioning_job_spec.rb` | `AC-013` |
| `TEST-014` | Core product UI system/request specs | partial request/model specs cover layout, Organization index/detail/new/edit pages, member management pages, Project index/detail/new/delete flows, role-aware empty states/actions, HTML form errors, 404 shells, redirects, and authz scope | `AC-014` |
| `TEST-015` | Provisioning detail and secret reveal specs | request/service specs cover provisioning show HTML timeline, persisted step state, step partial replacement endpoint, warnings/errors, manual retry UX, concurrent-job banners, authorized OIDC secret fetch, TTL expiry, authz, 404 shell, and JSON compatibility; shared masked/copy/confirm reveal UX is reused by auth-config secret and PAK surfaces | `AC-015` |
| `TEST-016` | Config management UI specs | partial request/spec coverage exists for auth config HTML view/update/regenerate-secret flow plus PAK summary/reveal rendering, LiteLLM config HTML view/update/validation flow, and config-version HTML index/show/diff/rollback-diagnostics flow in `spec/requests/auth_configs_spec.rb`, `spec/requests/litellm_configs_spec.rb`, and `spec/requests/config_versions_spec.rb`; SAML/OAuth auth expansion UI remains planned | `AC-016` |
| `TEST-017` | Auth expansion UI specs | partial request/spec coverage now exists for PAK issue/revoke/reveal and audit feedback in `spec/requests/project_api_keys_spec.rb` and `spec/requests/auth_configs_spec.rb`; SAML metadata and OAuth/PKCE follow-up specs remain planned | `AC-017` |
| `TEST-018` | Org/member completion specs | `spec/requests/organizations_spec.rb`, `spec/services/organizations/*_spec.rb`, `spec/requests/members_spec.rb`, `spec/clients/keycloak_client_spec.rb`, `spec/jobs/organization_destroy_finalize_job_spec.rb` | `AC-018` |
| `TEST-019` | Deployment/restore evidence | planned release-owner checklist, deploy/rollback dry-run evidence, Litestream restore drill, and ConfigVersion storage-policy acceptance notes | `AC-019` |
| `TEST-020` | Audit archive job specs | planned job/storage specs for archive JSONL content, prefix selection, retention deletion, and failure handling | `AC-020` |
| `TEST-021` | Super-admin dashboard specs | planned request/system specs for super_admin-only dashboard, service health summaries, and failed/manual-intervention job queue | `AC-021` |
| `TEST-022` | Full external rollback specs | planned service/request specs for Keycloak/Langfuse snapshot capture, restore ordering, Config Server rollback, diagnostics, and recoverable failure states | `AC-022` |
| `TEST-023` | Auth migration dual-client specs | planned request/service specs for `auth_binding_add` / `auth_binding_promote` / `auth_binding_remove` plans, role/state transitions on `project_auth_configs`, partial unique index enforcement, prefix-guarded Keycloak deletion, and rollback paths | `AC-023` |
| `TEST-024` | Unified Project edit specs | planned request specs covering combined PATCH (auth + LiteLLM + metadata) → single provisioning job with correct dirty step subset, metadata-only PATCH → no job, concurrency lock 409 with banner, read-only conversion of legacy auth/litellm edit pages, and `dirty-tracker` Stimulus contract | `AC-024` |

## Definition of Done

- 모든 `must` REQ의 AC가 `passing`
- 모든 required gate가 `passing` 또는 명시적으로 `waived`
- 모든 NFR이 측정 가능한 방식으로 검증됨
- 주요 운영 시나리오가 `docs/05_RUNBOOK.md`에 문서화됨
- Traceability matrix가 최신

## Notes

- AC가 없는 REQ는 verify 불가하므로 PRD로 돌려보낸다.
- 실패한 수동 acceptance는 회귀 방지를 위해 automated TEST로 승격한다.
