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
- Resolution: backend/API gate accepted; SAML/OAuth/PAK UI remains deferred/non-gating.

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
