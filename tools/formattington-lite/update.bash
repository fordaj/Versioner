#!/usr/bin/env bash
# update.bash — refresh bundled formattington-lite binaries from fordaj/formattington releases.
#
# Downloads the latest release's per-platform executables via gh, verifies
# SHA256 checksums when the release ships them, extracts each binary into
# tools/formattington-lite/<tag>/<platform>/ (platform is the bundled <os>-<arch> layout:
# macos/linux/windows + x86_64/arm64, so darwin-amd64 -> macos-x86_64, etc.),
# and deletes old version folders. Old v*/ folders are deleted only after the
# new version is fully staged, so a failed download leaves the previous
# bundle intact.
#
# Archives are consumed in their platform-native formats: .tar.gz on
# macOS/Linux and .zip on Windows. Legacy .7z assets are still accepted as
# a fallback (requires 7z/7zz) so this script keeps working against releases
# cut before the format change; new releases do not need p7zip at all.
#
# Usage:
#   tools/formattington-lite/update.bash              # download latest, replace old versions
#   tools/formattington-lite/update.bash --dry-run    # resolve tag + list assets, change nothing
#   tools/formattington-lite/update.bash --help       # usage
#
# Prerequisites: gh (https://cli.github.com/) and tar/unzip (.7z assets
# additionally need 7z/7zz). The script resolves its own directory, so it can
# be run from anywhere. Logging uses log <level> <message> from
# scripts/entry.sh (logamuffin, with printf fallback).
#
# Layout after a successful run (example for v0.1.2.3):
#   tools/formattington-lite/
#     update.bash
#     v0.1.2.3/
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
REPO_ROOT_FOR_ENV=$(cd -- "$SCRIPT_DIR/../.." &>/dev/null && pwd)
if [[ ! -f "$REPO_ROOT_FOR_ENV/scripts/entry.sh" ]]; then
    printf 'update.bash: error: entry point not found: %s/scripts/entry.sh\n' "$REPO_ROOT_FOR_ENV" >&2
    exit 1
fi
# shellcheck disable=SC1091
. "$REPO_ROOT_FOR_ENV/scripts/entry.sh"

DRY_RUN=0
TAG="${FORMATTINGTON_TAG:-}"
REPO="${FORMATTINGTON_REPO:-fordaj/formattington}"

usage() {
    cat <<'EOF'
Usage: tools/formattington-lite/update.bash [--dry-run] [--tag TAG] [--repo REPO]

Download the latest formattington-lite release from GitHub via gh, extract each
platform binary into tools/formattington-lite/<tag>/<platform>/ (platform is the
bundled <os>-<arch> layout, e.g. darwin-amd64 -> macos-x86_64), and delete old
version folders. Only the binary is kept, plus NOTICE.md and LICENSES/.

Flags:
  --dry-run, -n   Resolve tag + list planned assets, change nothing.
  --tag TAG       Pin a specific release tag (default: latest release).
  --repo REPO     Repository slug (default: fordaj/formattington).
  --help, -h      Show this help.

Env:
  FORMATTINGTON_REPO  Repository slug (overridden by --repo).
  FORMATTINGTON_TAG   Pinned tag (overridden by --tag).
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --dry-run | -n)
        DRY_RUN=1
        shift
        ;;
    --help | -h)
        usage
        exit 0
        ;;
    --tag)
        [[ $# -ge 2 ]] || {
            log ERROR "--tag requires a value"
            usage >&2
            exit 2
        }
        TAG="$2"
        shift 2
        ;;
    --tag=*)
        TAG="${1#--tag=}"
        shift
        ;;
    --repo)
        [[ $# -ge 2 ]] || {
            log ERROR "--repo requires a value"
            usage >&2
            exit 2
        }
        REPO="$2"
        shift 2
        ;;
    --repo=*)
        REPO="${1#--repo=}"
        shift
        ;;
    *)
        log ERROR "unknown argument: $1"
        usage >&2
        exit 2
        ;;
    esac
done

[[ -n "$REPO" ]] || {
    log ERROR "repository must not be empty"
    exit 2
}

die() {
    log ERROR "$*" || true
    exit 1
}
need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

need_cmd gh
need_cmd tar

