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
| M6 — Performance                | v0.10.0  | `[x] done`   |
| M7 — Upgrade Checklist          | v0.10.0  | `[x] done`   |
| M8 — Visual Polish              | v0.10.0  | `[x] done`   |
| M9 — Manual & Help              | v0.10.0  | `[x] done`   |
| M10 — Colorized Help            | v0.11.0  | `[x] done`   |
| M11 — Interactive Selection UX  | v0.12.0  | `[x] done`   |

> Shell completions (bash/zsh) shipped as a patch in v0.6.1 — not a formal milestone.
> M6–M9 shipped together in v0.10.0 (2026-08-11). The `(M6)`/`(M7)` labels on
> CHANGELOG's v0.7.0/v0.8.0 entries predate the current milestone numbering,
> and there was never a v0.9.0.
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

**Status:** `[x] done` **Branch:** `perf/cache-first` **Version:** `v0.10.0` **Depends on:** M0, M4

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

**Status:** `[x] done` **Branch:** `feat/checklist` **Version:** `v0.10.0` **Depends on:** M0, M2, M3

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

**Status:** `[x] done` **Branch:** `feat/visual` **Version:** `v0.10.0` **Depends on:** M0, M4, M5, M6, M7

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

**Status:** `[x] done` **Branch:** `feat/manual` **Version:** `v0.10.0` **Depends on:** M0, M8

#### Scope (as actually built — see below for how this differs from the original plan)

Before proposing, checked the real state instead of trusting the plan below:
top-level `--help` was already grouped by command area (M8's polish pass
had already left it that way), so "replace flat `--help`" was already
done. `docs/brewmaster.1` already existed too, but hand-written and stale
at v0.6.1, predating profiles/audit-log/cleanup. `Formula/brewmaster.rb`
doesn't exist in this repo at all — it lives in `pimlabs/homebrew-tap`,
confirmed via the GitHub API, and that formula already had
`man1.install "docs/brewmaster.1"`. So the Formula task was already done,
just not in a place this repo can touch or take credit for.

