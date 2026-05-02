# AAP Console — Project Charter for Claude Code

> This file is Claude Code's persistent instructions for this repository. Keep it short. For Codex/agent read order, see `AGENTS.md`.

## Project Identity

AAP Console is a **Rails 8 + SolidQueue + SQLite** self-service management console for onboarding Organizations and Projects onto the AI Assistant Platform (AAP). It orchestrates **Keycloak**, **Langfuse**, **LiteLLM**, and an internal **Config Server** through provisioning pipelines with all-or-nothing semantics. The Hotwire baseline (importmap, Turbo, Stimulus, ActionCable) accepted in ADR-006 is wired in; product ERB pages are landing under `UI-5A.*` / `UI-5B.*` / `UI-5C.*`.

The repository contains an implemented Rails app with RSpec/WebMock coverage. Code, tests, migrations, and generated schemas are authoritative for implemented behavior.

## Read Order

1. `docs/context/current-state.md`
2. `docs/04_IMPLEMENTATION_PLAN.md`
3. `docs/current/CODE_MAP.md`
4. `docs/current/TESTING.md`
5. Task-relevant source/tests
6. ADRs only when changing architecture or product scope

## Reference Documents

- `docs/01_PRD.md` — product requirements
- `docs/02_HLD.md` — high-level design
- `docs/04_IMPLEMENTATION_PLAN.md` — roadmap/status ledger
- `docs/06_ACCEPTANCE_TESTS.md` — acceptance gates
- `docs/ui-spec.md` — UI specification
- `docs/current/` — current implementation navigation
- `docs/development-process.md` — TDD workflow rules
- `docs/adr/` — architecture decisions

## Non-negotiable Rules

### Language

- **Commit messages, code comments, code identifiers, and variable names**: English only.
- **Documentation prose (`docs/**/*.md`)**: Korean.
- **CLAUDE.md, `.claude/`, and harness artifacts**: English.

### TDD

- Cycle is **RED -> GREEN -> REFACTOR**.
- Write the failing test first, confirm it fails, implement the minimum to pass, then refactor.
- Commits pair test + implementation together. Refactors may be separate commits.
- External services must always be mocked. Never hit real Keycloak, Langfuse, LiteLLM, or Config Server from tests.

### Secret Zero-Store

- The Console must never persist secrets in plaintext.
- Do not write API keys, tokens, private keys, or `.env` contents into source files.
- If a value looks like a secret, route it through environment variables or the Config Server path.

### All-or-Nothing Provisioning

- Every provisioning step must be reversible unless explicitly documented as warning-only.
- When implementing a provisioner, pair it with rollback behavior and tests.
- `health_check` is the current warning-only step; see `docs/04_IMPLEMENTATION_PLAN.md`.

### Scope Discipline

- Console decides **what** to configure; Config Server decides **how** to store/propagate.
- Do not leak Config Server internals into Console code or docs.
- New capability requires PRD/HLD/roadmap update before implementation.

## Project Layout

```text
app/
  controllers/       # authz checks, request handling, rendering
  services/          # business logic and provisioning orchestration
  clients/           # external API clients
  jobs/              # SolidQueue jobs
  channels/          # ActionCable channels
  models/            # ActiveRecord models and policy helpers
  views/             # ERB views with Hotwire (Turbo Frames/Streams + Stimulus)
spec/
  factories/
  support/           # WebMock helpers
  models/ services/ jobs/ requests/ channels/ clients/
docs/
  context/ current/  # implementation-stage docs
  adr/               # architecture decisions
```

## Standard Commands

Use `docs/current/TESTING.md` as the canonical command source.

```bash
bin/rspec
RUBOCOP_CACHE_ROOT=tmp/rubocop bin/rubocop
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit
bin/rails db:migrate:status
```

## External API Policy

- Never call Keycloak, Langfuse, LiteLLM, or Config Server from Claude Code via `curl`, `wget`, or ad hoc Ruby scripts.
- Stubs live in `spec/support/keycloak_mock.rb`, `spec/support/langfuse_mock.rb`, and `spec/support/config_server_mock.rb`.
- Keycloak client naming convention: `aap-{org-id}-{project-id}-{protocol}`. Only touch clients with the `aap-` prefix.

## Documentation Etiquette

- `docs/04_IMPLEMENTATION_PLAN.md` owns roadmap/status ledger details.
- `docs/context/current-state.md` summarizes only the active position.
- `docs/current/` describes implemented state navigation, not future backlog.
- PRD/HLD/ADRs/UI spec carry `Version` and `Date` metadata. Bump both when editing material content.
- Do not embed conversation artifacts in documents.

## Branching

- Primary integration branch: `dev`.
- Never force-push.
- Never push to `main` directly.
- Commit messages follow `<type>(<scope>): <description>`.

## When To Update This File

Add a rule here only when it is stable repo guidance that is not better placed in `AGENTS.md`, `.claude/rules/`, or `docs/current/*`.
