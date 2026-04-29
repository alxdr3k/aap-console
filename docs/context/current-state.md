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
- active tracks: `UI`, `SEC`
- active phases: `UI-5A`, `UI-5B`, `UI-5C`, `SEC-5B`
- active slices: `CORE-5A.1`, `CORE-5A.2`, `CORE-5A.3`, and `UI-5A.1` landed; next candidates are `UI-5A.2`, `UI-5A.3`, `UI-5A.4`
- last accepted gate: `AC-011` SAML/OAuth/PAK backend/API gate
- last passing doc gate: `AC-DOC-001`
- next gates: `AC-014`, `AC-015`, `AC-016`
- canonical ledger: `docs/04_IMPLEMENTATION_PLAN.md`

## Implemented

- Organization CRUD, Project CRUD, membership/RBAC guard path.
- Project create/update/delete용 provisioning job seeding.
- Parallel step group, scheduled retry, rollback, warning step handling을 가진 provisioning orchestrator.
- Keycloak OIDC client path, Langfuse project create path, Config Server apply/delete path.
- Config version listing과 rollback entry point. `POST /config_versions/:id/rollback`는 Config Server revert, rollback `ConfigVersion` 기록, Keycloak/Langfuse diagnostics를 반환한다.
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

## Planned

- `P0-M5`: core server-rendered UI, provisioning detail, and secret reveal.
- `P1-M1`: SAML/OAuth/PAK product UI.
- `P1-M2`: production deploy/rollback/Litestream restore evidence and audit archive.
- `P2-M1`: Playground.
- `P2-M2`: super-admin operations dashboard.

## Explicit Non-goals

- Test나 agent command에서 real external API를 호출하지 않는다.
- DB, log, source, docs에 plaintext secret을 남기지 않는다.
- Console code/docs에 Config Server storage/propagation internals를 넣지 않는다.
- 이 파일에 전체 roadmap inventory를 복제하지 않는다. `docs/04_IMPLEMENTATION_PLAN.md`를 사용한다.

## Current Priorities

1. `UI-5A.2`~`UI-5A.4`로 Organization detail, member management, Project pages를 구현한다.
2. `UI-5B.*` / `SEC-5B.1`로 provisioning detail/secret reveal을 구현한다.
3. `UI-5C.*`로 auth/LiteLLM/config-version UI를 제품화한다.

## Current Risks / Unknowns

- `Q-003`: super-admin dashboard scope.
- Deployment command, rollback procedure, and Litestream restore are not accepted until `OPS-7A.1` / `OPS-7A.2`.
- `ProvisioningJobsController#secrets` can read cache, but provisioning steps do not write the one-time secret cache yet.
- Full Keycloak/Langfuse config rollback is diagnostics-only until `OPS-7A.5`.

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
