#!/usr/bin/env bash
# PreToolUse hook for Bash: defense-in-depth against risky commands beyond the deny list.
# Blocks commands that attempt to call real external services directly, disable WebMock,
# or alter git protections. Settings.json already denies the obvious ones; this catches
# variants (quoted URLs, piped curls, git aliases).
#
# Contract: stdin = PreToolUse event JSON. Exit 2 to block, exit 0 to allow.

set -euo pipefail

input="$(cat)"

cmd="$(python3 - <<'PY' <<<"$input"
import json, sys
try:
    e = json.load(sys.stdin)
    print((e.get("tool_input") or {}).get("command") or "")
except Exception:
    print("")
PY
)"

if [ -z "$cmd" ]; then
  exit 0
fi

block() {
  printf '[bash-guard] Blocked: %s\n' "$1" >&2
  printf 'Reason: %s\n' "$2" >&2
  exit 2
}

# Real external service calls must go through WebMock/VCR in tests, not shell.
if printf '%s' "$cmd" | grep -Eiq '(curl|wget|http|httpie)([[:space:]]|\b).*(keycloak|langfuse|litellm|config-server|aap-config-server)'; then
  block "network call to protected external service" \
        "Mock via spec/support/*_mock.rb. See docs/development-process.md §2.3."
fi

# Disabling WebMock outside test helpers is forbidden.
if printf '%s' "$cmd" | grep -Eq 'WebMock\.(disable|allow_net_connect)'; then
  block "WebMock disable attempt" \
        "External services must remain stubbed. If you need a new stub, add it under spec/support/."
fi

# Force push to main/master, even via aliases.
if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push.*(-f|--force).*\b(main|master)\b'; then
  block "force push to main/master" "Never force-push protected branches."
fi

# rm -rf on / or $HOME roots.
if printf '%s' "$cmd" | grep -Eq 'rm[[:space:]]+(-[a-zA-Z]*[rf][a-zA-Z]*)+([[:space:]]+--)?([[:space:]]+[\"'\'']?)?(/([[:space:]]|$)|\$HOME([[:space:]]|/|$)|~([[:space:]]|/|$))'; then
  block "recursive delete at filesystem root" "Refusing destructive rm."
fi

exit 0
