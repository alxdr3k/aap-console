# AAP Console — Code Map

구현된 Rails app의 얇은 navigation map이다.

## Entry Points

| Path | Purpose |
|---|---|
| `config/routes.rb` | Auth, organizations, projects, config versions, provisioning jobs, `api/v1/apps` HTTP route |
| `app/controllers/application_controller.rb` | 공통 authentication/current user setup |
| `app/controllers/sessions_controller.rb` | Keycloak OIDC callback/logout/failure 처리 |
| `app/controllers/api/v1/apps_controller.rb` | Config Server app registry read API |

## Runtime / App

| Path | Purpose |
|---|---|
| `app/controllers/organizations_controller.rb` | Organization CRUD |
| `app/controllers/projects_controller.rb` | Project CRUD와 service 호출 |
| `app/controllers/members_controller.rb` | Org membership과 project permission 관리 |
| `app/controllers/auth_configs_controller.rb` | Project auth config update와 provisioning trigger |
| `app/controllers/litellm_configs_controller.rb` | LiteLLM config update와 provisioning trigger |
| `app/controllers/config_versions_controller.rb` | Config version index/show/rollback entry point |
| `app/controllers/project_api_keys_controller.rb` | Project-scoped PAK issue/list/revoke API |
| `app/controllers/provisioning_jobs_controller.rb` | Provisioning job show/retry/secrets endpoint |
| `app/channels/provisioning_channel.rb` | Provisioning job status용 ActionCable stream |
| `app/controllers/api/v1/project_api_keys_controller.rb` | Inbound PAK verification API |
| `app/jobs/provisioning_execute_job.rb` | Provisioning orchestration을 실행하는 SolidQueue job |
| `app/jobs/provisioning_jobs_cleanup_job.rb` | Retention window가 지난 성공 계열 terminal provisioning job/step cleanup |
| `app/jobs/app_registry_webhook_job.rb` | Standalone app registry webhook retry job. Current provisioning steps call the webhook inline |

## Domain / Services

| Path | Purpose |
|---|---|
| `app/services/projects/create_service.rb` | Project create transaction과 provisioning job setup |
| `app/services/projects/update_service.rb` | Project update와 provisioning trigger |
| `app/services/projects/destroy_service.rb` | Project deletion flow |
| `app/services/project_api_keys/` | PAK issue/revoke/verify services. Plaintext token is returned only from issue response |
| `app/services/organizations/create_service.rb` | Organization create flow |
| `app/services/organizations/update_service.rb` | Organization update flow with Langfuse org name sync |
| `app/services/organizations/destroy_service.rb` | Organization deletion flow |
| `app/services/provisioning/step_seeder.rb` | Operation별 provisioning step plan |
| `app/services/provisioning/orchestrator.rb` | Step group execution, retry scheduling, rollback decision, completion broadcast |
| `app/services/provisioning/step_runner.rb` | Individual step retry/defer execution |
| `app/services/provisioning/rollback_runner.rb` | Completed-step rollback execution |
| `app/services/provisioning/steps/*.rb` | Keycloak, Langfuse, Config Server, app registry, DB cleanup, health check step |
| `app/services/config_versions/rollback_service.rb` | Config Server rollback restore + diagnostics |
| `app/clients/keycloak_client.rb` | Keycloak Admin API client |
| `app/clients/langfuse_client.rb` | Langfuse tRPC client |
| `app/clients/config_server_client.rb` | Config Server Admin/read API client |
| `app/services/result.rb` | Service result object |

## Views / Assets

| Path | Purpose |
|---|---|
| `app/views/layouts/application.html.erb` | Minimal application layout |
| `app/views/sessions/login.html.erb` | SSO auto-submit login page |
| `app/views/pwa/` | Generated PWA placeholder views |
| `app/assets/stylesheets/application.css` | Placeholder stylesheet |

There is no `app/javascript/` tree and no Turbo/Stimulus controller wiring yet.

## Data / Persistence

| Path | Purpose |
|---|---|
| `app/models/organization.rb` | Organization aggregate root |
| `app/models/project.rb` | Project lifecycle와 App ID |
| `app/models/org_membership.rb` | Org-level role |
| `app/models/project_permission.rb` | Project-specific permission |
| `app/models/project_auth_config.rb` | Main auth configuration |
| `app/models/project_api_key.rb` | PAK digest/prefix metadata and active/revoked state |
| `app/models/provisioning_job.rb` | Provisioning job state |
| `app/models/provisioning_step.rb` | Provisioning step state |
| `app/models/config_version.rb` | Config version history |
| `app/models/audit_log.rb` | Audit event |
| `app/models/authorization.rb` | Persisted model이 아닌 authorization policy helper |
| `app/models/current.rb` | Per-request current user context |
| `db/schema.rb` | Main schema source |
| `db/*_schema.rb` | Solid Rails auxiliary schema |

## Tests

| Path | Purpose |
|---|---|
| `spec/requests/` | Controller/request behavior |
| `spec/services/` | Service와 provisioning behavior |
| `spec/services/provisioning/steps/` | Mock 기반 external step behavior |
| `spec/clients/` | External client request/response behavior |
| `spec/models/` | Model validation/state helper |
| `spec/jobs/` | Background job execution |
| `spec/channels/` | ActionCable connection/channel behavior |
| `spec/support/*_mock.rb` | External service용 WebMock helper |

## Needs Audit

| Path | Reason |
|---|---|
| `app/views/` / `app/javascript/` | Core product UI, Hotwire provisioning timeline/retry UX, secret reveal, config UI, Playground, and dashboard leaves are planned in `UI-5A.*`, `UI-5B.*`, `SEC-5B.1`, `UI-5C.*`, `PLAY-8A.*`, `ADMIN-8A.*` |
| `app/controllers/members_controller.rb` and related services | Current member API manages org membership roles only; Keycloak pre-assignment and project permission CRUD are `CORE-5A.2` |
| `app/services/organizations/destroy_service.rb` | Current org delete starts child project delete jobs and returns; final org cleanup after async project deletion is `CORE-5A.3` |
| `app/jobs/` | `AuditLogsArchiveJob` is not implemented; tracked by `OPS-7A.3` |
