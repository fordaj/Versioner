#!/usr/bin/env bash
# scripts/env.sh — source the environment cascade.
#
#   source scripts/env.sh
#
# Sources scripts/.common.env (the base cascade) followed by the
# platform file scripts/.<os>-<arch>.env selected from `uname`
# (for example .macos-x86_64.env). The cascade files define the
# variables; this script only locates them, sources them, and
# anchors the repository-relative tool paths (tools/...) to the
# repository root so they resolve from any working directory.
# Works in bash and zsh, sourced from any directory.

if [ -n "${BASH_VERSION:-}" ]; then
  _env_sh_path="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  # zsh: %x expands to the file being sourced. Kept inside eval so
  # bash (and shfmt) never parse the zsh-only parameter flag.
  _env_sh_path="$(eval 'printf "%s" "${(%):-%x}"')"
else
  _env_sh_path="$0"
fi
ENV_DIR="$(cd -- "$(dirname -- "$_env_sh_path")" && pwd)"
REPO_ROOT_DIR="$(cd -- "$ENV_DIR/.." && pwd)"
unset _env_sh_path

set -a
# shellcheck disable=SC1091
. "$ENV_DIR/.common.env"
case "$(uname -s):$(uname -m)" in
Darwin:x86_64) . "$ENV_DIR/.macos-x86_64.env" ;;
Darwin:arm64) . "$ENV_DIR/.macos-arm64.env" ;;
Linux:x86_64) . "$ENV_DIR/.linux-x86_64.env" ;;
Linux:aarch64) . "$ENV_DIR/.linux-arm64.env" ;;
MINGW*:x86_64 | MSYS*:x86_64 | CYGWIN*:x86_64) . "$ENV_DIR/.windows-x86_64.env" ;;
MINGW*:aarch64 | MSYS*:aarch64 | CYGWIN*:aarch64 | MINGW*:arm64 | MSYS*:arm64 | CYGWIN*:arm64) . "$ENV_DIR/.windows-arm64.env" ;;
*)
  echo "Unsupported platform: $(uname -s) $(uname -m)" >&2
  set +a
  # shellcheck disable=SC2317
  return 1 2>/dev/null || exit 1
  ;;
esac

# Anchor the repository-relative tool binaries to the repo root.
# Absolute paths are left untouched.
case "${VERSIONER_BIN:-}" in "" | /*) ;; *) VERSIONER_BIN="$REPO_ROOT_DIR/$VERSIONER_BIN" ;; esac
case "${LOGAMUFFIN_BIN:-}" in "" | /*) ;; *) LOGAMUFFIN_BIN="$REPO_ROOT_DIR/$LOGAMUFFIN_BIN" ;; esac
case "${RUNNER_SPAWNER_BIN:-}" in "" | /*) ;; *) RUNNER_SPAWNER_BIN="$REPO_ROOT_DIR/$RUNNER_SPAWNER_BIN" ;; esac
case "${BARNACLE_BIN:-}" in "" | /*) ;; *) BARNACLE_BIN="$REPO_ROOT_DIR/$BARNACLE_BIN" ;; esac

set +a
