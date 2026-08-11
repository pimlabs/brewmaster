# Changelog

All notable changes to brewmaster will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
brewmaster adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.10.0] — 2026-08-11

### Added

- `brewmaster help [command]` — per-command usage, flags, and one worked
  example, sourced from a single shared table
  (`lib/brewmaster/core/help_data.sh`) that also drives the existing
  top-level `--help` output, so the two can never drift apart
- `docs/gen-man.sh` — generates `docs/brewmaster.1` from that same shared
  table; a test diffs the generator's output against the committed man
  page so it can never go stale again (the previous hand-written page had
  drifted, missing profiles, audit log/report, and cleanup entirely)
- `brewmaster --version`/`-V` now includes a build date:
  `brewmaster <version> (built <date>)`
- Upgrade candidates are now always reviewed before executing — fzf
  multi-select if installed, otherwise a table plus a single `[y/N]` for
  the batch; `--dry-run` and `--yes` both skip the review
- Color-coded output via `lib/brewmaster/core/ui.sh`: dependency risk
  score and cleanup score are highlighted by level (opposite color
  directions — high risk is red/dangerous, high cleanup score is
  green/safe to remove), `snapshot diff` tags (NEW/REMOVED/UPGRADE/
  DOWNGRADE) are colored, respects `NO_COLOR` and non-TTY output

### Changed

- `cleanup`/`bloat`/`why` no longer call `brew list`/`brew --cellar` once
  per installed package — the Cellar root is fetched once and package
  paths are derived from it directly (measured ~29x per-lookup speedup)
- `--interactive`/`-i` is now a no-op on `upgrade` (kept for backward
  compatibility) since candidate review happens by default; `--yes`/`-y`
  skips it
- All five existing ad-hoc table/progress-line implementations
  (`profile`, `audit`, `depgraph`, `cleanup`, `snapshot`) migrated to the
  shared `ui.sh` helpers instead of five hand-rolled copies

## [0.8.1] — 2026-06-14

### Changed

- `--help` output now uses bold/underline/dim styling (via `tput`) for
  section headers, command/flag names, and placeholders, with secondary
  `(default: ...)`/`(also: ...)`/`(requires fzf)` annotations dimmed —
  degrades to byte-identical plain text when `NO_COLOR` is set, stdout is
  not a TTY, or `tput` is unavailable

## [0.8.0] — 2026-06-14

### Added (M7)

- `run_upgrade` now prints a `[i/total]` progress counter for each package,
  matching the `\r\033[K` pattern already used in `cleanup_scan`
- Shell completions for bash, zsh, and fish (`completions/brewmaster.{bash,zsh,fish}`)
  — covers every subcommand, sub-subcommand, and flag, with dynamic completion
  for package names, profile names, and enum-valued flags (`--level`,
  `--action`, `--format`)
- `docs/brewmaster.1` man page, reusing the wording from `bin/brewmaster`'s
  `--help` output for COMMANDS, OPTIONS, and NOTES

### Changed (M7)

- Replaced `"${arr[@]:-}"` empty-array workarounds with
  `(( ${#arr[@]} == 0 ))` length checks in `upgrade.sh` and `profile.sh`
- Audited all `|| return 1` error paths in `semver.sh` and `audit.sh` —
  confirmed every one prints or propagates an error message

## [0.7.0] — 2026-06-14

### Fixed (M6)

- `snapshot_diff`/`snapshot_restore`: scratch tmpfile is now removed on all
  exit paths via a `RETURN` trap, not just the normal fall-through path
- `cleanup_bloat`: fixed a variable shadowing bug where the scan row count
  overwrote the total installed package count
- `_cleanup_last_access`: replaced per-formula `brew list` calls inside the
  scan loop with a single upfront file map (O(n) → O(1) brew invocations)

### Changed (M6)

- `snapshot_restore` now documents the versioned-install limitation up front:
  entries with no matching `brew info pkg@version` are flagged
  `[likely unsupported]` in the restore plan (including under `--dry-run`),
  and failures get a specific warning instead of a generic one
- `lib/brewmaster/core/upgrade.sh` moved to `lib/brewmaster/upgrade.sh` —
  `run_upgrade` performs brew invocations and interactive I/O, which doesn't
  belong in the pure-function `core/` convention

## [0.6.1] — 2026-06-11

### Changed

- Restructured `--help` output: each command is now grouped with the flags
  that apply to it (UPGRADE, DEPENDENCY RISK, SNAPSHOT & ROLLBACK, PROFILES,
  CLEANUP & INTENT, AUDIT LOG & REPORTS, GENERAL), instead of separate
  Commands/Options sections
- Clarified in `--help` notes: `--level=X` vs `--patch/--minor/--major` are
  equivalent, `--force` means different things per command, and risk score
  vs cleanup score are opposite-direction 0-10 scales
- Added a "Commands at a Glance" index table to README.md

## [0.6.0] — 2026-06-11

### Added (M5)

- Persistent NDJSON audit log at `~/.local/share/brewmaster/audit.log` (`XDG_DATA_HOME` respected) — one record per upgrade, cleanup, and snapshot action
- `brewmaster log [--package=NAME] [--action=upgrade|cleanup|snapshot] [--since=Nd|Nh|Nw] [--format=table|json|csv]` — query the audit log; defaults to the last 20 entries (table format), no cap when any filter is set
- `brewmaster report` — machine health summary: upgrades (30d) by bump type, cleanups (90d), snapshot count/oldest/latest, current orphan count, and average risk score over the last 10 upgrades
- `upgrade`/`cleanup`/`snapshot` actions are logged only on real (non-dry-run) execution; upgrade entries include a `risk` field when `--check-deps` was used
- `tests/test_audit.sh` — 75 assertions covering append/query/report and integration with snapshot, cleanup, and upgrade

