# The runner-spawner bundle (`tools/runner-spawner/`)

[Runner-spawner](https://github.com/fordaj/runner-spawner) provisions
self-hosted GitHub Actions runners. This repository's CI (`.github/
workflows/ci.yml`) runs on self-hosted macOS and Windows runners managed
with it — see `.runner-spawner.json` (`runnerNames`, `runnersDir`,
`runnerGroup`, `runnerVersion`) and `AGENTS.md`.

Runner-spawner supports macOS and Windows only; on Linux the bundled
binary is shipped for a uniform layout but reports itself unsupported (the
platform env files note this).

## Layout

```text
tools/runner-spawner/
  update.bash                     # refresh from fordaj/runner-spawner releases
  v0.0.1.2.6/
    macos-arm64/runner-spawner
    macos-x86_64/runner-spawner
    linux-arm64/runner-spawner
    linux-x86_64/runner-spawner
    windows-arm64/runner-spawner.exe
    windows-x86_64/runner-spawner.exe
```

## `update.bash` in detail

The script downloads the latest (or `--tag`ged) runner-spawner release
from GitHub via `gh` and stages it into
`tools/runner-spawner/v<tag>/<platform>/`.

1. Resolves the tag (latest release via `gh release view`, or `--tag` /
   `RUNNER_SPAWNER_TAG`), validating the tag shape (`vX.Y.Z…`).
2. Downloads `*.tar.gz`, `*.zip`, `*.7z` plus
   `checksums.txt`/`SHA256SUMS.txt` via `gh release download`. If a
   checksums file is present, every downloaded archive is verified
   (`shasum -a 256 -c` or `sha256sum -c`); a mismatch is fatal.
   **If no checksums file is present the script refuses to install**
   (`no checksums.txt/SHA256SUMS.txt in <tag> release; refusing to install
   unverified binaries`) — the only bundle that fails closed.
3. Extracts each archive (`tar` for `.tar.gz`; `unzip`, or `7z`/`7zz` for
   `.zip`/legacy `.7z`), normalises platform names (`darwin-amd64` →
   `macos-x86_64`), and copies the binary into `v<tag>/<platform>/`,
   executable. Only the binary is kept.
4. Swaps in the new version directory and deletes superseded `v*/` folders
   only after the new one is fully staged, then smoke-tests the host
   binary (`runner-spawner --version`).

Prerequisites: `gh` and `tar` (plus `unzip` for `.zip` assets; `7z`/`7zz`
only for legacy `.7z`). Environment overrides: `RUNNER_SPAWNER_TOOL_REPO`
(default `fordaj/runner-spawner` — note the `_TOOL_` infix, so it does not
collide with other `RUNNER_SPAWNER_*` variables), `RUNNER_SPAWNER_TAG`.
`--dry-run` lists assets without touching anything; `--help` prints
usage. The script sources [`scripts/entry.sh`](../../scripts/entry.md) for
logging and can run from any directory.

## Related pages

- [../README.md](../README.md) — the bundle index
- [../../scripts/env.md](../../scripts/env.md) — the cascade that selects `RUNNER_SPAWNER_BIN`
