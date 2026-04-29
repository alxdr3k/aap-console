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

### Project API Keys

- Project users with `write` permission can issue and revoke PAKs through `ProjectApiKeysController`.
- The issue response includes the plaintext `token` once. Console stores only `token_digest` and `token_prefix`.
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
- Client는 `GET /provisioning_jobs/:id`로 polling할 수도 있다.
- Turbo Stream/Stimulus consumer와 provisioning ERB timeline은 아직 구현되지 않았다.

### Retention Cleanup

- `ProvisioningJobsCleanupJob`은 180일이 지난 `completed`, `completed_with_warnings`, `rolled_back` provisioning job을 삭제한다.
- 삭제된 job의 `provisioning_steps`는 함께 삭제된다.
- 연결된 모든 `ConfigVersion`은 보존되며 `provisioning_job_id`만 null 처리된다.
- `failed` / `rollback_failed` job은 manual inspection을 위해 보존된다.
- Production schedule은 `config/recurring.yml`의 `provisioning_jobs_cleanup`에 둔다.

## Planned / Partial Flow

| Flow | State |
|---|---|
| Organization/member completion | Designated initial admin and Langfuse org name sync are landed in `CORE-5A.1`; Keycloak pre-assignment and project permission CRUD API are landed in `CORE-5A.2`; org delete finalization is landed in `CORE-5A.3`; member/org UI remains in `UI-5A.*` |
| Hotwire provisioning detail UI | ActionCable server path만 있고 Turbo/Stimulus consumer는 없음. `Q-002` is resolved by `DEC-004`; follow-up is `UI-5B.*` / `AC-015` |
| Secret reveal cache write path | `ProvisioningJobsController#secrets` reads cache, but provisioning steps do not write Keycloak/PAK secrets to the TTL cache yet. Tracked by `SEC-5B.1` |
| Config/product UI | Auth config, LiteLLM config, and config-version APIs exist, but server-rendered product UI is `UI-5C.*` |
| Full external config rollback | Current rollback restores Config Server and reports Keycloak/Langfuse as non-snapshotted diagnostics. Full Keycloak/Langfuse snapshot restore is `OPS-7A.5` / `AC-022` |
| SAML/OAuth/PAK UI | Backend/API gate is accepted by `DEC-003`; product UI remains `AUTH-6A.*` |
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
