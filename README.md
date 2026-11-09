# Versioner

`versioner` computes a version number from git history.

It shells out to `git` (so `git` must be on `PATH`) but the binary itself
has no third-party dependencies and builds reproducible with
`CGO_ENABLED=0`.

```text
VERSION = <branch-version>.<major>.<minor>.<revision>.<patch>
TAG     = "v" + VERSION
```

The legacy `get_version.sh` is kept in the repo root as a reference and
fallback only. New usage should use the `versioner` binary.

## Version scheme

The base version comes from the most recent tag matching the configured
pattern (default `v[0-9]*`) via `git describe --tags --abbrev=0 --match`.

- If a tag `v<branch>.<major>.<minor>.<revision>.<patch>` exists, the base
  `major`, `minor`, and `revision` are taken from it. The `patch` component
  is replaced with the total number of commits reachable from the tag
  (`git rev-list <tag> --count`), exactly as the shell script did.
- If no tag exists, the base starts at `0.0.0.0` (patch `0`).

Commits after the tag (or all commits when there is no tag) are replayed
oldest-first. Each commit's subject prefix before the first `:` is
lowercased and classified:

| Commit prefix                                                       | Effect                                        |
| ------------------------------------------------------------------- | --------------------------------------------- |
| `feat!:` / `feat(scope)!:` / `feature!:` / `fix!:` / `fix(scope)!:` | `major++`, `minor=0`, `revision=0` (breaking) |
| `feat:` / `feat(scope):` / `feature:` / `feature(scope):`           | `minor++`, `revision=0`                       |
| `fix:` / `fix(scope):`                                              | `revision++`                                  |
| anything else (e.g. `docs:`, `chore:`, no colon)                    | no `major`/`minor`/`revision` bump            |
| every commit                                                        | `patch++`                                     |

Matching is case-insensitive. A breaking marker (`!`) on an unrecognised
type (e.g. `chore!:`) only bumps `patch`.

The branch version is resolved from the current branch
(`git branch --show-current`): exempt branches use their configured value,
everything else (including detached `HEAD`) uses the default branch
version, `254`.

## Build

Requires Go 1.23 or newer.

```sh
# build for the current platform (binary: ./versioner)
make build

# tests + vet
make test

# cross-compile static binaries into ./dist/
make cross
```

Cross-compiled artifacts are pure Go with `CGO_ENABLED=0`:

```sh
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -o dist/versioner-linux-amd64 .
```

`make cross` builds `darwin/amd64`, `darwin/arm64`, `linux/amd64`,
`linux/arm64`, and `windows/amd64`.

## Releases

`release.bash` cuts a release by **dogfooding** `versioner`: it builds
`versioner` from source, uses it to compute the next `VERSION`/`TAG`,
cross-compiles the binaries with that tag injected
(`-X main.toolVersion=$TAG`, so `versioner --version` reports the release),
tags `HEAD`, pushes the tag, and publishes a GitHub release.

```sh
./release.bash              # compute version, cross-compile, tag, push, gh release create
./release.bash --dry-run    # compute + build only; touch nothing remote
./release.bash --help       # usage
```

What it does:

1. Checks prerequisites (`go`, `git`, `make`, plus authenticated `gh`
   for the real release) and a clean working tree.
2. Builds `versioner` from source (or uses `$VERSIONER_BIN` if set) and
   runs it against the current repo to compute `VERSION`/`TAG`.
3. Validates the tag and aborts if it already exists locally or on
   `origin` (make a new `feat:`/`fix:` commit to bump the version, then
   re-run).
4. Runs `make cross` (`VERSION=$TAG`) → five binaries in `dist/` plus
   `dist/checksums.txt` (SHA-256 via `shasum` or `sha256sum`).
5. Creates an annotated tag, pushes it, and creates the GitHub release
   (`gh release create --generate-notes`) with all binaries + checksums.

The working tree must be clean (no uncommitted changes) and `HEAD`
should already be pushed when starting a real release. `--dry-run`
still builds everything but skips tag/push/release; a dirty tree is
only warned about in dry-run mode. To verify a built binary, run
`./dist/versioner-<os>-<arch> --version` and `shasum -a 256 -c dist/checksums.txt`.

## Usage

Run inside (or point at) a git repo:

```sh
./versioner                    # text output, per-commit trace
./versioner --quiet            # LAST_TAG/VERSION/TAG only
./versioner --format shell     # eval-able exports
./versioner --format json      # structured output
./versioner --repo-dir /path/to/repo
./versioner --help             # all flags
./versioner --version          # tool version
```

Text output matches `get_version.sh` line-for-line:

```text
LAST_TAG=v254.1.2.3.4
feat!: big
 -> 254.2.0.0.11
fix: small
 -> 254.2.0.1.12
VERSION=254.2.0.1.12
TAG=v254.2.0.1.12
```

Use the `VERSION`/`TAG` from `text` or `shell` output in your build:

```sh
# capture text output
VERSION=$(./versioner --quiet | sed -n 's/^VERSION=//p')
TAG=$(./versioner --quiet | sed -n 's/^TAG=//p')

# or load all shell exports at once (note: a plain binary cannot `export`
# into its parent shell, so the legacy `export TAG=...` idiom only works
# via eval)
eval $(./versioner --format shell)
echo "$TAG"   # v254.2.0.1.12
```

JSON output:

