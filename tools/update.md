# The shared tool refresher (`tools/update.sh`)

`tools/update.sh` is the single implementation behind every
`tools/<name>/update.sh`. Each bundle's `update.sh` is a thin wrapper
that exports the per-tool settings below and `exec`s this script — the
download/verify/stage/swap logic lives here exactly once. It can run
from anywhere; logging comes from [`scripts/entry.sh`](../scripts/entry.sh.md).

## What it does

1. Resolves the tag (latest release via `gh release view`, or `--tag` /
   the bundle's `*_TAG` env var), validating the tag shape (`vX.Y.Z…`).
2. Downloads `*.tar.gz`, `*.zip`, `*.7z` plus
   `checksums.txt`/`SHA256SUMS.txt` via `gh release download`. If a
   checksums file is present, every downloaded archive is verified
   (`shasum -a 256 -c` or `sha256sum -c`); a mismatch is fatal. If not:
   bundles with `UPDATE_REQUIRE_CHECKSUMS=0` log a warning and skip
   verification; bundles with `1` (runner-spawner) die instead.
3. Extracts each archive (`tar` for `.tar.gz`; `unzip`, or `7z`/`7zz` for
   `.zip`/legacy `.7z`), normalises platform names (`darwin-amd64` →
   `macos-x86_64`, `x64`/`amd64` → `x86_64`), and copies the binary into
   `v<tag>/<platform>/`, executable. Files/directories listed in
   `UPDATE_EXTRA_FILES` (e.g. `LICENSE`, or `NOTICE.md` + `LICENSES/`)
   are copied alongside it when present.
4. Swaps in the new version directory and deletes superseded `v*/` folders
   only after the new one is fully staged, then smoke-tests the host
   binary (`<binary> --version`).

`--dry-run` lists the assets it would install without touching anything;
`--help` prints usage (with the bundle's env var names). Prerequisites:
`gh` and `tar` (plus `unzip` for `.zip` assets; `7z`/`7zz` only for
legacy `.7z`).

## Per-tool settings (exported by the wrappers)

| Setting | Meaning |
| --- | --- |
| `TOOL_ROOT` | Bundle directory (`tools/<name>`) |
| `UPDATE_TOOL_NAME` | Bundle name, used in log/error messages and as the path component in usage text |
| `UPDATE_BIN_NAME` | Binary name inside the archives |
| `UPDATE_DEFAULT_REPO` | Repository slug (e.g. `fordaj/barnacle`) |
| `UPDATE_REPO_ENV` | Name of the env var overriding the slug |
| `UPDATE_TAG_ENV` | Name of the env var pinning the tag |
| `UPDATE_ASSET_SUFFIX` | If non-empty, only archives whose stem contains this suffix are installed (`-lite` for formattington-lite) |
| `UPDATE_EXTRA_FILES` | Space-separated extra paths to copy from each archive next to the binary |
| `UPDATE_REQUIRE_CHECKSUMS` | `1` to refuse installing without a checksums file, `0` to warn and continue |

## Related pages

- [README.md](README.md) — the bundle index
- [barnacle/update.sh.md](barnacle/update.sh.md), [formattington-lite/update.sh.md](formattington-lite/update.sh.md), [logamuffin/update.sh.md](logamuffin/update.sh.md), [runner-spawner/update.sh.md](runner-spawner/update.sh.md) — the per-tool wrappers
