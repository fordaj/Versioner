#!/usr/bin/env bash
# Check formatting without modifying files (for CI).
#
#   ./ci/format_check.sh              # exit 1 if anything needs formatting
#   ./ci/format_check.sh --series     # check sequentially (ordered output)
#   ./ci/format_check.sh --verbose    # show which formatter executables were resolved
#
# This is the check-only counterpart of ./scripts/format.sh: it runs the same
# formattington configuration (.formattington.json) with --check, so it
# never rewrites files. See ./scripts/format.sh for scope, prerequisites, and
# version-pinning details.
#
# Exit codes (formattington): 0 = clean, 1 = formatting required,
# 2 = usage/config error, 127 = formatter executable missing.
#
# Extra flags are forwarded to `formattington` before `all`
# (e.g. --series, --verbose). --config and --check are managed here;
# do not pass them.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v uv >/dev/null 2>&1; then
  echo "ERROR: uv not found (https://docs.astral.sh/uv/)" >&2
  exit 1
fi

# goimports installed via `go install` lands in $(go env GOPATH)/bin,
# which is not always on PATH. Prepend it when Go is available.
if command -v go >/dev/null 2>&1; then
  GOPATH_BIN="$(go env GOPATH)/bin"
  if [[ -d "$GOPATH_BIN" && ":$PATH:" != *":$GOPATH_BIN:"* ]]; then
    export PATH="$GOPATH_BIN:$PATH"
  fi
fi

exec uv run formattington --check "$@" --config "$REPO_ROOT/.formattington.json" all
