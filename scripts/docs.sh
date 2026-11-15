#!/usr/bin/env bash
# scripts/docs.sh — generate the repository's documentation site with barnacle.
#
# Barnacle (https://github.com/fordaj/barnacle) turns the Markdown and
# Mermaid files scattered through the repository into a static, navigable
# HTML site. This script runs the bundled binary from
# tools/barnacle/v<version>/<platform>/ (refresh with
# tools/barnacle/update.sh; resolved via scripts/entry.sh) against the
# repository root, so ./site is generated next to .formattington.json.
#
# The generated site is written to ./site by default (git-ignored). Any
# arguments are forwarded to barnacle verbatim, so barnacle's own options
# work natively:
#
#   scripts/docs.sh                          # generate into ./site
#   scripts/docs.sh --site ./public          # generate elsewhere
#   scripts/docs.sh --config ./docs/barnacle.json
#
# Usage:
#   scripts/docs.sh [barnacle options...]
#   scripts/docs.sh --help
#
# Env:
#   BARNACLE_BIN   Path to the barnacle binary (default: via scripts/entry.sh).

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)
if [[ ! -f "$REPO_ROOT/scripts/entry.sh" ]]; then
  printf 'docs.sh: error: script entry point not found: %s/scripts/entry.sh\n' "$REPO_ROOT/scripts/entry.sh" >&2
  exit 1
fi
# shellcheck disable=SC1091
. "$REPO_ROOT/scripts/entry.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
Usage: scripts/docs.sh [barnacle options...]

Generate the repository's documentation site with barnacle. With no
options, the site is written to ./site (relative to the repository root).
Any options are forwarded to barnacle verbatim; see `barnacle --help`.

Options handled by this script:
  --help, -h   Show this help and exit.

Environment:
  BARNACLE_BIN   Path to the barnacle binary (default: the bundle under
                 tools/barnacle/v<version>/<platform>/, resolved via
                 scripts/entry.sh).

The bundled binaries are refreshed with tools/barnacle/update.sh.
EOF
  exit 0
fi

if [[ -z "${BARNACLE_BIN:-}" ]]; then
  log ERROR "no barnacle binary found (run tools/barnacle/update.sh, or set BARNACLE_BIN)"
  exit 1
fi
[[ -x "$BARNACLE_BIN" ]] || {
  log ERROR "BARNACLE_BIN=$BARNACLE_BIN is not executable (run tools/barnacle/update.sh, or set BARNACLE_BIN)"
  exit 1
}
log INFO "using barnacle: $BARNACLE_BIN"

# barnacle resolves ./.barnacle.json and ./site relative to the cwd; run it
# from the repository root so the site lands at the repository root no
# matter where this script is invoked from.
cd -- "$REPO_ROOT"
"$BARNACLE_BIN" "$@"
log INFO "documentation site generated (default: $REPO_ROOT/site; override with --site <path>)"
