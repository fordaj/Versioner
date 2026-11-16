#!/usr/bin/env bash
# update.sh — refresh bundled runner-spawner binaries from fordaj/runner-spawner releases.
#
# Thin wrapper around tools/update.sh (the shared implementation). See that
# script for the download/verify/stage/swap logic; this wrapper only declares
# the runner-spawner bundle's settings. Unlike the other bundles, a missing
# checksums file is fatal: runner-spawner manages self-hosted CI runners, so
# unverified binaries are refused.
#
# Usage:
#   tools/runner-spawner/update.sh              # download latest, replace old versions
#   tools/runner-spawner/update.sh --dry-run    # resolve tag + list assets, change nothing
#   tools/runner-spawner/update.sh --help       # usage
#
# Layout after a successful run (example for v0.0.1.2.7):
#   tools/runner-spawner/
#     update.sh
#     v0.0.1.2.7/
#       macos-arm64/runner-spawner
#       macos-x86_64/runner-spawner
#       linux-arm64/runner-spawner
#       linux-x86_64/runner-spawner
#       windows-x86_64/runner-spawner
#
# Env:
#   RUNNER_SPAWNER_TOOL_REPO  Repository slug (default: fordaj/runner-spawner)
#   RUNNER_SPAWNER_TAG        Pinned tag (default: latest release)

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

export TOOL_ROOT="$SCRIPT_DIR"
export UPDATE_TOOL_NAME=runner-spawner
export UPDATE_BIN_NAME=runner-spawner
export UPDATE_DEFAULT_REPO=fordaj/runner-spawner
export UPDATE_REPO_ENV=RUNNER_SPAWNER_TOOL_REPO
export UPDATE_TAG_ENV=RUNNER_SPAWNER_TAG
export UPDATE_ASSET_SUFFIX=""
export UPDATE_EXTRA_FILES=""
export UPDATE_REQUIRE_CHECKSUMS=1

exec "$SCRIPT_DIR/../update.sh" "$@"
