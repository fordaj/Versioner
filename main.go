// Command versioner computes a semantic-ish version from git history.
//
// It is the Go replacement for get_version.sh: cross-compiled and dropped
// into git-based projects. Configuration precedence (lowest to highest):
// built-in defaults, .versioner.json, VERSIONER_* env vars, CLI flags.
//
// Exit codes: 0 on success, 1 on a computation error, 2 on bad flags/config.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"regexp"
	"sort"
	"strings"
)

// toolVersion is replaced at link time via -ldflags="-X main.toolVersion=...".
var toolVersion = "dev"

func main() {
	if err := run(os.Args[1:], os.Stdout, os.Stderr); err != nil {
		os.Exit(exitCode(err))
	}
}

// codedError carries an exit code.
type codedError struct {
	code int
	msg  string
}

func (e *codedError) Error() string { return e.msg }

func exitCode(err error) int {
	if ce, ok := err.(*codedError); ok {
		return ce.code
	}
	return 1
}

func configErrf(format string, args ...any) error {
	return &codedError{code: 2, msg: fmt.Sprintf(format, args...)}
}

func computeErrf(format string, args ...any) error {
	return &codedError{code: 1, msg: fmt.Sprintf(format, args...)}
}

// exemptFlag collects repeatable --exempt-branch flags.
type exemptFlag struct {
	m map[string]int
}

func (f *exemptFlag) String() string {
	if f == nil || f.m == nil {
		return ""
	}
	keys := make([]string, 0, len(f.m))
	for k := range f.m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, k := range keys {
		parts = append(parts, fmt.Sprintf("%s=%d", k, f.m[k]))
	}
	return strings.Join(parts, ",")
}

func (f *exemptFlag) Set(s string) error {
	m, err := ParseExemptBranches(s)
	if err != nil {
		return err
	}
	if f.m == nil {
		f.m = map[string]int{}
	}
	for k, v := range m {
		f.m[k] = v
	}
	return nil
}

func run(args []string, stdout, stderr io.Writer) error {
	fs := flag.NewFlagSet("versioner", flag.ContinueOnError)
	fs.SetOutput(stderr)

	configPath := fs.String("config", "", "path to .versioner.json (auto-discovered by default)")
	repoDirFlag := fs.String("repo-dir", "", "git repository directory (default: .)")
	head := fs.String("head", "", "ref to compute up to (default: HEAD)")
	branch := fs.String("branch", "", "override current branch name (default: git branch --show-current)")
	tagPattern := fs.String("tag-pattern", "", "git describe --match pattern (default: v[0-9]*)")
	defaultVersion := fs.Int("default-branch-version", -1, "branch version for non-exempt branches (default: 254)")
	format := fs.String("format", "", "output format: text, shell, json (default: text)")
	quiet := fs.Bool("quiet", false, "suppress per-commit trace in text output")
	showVersion := fs.Bool("version", false, "print tool version and exit")
	var ef exemptFlag
	fs.Var(&ef, "exempt-branch", "exempt branch mapping branch=version (repeatable; JSON also accepted)")

	fs.Usage = func() {
		fmt.Fprintln(stderr, "versioner - compute a version from git history (Go replacement for get_version.sh)")
		fmt.Fprintln(stderr, "")
		fmt.Fprintln(stderr, "Usage: versioner [flags]")
		fmt.Fprintln(stderr, "")
		fmt.Fprintln(stderr, "Flags:")
		fs.PrintDefaults()
		fmt.Fprintln(stderr, "")
		fmt.Fprintln(stderr, "Configuration precedence (lowest to highest): defaults < .versioner.json < VERSIONER_* env < flags.")
		fmt.Fprintln(stderr, "Environment: VERSIONER_CONFIG, VERSIONER_REPO_DIR, VERSIONER_HEAD, VERSIONER_BRANCH,")
		fmt.Fprintln(stderr, "  VERSIONER_TAG_PATTERN, VERSIONER_DEFAULT_BRANCH_VERSION, VERSIONER_EXEMPT_BRANCHES,")
		fmt.Fprintln(stderr, "  VERSIONER_FORMAT, VERSIONER_QUIET.")
		fmt.Fprintln(stderr, "")
		fmt.Fprintln(stderr, "Output (--format):")
		fmt.Fprintln(stderr, "  text   LAST_TAG=/per-commit trace/VERSION=/TAG= lines (matches get_version.sh)")
		fmt.Fprintln(stderr, "  shell  export lines for: eval $(versioner --format shell)")
		fmt.Fprintln(stderr, "  json   structured object (see README.md)")
	}

	if err := fs.Parse(args); err != nil {
		if err == flag.ErrHelp {
			return nil
		}
		fmt.Fprintln(stderr, "versioner:", err)
		return &codedError{code: 2, msg: err.Error()}
	}
	if fs.NArg() > 0 {
		msg := fmt.Sprintf("unexpected positional arguments: %s", strings.Join(fs.Args(), " "))
		fmt.Fprintln(stderr, "versioner:", msg)
		return &codedError{code: 2, msg: msg}
	}
	if *showVersion {
		fmt.Fprintln(stdout, "versioner "+toolVersion)
		return nil
	}

	cfg := DefaultConfig()

	// Preliminary repo dir for config discovery: flag > env > default.
	prelimRepoDir := cfg.RepoDir
	if v := os.Getenv(EnvRepoDir); v != "" {
		prelimRepoDir = v
	}
	if *repoDirFlag != "" {
		prelimRepoDir = *repoDirFlag
	}
	cfg.RepoDir = prelimRepoDir

	// Explicit config: --config > VERSIONER_CONFIG; else auto-discover.
	explicitConfig := os.Getenv(EnvConfig)
	if *configPath != "" {
		explicitConfig = *configPath
	}
	configFile := explicitConfig
	if configFile == "" {
		configFile = FindConfigFile(prelimRepoDir)
	}
	if configFile != "" {
		if err := cfg.LoadFile(configFile); err != nil {
			fmt.Fprintln(stderr, "versioner:", err)
			return &codedError{code: 2, msg: err.Error()}
		}
	} else if explicitConfig != "" {
		if _, err := os.Stat(explicitConfig); err != nil {
			msg := fmt.Sprintf("config file %q not found", explicitConfig)
			fmt.Fprintln(stderr, "versioner:", msg)
			return &codedError{code: 2, msg: msg}
		}
	}

	// Env layer (may redefine repoDir etc.).
	if err := cfg.ApplyEnv(nil); err != nil {
		fmt.Fprintln(stderr, "versioner:", err)
		return &codedError{code: 2, msg: err.Error()}
	}

	// Flag layer (explicit only; unset flags must not clobber env/file).
	if *repoDirFlag != "" {
		cfg.RepoDir = *repoDirFlag
	}
	if *head != "" {
		cfg.Head = *head
	}
	if *branch != "" {
		cfg.Branch = *branch
	}
	if *tagPattern != "" {
		cfg.TagPattern = *tagPattern
	}
	if *defaultVersion >= 0 {
		cfg.DefaultBranchVersion = *defaultVersion
	}
	if ef.m != nil {
		for k, v := range ef.m {
			cfg.ExemptBranches[k] = v
		}
	}
	if *format != "" {
		cfg.Format = *format
	}
	if *quiet {
		cfg.Quiet = true
	}

	// Validate.
	if cfg.ExemptBranches == nil {
		cfg.ExemptBranches = map[string]int{}
	}
	switch cfg.Format {
	case "text", "shell", "json":
	default:
		msg := fmt.Sprintf("invalid --format %q (want text, shell, or json)", cfg.Format)
		fmt.Fprintln(stderr, "versioner:", msg)
		return &codedError{code: 2, msg: msg}
	}
	if cfg.TagPattern == "" {
		msg := "tag pattern must not be empty"
		fmt.Fprintln(stderr, "versioner:", msg)
		return &codedError{code: 2, msg: msg}
	}
	if cfg.RepoDir == "" {
		cfg.RepoDir = "."
	}
	if cfg.Head == "" {
		cfg.Head = "HEAD"
	}

	res, err := Compute(cfg)
	if err != nil {
		fmt.Fprintln(stderr, "versioner:", err)
		return computeErrf("%v", err)
	}

	writeOutput(stdout, cfg, res)
	return nil
}

