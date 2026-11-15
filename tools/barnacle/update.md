# The barnacle bundle (`tools/barnacle/`)

[Barnacle](https://github.com/fordaj/barnacle) is a documentation-site
generator: it renders the `.md` and `.mmd` files scattered through a
repository into a static, navigable HTML site. Versioner uses it to render
*this* documentation; the site you may be reading was built by it.

## Layout

```text
tools/barnacle/
  update.bash                     # refresh from fordaj/barnacle releases
  v0.0.1.0.5/
    macos-arm64/barnacle
    macos-x86_64/barnacle
    linux-arm64/barnacle
    linux-x86_64/barnacle
    windows-arm64/barnacle.exe
    windows-x86_64/barnacle.exe
```

## `update.bash` in detail

The script downloads the latest (or `--tag`ged) barnacle release from
GitHub via `gh` and stages it into `tools/barnacle/v<tag>/<platform>/`.

1. Resolves the tag (latest release via `gh release view`, or `--tag` /
   `BARNACLE_TAG`), validating the tag shape (`vX.Y.Z…`).
2. Downloads `*.tar.gz`, `*.zip`, `*.7z` plus
   `checksums.txt`/`SHA256SUMS.txt` via `gh release download`. If a
   checksums file is present, every downloaded archive is verified
   (`shasum -a 256 -c` or `sha256sum -c`); a mismatch is fatal. If not, a
   warning is logged and verification is skipped.
3. Extracts each archive (`tar` for `.tar.gz`; `unzip`, or `7z`/`7zz` for
   `.zip`/legacy `.7z`), normalises platform names (`darwin-amd64` →
   `macos-x86_64`, `x64`/`amd64` → `x86_64`), and copies the binary into
   `v<tag>/<platform>/`, executable. If the archive carries a top-level
   `LICENSE`, it is copied alongside the binary in each platform dir (none
   is present in the committed `v0.0.1.0.5`).
4. Swaps in the new version directory and deletes superseded `v*/` folders
   only after the new one is fully staged, then smoke-tests the host
   binary (`barnacle --version`).

Only platform archives are kept (no `-lite`/`-full` filtering — every
platform archive is installed). Prerequisites: `gh` and `tar` (plus
`unzip` for `.zip` assets; `7z`/`7zz` only for legacy `.7z`). Environment
overrides: `BARNACLE_REPO` (default `fordaj/barnacle`), `BARNACLE_TAG`.
`--dry-run` lists assets without touching anything; `--help` prints
usage. The script sources [`scripts/entry.sh`](../../scripts/entry.md) for
logging and can run from any directory.

## How the repository uses it

[scripts/docs.sh](../../scripts/docs.md) resolves `BARNACLE_BIN` through
the [env cascade](../../scripts/env.md) and generates `./site/` from the
repo root; the output is git-ignored.

## Related pages

- [../README.md](../README.md) — the bundle index
- [../../scripts/README.md](../../scripts/README.md) — the scripts that consume the bundle
