# AAP Console

AI Assistant Platform (AAP) 셀프서비스 관리 콘솔. Organization / Project 온보딩 시 Keycloak, Langfuse, LiteLLM, Config Server 등 공유 서비스 설정을 자동으로 프로비저닝한다.

> **문서 기준점**: [PRD](./docs/01_PRD.md) · [HLD](./docs/02_HLD.md) · [UI Spec](./docs/ui-spec.md) · [ADR](./docs/adr/)
> **현재 상태**: [current-state](./docs/context/current-state.md) · [roadmap/status ledger](./docs/04_IMPLEMENTATION_PLAN.md) · [current docs](./docs/current/)

---

## 기술 스택

| 영역 | 기술 |
|------|------|
| Backend | Ruby on Rails 8 |
| Frontend | Rails server-rendered ERB + importmap-backed Turbo/Stimulus baseline. Core product pages are being added under `UI-5A.*` |
| Background Job | SolidQueue |
| Realtime | ActionCable + SolidCable |
| Database | SQLite (WAL). Litestream 백업은 ADR/배포 target이며 현재 repo 배포 설정에는 아직 wired sidecar가 없다 |
| Auth | Keycloak (OIDC) + Console DB RBAC |

## 로컬 개발 환경

### 1. 요구 사항

- Ruby 3.3.6 (`.ruby-version` 참조)
- Bundler
- SQLite3

### 2. 셋업

```bash
bundle install
bin/rails db:setup   # db:create + db:migrate + db:seed
```

### 3. 필수 환경변수

외부 서비스 호출은 기본적으로 WebMock으로 차단되며, 실제 값이 없어도 테스트는 동작한다. 운영/스테이징 배포 시에는 아래 값이 필요하다.

| 변수 | 용도 |
|------|------|
| `KEYCLOAK_URL` | Keycloak 서버 base URL |
| `KEYCLOAK_REALM` | Realm 이름 (예: `aap`) |
| `KEYCLOAK_CLIENT_ID` | Console OIDC Client ID |
| `KEYCLOAK_CLIENT_SECRET` | Console OIDC Client Secret |
| `LANGFUSE_URL` | Langfuse 서버 URL |
| `LANGFUSE_SERVICE_EMAIL` | Langfuse 서비스 계정 이메일 |
| `LANGFUSE_SERVICE_PASSWORD` | Langfuse 서비스 계정 비밀번호 |
| `CONFIG_SERVER_URL` | aap-config-server URL |
| `CONFIG_SERVER_API_KEY` | Console → Config Server Admin API 호출용 |
| `CONSOLE_INBOUND_API_KEY` | Config Server → Console `GET /api/v1/apps` 호출용 |

시크릿은 절대 커밋하지 않는다. `.env.local` 을 만들어 `direnv` / `dotenv` 로 주입한다.

### 4. 실행

```bash
bin/dev           # Rails server only
# 또는
bin/rails server
bin/jobs          # SolidQueue worker in a separate shell
```

## 테스트

```bash
bin/rspec                           # 전체
bin/rspec spec/services/provisioning/orchestrator_spec.rb   # 단일 파일
bin/rspec --only-failures           # 실패한 것만 재실행
COVERAGE=true bin/rspec             # SimpleCov 리포트
```

TDD 필수 (RED → GREEN → REFACTOR). 상세는 [docs/development-process.md](./docs/development-process.md).

## 외부 서비스 Mock

모든 외부 API 호출은 테스트에서 WebMock으로 stub한다. 실제 서비스는 절대 호출하지 않는다.

- `spec/support/keycloak_mock.rb`
- `spec/support/langfuse_mock.rb`
- `spec/support/config_server_mock.rb`

로컬 개발 중 실제 서비스를 연동하려면 별도 지시가 있을 때만 환경변수로 real endpoint를 주입한다.

## 프로비저닝 파이프라인

Project 생성/수정/삭제 요청은 `ProvisioningExecuteJob` → `Provisioning::Orchestrator` → `Provisioning::StepRunner` → 개별 Step으로 실행된다.

- Step plan은 `Provisioning::StepSeeder` 가 `operation` 에 따라 seed
- 병렬 그룹은 동일 `step_order` 로 묶임 (Rails executor + connection pool 래핑)
- 재시도는 backoff (≤ 8초는 inline, 이상은 SolidQueue scheduled re-enqueue)
- 실패 시 `RollbackRunner` 가 완료된 step을 역순 롤백
- `failed` step도 `result_snapshot` 이 남아있으면 롤백 대상에 포함되어 외부 side effect 가 누출되지 않는다 (atomicity gap 방지)
- `health_check` 실패는 롤백 대신 `completed_with_warnings` 로 처리

### 비동기 Update API 계약

설정 변경(LiteLLM Config, 인증 설정)은 모두 비동기 프로비저닝으로 전파되며, 응답 계약이 통일되어 있다.

| 엔드포인트 | 외부 전파가 필요한 변경 | 외부 전파가 없는 변경 |
|-----------|----------------------|---------------------|
| `PATCH /organizations/:org/projects/:slug/auth_config` | `202 Accepted` + `{ provisioning_job_id }` | `200 OK` + `{ message }` |
| `PATCH /organizations/:org/projects/:slug/litellm_config` | `202 Accepted` + `{ provisioning_job_id }` | `200 OK` + `{ message }` |

API 소비자는 `provisioning_job_id` 로 `GET /provisioning_jobs/:id` 를 polling 하거나 `ProvisioningChannel` (ActionCable) 을 구독해 진행 상태를 받는다.

## 디렉토리 구조 요약

```
app/
  controllers/       # 인증·인가 + 서비스 호출
  services/
    projects/        # Create/Update/Destroy
    provisioning/    # Orchestrator, StepRunner, StepSeeder, RollbackRunner, steps/
    ...
  clients/           # Keycloak/Langfuse/ConfigServer HTTP 클라이언트 (WebMock 대상)
  jobs/              # SolidQueue Jobs
  channels/          # ActionCable (프로비저닝 현황 streaming)
  models/
spec/                # RSpec + FactoryBot + WebMock
docs/                # PRD / HLD / ADR / UI Spec (한글)
.claude/             # Claude Code harness (English)
```

## 트러블슈팅

- **`bin/rspec` 이 안 보인다** → `bundle binstubs rspec-core --force` 로 재생성
- **DB 락** → `db/development.sqlite3-journal` 잔존 시 `bin/rails db:drop db:create db:migrate`
- **프로비저닝 Job이 멈췄다** → `provisioning_jobs` 상태 확인, `status: retrying` 이면 스케줄된 시각 이후 자동 재시도. `rollback_failed` 는 수동 개입 필요

## 기여

- 커밋 메시지는 영문, `<type>(<scope>): <description>` 규칙 (`feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `harness`)
- 문서 prose는 한글
- PR 전 필수: `bin/rspec`, `RUBOCOP_CACHE_ROOT=tmp/rubocop bin/rubocop`, `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error`, `bin/bundler-audit`
- 배포 가능 상태 확인은 [roadmap/status ledger](./docs/04_IMPLEMENTATION_PLAN.md)와 [acceptance gates](./docs/06_ACCEPTANCE_TESTS.md) 참조
