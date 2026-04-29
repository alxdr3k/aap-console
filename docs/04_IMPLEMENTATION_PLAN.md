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
| Slice / Task | 커밋 가능한 구현 단위 | `PROV-3A.1` | PR / commit / issue와 연결 가능한 크기 |
| Gate | 검증 / acceptance 기준 | `AC-009` / `TEST-020` | `06_ACCEPTANCE_TESTS.md` 또는 spec 위치 |
| Evidence | 완료를 뒷받침하는 근거 | code, tests, docs | 본문 복제 대신 링크 / ID |

## Thin-doc Boundary

- `docs/04_IMPLEMENTATION_PLAN.md`가 roadmap / status ledger의 canonical 위치다.
- `docs/context/current-state.md`는 현재 milestone / track / phase / slice만 짧게 요약한다.
- `docs/current/`는 구현된 상태를 빠르게 찾는 navigation layer다.
- 미래 roadmap, phase inventory, 상세 backlog를 `docs/current/`에 복제하지 않는다.
- Runtime, schema, operation, test command가 바뀌면 해당 `docs/current/` 문서를 같이 갱신한다.

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
| `P0-M2` | OIDC, Langfuse, LiteLLM, Config Server 기본 프로비저닝 경로가 동작한다 | 2026-04-25 | `accepted` | `AC-004` / `AC-005` / `AC-006` | `app/services/provisioning/`, `spec/services/provisioning/` | Health check 상세 검증은 `P0-M3` |
| `P0-M3` | 운영 안정성 release gate를 닫는다 |  | `in_progress` | `AC-007` / `AC-008` / `AC-009` | `docs/03_RISK_SPIKES.md` | Health check, config rollback, 통합 smoke 남음 |
| `P0-M4` | SAML/OAuth/PAK 범위를 확정하고 구현한다 |  | `planned` | `AC-010` / `AC-011` | `docs/07_QUESTIONS_REGISTER.md#q-001` | MVP 범위 결정 필요 |
| `P0-M5` | Playground를 제품 화면에 노출한다 |  | `deferred` | `AC-012` | `docs/01_PRD.md#fr-10-playground-ai-chat`, `docs/ui-spec.md#810-playground--fr-10-phase-4` | Phase 4 |
| `DOC-M1` | Boilerplate 문서 체계가 repo에 적용된다 | 2026-04-29 | `landed` | `AC-DOC-001` | `AGENTS.md`, `docs/context/current-state.md`, `docs/current/`, `.github/pull_request_template.md` | PR/merge acceptance 남음 |

## Tracks

| Track | Purpose | Active phase | Status | Notes |
|---|---|---|---|---|
| `DOC` | Boilerplate migration, source-of-truth 정리, agent guidance | `DOC-1A` | `landed` | 최신 roadmap taxonomy와 maintenance drift workflow 반영 |
| `CORE` | Organization, Project, member, RBAC core | `CORE-1A` | `accepted` | CRUD와 권한 guard 구현됨 |
| `PROV` | Provisioning pipeline, step orchestration, rollback | `PROV-3A` | `in_progress` | 기본 경로 accepted, 운영 안정성 보강 중 |
| `INTEG` | Keycloak, Langfuse, Config Server client integration | `INTEG-2A` | `accepted` | 테스트는 WebMock 기반 |
| `UI` | Hotwire 화면과 realtime 진행 상태 | `UI-2B` | `landed` | Provisioning detail UI는 부분 구현 |
| `AUTH` | 인증 방식 확장과 PAK | `AUTH-4A` | `planned` | OIDC 외 범위 결정 필요 |
| `OPS` | Runbook, deployment, health check, rollback operation | `OPS-3A` | `in_progress` | Release gate 잔여 항목 |
| `PLAY` | Playground AI chat | `PLAY-4A` | `deferred` | P0-M5 이후 |

## Phases / Slices

