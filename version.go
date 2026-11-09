// Package main implements the versioner CLI.
//
// Version scheme (mirrors the legacy get_version.sh semantics):
//
//	VERSION = <branch-version>.<major>.<minor>.<revision>.<patch>
//	TAG     = "v" + VERSION
//
// The base version is taken from the most recent tag matching the configured
// pattern (default "v[0-9]*") found via `git describe`. If no such tag exists,
// the base is 0.0.0.0. The patch component is then replaced with the total
// commit count reachable from the tag (`git rev-list <tag> --count`), matching
// the original shell script.
//
// Each commit after the tag (or every commit when there is no tag) is then
// replayed oldest-first and bumps the version:
//
//   - breaking feat/feature/fix (prefix ends with "!"), e.g. "feat!:", "fix(scope)!:" -> major++, minor=0, revision=0
//   - feat / feature (with optional scope)                                             -> minor++, revision=0
//   - fix (with optional scope)                                                        -> revision++
//   - every replayed commit                                                            -> patch++
//
// Prefix matching is case-insensitive. Unrecognised prefixes only bump patch.
package main

import (
	"fmt"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
)

// Version is a computed version number.
type Version struct {
	Branch   int `json:"branch"`
	Major    int `json:"major"`
	Minor    int `json:"minor"`
	Revision int `json:"revision"`
	Patch    int `json:"patch"`
}

// String returns e.g. "254.1.2.3.4".
func (v Version) String() string {
	return fmt.Sprintf("%d.%d.%d.%d.%d", v.Branch, v.Major, v.Minor, v.Revision, v.Patch)
}

// Tag returns e.g. "v254.1.2.3.4".
func (v Version) Tag() string {
	return "v" + v.String()
}

// ParseTag parses a version tag of the form "v<branch>.<major>.<minor>.<revision>.<patch>".
//
// The leading "v" is required. Missing components default to 0, mirroring the
// shell script's `IFS='.' read` behaviour. Extra components beyond the fifth
// are ignored, as they were overwritten by the rev-list count in the script.
// The branch and patch components are parsed for validation; callers ignore
// branch (the current branch determines it) and replace patch with the
// rev-list count, again matching the script.
func ParseTag(tag string) (Version, error) {
	var v Version
	if !strings.HasPrefix(tag, "v") {
		return v, fmt.Errorf("tag %q does not start with \"v\"", tag)
	}
	body := strings.TrimPrefix(tag, "v")
	if body == "" {
		return v, fmt.Errorf("tag %q has no version components", tag)
	}
	parts := strings.Split(body, ".")
	fields := []*int{&v.Branch, &v.Major, &v.Minor, &v.Revision, &v.Patch}
	for i := 0; i < len(parts) && i < len(fields); i++ {
		n, err := strconv.Atoi(parts[i])
		if err != nil {
			return v, fmt.Errorf("tag %q has non-numeric component %q", tag, parts[i])
		}
		*fields[i] = n
	}
	return v, nil
}

// Commit type recognised by the version rules.
type CommitType string

const (
	CommitFeat    CommitType = "feat"
	CommitFeature CommitType = "feature"
	CommitFix     CommitType = "fix"
	CommitOther   CommitType = ""
)

// prefixRe matches a normalised conventional-commit prefix with optional scope.
var prefixRe = regexp.MustCompile(`^(feat|feature|fix)(\(.*\))?$`)

// ClassifyCommit extracts the commit type and breaking flag from a commit subject.
//
// It mirrors the shell bump_version() logic: take the text before the first
// ":", lowercase it, note a "!" (breaking), strip a trailing "!", then match
// the remainder against feat/feature/fix with an optional "(scope)".
func ClassifyCommit(subject string) (typ CommitType, breaking bool) {
	prefix := subject
	if i := strings.IndexByte(subject, ':'); i >= 0 {
		prefix = subject[:i]
	}
	prefix = strings.ToLower(prefix)

	// The shell script checks for a "!" anywhere in the prefix, then strips
	// a trailing "!" (if present). Replicate both so that e.g. "feat!scope"
	// still counts as breaking but fails the type regex and bumps nothing.
	if strings.Contains(prefix, "!") {
		breaking = true
		prefix = strings.TrimSuffix(prefix, "!")
	}

	m := prefixRe.FindStringSubmatch(prefix)
	if m == nil {
		return CommitOther, breaking
	}
	return CommitType(m[1]), breaking
}

// ApplyBump returns the version after replaying one commit subject.
func ApplyBump(v Version, subject string) Version {
	typ, breaking := ClassifyCommit(subject)
	switch {
	case breaking && (typ == CommitFeat || typ == CommitFeature || typ == CommitFix):
		v.Major++
		v.Minor = 0
		v.Revision = 0
	case typ == CommitFeat || typ == CommitFeature:
		v.Minor++
		v.Revision = 0
	case typ == CommitFix:
		v.Revision++
	}
	v.Patch++
	return v
}

