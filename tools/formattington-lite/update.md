# The formattington-lite bundle (`tools/formattington-lite/`)

[Formattington](https://github.com/fordaj/formattington) is a formatting
orchestrator; the `-lite` assets are its bare program without embedded
formatter executables (the `-full` assets embed them). This bundle pins
the lite binary for the six supported platforms.

Note: this repository formats itself with formattington via `uv`
(`format.sh` → `uv run formattington`, pinned in `pyproject.toml`), **not**
via this bundle — no script here references `tools/formattington-lite/`.
It is kept in the uniform `tools/` layout alongside the other pinned
helpers.

## Layout

```text
tools/formattington-lite/
  update.sh                     # refresh from fordaj/formattington releases
  v0.0.2.0.53/
    macos-arm64/formattington
    macos-x86_64/formattington
    linux-arm64/formattington
    linux-x86_64/formattington
    windows-arm64/formattington.exe
    windows-x86_64/formattington.exe
```

## `update.sh` in detail

The script downloads the latest (or `--tag`ged) formattington release from
GitHub via `gh` and stages it into
`tools/formattington-lite/v<tag>/<platform>/`.

1. Resolves the tag (latest release via `gh release view`, or `--tag` /
   `FORMATTINGTON_TAG`), validating the tag shape (`vX.Y.Z…`).
2. Downloads `*.tar.gz`, `*.zip`, `*.7z` plus
   `checksums.txt`/`SHA256SUMS.txt` via `gh release download`. If a
   checksums file is present, every downloaded archive is verified
   (`shasum -a 256 -c` or `sha256sum -c`); a mismatch is fatal. If not, a
   warning is logged and verification is skipped.
3. **Filters for `-lite` assets only** — any asset whose stem does not
   contain `-lite` is ignored (this is the one bundle that discriminates;
   the others install every platform archive). Platform names are
   normalised (`darwin-amd64` → `macos-x86_64`).
4. Extracts each archive (`tar` for `.tar.gz`; `unzip`, or `7z`/`7zz` for
   `.zip`/legacy `.7z`), copies the binary into `v<tag>/<platform>/`
   (executable), and — when present — copies top-level `NOTICE.md` and
   `LICENSES/` into each platform dir (none are present in the committed
   `v0.0.2.0.53`).
5. Swaps in the new version directory and deletes superseded `v*/` folders
   only after the new one is fully staged, then smoke-tests the host
   binary (`formattington --version`).

Prerequisites: `gh` and `tar` (plus `unzip` for `.zip` assets; `7z`/`7zz`
only for legacy `.7z`). Environment overrides: `FORMATTINGTON_REPO`
(default `fordaj/formattington`), `FORMATTINGTON_TAG`. `--dry-run` lists
assets without touching anything; `--help` prints usage. The script
sources [`scripts/entry.sh`](../../scripts/entry.md) for logging and can
run from any directory.

## Related pages

- [../README.md](../README.md) — the bundle index
- [../../format.md](../../format.md) — how this repo actually runs formattington (via `uv`)
- [../../scripts/README.md](../../scripts/README.md) — the scripts directory
