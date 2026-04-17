---
description: Rules for HTTP clients in app/clients/ and their specs.
paths:
  - app/clients/**/*.rb
  - spec/clients/**/*.rb
---

# External API Client Rules

Clients under `app/clients/` are the only code paths that speak HTTP to external systems.

## Structural rules

- One file per external system. No cross-system logic inside a client.
- Inherit from a shared `BaseClient` that owns Faraday setup, JSON handling, error translation.
- Raise a client-specific error (`KeycloakClient::ApiError`, etc.) on non-2xx. Never leak raw Faraday exceptions upward.
- Configuration via `ActiveSupport::Configurable` with ENV-backed defaults. No hard-coded URLs or tokens.

## Per-client specifics

### KeycloakClient (PRD FR-2, FR-4)

- Service Account token caching with proactive refresh (refresh 30s before `expires_in`).
- `aap-` prefix invariant: before any mutation on a Client, verify `clientId` starts with `aap-`. Raise if not.
- Use dedicated scope endpoints for `default-client-scopes` / `optional-client-scopes` — the main `PUT /clients/{id}` body ignores these fields (Keycloak #24920).

### LangfuseClient (PRD FR-1, FR-5, ADR-002)

- tRPC over `POST /api/trpc/{procedure}` authenticated by NextAuth session cookie.
- Cookie lifecycle: lazy login on first call, re-login on 401, no background refresh.
- Service account credentials via `LANGFUSE_SERVICE_EMAIL` / `LANGFUSE_SERVICE_PASSWORD`. Never commit.
- tRPC is unofficial API; upgrades may break it. Integration tests run against a pinned Langfuse container.

### ConfigServerClient (PRD FR-6, FR-8)

- Auth: `Authorization: Bearer ${CONFIG_SERVER_API_KEY}`.
- Console sends plaintext secrets to `POST /admin/changes`; response is a version identifier. Do not log the request body.
- `DELETE /admin/changes` and `POST /admin/changes/revert` must be idempotent on repeat.
- App Registry webhook (`/admin/app-registry/webhook`) is fire-and-forget during normal operations but synchronous inside the provisioning pipeline.

## Testing

- All specs use WebMock. No real network calls, no VCR records against production.
- Stub helpers live in `spec/support/keycloak_mock.rb`, `spec/support/langfuse_mock.rb`, `spec/support/config_server_mock.rb`.
- Cover: 2xx happy path, 4xx validation error, 5xx transient error (should raise, triggering upstream retry), timeout, malformed JSON.

## Anti-patterns

- Do not let controllers or services call raw `Faraday.new` — they must go through a client.
- Do not put retry loops inside clients. Retry is the orchestrator's concern (per FR-7.2).
- Do not cache responses in-process unless explicitly documented (tokens only, and with a clear TTL).
