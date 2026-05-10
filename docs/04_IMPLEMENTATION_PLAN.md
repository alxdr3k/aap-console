# AAP Console — Implementation Plan

제품 gate, 기술 흐름, 구현 slice 상태를 한 곳에서 시퀀싱한다.

이 문서는 boilerplate `24851cf`의 roadmap / status taxonomy와 `24b47f1`의
maintenance drift workflow를 기준으로 한 canonical status ledger다. 세부 구현
설명은 code / tests / current docs에 두고, 여기에는 milestone, track, phase,
slice, gate, evidence, next work만 남긴다.

## Taxonomy

| Term | Meaning | Example ID | Notes |
|---|---|---|---|
| Milestone | 제품 / 사용자 관점의 delivery gate | `P0-M3` | 사용자가 얻는 상태 기준 |
| Track | 기술 영역 또는 큰 구현 흐름 | `PROV` | `CORE`, `PROV`, `OPS` 등 |
| Phase | Track 안의 구현 단계 | `PROV-3A` | 같은 track 안에서 순서가 있는 단계 |
| Slice | 커밋 가능한 구현/검증 단위 | `PROV-3A.1` | PR / commit / issue와 연결 가능한 크기 |
| Gate | 검증 / acceptance 기준 | `AC-009` / `TEST-020` | `06_ACCEPTANCE_TESTS.md` 또는 spec 위치 |
| Evidence | 완료를 뒷받침하는 근거 | code, tests, docs | 본문 복제 대신 링크 / ID |

## Thin-doc Boundary

- `docs/04_IMPLEMENTATION_PLAN.md`가 roadmap / status ledger의 canonical 위치다.
- `docs/context/current-state.md`는 현재 milestone / track / phase / slice만 짧게 요약한다.
- `docs/current/`는 구현된 상태를 빠르게 찾는 navigation layer다.
- 미래 roadmap, phase inventory, 상세 backlog를 `docs/current/`에 복제하지 않는다.
- Runtime, schema, operation, test command가 바뀌면 해당 `docs/current/` 문서를 같이 갱신한다.

## Unplanned feedback

User feedback from real usage is triaged before it enters the roadmap.

- Clear defects, UX regressions, or acceptance failures may become small hotfix slices.
- Broader product or architecture changes go through Q / DEC / PRD / roadmap updates.
- Keep detailed feedback threads in the issue tracker. Record only the actionable
  slice, gate, evidence, and next step here.
- Bug fixes should leave regression evidence when practical.

## Status Vocabulary

Implementation status:

| Status | Meaning |
|---|---|
| `planned` | 계획됨. 아직 시작 조건이 충족되지 않음 |
| `ready` | 시작 가능. dependency와 scope가 충분히 정리됨 |
| `in_progress` | 구현 또는 문서 작업 진행 중 |
| `landed` | 코드 / 문서 변경이 반영됨 |
| `accepted` | Gate를 통과했고 milestone 기준으로 수용됨 |
| `blocked` | Blocker 때문에 진행 불가 |
| `deferred` | 의도적으로 뒤로 미룸 |
| `dropped` | 하지 않기로 함 |

Gate status:

| Status | Meaning |
|---|---|
| `defined` | 기준은 정의됐지만 아직 실행하지 않음 |
| `not_run` | 실행 대상이지만 아직 실행하지 않음 |
| `passing` | 통과 |
| `failing` | 실패 |
| `waived` | 명시적 사유로 면제 |

## Milestones

