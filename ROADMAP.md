# ROADMAP — brewmaster

> **For AI coding assistants (Claude Code and others):** M0–M5 is complete and frozen — see [`docs/ARCHIVE_ROADMAP.md`](docs/ARCHIVE_ROADMAP.md) for milestone history
> and frozen function contracts referenced by `tests/`.
> Do not invent new milestones or features —
> propose changes (as an issue, or a new section under "Upcoming Milestones" below)
> before implementing.
> Do not add Co-authored-by or any AI tool attribution to commits.

---

## Philosophy

> **brewmaster knows what's on your machine — and why.** Upgrade only what's deliberate. Keep only what's intentional.

M0–M5 built out this philosophy across five pillars:

| Question                         | Answered by           |
| -------------------------------- | --------------------- |
| Am I safe to proceed?            | M1 — Snapshot         |
| What's risky to upgrade?         | M2 — Dependency Graph |
| What should I upgrade right now? | M3 — Profile System   |
| What belongs on my machine?      | M4 — Cleanup & Intent |
| What happened over time?         | M5 — Audit Log        |

Any future feature should still answer one of these questions, or a new
question in the same spirit. If it doesn't, it's out of scope.

---

## Project Context

`brewmaster` is a CLI tool for selective package upgrades based on semver classification.
Core logic lives in `bin/brewmaster`, modularized across `lib/brewmaster/core/`.

**Stack:** Bash (POSIX-compatible where possible), `jq`, `curl`, `fzf` (optional)
**Target OS:** macOS (Homebrew)
**Distribution:** `brew tap pimlabs/brewmaster`

---

## Status

| Milestone                       | Version  | Status        |
| ------------------------------- | -------- | ------------- |
| M0 — Refactor & Foundation      | v0.1.0   | `[x] done`   |
| M1 — Snapshot & Rollback        | v0.2.0   | `[x] done`   |
| M2 — Dependency Graph Awareness | v0.3.0   | `[x] done`   |
| M3 — Profile System             | v0.4.0   | `[x] done`   |
| M4 — Cleanup & Intent           | v0.5.0   | `[x] done`   |
| M5 — Audit Log & Report         | v0.6.0   | `[x] done`   |
| M6 — Performance                | v0.7.0   | `[ ] next`   |
| M7 — Upgrade Checklist          | v0.8.0   | `[ ] planned` |
| M8 — Visual Polish              | v0.9.0   | `[ ] planned` |
| M9 — Manual & Help              | v0.10.0  | `[ ] planned` |

> Shell completions (bash/zsh) shipped as a patch in v0.6.1 — not a formal milestone.
> Full scope, function contracts, and acceptance criteria for M0–M5:
> see [`docs/ARCHIVE_ROADMAP.md`](docs/ARCHIVE_ROADMAP.md).

---

## Coding Conventions

> These apply to every file, every milestone. Read before writing any code.

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

## Out of Scope

These were considered and explicitly deferred:

| Feature                        | Reason                                                  |
| ------------------------------ | ------------------------------------------------------- |
| Multi-driver (npm, pip, cargo) | Philosophy needs to mature at brew level first          |
| Cross-machine sync             | Doesn't fit personal tool philosophy                    |
| Plugin/hook system             | Shell is already composable — not needed at this scale  |
| Team/org policy enforcement    | Out of solo-tool scope                                  |

---

## Upcoming Milestones

---

### Milestone 6 — Performance

**Status:** `[ ] next` **Branch:** `perf/cache-first` **Version:** `v0.7.0` **Depends on:** M0, M4

#### Scope

`cleanup` and `bloat` are slow on machines with large package lists because
dependency data is fetched per-package inside a serial loop. On a 400-package
machine this produces hundreds of redundant `brew` subprocess calls.

The fix: collect all dependency data in three bulk calls before any loop begins,
then let the loop parse strings from memory — no subprocesses inside the walk.

