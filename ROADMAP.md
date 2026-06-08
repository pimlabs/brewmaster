# ROADMAP — brewmaster

> **For AI coding assistants:**
> This document is the single source of truth for brewmaster development.
> Each milestone defines its own scope, file contracts, and acceptance criteria.
> Do not implement features outside the active milestone scope unless explicitly instructed.
> Never add AI tool attribution to commits (no Co-authored-by trailers).

---

## Project Context

`brewmaster` is a CLI tool for selective package upgrades based on semver classification.
Core logic (semver parsing, bump classification, upgrade execution) lives in `bin/brewmaster`.
This roadmap defines modular development built on top of that core.

**Stack:** Bash (POSIX-compatible where possible), `jq`, `curl`
**Target OS:** macOS (Homebrew), with additional drivers for Linux (apt) in Milestone 5
**Distribution:** `brew tap pimlabs/brewmaster`

---

## Target Directory Structure (End State)

```
brewmaster/
├── bin/
│   └── brewmaster                  # main entry point
├── lib/
│   └── brewmaster/
│       ├── core/
│       │   ├── semver.sh           # to_semver_3, bump_kind, allow_by_level
│       │   ├── outdated.sh         # parse_outdated_line, fetch outdated list
│       │   └── upgrade.sh          # upgrade execution + reporting
│       ├── snapshot.sh             # Milestone 1
│       ├── depgraph.sh             # Milestone 2
│       ├── profile.sh              # Milestone 3
│       ├── sync.sh                 # Milestone 4
│       └── drivers/                # Milestone 5
│           ├── _base.sh
│           ├── brew.sh
│           ├── npm.sh
│           ├── pip.sh
│           └── cargo.sh
├── completions/
│   ├── brewmaster.bash
│   └── brewmaster.zsh
├── config/
│   └── profiles.toml.example
├── Formula/
│   └── brewmaster.rb
├── tests/
│   ├── test_semver.sh
│   ├── test_snapshot.sh
│   ├── test_depgraph.sh
│   ├── test_profile.sh
│   └── test_drivers.sh
├── ROADMAP.md
├── CONTRIBUTING.md
├── CHANGELOG.md
└── README.md
```

---

## Milestone 0 — Refactor & Foundation

**Status:** `[ ] todo`
**Branch:** `refactor/foundation`

### Scope

Break the monolithic `bin/brewmaster` into separate modules without changing behavior.
This is a prerequisite for all subsequent milestones.

### Tasks

- [ ] Extract `to_semver_3`, `bump_kind`, `allow_by_level` → `lib/brewmaster/core/semver.sh`
- [ ] Extract `parse_outdated_line` → `lib/brewmaster/core/outdated.sh`
- [ ] Create `lib/brewmaster/core/upgrade.sh` for execution + reporting loop
- [ ] Create `bin/brewmaster` as new entry point that sources all modules
- [ ] Ensure all existing flags (`--level`, `--or-lower`, `--dry-run`, etc.) still work
- [ ] Write `tests/test_semver.sh` with at least 10 test cases (edge cases: date versions, pre-release, +build)

### Acceptance Criteria

```bash
# All of these must produce identical output to the original script
brewmaster --dry-run
brewmaster --level=patch --dry-run
brewmaster --level=major --or-lower --dry-run
```

### Function Contracts (do not change these signatures in later milestones)

```bash
# semver.sh
to_semver_3 "$raw_version"                        # stdout: "M.m.p" | return 1 on failure
bump_kind "$old_sv" "$new_sv"                     # stdout: major|minor|patch|downgrade|none
allow_by_level "$kind" "$level" "$or_lower"       # return 0/1
```

---

## Milestone 1 — Snapshot & Rollback

**Status:** `[ ] todo`
**Branch:** `feat/snapshot`
**Depends on:** Milestone 0

### Scope

Save Homebrew state before an upgrade, and restore to a specific snapshot.

### Files Created/Modified

- `lib/brewmaster/snapshot.sh` — all snapshot logic
- `bin/brewmaster` — add `snapshot` subcommand

### Specification: `snapshot.sh`