TOOL_ROOT="$SCRIPT_DIR"
[[ -d "$TOOL_ROOT" ]] || die "formattington-lite bundle directory not found: $TOOL_ROOT"
log INFO "formattington-lite bundle directory: $TOOL_ROOT"
log INFO "repository: $REPO"

if [[ -z "$TAG" ]]; then
    TAG="$(gh release view --repo "$REPO" --json tagName -q .tagName)" ||
        die "could not determine latest release from $REPO (is gh authenticated and the repo visible?)"
fi
[[ -n "$TAG" ]] || die "could not determine release tag from $REPO"
if ! [[ "$TAG" =~ ^v[0-9]+(\.[0-9]+)+$ ]]; then
    die "invalid tag '$TAG' (expected vX.Y.Z...)"
fi
log INFO "release tag: $TAG"

# parse_stem_to_platform <stem> sets PLATFORM (e.g.
# Versioner_v0.0.3.0.5_darwin-arm64 -> macos-arm64) or returns 1 for
# unknown values. Accepts any single separator before the os-arch suffix and
# normalizes x64 -> x86_64, amd64 -> x86_64, x86_64 -> x86_64, darwin -> macos.
parse_stem_to_platform() {
    local stem="$1"
    local suffix="${stem##*[-_]}"
    local prefix="${stem%[-_]*}"
    # Reconstruct the os-arch pair: strip a trailing -lite/-full from the suffix area first.
    case "$suffix" in
    lite | full)
        suffix="${prefix##*[-_]}"
        prefix="${prefix%[-_]*}"
        ;;
    esac
    # suffix may be e.g. "arm64" alone only when the os was in prefix; redo as regex below instead.
    if [[ "$stem" =~ [-_](darwin-amd64|darwin-arm64|darwin-x86_64|macos-x86_64|macos-arm64|macos-x64|macos-amd64|linux-x86_64|linux-amd64|linux-x64|linux-arm64|windows-x86_64|windows-amd64|windows-x64|windows-arm64)(-lite|-full)?$ ]]; then
        case "${BASH_REMATCH[1]}" in
        darwin-amd64 | darwin-x86_64 | macos-x86_64 | macos-x64 | macos-amd64) PLATFORM="macos-x86_64" ;;
        darwin-arm64 | macos-arm64) PLATFORM="macos-arm64" ;;
        linux-x86_64 | linux-amd64 | linux-x64) PLATFORM="linux-x86_64" ;;
        linux-arm64) PLATFORM="linux-arm64" ;;
        windows-x86_64 | windows-amd64 | windows-x64) PLATFORM="windows-x86_64" ;;
        windows-arm64) PLATFORM="windows-arm64" ;;
        *) return 1 ;;
        esac
        VARIANT="${BASH_REMATCH[2]#-}"
        return 0
    fi
    return 1
}

strip_archive_ext() {
    local name="$1"
    case "$name" in
    *.tar.gz) printf '%s' "${name%.tar.gz}" ;;
    *.zip) printf '%s' "${name%.zip}" ;;
    *.7z) printf '%s' "${name%.7z}" ;;
    *) printf '%s' "$name" ;;
    esac
}

if [[ "$DRY_RUN" -eq 1 ]]; then
    log INFO "DRY RUN: no download, extraction, or deletion will happen"
    log INFO "release $TAG assets:"
    assets_list=$(gh release view "$TAG" --repo "$REPO" --json assets -q '.assets[].name' ||
        die "could not list assets for $TAG in $REPO")
    [[ -n "$assets_list" ]] || die "no assets found for $TAG in $REPO"
    asset_count=0
    while IFS= read -r asset; do
        [[ -n "$asset" ]] || continue
        case "$asset" in
        *.tar.gz | *.zip | *.7z)
            stem="$(strip_archive_ext "$asset")"
            if [[ "-lite" != "" && "$stem" != *"-lite" ]]; then
                log INFO "  $asset (ignored: not a -lite archive)"
                continue
            fi
            asset_count=$((asset_count + 1))
            if parse_stem_to_platform "$stem"; then
                log INFO "  $asset -> $TAG/$PLATFORM"
            else
                log INFO "  $asset -> unknown platform (would fail)"
            fi
            ;;
        checksums.txt | SHA256SUMS.txt)
            log INFO "  $asset (checksums)"
            ;;
        *)
            log INFO "  $asset (ignored)"
            ;;
        esac
    done <<<"$assets_list"
    ((asset_count > 0)) || die "no platform archives found for $TAG in $REPO"
    shopt -s nullglob
    old_found=0
    for dir in "$TOOL_ROOT"/v*/; do
        [[ -d "$dir" ]] || continue
        dir_name="$(basename "$dir")"
        if [[ "$dir_name" != "$TAG" ]]; then
            log INFO "would remove old $dir_name"
            old_found=1
        fi
    done
    if [[ "$old_found" -eq 0 ]]; then
        log INFO "no old version folders to remove"
    fi
    log INFO "dry run complete: would update $TOOL_ROOT/$TAG"
    exit 0
