#!/usr/bin/env bash
# release.bash — dogfooding release for versioner.
#
# Uses versioner itself to compute the next tag, cross-compiles the
# release binaries for injection (ldflags toolVersion=$TAG), tags HEAD,
# and publishes a GitHub release with the binaries + SHA-256 checksums.
#
# Usage:
#   ./release.bash           # tag + push + GitHub release
#   ./release.bash --dry-run # compute + build only, touch nothing remote
#
# Prerequisites: go, git, make, and (for the real release) gh authenticated
# via `gh auth login`. Working tree must be clean; HEAD should be pushed.

set -euo pipefail

DRY_RUN=0

usage() {
    cat <<'EOF'
Usage: ./release.bash [--dry-run]

Compute the next version with versioner itself (dogfooding), cross-compile
the release binaries (see Makefile `cross`), create an annotated tag,
push it, and create a GitHub release with the binaries + checksums.

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
        --dry-run|-n) DRY_RUN=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "release.bash: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

log() { printf 'release.bash: %s\n' "$*"; }
die() { printf 'release.bash: error: %s\n' "$*" >&2; exit 1; }
need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

for cmd in git go make; do need_cmd "$cmd"; done

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

RANCH="$(git rev-parse --abbrev-ref HEAD)"
HEAD_SHORT="$(git rev-parse --short HEAD)"
log "repo: $REPO_ROOT"
log "branch: $RANCH  HEAD: $HEAD_SHORT"
if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY RUN: no tag/push/release will happen"
fi

# --- Precondition: clean working tree ---------------------------------
if [[ -n "$(git status --porcelain)" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "warning: working tree is not clean (allowed in --dry-run)"
        git status --short | sed 's/^/release.bash:   /' >&2
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
printf '%s\n' "$VERSION_OUT" | sed 's/^/release.bash:   /'

VERSION="$(printf '%s\n' "$VERSION_OUT" | sed -n 's/^VERSION=//p' | tail -1)"
TAG="$(printf '%s\n' "$VERSION_OUT" | sed -n 's/^TAG=//p' | tail -1)"
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
assets=(dist/versioner-*)
(( ${#assets[@]} > 0 )) || die "make cross produced no binaries in dist/"
for f in "${assets[@]}"; do
    [[ -s "$f" ]] || die "built binary is empty: $f"
done
log "built ${#assets[@]} binaries:"
for f in "${assets[@]}"; do log "  $f"; done

# Native binary should report our tag (guards ldflags wiring).
NATIVE_OS="$(go env GOOS)"
NATIVE_ARCH="$(go env GOARCH)"
NATIVE_BIN="dist/versioner-${NATIVE_OS}-${NATIVE_ARCH}"
if [[ -x "$NATIVE_BIN" ]]; then
    NATIVE_VER="$("$NATIVE_BIN" --version)"
    log "native binary reports: $NATIVE_VER"
    case "$NATIVE_VER" in
        *"$TAG"*) ;;
        *) die "native binary version '$NATIVE_VER' does not contain $TAG (ldflags missing?)" ;;
    esac
fi

# Checksums (portable shasum; sha256sum fallback).
log "generating checksums..."
if command -v shasum >/dev/null 2>&1; then
    (cd dist && shasum -a 256 versioner-* > checksums.txt)
elif command -v sha256sum >/dev/null 2>&1; then
    (cd dist && sha256sum versioner-* > checksums.txt)
else
    die "neither shasum nor sha256sum found (need one for checksums)"
fi
cat dist/checksums.txt | sed 's/^/release.bash:   /'

# --- Tag + GitHub release ----------------------------------------------
if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY RUN: would run:"
    log "  git tag -a $TAG -m \"versioner $TAG\""
    log "  git push origin $TAG"
    log "  gh release create $TAG --title \"versioner $TAG\" --generate-notes dist/versioner-* dist/checksums.txt"
    log "dry run complete: VERSION=$VERSION TAG=$TAG"
    exit 0
fi

log "creating annotated tag $TAG..."
git tag -a "$TAG" -m "versioner $TAG"

log "pushing tag $TAG..."
git push origin "$TAG"

if gh release view "$TAG" >/dev/null 2>&1; then
    die "GitHub release $TAG already exists (tag was pushed; upload assets manually with: gh release upload $TAG dist/versioner-* dist/checksums.txt --clobber)"
fi

log "creating GitHub release $TAG with ${#assets[@]} binaries + checksums..."
gh release create "$TAG" \
    --title "versioner $TAG" \
    --generate-notes \
    dist/versioner-* dist/checksums.txt

if REPO_SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" && [[ -n "$REPO_SLUG" ]]; then
    log "release: https://github.com/$REPO_SLUG/releases/tag/$TAG"
else
    log "release $TAG created (see GitHub Releases)"
fi
