# AAP Console — Current State

새 AI/human session의 첫 read 문서다. 전체 history가 아니라 압축된 현재 운영
상태만 담는다.

## Product / Project

AAP Console은 Organization / Project 온보딩을 위한 Rails 8 기반 self-service
management console이다. Keycloak, Langfuse, Config Server를 통한 LiteLLM config,
SolidQueue provisioning job, ActionCable status stream을 오케스트레이션한다.
Importmap-backed Turbo/Stimulus baseline과 application shell이 있고, product UI는
`UI-5A.*`부터 단계적으로 채우는 중이다.

## Current Roadmap Position

- current milestone: `P0-M5` core product UI / provisioning detail / FR-1~3 completion
- recently accepted: `DOC-M1` boilerplate migration via PR #24 on 2026-04-29
- active tracks: `UI`, `AUTH`
- active phases: `UI-5A`, `UI-5B`, `UI-5C`, `AUTH-6A`
- active slices: `CORE-5A.1`, `CORE-5A.2`, `CORE-5A.3`, `UI-5A.1`, `UI-5A.2`, `UI-5A.3`, `UI-5A.4`, `UI-5B.1`, `UI-5B.2`, `UI-5B.3`, `SEC-5B.1`, `UI-5C.1`, `UI-5C.2`, `UI-5C.3`, and `AUTH-6A.3` landed; no additional ready auth leaf is open yet
- last accepted gate: `AC-011` SAML/OAuth/PAK backend/API gate
- last passing doc gate: `AC-DOC-001`
- next gates: `AC-014`, `AC-015`, `AC-016`, `AC-017`
- canonical ledger: `docs/04_IMPLEMENTATION_PLAN.md`

## Implemented

- Organization CRUD, Project CRUD, membership/RBAC guard path.
- Project create/update/delete용 provisioning job seeding.
- Parallel step group, scheduled retry, rollback, warning step handling을 가진 provisioning orchestrator.
- Keycloak OIDC client path, Langfuse project create path, Config Server apply/delete path.
- Config version browser page, inline diff/detail view, and rollback diagnostics UI. `POST /config_versions/:id/rollback`는 Config Server revert, rollback `ConfigVersion` 기록, Keycloak/Langfuse diagnostics를 반환하고 browser flow는 같은 history page로 되돌린다.
- Authorization check와 JSON `step_update` / `job_completed` payload를 포함한 ActionCable `ProvisioningChannel`.
- Core request, model, service, job, client, channel path에 대한 RSpec/WebMock coverage.
- `OPS-3A.1` release smoke validation accepted on 2026-04-29.
- `OPS-3A.2` health check service-specific assertions for Keycloak, LiteLLM Config Server, and Langfuse.
- `OPS-3A.3` config rollback external restore/diagnostics path.
- `OPS-3A.4` provisioning job retention cleanup for old successful terminal jobs.
- `AUTH-4A.2` PAK issue/revoke/verify API and inbound verification endpoint.
- `AUTH-4A.1` SAML/OAuth backend provisioning coverage for Keycloak client create.
- `Q-001` resolved by `DEC-003`: auth expansion gate is backend/API; UI follow-up is non-gating.
- `Q-002` resolved by `DEC-004`: provisioning detail UI is `P0-M5` product UI work, not a reopened `P0-M3` gate.
- `CORE-5A.1` landed: organization creation supports a designated initial admin, organization update uses a service object, and Langfuse org name sync is covered.
- `CORE-5A.2` landed: member create validates/pre-assigns users through Keycloak, member list can hydrate Keycloak user details, project permission grant/update/revoke API is present, and member/project-permission audit logs are covered.
- `CORE-5A.3` landed: organization delete starts/observes child project delete jobs, records pending project/job summaries, and finalizes Langfuse/Console org deletion once all projects are deleted.
- `UI-5A.1` landed: importmap/Turbo/Stimulus asset baseline, application shell, navigation, flash UI, Organization index/detail shell empty states, and super_admin create affordance are present.
- `UI-5A.2` landed: Organization list/detail/new/edit ERB pages share a form partial, preserve JSON defaults for API-like requests, and render role-aware edit/delete actions and HTML 404/error states.
- `UI-5A.3` landed: member management ERB renders Keycloak-hydrated member rows, pending badges, member add/update/remove forms, and project permission grant/update/revoke controls while keeping JSON API compatibility.
- `UI-5A.4` landed: Project list/detail/new ERB pages render role-aware actions, OIDC-only create form controls, recent config/provisioning summaries, metadata update, delete provisioning redirects, and JSON compatibility.
- `UI-5B.1` landed: provisioning job show ERB renders persisted create/update/delete timeline state, warnings/errors, Project/Organization navigation, and JSON compatibility.
- `UI-5B.2` landed: provisioning show page subscribes to `ProvisioningChannel`, replaces individual step partials, and keeps JSON polling fallback for reconnect/refresh.
- `UI-5B.3` landed: retryable provisioning jobs show manual-intervention controls, HTML retry redirects, retry conflict protection, and Project detail active-job warning banners.
- `SEC-5B.1` landed: OIDC client secrets are written only to 10-minute `Rails.cache`, served by authorized completed-job fetch, and displayed with masked/copy/confirm UX on the provisioning page.
- `UI-5C.1` landed: auth config browser page renders OIDC redirect/post-logout URI editing, write-gated Client Secret regeneration with masked/copy/confirm reveal, project-detail link-through, and disabled SAML/OAuth placeholders while keeping JSON compatibility.
- `UI-5C.2` landed: LiteLLM config browser page renders model/guardrail/S3 retention editing, read-only summary for readers, HTML provisioning redirects, basic form validation, and JSON compatibility.
- `UI-5C.3` landed: config-version browser page renders version history, Turbo Frame detail/diff view, synchronous rollback entry with diagnostics banner, Project-detail link-through, and JSON compatibility.
- `AUTH-6A.3` landed: auth-config browser page now renders Project API Key list, writer-only issue/revoke actions, one-time reveal with 10-minute project-scoped cache, and JSON compatibility for existing PAK API clients.

