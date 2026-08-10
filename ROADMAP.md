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
| M6 — Performance                | v0.7.0   | `[x] done`   |
| M7 — Upgrade Checklist          | v0.8.0   | `[x] done`   |
| M8 — Visual Polish              | v0.9.0   | `[x] done`   |
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

**Status:** `[x] done` **Branch:** `perf/cache-first` **Version:** `v0.7.0` **Depends on:** M0, M4

#### Scope (as actually built — see below for how this differs from the original plan)

`cleanup` and `bloat` still called `brew list "$pkg"` and `brew --cellar
"$pkg"` once per installed package — `_cleanup_last_access` used
`brew list` to find a package's bin/sbin files for the last-access
heuristic, and `cleanup_bloat` used `brew --cellar` to locate each
package's Cellar directory for disk-size accounting. Each is a `brew`
subprocess with Ruby/Formulary startup cost, repeated per package
(measured ~0.5s/call on this machine).

The fix: fetch the Homebrew Cellar root path once (`brew --cellar`, no
argument) and derive every package's Cellar directory from it directly —
`_cleanup_last_access` now `find`s bin/sbin files under that path instead
of calling `brew list` (measured ~0.017s/call, a ~29x per-lookup speedup).

**This is not what the milestone originally planned to build** (see the
plan below, kept for context). The original plan assumed `brew deps`/
`brew uses` were still being called per-package — that was already fixed
in M2 (`depgraph_build`, a single bulk `brew info --json=v2` call). That
was caught while implementing this milestone's OpenSpec proposal
(`openspec/changes/m6-performance/`), before any code was written against
the stale premise, and the proposal was retargeted at the bottleneck that
actually still existed.

**The `<5s on a 400-package machine` target below was not fully met.**
The per-package `brew` subprocess cost this milestone targeted is gone,
but `cleanup_scan`'s per-package `jq` lookups (`_cleanup_formula_json`,
`_depgraph_query`, once each per package against the cached JSON) still
dominate — measured ~27s for 403 real installed packages. That's a
separate bottleneck, out of scope for this milestone (see design.md's
Non-Goals); a future milestone could batch those `jq` lookups the same
way M2/M6 batched the `brew` calls.

#### Original plan (superseded — kept for context, not what was built)

`cleanup` and `bloat` are slow on machines with large package lists because
dependency data is fetched per-package inside a serial loop. On a 400-package
machine this produces hundreds of redundant `brew` subprocess calls.

The fix: collect all dependency data in three bulk calls before any loop begins,
then let the loop parse strings from memory — no subprocesses inside the walk.

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

#### Files

- `lib/brewmaster/cleanup.sh` — added `_cleanup_cellar_root` (Cellar-root
  cache) and refactored `_cleanup_last_access`/`cleanup_bloat` to consume it
- `bin/brewmaster` — `why` dispatch pre-warms the Cellar-root cache
- `tests/test_cleanup.sh` — fixture updates + coverage for the new cache
  and the removal of per-package `brew` calls

#### Acceptance Criteria (actual)

```
# cleanup/bloat make zero per-package `brew list`/`brew --cellar` calls
# (see tests/test_cleanup.sh: no-per-package-brew-calls assertions)
# Cellar root fetched exactly once per test-suite run, not once per package
# All existing tests pass unmodified in behavior (same scores/categories)
# shellcheck clean on bin/brewmaster and lib/brewmaster/*.sh
```

See `openspec/changes/m6-performance/` (proposal, design, specs, tasks) for
the full record of what was proposed, what was found during implementation,
and why the scope changed.

---

### Milestone 7 — Upgrade Checklist

**Status:** `[x] done` **Branch:** `feat/checklist` **Version:** `v0.8.0` **Depends on:** M0, M2, M3

#### Scope (as actually built — see below for how this differs from the original plan)

`run_upgrade` already collected every candidate upfront (not a sequential
per-package prompt, as originally described) and already had an `fzf`
multi-select path — but only opt-in via `--interactive`/`-i`, and it
hard-`exit 1`'d if `fzf` wasn't installed. Without `-i`, upgrades executed
immediately with no confirmation at all.

**BREAKING**: the review step is now the default for every `upgrade`
invocation with candidates, not opt-in. `fzf` multi-select when
installed; a plain table + single `[y/N]` for the whole batch otherwise
(no more hard exit on missing `fzf`). `--yes` skips review entirely,
preserving the old "just run" behavior for scripts/automation —
unattended callers that don't pass `--yes` will now get prompted (and,
without a TTY/piped answer, will safely decline rather than upgrade).
`--dry-run` is unaffected: it still shows the full table and returns
before any review step, and no longer touches `fzf` at all even combined
with `--interactive` (which is now a no-op for `upgrade`).

This shape (review-by-default, `--yes` to opt out) was chosen to match
how `cleanup` already works in this codebase — default is look-before-you
-act — rather than the "opt-in checklist" the original plan described.
Confirmed with the user before writing the proposal.

One more originally-assumed "existing behavior" that turned out not to
exist: `run_upgrade` does not (and still does not, after this milestone)
take a snapshot before executing — only `cleanup_main` does that. Adding
snapshot-before-upgrade would be a separate, more involved change; out of
scope here.

#### Original plan (superseded — kept for context, not what was built)

Current upgrade flow prompts confirmation per-package sequentially.
On a large upgrade batch the user cannot see the full picture before approving
individual items — one confirmation dialog at a time.

