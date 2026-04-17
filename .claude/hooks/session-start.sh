#!/usr/bin/env bash
# SessionStart hook: seeds the session with a compact project status snapshot.
# Emits JSON with `additionalContext` to inject a small header before the first user turn.

set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || true

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
head="$(git log -1 --pretty=format:'%h %s' 2>/dev/null || echo 'no commits')"
dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
worktrees="$(git worktree list 2>/dev/null | wc -l | tr -d ' ')"

# Keep this short. CLAUDE.md already carries the stable rules.
context=$(cat <<EOF
AAP Console — session context
- branch: ${branch}
- HEAD: ${head}
- working tree: ${dirty} changed file(s)
- worktrees: ${worktrees}
- stage: documentation-only (no Rails code yet); see docs/harness-methodology.md §7.2 for S1 posture.
- reminder: commits in English, docs in Korean, external services must be mocked.
EOF
)

python3 - "$context" <<'PY'
import json, sys
ctx = sys.argv[1]
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx}}))
PY
