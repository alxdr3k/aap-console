# AAP Console — Operations

구현된 repo의 얇은 operational reference다.

## Local Run

Web server:

```bash
bin/dev
```

`bin/dev` currently execs `bin/rails server`; it does not start a worker.

Worker, in a separate shell when provisioning jobs must run locally:

```bash
bin/jobs
```

Equivalent worker command:

```bash
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
| `CONSOLE_INBOUND_API_KEY` | Config Server to Console app registry API key |

Secret은 commit하지 않는다.

## Database

- Main schema: `db/schema.rb`
- Queue schema: `db/queue_schema.rb`
- Cache schema: `db/cache_schema.rb`
- Cable schema: `db/cable_schema.rb`

Useful commands:

```bash
bin/rails db:setup
bin/rails db:migrate:status
bin/rails db:test:prepare
```

## Logs / Observability

- Rails log는 `log/` 아래에 있다.
- Audit event는 `audit_logs`에 저장된다.
- Provisioning diagnostics는 `provisioning_jobs.error_message`, `warnings`,
  `provisioning_steps.error_message`, `result_snapshot`에 저장된다.
- Langfuse는 onboarded project용 external observability integration이다. 이 repo의
  Console-internal tracing backend는 아니다.

## Background Jobs

- Runtime job backend: SolidQueue.
- Main job: `app/jobs/provisioning_execute_job.rb`.
- App registry retry job: `app/jobs/app_registry_webhook_job.rb` exists, but the current provisioning steps call the app-registry webhook inline.
- Local worker: `bin/jobs` 또는 `bundle exec solid_queue:start`. `bin/dev`는 worker를 시작하지 않는다.
- Production Kamal config sets `SOLID_QUEUE_IN_PUMA=true`, so the web Puma process runs the SolidQueue supervisor unless deployment config changes.

## Deployment

Deployment artifact는 존재한다.

- `Dockerfile`
- `config/deploy.yml`
- `.kamal/`

정확한 production deployment command와 rollback procedure는 이 migration에서
검증하지 않았다. Deployment를 accepted gate로 보기 전에 여기에 기록해야 한다.
Litestream sidecar/restore wiring도 현재 repo 배포 설정에는 아직 없다.

## Troubleshooting

| Symptom | Check |
|---|---|
| Provisioning job stuck | `provisioning_jobs.status`, scheduled SolidQueue jobs, step `retry_count` |
| `rollback_failed` | Failed step `error_message`, completed step `result_snapshot`, external resource side effects |
| Local DB lock | Local server/worker를 중지한 뒤 안전할 때 `bin/rails db:drop db:create db:migrate` |
| External API test failure | `spec/support/`의 matching WebMock helper |

Operational incident와 procedure는 `docs/05_RUNBOOK.md`에 둔다.