## Planned

- `P0-M5`: core server-rendered UI, provisioning detail, and secret reveal.
- `P1-M1`: SAML/OAuth/PAK product UI. `AUTH-6A.1` landed; `AUTH-6A.2` landed. P1-M1 complete.
- `P1-M2`: production deploy/rollback/Litestream restore evidence and audit archive.
- `P1-M3`: auth_type seamless migration (AUTH-6B dual-client flow). Planned after AUTH-6A.
- `P2-M1`: Playground. Deferred until after OPS stabilization (P1-M2).
- `P2-M2`: super-admin operations dashboard.

## Explicit Non-goals

- Test나 agent command에서 real external API를 호출하지 않는다.
- DB, log, source, docs에 plaintext secret을 남기지 않는다.
- Console code/docs에 Config Server storage/propagation internals를 넣지 않는다.
- 이 파일에 전체 roadmap inventory를 복제하지 않는다. `docs/04_IMPLEMENTATION_PLAN.md`를 사용한다.

## Current Priorities

1. `OPS-7A.*` (P1-M2) ready 조건 확인 — 배포/운영/Litestream 복구 절차 문서화.
2. `AUTH-6B.1` 착수 여부 결정 — AUTH-6A 완료됨, `project_auth_configs` 마이그레이션 모델 설계 검토.
3. `PLAY-8A.*` (P2-M1) — P1-M2 OPS 안정화 이후.

## Next Review Candidates

- `OPS-7A.1` (planned): Production deploy command, smoke checklist, rollback documented. P1-M2 착수 결정 필요.
- `AUTH-6B.1` (planned): `project_auth_configs` role/state 컬럼 + partial index + backfill. AUTH-6A 완료됨; AUTH-6B 착수 여부 사용자 결정 필요.
- `PLAY-8A.1` (planned): Playground routes/controller. P1-M2 (OPS) 완료 후 착수.

## Current Risks / Unknowns

- `Q-003`: super-admin dashboard scope.
- Deployment command, rollback procedure, and Litestream restore are not accepted until `OPS-7A.1` / `OPS-7A.2`.
- Full Keycloak/Langfuse config rollback is diagnostics-only until `OPS-7A.5`.
- `AUTH-6B` session 처리: 자연 만료 채택 (ADR-007). 미결 사항 없음.
- `AUTH-6B` 착수 여부: AUTH-6A 완료됨. AUTH-6B.1 착수를 위한 사용자 결정 필요.

## Current Validation

- Acceptance gates: `docs/06_ACCEPTANCE_TESTS.md`
- Test command source: `docs/current/TESTING.md`
- Current known open gates: `AC-012`, `AC-014`~`AC-017`, `AC-019`~`AC-022`

## Needs Audit

- `docs/implementation-status.md`는 legacy pointer이며 다시 canonical status가 되면 안 된다.
- Deployment command와 rollback procedure는 아직 검증되지 않았다.

## Links

- PRD: `docs/01_PRD.md`
- HLD: `docs/02_HLD.md`
- Roadmap / status ledger: `docs/04_IMPLEMENTATION_PLAN.md`
- Acceptance tests: `docs/06_ACCEPTANCE_TESTS.md`
- Questions: `docs/07_QUESTIONS_REGISTER.md`
- Decisions: `docs/08_DECISION_REGISTER.md`
- ADRs: `docs/adr/`

---

규칙:

- 짧게 유지한다.
- 전체 history를 누적하지 않는다.
- 전체 roadmap / phase / slice ledger를 복제하지 않는다.
- historical reasoning이 필요하면 ADR/discovery/archive로 링크한다.
- 길어지면 압축한다.
