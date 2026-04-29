# AAP Console — ADR Index

중요한 아키텍처 결정을 기록한다. 더 작은 결정은
[`../08_DECISION_REGISTER.md`](../08_DECISION_REGISTER.md)에 둔다.

## Index

| ADR | Title | Status | Date |
|---|---|---|---|
| ADR-001 | 프로비저닝 오케스트레이션 방식 선정 | Accepted | 2026-04-22 |
| ADR-002 | Langfuse API 연동 전략 | Accepted | 2026-04-22 |
| ADR-003 | 외부 API 연동 방식 — Terraform Provider vs 직접 호출 | Accepted | 2026-04-22 |
| ADR-004 | 인증/인가 분리 — Keycloak 순수 인증 + Console DB RBAC | Accepted | 2026-04-22 |
| ADR-005 | 데이터베이스 — SQLite + Litestream vs PostgreSQL | Accepted | 2026-04-22 |
| ADR-006 | 프론트엔드 아키텍처 — Hotwire (서버 렌더링) vs SPA | Accepted | 2026-04-22 |

## Filename Note

기존 ADR 파일명은 `adr-001-*` 형식을 유지한다. 새 ADR은
`ADR-0007-<kebab-title>.md` 형식을 사용한다.

## Template

새 ADR을 만들 때는 [`../templates/ADR_TEMPLATE.md`](../templates/ADR_TEMPLATE.md)를 복사한다.
