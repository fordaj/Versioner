#!/usr/bin/env bash
# scripts/release.sh — dogfooding release for versioner.
#
# Uses versioner itself to compute the next tag, cross-compiles the
# release binaries for injection (ldflags toolVersion=$TAG), packs each
# architecture into Versioner_<tag>_<arch>.tar.gz (.zip on Windows;
# flat archives: binary + README + LICENSE), tags HEAD, and publishes a
# GitHub release with those archives + SHA-256 checksums.
#
# Usage:
#   scripts/release.sh           # tag + push + GitHub release
#   scripts/release.sh --dry-run # compute + build only, touch nothing remote
#
# Prerequisites: go, git, make, tar, zip, and (for the real release)
# gh authenticated via `gh auth login`. Working tree must be clean;
# HEAD should be pushed.

set -euo pipefail

DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: scripts/release.sh [--dry-run]

Compute the next version with versioner itself (dogfooding), cross-compile
the release binaries (see Makefile `cross`) into dist/<arch>/versioner[.exe],
pack each into Versioner_<tag>_<arch>.tar.gz (.zip on Windows; flat archives:
binary + README.md + LICENSE), create an annotated tag, push it, and create a
GitHub release with those archives + checksums.

Flags:
  --dry-run, -n   Build + compute version, but do not tag/push/release.
  --help, -h      Show this help.

Env:
  VERSIONER_BIN   Path to a prebuilt versioner used for version computation
                  (default: built fresh from source).
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
  *)
    echo "release.sh: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

log() { printf 'release.sh: %s\n' "$*"; }
die() {
  printf 'release.sh: error: %s\n' "$*" >&2
  exit 1
}
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}
# extract_value <versioner-output> <key> — print the last VALUE=<value>
# line's value from versioner's text output (LAST_TAG/VERSION/TAG style).
extract_value() {
  printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1
}

for cmd in git go make tar zip; do need_cmd "$cmd"; done

# Basename used for the release archives and their checksums file.
ARCHIVE_PREFIX="Versioner"

if [[ "$DRY_RUN" -ne 1 ]]; then
  need_cmd gh
  if ! gh auth status >/dev/null 2>&1; then
    die "gh is not authenticated (run: gh auth login)"
  fi
fi

if ! REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  die "not inside a git repository"
fi
cd "$REPO_ROOT"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
HEAD_SHORT="$(git rev-parse --short HEAD)"
log "repo: $REPO_ROOT"
log "branch: $BRANCH  HEAD: $HEAD_SHORT"
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY RUN: no tag/push/release will happen"
fi

