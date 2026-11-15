#!/usr/bin/env bash
#
# version.sh - print the version of the repository.
#
# The version is computed by versioner (see tools/versioner and
# .versioner.json), so the version of a build and the version of a release
# can never drift apart.
#
# Usage:
#   scripts/version.sh                 # prints "VERSION=<v>" and "TAG=<t>"
#   scripts/version.sh --format shell  # prints "export VERSION=..." lines
#   scripts/version.sh --format json   # prints the raw versioner json
#
# Environment:
#   VERSIONER_BIN        Path to the versioner binary. This repository IS
#                        versioner, so when VERSIONER_BIN is unset or not
#                        executable the script falls back to `go run .`.
#   VERSIONER_REPO_DIR   Repository to inspect (default: the repository root).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/entry.sh"

FORMAT="text"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --format)
    [[ $# -ge 2 ]] || {
      log ERROR "--format requires a value"
      exit 2
    }
    FORMAT="$2"
    shift 2
    ;;
  --format=*)
    FORMAT="${1#--format=}"
    shift
    ;;
  --help | -h)
    cat <<'EOF'
Usage: scripts/version.sh [--format text|shell|json]

Print the version of the repository computed by versioner.

  text   VERSION=<version> and TAG=<tag> lines (default)
  shell  export VERSION=... and export TAG=... lines
  json   the raw json document produced by versioner
EOF
    exit 0
    ;;
  *)
    log ERROR "unknown argument: $1"
    exit 2
    ;;
  esac
done

REPO_DIR="${VERSIONER_REPO_DIR:-${REPO_ROOT_DIR:-$SCRIPT_DIR/..}}"
REPO_DIR="$(cd -- "$REPO_DIR" && pwd)"

VERSIONER_CMD=("$VERSIONER_BIN")
if [[ -z "${VERSIONER_BIN:-}" || ! -x "${VERSIONER_BIN:-}" ]]; then
  if command -v go >/dev/null 2>&1; then
    VERSIONER_CMD=(go run .)
  else
    log ERROR "no versioner binary found and no go toolchain on PATH (set VERSIONER_BIN)"
    exit 1
  fi
fi

if [[ "$FORMAT" == "json" ]]; then
  (cd "$REPO_DIR" && "${VERSIONER_CMD[@]}" --repo-dir "$REPO_DIR" --quiet --format json)
  exit 0
fi

OUTPUT="$(cd "$REPO_DIR" && "${VERSIONER_CMD[@]}" --repo-dir "$REPO_DIR" --quiet)"

VERSION="$(printf '%s\n' "$OUTPUT" | sed -n 's/^VERSION=//p' | tail -1)"
TAG="$(printf '%s\n' "$OUTPUT" | sed -n 's/^TAG=//p' | tail -1)"

[[ -n "$VERSION" ]] || {
  log ERROR "could not parse VERSION from the versioner output"
  exit 1
}
[[ -n "$TAG" ]] || {
  log ERROR "could not parse TAG from the versioner output"
  exit 1
}

case "$FORMAT" in
text)
  printf 'VERSION=%s\n' "$VERSION"
  printf 'TAG=%s\n' "$TAG"
  ;;
shell)
  printf 'export VERSION=%s\n' "$VERSION"
  printf 'export TAG=%s\n' "$TAG"
  ;;
*)
  log ERROR "unknown format: $FORMAT (expected text, shell or json)"
  exit 2
  ;;
esac
