package main

import (
	"strings"
	"testing"
)

func TestParseTag(t *testing.T) {
	for _, tc := range []struct {
		tag     string
		want    Version
		wantErr bool
	}{
		{"v254.1.2.3.4", Version{254, 1, 2, 3, 4}, false},
		{"v1.0.0.0.0", Version{1, 0, 0, 0, 0}, false},
		{"v254.0.1.0.0", Version{254, 0, 1, 0, 0}, false},
		{"v2.3", Version{2, 3, 0, 0, 0}, false},                 // missing -> 0
		{"v2", Version{2, 0, 0, 0, 0}, false},                   // shell `read` defaults
		{"v254.1.2.3.4.extra", Version{254, 1, 2, 3, 4}, false}, // extra ignored
		{"254.1.2.3.4", Version{}, true},                        // missing v
		{"vfoo", Version{}, true},                               // non-numeric
		{"v", Version{}, true},                                  // empty body
	} {
		got, err := ParseTag(tc.tag)
		if tc.wantErr {
			if err == nil {
				t.Errorf("ParseTag(%q): expected error, got %+v", tc.tag, got)
			}
			continue
		}
		if err != nil {
			t.Errorf("ParseTag(%q): unexpected error: %v", tc.tag, err)
			continue
		}
		if got != tc.want {
			t.Errorf("ParseTag(%q) = %+v, want %+v", tc.tag, got, tc.want)
		}
	}
}

func TestVersionStringTag(t *testing.T) {
	v := Version{254, 1, 2, 3, 4}
	if v.String() != "254.1.2.3.4" {
		t.Errorf("String() = %q", v.String())
	}
	if v.Tag() != "v254.1.2.3.4" {
		t.Errorf("Tag() = %q", v.Tag())
	}
}

func TestClassifyAndBump(t *testing.T) {
	start := Version{Branch: 254, Major: 1, Minor: 2, Revision: 3, Patch: 4}
	for _, tc := range []struct {
		subject string
		want    Version
	}{
		{"feat: add x", Version{254, 1, 3, 0, 5}},
		{"feat(api): add x", Version{254, 1, 3, 0, 5}},
		{"feature: add x", Version{254, 1, 3, 0, 5}},
		{"feature(ui): add x", Version{254, 1, 3, 0, 5}},
		{"feat!: breaking", Version{254, 2, 0, 0, 5}},
		{"feat(api)!: breaking", Version{254, 2, 0, 0, 5}},
		{"feature!: breaking", Version{254, 2, 0, 0, 5}},
		{"fix: bug", Version{254, 1, 2, 4, 5}},
		{"fix(web): bug", Version{254, 1, 2, 4, 5}},
		{"fix!: breaking", Version{254, 2, 0, 0, 5}},
		{"fix(core)!: breaking", Version{254, 2, 0, 0, 5}},
		{"FEAT: upper", Version{254, 1, 3, 0, 5}},
		{"Fix(core): upper", Version{254, 1, 2, 4, 5}},
		{"docs: readme", Version{254, 1, 2, 3, 5}},           // patch only
		{"Initial commit", Version{254, 1, 2, 3, 5}},         // no colon
		{"chore!: breaking other", Version{254, 1, 2, 3, 5}}, // breaking other => patch only
		{"featx: not a type", Version{254, 1, 2, 3, 5}},
	} {
		got := ApplyBump(start, tc.subject)
		if got != tc.want {
			t.Errorf("ApplyBump(..., %q) = %+v, want %+v", tc.subject, got, tc.want)
		}
	}
}

// stubGit replaces gitRun with a function keyed by the full command string.
func stubGit(t *testing.T, replies map[string]string) func() {
	t.Helper()
	orig := gitRun
	gitRun = func(dir string, args ...string) (string, error) {
		key := strings.Join(args, " ")
		if v, ok := replies[key]; ok {
			return v, nil
		}
		return "", errUnexpectedGit(key)
	}
	return func() { gitRun = orig }
}

