# AAP Console — 구현 상태 매트릭스

> **Version**: 1.0
> **Date**: 2026-04-23
> **Status**: Draft
> **목적**: PRD/HLD/UI Spec 에서 기술한 기능이 현재 코드베이스에서 어느 단계(구현 완료 / 부분 구현 / 미구현)인지 한눈에 파악하기 위한 문서. 외부 리뷰어와 신규 온보딩 개발자가 "문서상 존재하는 기능"과 "실제 동작하는 기능"을 혼동하지 않도록 한다.

---

## 상태 정의

| 상태 | 의미 |
|------|------|
| ✅ 구현 완료 | 서비스·컨트롤러·라우트·테스트 포함 모두 존재. 엔드포인트 호출 시 정상 동작 |
| 🟡 부분 구현 | 모델·서비스·UI 중 일부만 존재. 추가 작업 없이는 기능이 닫히지 않음 |
| ⏳ 미구현 | 문서에는 기술되어 있으나 현재 코드에 진입점 없음. 명시적으로 **future** |

---

## FR별 매트릭스

| FR | 항목 | 상태 | 비고 |
|----|------|:----:|------|
| FR-1 | Organization CRUD | ✅ | Langfuse Org 연동은 step 레벨 (프로비저닝 파이프라인) |
| FR-2 | RBAC + 멤버 관리 | ✅ | 최근 추가: last-admin guard, self-demotion guard |
| FR-2 | Keycloak 사용자 검색 | ✅ | `GET /users/search` (Keycloak Admin API 프록시) |
| FR-3 | Project CRUD | ✅ | StepSeeder 기반 프로비저닝 파이프라인 완비 |
| FR-4 | 인증 체계 — OIDC | ✅ | `keycloak_client_create` step |
| FR-4 | 인증 체계 — SAML / OAuth | 🟡 | step class는 미분기 (OIDC만 지원). `auth_type` 선택 후 실제 client 생성 로직 추가 필요 |
| FR-4 | PAK (Project API Key) 발급/폐기/검증 | ⏳ | 모델·팩토리·마이그레이션은 있음. **컨트롤러·라우트·서비스 전혀 없음.** MVP 범위 판단 후 구현 또는 문서 제거 |
| FR-5 | Langfuse Project + SDK Key | ✅ | `langfuse_project_create` step. SK/PK 는 `_ephemeral` 로 Config Server 로 전달, DB 미저장 |
| FR-6 | LiteLLM Config 반영 | ✅ | `config_server_apply` step |
| FR-7.1 | 프로비저닝 상태 머신 | ✅ | `pending / in_progress / completed / completed_with_warnings / failed / retrying / rolling_back / rolled_back / rollback_failed` |
| FR-7.2 | 단계별 실행·재시도·롤백 | ✅ | StepSeeder + Orchestrator + StepRunner + RollbackRunner. 크래시 복구(`already_completed?` idempotency) 구현 |
| FR-7.3 | 프로비저닝 현황 UI (Turbo Streams) | 🟡 | ActionCable 브로드캐스트는 연결되어 있음. ERB 뷰 레벨의 상세 UI (타임라인, 재시도 버튼 등)는 미구현 |
| FR-8 | 설정 변경 이력 / 버전 롤백 | 🟡 | `config_versions` 테이블·레코드 생성·조회 API 존재. `POST /config_versions/:id/rollback` 실제 Keycloak/Langfuse 스냅샷 복구까지는 완결되지 않음 |
| FR-9 | Health Check | 🟡 | `health_check` step 존재, `completed_with_warnings` 상태 처리 완료. 실제 검증 로직(상세 assertion)은 placeholder 수준 |
| FR-10 | Playground (AI Chat) | ⏳ | 문서에는 상세 UX 정의. **컨트롤러·라우트·뷰·SSE proxy 전혀 없음.** Phase 4로 분리 |

---

## 컴포넌트 레벨