| Milestone | Product / user gate | Target date | Status | Gate | Evidence | Notes |
|---|---|---|---|---|---|---|
| `P0-M1` | Organization / Project CRUD와 Console DB RBAC가 동작한다 | 2026-04-25 | `accepted` | `AC-001` / `AC-002` / `AC-003` | `spec/requests/organizations_spec.rb`, `spec/requests/projects_spec.rb`, `spec/requests/members_spec.rb` | MVP foundation |
| `P0-M2` | OIDC, Langfuse, LiteLLM, Config Server 기본 프로비저닝 경로가 동작한다 | 2026-04-25 | `accepted` | `AC-004` / `AC-005` / `AC-006` | `app/services/provisioning/`, `spec/services/provisioning/` | 기본 프로비저닝 경로 accepted |
| `P0-M3` | 운영 안정성 release gate를 닫는다 | 2026-04-29 | `accepted` | `AC-007` / `AC-008` / `AC-009` / `AC-010` / `AC-013` | `docs/03_RISK_SPIKES.md`, `app/jobs/provisioning_jobs_cleanup_job.rb` | 운영 안정성 gate closed |
| `P0-M4` | SAML/OAuth/PAK 범위를 확정하고 구현한다 | 2026-04-29 | `accepted` | `AC-011` | `DEC-003`, `app/controllers/project_api_keys_controller.rb`, `spec/services/provisioning/steps/keycloak_client_create_spec.rb` | Backend/API gate accepted; UI follow-up deferred |
| `P0-M5` | Core server-rendered product UI, provisioning detail, and FR-1/2/3 completion gaps are productized |  | `planned` | `AC-014` / `AC-015` / `AC-016` / `AC-018` | `docs/ui-spec.md`, `docs/02_HLD.md#4-api-설계` | Next gate |
| `P1-M1` | SAML/OAuth/PAK backend/API work is exposed through safe product UI |  | `planned` | `AC-017` | `DEC-003`, `docs/ui-spec.md#811-인증-설정-편집--fr-4` | Auth UI follow-up |
| `P1-M2` | Deployment, restore, audit archive, storage-policy, and full external rollback operations are accepted |  | `planned` | `AC-019` / `AC-020` / `AC-022` | `docs/05_RUNBOOK.md`, `docs/02_HLD.md#82-k8s-배포-전략` | Operational hardening |
| `P1-M3` | 운영 중인 Project의 auth_type을 dual-client coexistence로 seamless하게 마이그레이션할 수 있다 |  | `planned` | `AC-023` | `docs/adr/adr-007-auth-type-migration.md`, `DEC-005` | AUTH-6B 마이그레이션 플로우; AUTH-6A 완료 후 착수 |
| `P2-M1` | Playground works end to end as a project-scoped verification tool |  | `planned` | `AC-012` | `docs/01_PRD.md#fr-10-playground-ai-chat`, `docs/ui-spec.md#810-playground--fr-10-phase-4` | PRD P2 |
| `P2-M2` | Super-admin operations dashboard is defined and implemented |  | `planned` | `AC-021` | `docs/01_PRD.md#66-관측성`, `docs/ui-spec.md` | Requires `Q-003` decision |
| `DOC-M1` | Boilerplate 문서 체계가 repo에 적용된다 | 2026-04-29 | `accepted` | `AC-DOC-001` | `AGENTS.md`, `docs/context/current-state.md`, `docs/current/`, `.github/pull_request_template.md`, PR #24 | Merged on 2026-04-29 |

## Tracks

| Track | Purpose | Active phase | Status | Notes |
|---|---|---|---|---|
| `DOC` | Boilerplate migration, source-of-truth 정리, agent guidance | `DOC-1A` | `accepted` | 최신 roadmap taxonomy와 maintenance drift workflow 반영 |
| `CORE` | Organization, Project, member, RBAC core | `CORE-5A` | `landed` | API baseline plus initial admin/pre-assignment/project permission/org delete completion gaps are implemented; product UI remains in `UI-5A.*` |
| `PROV` | Provisioning pipeline, step orchestration, rollback | `PROV-2A` | `accepted` | 기본 경로 accepted. P0-M3 운영 보강은 `OPS-3A`에서 추적 |
| `INTEG` | Keycloak, Langfuse, Config Server client integration | `INTEG-2A` | `accepted` | 테스트는 WebMock 기반 |
| `UI` | Realtime status path와 server-rendered UI | `UI-5A` / `UI-5B` / `UI-5C` | `in_progress` | ActionCable path and UI shell/Hotwire baseline landed. Product ERB pages continue as leaf work |
| `SEC` | Secret reveal and zero-store product path | `SEC-5B` | `landed` | Provisioning secret reveal cache path is landed and now reused by auth-config secret/PAK reveal product flows |
| `AUTH` | 인증 방식 확장과 PAK | `AUTH-6A` | `in_progress` | P0-M4 backend/API gate accepted; PAK product UI landed, SAML/OAuth product UI remains |
| `OPS` | Runbook, deployment, health check, rollback operation | `OPS-7A` | `planned` | P0-M3 stability accepted; production deploy/restore/archive remains |
| `PLAY` | Playground AI chat | `PLAY-8A` | `planned` | PRD P2 gate |
| `ADMIN` | Super-admin operations dashboard | `ADMIN-8A` | `planned` | Scope question open |

## Phases / Slices

