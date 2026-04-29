# AAP Console — Current State

새 AI/human session의 첫 read 문서다. 전체 history가 아니라 압축된 현재 운영
상태만 담는다.

## Product / Project

AAP Console은 Organization / Project 온보딩을 위한 Rails 8 + Hotwire 기반
self-service management console이다. Keycloak, Langfuse, Config Server를 통한
LiteLLM config, SolidQueue provisioning job, ActionCable status stream을
오케스트레이션한다.

## Current Roadmap Position

- current milestone: `P0-M3` 운영 안정성 release gate, plus `DOC-M1` boilerplate migration landed on the working branch
- active tracks: `DOC`, `PROV`, `OPS`, `UI`
- active phase: `DOC-1A`, `OPS-3A`
- active slice: `DOC-1A.1` / `DOC-1A.2` / `DOC-1A.3` / `DOC-1A.4`
- last accepted gate: `AC-006` provisioning saga core, `AC-007` ActionCable authorization/broadcast path
- last passing doc gate: `AC-DOC-001`
- next gate: `AC-008`, `AC-009`, `AC-010`
- canonical ledger: `docs/04_IMPLEMENTATION_PLAN.md`

## Implemented

- Organization CRUD, Project CRUD, membership/RBAC guard path.
- Project create/update/delete용 provisioning job seeding.
- Parallel step group, scheduled retry, rollback, warning step handling을 가진 provisioning orchestrator.
- Keycloak OIDC client path, Langfuse project create path, Config Server apply/delete path.
- Config version listing과 rollback entry point.
- Authorization check를 포함한 ActionCable `ProvisioningChannel`.
- Core request, model, service, job, client, channel path에 대한 RSpec/WebMock coverage.

## Planned

- `OPS-3A.1`: release gate용 full smoke validation.
- `OPS-3A.2`: health check service-specific assertion.
- `OPS-3A.3`: config rollback external restore path.
- `AUTH-4A`: SAML/OAuth/PAK scope decision and implementation.
- `PLAY-4A`: auth/ops maturity 이후 Playground.

## Explicit Non-goals

- Test나 agent command에서 real external API를 호출하지 않는다.
- DB, log, source, docs에 plaintext secret을 남기지 않는다.
- Console code/docs에 Config Server storage/propagation internals를 넣지 않는다.
- 이 파일에 전체 roadmap inventory를 복제하지 않는다. `docs/04_IMPLEMENTATION_PLAN.md`를 사용한다.

## Current Priorities

1. Boilerplate migration, maintenance drift workflow, stale guidance cleanup 마무리.
2. `docs/current/TESTING.md`의 release smoke check 실행.
3. `FR-9` health check와 `FR-8` rollback gap을 닫거나 명시적으로 defer.

## Current Risks / Unknowns

- `SPIKE-001`: health check assertion depth.
- `SPIKE-002`: config rollback external restore boundary.
- `Q-001`: SAML/OAuth/PAK MVP scope.
- `Q-002`: provisioning detail UI release gate.

## Current Validation

- Acceptance gates: `docs/06_ACCEPTANCE_TESTS.md`
- Test command source: `docs/current/TESTING.md`
- Current known open gates: `AC-008`, `AC-009`, `AC-010`, `AC-011`, `AC-012`

## Needs Audit

- `docs/implementation-status.md`는 legacy pointer이며 다시 canonical status가 되면 안 된다.
- Deployment command와 rollback procedure는 아직 검증되지 않았다.
- Health check와 config rollback release gate가 열려 있다.

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