```json
{
  "lastTag": "v254.1.2.3.4",
  "branch": "feature-x",
  "version": "254.2.0.1.12",
  "tag": "v254.2.0.1.12",
  "branchVersion": 254,
  "major": 2,
  "minor": 0,
  "revision": 1,
  "patch": 12,
  "trace": [
    { "commit": "feat!: big", "version": "254.2.0.0.11" },
    { "commit": "fix: small", "version": "254.2.0.1.12" }
  ]
}
```

## Configuration

Precedence, lowest to highest:

1. built-in defaults,
2. `.versioner.json`,
3. `VERSIONER_*` environment variables,
4. command-line flags.

### `.versioner.json`

Place `.versioner.json` in the repo root (auto-discovered) or pass
`--config <path>` / `VERSIONER_CONFIG`. See `versioner.example.json`:

```json
{
  "defaultBranchVersion": 254,
  "exemptBranches": { "main": 1 },
  "tagPattern": "v[0-9]*",
  "repoDir": ".",
  "head": "HEAD"
}
```

| Key                    | Type            | Default   | Meaning                                |
| ---------------------- | --------------- | --------- | -------------------------------------- |
| `defaultBranchVersion` | int             | `254`     | branch version for non-exempt branches |
| `exemptBranches`       | `{branch: int}` | `{}`      | branch → branch version overrides      |
| `tagPattern`           | string          | `v[0-9]*` | `git describe --match` pattern         |
| `repoDir`              | string          | `"."`     | repository directory                   |
| `head`                 | string          | `"HEAD"`  | ref to compute up to                   |

Unknown keys are ignored. Invalid JSON or an explicitly requested missing
file is an error (exit `2`); a merely absent auto-discovered file is fine.

### Environment variables

| Var                                | Meaning                                                           |
| ---------------------------------- | ----------------------------------------------------------------- |
| `VERSIONER_CONFIG`                 | path to `.versioner.json` (same as `--config`)                    |
| `VERSIONER_REPO_DIR`               | repository directory                                              |
| `VERSIONER_HEAD`                   | ref to compute up to                                              |
| `VERSIONER_BRANCH`                 | override current branch detection                                 |
| `VERSIONER_TAG_PATTERN`            | tag pattern                                                       |
| `VERSIONER_DEFAULT_BRANCH_VERSION` | default branch version (integer)                                  |
| `VERSIONER_EXEMPT_BRANCHES`        | exempt branches, JSON (`{"main":1}`) or list (`main=1,develop=2`) |
| `VERSIONER_FORMAT`                 | `text`, `shell`, or `json`                                        |
| `VERSIONER_QUIET`                  | `true`/`false`                                                    |

Env exempt branches merge over the file's per-branch (env wins on
conflict); all other env values replace the file's wholesale.

### Command-line flags

Flags beat env and file. Unset flags never clobber env/file values.

| Flag                               | Meaning                                        |
| ---------------------------------- | ---------------------------------------------- |
| `--config <path>`                  | path to `.versioner.json`                      |
| `--repo-dir <path>`                | repository directory                           |
| `--head <ref>`                     | ref to compute up to (default `HEAD`)          |
| `--branch <name>`                  | override current branch detection              |
| `--tag-pattern <glob>`             | `git describe --match` pattern                 |
| `--default-branch-version <int>`   | default branch version                         |
| `--exempt-branch <branch=version>` | repeatable exempt mapping (JSON also accepted) |
| `--format text\|shell\|json`       | output format (default `text`)                 |
| `--quiet`                          | suppress the per-commit trace (text mode)      |
| `--version`                        | print tool version and exit                    |
| `--help`                           | usage                                          |

### Migrating from `get_version.sh` + `env.sh`

The shell script sourced `env.sh` next to itself (which defined the
`EXEMPT_BRANCHES` associative array):

```sh
declare -A EXEMPT_BRANCHES=([main]=1)
```

The Go binary does **not** source arbitrary shell files. Move that mapping
to `.versioner.json` (`exemptBranches`), `VERSIONER_EXEMPT_BRANCHES`, or
`--exempt-branch main=1`. Everything else in the shell script —
`LAST_TAG=`, the per-commit ` -> ` trace, `VERSION=`/`TAG=` lines — is
reproduced in the default `text` format.

## Exit codes

| Code | Meaning                                                              |
| ---- | -------------------------------------------------------------------- |
| `0`  | success                                                              |
| `1`  | computation failure (not a git repo, no commits, bad tag, git error) |
| `2`  | bad flags or config                                                  |

Errors go to stderr in the form `versioner: <message>`.

## Dropping into a project

1. Cross-compile (`make cross`) and commit or publish the binary for your
   platform(s), or build it in CI.
2. Drop the binary next to your project (or on `PATH`).
3. Add a `.versioner.json` at the repo root with your exempt branches.
4. Call `./versioner` (or `versioner`) from your build script; parse
   `VERSION`/`TAG` from `--quiet` output, or `eval $(versioner --format shell)`.

Example (`Makefile`):

```make
VERSION := $(shell ./versioner --quiet | sed -n 's/^VERSION=//p')
TAG := $(shell ./versioner --quiet | sed -n 's/^TAG=//p')
```

## Tests

```sh
go test ./...
go vet ./...
```

Tests cover tag parsing, commit classification/bumps, config-file/env
parsing, and `Compute` with a stubbed git runner. Parity with
`get_version.sh` (tag vs no-tag, exempt branches, intermediate trace)
was verified manually against temporary git repositories.

## License

MIT — see `LICENSE`.
