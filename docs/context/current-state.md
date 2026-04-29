# AAP Console — Current State

새 AI/human session의 첫 read 문서다. 전체 history가 아니라 압축된 현재 운영
상태만 담는다.

## Product / Project

AAP Console은 Organization / Project 온보딩을 위한 Rails 8 기반 self-service
management console이다. Keycloak, Langfuse, Config Server를 통한 LiteLLM config,
SolidQueue provisioning job, ActionCable status stream을 오케스트레이션한다.
Hotwire는 ADR-006의 UI target architecture지만, 현재 repo에는 Turbo/Stimulus wiring
없이 minimal ERB/API surface만 있다.

## Current Roadmap Position

- current milestone: `P0-M4` SAML/OAuth/PAK scope and implementation
- recently accepted: `DOC-M1` boilerplate migration via PR #24 on 2026-04-29
- active tracks: `AUTH`
- active phase: `AUTH-4A`
- active slice: `AUTH-4A.1`
- last accepted gate: `AC-013` provisioning job retention cleanup
- last passing doc gate: `AC-DOC-001`
- next gate: `AC-011`
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

## Planned

- `UI-2B`: Hotwire/ERB provisioning timeline and retry UX.
- `AUTH-4A`: SAML/OAuth scope decision and PAK UI follow-up.
- `PLAY-4A`: auth/ops maturity 이후 Playground.

## Explicit Non-goals

- Test나 agent command에서 real external API를 호출하지 않는다.
- DB, log, source, docs에 plaintext secret을 남기지 않는다.
- Console code/docs에 Config Server storage/propagation internals를 넣지 않는다.
- 이 파일에 전체 roadmap inventory를 복제하지 않는다. `docs/04_IMPLEMENTATION_PLAN.md`를 사용한다.

## Current Priorities

1. `Q-001`의 SAML/OAuth MVP 범위를 결정.
2. `AC-011` 잔여 범위(SAML/OAuth, PAK UI)를 구현하거나 명시적으로 defer.

## Current Risks / Unknowns

- `Q-001`: SAML/OAuth MVP scope.
- `Q-002`: provisioning detail UI release gate.

## Current Validation

- Acceptance gates: `docs/06_ACCEPTANCE_TESTS.md`
- Test command source: `docs/current/TESTING.md`
- Current known open gates: `AC-011`, `AC-012`

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
