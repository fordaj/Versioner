package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseExemptBranches(t *testing.T) {
	for _, tc := range []struct {
		in      string
		want    map[string]int
		wantErr bool
	}{
		{"", map[string]int{}, false},
		{`{"main":1,"develop":2}`, map[string]int{"main": 1, "develop": 2}, false},
		{"main=1,develop=2", map[string]int{"main": 1, "develop": 2}, false},
		{"main=1", map[string]int{"main": 1}, false},
		{"main=1, release=3", map[string]int{"main": 1, "release": 3}, false},
		{"badentry", nil, true},
		{"main=xyz", nil, true},
		{`{not json}`, nil, true},
	} {
		got, err := ParseExemptBranches(tc.in)
		if tc.wantErr {
			if err == nil {
				t.Errorf("ParseExemptBranches(%q): expected error, got %v", tc.in, got)
			}
			continue
		}
		if err != nil {
			t.Errorf("ParseExemptBranches(%q): %v", tc.in, err)
			continue
		}
		if len(got) != len(tc.want) {
			t.Errorf("ParseExemptBranches(%q) = %v, want %v", tc.in, got, tc.want)
			continue
		}
		for k, v := range tc.want {
			if got[k] != v {
				t.Errorf("ParseExemptBranches(%q)[%q] = %d, want %d", tc.in, k, got[k], v)
			}
		}
	}
}

func TestLoadFile(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, ".versioner.json")
	body := `{
  "defaultBranchVersion": 7,
  "exemptBranches": {"main": 1},
  "tagPattern": "release-*",
  "repoDir": "/tmp/repo",
  "head": "HEAD~1"
}`
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	cfg := DefaultConfig()
	if err := cfg.LoadFile(p); err != nil {
		t.Fatalf("LoadFile: %v", err)
	}
	if cfg.DefaultBranchVersion != 7 || cfg.ExemptBranches["main"] != 1 ||
		cfg.TagPattern != "release-*" || cfg.RepoDir != "/tmp/repo" || cfg.Head != "HEAD~1" {
		t.Errorf("loaded: %+v", cfg)
	}
}

func TestLoadFileInvalid(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, ".versioner.json")
	if err := os.WriteFile(p, []byte("{not json"), 0o644); err != nil {
		t.Fatal(err)
	}
	cfg := DefaultConfig()
	if err := cfg.LoadFile(p); err == nil {
		t.Error("expected error for invalid JSON")
	}
}

func TestApplyEnv(t *testing.T) {
	cfg := DefaultConfig()
	cfg.ExemptBranches["main"] = 1
	env := map[string]string{
		EnvDefault:    "9",
		EnvTagPattern: "v*",
		EnvExempt:     `{"develop":2,"main":5}`,
		EnvFormat:     "json",
		EnvQuiet:      "true",
	}
	if err := cfg.ApplyEnv(func(k string) string { return env[k] }); err != nil {
		t.Fatalf("ApplyEnv: %v", err)
	}
	if cfg.DefaultBranchVersion != 9 {
		t.Errorf("DefaultBranchVersion = %d, want 9", cfg.DefaultBranchVersion)
	}
	if cfg.TagPattern != "v*" {
		t.Errorf("TagPattern = %q, want v*", cfg.TagPattern)
	}
	if cfg.ExemptBranches["main"] != 5 { // env overrides file per-branch
		t.Errorf("exempt main = %d, want 5", cfg.ExemptBranches["main"])
	}
	if cfg.ExemptBranches["develop"] != 2 {
		t.Errorf("exempt develop = %d, want 2", cfg.ExemptBranches["develop"])
	}
	if cfg.Format != "json" || !cfg.Quiet {
		t.Errorf("Format=%q Quiet=%v", cfg.Format, cfg.Quiet)
	}
}

func TestApplyEnvInvalid(t *testing.T) {
	cfg := DefaultConfig()
	if err := cfg.ApplyEnv(func(k string) string {
		if k == EnvDefault {
			return "notanint"
		}
		return ""
	}); err == nil {
		t.Error("expected error for bad int")
	}
}

func TestFindConfigFile(t *testing.T) {
	dir := t.TempDir()
	if FindConfigFile(dir) != "" {
		t.Error("expected no config file yet")
	}
	p := filepath.Join(dir, ".versioner.json")
	if err := os.WriteFile(p, []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := FindConfigFile(dir); got != p {
		t.Errorf("FindConfigFile = %q, want %q", got, p)
	}
}