fi

# --- Real update: download to a temp dir, stage the bundle, then swap. ---
TMP_DIR=""
STAGE_DIR=""
cleanup() {
    if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
        rm -rf -- "$TMP_DIR"
    fi
    if [[ -n "${STAGE_DIR:-}" && -d "$STAGE_DIR" ]]; then
        rm -rf -- "$STAGE_DIR"
    fi
}
trap cleanup EXIT

TMP_DIR="$(mktemp -d)"
STAGE_DIR="$(mktemp -d "$TOOL_ROOT/.tmp.XXXXXX")"

log INFO "downloading $TAG assets from $REPO..."
gh release download "$TAG" --repo "$REPO" --dir "$TMP_DIR" --pattern '*.tar.gz' --pattern '*.zip' --pattern '*.7z' --pattern 'checksums.txt' --pattern 'SHA256SUMS.txt' --clobber

shopt -s nullglob
archives=()
for archive in "$TMP_DIR"/*.tar.gz "$TMP_DIR"/*.zip "$TMP_DIR"/*.7z; do
    [[ -e "$archive" ]] || continue
    stem="$(strip_archive_ext "$(basename "$archive")")"
    if [[ "-lite" != "" && "$stem" != *"-lite" ]]; then
        continue
    fi
    archives+=("$archive")
done
((${#archives[@]} > 0)) || die "no platform archives downloaded from $REPO $TAG"
log INFO "downloaded ${#archives[@]} platform archives"

checksums_file=""
for candidate in checksums.txt SHA256SUMS.txt; do
    if [[ -f "$TMP_DIR/$candidate" ]]; then
        checksums_file="$TMP_DIR/$candidate"
        break
    fi
done
if [[ -n "$checksums_file" ]]; then
    log INFO "verifying checksums ($(basename "$checksums_file"))..."
    # The checksums file may be cumulative across releases (or list every
    # uploaded asset), so verify only the archives downloaded for this run.
    checksum_tool=""
    if command -v shasum >/dev/null 2>&1; then
        checksum_tool="shasum -a 256"
    elif command -v sha256sum >/dev/null 2>&1; then
        checksum_tool="sha256sum"
    fi
    [[ -n "$checksum_tool" ]] || die "checksums file present but neither shasum nor sha256sum found"
    verify_list="$TMP_DIR/.verify-list"
    : >"$verify_list"
    for archive in "${archives[@]}"; do
        base="$(basename "$archive")"
        grep -F " $base" "$checksums_file" >>"$verify_list" ||
            die "no checksum entry for downloaded asset $base in $(basename "$checksums_file")"
    done
    # Entries are "<sha>  <name>" (or with a leading *), relative to $TMP_DIR.
    (cd "$TMP_DIR" && $checksum_tool -c "$verify_list") || die "checksum verification failed for $TAG"
    log INFO "checksums verified"
else
    log WARNING "no checksums in $TAG release; skipping verification"
fi

# Extract one archive into a destination directory, format-agnostic.
extract_archive() {
    local archive="$1" dest="$2"
    case "$archive" in
    *.tar.gz)
        tar -xzf "$archive" -C "$dest"
        ;;
    *.zip)
        need_cmd unzip
        unzip -q "$archive" -d "$dest"
        ;;
    *.7z)
        if command -v 7zz >/dev/null 2>&1; then
            7zz x -y "$archive" -o"$dest" >/dev/null
        elif command -v 7z >/dev/null 2>&1; then
            7z x -y "$archive" -o"$dest" >/dev/null
        else
            die "legacy .7z asset $(basename "$archive") requires 7z/7zz (this release predates platform-native archives)"
        fi
        ;;
    *)
        die "unsupported archive format: $archive"
        ;;
    esac
}

for archive in "${archives[@]}"; do
    base="$(basename "$archive")"
    stem="$(strip_archive_ext "$base")"
    if ! parse_stem_to_platform "$stem"; then
        die "unknown platform in asset '$base' (expected <os>-<arch> such as darwin-arm64)"
    fi
    if [[ -e "$STAGE_DIR/$PLATFORM" ]]; then
        die "duplicate asset for platform $PLATFORM (from $base)"
    fi
    log INFO "extracting $base -> $TAG/$PLATFORM"
    extract_dir="$TMP_DIR/extract-$PLATFORM"
    mkdir -p "$extract_dir"
    extract_archive "$archive" "$extract_dir"
    bin_src=""
    for cand in "$extract_dir/formattington" "$extract_dir/formattington.exe"; do
        if [[ -f "$cand" ]]; then
            bin_src="$cand"
            break
        fi
    done
    if [[ -z "$bin_src" ]]; then
        # Some archives nest everything under a single top-level directory.
        for cand in "$extract_dir"/*/formattington "$extract_dir"/*/formattington.exe; do
            if [[ -f "$cand" ]]; then
                bin_src="$cand"
                break
            fi
        done
    fi
    [[ -n "$bin_src" ]] || die "no formattington binary in $base (expected formattington)"
    bin_name="$(basename "$bin_src")"
    target_dir="$STAGE_DIR/$PLATFORM"
    mkdir -p "$target_dir"
    cp -p "$bin_src" "$target_dir/$bin_name"
    chmod +x "$target_dir/$bin_name"
    [[ -s "$target_dir/$bin_name" ]] || die "installed binary is empty: $target_dir/$bin_name"
    for extra in NOTICE.md "LICENSES"; do
        if [[ -e "$extract_dir/$extra" ]]; then
            cp -pr "$extract_dir/$extra" "$target_dir/"
        fi
    done
    log INFO "installed $PLATFORM/$bin_name (from $base)"
    rm -rf -- "$extract_dir"
done

TAG_DIR="$TOOL_ROOT/$TAG"
rm -rf -- "$TAG_DIR"
mkdir -p "$TOOL_ROOT"
mv "$STAGE_DIR" "$TAG_DIR"
STAGE_DIR=""

for dir in "$TOOL_ROOT"/v*/; do
    [[ -d "$dir" ]] || continue
    dir_name="$(basename "$dir")"
    if [[ "$dir_name" != "$TAG" ]]; then
        log INFO "removing old $dir_name"
        rm -rf -- "$dir"
    fi
