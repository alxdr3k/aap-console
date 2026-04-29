# AAP Console — Traceability Matrix

Question, decision, requirement, acceptance gate, test, slice를 연결한다.

## Matrix

| TRACE-ID | Question | Decision / ADR | Requirement | AC / Test | Slice | Notes |
|---|---|---|---|---|---|---|
| `TRACE-001` |  | ADR-004 | FR-2 | `AC-002` / `TEST-002` | `CORE-1A.2` | Authn/Authz separation and Console DB RBAC |
| `TRACE-002` |  | ADR-001, ADR-003 | FR-7.1 / FR-7.2 | `AC-006` / `TEST-006` / `TEST-007` | `PROV-2A.1`, `PROV-2A.2` | Rails saga provisioning |
| `TRACE-003` |  | ADR-002 | FR-5 | `AC-005` / `TEST-005` | `INTEG-2A.2` | Langfuse tRPC integration |
| `TRACE-004` |  | ADR-005 | NFR availability / persistence | `AC-008` | `OPS-3A.1` | SQLite + Litestream operational gate |
| `TRACE-005` |  | ADR-006 | UI / realtime | `AC-007` / `TEST-008` | `UI-2B.1` | ActionCable JSON stream landed; Hotwire UI target remains open |
| `TRACE-006` | `Q-001` | pending | FR-4 | `AC-011` | `AUTH-4A.1`, `AUTH-4A.2` | SAML/OAuth/PAK scope decision |
| `TRACE-007` |  | `DEC-001` | DOC-M1 | `AC-DOC-001` | `DOC-1A.2`, `DOC-1A.3`, `DOC-1A.4` | Roadmap/status taxonomy and maintenance drift workflow migration |
| `TRACE-008` |  | `DEC-002` | DOC-M1 | `AC-DOC-001` | `DOC-1A.1` | Numbered PRD/HLD canonical paths |
| `TRACE-009` |  | pending | FR-9 | `AC-009` / `TEST-009` | `OPS-3A.2` | Health check verifies Keycloak, LiteLLM Config Server, and Langfuse read paths |
| `TRACE-010` |  | pending | FR-8 | `AC-010` / `TEST-010` | `OPS-3A.3` | Config rollback restores Config Server and diagnoses non-snapshotted Keycloak/Langfuse state |
| `TRACE-011` |  |  | OPS retention | `AC-013` / `TEST-013` | `OPS-3A.4` | Deletes successful terminal provisioning jobs after retention while preserving failed/manual-intervention records |

## Invariants

- 모든 `must` REQ는 최소 한 개의 AC를 가져야 한다.
- 모든 accepted DEC/ADR은 영향받는 REQ/HLD/Runbook을 갖는다.
- 모든 완료 slice는 적어도 하나의 TRACE row와 연결된다.

## Gaps

- `AC-011`, `AC-012`는 아직 passing gate가 아니다.
- `Q-001`, `Q-002`는 decision으로 승격되지 않았다.
