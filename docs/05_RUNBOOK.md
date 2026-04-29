# AAP Console — Runbook

운영 절차 모음이다. 명령은 실제 repo에 존재하는 것만 적는다.

## Local Setup

Requirements:

- Ruby 3.3.6 (`.ruby-version`)
- Bundler
- SQLite3

Setup:

```bash
bundle install
bin/rails db:setup
```

## Local Run

```bash
bin/dev
```

Alternative split process:

```bash
bin/rails server
bundle exec solid_queue:start
```

## Environment Variables

| Variable | Purpose |
|---|---|
| `KEYCLOAK_URL` | Keycloak base URL |
| `KEYCLOAK_REALM` | Keycloak realm |
| `KEYCLOAK_CLIENT_ID` | Console OIDC client ID |
| `KEYCLOAK_CLIENT_SECRET` | Console OIDC client secret |
| `LANGFUSE_URL` | Langfuse URL |
| `LANGFUSE_SERVICE_EMAIL` | Langfuse service account email |
| `LANGFUSE_SERVICE_PASSWORD` | Langfuse service account password |
| `CONFIG_SERVER_URL` | aap-config-server URL |
| `CONFIG_SERVER_API_KEY` | Console to Config Server Admin API key |
| `CONSOLE_INBOUND_API_KEY` | Config Server to Console `GET /api/v1/apps` key |

Secret은 commit하지 않는다. `.env.local` 같은 local environment injection은
project-approved loader와 함께 사용한다.

## Deployment

Deployment config exists in:

- `Dockerfile`
- `config/deploy.yml`
- `.kamal/`

The active manual deploy command is not documented in this repo yet. Treat deployment
operation as `not_run` until the release owner records the exact command and rollback
procedure.

## Monitoring / Debug Paths

| Area | Check |
|---|---|
| App health | `GET /up` |
| Provisioning job | Inspect `provisioning_jobs.status`, `error_message`, `warnings` |
| Provisioning steps | Inspect `provisioning_steps.status`, `error_message`, `result_snapshot` |
| Background jobs | SolidQueue process from `bin/dev` or `bundle exec solid_queue:start` |
| External API mocks in test | `spec/support/keycloak_mock.rb`, `spec/support/langfuse_mock.rb`, `spec/support/config_server_mock.rb` |

## Common Incidents

### Incident: Provisioning job is stuck in `retrying`

- Symptom: A job remains `retrying` after an external API failure.
- Detection: `provisioning_jobs.status = retrying`; scheduled job is expected after retry interval.
- Mitigation: Wait until scheduled retry time. If it does not resume, inspect SolidQueue state and the related step's `retry_count` / `error_message`.
- Root-cause investigation: Check `Provisioning::StepRunner`, `ProvisioningExecuteJob`, and external client mock/response path.
- Related: `AC-006`

### Incident: Job reaches `rollback_failed`

- Symptom: Provisioning job completes with `rollback_failed`.
- Detection: `provisioning_jobs.status = rollback_failed`; failed rollback step has `error_message`.
- Mitigation: 모든 external side effect가 정리됐다고 가정하지 않는다. 완료/실패 step의 `result_snapshot`을 확인하고 영향을 받은 external resource를 수동 복구한다.
- Root-cause investigation: Check `Provisioning::RollbackRunner` and the failing step's rollback implementation.
- Related: `AC-006`, `AC-010`

### Incident: Config Server is unavailable

- Symptom: Config lookup/apply views or steps fail, while local Console CRUD may still work.
- Detection: `ConfigServerClient` errors in job or request path.
- Mitigation: Confirm `CONFIG_SERVER_URL` and `CONFIG_SERVER_API_KEY`; retry provisioning if side effects are safe.
- Root-cause investigation: Check Config Server availability and Console `app_registry_webhook_job` retries.
- Related: `AC-005`

## Data Operations

| Operation | Procedure |
|---|---|
| Test DB prepare | `bin/rails db:test:prepare` |
| Local DB recreate | `bin/rails db:drop db:create db:migrate` |
| Migration status | `bin/rails db:migrate:status` |
| Schema source | `db/schema.rb`, `db/*_schema.rb` |

## Validation Before Release

Canonical command list는 `docs/current/TESTING.md`를 사용한다.

## Change Log

| Date | Change | By |
|---|---|---|
| 2026-04-29 | Initial runbook migrated from README and current repo commands | Codex |