done

# Best-effort host verification: run the bundled binary for this machine.
host_os_raw="$(uname -s | tr '[:upper:]' '[:lower:]')"
host_arch_raw="$(uname -m | tr '[:upper:]' '[:lower:]')"
case "$host_os_raw" in
darwin*) host_os="macos" ;;
linux*) host_os="linux" ;;
msys* | mingw* | cygwin* | windows* | win*) host_os="windows" ;;
*) host_os="$host_os_raw" ;;
esac
case "$host_arch_raw" in
x86_64 | amd64) host_arch="x86_64" ;;
arm64 | aarch64) host_arch="arm64" ;;
*) host_arch="$host_arch_raw" ;;
esac
host_platform="$host_os-$host_arch"
host_bin=""
for cand in "$TAG_DIR/$host_platform/formattington" "$TAG_DIR/$host_platform/formattington.exe"; do
    if [[ -x "$cand" ]]; then
        host_bin="$cand"
    fi
done
if [[ -n "$host_bin" ]]; then
    host_ver="$("$host_bin" --version 2>&1 || true)"
    log INFO "host binary $host_platform reports: $host_ver"
    case "$host_ver" in
    *"$TAG"* | *"${TAG#v}"*) ;;
    *) log WARNING "host binary version '$host_ver' does not contain $TAG" ;;
    esac
else
    log WARNING "host platform $host_platform not in bundle; skipped version check"
fi

log INFO "done: $TAG_DIR now contains:"
for dir in "$TAG_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    log INFO "  $(basename "$dir")"
done
