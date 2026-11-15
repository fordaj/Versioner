# The logamuffin bundle (`tools/logamuffin/`)

[Logamuffin](https://github.com/fordaj/logamuffin) is the structured
logging backend for the `log()` function defined in
[`scripts/entry.sh`](../../scripts/entry.md). Every script in `scripts/`
and every `tools/<name>/update.bash` logs through it (with a printf
fallback when the binary is absent).

## Layout

```text
tools/logamuffin/
  update.bash                     # refresh from fordaj/logamuffin releases
  v0.1.3.0.35/
    macos-arm64/logamuffin
    macos-x86_64/logamuffin
    linux-arm64/logamuffin
    linux-x86_64/logamuffin
    windows-arm64/logamuffin.exe
    windows-x86_64/logamuffin.exe
```

## `update.bash` in detail

The script downloads the latest (or `--tag`ged) logamuffin release from
GitHub via `gh` and stages it into `tools/logamuffin/v<tag>/<platform>/`.

1. Resolves the tag (latest release via `gh release view`, or `--tag` /
   `LOGAMUFFIN_TAG`), validating the tag shape (`vX.Y.Z…`).
2. Downloads `*.tar.gz`, `*.zip`, `*.7z` plus
   `checksums.txt`/`SHA256SUMS.txt` via `gh release download`. If a
   checksums file is present, every downloaded archive is verified
   (`shasum -a 256 -c` or `sha256sum -c`); a mismatch is fatal. If not, a
   warning is logged and verification is skipped.
3. Extracts each archive (`tar` for `.tar.gz`; `unzip`, or `7z`/`7zz` for
   `.zip`/legacy `.7z`), normalises platform names (`darwin-amd64` →
   `macos-x86_64`), and copies the binary into `v<tag>/<platform>/`,
   executable. Only the binary is kept.
4. Swaps in the new version directory and deletes superseded `v*/` folders
   only after the new one is fully staged, then smoke-tests the host
   binary (`logamuffin --version`).

Prerequisites: `gh` and `tar` (plus `unzip` for `.zip` assets; `7z`/`7zz`
only for legacy `.7z`). Environment overrides: `LOGAMUFFIN_REPO` (default
`fordaj/logamuffin`), `LOGAMUFFIN_TAG`. `--dry-run` lists assets without
touching anything; `--help` prints usage. The script sources
[`scripts/entry.sh`](../../scripts/entry.md) for logging and can run from
any directory.

## How the repository uses it

[`scripts/entry.sh`](../../scripts/entry.md) forwards `log()` calls to the
binary at `LOGAMUFFIN_BIN` (selected by the
[cascade](../../scripts/env.md)), passing the call site's `file:line` in
`LOG_SOURCE`.

## Related pages

- [../README.md](../README.md) — the bundle index
- [../../scripts/entry.md](../../scripts/entry.md) — the `log()` consumer
