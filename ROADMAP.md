# ROADMAP — brewmaster

> **For AI coding assistants (Claude Code and others):**
> This document is the single source of truth for brewmaster development.
> Read this file in full before writing any code.
> Do not implement features outside the active milestone scope.
> Do not add Co-authored-by or any AI attribution to commits.
> When a milestone is complete, update its status from `[ ] todo` to `[x] done`.

---

## Philosophy

> **brewmaster knows what's on your machine — and why.**
> Upgrade only what's deliberate. Keep only what's intentional.

Every feature in this roadmap answers one of these questions:

| Question | Answered by |
|---|---|
| Am I safe to proceed? | M1 — Snapshot |
| What's risky to upgrade? | M2 — Dependency Graph |
| What should I upgrade right now? | M3 — Profile System |
| What belongs on my machine? | M4 — Cleanup & Intent |
| What happened over time? | M5 — Audit Log |

If a proposed feature does not answer one of these questions, it is out of scope.

---

## Project Context

`brewmaster` is a CLI tool for selective package upgrades based on semver classification.
Core logic lives in `bin/brewmaster`, modularized across `lib/brewmaster/core/`.

**Stack:** Bash (POSIX-compatible where possible), `jq`, `curl`, `fzf` (optional)
**Target OS:** macOS (Homebrew)
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
│       │   ├── semver.sh           # M0: to_semver_3, bump_kind, allow_by_level
│       │   ├── outdated.sh         # M0: parse_outdated_line, fetch outdated list
│       │   └── upgrade.sh          # M0: upgrade execution + reporting
│       ├── snapshot.sh             # M1
│       ├── depgraph.sh             # M2
│       ├── profile.sh              # M3
│       └── cleanup.sh              # M4
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
│   └── test_cleanup.sh
├── ROADMAP.md
├── CONTRIBUTING.md
├── CHANGELOG.md
└── README.md
```

---

## Milestone Dependency Graph

```
M0 (core)
├── M1 (snapshot)   ← required by M4
├── M2 (depgraph)   ← required by M3, M4
│   └── M3 (profile) ← required by M4
│       └── M4 (cleanup) ← required by M5
│           └── M5 (audit)
```

Each milestone is independently shippable after its dependencies are met.

---

## Milestone 0 — Refactor & Foundation

**Status:** `[x] done`
**Branch:** `refactor/foundation`
**Version:** `v0.1.0`

### Scope

Break the monolithic `bin/brewmaster` into separate modules without changing behavior.
Prerequisite for all subsequent milestones.

### Tasks

- [x] Extract `to_semver_3`, `bump_kind`, `allow_by_level` → `lib/brewmaster/core/semver.sh`
- [x] Extract `parse_outdated_line` → `lib/brewmaster/core/outdated.sh`
- [x] Create `lib/brewmaster/core/upgrade.sh` for execution + reporting loop
- [x] Create `bin/brewmaster` as new entry point that sources all modules
- [x] Ensure all existing flags (`--level`, `--or-lower`, `--dry-run`) still work
- [x] Write `tests/test_semver.sh` with at least 10 test cases

### Function Contracts (frozen — do not change these signatures)

```bash
# semver.sh
to_semver_3 "$raw_version" "$allow_date"   # stdout: "M.m.p" | return 1 on failure
bump_kind "$old_sv" "$new_sv"              # stdout: major|minor|patch|downgrade|none
allow_by_level "$kind" "$level" "$or_lower" # return 0/1

