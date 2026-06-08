# Changelog

All notable changes to brewmaster will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
brewmaster adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

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
