package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// Config holds every tunable of versioner.
//
// Precedence, lowest to highest: built-in defaults, .versioner.json,
// VERSIONER_* environment variables, command-line flags.
type Config struct {
	ConfigPath           string         `json:"-"`
	RepoDir              string         `json:"repoDir"`
	Head                 string         `json:"head"`
	Branch               string         `json:"branch"`
	TagPattern           string         `json:"tagPattern"`
	DefaultBranchVersion int            `json:"defaultBranchVersion"`
	ExemptBranches       map[string]int `json:"exemptBranches"`

	// Flags-only knobs, not serialised to .versioner.json.
	Format string `json:"-"`
	Quiet  bool   `json:"-"`
}

// DefaultConfig returns the built-in defaults.
func DefaultConfig() *Config {
	return &Config{
		RepoDir:              ".",
		Head:                 "HEAD",
		TagPattern:           "v[0-9]*",
		DefaultBranchVersion: 254,
		ExemptBranches:       map[string]int{},
		Format:               "text",
	}
}

// DefaultConfigFile is the name of the per-project config file.
const DefaultConfigFile = ".versioner.json"

// Env vars honoured by ApplyEnv.
const (
	EnvConfig     = "VERSIONER_CONFIG"
	EnvRepoDir    = "VERSIONER_REPO_DIR"
	EnvHead       = "VERSIONER_HEAD"
	EnvBranch     = "VERSIONER_BRANCH"
	EnvTagPattern = "VERSIONER_TAG_PATTERN"
	EnvDefault    = "VERSIONER_DEFAULT_BRANCH_VERSION"
	EnvExempt     = "VERSIONER_EXEMPT_BRANCHES"
	EnvFormat     = "VERSIONER_FORMAT"
	EnvQuiet      = "VERSIONER_QUIET"
)

// FindConfigFile locates a .versioner.json for repo dir.
// It checks repoDir/.versioner.json then the current working directory's.
// Returns "" when no file exists.
func FindConfigFile(repoDir string) string {
	for _, dir := range []string{repoDir, "."} {
		if dir == "" {
			continue
		}
		p := filepath.Join(dir, DefaultConfigFile)
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

// LoadFile parses a .versioner.json file into a Config overlaid on dst.
func (c *Config) LoadFile(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	c.ConfigPath = path

	// Parse into a partial struct so omitted fields keep existing values.
	var raw struct {
		RepoDir              *string        `json:"repoDir"`
		Head                 *string        `json:"head"`
		Branch               *string        `json:"branch"`
		TagPattern           *string        `json:"tagPattern"`
		DefaultBranchVersion *int           `json:"defaultBranchVersion"`
		ExemptBranches       map[string]int `json:"exemptBranches"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	if raw.RepoDir != nil {
		c.RepoDir = *raw.RepoDir
	}
	if raw.Head != nil {
		c.Head = *raw.Head
	}
	if raw.Branch != nil {
		c.Branch = *raw.Branch
	}
	if raw.TagPattern != nil {
		c.TagPattern = *raw.TagPattern
	}
	if raw.DefaultBranchVersion != nil {
		c.DefaultBranchVersion = *raw.DefaultBranchVersion
	}
	if raw.ExemptBranches != nil {
		// Explicit map in file replaces the contents (file is authoritative
		// for exempt branches; env/flags merge on top).
		c.ExemptBranches = raw.ExemptBranches
	}
	return nil
}

// ParseExemptBranches parses exempt-branch definitions in either form:
//
//   - JSON object: {"main":1,"develop":2}
//   - comma list:  main=1,develop=2   (also accepts "main:1")
//
// Empty string yields an empty (non-nil) map.
func ParseExemptBranches(s string) (map[string]int, error) {
	out := map[string]int{}
	s = strings.TrimSpace(s)
	if s == "" {
		return out, nil
	}
	if strings.HasPrefix(s, "{") {
		if err := json.Unmarshal([]byte(s), &out); err != nil {
			return nil, fmt.Errorf("parsing %s as JSON: %w", EnvExempt, err)
		}
		return out, nil
	}
	for _, pair := range strings.Split(s, ",") {
		pair = strings.TrimSpace(pair)
		if pair == "" {
			continue
		}
		var key, val string
		if i := strings.IndexByte(pair, '='); i >= 0 {
			key, val = pair[:i], pair[i+1:]
		} else if i := strings.IndexByte(pair, ':'); i >= 0 {
			key, val = pair[:i], pair[i+1:]
		} else {
			return nil, fmt.Errorf("exempt branch entry %q must be branch=version", pair)
		}
		key = strings.TrimSpace(key)
		n, err := strconv.Atoi(strings.TrimSpace(val))
		if err != nil {
			return nil, fmt.Errorf("exempt branch %q: invalid version %q", key, val)
		}
		if key == "" {
			return nil, fmt.Errorf("exempt branch entry %q has an empty branch name", pair)
		}
		out[key] = n
	}
	return out, nil
}

// ParseBool parses boolean env values.
func ParseBool(s string) (bool, error) {
	return strconv.ParseBool(strings.TrimSpace(s))
}

// ApplyEnv overlays VERSIONER_* variables. getenv defaults to os.Getenv
// so tests can inject an environment.
func (c *Config) ApplyEnv(getenv func(string) string) error {
	if getenv == nil {
		getenv = os.Getenv
	}
	// Note: EnvConfig is consumed by main before ApplyEnv (it selects the
	// file, so it cannot be applied here). Ignore it here.
	if v := getenv(EnvRepoDir); v != "" {
		c.RepoDir = v
	}
	if v := getenv(EnvHead); v != "" {
		c.Head = v
	}
	if v := getenv(EnvBranch); v != "" {
		c.Branch = v
	}
	if v := getenv(EnvTagPattern); v != "" {
		c.TagPattern = v
	}
	if v := getenv(EnvDefault); v != "" {
		n, err := strconv.Atoi(strings.TrimSpace(v))
		if err != nil {
			return fmt.Errorf("%s: invalid integer %q", EnvDefault, v)
		}
		c.DefaultBranchVersion = n
	}
	if v := getenv(EnvExempt); v != "" {
		m, err := ParseExemptBranches(v)
		if err != nil {
			return fmt.Errorf("%s: %w", EnvExempt, err)
		}
		// Merge: env entries override file entries per-branch.
		for k, val := range m {
			c.ExemptBranches[k] = val
		}
	}
	if v := getenv(EnvFormat); v != "" {
		c.Format = v
	}
	if v := getenv(EnvQuiet); v != "" {
		b, err := ParseBool(v)
		if err != nil {
			return fmt.Errorf("%s: invalid boolean %q", EnvQuiet, v)
		}
		c.Quiet = b
	}
	return nil
}
