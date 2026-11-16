#!/usr/bin/env bash
# update.sh — refresh bundled barnacle binaries from fordaj/barnacle releases.
#
# Thin wrapper around tools/update.sh (the shared implementation). See that
# script for the download/verify/stage/swap logic; this wrapper only declares
# the barnacle bundle's settings.
#
# Usage:
#   tools/barnacle/update.sh              # download latest, replace old versions
#   tools/barnacle/update.sh --dry-run    # resolve tag + list assets, change nothing
#   tools/barnacle/update.sh --help       # usage
#
# Layout after a successful run (example for v0.1.2.3):
#   tools/barnacle/
#     update.sh
#     v0.1.2.3/
#       macos-arm64/barnacle
#       macos-x86_64/barnacle
#       linux-arm64/barnacle
#       linux-x86_64/barnacle
#       windows-x86_64/barnacle
#
# Env:
#   BARNACLE_REPO  Repository slug (default: fordaj/barnacle)
#   BARNACLE_TAG   Pinned tag (default: latest release)

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

export TOOL_ROOT="$SCRIPT_DIR"
export UPDATE_TOOL_NAME=barnacle
export UPDATE_BIN_NAME=barnacle
export UPDATE_DEFAULT_REPO=fordaj/barnacle
export UPDATE_REPO_ENV=BARNACLE_REPO
export UPDATE_TAG_ENV=BARNACLE_TAG
export UPDATE_ASSET_SUFFIX=""
export UPDATE_EXTRA_FILES="LICENSE"
export UPDATE_REQUIRE_CHECKSUMS=0

exec "$SCRIPT_DIR/../update.sh" "$@"
