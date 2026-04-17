# AAP Console — Project Charter for Claude Code

> This file is Claude Code's persistent instructions for this repository. Kept under 200 lines. See `docs/harness-methodology.md` for the theory behind this setup.

## Project identity

AAP Console is a **Rails 8 + Hotwire + SolidQueue + SQLite** self-service management console for onboarding Organizations and Projects onto the AI Assistant Platform (AAP). It orchestrates **Keycloak**, **Langfuse**, **LiteLLM**, and an internal **Config Server** through provisioning pipelines with all-or-nothing semantics.

The repository currently contains **documentation only** (PRD / HLD / ADRs / UI spec). Code scaffolding has not started. Treat the docs as the ground truth.

## Reference documents

- @docs/PRD.md — Product requirements (what the system must do)
- @docs/HLD.md — High-level design (how it is structured)
- @docs/ui-spec.md — UI specification
- @docs/development-process.md — TDD workflow rules
- @docs/ai-assisted-project-design-guide.md — How this project collaborates with AI
- @docs/harness-methodology.md — Harness theory and the rationale for this setup
- @docs/business-objectives.md — Business objectives
- ADRs: @docs/adr-001-provisioning-orchestration.md · @docs/adr-002-langfuse-api-strategy.md · @docs/adr-003-external-api-integration-strategy.md · @docs/adr-004-auth-authz-separation.md · @docs/adr-005-sqlite-litestream.md · @docs/adr-006-hotwire-server-rendering.md

## Non-negotiable rules

### Language

- **Commit messages, code comments, code identifiers, and variable names**: **English only**. This rule is violated frequently; enforce it every time.
- **Documentation prose (`docs/**/*.md`)**: **Korean** (this project's domain is Korean).
- **CLAUDE.md, .claude/**, and harness artifacts**: **English** for operational clarity.

### TDD (from docs/development-process.md)

- Cycle is strictly **RED → GREEN → REFACTOR**.
- Write the failing test first, confirm it fails, then implement the minimum to pass, then refactor.
- Commits pair **test + implementation** together. Refactors may be separate commits.
- External services (Keycloak, Langfuse, LiteLLM, Config Server) must **always be mocked** (WebMock/VCR). Never hit real services from tests.

### Secret Zero-Store

- The Console must **never persist secrets** in plaintext. Surface once, hand off to Config Server Admin API, then discard.
- Do not write API keys, tokens, private keys, or `.env` contents into source files. If a value looks like a secret, route it through environment variables or the Config Server path.

### All-or-Nothing Provisioning

- Every provisioning step must be reversible. Partial-success states are forbidden.
- When implementing a provisioner, pair it with a rollback path and a test that exercises the rollback.

### Scope discipline

- Console decides **what** to configure; Config Server decides **how** to store/propagate. Do not leak Config Server internals into Console code or docs.
- Do not expand the system beyond what PRD/HLD describes. New capability → new PRD/HLD revision first.

## Project layout (planned)

```
app/
  controllers/            # Thin; authz check + render
  services/               # Business logic, external-API orchestration
    keycloak/             # Keycloak Admin API client + operations
    langfuse/             # Langfuse tRPC client + operations
    config_server/        # Config Server Admin API client
  jobs/                   # SolidQueue background jobs (ProvisioningJob, WebhookJob)
  channels/               # ActionCable channels (ProvisioningChannel)
  models/                 # ActiveRecord models with state machines
  views/                  # Hotwire (ERB + Turbo Frames/Streams)
  javascript/controllers/ # Stimulus controllers
spec/
  factories/              # FactoryBot
  support/                # WebMock helpers (keycloak_mock.rb, langfuse_mock.rb)
  models/ services/ jobs/ requests/ system/
docs/                     # PRD, HLD, ADRs, specs (Korean)
.claude/                  # Harness configuration (this setup)
```

## Standard commands

```bash
# Tests (after Rails scaffold exists)
bundle exec rspec                           # full suite
bundle exec rspec spec/services/...         # targeted
COVERAGE=true bundle exec rspec             # with SimpleCov

# Lint / style (after Rails scaffold exists)
bundle exec rubocop
bundle exec rubocop -A                      # autofix

# Rails
bin/rails db:migrate
bin/rails db:migrate:status
bin/rails routes | grep <pattern>
```

Do not assume these work today. They will once the Rails app is scaffolded.

## External API policy

- Never call Keycloak, Langfuse, LiteLLM, or Config Server from Claude Code (`curl`, `wget`, or Ruby code paths that bypass WebMock). Hooks enforce this.
- Stubs live in `spec/support/keycloak_mock.rb`, `spec/support/langfuse_mock.rb`, etc.
- Keycloak Client naming convention: `aap-{org-id}-{project-id}-{protocol}`. Only touch clients with the `aap-` prefix (PRD 5.4).

## Document etiquette (while the project is doc-only)

- PRD/HLD/ADRs carry `Version` and `Date` metadata. Bump both when editing material content.
- Run cross-doc consistency check after any substantive change: PRD terminology ↔ HLD schemas ↔ ADRs.
- Do not embed conversation artifacts ("이전에 논의한 바와 같이") in documents.
- Scope containment: PRD must not describe Config Server internals; HLD must not dictate UI copy; ADRs stay focused on one decision.

## Delegation defaults

- Broad exploration → `Explore` subagent (read-only, Haiku).
- Cross-doc consistency work → `docs-consistency-checker` (see `.claude/agents/`).
- Document declutter runs → `docs-declutter`.
- Commit message review → `commit-lint`.
- Architecture design discussion → `rails-architect` (read-only planning).

## Branching

- Active development branch for harness work: `claude/harness-documentation-implementation-gAK2F`.
- Never force-push. Never push to `main` directly.
- Commit messages follow: `<type>(<scope>): <description>` (English). Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `harness`.

## When to update this file

Add a rule here when:
- Claude makes the same correction twice in a session.
- A review surfaces a pattern Claude should have known.
- A domain constraint (organisational, legal, security) isn't discoverable from code.

Keep this file factual and specific. Move procedural how-to content into `.claude/rules/` path-scoped files, not here.
