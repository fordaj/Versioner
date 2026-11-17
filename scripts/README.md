# Repository script tooling (`scripts/`)

```mermaid
flowchart TD
    Entry("<img src='barnacle:terminal.svg' width='20' alt=''/><br/><u>entry.sh<br/>sources cascade, defines log()</u>") --> Env("<img src='barnacle:terminal.svg' width='20' alt=''/><br/><u>env.sh<br/>anchors *_BIN absolute</u>")
    Env --> Common("<img src='barnacle:terminal.svg' width='20' alt=''/><br/>.common.env<br/>TOOLS_DIR, upstream repos, pins")
    Env --> Plat("<img src='barnacle:terminal.svg' width='20' alt=''/><br/>platform .env file<br/>PROJECT_PLATFORM, *_BIN")
    Entry --> Version("<img src='barnacle:terminal.svg' width='20' alt=''/><br/><u>version.sh.md</u>")
    Entry --> Build("<img src='barnacle:terminal.svg' width='20' alt=''/><br/><u>build.sh.md</u>")
    Entry --> Docs("<img src='barnacle:terminal.svg' width='20' alt=''/><br/><u>docs.sh.md</u>")
    Entry --> Format("<img src='barnacle:terminal.svg' width='20' alt=''/><br/><u>format.sh.md</u>")
    Release("<img src='barnacle:terminal.svg' width='20' alt=''/><br/><u>release.sh.md<br/>self-contained, does not source entry.sh</u>")
    click Entry href "entry.sh.md"
    click Env href "env.sh.md"
    click Version href "version.sh.md"
    click Build href "build.sh.md"
    click Docs href "docs.sh.md"
    click Format href "format.sh.md"
    click Release href "release.sh.md"
    class Entry,Env,Common,Plat,Version,Build,Docs,Format,Release shFile
    classDef shFile fill:#abe07a,stroke:#3f6212,color:#16280a
```

The `scripts/` directory carries the repository's build/release/docs/version
tooling: an environment cascade the other scripts source, plus one entry
point per task. Everything here is bash; nothing requires a global install
beyond what each script documents.

Vernacular used in the headers (`log INFO`, `$REPO_ROOT_DIR`,
`VERSIONER_BIN`): read [entry.sh.md](entry.sh.md) first, then [env.sh.md](env.sh.md).

## The cascade (why the dotfiles exist)

- [entry.sh](entry.sh.md) — sources `scripts/env.sh` and defines `log()`
  (logamuffin, with a printf fallback). Sourced by everything except
  `release.sh`.
- [env.sh](env.sh.md) — locates and sources the cascade below, then anchors
  the repository-relative `*_BIN` tool paths to absolute paths.
- `scripts/.common.env`, `scripts/.<os>-<arch>.env` — the cascade proper.
  Hidden files, so barnacle does not render them as pages; [env.sh.md](env.sh.md)
  documents them. `.common.env` holds the platform-independent settings
  (`TOOLS_DIR=tools`, the `fordaj/*` upstream repos, and the pinned
  `*_VERSION_DIR`s); each platform file sets `PROJECT_PLATFORM` and the
  `*_BIN` paths for its `<os>-<arch>`.

## Task scripts

- [version.sh](version.sh.md) — print the repository version computed by
  versioner (`--format text|shell|json`).
- [format.sh](format.sh.md) — format the repository in place with formattington.
- [build.sh](build.sh.md) — cross-compile versioner into `dist/` with the
  version stamped in via `-ldflags`.
- [docs.sh](docs.sh.md) — generate the documentation site you are reading,
  with the bundled barnacle.
- [release.sh](release.sh.md) — dogfooding release: compute the tag with
  versioner, cross-compile, tag, push, and publish the GitHub release.

The `tools/` bundles are documented in `tools/README.md`,
`tools/update.md` (the shared refresher) and `tools/<name>/update.sh.md`
(source pages; `tools/` is excluded from the barnacle scan, so they are
not rendered into the site).

## Related pages

- [README.md](../README.md)
- [AGENTS.md](../AGENTS.md)
