#!/usr/bin/env bash
# PostToolUse hook (async) for Write|Edit: non-blocking nudges.
# Never blocks; only prints short advice to stderr when heuristics match.

set -euo pipefail

input="$(cat)"

read -r file_path tool_name <<EOF
$(python3 - <<'PY' <<<"$input"
import json, sys
try:
    e = json.load(sys.stdin)
except Exception:
    print("")
    sys.exit(0)
ti = e.get("tool_input") or {}
print((ti.get("file_path") or "").strip(), e.get("tool_name") or "")
PY
)
EOF

[ -z "${file_path:-}" ] && exit 0

case "$file_path" in
  */docs/*.md)
    echo "[advice] docs touched: consider running the docs-consistency-checker agent before committing." >&2
    ;;
  */app/**/*.rb|*/app/*.rb)
    echo "[advice] Rails code touched: pair with a spec under spec/ (RED→GREEN→REFACTOR)." >&2
    ;;
  */CLAUDE.md)
    echo "[advice] CLAUDE.md changed: keep under 200 lines; move procedural rules into .claude/rules/." >&2
    ;;
  */.claude/settings.json)
    echo "[advice] settings.json changed: verify JSON is valid and hooks remain executable." >&2
    ;;
esac

exit 0
