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

`update.sh` is a thin wrapper around [`tools/update.sh`](../update.md) —
the shared download/verify/stage/swap implementation. It declares the
bundle's settings and execs that script; see
[../update.md](../update.md) for the full algorithm.

formattington-lite's settings: repository `fordaj/formattington`, binary
`formattington`, tag override `FORMATTINGTON_TAG`, slug override
`FORMATTINGTON_REPO`, only `-lite` archives installed (assets whose stem
does not contain `-lite`, e.g. the `-full` builds, are ignored),
`NOTICE.md` and `LICENSES/` copied next to each binary when present
(neither is present in the committed `v0.0.2.0.53`), missing checksums
file is a warning (not fatal).

`--dry-run` lists assets without touching anything; `--help` prints
usage. It can run from any directory.

## Related pages

- [../README.md](../README.md) — the bundle index
- [../update.md](../update.md) — the shared implementation behind this wrapper
- [../../format.md](../../scripts/format.md) — how this repo actually runs formattington (via `uv`)
- [../../scripts/README.md](../../scripts/README.md) — the scripts directory
