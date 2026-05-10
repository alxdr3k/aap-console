# AAP Console — Questions Register

아직 답이 정해지지 않은 열린 질문을 기록한다.

## Questions

### Q-001: SAML/OAuth/PAK는 MVP release gate에 포함하는가?

- Opened: 2026-04-29
- Owner: Platform TG
- Status: resolved
- Proposed Answer: OIDC는 유지하고, SAML/OAuth/PAK backend/API는 `P0-M4`에서 수용한다. UI는 release blocker가 아니라 후속 UI work로 둔다.
- Blocks: `AUTH-4A.1`, `AUTH-4A.2`, `AC-011`
- Decision: `DEC-003`
- Resolution: backend/API gate accepted; UI is non-gating. PAK product UI later landed in `AUTH-6A.3`, while SAML/OAuth UI remains deferred.

**Context**

현재 `ProjectApiKey` model/schema/factory와 PAK issue/revoke/verify API는 존재한다. SAML/OAuth Keycloak client path는 backend/API 테스트로 고정한다. UI/metadata 입력 화면은 후속 UI work로 둔다.

**Discussion**

- `docs/implementation-status.md` 기존 matrix는 과거 상태에서 SAML/OAuth를 부분 구현, PAK를 미구현으로 분류했다.
- UI Spec은 Phase 4 전까지 숨김 또는 disabled 처리 가능성을 열어둔다.

---

### Q-002: Provisioning detail UI는 P0-M3 release gate에 포함하는가?

- Opened: 2026-04-29
- Owner: Platform TG
- Status: resolved
- Proposed Answer: ActionCable authorization and broadcast path는 accepted로 보고, 상세 timeline/retry button UX는 `UI-2B.1` 후속으로 둔다.
- Blocks: `UI-2B.1`
- Decision: `DEC-004`
- Resolution: P0-M3는 다시 열지 않는다. Provisioning detail ERB/Hotwire timeline, retry UX, secret reveal은 `P0-M5`의 `UI-5B.*` / `SEC-5B.1` leaf로 추적한다.

**Context**

`ProvisioningChannel`과 request specs는 존재하지만, 기존 status matrix는 ERB 상세 UI를 부분 구현으로 표시했다.

**Discussion**

- 운영 release gate에서 필요한 것은 실패 진단과 retry path인지, timeline UX 완성도인지 분리해야 한다.

---

### Q-003: Super-admin dashboard의 최소 범위는 무엇인가?

- Opened: 2026-04-29
- Owner: Platform TG
- Status: open
- Proposed Answer: P2 dashboard의 최소 범위는 전체 Organization/Project 상태, 외부 서비스 health summary, `failed`/`rollback_failed` provisioning work queue, runbook 링크로 제한한다. 비용/사용량 분석, 장기 trend, policy editing은 후속으로 둔다.
- Blocks: `ADMIN-8A.1`, `ADMIN-8A.2`, `ADMIN-8A.3`, `AC-021`
- Resolution: pending

**Context**

PRD는 "공유 서비스 연동 상태 대시보드"와 "Playground 및 관리자 고도화 기능"을 언급하지만, super-admin dashboard의 필수 metric과 release gate는 아직 leaf 수준으로 결정되지 않았다.

**Discussion**

- `ADMIN-8A.1`에서 dashboard scope를 먼저 결정해야 `ADMIN-8A.2` 구현이 과도하게 커지지 않는다.
- `ADMIN-8A.3`은 운영 수동 개입 queue와 연결되므로 `OPS-7A` runbook evidence와 함께 맞춰야 한다.

---

### Q-004: Keycloak mutation API에 exact-clientId invariant을 적용할 것인가?

- Opened: 2026-05-09
- Owner: Platform TG
- Status: resolved
- Proposed Answer: `KeycloakClient#update_client`, `delete_client`, `regenerate_client_secret`도 `expected_client_id:` 인자를 받아 정확한 clientId 일치를 검증하고, 모든 caller가 `auth_config.keycloak_client_id`를 전달하도록 강화한다. mismatch는 `IdentityMismatchError`로 raise하고 caller가 audit + abort 한다.
- Resolution: 같은 PR에서 모두 적용. `update_client`, `delete_client`, `regenerate_client_secret` 모두 `expected_client_id:` required로 강제. `regenerate_client_secret`은 `get_client_secret`과 동일하게 pre/post `IdentityMismatchError(stage:)` 검증을 적용해 secret 노출 race window를 한 round-trip 안으로 압축. caller (`KeycloakClientCreate#rollback`, `KeycloakClientUpdate#execute/rollback`, `KeycloakClientDelete`, `RegenerateClientSecretService`) 모두 expected_client_id 전달.

**Context**

Codex adversarial review에서 지적된 cross-project isolation risk였다. 기존 `assert_aap_client!`는 `aap-` prefix만 강제하므로 `auth_config.keycloak_client_uuid`가 stale인 상황(수동 삭제·재생성, race, version skew)에서 다른 project의 aap-prefixed client를 mutate/delete하거나 그 client의 secret을 regenerate해 운영자에게 노출시킬 수 있었다.

**Resolution Detail**

- `KeycloakClient#assert_client_identity!(uuid, expected_client_id, stage:)` private helper로 통일.
- `IdentityMismatchError`에 `stage` (`pre_fetch` / `post_fetch`) attribute 추가. secret 노출 경로(read/regenerate)에서만 `post_fetch`가 의미를 가진다.
- 회귀 spec: 각 mutation API에 대해 IdentityMismatchError raise + 부수효과 미수행 검증.

---

### Q-005: Provisioning create-time identity divergence는 step pass인가, fail인가?

- Opened: 2026-05-09
- Owner: Platform TG
- Status: open
- Proposed Answer: `KeycloakClientCreate#cache_client_secret!`이 secret refresh 중 `IdentityMismatchError`를 감지하면 현재는 audit + warn + return으로 step을 통과시키고 project를 active로 진행한다. 그러나 stale UUID + foreign aap client는 tenant isolation 우려가 있으므로, divergence를 raise해 step을 fail로 처리하고 orchestrator가 rollback을 돌리는 정책으로 전환할지 결정한다.
- Blocks: 없음 (현재 정책 mitigated)
- Resolution: pending

**Context**

8차 codex review (2026-05-09)에서 지적된 사항이다. 현재 stack에서:

1. `cache_client_secret!`의 `IdentityMismatchError` rescue는 audit + cache delete + return.
2. step 자체는 통과 (`already_completed?` 분기에서 동일 패턴 유지).
3. project는 정상 active로 진행되고 auth_config의 stale UUID는 그대로 유지.

**Mitigation 현황**

- `auth_config.keycloak_client_uuid`로 호출되는 모든 mutation/secret read API (`update_client`, `delete_client`, `regenerate_client_secret`, `get_client_secret`, `assign_client_scope`)는 `expected_client_id` required + `assert_client_identity!`로 보호된다. stale UUID로 호출되면 `IdentityMismatchError`가 발생하고 부수효과가 거부된다.
- secret cache는 비어 있어 reveal 시도 시 cache miss로 운영자가 발견 가능.

**Discussion**

- (A) 현재 정책: project active + audit + 모든 후속 호출이 mismatch에서 거부. 운영자가 audit/incident 로그로 발견하고 reconcile.
- (B) 정책 변경: divergence를 `cache_client_secret!`에서 raise해 step fail → rollback. project는 manual_intervention 상태. 더 보수적이지만 운영자가 이미 외부에서 정상화한 케이스도 fail로 처리.
- 정책은 PRD/HLD의 already_completed? divergence 처리 정책과 일관되게 가야 한다.
