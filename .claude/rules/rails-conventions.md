---
description: Rails 8 conventions for app/ and spec/ code.
paths:
  - app/**/*.rb
  - spec/**/*.rb
  - config/**/*.rb
---

# Rails Conventions

Load only when editing Ruby under `app/`, `spec/`, or `config/`. Rails 8 + SolidQueue + SQLite; Hotwire is the target UI architecture, not fully wired in current code.

## TDD is non-negotiable

- RED: write a failing spec first. Confirm it fails with the **expected** message (not an unrelated NoMethodError).
- GREEN: minimal code to pass. Hard-coding is acceptable at this step; the next test forces generalization.
- REFACTOR: only with a green bar. No new behavior.
- Each commit pairs test + implementation. Pure-refactor commits are allowed only when tests already pass.

## Layer responsibilities

- **Controller**: authn/authz check, param extraction, service call, render. No DB logic, no external API calls.
- **Service** (`app/services/**`): orchestrates a unit of work. Single DB transaction when needed. Returns `Result.success(data)` / `Result.failure(msg)`.
- **Client** (`app/clients/**`): pure HTTP surface over one external system. No business logic, no DB.
- **Model**: validations, associations, scopes, state machine transitions. No external API calls.
- **Job** (SolidQueue): retries, concurrency control, idempotency. Delegates business decisions to services/orchestrators.
- **Provisioning Step**: one external API call plus its rollback. Must implement `execute`, `rollback`, `already_completed?`.

## Naming

- Keycloak clients created by Console: `aap-{org-id}-{project-id}-{protocol}`. Only touch clients with the `aap-` prefix (PRD §5.4) — verify at code level before any mutation.
- App IDs: `app-{SecureRandom.alphanumeric(12)}`.
- Service objects: `<Domain>::<Verb>Service` (e.g. `Projects::CreateService`).
- Clients: `<System>Client` (e.g. `KeycloakClient`).

## External services

- **Never** hit real Keycloak, Langfuse, LiteLLM, or Config Server from tests. Use WebMock via `spec/support/*_mock.rb`.
- **Never** call them from ad-hoc scripts or `rails runner` invocations during development of this repo. The bash-guard hook enforces this at the shell level.
- Secret values (Client Secret, PAK, SDK Keys) must never be persisted to Console DB. Surface once, pass to Config Server, discard.

## State machines

- Provisioning states follow PRD FR-7.1: `pending → in_progress → (completed | failed → retrying → ... | rolling_back → (rolled_back | rollback_failed))`.
- Every transition is audit-logged. Every `rolling_back` has a matching rollback plan based on `result_snapshot`.

## Testing patterns

- `spec/requests/**` for controller + routing, prefer over `spec/controllers`.
- `spec/services/**` for service objects.
- `spec/clients/**` for external API clients (WebMock-heavy).
- `spec/system/**` for Capybara end-to-end flows.
- Factories in `spec/factories/**`. Avoid `create` when `build_stubbed` suffices.
- Coverage target: 90% (SimpleCov). New code without specs is rejected in review.

## Hotwire defaults

- Default to server-rendered ERB + Turbo when adding UI. Reach for Stimulus only when a DOM-local interaction has no server counterpart.
- Current provisioning realtime code broadcasts JSON via `ProvisioningChannel.broadcast_to`; only switch to `Turbo::StreamsChannel.broadcast_replace_to` when the matching Turbo Stream views/frames exist.
- Keep Stimulus controllers small and single-purpose. No client-side state that duplicates server state.
