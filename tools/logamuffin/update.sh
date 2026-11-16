#!/usr/bin/env bash
# update.sh — refresh bundled logamuffin binaries from fordaj/logamuffin releases.
#
# Thin wrapper around tools/update.sh (the shared implementation). See that
# script for the download/verify/stage/swap logic; this wrapper only declares
# the logamuffin bundle's settings.
#
# Usage:
#   tools/logamuffin/update.sh              # download latest, replace old versions
#   tools/logamuffin/update.sh --dry-run    # resolve tag + list assets, change nothing
#   tools/logamuffin/update.sh --help       # usage
#
# Layout after a successful run (example for v0.1.3.4):
#   tools/logamuffin/
#     update.sh
#     v0.1.3.4/
#       macos-arm64/logamuffin
#       macos-x86_64/logamuffin
#       linux-arm64/logamuffin
#       linux-x86_64/logamuffin
#       windows-x86_64/logamuffin
#
# Env:
#   LOGAMUFFIN_REPO  Repository slug (default: fordaj/logamuffin)
#   LOGAMUFFIN_TAG   Pinned tag (default: latest release)

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

export TOOL_ROOT="$SCRIPT_DIR"
export UPDATE_TOOL_NAME=logamuffin
export UPDATE_BIN_NAME=logamuffin
export UPDATE_DEFAULT_REPO=fordaj/logamuffin
export UPDATE_REPO_ENV=LOGAMUFFIN_REPO
export UPDATE_TAG_ENV=LOGAMUFFIN_TAG
export UPDATE_ASSET_SUFFIX=""
export UPDATE_EXTRA_FILES=""
export UPDATE_REQUIRE_CHECKSUMS=0

exec "$SCRIPT_DIR/../update.sh" "$@"