```bash
snapshot_save [label]
# Save to ~/.local/share/brewmaster/snapshots/YYYYMMDD-HHMMSS[-label].txt
# File format: "package_name\tversion" per line (from brew list --versions)
# stdout: path of saved snapshot

snapshot_list
# Print table: INDEX | TIMESTAMP | LABEL | PACKAGE_COUNT
# Sort: newest first

snapshot_restore "$snapshot_path_or_index"
# For each package in snapshot:
#   - current version > snapshot → brew install package@version (pin)
#   - package missing → brew install package@version
#   - version matches → skip
# Respects $DRY_RUN global

snapshot_diff "$snapshot_path_or_index"
# Print packages that changed since snapshot
# Format: "package  snapshot_ver  ->  current_ver  [UPGRADE|DOWNGRADE|NEW|REMOVED]"

snapshot_delete "$snapshot_path_or_index"
# Delete snapshot file, interactive confirmation unless --force
```

### CLI Commands

```bash
brewmaster snapshot save [--label="before-work-upgrade"]
brewmaster snapshot list
brewmaster snapshot diff [INDEX|PATH]
brewmaster snapshot restore [INDEX|PATH] [--dry-run]
brewmaster snapshot delete [INDEX|PATH] [--force]
```

### Storage

```
~/.local/share/brewmaster/snapshots/
├── 20250601-143022.txt
├── 20250601-143022.meta.json    # { "label": "", "brew_version": "4.x", "package_count": 42 }
└── 20250601-150000-before-work.txt
```

### Acceptance Criteria

```bash
brewmaster snapshot save --label="test"
# → File saved, path printed to stdout

brewmaster snapshot list
# → Readable table with "test" entry visible

brewmaster snapshot restore 1 --dry-run
# → Show plan without executing brew

brewmaster snapshot diff 1
# → Show which packages changed since snapshot 1
```

---

## Milestone 2 — Dependency Graph Awareness

**Status:** `[ ] todo`
**Branch:** `feat/depgraph`
**Depends on:** Milestone 0

### Scope

Before upgrading package X, check whether dependent packages may be affected.
Flag packages as "risky" based on dependency analysis.

### Files Created/Modified

- `lib/brewmaster/depgraph.sh`
- `bin/brewmaster` — add `--check-deps` flag

### Specification: `depgraph.sh`

```bash
depgraph_build
# Build graph: package → [dependents]
# Run once at startup if --check-deps is active
# Uses: brew uses --installed "$pkg" per outdated package
# Cache to /tmp/brewmaster-depgraph-$$.json (cleaned on EXIT trap)

depgraph_check "$package_name"
# stdout: JSON array of dependents
# return 0 if safe, return 1 if risky dependents detected

depgraph_risk_score "$package_name"
# Calculate risk score 0–10:
#   +3 if dependents are actively installed (brew uses --installed count > 0)
#   +3 if bump kind is major
#   +2 if dependent count > 3
#   +2 if package is a build-time dep (--include-build)
# stdout: integer 0–10

depgraph_report "$package_name"
# stdout: human-readable dependents table + risk score
```

### Integration in Upgrade Flow

```
When --check-deps is active:
  RISK_HIGH   (score >= 7)  → skip, show warning
  RISK_MEDIUM (score 4–6)   → show warning, ask confirmation (unless --yes)
  RISK_LOW    (score 0–3)   → upgrade normally
```

### CLI

```bash
brewmaster --check-deps [--risk-threshold=5] [--yes]
brewmaster depgraph show "$package"
```

### Acceptance Criteria

```bash
brewmaster depgraph show openssl
# → Show dependents table

brewmaster --check-deps --dry-run
# → High-risk packages flagged and excluded from UPGRADE_LIST
```

---

## Milestone 3 — Profile System

**Status:** `[ ] todo`
**Branch:** `feat/profiles`
**Depends on:** Milestone 0

### Scope

Named profiles to filter which packages get upgraded.
One machine can have multiple profiles for different work contexts.

### Files Created/Modified

- `lib/brewmaster/profile.sh`
- `config/profiles.toml.example`
- `bin/brewmaster` — add `--profile` flag

### Config Format

```toml
# ~/.config/brewmaster/profiles.toml

[profiles.work]
description = "Core dev tools"
include = ["node", "python@3.12", "git", "gh", "jq", "ripgrep"]

[profiles.media]
description = "Media processing"
include = ["ffmpeg", "imagemagick", "yt-dlp"]

[profiles.safe]
description = "Everything, but skip risky packages"
include = []                  # empty = all packages
exclude = ["openssl", "curl"]
max_risk_score = 5            # requires Milestone 2
level = "minor"               # overrides --level for this profile

[profiles.client-demo]
description = "Lock everything before a demo"
include = []
exclude = []
require_confirm = true
level = "patch"
```