What was genuinely missing: `brewmaster help [command]` (per-command
detail didn't exist at all — `bin/brewmaster` said so explicitly), a
build date on `--version`, and a real single-source mechanism so
`--help`, `help <command>`, and the man page could never drift apart
again (the old man page already had, which is exactly the failure mode
"no duplication" was meant to prevent).

Extracted `usage()`'s heredoc verbatim into
`lib/brewmaster/core/help_data.sh`'s `_help_source_text()` — zero
behavior change, confirmed byte-identical against the existing `--help`
fixture before anything else was built on top of it. Three renderers now
read that one source: `usage()` (unchanged output), a new `help_command()`
that slices the same text by group for `brewmaster help <command>`, and a
new `docs/gen-man.sh` that walks the same line shapes and emits troff.
Added one worked example per command group that didn't already have one.
`docs/brewmaster.1` is now generated, not hand-maintained, and a test
diffs the generator's output against the committed file so the two can
never drift again. `--version` gained `BUILD_DATE`, a literal constant
bumped by hand alongside `BREWMASTER_VERSION` — deliberately not computed
from `git log` or file mtime, since an installed `brew`-built binary
carries neither a `.git` directory nor a trustworthy mtime.

A few things planned but not built, dropped once the actual repo
boundaries were in front of us:

- No `Formula/brewmaster.rb` changes — that file isn't in this repo, and
  the copy in `pimlabs/homebrew-tap` already installs the man page.
- No changes to `.github/workflows/release.yml`'s tap-update job — it
  already does the right thing for the formula it owns.
- No CI codegen job for the man page — this repo has no build step at
  all today (shell completions are hand-committed static files too), so
  a drift-check test riding the existing test suite was the
  proportionate enforcement, not a new CI job.

#### Original plan (superseded — kept for context, not what was built)

`brewmaster help` shows flags but not workflow. There is no `man` page.
After a break, there is no quick reference for commands and their behavior.

```
docs/brewmaster.1        # new: troff man page (single source of truth)
bin/brewmaster            # replace flat --help with subcommand-level help
Formula/brewmaster.rb     # install man page to man/man1/
```

Tasks as originally planned:

- `brewmaster help [command]` — subcommand-level help: usage, flags, one example each
- Top-level `brewmaster help` shows command groups, not a flat flag dump
- `docs/brewmaster.1` — troff format, sections: NAME, SYNOPSIS, DESCRIPTION, COMMANDS, FILES, EXAMPLES
- Formula updated to install man page to correct `man/man1/` path
- `brewmaster --version` output includes build date
- No duplication between `--help` and man page — both derive from same source

#### Files

- `lib/brewmaster/core/help_data.sh` — new: single source of truth for
  `--help`, `help <command>`, and the man page
- `bin/brewmaster` — `help` dispatch, `help_command()`, `BUILD_DATE`
- `docs/gen-man.sh` — new: troff generator, reads `help_data.sh` only
- `docs/brewmaster.1` — now generated, not hand-maintained
- `tests/test_docs.sh` — new: drift check between generator and committed man page

#### Acceptance Criteria (actual)

```
brewmaster help cleanup       # shows purpose, all flags, one practical example
brewmaster help snapshot      # shows purpose, all flags, one practical example
man ./docs/brewmaster.1       # renders correctly via man(1)
brewmaster --version          # prints version and build date
# All 8 test files pass (265 assertions); shellcheck clean on bin/brewmaster,
# lib/brewmaster/core/help_data.sh, and docs/gen-man.sh
```

See `openspec/changes/archive/2026-08-11-m9-manual-help/` for the full
proposal, design, specs, and tasks record.

---

### Milestone 10 — Colorized Help

**Status:** `[x] done` **Branch:** `feat/help-color` **Version:** `v0.11.0` **Depends on:** M8, M9

#### Scope (as actually built)

Built close to plan — the one open design question the scope note flagged
(reuse `ui.sh`'s semantic colors, or add dedicated ones) was resolved in
`design.md` before any code was written: two new decorative constants,
`COLOR_HEADER` (cyan, section headers) and `COLOR_COMMAND` (blue,
command/flag name-tokens), added to `ui_color_init` in `ui.sh` rather
than living locally in `bin/brewmaster` — one color surface for the whole
CLI, not a second parallel one. Deliberately distinct `tput setaf` codes
from `COLOR_OK`/`WARN`/`HIGH` (2/3/1) so help styling can never be
mistaken for a risk or status signal elsewhere in the same terminal
session.

`ui.sh` is now sourced (and `ui_color_init` called) early in
`bin/brewmaster`, right alongside `help_data.sh` — the exact same
early-sourcing fix M9 already established, needed again here since
`usage()`/`help_command()` can run before argument parsing (`-h`/`--help`,
the unknown-command path). `_help_style_desc`'s local dim variable was
retired in favor of `ui.sh`'s `COLOR_MUTED` (literally the same `tput dim`
sequence, one less duplicate).

One deliberate deviation from the original scope line "section headers,
command names, flags, **and placeholders**": placeholders
(`<package>`/`[options]`) stayed underline-only, no third color added.
Decided in `design.md` as restraint reading as more "modern" than a third
arbitrary hue, and confirmed by the `[y/N]`-review-free `AskUserQuestion`
this milestone otherwise didn't need — the maintainer never asked for
placeholders to be colored, just headers and commands.

`NO_COLOR`/non-TTY output confirmed byte-identical to the pre-change
`tests/fixtures/help.txt` throughout (diffed at every step, not just at
the end). TTY color output verified two ways: visually through a real
pty (`script -q /dev/null`) during implementation, and as a permanent
test (`tests/test_cli.sh` tests 19-20) using the same `script`-based pty
technique — `test_cli.sh` invokes `bin/brewmaster` as a subprocess, so
the sentinel-override-in-process pattern used by `test_depgraph.sh`/
`test_cleanup.sh` doesn't apply there; a real pty plus grepping for the
actual `tput setaf` sequences proves the same thing through a mechanism
that fits this file's existing subprocess-testing style.

#### Files

- `lib/brewmaster/core/ui.sh` — `COLOR_HEADER`/`COLOR_COMMAND` added to
  `ui_color_init`
- `bin/brewmaster` — `ui.sh` sourced early; `_help_style_vars`,
  `_help_style_name`, `_help_style_desc`, `_help_render_line` updated to
  apply the new colors and consume `COLOR_MUTED` instead of a local dim
  variable
- `tests/test_cli.sh` — 3 new assertions (TTY color presence via a real
  pty, decorative/semantic color-code distinctness)

#### Acceptance Criteria (actual)

```
brewmaster --help                 # section headers cyan, command/flag names blue, on a TTY
brewmaster help cleanup           # same, for a single command block
NO_COLOR=1 brewmaster --help      # byte-identical to tests/fixtures/help.txt
brewmaster --help | cat           # non-TTY: no color codes leak into pipes
# All 8 test files pass (268 assertions); shellcheck clean on bin/brewmaster
# and lib/brewmaster/**/*.sh
```

See `openspec/changes/archive/2026-08-11-m10-colorized-help/` for the
full proposal, design, specs, and tasks record.

---

### Milestone 11 — Interactive Selection UX

**Status:** `[x] done` **Branch:** `feat/interactive-select` **Version:** `v0.12.0` **Depends on:** M4, M7, M8

#### Scope (as actually built)

The `fzf` multi-select in `cleanup --interactive` (M4) and `upgrade`'s
review gate (M7) never matched the UI their own frozen design
documented: a bare `fzf --multi --ansi` with no `--bind`, no `--marker`,
no `--pointer`, no `--height`. Both headers advertised `ctrl-a: all`
while `ctrl-a` stayed on fzf's default `beginning-of-line`; Enter with
nothing marked upgraded exactly one package; and `upgrade` was opt-in
with `fzf` but opt-out (`Upgrade all? [y/N]`) without it.

Built as proposed: one shared picker, `ui_select "$preselect" "$prompt"
[extra fzf args...]` in `lib/brewmaster/core/ui.sh`, owns every `fzf`
option and generates its `--header` from the same key table as its
`--bind` string, so a key can only be advertised if it is bound — the
invariant the two hand-written headers lacked. `upgrade` calls it with
`preselect=all` (every candidate starts selected, Enter upgrades the
batch, matching the no-`fzf` `[y/N]`), `cleanup --interactive` with
`preselect=none` (removal stays explicit, convention 11). Preselect-all
rides on `fzf`'s `start:select-all` bind, gated by a one-time probe that
tests for exit **2** (option parse error) rather than any non-zero
status — measured on `fzf 0.44.1`, exit 1 is "no match" for the probe's
empty input and means the bind was accepted. The risk score `upgrade`
already carried in `upgrade_meta` is now a colored trailing column of
the candidate rows, which are built once through `ui_table_row` and
printed by all four consumers (`--dry-run` plan, no-`fzf` table, picker,
"Upgrading N package(s)" listing).

Deviations from the proposal, all recorded in `design.md`:

- **No-`fzf` fallback for `cleanup --interactive`: dropped** (maintainer,
  2026-09-06). The hard `exit 1` is the frozen M4 contract
  (`ARCHIVE_ROADMAP.md:370`, `test_cleanup.sh` test 24), and a single
  `[y/N]` over a whole removal batch is a coarser confirmation than
  per-item `fzf` selection for a destructive action.
- **Selection lookup is a newline-framed substring test, not an
  associative array.** Same effect (no subprocess per candidate); macOS's
  stock bash 3.2 has no associative arrays and nothing in the tree
  requires bash 4.
- **`enter:accept` is bound explicitly** so the header/bind invariant
  covers every key the header names, `enter` included; `accept` is
  `fzf`'s default for Enter, so behavior is unchanged.
- **Markers stay ASCII** (`--pointer='>' --marker='x'`): `✓`/`▸` parse
  fine on 0.44.1, so this is taste, not compatibility; flip in
  `ui_select` at no cost.
- Task 0.1 (confirm on macOS that `ctrl-a` was not select-all before)
  was superseded rather than run: `ui_select` binds `ctrl-a` explicitly,
  so the old default no longer matters.

`test_cli.sh`'s no-`fzf` cases used to hide `fzf` by trimming `PATH` to
`/usr/bin:/bin`, which only holds where no `fzf` lives there (Homebrew,
yes; Linux distros, no). They now hide it with an exported `command`
override, the mechanism the sourced test files already used. The
`CHANGELOG` entry lands with the version bump, as every release since
v0.10.0 has done it.

#### Files

- `lib/brewmaster/core/ui.sh` — `ui_select`, `_ui_fzf_supports_start`
- `lib/brewmaster/upgrade.sh` — review gate via `ui_select all`; rows
  built once through `ui_table_row`, risk column under `--check-deps`;
  selection filter without a subprocess per candidate
- `lib/brewmaster/cleanup.sh` — `--interactive` via `ui_select none`
- `lib/brewmaster/core/help_data.sh`, `docs/brewmaster.1`,
  `tests/fixtures/help.txt` — review-gate paragraph describes opt-out
- `tests/test_ui.sh` — new: 19 assertions on the assembled `fzf`
  invocation (header/bind invariant, marker ≠ pointer, inline height,
  preselect modes, probe cache and degradation, missing `fzf` returns 1)
- `tests/test_{audit,profile,cleanup}.sh` — `fzf` mocks record their
  argv; assert preselect-all for `upgrade`, none for `cleanup`
- `tests/test_cli.sh` — no-`fzf` isolation via exported `command`

#### Acceptance Criteria (actual)

```
# Every key named in the picker header is present in the --bind string, and vice versa (tests/test_ui.sh)
brewmaster --minor             # all candidates start selected; Enter upgrades the batch
brewmaster --minor --check-deps  # risk:N column per row in the picker and the tables
brewmaster cleanup -i          # nothing preselected; removal stays explicit; exit 1 without fzf (unchanged)
brewmaster --minor --dry-run   # unchanged: table, no gate, fzf never invoked
brewmaster --minor --yes       # unchanged: no gate
# All 9 test files pass (293 assertions); shellcheck clean on bin/brewmaster and lib/brewmaster/**/*.sh
```

See `openspec/changes/archive/2026-09-06-m11-interactive-select/` for the
full proposal, design, specs, and tasks record.

---