# --- Precondition: clean working tree ---------------------------------
if [[ -n "$(git status --porcelain)" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "warning: working tree is not clean (allowed in --dry-run)"
    git status --short | sed 's/^/release.sh:   /' >&2
  else
    die "working tree is not clean (commit or stash first):"$'\n'"$(git status --short)"
  fi
fi

# Best-effort fetch so remote tag-existence checks are current.
if ! git fetch origin --tags 2>/dev/null; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "warning: git fetch origin --tags failed; remote tag check may be stale"
  else
    die "git fetch origin --tags failed"
  fi
fi

# --- Dogfooding: build versioner + compute VERSION/TAG ----------------
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
DOGFOOD_BIN="$TMP_DIR/versioner-dogfood"

if [[ -n "${VERSIONER_BIN:-}" ]]; then
  [[ -x "$VERSIONER_BIN" ]] || die "VERSIONER_BIN=$VERSIONER_BIN is not executable"
  DOGFOOD_BIN="$VERSIONER_BIN"
  log "using prebuilt versioner: $DOGFOOD_BIN"
else
  log "building dogfood versioner..."
  CGO_ENABLED=0 go build -trimpath -o "$DOGFOOD_BIN" .
fi

log "computing version with versioner (dogfooding)..."
VERSION_OUT="$("$DOGFOOD_BIN" --repo-dir "$REPO_ROOT")"
log "versioner output:"
printf '%s\n' "$VERSION_OUT" | sed 's/^/release.sh:   /'

VERSION="$(extract_value "$VERSION_OUT" VERSION)"
TAG="$(extract_value "$VERSION_OUT" TAG)"
[[ -n "$VERSION" ]] || die "could not parse VERSION from versioner output"
[[ -n "$TAG" ]] || die "could not parse TAG from versioner output"
if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  die "computed tag looks invalid: '$TAG' (expected vX.Y.Z.W.V)"
fi
log "VERSION=$VERSION  TAG=$TAG"

# --- Tag must not already exist ---------------------------------------
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  die "tag $TAG already exists locally (make a new feat:/fix: commit to bump the version, then re-run)"
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  die "tag $TAG already exists on origin (make a new feat:/fix: commit to bump the version, then re-run)"
fi

# --- Cross-compile release binaries -----------------------------------
log "cross-compiling release binaries (VERSION=$TAG) via make cross..."
VERSION="$TAG" make cross

shopt -s nullglob
arch_dirs=(dist/*/)
((${#arch_dirs[@]} > 0)) || die "make cross produced no dist/<arch>/ directories"
log "built ${#arch_dirs[@]} architecture directories:"
for d in "${arch_dirs[@]}"; do log "  $d"; done

# Stage user docs next to each binary (dist/<arch>/README.md, LICENSE)
# for inclusion in the release archives.
for d in "${arch_dirs[@]}"; do
  for doc in README.md LICENSE; do
    [[ -f "$doc" ]] || die "missing $doc (needed for release archives)"
    cp -p "$doc" "$d/"
  done
done

# Native binary should report our tag (guards ldflags wiring).
NATIVE_OS="$(go env GOOS)"
NATIVE_ARCH="$(go env GOARCH)"
if [[ "$NATIVE_OS" == "windows" ]]; then
  NATIVE_BIN="dist/${NATIVE_OS}-${NATIVE_ARCH}/versioner.exe"
else
  NATIVE_BIN="dist/${NATIVE_OS}-${NATIVE_ARCH}/versioner"
fi
if [[ -x "$NATIVE_BIN" ]]; then
  NATIVE_VER="$("$NATIVE_BIN" --version)"
  log "native binary reports: $NATIVE_VER"
  case "$NATIVE_VER" in
  *"$TAG"*) ;;
  *) die "native binary version '$NATIVE_VER' does not contain $TAG (ldflags missing?)" ;;
  esac
fi

# Pack each architecture into a platform-native archive (flat: binary
# + README.md + LICENSE at archive root). Unix targets get .tar.gz,
# Windows targets get .zip.
log "packing platform-native archives..."
archives=()
for d in "${arch_dirs[@]}"; do
  arch="$(basename "$d")"
  bin=""
  for cand in "${d}versioner" "${d}versioner.exe"; do
    [[ -f "$cand" ]] && bin="$cand"
  done
  [[ -n "$bin" ]] || die "no versioner binary in $d"
  [[ -s "$bin" ]] || die "built binary is empty: $bin"
  bin_name="$(basename "$bin")"
  case "$arch" in
  windows-*)
    archive="dist/${ARCHIVE_PREFIX}_${TAG}_${arch}.zip"
    rm -f "$archive"
    (cd "$d" && zip -q -j "../${ARCHIVE_PREFIX}_${TAG}_${arch}.zip" "$bin_name" README.md LICENSE)
    ;;
  *)
    archive="dist/${ARCHIVE_PREFIX}_${TAG}_${arch}.tar.gz"
    rm -f "$archive"
    (cd "$d" && tar -czf "../${ARCHIVE_PREFIX}_${TAG}_${arch}.tar.gz" "$bin_name" README.md LICENSE)
    ;;
  esac
  [[ -s "$archive" ]] || die "failed to create $archive"
  log "  $archive:"
  case "$archive" in
  *.zip) unzip -l "$archive" | sed 's/^/release.sh:     /' ;;
  *) tar -tzf "$archive" | sed 's/^/release.sh:     /' ;;
  esac
  archives+=("$archive")
done

# Checksums of the release archives (portable shasum; sha256sum fallback).
log "generating checksums..."
if command -v shasum >/dev/null 2>&1; then
  (cd dist && shasum -a 256 "${ARCHIVE_PREFIX}"_* >checksums.txt)
elif command -v sha256sum >/dev/null 2>&1; then
  (cd dist && sha256sum "${ARCHIVE_PREFIX}"_* >checksums.txt)
else
  die "neither shasum nor sha256sum found (need one for checksums)"
fi
cat dist/checksums.txt | sed 's/^/release.sh:   /'

# --- Tag + GitHub release ----------------------------------------------
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY RUN: would run:"
  log "  git tag -a $TAG -m \"versioner $TAG\""
  log "  git push origin $TAG"
  log "  gh release create $TAG --title \"versioner $TAG\" --generate-notes dist/${ARCHIVE_PREFIX}_* dist/checksums.txt"
  log "dry run complete: VERSION=$VERSION TAG=$TAG"
  exit 0
fi

log "creating annotated tag $TAG..."
git tag -a "$TAG" -m "versioner $TAG"

log "pushing tag $TAG..."
git push origin "$TAG"

if gh release view "$TAG" >/dev/null 2>&1; then
  die "GitHub release $TAG already exists (tag was pushed; upload assets manually with: gh release upload $TAG dist/${ARCHIVE_PREFIX}_* dist/checksums.txt --clobber)"
fi

log "creating GitHub release $TAG with ${#archives[@]} archives + checksums..."
gh release create "$TAG" \
  --title "versioner $TAG" \
  --generate-notes \
  "${archives[@]}" dist/checksums.txt

if REPO_SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" && [[ -n "$REPO_SLUG" ]]; then
  log "release: https://github.com/$REPO_SLUG/releases/tag/$TAG"
else
  log "release $TAG created (see GitHub Releases)"
fi
