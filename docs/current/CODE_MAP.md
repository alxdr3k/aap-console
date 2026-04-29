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
| `app/controllers/provisioning_jobs_controller.rb` | Provisioning job show/retry/secrets endpoint |
| `app/channels/provisioning_channel.rb` | Provisioning job status용 ActionCable stream |
| `app/jobs/provisioning_execute_job.rb` | Provisioning orchestration을 실행하는 SolidQueue job |
| `app/jobs/app_registry_webhook_job.rb` | Standalone app registry webhook retry job. Current provisioning steps call the webhook inline |

## Domain / Services

| Path | Purpose |
|---|---|
| `app/services/projects/create_service.rb` | Project create transaction과 provisioning job setup |
| `app/services/projects/update_service.rb` | Project update와 provisioning trigger |
| `app/services/projects/destroy_service.rb` | Project deletion flow |
| `app/services/organizations/create_service.rb` | Organization create flow |
| `app/services/organizations/destroy_service.rb` | Organization deletion flow |
| `app/services/provisioning/step_seeder.rb` | Operation별 provisioning step plan |
| `app/services/provisioning/orchestrator.rb` | Step group execution, retry scheduling, rollback decision, completion broadcast |
| `app/services/provisioning/step_runner.rb` | Individual step retry/defer execution |
| `app/services/provisioning/rollback_runner.rb` | Completed-step rollback execution |
| `app/services/provisioning/steps/*.rb` | Keycloak, Langfuse, Config Server, app registry, DB cleanup, health check step |
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
| `app/models/project_api_key.rb` | PAK schema/model. Controller는 아직 없음 |
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
| `app/controllers/config_versions_controller.rb` | External rollback completeness 확인 필요. `SPIKE-002` 참고 |
| `app/models/project_api_key.rb` | Model은 있으나 route/controller/service가 없다. `Q-001` 참고 |
| `app/views/` / `app/javascript/` | Hotwire provisioning timeline/retry UX는 ADR target이지만 current repo에는 아직 없다. `Q-002` 참고 |
