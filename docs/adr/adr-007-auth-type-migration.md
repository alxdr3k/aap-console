# ADR-007: auth_type 변경 — dual-client 마이그레이션 모델 채택

- **Date**: 2026-05-03
- **Status**: Accepted
- **Deciders**: Platform TG
- **Supersedes**: DEC-003 중 "auth_type 변경 금지" 조항
- **Related**: DEC-005, AUTH-6B.1~5

---

## 배경

AAP Console은 Project 생성 시 인증 방식(`auth_type`: OIDC / SAML / OAuth / PAK)을 고정하고, 이후 변경을 Controller 레벨에서 거부했다 (DEC-003). 이유는 Keycloak 클라이언트 재생성이 필요하기 때문이었다.

운영 현실에서는 기존 사용자가 있는 프로젝트도 인증 방식 전환이 필요하다. 단일 cut-over 방식은 활성 세션을 무효화하므로 수용 불가하다.

## 결정

`auth_type` 변경을 허용하되, **3단계 operator-driven dual-client 플로우**로만 수행한다.

### 오퍼레이션 설계

| 단계 | 오퍼레이션 | Keycloak 변화 | 가역성 |
|------|-----------|--------------|--------|
| 1 | `auth_binding_add` | 신규 client 생성 (신규 protocol suffix) | 가역 — 신규 client 삭제로 롤백 |
| 2 | `auth_binding_promote` | 없음 (DB role swap + Config Server re-publish) | 가역 — role 재역전으로 롤백 |
| 3 | `auth_binding_remove` | 구 client 삭제 | step 2 이후 불가역 — warning-only exception |

### 데이터 모델

`project_auth_configs`에 아래 컬럼을 추가해 1:N binding 구조로 전환한다.

- `role`: `primary | secondary | retiring`
- `state`: `pending | active | retiring | deleted`
- 부분 unique index: `(project_id) WHERE role = 'primary' AND state = 'active'`
- 부분 unique index: `(project_id, auth_type)`

기존 row는 `role: primary, state: active`로 backfill. PAK는 이 모델에서 제외 (`project_api_keys` CRUD 경로 유지).

### `auth_binding_add` 실행 순서

1. Project status → `update_pending`
2. `keycloak_client_create` (신규 protocol suffix `aap-{org}-{proj}-{new_protocol}`)
3. `config_server_apply` (양쪽 auth descriptor 게시)
4. `health_check` (warning-only)
5. DB insert: `role: secondary, state: active`
6. Project status → `active`

### `auth_binding_promote` 실행 순서

1. `config_server_apply` (신규 binding이 primary임을 게시)
2. `health_check`
3. DB: 구 primary → `role: retiring, state: retiring`, 신규 secondary → `role: primary, state: active`

### `auth_binding_remove` 실행 순서

1. `config_server_apply` (retiring binding 제거)
2. `keycloak_client_delete` (prefix guard: `aap-` 확인 필수)
3. DB: retiring row hard-delete

step 2 실패 시 롤백 불가 — Keycloak client는 삭제된 상태. 이후 cleanup sweep으로 처리.

### 사전 조건

`auth_binding_add`를 시작하려면 operator가 아래를 확인해야 한다.

- downstream 앱이 마이그레이션 기간 중 두 Keycloak client의 토큰을 모두 신뢰할 수 있다.
- 현재 Project에 active한 secondary binding이 없다.

### 제약

- `pak` ↔ Keycloak-backed 전환 시 Keycloak client create 또는 delete 중 하나만 실행 (PAK는 Keycloak client 없음).
- self-transition(`oidc → oidc`) Controller 레벨 거부.
- 마이그레이션 진행 중 Project slug 변경 금지 (Keycloak client ID 불변 보장).
- 동시에 secondary binding 1개 초과 금지.

## 고려한 대안

### A. 단일 `change_auth_type` 오퍼레이션 (create-new-then-delete-old)

한 번의 provisioningJob으로 처리. **기각**: 운영 중 세션 단절 위험, 전환 기간 없음, 운영 환경에서 수용 불가.

### B. in-place Keycloak 프로토콜 전환

Keycloak Admin API로 `protocol` field만 변경. **기각**: 반쪽짜리 설정 상태 위험, `aap-{protocol}` 명명 규칙 오염, 롤백 불가.

### C. Project 재생성 강제 (기존 DEC-003)

auth_type 변경 불가, Project 재생성 권장. **기각**: 기존 사용자 데이터와 설정 손실, 운영 현실과 불일치.

## 세션 처리 정책

`auth_binding_promote` 이후 구 client의 active session은 **자연 만료**에 맡긴다. Keycloak `logout-all` 호출 없음.

근거: promote 완료 시 Config Server가 새 primary client를 가리킨다. 구 client 세션이 만료되면 앱이 Keycloak 재인증으로 리다이렉트하고, 사용자는 새 primary client로 투명하게 로그인된다. 사용자 입장에서는 일반적인 세션 만료와 동일하여 마찰이 없다.

## 영향 범위

- `docs/02_HLD.md` §5.6 — Update 프로비저닝 트리거 규칙 표 갱신 (v1.19)
- `docs/04_IMPLEMENTATION_PLAN.md` — P1-M3, AUTH-6B.1~5 등록
- `docs/08_DECISION_REGISTER.md` — DEC-005
- `app/models/project_auth_config.rb` — role/state 컬럼 추가
- `app/services/provisioning/step_seeder.rb` — 3개 신규 plan 등록
- `app/controllers/auth_configs_controller.rb` — 3개 신규 endpoint