# outdated.sh
parse_outdated_line "$line"                # stdout: "name|old|new" | return 1
```

### Acceptance Criteria

```bash
brewmaster --dry-run
brewmaster --level=patch --dry-run
brewmaster --level=major --or-lower --dry-run
# All must produce identical output to the original monolithic script
```

---

## Milestone 1 — Snapshot & Rollback

**Status:** `[x] done`
**Branch:** `feat/snapshot`
**Version:** `v0.2.0`
**Depends on:** M0

### Scope

Save Homebrew state before an upgrade. Restore to any prior snapshot.
Used as a safety net — called automatically by M4 before cleanup.

### Files

- `lib/brewmaster/snapshot.sh`
- `bin/brewmaster` — add `snapshot` subcommand

### Function Contracts

```bash
snapshot_save [label]
# Save to ~/.local/share/brewmaster/snapshots/YYYYMMDD-HHMMSS[-label].txt
# Format: "package_name\tversion" per line (brew list --versions)
# stdout: path of saved snapshot file

snapshot_list
# Print table: INDEX | TIMESTAMP | LABEL | PACKAGE_COUNT
# Sort: newest first

snapshot_restore "$snapshot_path_or_index"
# For each package in snapshot:
#   current version > snapshot → brew install package@version (pin)
#   package missing → brew install package@version
#   version matches → skip
# Respects $DRY_RUN global

snapshot_diff "$snapshot_path_or_index"
# stdout: "package  snapshot_ver  ->  current_ver  [UPGRADE|DOWNGRADE|NEW|REMOVED]"

snapshot_delete "$snapshot_path_or_index"
# Interactive confirmation unless --force
```

### Storage

```
~/.local/share/brewmaster/snapshots/
├── 20250601-143022.txt
└── 20250601-143022.meta.json   # { "label": "", "brew_version": "4.x", "package_count": 42 }
```

### CLI

```bash
brewmaster snapshot save [--label="before-work-upgrade"]
brewmaster snapshot list
brewmaster snapshot diff [INDEX|PATH]
brewmaster snapshot restore [INDEX|PATH] [--dry-run]
brewmaster snapshot delete [INDEX|PATH] [--force]
```

### Acceptance Criteria

```bash
brewmaster snapshot save --label="test"     # file saved, path printed
brewmaster snapshot list                    # table shows "test" entry
brewmaster snapshot restore 1 --dry-run     # plan shown, nothing executed
brewmaster snapshot diff 1                  # changed packages shown
```

---

## Milestone 2 — Dependency Graph Awareness

**Status:** `[x] done`
**Branch:** `feat/depgraph`
**Version:** `v0.3.0`
**Depends on:** M0

### Scope

Before upgrading package X, check if dependent packages may break.
Risk score 0–10 per package. Consumed by M3 (configurable threshold per profile).

### Files

- `lib/brewmaster/depgraph.sh`
- `bin/brewmaster` — add `--check-deps` flag

### Function Contracts

```bash
depgraph_build
# Build graph: package → [dependents]
# Uses: brew uses --installed "$pkg" per outdated package
# Cache: /tmp/brewmaster-depgraph-$$.json (cleaned on EXIT trap)

depgraph_check "$package_name"
# stdout: JSON array of dependents
# return 0 if safe, return 1 if risky dependents detected

depgraph_risk_score "$package_name"
# Score 0–10:
#   +3 if dependents are actively installed (brew uses --installed count > 0)
#   +3 if bump kind is major
#   +2 if dependent count > 3
#   +2 if package is a build-time dep (--include-build)
# stdout: integer 0–10

depgraph_report "$package_name"
# stdout: human-readable dependents table + risk score
```

### Risk Integration

```
RISK_HIGH   (score >= 7) → skip, show warning
RISK_MEDIUM (score 4–6)  → show warning, ask confirmation (unless --yes)
RISK_LOW    (score 0–3)  → upgrade normally
```

### CLI

```bash
brewmaster --check-deps [--risk-threshold=5] [--yes]
brewmaster depgraph show "$package"
```

### Acceptance Criteria

```bash
brewmaster depgraph show openssl         # dependents table shown
brewmaster --check-deps --dry-run        # high-risk packages excluded from list
```

---

## Milestone 3 — Profile System

**Status:** `[x] done`
**Branch:** `feat/profiles`
**Version:** `v0.4.0`
**Depends on:** M0, M2 (for risk_threshold per profile)

### Scope

Named profiles to filter which packages get upgraded, and how aggressively.
One machine can have multiple profiles for different work contexts.
Includes `--interactive` flag (fzf-based) as part of the upgrade flow.

### Files

- `lib/brewmaster/profile.sh`
- `config/profiles.toml.example`
- `bin/brewmaster` — add `--profile` flag and `--interactive` flag

### Config Format

```toml
# ~/.config/brewmaster/profiles.toml

