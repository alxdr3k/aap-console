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
| `AC-011` | FR-4 | Given SAML/OAuth/PAK scope decision, when enabled, then auth selection, provisioning, PAK issuance, revocation, and verification paths are covered | future automated request/service/model specs | `defined` |
| `AC-012` | FR-10 | Given an authorized project user, when Playground is enabled, then chat streaming, request inspection, and trace links work without exposing secrets | future system/request specs | `defined` |
| `AC-013` | OPS retention | Given completed provisioning jobs older than the retention window, when retention cleanup runs, then terminal job/step records are archived or deleted while failed/manual-intervention records remain available | future job/service specs | `defined` |
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
| `TEST-013` | Provisioning retention cleanup specs | planned `spec/jobs/provisioning_jobs_cleanup_job_spec.rb` 또는 service spec | `AC-013` |

## Definition of Done

- 모든 `must` REQ의 AC가 `passing`
- 모든 required gate가 `passing` 또는 명시적으로 `waived`
- 모든 NFR이 측정 가능한 방식으로 검증됨
- 주요 운영 시나리오가 `docs/05_RUNBOOK.md`에 문서화됨
- Traceability matrix가 최신

## Notes

- AC가 없는 REQ는 verify 불가하므로 PRD로 돌려보낸다.
- 실패한 수동 acceptance는 회귀 방지를 위해 automated TEST로 승격한다.
