#!/usr/bin/env bash
# FileChanged hook for .env / .envrc / .env.local.
# Non-blocking: reminds the operator that secrets must not be committed and the
# Config Server is the authoritative path for runtime secrets.

set -euo pipefail

echo "[env-change-warn] .env* modified." >&2
echo "Reminder: do not commit these files. Runtime secrets flow through the Config Server Admin API." >&2
exit 0
