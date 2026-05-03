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
| `TRACE-006` | `Q-001` | `DEC-003` | FR-4 | `AC-011` / `TEST-011A` / `TEST-011B` | `AUTH-4A.1`, `AUTH-4A.2` | SAML/OAuth/PAK backend/API gate accepted; UI follow-up deferred |
| `TRACE-007` |  | `DEC-001` | DOC-M1 | `AC-DOC-001` | `DOC-1A.2`, `DOC-1A.3`, `DOC-1A.4` | Roadmap/status taxonomy and maintenance drift workflow migration |
| `TRACE-008` |  | `DEC-002` | DOC-M1 | `AC-DOC-001` | `DOC-1A.1` | Numbered PRD/HLD canonical paths |
| `TRACE-009` |  | SPIKE-001 | FR-9 | `AC-009` / `TEST-009` | `OPS-3A.2` | Health check verifies Keycloak, LiteLLM Config Server, and Langfuse read paths |
| `TRACE-010` |  | SPIKE-002 | FR-8 | `AC-010` / `TEST-010` | `OPS-3A.3` | Config rollback restores Config Server and diagnoses non-snapshotted Keycloak/Langfuse state |
| `TRACE-011` |  |  | OPS retention | `AC-013` / `TEST-013` | `OPS-3A.4` | Deletes successful terminal provisioning jobs after retention while preserving failed/manual-intervention records |
| `TRACE-012` | `Q-002` | `DEC-004`, ADR-006 | FR-7.3 / secret zero-store | `AC-015` / `TEST-015` | `UI-5B.1`, `UI-5B.2`, `UI-5B.3`, `SEC-5B.1` | Provisioning detail UI is a product UI gate, not a reopened P0-M3 release gate |
| `TRACE-013` |  | ADR-004, ADR-006 | FR-1 / FR-2 / FR-3 UI | `AC-014` / `TEST-014` | `UI-5A.1`, `UI-5A.2`, `UI-5A.3`, `UI-5A.4` | Core server-rendered pages and role-aware controls |
| `TRACE-014` |  | ADR-004 | FR-1 / FR-2 completion | `AC-018` / `TEST-018` | `CORE-5A.1`, `CORE-5A.2`, `CORE-5A.3` | Initial admin selection, Keycloak pre-assignment, project permission CRUD, org delete completion |
| `TRACE-015` | `Q-001` | `DEC-003` | FR-4 auth UI | `AC-017` / `TEST-017` | `AUTH-6A.1`, `AUTH-6A.2`, `AUTH-6A.3` | Backend/API gate accepted; PAK auth-config UI is landed and SAML/OAuth UI remains the planned productization follow-up |
| `TRACE-016` |  | ADR-003, ADR-006 | FR-4 / FR-6 / FR-8 UI | `AC-016` / `TEST-016` | `UI-5C.1`, `UI-5C.2`, `UI-5C.3` | Auth config, LiteLLM config, and config-version UI |
| `TRACE-017` |  | ADR-005 | NFR availability / deploy / storage | `AC-019` / `TEST-019` | `OPS-7A.1`, `OPS-7A.2`, `OPS-7A.4` | Deploy/rollback/restore evidence and ConfigVersion storage policy |
| `TRACE-018` |  | ADR-005 | Audit retention | `AC-020` / `TEST-020` | `OPS-7A.3` | AuditLogsArchiveJob target from HLD |
| `TRACE-019` |  | ADR-006 | FR-10 | `AC-012` / `TEST-012` | `PLAY-8A.1`, `PLAY-8A.2`, `PLAY-8A.3`, `PLAY-8A.4` | Playground route/proxy/UI/inspector leaf coverage |
| `TRACE-020` | `Q-003` | pending | Admin observability | `AC-021` / `TEST-021` | `ADMIN-8A.1`, `ADMIN-8A.2`, `ADMIN-8A.3` | Super-admin dashboard scope must be decided before implementation |
| `TRACE-021` |  | SPIKE-002 | FR-8 full rollback | `AC-022` / `TEST-022` | `OPS-7A.5` | Current rollback diagnoses non-snapshotted Keycloak/Langfuse state; full final-product rollback remains planned |
| `TRACE-022` |  |  | FR-1 | `AC-001` / `TEST-001` | `CORE-1A.1` | Organization baseline CRUD accepted; product completion gaps continue in `CORE-5A.*` / `UI-5A.*` |
| `TRACE-023` |  |  | FR-3 | `AC-003` / `TEST-003` | `CORE-1A.3`, `UI-5A.4` | Project baseline CRUD, provisioning job creation, and product list/detail/create/delete UI landed |
| `TRACE-024` |  | ADR-003 | FR-4 OIDC | `AC-004` / `TEST-004` | `INTEG-2A.1` | OIDC Keycloak client provisioning accepted; auth expansion continues in `AUTH-4A.*` / `AUTH-6A.*` |

## Invariants

- 모든 `must` REQ는 최소 한 개의 AC를 가져야 한다.
- 모든 accepted DEC/ADR은 영향받는 REQ/HLD/Runbook을 갖는다.
- 모든 완료 slice는 적어도 하나의 TRACE row와 연결된다.
- PRD/HLD/UI coverage gap을 닫는 planned slice도 최소 하나의 TRACE row와 연결한다.

## Gaps

- Planned gates `AC-012`, `AC-014`~`AC-022`은 아직 passing gate가 아니다.
- `Q-003`은 decision으로 승격되지 않았다.