// gitRun runs git in dir with the given arguments and returns trimmed stdout.
// It is a variable so tests can stub git without a real repository.
var gitRun = func(dir string, args ...string) (string, error) {
	full := append([]string{"-C", dir}, args...)
	cmd := exec.Command("git", full...)
	out, err := cmd.Output()
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return "", fmt.Errorf("git %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(string(ee.Stderr)))
		}
		if ee, ok := err.(*exec.Error); ok {
			return "", fmt.Errorf("git %s: %w", strings.Join(args, " "), ee.Err)
		}
		return "", fmt.Errorf("git %s: %w", strings.Join(args, " "), err)
	}
	return strings.TrimSpace(string(out)), nil
}

// LastTag returns the most recent tag matching pattern, or "" if none.
// Errors are swallowed (matching `git describe ... || true` in the shell
// script); a missing tag and a missing repo both yield "". Callers rely on
// the subsequent git log call to surface "not a repo / no commits" errors.
func LastTag(dir, pattern string) string {
	out, err := gitRun(dir, "describe", "--tags", "--abbrev=0", "--match", pattern)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(out)
}

// RevListCount returns `git rev-list <ref> --count`.
func RevListCount(dir, ref string) (int, error) {
	out, err := gitRun(dir, "rev-list", ref, "--count")
	if err != nil {
		return 0, err
	}
	n, err := strconv.Atoi(strings.TrimSpace(out))
	if err != nil {
		return 0, fmt.Errorf("cannot parse rev-list count %q: %w", out, err)
	}
	return n, nil
}

// CurrentBranch returns `git branch --show-current` ("" when detached).
// Errors are swallowed, matching the shell script's lenient behaviour.
func CurrentBranch(dir string) string {
	out, err := gitRun(dir, "branch", "--show-current")
	if err != nil {
		return ""
	}
	return strings.TrimSpace(out)
}

// LogSubjects returns commit subjects for ref range, oldest first.
func LogSubjects(dir, ref string) ([]string, error) {
	out, err := gitRun(dir, "log", ref, "--format=%s", "--reverse")
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(out) == "" {
		return nil, nil
	}
	lines := strings.Split(out, "\n")
	for i := range lines {
		lines[i] = strings.TrimRight(lines[i], "\r")
	}
	return lines, nil
}

// TraceEntry records the version after replaying a single commit.
type TraceEntry struct {
	Commit  string `json:"commit"`
	Version string `json:"version"`
}

// Result is the outcome of Compute.
type Result struct {
	LastTag  string       `json:"lastTag"`
	Branch   string       `json:"branch"`
	Version  Version      `json:"version"`
	Subjects []string     `json:"-"`
	Trace    []TraceEntry `json:"trace"`
}

// Compute derives the current version for repo dir using cfg.
//
// It performs the same steps as get_version.sh:
//  1. find the last tag, seed major/minor/revision from it (0 if none),
//     seed patch from `git rev-list <tag> --count` (0 if no tag);
//  2. resolve the branch version (exemptBranches or the default);
//  3. replay commits after the tag (or all commits) oldest-first.
func Compute(cfg *Config) (*Result, error) {
	dir := cfg.RepoDir
	head := cfg.Head
	if head == "" {
		head = "HEAD"
	}

	lastTag := LastTag(dir, cfg.TagPattern)

	base := Version{}
	if lastTag != "" {
		parsed, err := ParseTag(lastTag)
		if err != nil {
			return nil, fmt.Errorf("parsing last tag: %w", err)
		}
		base = parsed
		count, err := RevListCount(dir, lastTag)
		if err != nil {
			return nil, fmt.Errorf("counting commits up to %s: %w", lastTag, err)
		}
		base.Patch = count
	}

	branch := cfg.Branch
	if branch == "" {
		branch = CurrentBranch(dir)
	}
	branchVersion := cfg.DefaultBranchVersion
	if v, ok := cfg.ExemptBranches[branch]; ok && branch != "" {
		branchVersion = v
	}
	// cfg.ExemptBranches may be nil; indexing a nil map is safe.
	current := Version{
		Branch:   branchVersion,
		Major:    base.Major,
		Minor:    base.Minor,
		Revision: base.Revision,
		Patch:    base.Patch,
	}

	rng := head
	if lastTag != "" {
		rng = lastTag + ".." + head
	}
	subjects, err := LogSubjects(dir, rng)
	if err != nil {
		return nil, err
	}

	res := &Result{LastTag: lastTag, Branch: branch, Subjects: subjects}
	for _, s := range subjects {
		current = ApplyBump(current, s)
		res.Trace = append(res.Trace, TraceEntry{Commit: s, Version: current.String()})
	}
	res.Version = current
	return res, nil
}