[profiles.work]
description = "Core dev tools"
include = ["node", "python@3.12", "git", "gh", "jq", "ripgrep"]

[profiles.personal]
description = "Everything allowed, minor and below"
include = []       # empty = all packages
level = "minor"

[profiles.safe]
description = "Low-risk upgrades only"
include = []
exclude = ["openssl", "curl"]
max_risk_score = 3
level = "patch"

[profiles.demo]
description = "Freeze before a client demo"
include = []
exclude = []
require_confirm = true
level = "patch"
```

### Function Contracts

```bash
profile_load "$name"
# Parse profiles.toml, set globals:
#   PROFILE_INCLUDE (array)
#   PROFILE_EXCLUDE (array)
#   PROFILE_REQUIRE_CONFIRM (bool)
#   PROFILE_MAX_RISK (int, default 10)
#   PROFILE_LEVEL (string, overrides --level if set)
# return 1 if profile not found

profile_list
# Print all profiles with descriptions

profile_filter_package "$pkg_name"
# return 0 if package is allowed under active profile
# return 1 if package should be skipped

profile_diff "$name_a" "$name_b"
# Show which packages would differ between two profiles

profile_create "$name"     # interactive wizard
profile_edit "$name"       # open profiles.toml in $EDITOR
profile_validate           # check TOML syntax, report errors
```

### Interactive Mode (`--interactive` / `-i`)

When `--interactive` flag is passed (requires `fzf`):

```
❯ brewmaster --profile=work -i

  [x] git          2.44.0 → 2.45.0   minor   risk:1
  [ ] node         20.0.0 → 22.0.0   major   risk:6
  [x] jq           1.6.0  → 1.7.0    minor   risk:0
  [ ] openssl      3.1.0  → 3.2.0    minor   risk:8

  tab: toggle · ctrl-a: select all · ctrl-d: deselect · enter: upgrade
```

- `fzf` is an optional dependency — if not installed, `--interactive` exits with a clear error message pointing to `brew install fzf`
- Preview pane shows: dependent list, risk score, last version bump date
- Selected packages are passed to the normal upgrade flow
- `DRY_RUN` is respected: if active, show plan after selection without executing

### CLI

```bash
brewmaster --profile=work --dry-run
brewmaster --profile=work --interactive
brewmaster --profile=safe --check-deps
brewmaster profile list
brewmaster profile create
brewmaster profile edit work
brewmaster profile diff work safe
brewmaster profile validate
```

### Acceptance Criteria

```bash
# Setup
cat > ~/.config/brewmaster/profiles.toml <<'EOF'
[profiles.test]
description = "Test profile"
include = ["git"]
EOF

brewmaster profile list
# → Shows "test" with description

brewmaster --profile=test --dry-run
# → Only git appears as upgrade candidate

brewmaster --profile=nonexistent
# → Error: "Profile 'nonexistent' not found in ~/.config/brewmaster/profiles.toml"

