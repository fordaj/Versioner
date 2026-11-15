#!/usr/bin/env bash
set -euo pipefail

ENTRY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$ENTRY_DIR/env.sh"

# log LEVEL [MESSAGE ...]
#   LEVEL may be a word (INFO) or a number (50). When a logamuffin
#   binary is available all arguments are forwarded to it with
#   LOG_SOURCE set from the call site; otherwise a printf fallback
#   keeps the same `log LEVEL MESSAGE` call shape working (see the
#   header for filtering/stream semantics). The exit code is
#   preserved (2 for usage errors, 0 otherwise for the fallback).
log() {
  local bin
  bin="$LOGAMUFFIN_BIN"

  # Caller context -> LOG_SOURCE="file[:function]:line". BASH_SOURCE[1]
  # is the caller's file, BASH_LINENO[0] is the line that called
  # log(), and FUNCNAME[1] is the calling function (empty at top
  # level). Defaults keep `set -u` safe.
  local caller_file="${BASH_SOURCE[1]:-}"
  local caller_line="${BASH_LINENO[0]:-1}"
  local caller_func=""
  if ((${#FUNCNAME[@]} > 1)); then
    caller_func="${FUNCNAME[1]:-}"
  fi
  if [[ -z "$caller_file" ]]; then
    caller_file="${0:-log}"
  fi

  local src
  if [[ -n "$caller_func" && "$caller_func" != "log" && "$caller_func" != "main" ]]; then
    src="${caller_file}:${caller_func}:${caller_line}"
  else
    src="${caller_file}:${caller_line}"
  fi

  if [[ ! -x "$bin" ]]; then
    # No logamuffin binary: printf fallback (bootstrap / fresh clone).
    if [[ $# -eq 0 ]]; then
      printf '%s\n' "log: usage: log LEVEL MESSAGE..." >&2
      return 2
    fi
    local level_arg="${1:-}"
    shift
    local msg="$*"
    local level_upper level_value _thr_raw _thr_upper
    if [[ "$level_arg" =~ ^-?[0-9]+$ ]]; then
      level_value="$level_arg"
    else
      level_upper="$(printf '%s' "$level_arg" | tr '[:lower:]' '[:upper:]')"
      case "$level_upper" in
      TRACE) level_value=5 ;;
      DEBUG) level_value=10 ;;
      INFO) level_value=20 ;;
      WARNING | WARN) level_value=30 ;;
      ERROR) level_value=40 ;;
      CRITICAL | FATAL) level_value=50 ;;
      ALWAYS) level_value=-1 ;;
      *) level_value=20 ;;
      esac
    fi
    _thr_raw="${LOG_LEVEL:-${LOGAMUFFIN_LEVEL:-INFO}}"
    if [[ -z "$_thr_raw" ]]; then
      _thr_raw="INFO"
    fi
    if [[ "$_thr_raw" =~ ^-?[0-9]+$ ]]; then
      local threshold_value="$_thr_raw"
    else
      _thr_upper="$(printf '%s' "$_thr_raw" | tr '[:lower:]' '[:upper:]')"
      case "$_thr_upper" in
      TRACE) threshold_value=5 ;;
      DEBUG) threshold_value=10 ;;
      INFO) threshold_value=20 ;;
      WARNING | WARN) threshold_value=30 ;;
      ERROR) threshold_value=40 ;;
      CRITICAL | FATAL) threshold_value=50 ;;
      ALWAYS) threshold_value=-1 ;;
      *) threshold_value=20 ;;
      esac
    fi
    if [[ "$level_value" -ne -1 && "$level_value" -lt "$threshold_value" ]]; then
      return 0
    fi
    if [[ "$level_value" -ge 40 ]]; then
      printf '%s: [%s] %s\n' "$src" "$level_arg" "$msg" >&2
    else
      printf '%s: [%s] %s\n' "$src" "$level_arg" "$msg"
    fi
    return 0
  fi

  LOG_SOURCE="$src" "$bin" "$@"
  # Preserve `logamuffin`'s exit code (0 success/filtered,
  # 2 usage/config errors) even when `set -e` is active.
  return $?
}