var shellSafeRe = regexp.MustCompile(`^[A-Za-z0-9._/:@+-]+$`)

func shellQuote(s string) string {
	if shellSafeRe.MatchString(s) {
		return s
	}
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func writeOutput(w io.Writer, cfg *Config, res *Result) {
	switch cfg.Format {
	case "shell":
		fmt.Fprintf(w, "export LAST_TAG=%s\n", shellQuote(res.LastTag))
		fmt.Fprintf(w, "export VERSION_BRANCH=%d\n", res.Version.Branch)
		fmt.Fprintf(w, "export VERSION_MAJOR=%d\n", res.Version.Major)
		fmt.Fprintf(w, "export VERSION_MINOR=%d\n", res.Version.Minor)
		fmt.Fprintf(w, "export VERSION_REVISION=%d\n", res.Version.Revision)
		fmt.Fprintf(w, "export VERSION_PATCH=%d\n", res.Version.Patch)
		fmt.Fprintf(w, "export VERSION=%s\n", shellQuote(res.Version.String()))
		fmt.Fprintf(w, "export TAG=%s\n", shellQuote(res.Version.Tag()))
	case "json":
		enc := json.NewEncoder(w)
		enc.SetIndent("", "  ")
		_ = enc.Encode(map[string]any{
			"lastTag":       res.LastTag,
			"branch":        res.Branch,
			"version":       res.Version.String(),
			"tag":           res.Version.Tag(),
			"branchVersion": res.Version.Branch,
			"major":         res.Version.Major,
			"minor":         res.Version.Minor,
			"revision":      res.Version.Revision,
			"patch":         res.Version.Patch,
			"trace":         res.Trace,
		})
	default: // text, matches get_version.sh
		fmt.Fprintf(w, "LAST_TAG=%s\n", res.LastTag)
		if !cfg.Quiet {
			for _, t := range res.Trace {
				fmt.Fprintln(w, t.Commit)
				fmt.Fprintf(w, " -> %s\n", t.Version)
			}
		}
		fmt.Fprintf(w, "VERSION=%s\n", res.Version.String())
		fmt.Fprintf(w, "TAG=%s\n", res.Version.Tag())
	}
}
