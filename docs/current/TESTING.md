# AAP Console — Testing

구현된 repo의 validation command다. 이 파일 밖의 명령을 새로 만들지 않는다.

## Install

```bash
bundle install
```

## Typecheck

별도 typecheck command는 현재 없다.

## Lint

```bash
RUBOCOP_CACHE_ROOT=tmp/rubocop bin/rubocop
```

## Unit / Request / Service Tests

```bash
bin/rspec
```

Targeted examples:

```bash
bin/rspec spec/services/provisioning/orchestrator_spec.rb
bin/rspec spec/requests/projects_spec.rb
bin/rspec spec/channels/provisioning_channel_spec.rb
```

Failed tests only:

```bash
bin/rspec --only-failures
```

Coverage:

```bash
COVERAGE=true bin/rspec
```

## Integration Tests

External service는 WebMock helper로 mock한다.

- `spec/support/keycloak_mock.rb`
- `spec/support/langfuse_mock.rb`
- `spec/support/config_server_mock.rb`

Test는 real Keycloak, Langfuse, LiteLLM, Config Server endpoint를 호출하면 안 된다.

## Security Checks

```bash
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit
```

GitHub Actions는 현재 다음을 실행한다.

- `bin/brakeman --no-pager`
- `bin/bundler-audit`
- `bin/rubocop -f github`
- `bin/rails db:test:prepare`
- `bin/rspec --format progress`

## CI / Required Checks

| Check | Local command | CI workflow / job | Required? | Notes |
|---|---|---|---|---|
| security scan | `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error` / `bin/bundler-audit` | `.github/workflows/ci.yml` | yes | CI command flags differ slightly; keep both in sync when policy changes. |
| lint | `RUBOCOP_CACHE_ROOT=tmp/rubocop bin/rubocop` | `.github/workflows/ci.yml` | yes | CI uses GitHub formatter. |
| test DB prepare | `bin/rails db:test:prepare` | `.github/workflows/ci.yml` | yes | Required before request/service specs. |
| specs | `bin/rspec` | `.github/workflows/ci.yml` | yes | Main automated behavior gate. |
| docs freshness | n/a | `.github/workflows/doc-freshness.yml.example` | no | Example only; not active. |

The active CI workflow runs on pull requests and direct pushes to `main` or
`dev`.

CI/CD design guidance lives in `docs/11_CI_CD.md`.

## Evals

Eval command는 현재 없다.

## DB / Migration Checks

```bash
bin/rails db:test:prepare
bin/rails db:migrate:status
```

## Before Opening A PR

Run:

```bash
bin/rspec
RUBOCOP_CACHE_ROOT=tmp/rubocop bin/rubocop
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit
```

Behavior/schema/runtime이 바뀌면 관련 문서를 업데이트한다.

- `docs/04_IMPLEMENTATION_PLAN.md`
- `docs/context/current-state.md`
- `docs/current/CODE_MAP.md`
- `docs/current/DATA_MODEL.md`
- `docs/current/RUNTIME.md`
- `docs/current/OPERATIONS.md`
- `docs/06_ACCEPTANCE_TESTS.md`