| Slice | Milestone | Track | Phase | Goal | Depends | Gate | Gate status | Status | Evidence | Next |
|---|---|---|---|---|---|---|---|---|---|---|
| `DOC-1A.1` | `DOC-M1` | `DOC` | `DOC-1A` | Boilerplate skeleton과 numbered PRD/HLD path 도입 |  | `AC-DOC-001` | `passing` | `accepted` | `AGENTS.md`, `docs/00_PROJECT_DELIVERY_PLAYBOOK.md`, `docs/01_PRD.md`, `docs/02_HLD.md` | 유지보수 |
| `DOC-1A.2` | `DOC-M1` | `DOC` | `DOC-1A` | Roadmap/status ledger를 최신 taxonomy로 작성 | `DOC-1A.1` | `AC-DOC-001` | `passing` | `accepted` | `docs/04_IMPLEMENTATION_PLAN.md` | 유지보수 |
| `DOC-1A.3` | `DOC-M1` | `DOC` | `DOC-1A` | Current-state/current docs와 agent guidance 최신화 | `DOC-1A.2` | `AC-DOC-001` | `passing` | `accepted` | `docs/context/current-state.md`, `docs/current/`, `CLAUDE.md` | 유지보수 |
| `DOC-1A.4` | `DOC-M1` | `DOC` | `DOC-1A` | Maintenance drift workflow를 PR template과 doc-freshness 예시에 반영 | `DOC-1A.3` | `AC-DOC-001` | `passing` | `accepted` | `.github/pull_request_template.md`, `.github/workflows/doc-freshness.yml.example`, `docs/DOCUMENTATION.md` | 유지보수 |
| `CORE-1A.1` | `P0-M1` | `CORE` | `CORE-1A` | Organization CRUD |  | `AC-001` / `TEST-001` | `passing` | `accepted` | `app/controllers/organizations_controller.rb`, `spec/requests/organizations_spec.rb` | 유지보수 |
| `CORE-1A.2` | `P0-M1` | `CORE` | `CORE-1A` | Member/RBAC, last-admin/self-demotion guard | `CORE-1A.1` | `AC-002` / `TEST-002` | `passing` | `accepted` | `app/models/authorization.rb`, `spec/requests/members_spec.rb`, `spec/requests/users_spec.rb`, `spec/models/authorization_spec.rb` | 유지보수 |
| `CORE-1A.3` | `P0-M1` | `CORE` | `CORE-1A` | Project CRUD와 App ID lifecycle | `CORE-1A.1` | `AC-003` / `TEST-003` | `passing` | `accepted` | `app/services/projects/`, `spec/requests/projects_spec.rb` | 유지보수 |
| `PROV-2A.1` | `P0-M2` | `PROV` | `PROV-2A` | Create/update/delete step seeding | `CORE-1A.3` | `AC-006` / `TEST-006` | `passing` | `accepted` | `app/services/provisioning/step_seeder.rb`, `spec/services/provisioning/step_seeder_spec.rb` | 유지보수 |
| `PROV-2A.2` | `P0-M2` | `PROV` | `PROV-2A` | Parallel execution, retry, rollback status transitions | `PROV-2A.1` | `AC-006` / `TEST-007` | `passing` | `accepted` | `app/services/provisioning/orchestrator.rb`, `step_runner.rb`, `rollback_runner.rb`, related specs | 유지보수 |
| `INTEG-2A.1` | `P0-M2` | `INTEG` | `INTEG-2A` | OIDC Keycloak client provisioning | `PROV-2A.1` | `AC-004` / `TEST-004` | `passing` | `accepted` | `app/services/provisioning/steps/keycloak_client_create.rb`, `spec/services/provisioning/steps/keycloak_client_create_spec.rb` | SAML/OAuth는 `AUTH-4A` |
| `INTEG-2A.2` | `P0-M2` | `INTEG` | `INTEG-2A` | Langfuse project와 Config Server apply | `PROV-2A.1` | `AC-005` / `TEST-005` | `passing` | `accepted` | `app/clients/langfuse_client.rb`, `app/clients/config_server_client.rb`, related specs | 유지보수 |
| `UI-2B.1` | `P0-M3` | `UI` | `UI-2B` | ActionCable provisioning stream | `PROV-2A.2` | `AC-007` / `TEST-008` | `passing` | `landed` | `app/channels/provisioning_channel.rb`, `spec/channels/provisioning_channel_spec.rb` | Product UI follow-up in `UI-5B.*` |
| `OPS-3A.1` | `P0-M3` | `OPS` | `OPS-3A` | 외부 리뷰어 피드백 통합 smoke 재검증 | `P0-M2` | `AC-008` | `passing` | `accepted` | `docs/current/TESTING.md`, 2026-04-29 local smoke run: `bin/rspec`, `RUBOCOP_CACHE_ROOT=tmp/rubocop bin/rubocop`, `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error`, `bin/bundler-audit`, `bin/rails db:test:prepare`, `bin/rails db:migrate:status` | 유지보수 |
| `OPS-3A.2` | `P0-M3` | `OPS` | `OPS-3A` | Health check 상세 assertion 구현 | `PROV-2A.2` | `AC-009` / `TEST-009` | `passing` | `accepted` | `app/services/provisioning/steps/health_check.rb`, `spec/services/provisioning/steps/health_check_spec.rb` | 유지보수 |
| `OPS-3A.3` | `P0-M3` | `OPS` | `OPS-3A` | Config rollback의 external restore/diagnostics 경로 완결 | `INTEG-2A.2` | `AC-010` / `TEST-010` | `passing` | `accepted` | `app/controllers/config_versions_controller.rb`, `app/services/config_versions/rollback_service.rb`, `spec/requests/config_versions_spec.rb` | 유지보수 |
| `OPS-3A.4` | `P0-M3` | `OPS` | `OPS-3A` | Provisioning job retention cleanup 구현 | `PROV-2A.2` | `AC-013` / `TEST-013` | `passing` | `accepted` | `app/jobs/provisioning_jobs_cleanup_job.rb`, `config/recurring.yml`, `spec/jobs/provisioning_jobs_cleanup_job_spec.rb` | 유지보수 |
| `AUTH-4A.1` | `P0-M4` | `AUTH` | `AUTH-4A` | SAML/OAuth backend provisioning coverage | `Q-001` / `DEC-003` | `AC-011` SAML/OAuth subset / `TEST-011B` | `passing` | `accepted` | `spec/clients/keycloak_client_spec.rb`, `spec/services/provisioning/steps/keycloak_client_create_spec.rb`, `spec/services/projects/create_service_spec.rb` | UI follow-up deferred |
| `AUTH-4A.2` | `P0-M4` | `AUTH` | `AUTH-4A` | PAK 발급/폐기/검증 API | `Q-001` | `AC-011` PAK subset / `TEST-011A` | `passing` | `accepted` | `app/controllers/project_api_keys_controller.rb`, `app/controllers/api/v1/project_api_keys_controller.rb`, `app/services/project_api_keys/`, `spec/requests/project_api_keys_spec.rb`, `spec/requests/api/v1/project_api_keys_spec.rb` | UI follow-up deferred |
| `CORE-5A.1` | `P0-M5` | `CORE` | `CORE-5A` | Organization create/update product semantics: initial admin selection, Langfuse org update, audit coverage | `CORE-1A.1` | `AC-018` / `TEST-018` | `passing` | `landed` | `app/services/organizations/create_service.rb`, `app/services/organizations/update_service.rb`, `spec/services/organizations/update_service_spec.rb`, `spec/requests/organizations_spec.rb` | Product UI remains `UI-5A.*` |
| `CORE-5A.2` | `P0-M5` | `CORE` | `CORE-5A` | Member management completion: Keycloak search/pre-assignment, project permission grant/update/revoke API, audit logs | `CORE-1A.2` | `AC-018` / `TEST-018` | `passing` | `landed` | `app/controllers/members_controller.rb`, `app/controllers/member_project_permissions_controller.rb`, `spec/requests/members_spec.rb`, `spec/clients/keycloak_client_spec.rb` | Product UI landed in `UI-5A.3` |
| `CORE-5A.3` | `P0-M5` | `CORE` | `CORE-5A` | Organization delete completion orchestration after child project delete jobs, Langfuse org delete, and progress summary links | `PROV-2A.2` / `CORE-1A.3` | `AC-018` / `TEST-018` | `passing` | `landed` | `app/services/organizations/destroy_service.rb`, `app/jobs/organization_destroy_finalize_job.rb`, `spec/services/organizations/destroy_service_spec.rb`, `spec/jobs/organization_destroy_finalize_job_spec.rb` | Progress UI links remain `UI-5B.*` / `UI-5A.*` |
| `UI-5A.1` | `P0-M5` | `UI` | `UI-5A` | Application layout, navigation, authenticated empty states, role-aware controls | `CORE-1A` | `AC-014` / `TEST-014` | `defined` | `landed` | `app/views/layouts/application.html.erb`, `app/views/organizations/index.html.erb`, `app/views/organizations/show.html.erb`, `app/javascript/controllers/flash_controller.js`, `spec/requests/organizations_spec.rb`, `spec/models/authorization_spec.rb` | 유지보수 |
| `UI-5A.2` | `P0-M5` | `UI` | `UI-5A` | Organization list/detail/new/edit ERB pages | `CORE-5A.1` | `AC-014` / `TEST-014` | `defined` | `landed` | `app/views/organizations/index.html.erb`, `app/views/organizations/show.html.erb`, `app/views/organizations/new.html.erb`, `app/views/organizations/edit.html.erb`, `app/views/organizations/_form.html.erb`, `spec/requests/organizations_spec.rb` | 유지보수 |
| `UI-5A.3` | `P0-M5` | `UI` | `UI-5A` | Member management ERB, user search autocomplete, role/project permission controls | `CORE-5A.2` | `AC-014` / `AC-018` / `TEST-014` / `TEST-018` | `defined` | `landed` | `app/controllers/members_controller.rb`, `app/controllers/member_project_permissions_controller.rb`, `app/views/members/index.html.erb`, `app/javascript/controllers/user_search_controller.js`, `app/javascript/controllers/role_permissions_controller.js`, `spec/requests/members_spec.rb` | Server-side validation remains authoritative |
| `UI-5A.4` | `P0-M5` | `UI` | `UI-5A` | Project list/detail/create/delete ERB pages with provisioning redirects | `CORE-1A.3` / `PROV-2A.1` | `AC-014` / `TEST-014` | `defined` | `landed` | `app/controllers/projects_controller.rb`, `app/views/projects/index.html.erb`, `app/views/projects/new.html.erb`, `app/views/projects/show.html.erb`, `spec/requests/projects_spec.rb` | Disabled future auth/config modes remain `UI-5C.*` / `AUTH-6A.*` |
| `UI-5B.1` | `P0-M5` | `UI` | `UI-5B` | Provisioning show ERB timeline for create/update/delete operations | `UI-2B.1` | `AC-015` / `TEST-015` | `defined` | `landed` | `app/controllers/provisioning_jobs_controller.rb`, `app/views/provisioning_jobs/show.html.erb`, `spec/requests/provisioning_jobs_spec.rb` | Renders latest DB state on refresh; realtime replacement remains `UI-5B.2` |
| `UI-5B.2` | `P0-M5` | `UI` | `UI-5B` | Turbo/Stimulus ActionCable consumer, reconnect/polling fallback, step partial replacement | `UI-5B.1` | `AC-015` / `TEST-015` | `defined` | `landed` | `app/javascript/controllers/provisioning_controller.js`, `app/views/provisioning_jobs/_step.html.erb`, `app/controllers/provisioning_jobs_controller.rb`, `spec/requests/provisioning_jobs_spec.rb` | No secret payload over ActionCable |
| `UI-5B.3` | `P0-M5` | `UI` | `UI-5B` | Manual retry UX, rollback_failed/manual-intervention state, concurrent job warning banners | `UI-5B.1` | `AC-015` / `TEST-015` | `defined` | `landed` | `app/controllers/provisioning_jobs_controller.rb`, `app/views/provisioning_jobs/show.html.erb`, `app/views/projects/show.html.erb`, `spec/requests/provisioning_jobs_spec.rb`, `spec/requests/projects_spec.rb` | Secret reveal remains `SEC-5B.1` |
| `SEC-5B.1` | `P0-M5` | `SEC` | `SEC-5B` | One-time secret reveal cache write path, authorized fetch, masking/copy UX, TTL expiry handling | `UI-5B.1` / `AUTH-4A.2` | `AC-015` / `TEST-015` | `defined` | `landed` | `app/services/provisioning/secret_cache.rb`, `app/services/provisioning/steps/keycloak_client_create.rb`, `app/controllers/provisioning_jobs_controller.rb`, `app/javascript/controllers/provisioning_controller.js`, `spec/services/provisioning/secret_cache_spec.rb`, `spec/requests/provisioning_jobs_spec.rb` | Shared reveal foundation for provisioning-complete OIDC secrets and auth-config secret/PAK follow-up surfaces |
| `UI-5C.1` | `P0-M5` | `UI` | `UI-5C` | OIDC auth config ERB: redirect URIs, post-logout URIs, client secret regeneration entry point | `INTEG-2A.1` / `SEC-5B.1` | `AC-016` / `TEST-016` | `defined` | `landed` | `app/controllers/auth_configs_controller.rb`, `app/views/auth_configs/show.html.erb`, `app/services/auth_configs/`, `app/javascript/controllers/secret_reveal_controller.js`, `app/javascript/controllers/uri_list_controller.js`, `spec/requests/auth_configs_spec.rb` | SAML/OAuth controls remain disabled until `AUTH-6A`; PAK controls now extend the same page via `AUTH-6A.3` |
| `UI-5C.2` | `P0-M5` | `UI` | `UI-5C` | LiteLLM config ERB: models, guardrails, S3 retention, update provisioning redirect | `INTEG-2A.2` / `PROV-2A.1` | `AC-016` / `TEST-016` | `defined` | `landed` | `app/controllers/litellm_configs_controller.rb`, `app/views/litellm_configs/show.html.erb`, `app/views/projects/show.html.erb`, `spec/requests/litellm_configs_spec.rb` | Current scope covers checkbox/retention edit, HTML redirect, and JSON compatibility; auth expansion remains `AUTH-6A.*` |
| `UI-5C.3` | `P0-M5` | `UI` | `UI-5C` | Config version list/show/diff/rollback UI with diagnostics display | `OPS-3A.3` | `AC-016` / `TEST-016` | `defined` | `landed` | `app/controllers/config_versions_controller.rb`, `app/views/config_versions/`, `app/services/config_versions/diff_builder.rb`, `spec/requests/config_versions_spec.rb` | Browser flow reflects current synchronous rollback API and surfaces diagnostics instead of implying a hidden provisioning job |
| `UI-5C.4` | `P0-M5` | `UI` | `UI-5C` | Unified Project configuration edit (§8.5.1): single form combining auth + LiteLLM + metadata, single PATCH triggers single Update provisioning job; introduce `[설정 편집]` CTA on the existing detail pages | `UI-5C.1` / `UI-5C.2` | `AC-024` / `TEST-024` | `defined` | `planned` | `docs/ui-spec.md#851-project-설정-통합-편집--fr-346`, `app/controllers/projects_controller.rb`, `app/views/projects/edit.html.erb`, `app/javascript/controllers/dirty_tracker_controller.js`, `spec/requests/projects_spec.rb` | Backend `Projects::UpdateService` already aggregates dirty_attributes; only `project_update_params` permit + new edit view + parity validation/concurrency banner required. Legacy `auth_config#update` and `litellm_config#update` endpoints remain live in this slice as compatibility surfaces; deprecation is tracked under `UI-5C.5`. |
| `UI-5C.5` | `P0-M5` | `UI` | `UI-5C` | Deprecate legacy `PATCH /auth_config` / `PATCH /litellm_config` write surfaces — redirect browser PATCH to the unified edit page (or return 410 Gone for API), demote `auth_configs/show` and `litellm_configs/show` to read-only views per `ui-spec §8.8/§8.11`, migrate existing request specs | `UI-5C.4` | `AC-024` / `TEST-024` | `defined` | `planned` | `docs/ui-spec.md#88-litellm-config--fr-6-read-only-상세`, `docs/ui-spec.md#811-인증-설정--fr-4-read-only-상세--destructive-액션`, `app/controllers/auth_configs_controller.rb`, `app/controllers/litellm_configs_controller.rb`, `config/routes.rb` | Required to honor the "single writable surface" invariant declared by `UI-5C.4`. Destructive actions (`regenerate_secret`, PAK issue/revoke, auth migration) stay on the auth_config page. |
| `PROV-5C.6` | `P0-M5` | `PROV` | `UI-5C` | Conditional update step seeding + dirty-aware health-check scoping: derive seeded steps from the dirty external subset (skip `keycloak_client_update` for LiteLLM-only updates) and scope `HealthCheck` to only the services whose dirty fields changed so a LiteLLM-only save no longer surfaces unrelated Keycloak/Langfuse warnings | `UI-5C.4` | `AC-024` / `TEST-024` | `defined` | `planned` | `app/services/provisioning/step_seeder.rb`, `app/services/provisioning/steps/health_check.rb`, `spec/services/provisioning/step_seeder_spec.rb` | Today the mutation steps short-circuit on irrelevant fields, but the seeded step list still includes all three update steps and `HealthCheck` runs all three external service probes. Aligns persisted timeline + retry surface + warning blast radius with the dirty subset. |
| `AUTH-6A.1` | `P1-M1` | `AUTH` | `AUTH-6A` | SAML metadata UI, SP metadata URL copy, provisioning coverage | `AUTH-4A.1` / `UI-5C.1` | `AC-017` / `TEST-017` | `defined` | `landed` | `app/controllers/auth_configs_controller.rb`, `app/views/auth_configs/show.html.erb`, `spec/requests/auth_configs_spec.rb` | SP Entity ID + IdP metadata URL displayed; gated on keycloak_client_uuid; 3 new request specs |
| `AUTH-6A.2` | `P1-M1` | `AUTH` | `AUTH-6A` | OAuth/PKCE UI, public-client display, redirect URI validation | `AUTH-4A.1` / `UI-5C.1` | `AC-017` / `TEST-017` | `defined` | `landed` | `app/controllers/auth_configs_controller.rb`, `app/views/auth_configs/show.html.erb`, `app/controllers/projects_controller.rb`, `spec/requests/auth_configs_spec.rb` | OAuth panel with PKCE S256, public client; HTTPS/host/scheme/IPv6 redirect URI validation; 521 specs passing |
| `AUTH-6A.3` | `P1-M1` | `AUTH` | `AUTH-6A` | PAK list/issue/revoke UI with one-time reveal and audit feedback | `AUTH-4A.2` / `SEC-5B.1` | `AC-017` / `TEST-017` | `defined` | `landed` | `app/controllers/project_api_keys_controller.rb`, `app/views/auth_configs/show.html.erb`, `app/services/project_api_keys/reveal_cache.rb`, `spec/requests/project_api_keys_spec.rb`, `spec/requests/auth_configs_spec.rb`, `docs/ui-spec.md#811-인증-설정-편집--fr-4` | Auth-config page now ships PAK list/issue/revoke/reveal flow; SAML/OAuth leaves remain follow-up scope |
| `AUTH-6B.1` | `P1-M3` | `AUTH` | `AUTH-6B` | `project_auth_configs`에 `role`/`state` 컬럼과 partial unique index 추가, 기존 row backfill | `AUTH-6A.1` / `AUTH-6A.2` | `AC-023` / `TEST-023` | `defined` | `planned` | `DEC-005`, `docs/adr/adr-007-auth-type-migration.md` | 1:1 → 1:N binding model; 기존 row는 `role: primary, state: active`로 backfill; PAK 제외 |
| `AUTH-6B.2` | `P1-M3` | `AUTH` | `AUTH-6B` | `auth_binding_add` 프로비저닝 오퍼레이션 — secondary Keycloak client 생성 + Config Server apply | `AUTH-6B.1` | `AC-023` / `TEST-023` | `defined` | `planned` | `docs/adr/adr-007-auth-type-migration.md` | downstream dual-trust operator 확인 체크박스 포함; 기존 step type 재사용 |
| `AUTH-6B.3` | `P1-M3` | `AUTH` | `AUTH-6B` | `auth_binding_promote` 오퍼레이션 — DB role swap + Config Server re-publish (Keycloak 변경 없음) | `AUTH-6B.2` | `AC-023` / `TEST-023` | `defined` | `planned` | `docs/adr/adr-007-auth-type-migration.md` | 완전 가역; 양쪽 클라이언트 Keycloak에 생존 중 |
| `AUTH-6B.4` | `P1-M3` | `AUTH` | `AUTH-6B` | `auth_binding_remove` 오퍼레이션 — retiring Keycloak client 삭제 + DB cleanup | `AUTH-6B.3` | `AC-023` / `TEST-023` | `defined` | `planned` | `docs/adr/adr-007-auth-type-migration.md` | step 2(Keycloak delete) 이후 롤백 불가 — warning-only exception 문서화 |
| `AUTH-6B.5` | `P1-M3` | `AUTH` | `AUTH-6B` | auth migration UI — Add/Promote/Remove 버튼, binding state-aware 어포던스, operator 확인 모달 | `AUTH-6B.2` | `AC-023` / `TEST-023` | `defined` | `planned` | `docs/ui-spec.md`, `docs/adr/adr-007-auth-type-migration.md` | 기존 provisioning timeline UI 재사용; 새 realtime 인프라 불필요 |
| `OPS-7A.1` | `P1-M2` | `OPS` | `OPS-7A` | Production deploy command, smoke checklist, rollback command documented and dry-run accepted | `OPS-3A.1` | `AC-019` / `TEST-019` | `defined` | `planned` | `docs/05_RUNBOOK.md`, `config/deploy.yml`, `.kamal/` | Current runbook marks deploy operation `not_run` |
| `OPS-7A.2` | `P1-M2` | `OPS` | `OPS-7A` | Litestream sidecar/init-restore wiring and restore drill evidence | `OPS-7A.1` | `AC-019` / `TEST-019` | `defined` | `planned` | `docs/01_PRD.md#82-k8s-배포-전략`, `docs/adr/adr-005-sqlite-litestream.md` | Confirms RPO/RTO assumptions |
| `OPS-7A.3` | `P1-M2` | `OPS` | `OPS-7A` | AuditLogsArchiveJob JSONL export to S3 archive prefix and retention deletion | `OPS-3A.1` | `AC-020` / `TEST-020` | `defined` | `planned` | `docs/02_HLD.md#audit-logs`, `docs/current/OPERATIONS.md` | HLD target says audit logs archive after 365 days |
| `OPS-7A.4` | `P1-M2` | `OPS` | `OPS-7A` | ConfigVersion storage policy review: accept permanent retention with monitoring or implement prune job | `OPS-3A.3` | `AC-019` / `TEST-019` | `defined` | `planned` | `docs/02_HLD.md#configversions`, `docs/current/DATA_MODEL.md` | HLD default is permanent retention; prune only if policy changes |
| `OPS-7A.5` | `P1-M2` | `OPS` | `OPS-7A` | Full external config rollback: snapshot Keycloak/Langfuse mutable config and restore it instead of diagnostics-only reporting | `OPS-3A.3` / `INTEG-2A.1` / `INTEG-2A.2` | `AC-022` / `TEST-022` | `defined` | `planned` | `docs/01_PRD.md#fr-8-설정-변경-이력-관리-및-버전-롤백`, `docs/03_RISK_SPIKES.md#spike-002-config-rollback의-외부-리소스-복구-경계` | Current accepted behavior diagnoses non-snapshotted state |
| `PLAY-8A.1` | `P2-M1` | `PLAY` | `PLAY-8A` | Playground routes/controller authorization, model list source, request validation | `UI-5A.4` / `UI-5C.2` | `AC-012` / `TEST-012` | `defined` | `planned` | `docs/01_PRD.md#fr-10-playground-ai-chat`, `docs/02_HLD.md#playground--fr-10` | Project `read`+ only |
| `PLAY-8A.2` | `P2-M1` | `PLAY` | `PLAY-8A` | LiteLLM streaming proxy with timeout, disconnect cancel, per-project concurrency limit, secret redaction | `PLAY-8A.1` | `AC-012` / `TEST-012` | `defined` | `planned` | `docs/02_HLD.md#playground--fr-10` | Uses `ActionController::Live` or documented equivalent |
| `PLAY-8A.3` | `P2-M1` | `PLAY` | `PLAY-8A` | Playground chat UI: streaming transcript, params, guardrail responses, session-only history, JSON export | `PLAY-8A.2` | `AC-012` / `TEST-012` | `defined` | `planned` | `docs/ui-spec.md#810-playground--fr-10-phase-4` | No server-side conversation persistence |
| `PLAY-8A.4` | `P2-M1` | `PLAY` | `PLAY-8A` | Request/response inspector, token/latency/cost display, Langfuse trace links | `PLAY-8A.2` | `AC-012` / `TEST-012` | `defined` | `planned` | `docs/01_PRD.md#fr-10-playground-ai-chat`, `docs/ui-spec.md#810-playground--fr-10-phase-4` | Must not expose secrets in headers/body |
| `ADMIN-8A.1` | `P2-M2` | `ADMIN` | `ADMIN-8A` | Super-admin dashboard scope decision: metrics, service health, manual intervention queue, release gating | `Q-003` | `AC-021` / `TEST-021` | `defined` | `planned` | `docs/01_PRD.md#66-관측성`, `docs/07_QUESTIONS_REGISTER.md#q-003-super-admin-dashboard의-최소-범위는-무엇인가` | Decision before implementation |
| `ADMIN-8A.2` | `P2-M2` | `ADMIN` | `ADMIN-8A` | Super-admin dashboard UI/API: all orgs/projects status, external service health, failed job links | `ADMIN-8A.1` / `OPS-7A.1` | `AC-021` / `TEST-021` | `defined` | `planned` | `docs/01_PRD.md#66-관측성`, `docs/ui-spec.md` | Hidden unless `super_admin` |
| `ADMIN-8A.3` | `P2-M2` | `ADMIN` | `ADMIN-8A` | Manual intervention workflow for `failed`/`rollback_failed` jobs with runbook links and audit trail | `ADMIN-8A.2` / `OPS-7A.3` | `AC-021` / `TEST-021` | `defined` | `planned` | `docs/05_RUNBOOK.md`, `docs/01_PRD.md#fr-73-프로비저닝-현황-화면` | Complements per-job retry UI |

