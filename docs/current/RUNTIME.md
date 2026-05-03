# AAP Console — Runtime Flow

실제 구현된 request/job/channel flow의 얇은 map이다.

## Implemented Flow

### Login / Current User

1. 사용자는 Keycloak OIDC로 인증한다.
2. `SessionsController`가 callback/logout/failure를 처리한다.
3. `ApplicationController`가 current request context를 설정한다.
4. Authorization은 Keycloak identity와 Console DB membership/permission state를 함께 사용한다.

### Organization / Project CRUD

1. Controller가 authz를 검증하고 필요한 경우 service object에 위임한다.
2. Service가 transaction 안에서 app DB state를 쓴다.
3. Project lifecycle 변경은 `ProvisioningJob`을 만든다.
4. `Provisioning::StepSeeder`가 operation별 step을 seed한다.
5. `ProvisioningExecuteJob`이 orchestrator를 비동기로 실행한다.
6. Browser Project create/delete flows redirect to the provisioning job page; API-like wildcard/JSON requests keep JSON-compatible read/update responses.

### Provisioning Create

`create` operation steps:

1. `app_registry_register`
2. Parallel group: `keycloak_client_create`, `langfuse_project_create`
3. `config_server_apply`
4. `health_check`

`health_check`는 warning-only step이다. Keycloak client lookup, Config Server
LiteLLM config readback, Langfuse API key listing으로 post-provisioning
consistency를 확인한다. 실패해도 rollback하지 않고 `completed_with_warnings`를
만든다.

### Provisioning Update

`update` operation steps:

1. `keycloak_client_update`
2. `config_server_apply`
3. `health_check`

Auth config와 LiteLLM config update controller는 external propagation이 필요할
때 `202 Accepted`와 `provisioning_job_id`를 반환한다.

### Auth Config HTML / Secret Regeneration

- Browser `GET /organizations/:org_slug/projects/:slug/auth_config` renders the OIDC auth config page for Project `read`+ users while preserving JSON compatibility for API-like requests.
- Browser `PATCH /organizations/:org_slug/projects/:slug/auth_config` redirects write users to the update provisioning job page when redirect URI fields change.
- `POST /organizations/:org_slug/projects/:slug/auth_config/regenerate_secret` calls Keycloak `client-secret` regeneration directly for OIDC projects, blocks while another provisioning job is active, writes an audit log, and stores the new secret only in a 10-minute `AuthConfigs::SecretRevealCache`.
- The auth config page applies `Cache-Control: no-store` whenever a regenerated secret is present and uses masked reveal/copy/confirm UX gated by Project `write` permission.

### LiteLLM Config HTML

- Browser `GET /organizations/:org_slug/projects/:slug/litellm_config` renders the current LiteLLM config page for Project `read`+ users while preserving JSON compatibility for API-like requests.
- Browser `PATCH /organizations/:org_slug/projects/:slug/litellm_config` validates model presence and S3 retention bounds, then redirects write users to the update provisioning job page when the config change is accepted.
- The page reuses the current `ConfigVersion` snapshot as the edit base, shows the derived S3 path as read-only, and disables edits while another provisioning job is active.

### Provisioning Delete

`delete` operation steps:

1. Parallel group: `config_server_delete`, `keycloak_client_delete`, `langfuse_project_delete`
2. `app_registry_deregister`
3. `db_cleanup`

### Config Version Rollback

`POST /config_versions/:id/rollback` calls `ConfigVersions::RollbackService`
synchronously. It reverts Config Server LiteLLM config to the target
`ConfigVersion`, creates a rollback `ConfigVersion`, and writes an audit log.
Keycloak/Langfuse state is reported in diagnostics as not snapshotted by the
current `ConfigVersion` model.

### Config Version HTML

- Browser `GET /organizations/:org_slug/projects/:slug/config_versions` renders the config history page for Project `read`+ users while preserving JSON compatibility for API-like requests.
- Browser `GET /config_versions/:id` renders the detail/diff panel used both for direct navigation and Turbo Frame inline replacement from the history page.
- Browser `POST /config_versions/:id/rollback` redirects back to the history page with a rollback diagnostics banner. It does not enqueue a provisioning job because the current rollback path is synchronous.

### Project API Keys

- Project users with `write` permission can issue and revoke PAKs through `ProjectApiKeysController`; browser HTML requests redirect back to the auth-config page while JSON/default API clients keep the existing response contract.
- The issue response includes the plaintext `token` once. Console stores only `token_digest` and `token_prefix`.
- Browser issue flow stores a 10-minute project-scoped reveal payload in `ProjectApiKeys::RevealCache`; if that shared cache write fails, the same payload falls back to the current browser session so the newly issued token is not lost. `AuthConfigsController#show` renders either path with `no-store` headers on the auth-config page.
- `DELETE /project_api_keys/:id` soft-revokes by setting `revoked_at`; it does not delete the row.
- `POST /api/v1/project_api_keys/verify` is protected by `CONSOLE_INBOUND_API_KEY`, matches active PAK digests for `active` / `update_pending` projects, and updates `last_used_at`.
- Audit events: `project_api_key.create`, `project_api_key.revoke`.

### Retry / Rollback