Replace with a single upfront checklist: show all candidates, let the user
review and deselect, then execute once.

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

#### Files

- `lib/brewmaster/upgrade.sh` — `run_upgrade`'s review gate (fzf when
  available, plain table + `[y/N]` fallback otherwise), skipped by
  `--dry-run`/`--yes`
- `bin/brewmaster` — help text for `--interactive`/`-i` and `--yes`/`-y`
  under UPGRADE and PROFILES
- `tests/test_cli.sh`, `tests/test_audit.sh`, `tests/test_profile.sh` —
  updated/added coverage for the new default gate

#### Acceptance Criteria (actual)

```
brewmaster --dry-run          # shows full candidate table, no review gate, no fzf touched
brewmaster --minor            # shows review (fzf or table+[y/N]), waits, then upgrades
brewmaster --minor --yes      # skips review, upgrades all (preserves old default behavior)
# Fallback works correctly when fzf is not installed
```

See `openspec/changes/archive/` (once archived) for the full proposal,
design, specs, and tasks record, including what was found during
implementation and why the scope changed.

---

### Milestone 8 — Visual Polish

**Status:** `[x] done` **Branch:** `feat/visual` **Version:** `v0.9.0` **Depends on:** M0, M4, M5, M6, M7

#### Scope (as actually built — see below for how this differs from the original plan)

Progress indicators (`[N/total]`) and aligned tables already existed —
`cleanup.sh`, `upgrade.sh` had working progress lines, and `profile.sh`,
`audit.sh`, `depgraph.sh`, `cleanup.sh`, `snapshot.sh` each hand-rolled
their own aligned table header/rule/rows. `audit_report` already drew a
title-width `─────` rule. What was genuinely missing: any actual ANSI
color anywhere (risk/cleanup scores were plain numbers), and a shared
place for these patterns instead of five duplicated copies.

Built `lib/brewmaster/core/ui.sh` with `ui_color_init` (extends
`bin/brewmaster`'s existing `--help` `NO_COLOR`/non-TTY/no-`tput`
detection to real colors), `ui_table_header`/`ui_table_row` (width/value
pairs, not a fixed schema — five tables have five different shapes),
`ui_progress`/`ui_progress_clear` (extracted, not redesigned — no
spinner, `[N/total]` already worked), `ui_section`, `ui_summary`, and
`ui_colorize` (pads *before* coloring — `printf`'s `%-Ns` counts raw ANSI
bytes, so padding after coloring would misalign columns). Migrated all
six files. Colored dependency risk score (`deps show`, `upgrade` risk
warnings) and cleanup score (`cleanup`, `why` via `cleanup_report`) using
the thresholds already defined in `depgraph.sh`/`cleanup.sh` — note the
color *direction* is inverted between the two: a HIGH risk score is red
(dangerous to upgrade), a HIGH cleanup score is green (safer to remove).
Colored `snapshot diff`'s NEW/REMOVED/UPGRADE/DOWNGRADE tags too.

A few things planned but not built, found not to fit once the actual
code was in front of us:
- No spinner — `[N/total]` was already the working pattern, extracting
  it was the job, not replacing it.
- `run_upgrade`'s per-package `[i/total] ==> brew upgrade name` line
  ends with a real newline and stays as a permanent log entry, unlike
  the transient overwritten-in-place progress lines elsewhere — left it
  alone rather than forcing it into `ui_progress`.
- `why()` and `audit_report`'s metric block don't have a natural
  "section title" or "single closing line" to hang `ui_section`/
  `ui_summary` on — both are compact/multi-row output, not a table with
  a title. Left unchanged rather than adding a decoration that didn't
  read better.
- `snapshot_diff` never had a header row and mixes fixed decoration
  (`  ->  `, `[...]`) into its row format — didn't force it through
  `ui_table_row`, just colored the tag value directly.
- No test needed `sed`-based ANSI stripping in practice: `ui_color_init`
  checks `[ -t 1 ]`, and a `$(...)` command substitution is never a TTY,
  so every existing test's captured output was already colorless for
  free. Only the handful of tests written specifically to check color
  *selection* logic needed anything extra (sentinel color overrides).

#### Original plan (superseded — kept for context, not what was built)

Output is functional but visually flat — no hierarchy, no color coding, no feedback
during long operations. Polish all command output to a consistent visual standard.

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

#### Files

- `lib/brewmaster/core/ui.sh` — color constants, table rendering,
  progress line, section header, summary line, `ui_colorize`
- `lib/brewmaster/{profile,audit,depgraph,cleanup,upgrade,snapshot}.sh` —
  migrated to consume `ui.sh`
- `bin/brewmaster` — sources `core/ui.sh`, calls `ui_color_init` once

#### Acceptance Criteria (actual)

```
brewmaster cleanup            # color-coded cleanup score, [N/total] during walk
brewmaster report             # aligned table, section-headed title
brewmaster deps show openssl  # risk score highlighted by level (inverted direction from cleanup)
brewmaster report | grep done # clean plain text — no color bleed in pipes
NO_COLOR=1 brewmaster cleanup # no color codes in output
# All 7 test files pass (256 assertions); shellcheck clean on bin/brewmaster and lib/brewmaster/**/*.sh
```

See `openspec/changes/archive/` (once archived) for the full proposal,
design, specs, and tasks record.

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