#### Files

- `lib/brewmaster/cleanup.sh` — refactor walk to consume cache
- `lib/brewmaster/core/cache.sh` — new: shared cache-build functions

#### Approach

```bash
# Before: N brew calls inside loop (slow)
for pkg in $(brew list); do
    brew deps "$pkg"          # called 400 times
    brew uses --installed "$pkg"  # called 400 times
done

# After: 3 calls total, loop only parses strings (fast)
DEPS_CACHE=$(brew deps --installed --for-each)
USES_CACHE=$(brew uses --installed --eval-all)
LIST_CACHE=$(brew list --installed)
for pkg in $LIST_CACHE; do
    # grep/awk from cache — no subprocess
done
```

#### Function Contracts

```
cache_build
# Populate globals: BM_DEPS_CACHE, BM_USES_CACHE, BM_LIST_CACHE
# Called once at start of cleanup/bloat — no-op if already populated
# stdout: nothing
# return 0

cache_deps_for "$package_name"
# Parse BM_DEPS_CACHE for a specific package
# stdout: newline-separated dependency list
# return 0

cache_uses_for "$package_name"
# Parse BM_USES_CACHE for a specific package
# stdout: newline-separated dependent list
# return 0
```

#### Tasks

- [ ] Create `lib/brewmaster/core/cache.sh` with `cache_build`, `cache_deps_for`, `cache_uses_for`
- [ ] Refactor `cleanup_scan` in `cleanup.sh` to call `cache_build` before walk loop
- [ ] Refactor `bloat` walk to consume cache, not subprocess
- [ ] Remove per-package `brew deps` and `brew uses` calls from all walk loops
- [ ] Add timing output under `VERBOSE` flag: `logv "[timing] cache built in Xs"`
- [ ] Update `tests/test_cleanup.sh` to cover cache-fed walk paths
- [ ] Verify `--dry-run` still works correctly post-refactor

#### Acceptance Criteria

```
brewmaster cleanup --dry-run   # completes in under 5 seconds on a 400-package machine
brewmaster bloat               # completes in under 5 seconds on a 400-package machine
# All existing tests pass without modification
```

---

### Milestone 7 — Upgrade Checklist

**Status:** `[ ] planned` **Branch:** `feat/checklist` **Version:** `v0.8.0` **Depends on:** M0, M2, M3

#### Scope

Current upgrade flow prompts confirmation per-package sequentially.
On a large upgrade batch the user cannot see the full picture before approving
individual items — one confirmation dialog at a time.

Replace with a single upfront checklist: show all candidates, let the user
review and deselect, then execute once.

#### Files

- `bin/brewmaster` — replace sequential confirm loop with checklist flow
- `lib/brewmaster/core/upgrade.sh` — add `upgrade_from_selection`
- `lib/brewmaster/checklist.sh` — new: checklist rendering and fzf integration

#### Function Contracts

```
checklist_build "$candidates"
# Build display list from upgrade candidates
# stdout: formatted rows "package | current | target | bump | risk"

checklist_select "$display_list"
# fzf multi-select — return selected package names
# Degrades gracefully without fzf: print table, single y/N prompt
# stdout: newline-separated selected package names

upgrade_from_selection "$selected_packages"
# Run upgrade loop on selected packages only
# Respects $DRY_RUN
```

#### Tasks

- [ ] Collect all upgrade candidates before any confirmation prompt
- [ ] Display full candidate table: package, current version, target version, semver bump, risk score
- [ ] `fzf` multi-select: user can deselect individual packages before confirming
- [ ] Non-interactive fallback: print table, single `y/N` to proceed with all
- [ ] `--yes` flag bypasses checklist entirely (existing behavior preserved)
- [ ] Snapshot taken automatically before any upgrade executes (existing behavior)
- [ ] Update `tests/test_cli.sh` to cover checklist flow and fallback path

#### Acceptance Criteria