## Leaf Coverage

| Source scope | Leaf slices |
|---|---|
| FR-1 Organization CRUD | `CORE-1A.1`, `CORE-5A.1`, `CORE-5A.3`, `UI-5A.2` |
| FR-2 RBAC / members / user assignment | `CORE-1A.2`, `CORE-5A.2`, `UI-5A.1`, `UI-5A.3` |
| FR-3 Project CRUD | `CORE-1A.3`, `UI-5A.4`, `UI-5B.1`, `UI-5B.3`, `UI-5C.4` |
| FR-4 Auth automation / SAML / OAuth / PAK | `INTEG-2A.1`, `AUTH-4A.1`, `AUTH-4A.2`, `UI-5C.1`, `UI-5C.4`, `AUTH-6A.1`, `AUTH-6A.2`, `AUTH-6A.3` |
| FR-4 (migration) auth_type seamless change | `AUTH-6B.1`, `AUTH-6B.2`, `AUTH-6B.3`, `AUTH-6B.4`, `AUTH-6B.5` |
| FR-5 Langfuse project / keys | `INTEG-2A.2`, `OPS-3A.2`, `CORE-5A.1`, `CORE-5A.3` |
| FR-6 LiteLLM config | `INTEG-2A.2`, `UI-5C.2`, `UI-5C.4`, `OPS-3A.2` |
| FR-7 Provisioning pipeline/status | `PROV-2A.1`, `PROV-2A.2`, `UI-2B.1`, `UI-5B.1`, `UI-5B.2`, `UI-5B.3`, `SEC-5B.1` |
| FR-8 Config history/rollback | `OPS-3A.3`, `UI-5C.3`, `OPS-7A.4`, `OPS-7A.5` |
| FR-9 Health/check consistency | `OPS-3A.2`, `ADMIN-8A.2` |
| FR-10 Playground | `PLAY-8A.1`, `PLAY-8A.2`, `PLAY-8A.3`, `PLAY-8A.4` |
| HLD secret reveal target | `SEC-5B.1` |
| HLD deployment/Litestream restore target | `OPS-7A.1`, `OPS-7A.2` |
| HLD audit archive target | `OPS-7A.3` |
| PRD/admin observability target | `ADMIN-8A.1`, `ADMIN-8A.2`, `ADMIN-8A.3` |