brewmaster --profile=work --interactive
# → fzf multi-select UI shown with risk scores visible
# → Only packages in work.include shown
```

---

## Milestone 4 — Cleanup & Intent

**Status:** `[x] done`
**Branch:** `feat/cleanup`
**Version:** `v0.5.0`
**Depends on:** M0, M1, M2, M3

### Scope

Answer the question no other tool asks: *"why is this package here, and do you still need it?"*

Identify orphan packages (nothing depends on them), stale packages (installed long ago, last-used heuristic suggests inactive), and old pinned versions — then clean up safely.

This milestone is brewmaster's primary market differentiator.

### Files

- `lib/brewmaster/cleanup.sh`
- `bin/brewmaster` — add `cleanup`, `why`, `bloat` subcommands

### Cleanup Categories

| Category | Definition |
|---|---|
| `orphan` | Package has zero dependents (`brew uses --installed` returns empty) AND was manually installed |
| `stale` | Not a dependency, no binary accessed in >90 days (heuristic via file atime/mtime) |
| `pinned-old` | A newer version is installed but an old pinned version remains |

> **Important:** All categories are heuristics. The user must always confirm before removal. Never auto-remove without explicit confirmation or `--force`.

### Function Contracts

```bash
cleanup_scan
# Scan all installed packages, classify into orphan/stale/pinned-old
# stdout: stream of "name|category|cleanup_score|reason"
# Calls depgraph_build (M2) internally — do not duplicate logic

cleanup_score "$package_name"
# Score 0–10 (higher = safer to remove):
#   +4 if orphan (no dependents)
#   +3 if not accessed in >90 days
#   +2 if has newer version installed
#   +1 if install date > 180 days ago
# stdout: integer 0–10

cleanup_execute "$package_name"
# Run: brew uninstall "$package_name"
# Respects $DRY_RUN
# return 0/1

cleanup_report
# Print categorized table with cleanup_score per package
# Format: CATEGORY | PACKAGE | INSTALLED | SCORE | REASON

why "$package_name"
# Explain why this package is on the machine:
#   - Who depends on it (from depgraph)
#   - When it was installed (brew info)
#   - Whether it was manually installed or pulled as a dependency
#   - Last known access (heuristic)
# stdout: human-readable explanation
```

### Interactive Mode (`--interactive` / `-i`)

When `--interactive` flag is passed (requires `fzf`):

```
❯ brewmaster cleanup -i

  [x] imagemagick    orphan    score:9   installed 8 months ago
  [x] watchman       stale     score:7   last used ~4 months ago
  [ ] openssl@1.1    pinned    score:5   openssl@3 already installed
  [ ] wget           orphan    score:4   installed 2 years ago

  tab: toggle · ctrl-a: select all · enter: remove selected
```

- Preview pane shows output of `why <package>` for highlighted item
- Auto-snapshot (M1) is triggered before any removal, unless snapshot already exists for today
- `DRY_RUN` respected: show plan after selection without executing

### CLI

```bash
brewmaster cleanup --dry-run           # scan + show candidates, no removal
brewmaster cleanup --interactive       # fzf selection UI
brewmaster cleanup --force             # remove all orphans with score >= 7, no confirm
brewmaster why <package>               # explain why this package is installed
brewmaster bloat                       # summary: total, orphans, stale, disk estimate
```

### Output Format (`brewmaster bloat`)

```
Machine package report
  Total installed:   147
  Orphans:            23   (could be removed)
  Stale (>90d):       11   (last-access heuristic)
  Pinned old:          4
  Est. disk reclaim: ~380 MB

Run: brewmaster cleanup --dry-run  to review candidates
```

### Acceptance Criteria

```bash
brewmaster why git
# → "git was installed manually on 2024-01-15. 3 packages depend on it: gh, delta, lazygit."

brewmaster bloat
# → Summary table with counts and disk estimate

brewmaster cleanup --dry-run
# → Categorized list, no packages removed

