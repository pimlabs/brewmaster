## ADDED Requirements

### Requirement: Bulk cache build
`cache_build` SHALL populate `BM_DEPS_CACHE`, `BM_USES_CACHE`, and
`BM_LIST_CACHE` using exactly three `brew` calls total
(`brew deps --installed --for-each`, `brew uses --installed --eval-all`,
`brew list --installed`), regardless of how many packages are installed.
It SHALL be a no-op if the cache is already populated in the current
process.

#### Scenario: First call builds the cache
- **WHEN** `cache_build` is called and `BM_DEPS_CACHE` is unset
- **THEN** it runs the three bulk `brew` calls and populates
  `BM_DEPS_CACHE`, `BM_USES_CACHE`, and `BM_LIST_CACHE`

#### Scenario: Repeated call in the same invocation is a no-op
- **WHEN** `cache_build` is called and the cache globals are already
  populated
- **THEN** it returns immediately without invoking `brew` again

### Requirement: Per-package dependency lookup from cache
`cache_deps_for "$package_name"` SHALL return the newline-separated
dependency list for the given package by parsing `BM_DEPS_CACHE`, without
invoking `brew`.

#### Scenario: Lookup for a package with dependencies
- **WHEN** `cache_deps_for` is called with a package present in
  `BM_DEPS_CACHE`
- **THEN** it prints that package's dependencies, one per line, with no
  `brew` subprocess invoked

#### Scenario: Lookup for a package with no dependencies
- **WHEN** `cache_deps_for` is called with a package that has no
  dependencies
- **THEN** it prints nothing and returns 0

### Requirement: Per-package reverse-dependency lookup from cache
`cache_uses_for "$package_name"` SHALL return the newline-separated list of
installed packages that depend on the given package by parsing
`BM_USES_CACHE`, without invoking `brew`.

#### Scenario: Lookup for a package used by others
- **WHEN** `cache_uses_for` is called with a package present in
  `BM_USES_CACHE`
- **THEN** it prints the dependent package names, one per line, with no
  `brew` subprocess invoked

#### Scenario: Lookup for a package used by nothing
- **WHEN** `cache_uses_for` is called with a package no other installed
  package depends on
- **THEN** it prints nothing and returns 0

### Requirement: cleanup and bloat walks consume the cache
`cleanup_scan` and the `bloat` walk SHALL call `cache_build` once before
their per-package loop and SHALL use `cache_deps_for`/`cache_uses_for`
inside the loop instead of calling `brew deps`/`brew uses` per package.

#### Scenario: cleanup --dry-run makes no per-package brew calls
- **WHEN** `brewmaster cleanup --dry-run` runs on a machine with N
  installed packages
- **THEN** it invokes `brew deps`/`brew uses` a total of one time each
  (via the bulk cache build), not N times each

#### Scenario: bloat makes no per-package brew calls
- **WHEN** `brewmaster bloat` runs
- **THEN** it invokes `brew deps`/`brew uses` a total of one time each,
  not once per package

#### Scenario: Output is unchanged from the pre-cache implementation
- **WHEN** `cleanup` or `bloat` runs against the same installed-package
  state before and after this change
- **THEN** the printed output (package lists, risk levels, cleanup
  categories) is identical

### Requirement: Cache-build timing under VERBOSE
When `VERBOSE` is set, `cache_build` SHALL emit a timing line via `logv` in
the form `[timing] cache built in Xs` after the bulk calls complete. When
`VERBOSE` is unset, no such line SHALL be printed.

#### Scenario: VERBOSE enabled shows timing
- **WHEN** `VERBOSE=1` and `cache_build` runs
- **THEN** stdout/stderr includes a line matching
  `[timing] cache built in `

#### Scenario: VERBOSE disabled shows no timing
- **WHEN** `VERBOSE` is unset and `cache_build` runs
- **THEN** no `[timing]` line is printed
