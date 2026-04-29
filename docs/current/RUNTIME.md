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

## Planned / Partial Flow

| Flow | State |
|---|---|
| Config rollback external restore | Entry point는 있으나 completeness gap은 `SPIKE-002`에서 추적 |
| Hotwire provisioning detail UI | ActionCable server path만 있고 Turbo/Stimulus consumer는 없음. `Q-002` 참고 |
| SAML/OAuth/PAK provisioning | Model/schema 일부 외에는 미구현. `Q-001` 참고 |
| Playground | Phase 4로 deferred |

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
