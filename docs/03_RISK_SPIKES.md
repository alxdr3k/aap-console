# AAP Console — Risk Spikes

기술 가정을 실험으로 검증하는 짧은 탐색 작업이다. 결과가 결정으로 굳어지면
`docs/08_DECISION_REGISTER.md` 또는 ADR로 승격한다.

## Spikes

### SPIKE-001: Health check 상세 검증 수준

- Hypothesis: 현재 `health_check` step은 warning 상태 처리는 갖췄지만, 서비스별 post-provisioning consistency를 충분히 검증하지 못한다.
- Owner: Platform TG
- Time-box: 1-2 days
- Start / End: anchor missing
- Status: completed

**Experiment**

Keycloak client, Langfuse project, Config Server applied config를 각각 어떤 API/read path로 확인할 수 있는지 정리하고, 테스트 가능한 assertion set을 정의한다.

**Result**

`Steps::HealthCheck`가 Keycloak client lookup, Config Server LiteLLM config readback, Langfuse API key listing을 수행하도록 구현했고 `spec/services/provisioning/steps/health_check_spec.rb`로 mismatch warning path를 검증한다.

**Decision / Next Step**

- Decision: `OPS-3A.2` / `AC-009` accepted.
- Follow-up: 유지보수.

---

### SPIKE-002: Config rollback의 외부 리소스 복구 경계

- Hypothesis: `config_versions` rollback은 Console/Config Server 경로만으로는 Keycloak/Langfuse snapshot 복구까지 닫히지 않을 수 있다.
- Owner: Platform TG
- Time-box: 1-3 days
- Start / End: anchor missing
- Status: open

**Experiment**

현재 `ConfigVersionsController#rollback`과 관련 service/spec를 기준으로 복구 대상, snapshot 필드, 실패 진단 상태를 분리한다.

**Result**

Not run.

**Decision / Next Step**

- Decision: pending
- Follow-up: `OPS-3A.3`, `AC-010`

---

### SPIKE-003: SAML/OAuth/PAK MVP 범위

- Hypothesis: OIDC 외 인증 방식과 PAK는 schema/model 일부가 존재하지만, 제품 MVP에서는 scope 축소 또는 Phase 4 이동이 필요할 수 있다.
- Owner: Platform TG
- Time-box: 1 day
- Start / End: anchor missing
- Status: open

**Experiment**

PRD FR-4, UI Spec phase gating, 현재 `ProjectApiKey` model/schema, Keycloak step 구현 범위를 비교해 `implement`, `defer`, `drop` 후보를 나눈다.

**Result**

Not run.

**Decision / Next Step**

- Decision: `Q-001`
- Follow-up: `AUTH-4A.1`, `AUTH-4A.2`, `AC-011`