## Gates / Acceptance

- Gate definition은 `docs/06_ACCEPTANCE_TESTS.md`에 둔다.
- Automated check는 `docs/current/TESTING.md`에 둔다.
- Slice는 gate가 `passing`이 되기 전에 `landed`일 수 있다.
- Milestone은 required gate가 `passing`이거나 명시적으로 `waived`일 때만 `accepted`가 된다.

## Traceability

- Completed slices should have a row in `docs/09_TRACEABILITY_MATRIX.md`.
- Planned slices that close PRD / HLD / UI coverage gaps should also have a trace row,
  so leaf completeness can be reviewed before implementation starts.
- Link slices to the relevant Q / DEC / ADR, REQ / NFR, AC / TEST, and milestone.
- Trace row를 backlog처럼 쓰지 않는다. 중요한 연결 경로를 기록하는 용도다.

## Dependencies

- Keycloak Admin API: 인증 client 생성/수정/삭제, 사용자 검색
- Langfuse tRPC API: Organization/Project 생성과 SDK key 발급
- Config Server Admin API: LiteLLM config/app registry write path
- SQLite + SolidQueue + SolidCable: app runtime persistence and jobs

## Risks (Open)

- `Q-003`: super-admin dashboard scope is not decided yet, so `ADMIN-8A.1` must run before dashboard implementation.
- Deployment command, rollback procedure, and Litestream restore are not accepted until `OPS-7A.1` / `OPS-7A.2` pass.
- Full Keycloak/Langfuse rollback remains diagnostics-only until `OPS-7A.5` passes.
- PAK one-time reveal UI is landed in `AUTH-6A.3`; `SEC-5B.1` remains the shared reveal/cache foundation.

## Capacity / Timeline

- 인원: Platform TG / AI-assisted implementation
- 주당 가용 시간: anchor missing
- 예상 완료: `P0-M5` core product UI and provisioning detail after P0-M4 backend/API closure