```
brewmaster --dry-run          # shows full candidate table before any action
brewmaster --minor            # shows checklist, waits for confirm, then upgrades
brewmaster --minor --yes      # skips checklist, upgrades all (existing behavior)
# Fallback works correctly when fzf is not installed
```

---

### Milestone 8 — Visual Polish

**Status:** `[ ] planned` **Branch:** `feat/visual` **Version:** `v0.9.0` **Depends on:** M0, M4, M5, M6, M7

#### Scope

Output is functional but visually flat — no hierarchy, no color coding, no feedback
during long operations. Polish all command output to a consistent visual standard.

#### Files

- `lib/brewmaster/core/ui.sh` — new: color constants, spinner, aligned columns, section headers
- All existing command files — consume `ui.sh` helpers

#### Function Contracts

```
ui_color_init
# Set COLOR_OK, COLOR_WARN, COLOR_HIGH, COLOR_MUTED, COLOR_RESET
# Respect NO_COLOR env var; strip colors if stdout is not a TTY

ui_spinner_start "$label"   # start spinner in background
ui_spinner_stop             # stop spinner, clear line

ui_table_row "$col1" "$col2" ...   # print aligned row
ui_table_header "$col1" "$col2"    # print header row with separator

ui_section "$title"         # e.g. "── Cleanup Report ──────────"
ui_summary "$msg"           # consistent end-of-command summary line
```

#### Tasks

- [ ] Create `lib/brewmaster/core/ui.sh` with color constants and helpers
- [ ] Respect `NO_COLOR` env var — strip all colors when set
- [ ] Strip colors automatically when stdout is not a TTY (piped output stays clean)
- [ ] Risk score coloring consistent across all commands: LOW=green, MEDIUM=yellow, HIGH=red
- [ ] Progress indicator for long walks (`cleanup`, `bloat`, `deps show`) — spinner or `[N/total]`
- [ ] Aligned column output for all tabular data (upgrade list, snapshot list, log)
- [ ] Section headers consistent style: `── Section Title ──────────`
- [ ] Summary line at end of every command: counts, timing, next suggested action
- [ ] Update tests to strip color codes before assertion: `sed 's/\x1b\[[0-9;]*m//g'`

#### Acceptance Criteria

```
brewmaster cleanup            # color-coded risk levels, spinner during walk
brewmaster report             # aligned columns, section headers
brewmaster deps show openssl  # risk score highlighted by level
brewmaster report | grep done # clean plain text — no color bleed in pipes
# NO_COLOR=1 brewmaster cleanup  # no color codes in output
```

---

### Milestone 9 — Manual & Help

**Status:** `[ ] planned` **Branch:** `feat/manual` **Version:** `v0.10.0` **Depends on:** M0, M8

#### Scope

`brewmaster help` shows flags but not workflow. There is no `man` page.
After a break, there is no quick reference for commands and their behavior.

#### Files

- `docs/brewmaster.1` — new: troff man page (single source of truth)
- `bin/brewmaster` — replace flat `--help` with subcommand-level help
- `Formula/brewmaster.rb` — install man page to `man/man1/`

#### Tasks

- [ ] `brewmaster help [command]` — subcommand-level help: usage, flags, one example each
- [ ] Top-level `brewmaster help` shows command groups, not a flat flag dump
- [ ] `docs/brewmaster.1` — troff format, sections: NAME, SYNOPSIS, DESCRIPTION, COMMANDS, FILES, EXAMPLES
- [ ] Formula updated to install man page to correct `man/man1/` path
- [ ] `brewmaster --version` output includes build date
- [ ] No duplication between `--help` and man page — both derive from same source

#### Acceptance Criteria

```
brewmaster help cleanup       # shows purpose, all flags, one practical example
brewmaster help snapshot      # shows purpose, all flags, one practical example
man brewmaster                # renders correctly via man(1)
brewmaster --version          # prints version and build date
```