brewmaster cleanup --interactive
# → fzf UI shown, preview pane shows 'why' output
# → Auto-snapshot triggered before removal
# → Only selected packages removed
```

---

## Milestone 5 — Audit Log & Report

**Status:** `[ ] todo`
**Branch:** `feat/audit`
**Version:** `v0.6.0`
**Depends on:** M0, M1, M4

### Scope

Persistent, append-only log of all brewmaster actions: upgrades, cleanups, snapshots.
Machine health report in one command.

### Files

- Audit log: `~/.local/share/brewmaster/audit.log` (NDJSON)
- `bin/brewmaster` — add `log` and `report` subcommands

### Log Entry Format (NDJSON)

```json
{"ts":"2025-06-01T14:30:00Z","action":"upgrade","package":"git","old":"2.44.0","new":"2.45.0","bump":"minor","risk":1,"profile":"work","dry_run":false}
{"ts":"2025-06-01T14:31:00Z","action":"cleanup","package":"watchman","category":"stale","score":7,"dry_run":false}
{"ts":"2025-06-01T14:29:00Z","action":"snapshot","path":"~/.local/share/brewmaster/snapshots/20250601-143022.txt","label":""}
```

### Function Contracts

```bash
audit_append "$action" "$json_fields"
# Append one NDJSON line to audit.log
# Called internally after every upgrade, cleanup, snapshot action

audit_query [--package="git"] [--action="upgrade"] [--since="7d"] [--format=table|json|csv]
# Filter and display log entries
# Default format: table

audit_report
# Compute and display:
#   - Upgrades last 30/90 days (count by bump kind)
#   - Packages cleaned last 90 days
#   - Current orphan count
#   - Risk trend (avg risk score of recent upgrades)
#   - Snapshots count + oldest/newest
```

### CLI

```bash
brewmaster log                          # last 20 entries, table format
brewmaster log --package=git            # all entries for git
brewmaster log --action=cleanup --since=30d
brewmaster log --format=json            # pipe-friendly
brewmaster report                       # full machine health summary
```

### Report Output Format

```
brewmaster machine report  (as of 2025-06-01)
─────────────────────────────────────────────
Upgrades (30d):    12  (patch: 8  minor: 4  major: 0)
Cleanups (90d):     5  packages removed
Snapshots:          3  (oldest: 2025-04-10, latest: 2025-06-01)
Orphans now:       18  → run: brewmaster cleanup --dry-run
Avg risk score:   2.1  (last 10 upgrades)
```

### Acceptance Criteria

```bash
brewmaster log
# → Table of recent actions

brewmaster log --package=openssl --since=90d
# → Filtered entries for openssl in last 90 days

brewmaster report
# → Health summary matching format above
```

---

## Version Targets

| Version | Milestone |
|---|---|
| v0.1.0 | M0 — Refactor & Foundation |
| v0.2.0 | M1 — Snapshot & Rollback |
| v0.3.0 | M2 — Dependency Graph |
| v0.4.0 | M3 — Profile System |
| v0.5.0 | M4 — Cleanup & Intent |
| v0.6.0 | M5 — Audit Log & Report |

---

## Coding Conventions

> These apply to every file in every milestone. Read before writing any code.

1. Every public function must have a header comment: purpose, args, stdout, return code
2. Use `local` for all variables inside functions
3. No `set -e` inside functions — handle errors explicitly with `|| return 1`
4. `DRY_RUN` is a global boolean — always check before any destructive action
5. `VERBOSE` is a global boolean — use `logv()` from core for debug output
6. All user-facing paths use `${XDG_DATA_HOME:-$HOME/.local/share}/brewmaster/`
7. All config paths use `${XDG_CONFIG_HOME:-$HOME/.config}/brewmaster/`
8. `jq` is available — declared as hard dependency in formula
9. `fzf` is optional — always degrade gracefully with a clear install message
10. Test functions follow: `test_functionname_condition()` with simple assert helpers
11. Never auto-remove or auto-modify packages without explicit user confirmation or `--force`
12. Never add Co-authored-by or any AI tool attribution to commits

---

## Out of Scope (v1)

These were considered and explicitly deferred:

| Feature | Reason |
|---|---|
| Multi-driver (npm, pip, cargo) | Philosophy needs to mature at brew level first |
| Cross-machine sync | Doesn't fit personal tool philosophy |
| Plugin/hook system | Shell is already composable — not needed at this scale |
| Team/org policy enforcement | Out of solo-tool scope |

*Update milestone status from `[ ] todo` to `[x] done` when each milestone is complete.*