type unexpectedGit struct{ cmd string }

func (e unexpectedGit) Error() string { return "unexpected git: " + e.cmd }

func errUnexpectedGit(cmd string) error { return unexpectedGit{cmd} }

func TestComputeNoTag(t *testing.T) {
	restore := stubGit(t, map[string]string{
		"describe --tags --abbrev=0 --match v[0-9]*": "",
		"branch --show-current":                      "main",
		"log HEAD --format=%s --reverse":             "feat: one\nfix: two\nchore: three",
	})
	defer restore()

	cfg := DefaultConfig()
	res, err := Compute(cfg)
	if err != nil {
		t.Fatalf("Compute: %v", err)
	}
	// 0,0,0,0 + feat(minor) + fix(rev) + chore(patch) = 0,1,1,3
	want := Version{Branch: 254, Major: 0, Minor: 1, Revision: 1, Patch: 3}
	if res.Version != want {
		t.Errorf("Version = %+v, want %+v", res.Version, want)
	}
	if len(res.Trace) != 3 {
		t.Errorf("trace len = %d, want 3 (%v)", len(res.Trace), res.Trace)
	}
	if res.Branch != "main" || res.LastTag != "" {
		t.Errorf("Branch=%q LastTag=%q", res.Branch, res.LastTag)
	}
}

func TestComputeWithTag(t *testing.T) {
	restore := stubGit(t, map[string]string{
		"describe --tags --abbrev=0 --match v[0-9]*":   "v254.1.2.3.4",
		"rev-list v254.1.2.3.4 --count":                "10",
		"branch --show-current":                        "feature-x",
		"log v254.1.2.3.4..HEAD --format=%s --reverse": "feat!: big\nfix: small",
	})
	defer restore()

	cfg := DefaultConfig()
	res, err := Compute(cfg)
	if err != nil {
		t.Fatalf("Compute: %v", err)
	}
	// base 1.2.3.10 -> major 2.0.0.11 -> rev 2.0.1.12
	want := Version{Branch: 254, Major: 2, Minor: 0, Revision: 1, Patch: 12}
	if res.Version != want {
		t.Errorf("Version = %+v, want %+v", res.Version, want)
	}
	if res.LastTag != "v254.1.2.3.4" {
		t.Errorf("LastTag = %q", res.LastTag)
	}
}

func TestComputeExemptBranch(t *testing.T) {
	restore := stubGit(t, map[string]string{
		"describe --tags --abbrev=0 --match v[0-9]*": "",
		"branch --show-current":                      "main",
		"log HEAD --format=%s --reverse":             "fix: one",
	})
	defer restore()

	cfg := DefaultConfig()
	cfg.ExemptBranches["main"] = 1
	res, err := Compute(cfg)
	if err != nil {
		t.Fatalf("Compute: %v", err)
	}
	if res.Version.Branch != 1 {
		t.Errorf("Branch = %d, want 1", res.Version.Branch)
	}
}

func TestComputeNoCommitsAfterTag(t *testing.T) {
	restore := stubGit(t, map[string]string{
		"describe --tags --abbrev=0 --match v[0-9]*":   "v254.1.2.3.4",
		"rev-list v254.1.2.3.4 --count":                "7",
		"branch --show-current":                        "main",
		"log v254.1.2.3.4..HEAD --format=%s --reverse": "",
	})
	defer restore()

	cfg := DefaultConfig()
	res, err := Compute(cfg)
	if err != nil {
		t.Fatalf("Compute: %v", err)
	}
	want := Version{Branch: 254, Major: 1, Minor: 2, Revision: 3, Patch: 7}
	if res.Version != want {
		t.Errorf("Version = %+v, want %+v", res.Version, want)
	}
	if len(res.Trace) != 0 {
		t.Errorf("trace = %v, want empty", res.Trace)
	}
}