### Specification: `profile.sh`

```bash
profile_load "$name"
# Parse profiles.toml, set globals:
#   PROFILE_INCLUDE (array)
#   PROFILE_EXCLUDE (array)
#   PROFILE_REQUIRE_CONFIRM (bool)
#   PROFILE_MAX_RISK (int, default 10)
#   PROFILE_LEVEL (string, overrides LEVEL if set)
# return 1 if profile not found

profile_list
# Print all defined profiles with descriptions

profile_filter_package "$pkg_name"
# return 0 if package is allowed under active profile
# return 1 if package should be skipped

profile_create "$name"     # interactive wizard
profile_edit "$name"       # open profiles.toml in $EDITOR
profile_validate           # check profiles.toml syntax, report errors
```

### CLI

```bash
brewmaster --profile=work --dry-run
brewmaster --profile=safe --check-deps
brewmaster profile list
brewmaster profile create
brewmaster profile edit work
brewmaster profile validate
```

### Acceptance Criteria

```bash
cat > ~/.config/brewmaster/profiles.toml <<'EOF'
[profiles.test]
description = "Test profile"
include = ["git"]
EOF

brewmaster profile list
# → Shows "test" profile

brewmaster --profile=test --dry-run
# → Only git appears as upgrade candidate

brewmaster --profile=nonexistent
# → Clear error: "Profile 'nonexistent' not found"
```

---

## Milestone 4 — Cross-Machine Sync

**Status:** `[ ] todo`
**Branch:** `feat/sync`
**Depends on:** Milestone 0, Milestone 3 (optional, for profile sync)

### Scope

Export an upgrade plan and config to a portable format.
Import and apply on another machine.

### Files Created/Modified

- `lib/brewmaster/sync.sh`
- `bin/brewmaster` — add `sync` subcommand

### Export Format (`.brewmaster-plan.json`)

```json
{
  "version": "1",
  "created_at": "2025-06-08T14:30:00Z",
  "source_machine": "MacBook-Pro",
  "brewmaster_version": "0.5.0",
  "options": {
    "level": "minor",
    "or_lower": false,
    "profile": "work"
  },
  "packages": [
    {
      "name": "git",
      "old_version": "2.44.0",
      "new_version": "2.45.0",
      "bump_kind": "minor",
      "risk_score": 1
    }
  ],
  "profiles": {}
}
```

### Specification: `sync.sh`

```bash
sync_export "$output_file" [--include-profiles]
# Generate plan JSON from computed UPGRADE_LIST
# stdout: path of saved file

sync_import "$input_file" [--dry-run] [--skip-unknown]
# Read plan, apply upgrades only if:
#   1. Package exists on this machine
#   2. Current version is older than plan version (no downgrade)

sync_diff "$input_file"
# Compare plan against current machine state
# Output: WILL_APPLY | ALREADY_DONE | NOT_INSTALLED | WOULD_DOWNGRADE

sync_push "$remote" "$input_file"
# Send file via scp/rsync or GitHub Gist (--via=gist)
# Remote: user@host:path OR gist:GIST_ID

sync_pull "$remote" [--dry-run]
# Fetch plan from remote, import directly
```

### CLI

```bash
brewmaster sync export --include-profiles -o plan.json
brewmaster sync push user@other-machine:~/plan.json
brewmaster sync push --via=gist plan.json

brewmaster sync pull user@other-machine:~/plan.json --dry-run
brewmaster sync diff plan.json
brewmaster sync import plan.json
```

### Acceptance Criteria

```bash
brewmaster sync export -o /tmp/test-plan.json
# → Valid JSON file created

brewmaster sync diff /tmp/test-plan.json
# → Shows WILL_APPLY / ALREADY_DONE per package

brewmaster sync import /tmp/test-plan.json --dry-run
# → Shows plan without executing
```

---

## Milestone 5 — Multi-Package Manager Drivers

**Status:** `[ ] todo`
**Branch:** `feat/drivers`
**Depends on:** Milestone 0

### Scope

Abstract a driver interface so the same semver logic works across multiple package managers.

