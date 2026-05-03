# AAP Console — Decision Register

작은 ~ 중간 크기의 결정을 가벼운 레코드로 남긴다. 큰 결정은 `docs/adr/`.

## Decisions

### DEC-001: Boilerplate roadmap/status taxonomy 채택

- Date: 2026-04-29
- Status: accepted
- Deciders: Platform TG
- Supersedes: —
- Superseded by: —
- Resolves: —
- Impacts: `docs/04_IMPLEMENTATION_PLAN.md`, `docs/context/current-state.md`, `docs/current/`, `AGENTS.md`

**Context**

`../boilerplate` commit `24851cf`가 `04_IMPLEMENTATION_PLAN.md`를 roadmap / status ledger의 canonical 위치로 확장했고, `24b47f1`이 PR template과 doc freshness workflow에 roadmap/status 및 gate drift checks를 추가했다.

**Decision**

AAP Console은 milestone / track / phase / slice / gate / evidence taxonomy를 채택한다. 구현 상태 inventory는 `docs/04_IMPLEMENTATION_PLAN.md`에 두고, `docs/context/current-state.md`와 `docs/current/*`에는 전체 backlog를 복제하지 않는다. PR template과 doc freshness 예시는 roadmap/status ledger와 acceptance gates drift도 확인하도록 둔다.

**Rationale**

기존 `docs/implementation-status.md`의 완료/부분/미구현 표는 구현 상태와 acceptance gate 상태를 섞고 있었다. 새 taxonomy는 `landed`와 `passing`, `planned`와 `defined`를 분리한다.

**Consequences**

- 긍정: 신규 세션과 리뷰에서 현재 위치, evidence, next work를 한 곳에서 확인할 수 있다.
- 부정: 기존 status matrix 링크를 새 ledger로 정리해야 한다.
- Follow-ups: `DOC-1A.2`, `DOC-1A.3`, `AC-DOC-001`

---

### DEC-002: PRD/HLD canonical path를 numbered docs로 전환

- Date: 2026-04-29
- Status: accepted
- Deciders: Platform TG
- Supersedes: —
- Superseded by: —
- Resolves: —
- Impacts: `docs/01_PRD.md`, `docs/02_HLD.md`, `README.md`, `CLAUDE.md`, `.claude/agents/*`

**Context**

Boilerplate source-of-truth map은 PRD/HLD를 `01_PRD.md`와 `02_HLD.md`로 둔다. AAP Console은 기존에 `PRD.md`와 `HLD.md`를 사용했다.

**Decision**

기존 PRD/HLD 본문을 numbered canonical path로 이동하고, `docs/PRD.md`와 `docs/HLD.md`는 compatibility pointer로 남긴다.

**Rationale**

외부/기존 링크를 즉시 깨뜨리지 않으면서 boilerplate 문서 순서를 채택한다.

**Consequences**

- 긍정: Boilerplate read order와 repo 문서명이 일치한다.
- 부정: 과거 링크가 남아 있을 수 있어 link scan이 필요하다.
- Follow-ups: `AC-DOC-001`

---

### DEC-003: P0-M4 auth 확장 gate는 backend/API 범위로 수용

- Date: 2026-04-29
- Status: accepted
- Deciders: Platform TG
- Supersedes: —
- Superseded by: —
- Resolves: `Q-001`
- Impacts: `AC-011`, `AUTH-4A.1`, `AUTH-4A.2`, `docs/current/RUNTIME.md`, `docs/ui-spec.md`

**Context**

이 결정 당시 repo는 minimal ERB/API surface였고, SAML/OAuth/PAK UI는 ui-spec상 Phase 4 화면으로 남아 있었다. Backend에는 Keycloak SAML/OAuth client path와 PAK schema가 있었고, PAK API는 `AUTH-4A.2`에서 구현됐다.

**Decision**

`P0-M4` / `AC-011`은 backend/API gate로 수용한다. SAML/OAuth는 Project create `auth_type` 선택과 Keycloak client create payload/step coverage로 검증하고, PAK는 issue/revoke/verify API로 검증한다. SAML/OAuth/PAK UI는 `AC-011` release blocker가 아니라 후속 UI work로 둔다.

**Rationale**

현재 제품 surface가 API 중심이므로 FR-4의 동작 보장은 backend provisioning과 token verification coverage가 핵심이다. UI를 같은 gate에 묶으면 `Q-002`와 Hotwire timeline work처럼 별도 UI architecture migration과 결합되어 release gate가 불필요하게 커진다.

**Consequences**

- 긍정: OIDC 외 auth backend/API path가 자동 테스트로 고정된다.
- 부정: 결정 시점에는 SAML/OAuth/PAK UI가 제품 화면에서 disabled/hidden 또는 후속 구현이 필요했다.
- Follow-ups: `AUTH-6A.1`, `AUTH-6A.2`, `AUTH-6A.3` (`AUTH-6A.3` landed; SAML/OAuth UI는 계속 후속)

