#!/usr/bin/env bash
# Stop hook: final sanity check before the agent hands the turn back.
# Currently checks the last commit message language (CLAUDE.md rule: English commits).
# Non-blocking in most cases — prints a warning so the model can self-correct next turn.

set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

last_msg="$(git log -1 --pretty=%B 2>/dev/null || true)"
[ -z "$last_msg" ] && exit 0

# Detect CJK characters in the most recent commit message.
if printf '%s' "$last_msg" | LC_ALL=C grep -Pq '[^\x00-\x7F]'; then
  echo "[pre-stop] Warning: last commit message contains non-ASCII characters." >&2
  echo "CLAUDE.md requires English commit messages. Consider amending or writing the next commit in English." >&2
fi

# Warn if working tree has unstaged changes that look like secret files.
if git status --porcelain 2>/dev/null | grep -Eq '(\.env|\.pem|\.key|credentials\.yml)'; then
  echo "[pre-stop] Warning: sensitive-looking file is modified. Do not commit secrets." >&2
fi

exit 0
