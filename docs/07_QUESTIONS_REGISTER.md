# AAP Console — Questions Register

아직 답이 정해지지 않은 열린 질문을 기록한다.

## Questions

### Q-001: SAML/OAuth/PAK는 MVP release gate에 포함하는가?

- Opened: 2026-04-29
- Owner: Platform TG
- Status: open
- Proposed Answer: OIDC는 유지하고, SAML/OAuth/PAK는 `P0-M4`로 분리한다. PAK API는 먼저 착수하고, SAML/OAuth UI/metadata 범위는 별도 확정한다.
- Blocks: `AUTH-4A.1`, `AUTH-4A.2`, `AC-011`
- Resolution: partial — PAK issue/revoke/verify API landed; SAML/OAuth scope remains pending.

**Context**

현재 `ProjectApiKey` model/schema/factory와 PAK issue/revoke/verify API는 존재한다. SAML/OAuth Keycloak client path는 일부 구현되어 있으나 UI/metadata 입력 범위가 아직 확정되지 않았다.

**Discussion**

- `docs/implementation-status.md` 기존 matrix는 SAML/OAuth를 부분 구현, PAK를 미구현으로 분류했다.
- UI Spec은 Phase 4 전까지 숨김 또는 disabled 처리 가능성을 열어둔다.

---

### Q-002: Provisioning detail UI는 P0-M3 release gate에 포함하는가?

- Opened: 2026-04-29
- Owner: Platform TG
- Status: open
- Proposed Answer: ActionCable authorization and broadcast path는 accepted로 보고, 상세 timeline/retry button UX는 `UI-2B.1` 후속으로 둔다.
- Blocks: `UI-2B.1`
- Resolution: pending

**Context**

`ProvisioningChannel`과 request specs는 존재하지만, 기존 status matrix는 ERB 상세 UI를 부분 구현으로 표시했다.

**Discussion**

- 운영 release gate에서 필요한 것은 실패 진단과 retry path인지, timeline UX 완성도인지 분리해야 한다.
