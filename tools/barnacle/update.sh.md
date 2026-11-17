# The barnacle bundle (`tools/barnacle/`)

```mermaid
flowchart TD
    Tag("<img src='barnacle:tag.svg' width='20' alt=''/><br/>resolve tag: latest via gh<br/>(or --tag / BARNACLE_TAG)") --> DL("<img src='barnacle:download.svg' width='20' alt=''/><br/>gh release download<br/>archives + checksums")
    DL --> Verify("<img src='barnacle:check.svg' width='20' alt=''/><br/>sha256 verify when present;<br/>warn and skip otherwise")
    Verify --> Extract("<img src='barnacle:package-open.svg' width='20' alt=''/><br/>extract; normalize platform names<br/>darwin-amd64 to macos-x86_64")
    Extract --> Swap("<img src='barnacle:folder-sync.svg' width='20' alt=''/><br/>swap v_tag/ dir, delete superseded,<br/>smoke test barnacle --version")
    Swap --> Done("<img src='barnacle:anchor.svg' width='20' alt=''/><br/><u>BARNACLE_BIN points at the new pin<br/>scripts/docs.sh renders ./site/</u>")
    click Done href "../../scripts/docs.sh.md"
    class Tag tagNode
    class DL dlNode
    class Verify checkNode
    class Extract boxNode
    class Swap folder
    classDef tagNode fill:#f6b8d4,stroke:#be185d,color:#500724
    classDef dlNode fill:#93e2e2,stroke:#0f766e,color:#042f2e
    classDef checkNode fill:#9fe8c9,stroke:#0f766e,color:#052e22
    classDef boxNode fill:#e8cf9d,stroke:#a16207,color:#33240a
    classDef folder fill:#f0c558,stroke:#8a6d1c,color:#332a05
```

[Barnacle](https://github.com/fordaj/barnacle) is a documentation-site
generator: it renders the `.md` and `.mmd` files scattered through a
repository into a static, navigable HTML site. Versioner uses it to render
*this* documentation; the site you may be reading was built by it.

## Layout

```text
tools/barnacle/
  update.sh                     # refresh from fordaj/barnacle releases
  v0.0.2.1.25/
    macos-arm64/barnacle
    macos-x86_64/barnacle
    linux-arm64/barnacle
    linux-x86_64/barnacle
    windows-arm64/barnacle.exe
    windows-x86_64/barnacle.exe
```

## `update.sh` in detail

`update.sh` is a thin wrapper around [`tools/update.sh`](../update.md) —
the shared download/verify/stage/swap implementation. It declares the
bundle's settings and execs that script; see
[../update.md](../update.md) for the full algorithm.

Barnacle's settings: repository `fordaj/barnacle`, binary `barnacle`,
tag override `BARNACLE_TAG`, slug override `BARNACLE_REPO`, every
platform archive installed (no suffix filter), `LICENSE` copied next to
each binary when the archive carries one (none is present in the
committed `v0.0.2.1.25`), missing checksums file is a warning (not fatal).

`--dry-run` lists assets without touching anything; `--help` prints
usage. The script sources [`scripts/entry.sh`](../../scripts/entry.sh.md) for
logging and can run from any directory.

## How the repository uses it

[scripts/docs.sh](../../scripts/docs.sh.md) resolves `BARNACLE_BIN` through
the [env cascade](../../scripts/env.sh.md) and generates `./site/` from the
repo root; the output is git-ignored.

## Related pages

- [../README.md](../README.md) — the bundle index
- [../update.md](../update.md) — the shared implementation behind this wrapper
- [../../scripts/README.md](../../scripts/README.md) — the scripts that consume the bundle