## [0.5.0] — 2026-06-10

### Added (M4)

- `brewmaster cleanup` — report orphan/stale/pinned-old formulae with a 0–10 removability score (read-only by default, same as `--dry-run`)
- `--interactive` / `-i` for `cleanup` — fzf multi-select packages to remove, with a `why`-based preview pane
- `--force` for `cleanup` — auto-remove `orphan` candidates with score ≥ 7
- `brewmaster why <package>` — explain why a formula is installed: manual vs. dependency, install date, dependents, last-access heuristic, extra versions
- `brewmaster bloat` — machine package summary: totals, category counts, estimated disk reclaim from cleanup candidates
- Auto-snapshot ("pre-cleanup") before any `cleanup` removal, unless one already exists for today
- `tests/test_cleanup.sh` — 42 scoring, scanning, reporting, and removal-flow assertions
- Scope: formulae only (`brew uses`/`brew leaves` don't apply meaningfully to casks); `bloat`'s totals include casks, but categorization and removal do not

## [0.4.0] — 2026-06-10

### Added (M3)

- `--profile=NAME`: filter packages and override the bump level from a named profile
- `--interactive` / `-i`: fzf multi-select among upgrade candidates (requires `fzf`; exits with an install hint if missing)
- `brewmaster profile list` — show all configured profiles with descriptions
- `brewmaster profile create` — interactive wizard to add a new profile
- `brewmaster profile edit [name]` — open `profiles.toml` in `$EDITOR`
- `brewmaster profile diff <a> <b>` — compare include lists between two profiles
- `brewmaster profile validate` — check `profiles.toml` for duplicate sections and invalid values
- TOML config at `~/.config/brewmaster/profiles.toml` (`XDG_CONFIG_HOME` respected); example at `config/profiles.toml.example`
- Profile fields: `include`, `exclude`, `level`, `max_risk_score`, `require_confirm`
- `tests/test_profile.sh` — 45 profile function and upgrade-flow assertions

## [0.3.0] — 2026-06-09

### Added (M2)

- `--check-deps`: risk-score each upgrade candidate using `brew uses`; skip HIGH-risk (score ≥ threshold), warn + prompt on MEDIUM (score 4–6)
- `--risk-threshold=N` (default 7): configurable HIGH-risk cutoff
- `--yes` / `-y`: auto-confirm MEDIUM-risk packages without prompting
- `brewmaster deps show [package]`: show dependency risk report for one package; without arg, lists all outdated packages sorted by risk score (highest first)
- `tests/test_depgraph.sh` — 18 depgraph function and upgrade-flow tests

### Added (M1)

- `snapshot save [--label=TEXT]` — save current Homebrew state (`brew list --versions`) to a timestamped file
- `snapshot list` — show all saved snapshots with index, timestamp, label, and package count
- `snapshot diff [INDEX|PATH]` — show packages that changed (UPGRADE / DOWNGRADE / NEW / REMOVED) since a snapshot
- `snapshot restore [INDEX|PATH] [--dry-run]` — reinstall packages from a snapshot; respects `--dry-run`
- `snapshot delete [INDEX|PATH] [--force]` — delete a snapshot file pair, with interactive confirmation unless `--force`
- Snapshots stored in `${XDG_DATA_HOME:-~/.local/share}/brewmaster/snapshots/` as `.txt` + `.meta.json` pairs
- `tests/test_snapshot.sh` — 19 snapshot function tests using a mock brew

### Added

- Initial project structure
- Core semver logic: `to_semver_3`, `bump_kind`, `allow_by_level`
- Outdated package parser: `parse_outdated_line`
- CLI entry point with flags: `--level`, `--or-lower`, `--dry-run`, `--formulae`, `--casks`, `--verbose`
- Unit tests for the semver core (`tests/test_semver.sh`)

### Changed

- Split the monolithic `brew-upgrade.sh` into `bin/brewmaster` plus `lib/brewmaster/core/{semver,outdated,upgrade}.sh`
- Standardized all user-facing text and comments to English
- `--allow-date` is now opt-in (default off); date versions are skipped unless requested
- `--formulae` and `--casks` are now mutually exclusive (error if combined)
- Cask detection caches the installed cask list once instead of querying per package
- Report the number of packages skipped due to non-semver versions
- `to_semver_3` takes `allow_date` as an explicit argument instead of a hidden global
- `parse_outdated_line` outputs `name|old|new` (dropped unused `op` field) to match the Milestone 5 driver contract
- Added `--version`/`-V`, a space form for `--level` (e.g. `--level minor`) with validation, and an explicit `upgrade` subcommand (default action)
- Level can be selected with `--patch`/`--minor`/`--major` (mutually exclusive); `--level=` remains an alias
- `upgrade` accepts positional package names to limit the run (e.g. `brewmaster upgrade git node --minor`)
- **Changed the default bump level from `minor` to `patch`** — the most conservative default, so a bare `brewmaster upgrade` no longer skips patch/security fixes
- CLI behavior tests (`tests/test_cli.sh`) covering level flags, the package filter, and exit codes

---

<!-- Add new versions above this line using the format below -->

<!--
## [X.Y.Z] — YYYY-MM-DD

### Added
- 

### Changed
- 

### Fixed
- 

### Removed
- 

### Breaking Changes
- 
-->