| Slice | Milestone | Track | Phase | Goal | Depends | Gate | Gate status | Status | Evidence | Next |
|---|---|---|---|---|---|---|---|---|---|---|
| `DOC-1A.1` | `DOC-M1` | `DOC` | `DOC-1A` | Boilerplate skeleton과 numbered PRD/HLD path 도입 |  | `AC-DOC-001` | `passing` | `landed` | `AGENTS.md`, `docs/00_PROJECT_DELIVERY_PLAYBOOK.md`, `docs/01_PRD.md`, `docs/02_HLD.md` | PR review |
| `DOC-1A.2` | `DOC-M1` | `DOC` | `DOC-1A` | Roadmap/status ledger를 최신 taxonomy로 작성 | `DOC-1A.1` | `AC-DOC-001` | `passing` | `landed` | `docs/04_IMPLEMENTATION_PLAN.md` | PR review |
| `DOC-1A.3` | `DOC-M1` | `DOC` | `DOC-1A` | Current-state/current docs와 agent guidance 최신화 | `DOC-1A.2` | `AC-DOC-001` | `passing` | `landed` | `docs/context/current-state.md`, `docs/current/`, `CLAUDE.md` | PR review |
| `DOC-1A.4` | `DOC-M1` | `DOC` | `DOC-1A` | Maintenance drift workflow를 PR template과 doc-freshness 예시에 반영 | `DOC-1A.3` | `AC-DOC-001` | `passing` | `landed` | `.github/pull_request_template.md`, `.github/workflows/doc-freshness.yml.example`, `docs/DOCUMENTATION.md` | PR review |
| `CORE-1A.1` | `P0-M1` | `CORE` | `CORE-1A` | Organization CRUD |  | `AC-001` / `TEST-001` | `passing` | `app/controllers/organizations_controller.rb`, `spec/requests/organizations_spec.rb` | 유지보수 |
| `CORE-1A.2` | `P0-M1` | `CORE` | `CORE-1A` | Member/RBAC, last-admin/self-demotion guard | `CORE-1A.1` | `AC-002` / `TEST-002` | `passing` | `app/models/authorization.rb`, `spec/requests/members_spec.rb`, `spec/models/authorization_spec.rb` | 유지보수 |
| `CORE-1A.3` | `P0-M1` | `CORE` | `CORE-1A` | Project CRUD와 App ID lifecycle | `CORE-1A.1` | `AC-003` / `TEST-003` | `passing` | `app/services/projects/`, `spec/requests/projects_spec.rb` | 유지보수 |
| `PROV-2A.1` | `P0-M2` | `PROV` | `PROV-2A` | Create/update/delete step seeding | `CORE-1A.3` | `AC-006` / `TEST-006` | `passing` | `app/services/provisioning/step_seeder.rb`, `spec/services/provisioning/step_seeder_spec.rb` | 유지보수 |
| `PROV-2A.2` | `P0-M2` | `PROV` | `PROV-2A` | Parallel execution, retry, rollback status transitions | `PROV-2A.1` | `AC-006` / `TEST-007` | `passing` | `app/services/provisioning/orchestrator.rb`, `step_runner.rb`, `rollback_runner.rb`, related specs | 유지보수 |
| `INTEG-2A.1` | `P0-M2` | `INTEG` | `INTEG-2A` | OIDC Keycloak client provisioning | `PROV-2A.1` | `AC-004` / `TEST-004` | `passing` | `app/services/provisioning/steps/keycloak_client_create.rb`, `spec/services/provisioning/steps/keycloak_client_create_spec.rb` | SAML/OAuth는 `AUTH-4A` |
| `INTEG-2A.2` | `P0-M2` | `INTEG` | `INTEG-2A` | Langfuse project와 Config Server apply | `PROV-2A.1` | `AC-005` / `TEST-005` | `passing` | `app/clients/langfuse_client.rb`, `app/clients/config_server_client.rb`, related specs | 유지보수 |
| `UI-2B.1` | `P0-M3` | `UI` | `UI-2B` | ActionCable provisioning stream | `PROV-2A.2` | `AC-007` / `TEST-008` | `passing` | `app/channels/provisioning_channel.rb`, `spec/channels/provisioning_channel_spec.rb` | ERB timeline/retry UX 보강 |
| `OPS-3A.1` | `P0-M3` | `OPS` | `OPS-3A` | 외부 리뷰어 피드백 통합 smoke 재검증 | `P0-M2` | `AC-008` | `not_run` | `docs/06_ACCEPTANCE_TESTS.md` | Smoke 절차 실행 |
| `OPS-3A.2` | `P0-M3` | `OPS` | `OPS-3A` | Health check 상세 assertion 구현 | `PROV-2A.2` | `AC-009` | `defined` | `app/services/provisioning/steps/health_check.rb` | `SPIKE-001` 결과 반영 |
| `OPS-3A.3` | `P0-M3` | `OPS` | `OPS-3A` | Config rollback의 Keycloak/Langfuse 복구 경로 완결 | `INTEG-2A.2` | `AC-010` | `defined` | `app/controllers/config_versions_controller.rb`, `spec/requests/config_versions_spec.rb` | `SPIKE-002` 결과 반영 |
| `AUTH-4A.1` | `P0-M4` | `AUTH` | `AUTH-4A` | SAML/OAuth 지원 범위 결정 및 구현 | `Q-001` | `AC-011` | `defined` | `docs/07_QUESTIONS_REGISTER.md#q-001` | MVP 범위 결정 |
| `AUTH-4A.2` | `P0-M4` | `AUTH` | `AUTH-4A` | PAK 발급/폐기/검증 API와 UI | `Q-001` | `AC-011` | `defined` | `app/models/project_api_key.rb`, `spec/factories/project_api_keys.rb` | Controller/service 추가 여부 결정 |
| `PLAY-4A.1` | `P0-M5` | `PLAY` | `PLAY-4A` | Playground SSE chat 화면 | `P0-M4` | `AC-012` | `defined` | `docs/01_PRD.md#fr-10-playground-ai-chat`, `docs/ui-spec.md#810-playground--fr-10-phase-4` | P0-M4 이후 착수 |

