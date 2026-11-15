#!/usr/bin/env bash
# scripts/build.sh — cross-compile versioner for the major operating
# systems and processor architectures.
#
#   scripts/build.sh
#
# Writes dist/<platform>/versioner (versioner.exe on Windows) for each
# target platform, using the version computed by versioner (see
# scripts/version.bash) stamped into the binary via -ldflags.
#
# Environment:
#   VERSION   Override the version string embedded in the binaries.

set -euo pipefail

ENTRY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$ENTRY_DIR/entry.sh"

REPO_ROOT="$REPO_ROOT_DIR"
cd "$REPO_ROOT"

if [[ -z "${VERSION:-}" ]]; then
  eval "$("$ENTRY_DIR/version.bash" --format shell)"
fi
log INFO "building versioner $VERSION"

if ! command -v go >/dev/null 2>&1; then
  log ERROR "go toolchain not found on PATH"
  exit 1
fi

# Same target matrix as the Makefile `cross` target so dist/ has one
# consistent layout (darwin-amd64, darwin-arm64, linux-amd64,
# linux-arm64, windows-amd64).
PLATFORMS=(
  darwin:amd64
  darwin:arm64
  linux:amd64
  linux:arm64
  windows:amd64
)

for entry in "${PLATFORMS[@]}"; do
  goos="${entry%%:*}"
  goarch="${entry##*:}"
  platform="$goos-$goarch"

  out_dir="dist/$platform"
  bin="versioner"
  if [[ "$goos" == "windows" ]]; then
    bin="versioner.exe"
  fi
  mkdir -p "$out_dir"

  log INFO "building $out_dir/$bin ($goos/$goarch)"
  GOOS="$goos" GOARCH="$goarch" CGO_ENABLED=0 \
    go build -trimpath -ldflags "-s -w -X main.toolVersion=$VERSION" \
    -o "$out_dir/$bin" .
done

log INFO "done: binaries in dist/"
