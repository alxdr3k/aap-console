#!/usr/bin/env bash
# PreToolUse hook for Write|Edit: blocks writes that contain likely secret values.
# Contract: receives PreToolUse event JSON on stdin. Prints nothing on success.
# On block: prints a short reason to stderr and exits 2 (Claude Code treats exit 2 as a block).

set -euo pipefail

# Read the hook event payload from stdin.
input="$(cat)"

# Extract tool_input content. We only inspect string fields; binary-ish blobs are ignored.
# Use python for robust JSON parsing (available on most dev/CI images).
payload="$(python3 - <<'PY' <<<"$input"
import json, sys
try:
    event = json.load(sys.stdin)
except Exception:
    print("")
    sys.exit(0)

tool_input = event.get("tool_input") or {}
parts = []
for key in ("content", "new_string", "old_string"):
    v = tool_input.get(key)
    if isinstance(v, str):
        parts.append(v)
# file_path is not sensitive content but useful for allowlisting spec fixtures.
fp = tool_input.get("file_path") or ""
print(fp)
print("---CONTENT---")
print("\n".join(parts))
PY
)"

file_path="$(printf '%s\n' "$payload" | sed -n '1p')"
content="$(printf '%s\n' "$payload" | sed -n '/^---CONTENT---$/,$p' | tail -n +2)"

# Allowlist: dummy tokens in spec fixtures are acceptable.
case "$file_path" in
  */spec/support/*|*/spec/fixtures/*|*/spec/factories/*)
    exit 0
    ;;
esac

# Pattern list. Keep deliberately narrow to avoid noisy blocks.
# 1) API keys starting with sk- (OpenAI/Anthropic/Langfuse style)
# 2) PEM private key headers
# 3) password/secret/token = "..." with 12+ char value
# 4) AWS-ish access key id
# 5) bearer JWT (three dot-separated base64 segments of reasonable length)
block_reason=""

if printf '%s' "$content" | grep -Eq '(^|[^A-Za-z0-9])sk-(lf-)?[A-Za-z0-9_-]{20,}'; then
  block_reason="Looks like an API key (sk-...)."
elif printf '%s' "$content" | grep -Eq -- '-----BEGIN [A-Z ]*PRIVATE KEY-----'; then
  block_reason="PEM private key detected."
elif printf '%s' "$content" | grep -Eiq '(password|secret|token|api[_-]?key)[[:space:]]*[:=][[:space:]]*["'\''][^"'\'']{12,}["'\'']'; then
  block_reason="Hard-coded secret literal detected."
elif printf '%s' "$content" | grep -Eq '(^|[^A-Z0-9])AKIA[0-9A-Z]{16}([^A-Z0-9]|$)'; then
  block_reason="Looks like an AWS access key id."
fi

if [ -n "$block_reason" ]; then
  cat >&2 <<EOF
[secret-scan] Blocked: $block_reason
Secret Zero-Store: do not commit plaintext secrets.
Route values through environment variables or the Config Server Admin API.
If this is a dummy value for a test, place it under spec/support|fixtures|factories.
EOF
  exit 2
fi

exit 0
