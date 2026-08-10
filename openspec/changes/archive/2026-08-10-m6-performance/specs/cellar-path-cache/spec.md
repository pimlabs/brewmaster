## ADDED Requirements

### Requirement: Cellar root cache

`_cleanup_cellar_root` SHALL fetch the Homebrew Cellar root path via
`brew --cellar` (no package argument) exactly once per command invocation
and cache it in a global variable. It SHALL be a no-op if the cache is
already populated. When `VERBOSE` is set, it SHALL emit a timing line via
`logv` after the call completes; when `VERBOSE` is unset, no such line
SHALL be printed.

#### Scenario: First call fetches the Cellar root
- **WHEN** `_cleanup_cellar_root` is called and the cache is unset
- **THEN** it runs `brew --cellar` once and stores the result in
  `CLEANUP_CELLAR_ROOT`

#### Scenario: Repeated call in the same invocation is a no-op
- **WHEN** `_cleanup_cellar_root` is called and `CLEANUP_CELLAR_ROOT` is
  already set
- **THEN** it returns immediately without invoking `brew` again

#### Scenario: VERBOSE enabled shows timing
- **WHEN** `VERBOSE=1` and `_cleanup_cellar_root` runs
- **THEN** output includes a `logv` line reporting the Cellar-root fetch
  time

#### Scenario: VERBOSE disabled shows no timing
- **WHEN** `VERBOSE` is unset and `_cleanup_cellar_root` runs
- **THEN** no timing line is printed

### Requirement: Last-access lookup avoids per-package brew calls

`_cleanup_last_access` SHALL locate a package's bin/sbin files by globbing
under the cached Cellar root instead of calling `brew list "$pkg"`, and
SHALL fall back to the cached Cellar root (instead of calling
`brew --cellar "$pkg"`) when no bin/sbin files are found.

#### Scenario: Package with bin/sbin files
- **WHEN** `_cleanup_last_access` is called for an installed package that
  has bin/sbin files
- **THEN** it returns the same max-atime result as the pre-refactor
  implementation, without invoking `brew list`

#### Scenario: Package with no bin/sbin files falls back to Cellar mtime
- **WHEN** `_cleanup_last_access` is called for a package with no bin/sbin
  files
- **THEN** it returns the Cellar directory's mtime derived from
  `CLEANUP_CELLAR_ROOT`, without invoking `brew --cellar` for that package

### Requirement: bloat walk avoids per-package brew --cellar calls

`cleanup_bloat` SHALL derive each package's Cellar directory from the
cached Cellar root instead of calling `brew --cellar "$name"` per package.

#### Scenario: bloat computes disk usage without per-package brew calls
- **WHEN** `brewmaster bloat` runs on a machine with N installed packages
- **THEN** it invokes `brew --cellar` a total of one time, not N times

### Requirement: Output parity

Output of `cleanup`, `bloat`, and `why` SHALL be identical before and after
this change for the same installed-package state.

#### Scenario: cleanup output unchanged
- **WHEN** `brewmaster cleanup --dry-run` runs against the same
  installed-package state before and after this change
- **THEN** the printed rows (category, package, score, reason) are
  identical

#### Scenario: bloat output unchanged
- **WHEN** `brewmaster bloat` runs against the same installed-package
  state before and after this change
- **THEN** totals and estimated disk reclaim are identical
