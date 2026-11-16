#!/usr/bin/env bash
# update.sh — refresh bundled formattington-lite binaries from fordaj/formattington releases.
#
# Thin wrapper around tools/update.sh (the shared implementation). See that
# script for the download/verify/stage/swap logic; this wrapper only declares
# the formattington-lite bundle's settings: only `-lite` archives are
# installed, and NOTICE.md + LICENSES/ are kept alongside the binary.
#
# Usage:
#   tools/formattington-lite/update.sh              # download latest, replace old versions
#   tools/formattington-lite/update.sh --dry-run    # resolve tag + list assets, change nothing
#   tools/formattington-lite/update.sh --help       # usage
#
# Layout after a successful run (example for v0.2.3.0):
#   tools/formattington-lite/
#     update.sh
#     v0.2.3.0/
#       macos-arm64/formattington
#       macos-x86_64/formattington
#       linux-arm64/formattington
#       linux-x86_64/formattington
#       windows-x86_64/formattington
#
# Env:
#   FORMATTINGTON_REPO  Repository slug (default: fordaj/formattington)
#   FORMATTINGTON_TAG   Pinned tag (default: latest release)

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

export TOOL_ROOT="$SCRIPT_DIR"
export UPDATE_TOOL_NAME=formattington-lite
export UPDATE_BIN_NAME=formattington
export UPDATE_DEFAULT_REPO=fordaj/formattington
export UPDATE_REPO_ENV=FORMATTINGTON_REPO
export UPDATE_TAG_ENV=FORMATTINGTON_TAG
export UPDATE_ASSET_SUFFIX=-lite
export UPDATE_EXTRA_FILES="NOTICE.md LICENSES"
export UPDATE_REQUIRE_CHECKSUMS=0

exec "$SCRIPT_DIR/../update.sh" "$@"