- `StepRunner`는 짧은 wait는 inline retry하고, 긴 wait는 `ProvisioningExecuteJob` re-enqueue로 defer한다.
- `Orchestrator`는 deferred step이 있으면 job을 `retrying`으로 전환한다.
- Fatal step failure는 `RollbackRunner`를 실행한다.
- 완료된 step은 역순으로 rollback된다.
- `rollback_failed`는 operator inspection이 필요하다는 뜻이다.

### Realtime Updates

- `ProvisioningChannel`은 특정 job subscription 권한을 검증한다.
- `StepRunner`는 상태 변경 시 `ProvisioningChannel.broadcast_to`로 JSON
  `step_update` payload를 broadcast한다.
- `Orchestrator`는 완료 시 `ProvisioningChannel.broadcast_to`로 JSON
  `job_completed` payload를 broadcast한다.
- Client는 `GET /provisioning_jobs/:id`로 polling할 수도 있고, browser HTML 요청은 persisted job/step state를 ERB timeline으로 렌더한다.
- Provisioning show page의 Stimulus controller는 `ProvisioningChannel`에 subscribe하고, `step_update`를 받으면 해당 step partial endpoint를 fetch해 DOM을 교체한다. Cable 연결이 없거나 끊기면 JSON polling fallback이 같은 partial replacement path를 사용한다.

### Retention Cleanup

- `ProvisioningJobsCleanupJob`은 180일이 지난 `completed`, `completed_with_warnings`, `rolled_back` provisioning job을 삭제한다.
- 삭제된 job의 `provisioning_steps`는 함께 삭제된다.
- 연결된 모든 `ConfigVersion`은 보존되며 `provisioning_job_id`만 null 처리된다.
- `failed` / `rollback_failed` job은 manual inspection을 위해 보존된다.
- Production schedule은 `config/recurring.yml`의 `provisioning_jobs_cleanup`에 둔다.

## Planned / Partial Flow

| Flow | State |
|---|---|
| Organization/member/project completion | Designated initial admin and Langfuse org name sync are landed in `CORE-5A.1`; Keycloak pre-assignment and project permission CRUD API are landed in `CORE-5A.2`; org delete finalization is landed in `CORE-5A.3`; Organization list/detail/new/edit UI is landed in `UI-5A.1` / `UI-5A.2`; member management UI is landed in `UI-5A.3`; Project list/detail/new/delete UI is landed in `UI-5A.4` |
| Hotwire provisioning detail UI | ERB timeline, ActionCable/Stimulus step replacement, manual retry UX, active-job warning banners, and OIDC secret reveal are landed in `UI-5B.1` / `UI-5B.2` / `UI-5B.3` / `SEC-5B.1`. `Q-002` is resolved by `DEC-004`; auth-config PAK reveal is landed in `AUTH-6A.3` |
| Secret reveal cache write path | `KeycloakClientCreate` writes provisioning-created OIDC secrets through `Provisioning::SecretCache`, auth config secret regeneration writes through `AuthConfigs::SecretRevealCache`, and browser PAK issuance writes through `ProjectApiKeys::RevealCache`; PAK browser flow falls back to a project-scoped session payload if shared cache persistence fails. Primary paths use 10-minute TTL and Project authorization metadata guards |
| Config/product UI | Auth config, LiteLLM config, and config-version server-rendered UI are landed in `UI-5C.1` / `UI-5C.2` / `UI-5C.3`; PAK auth-config extensions are landed in `AUTH-6A.3` |
| Full external config rollback | Current rollback restores Config Server and reports Keycloak/Langfuse as non-snapshotted diagnostics. Full Keycloak/Langfuse snapshot restore is `OPS-7A.5` / `AC-022` |
| SAML/OAuth/PAK UI | Backend/API gate is accepted by `DEC-003`; PAK auth-config UI is landed in `AUTH-6A.3`, while SAML/OAuth product UI remains `AUTH-6A.1` / `AUTH-6A.2` |
| Deployment/restore/archive operations | Deploy command, rollback procedure, Litestream restore, audit archive, and ConfigVersion storage policy are `OPS-7A.*` |
| Playground | PRD P2; tracked by `PLAY-8A.*` / `AC-012` |
| Super-admin dashboard | Scope is open in `Q-003`; tracked by `ADMIN-8A.*` |

## Failure Modes

| Failure | Expected Handling |
|---|---|
| Unknown provisioning operation | `StepSeeder::UnknownOperationError`; no-op success가 아니라 실패해야 함 |
| Deferred retry interval | Job은 `retrying`이 되고 worker는 release되며 job이 re-enqueue됨 |
| Fatal provisioning step failure | Job은 `rolling_back` 이후 `rolled_back` 또는 `rollback_failed`가 됨 |
| Health check failure | Job은 `completed_with_warnings`가 되고 project는 `active` 유지 |
| Rollback failure | Job은 `rollback_failed`가 되고 manual cleanup 필요 |
| Unauthorized channel subscription | Subscription rejected |

## Debug Path

1. `ProvisioningJob` status와 `error_message`에서 시작한다.
2. Ordered `ProvisioningStep` row와 각 `result_snapshot`을 확인한다.
3. `app/services/provisioning/steps/`의 step class를 확인한다.
4. `app/clients/`의 external client response behavior를 확인한다.
5. Matching spec과 `spec/support/` mock helper를 확인한다.