### Driver Interface Contract

```bash
# lib/brewmaster/drivers/_base.sh — interface documentation + helpers
#
# Every driver MUST implement:
#
#   driver_name            → stdout: "brew" | "npm" | "pip" | "cargo"
#   driver_available       → return 0 if PM is installed, 1 if not
#   driver_outdated        → stdout: stream of "name|old_version|new_version" (one per line)
#   driver_upgrade "$name" → execute upgrade, return 0/1
#   driver_list_installed  → stdout: stream of "name\tversion"
#
# Optional (for advanced features):
#   driver_deps "$name"              → stdout: JSON array of dependencies
#   driver_pin "$name" "$version"    → pin package to specific version
#   driver_unpin "$name"             → remove pin
```

### Driver Implementations

**`drivers/brew.sh`** — refactored from existing core
```bash
driver_outdated    # brew outdated --verbose
driver_upgrade     # brew upgrade "$name"
driver_list        # brew list --versions
driver_deps        # brew deps --installed "$name"
```

**`drivers/npm.sh`** — npm global packages
```bash
driver_outdated    # npm outdated -g --json
driver_upgrade     # npm install -g "$name@latest"
driver_list        # npm list -g --depth=0 --json
```

**`drivers/pip.sh`** — pip global packages
```bash
driver_outdated    # pip list --outdated --format=json
driver_upgrade     # pip install --upgrade "$name"
driver_list        # pip list --format=json
```

**`drivers/cargo.sh`** — cargo binaries
```bash
driver_outdated    # cargo install --list + crates.io API check
driver_upgrade     # cargo install "$name" --force
driver_list        # cargo install --list (parsed)
```

### CLI

```bash
brewmaster --dry-run                        # brew only (default)
brewmaster --drivers=brew,npm --dry-run     # brew + npm
brewmaster --drivers=all --dry-run          # all available drivers

brewmaster drivers list                     # list all drivers
brewmaster drivers status                   # show availability on this machine
```

### Output Format

```
Upgrade candidates (5) [level=minor]:
  [brew]  git          2.44.0 -> 2.45.0  [minor]
  [brew]  jq           1.6.0  -> 1.7.0   [minor]
  [npm]   typescript   5.3.0  -> 5.4.0   [minor]
  [pip]   black        24.1.0 -> 24.3.0  [minor]
  [cargo] ripgrep      13.0.0 -> 14.0.0  [major] ← skipped (level=minor)
```

### Acceptance Criteria

```bash
brewmaster drivers status
# → Table: driver | available | version

brewmaster --drivers=brew,npm --dry-run
# → Combined output with clear [brew]/[npm] labels

brewmaster --drivers=npm --level=minor --dry-run
# → Same semver logic as brew driver, npm packages only
```

---

## Milestone Dependency Graph

```
M0 (Refactor)
├── M1 (Snapshot)   ← independent after M0
├── M2 (DepGraph)   ← independent after M0
├── M3 (Profiles)   ← independent after M0
│   └── M4 (Sync)  ← requires M0 + M3
└── M5 (Drivers)    ← independent after M0
```

---

## Version Targets

| Version | Milestone                        |
|---------|----------------------------------|
| v0.1.0  | M0 — Refactor & Foundation       |
| v0.2.0  | M1 — Snapshot & Rollback         |
| v0.3.0  | M2 — Dependency Graph            |
| v0.4.0  | M3 — Profile System              |
| v0.5.0  | M4 — Cross-Machine Sync          |
| v1.0.0  | M5 — Multi-Driver + stable API   |

---

## Coding Conventions (for AI Assistants)

1. Every public function must have a header comment: purpose, args, stdout, return code
2. Use `local` for all variables inside functions
3. No `set -e` inside functions — handle errors explicitly with `|| return 1`
4. `DRY_RUN` is a global boolean — always check before any destructive execution
5. `VERBOSE` is a global boolean — use `logv()` from core for debug output
6. All user paths use `${XDG_DATA_HOME:-$HOME/.local/share}/brewmaster/`
7. `jq` is available — declared as dependency in formula
8. Test functions follow: `test_functionname_condition()` + simple assert helpers
9. **Never add Co-authored-by or any AI tool attribution to commits**

---

*Update milestone status from `[ ] todo` to `[x] done` after each milestone is complete.*