## Gates / Acceptance

- Gate definition은 `docs/06_ACCEPTANCE_TESTS.md`에 둔다.
- Automated check는 `docs/current/TESTING.md`에 둔다.
- Slice는 gate가 `passing`이 되기 전에 `landed`일 수 있다.
- Milestone은 required gate가 `passing`이거나 명시적으로 `waived`일 때만 `accepted`가 된다.

## Traceability

- Completed slices should have a row in `docs/09_TRACEABILITY_MATRIX.md`.
- Link slices to the relevant Q / DEC / ADR, REQ / NFR, AC / TEST, and milestone.
- Trace row를 backlog처럼 쓰지 않는다. 중요한 연결 경로를 기록하는 용도다.

## Dependencies

- Keycloak Admin API: 인증 client 생성/수정/삭제, 사용자 검색
- Langfuse tRPC API: Organization/Project 생성과 SDK key 발급
- Config Server Admin API: LiteLLM config/app registry write path
- SQLite + SolidQueue + SolidCable: app runtime persistence and jobs

## Risks (Open)

- `SPIKE-001`: Health check가 실제 외부 정합성을 검증하는 수준인지 확인 필요
- `SPIKE-002`: Config rollback이 Console snapshot만이 아니라 Keycloak/Langfuse 복구까지 닫히는지 확인 필요
- `SPIKE-003`: SAML/OAuth/PAK가 MVP인지 Phase 4인지 제품 결정 필요

## Capacity / Timeline

- 인원: Platform TG / AI-assisted implementation
- 주당 가용 시간: anchor missing
- 예상 완료: `P0-M3` gate closure after smoke, health check, rollback slices
