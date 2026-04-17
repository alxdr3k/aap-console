---
description: Global security rules. Always loaded.
alwaysApply: true
---

# Security Rules (Global)

These are enforced in code review and by hooks. Violations block merge.

## Secret Zero-Store

Console must never persist secrets in plaintext. Applies to:

- Keycloak Client Secrets, PAKs
- Langfuse SDK Keys (PK/SK)
- Any `*_API_KEY`, `*_TOKEN`, password, private key

Allowed paths:
- Display once in the UI at creation time, then discard.
- Forward to Config Server Admin API (`POST /admin/changes`) in the same request that surfaces to the user.

Forbidden:
- Writing secret values into Console DB columns.
- Logging secrets (including accidental inclusion in `inspect`, error messages, or exception backtraces).
- Committing `.env`, `credentials.yml*`, `*.pem`, `*.key` files. The hook blocks these Writes/Edits.

## Input validation boundaries

Validate at:
- HTTP request boundaries (strong params, typed coercion).
- External API responses (do not trust the shape; verify keys exist).

Do not over-validate internal calls between Console-owned services.

## SQL / XSS / command injection

- ActiveRecord for all queries. Never interpolate user input into raw SQL.
- Rails ERB auto-escapes; reach for `raw` or `html_safe` only with an audit trail.
- Never shell out with user input. If a shell is truly required, use `Open3.capture3` with an array argv.

## AuthN/AuthZ

- Every controller action calls `authorize_*!` (see HLD §8.4). No implicit "authenticated == authorized" assumptions.
- `super_admin` is Keycloak-driven (realm role). Org/project roles are Console-DB-driven.
- Session holds `sub` and `realm_roles` only. Do not stash PII.

## External service policy

- All external service calls go through `app/clients/*`. No ad-hoc `Faraday.new` in services/controllers/jobs.
- Tests must stub via WebMock — real calls are blocked by the bash-guard hook.
- Keycloak Client mutations: verify `aap-` prefix before calling delete/update.

## Audit logging

- Every state-changing action writes an `audit_logs` row (`user_sub`, `action`, `resource_type`, `resource_id`, `details`).
- Do not put secrets in `details`. Metadata only.
