# AGENTS.md

Instructions for AI coding agents working in this repo.

## What this is

`versioner` is a small Go CLI that computes

```text
VERSION = <branch-version>.<major>.<minor>.<revision>.<patch>
TAG     = "v" + VERSION
```

from git history. It is the Go replacement for a legacy shell script
(`get_version.sh`); that script is **not** in this repository — `versioner`
is the canonical implementation.

The binary is meant to be cross-compiled (`CGO_ENABLED=0`) and dropped into
git-based software projects. It shells out to `git` but has no third-party
Go dependencies.

## Source layout

- `main.go` — CLI flags (`flag` pkg), config precedence, output formats
  (`text`/`shell`/`json`), exit codes (`0` ok, `1` compute, `2` usage/config).
- `config.go` — `Config`, defaults, `.versioner.json` loading, `VERSIONER_*`
  env overlay, exempt-branch parsing (JSON or `a=1,b=2`).
- `version.go` — pure version rules (`ParseTag`, `ClassifyCommit`,
  `ApplyBump`), git plumbing via a stubbable `gitRun` func var, `Compute`.
- `*_test.go` — table/'stubbed-git' unit tests.
- `Makefile` — `build`/`test`/`vet`/`cross`/`clean`.
- `scripts/release.sh` — dogfooding release: builds `versioner`, computes
  `TAG`, runs `make cross` with `VERSION=$TAG` to
  `dist/<arch>/versioner[.exe]`, packs each into
  `dist/Versioner_<tag>_<arch>.tar.gz` (`.zip` on Windows) with
  README/LICENSE, tags/pushes, and `gh release create`s the archives +
  `checksums.txt` (`--dry-run` to preview). There is no 7zip anywhere.
- `scripts/` — the env cascade (`env.sh`, `entry.sh`, `.common.env`,
  `.<platform>.env`), `version.bash`, `build.sh`, `docs.sh`.
- `tools/` — bundled binaries from the sibling `fordaj/*` repos
  (`barnacle`, `formattington-lite`, `logamuffin`, `runner-spawner`)
  with one `update.bash` per tool refreshing them from the upstream
  GitHub releases (platform-native `.tar.gz`/`.zip` assets; legacy `.7z`
  still accepted). `scripts/entry.sh` exposes `log()` (logamuffin-backed).
- `.formattington.json` — formatting configuration (formattington); the
  repo formats itself with it via `./format.bash` / `./ci/format_check.bash`.
- `.runner-spawner.json` — self-hosted runner provisioning for this repo
  (consumed by `runner-spawner create`).
- `.versioner.json` — this repo's own configuration (`main` → `0`).
- `README.md` — user-facing docs. Keep flag/env/config tables in sync with
  `main.go` and `config.go`.

## Invariants — do not change casually

These mirror the legacy shell script exactly; changing them breaks parity
and every project that depends on the version numbers.

1. **Base from the tag.** `git describe --tags --abbrev=0 --match <pattern>`
   (default `v[0-9]*`). Seed `major/minor/revision` from the tag's
   `v<branch>.<major>.<minor>.<revision>.<patch>`; **overwrite `patch`**
   with `git rev-list <tag> --count` (`version.go:Compute`). No tag ⇒ base
   `0.0.0.0`.
2. **Replay after tagging.** Commit subjects after the tag (or all when
   untagged) oldest-first; every commit bumps `patch`.
3. **Conventional prefixes (case-insensitive, before the first `:`):**
   breaking (`feat!`/`feature!`/`fix!`, with optional `(scope)`) ⇒ `major++`
   - reset `minor`/`revision`; `feat`/`feature` ⇒ `minor++` + reset
     `revision`; `fix` ⇒ `revision++`. Unrecognised types (and breaking
     unrecognised types) bump `patch` only.
4. **Branch version.** Exempt branch ⇒ its value, else default `254`
   (including detached `HEAD`). `Compute` resolves branch before replay.
5. **Text output is a compatibility surface.** Default `text` format prints
   `LAST_TAG=`, one subject + ` -> <version>` line per replayed commit,
   then `VERSION=`/`TAG=`. Only add new flags/formats; do not alter or
   remove these lines.

## Configuration precedence

`defaults < .versioner.json < VERSIONER_* env < CLI flags` (`main.go:run`).
Unset flags must never clobber env/file values (flags default to sentinel
values: `""`, `-1`, `false` — check before applying).

`.versioner.json` fields: `defaultBranchVersion`, `exemptBranches`,
`tagPattern`, `repoDir`, `head` (all optional). Env vars:
`VERSIONER_CONFIG`, `VERSIONER_REPO_DIR`, `VERSIONER_HEAD`,
`VERSIONER_BRANCH`, `VERSIONER_TAG_PATTERN`,
`VERSIONER_DEFAULT_BRANCH_VERSION`, `VERSIONER_EXEMPT_BRANCHES` (JSON or
list, merges per-branch over the file), `VERSIONER_FORMAT`, `VERSIONER_QUIET`.

Do not reintroduce sourcing `env.sh` or any arbitrary shell file — it is
intentionally not supported (security/portability). Point users at the
JSON/env/flags instead.

## Working here

```sh
gofmt -w .          # format
go vet ./...        # must pass
go test ./...       # must pass; add coverage for new pure logic
make build          # ./versioner
make cross          # ./dist/ binaries for 5 targets
./scripts/release.sh --dry-run   # preview dogfooding release (no tag/push)
./format.bash                   # format in place (formattington via uv)
./ci/format_check.bash          # CI formatting gate
```

CI (`.github/workflows/ci.yml`) runs on self-hosted macOS and Windows runners
(managed by `tools/runner-spawner/` per the committed `.runner-spawner.json`):
Check Formatting (`./ci/format_check.bash`) and Test (`go vet ./...`, `gofmt`
check, `go test ./...`, `go build ./...`). There is no GitHub-hosted Linux
compute.

- Use `gofmt`; run `go vet`/`go test` before finishing any change.
- Pure logic (parsing, bumping, config overlay) should stay pure and
  table-tested. Stub git in tests via the `gitRun` variable (`stubGit`
  helper in `version_test.go`) rather than building real repos.
- New flags: add to `run()` in `main.go`, document in `--help` and
  `README.md`, respect precedence (sentinel default + explicit-only apply).
- New config knobs need all three layers: `Config` field, env var (if
  user-facing), and flag (if user-facing), plus `README.md` table updates.
- Error messages go to stderr as `versioner: <message>` with exit `1` for
  compute failures, `2` for bad flags/config. Never print trace lines on
  failure paths.

## Parity checking (shell vs Go)

The legacy shell script is not in this repo. When changing version rules,
write scratch git repositories (`mktemp -d`) and assert `versioner`'s output
directly (`--quiet`, `--format json`) against the documented scheme above;
table-driven tests in `version_test.go`/`config_test.go` are the primary
guard. The rule semantics must not change without updating `README.md` and
this file.

## Conventions

- Conventional commit messages (`feat:`, `fix:`…) — the version rules read
  them, so be accurate: `feat!:` only when truly breaking.
- Keep the module path `github.com/fordaj/versioner` and binary name
  `versioner` stable — downstream projects reference them.
- Commit `dist/` never (it is git-ignored); binaries are built or fetched.
