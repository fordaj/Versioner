#!/usr/bin/env bash
# Format the versioner repository in place with formattington.
#
#   ./scripts/format.sh              # format all matching files in place
#   ./scripts/format.sh --series     # format sequentially (ordered output)
#   ./scripts/format.sh --verbose    # show which formatter executables were resolved
#
# Formattington (https://github.com/fordaj/formattington) is pinned in
# pyproject.toml (git commit) and locked in uv.lock. This project uses
# Python 3.14 (see .python-version), the latest version it supports.
# No pip/venv setup is needed: `uv run` creates .venv/ automatically.
#
# Scope (see .formattington.json):
#   markdown (*.md) / json (*.json) / yaml (*.yml)   -> prettier
#   go (*.go)                                        -> gofmt, goimports
#   shell (*.sh, *.bash)                              -> shfmt (-i 2)
#   toml (*.toml)                                     -> taplo
#
# Prerequisites (formatter executables must be on PATH; formattington
# exits 127 if one is missing):
#   * uv (https://docs.astral.sh/uv/)
#   * shfmt, prettier, taplo, goimports (e.g. via your OS package manager;
#     prettier: `npm install -g prettier`;
#     goimports: `go install golang.org/x/tools/cmd/goimports@latest`)
#
# To check formatting without modifying files (CI):
#   ./ci/format_check.sh
#
# Extra flags are forwarded to `formattington` before `all`
# (e.g. --series, --verbose). --config is managed here; do not pass it.
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

exec uv run formattington "$@" --config "$REPO_ROOT/.formattington.json" all