---

### DEC-004: Provisioning detail UI는 P0-M5 product UI gate로 추적

- Date: 2026-04-29
- Status: accepted
- Deciders: Platform TG
- Supersedes: —
- Superseded by: —
- Resolves: `Q-002`
- Impacts: `AC-015`, `UI-5B.1`, `UI-5B.2`, `UI-5B.3`, `SEC-5B.1`, `docs/context/current-state.md`

**Context**

`P0-M3`는 ActionCable authorization, status broadcast, rollback/health/retention 운영 gate를 닫았다. 그러나 PRD/UI Spec의 프로비저닝 현황 화면은 ERB timeline, Hotwire consumer, 수동 재시도 UX, 시크릿 일회성 표시까지 포함한다. 이 UI 완성도를 `P0-M3`에 다시 묶으면 이미 accepted된 운영 gate와 별개 제품 UI work가 섞인다.

**Decision**

`P0-M3`를 다시 열지 않는다. `AC-007`은 ActionCable server path gate로 유지한다. 프로비저닝 상세 ERB/Hotwire timeline, retry/manual-intervention UX, secret reveal cache write/read path는 `P0-M5`의 `UI-5B.*` / `SEC-5B.1` leaf와 `AC-015`로 추적한다.

**Rationale**

실시간 서버 경로와 제품 UI 완성도는 검증 방법과 blast radius가 다르다. 별도 gate로 분리하면 `AC-007`의 regression coverage를 유지하면서 UI/secret 흐름을 더 작은 leaf로 구현할 수 있다.

**Consequences**

- 긍정: P0-M3 accepted 상태와 현재 코드 evidence가 유지된다.
- 긍정: Secret reveal은 ActionCable과 분리된 보안 경로로 독립 검증된다.
- 부정: Product UI가 완성되기 전까지 current repo는 minimal JSON/ERB surface로 남는다.
- Follow-ups: `UI-5B.1`, `UI-5B.2`, `UI-5B.3`, `SEC-5B.1`

---

### DEC-005: auth_type 변경은 dual-client 마이그레이션 플로우로 허용

- Date: 2026-05-03
- Status: accepted
- Deciders: Platform TG
- Supersedes: `DEC-003` 중 "SAML/OAuth/PAK UI follow-up" 범위 일부
- Superseded by: —
- Resolves: —
- Impacts: `AUTH-6A.1`, `AUTH-6A.2`, `AUTH-6B.*`, `docs/02_HLD.md#54-update-프로비저닝`, `docs/adr/adr-007-auth-type-migration.md`

**Context**

`DEC-003`은 `auth_type`을 변경 불가로 정의했다. 실제 운영에서는 OIDC → SAML처럼 인증 방식을 전환해야 하는 요구가 발생한다. 단일 cut-over는 세션이 살아있는 사용자에게 영향을 주므로 운영 환경에서 수용할 수 없다.

**Decision**

`auth_type` 변경은 허용하되, 반드시 3단계 operator-driven 플로우를 통해서만 수행한다.
1. `auth_binding_add`: 신규 프로토콜의 Keycloak client를 secondary로 추가.
2. `auth_binding_promote`: secondary를 primary로 승격 (DB role swap + Config Server re-publish; Keycloak 변화 없음).
3. `auth_binding_remove`: retiring client 삭제.

마이그레이션 기간 동안 두 클라이언트가 동시에 활성화되므로 세션 단절 없이 전환 가능하다. 단, downstream 앱이 마이그레이션 기간 중 두 클라이언트의 토큰을 모두 신뢰할 수 있어야 한다 (operator 확인 체크박스로 처리). PAK는 이 플로우에서 제외한다.

SAML SP metadata export는 URL copy 방식만 제공한다 (XML 다운로드 불필요). OAuth/PKCE redirect URI는 기존 `uri_list` Stimulus 컨트롤러를 재사용하고 서버 사이드에서 PKCE 규칙을 추가한다 (HTTPS 필수, localhost 예외, URI fragment 불허).

**Rationale**

in-place 프로토콜 전환은 Keycloak의 `protocol` attribute를 변경하면 반쪽짜리 설정 상태가 되고, 현재 명명 규칙(`aap-{org}-{proj}-{protocol}`)과도 충돌한다. delete-old-then-create-new는 일시적 auth 공백을 만든다. create-new-then-delete-old 3단계 분리가 운영 안전성을 보장하는 유일한 방법이다.

**Consequences**

- 긍정: 운영 중 세션 단절 없이 auth_type 전환 가능.
- 긍정: 각 오퍼레이션이 독립적으로 안전하고 롤백 가능.
- 긍정: `AUTH-6A.1` / `AUTH-6A.2` contract가 확정되어 ready 승격.
- 부정: 단일 오퍼레이션보다 복잡한 3단계 절차.
- 부정: downstream 앱의 dual-trust 지원이 전제.
- Follow-ups: `AUTH-6B.1`~`AUTH-6B.5`