| 컴포넌트 | 상태 | 비고 |
|----------|:----:|------|
| `Provisioning::StepSeeder` | ✅ | create/update/delete 플랜. idempotent |
| `Provisioning::Orchestrator` | ✅ | 빈 step 가드, exception → rollback, Rails executor 래핑, health_check severity |
| `Provisioning::StepRunner` | ✅ | Inline retry (≤ 8s) + Scheduled retry (SolidQueue re-enqueue) |
| `Provisioning::RollbackRunner` | ✅ | 완료 step 역순 rollback |
| `Provisioning::Steps::KeycloakClientCreate` | 🟡 | OIDC 기본 경로만. SAML/OAuth/PAK 분기 추가 필요 |
| `Provisioning::Steps::LangfuseProjectCreate` | ✅ | SK/PK ephemeral 전달 |
| `Provisioning::Steps::ConfigServerApply` | ✅ | Idempotency key 포함 |
| `Provisioning::Steps::HealthCheck` | 🟡 | 기본 ping 수준. 서비스별 상세 검증 미구현 |
| `KeycloakClient` | ✅ | 사용자 검색/조회/사전 생성, Client CRUD |
| `LangfuseClient` | ✅ | tRPC (NextAuth 세션 쿠키). Thread-safety Mutex 적용 |
| `ConfigServerClient` | ✅ | Admin API write + 읽기 API |
| `ProvisioningChannel` (ActionCable) | ✅ | 인가 검증 포함 |
| `Projects::CreateService` / `UpdateService` / `DestroyService` | ✅ | StepSeeder 통합 완료 |
| `AuthConfigsController` | ✅ | Keycloak 식별자는 server-owned, mutation 은 provisioning update 로 위임 |
| `MembersController` | ✅ | last-admin + self-demotion guard |
| `ProjectApiKeysController` | ⏳ | 없음. PRD FR-4 PAK 기능 미구현 |
| `PlaygroundsController` | ⏳ | 없음. FR-10 전체 미구현 |

---

## Release Gate

릴리스 전 필수로 닫혀야 하는 항목:

- [x] Provisioning step seeding — Orchestrator 가 no-op 로 success 처리하지 않음
- [x] 프로비저닝 exception → rollback 경로 단일화
- [x] 병렬 step 의 Rails executor + connection pool 래핑
- [x] Health check failure → `completed_with_warnings` 분리
- [x] AuthConfig mutation 이 Keycloak 프로비저닝을 반드시 경유
- [x] Keycloak Client 식별자는 server-owned
- [x] CI 에 RSpec 포함
- [x] Members 마지막 admin 방어
- [x] Project slug scoped uniqueness + app_id 재시도 상한
- [x] StepRunner 재시도가 worker 를 sleep 으로 장기 점유하지 않음
- [ ] 외부 리뷰어 피드백 재검증 (통합 smoke)
- [ ] FR-9 Health Check 실제 검증 로직 구현
- [ ] FR-8 config 롤백의 Keycloak/Langfuse 복구 경로 완결
- [ ] FR-4 SAML / OAuth / PAK 분기 구현 (또는 MVP 범위 축소 결정)

위 3개 `[ ]` 항목은 Phase 3 (운영 안정성) 범위 내에서 순차 처리.

---

## Future 항목 (Phase 4 이후)

| 항목 | 메모 |
|------|------|
| Playground (FR-10) | SSE streaming, Langfuse trace link, JSON 내보내기 포함. 먼저 PAK/auth/health-check 성숙화 이후 착수 |
| Playground 탭 UI | Project 상세의 "Playground" 링크는 구현 완료 전까지 nav 에서 숨기거나 disabled 처리 |
| PAK 일회성 표시 + 폐기 | FR-4 MVP 스코프 결정 필요. 현재 model/schema 만 존재 |
| LiteFS read replica | PRD 8.2. 단일 인스턴스에서 읽기 병목 생기면 재검토 |
