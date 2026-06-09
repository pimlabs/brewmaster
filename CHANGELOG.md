# Changelog

All notable changes to brewmaster will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
brewmaster adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

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
