## Context

`_cleanup_last_access` (`lib/brewmaster/cleanup.sh:37-49`) calls
`brew list "$pkg"` per package to enumerate its installed files, filters
for `bin`/`sbin` paths, then stats their atimes; if none are found it falls
back to `brew --cellar "$pkg"` for the Cellar directory's mtime.
`cleanup_bloat` (`lib/brewmaster/cleanup.sh:341-379`) separately calls
`brew --cellar "$name"` per package to locate the Cellar directory for
`du -sk` disk-usage accounting. Both run inside `cleanup_scan`/
`cleanup_bloat`'s per-package walk loops, so each is a `brew` subprocess
(with Ruby/Formulary startup cost) repeated once per installed package.

This is the actual remaining per-package `brew`-call cost in the walk.
The dependency/reverse-dependency lookups (`brew deps`/`brew uses`) were
already collapsed into a single bulk call by `depgraph_build` in M2
(`lib/brewmaster/depgraph.sh:9-13`) — that work is done and out of scope
here.

## Goals / Non-Goals

**Goals:**
- Eliminate the per-package `brew list` call in `_cleanup_last_access`.
- Eliminate the per-package `brew --cellar` calls in both
  `_cleanup_last_access`'s fallback and `cleanup_bloat`.
- Keep `cleanup`, `bloat`, and `why` output byte-for-byte identical to
  today.

**Non-Goals:**
- No changes to `depgraph.sh` — its bulk deps/uses fetch is already
  correct (M2).
- No changes to `du -sk` per package in `cleanup_bloat` — it's a
  filesystem utility, not a `brew` subprocess, and far cheaper than the
  Ruby startup cost this change targets.
- No new CLI flags or config options.
- No change to risk scoring, cleanup categories, or output formatting.

## Decisions

- **Cache the Cellar root via `brew --cellar` (no package argument),
  once per invocation, in a global (`CELLAR_ROOT`).**
  A single call gives the Homebrew Cellar root (e.g.
  `/opt/homebrew/Cellar`); every package's Cellar directory is then just
  `$CELLAR_ROOT/$pkg`, needing zero further `brew` calls to resolve.

- **Replace `brew list "$pkg"` with a direct filesystem glob under
  `$CELLAR_ROOT/$pkg/*/bin/*` and `$CELLAR_ROOT/$pkg/*/sbin/*`.**
  `brew list <formula>` walks the same keg directory tree and prints the
  files bin/sbin are filtered from — this replaces a `brew` subprocess with
  a plain Bash glob, which is not just cheaper per call but removes the
  Ruby startup cost entirely rather than merely batching it. No bulk
  variant of `brew list` exists that preserves per-package grouping cheaply,
  so batching (as done for deps/uses in M2) isn't an option here; direct
  filesystem access is the available bulk-equivalent.

- **`_cleanup_cellar_root` is idempotent**, matching the existing
  `_cleanup_build`/`depgraph_build` no-op-if-cached pattern already used in
  this file, so it's safe to call from every entry point
  (`cleanup_scan`, `cleanup_main`, `cleanup_bloat`, `why`) without tracking
  call order between them.

## Risks / Trade-offs

- **[Risk]** Direct Cellar globbing might not match `brew list`'s output
  exactly for unusual installs (keg-only formulae, non-standard layouts).
  **Mitigation**: glob against all version directories under
  `$CELLAR_ROOT/$pkg/*`, matching what `brew list` walks; add fixture
  tests asserting last-access results are unchanged for representative
  packages.

- **[Risk]** A relocated or non-standard Homebrew prefix (e.g. Linuxbrew,
  custom `--prefix`) changes the Cellar root path.
  **Mitigation**: unaffected — `brew --cellar` is still the source of
  truth for the root path; it's just fetched once instead of once per
  package.

- **[Risk]** A caller reads `CELLAR_ROOT` before `_cleanup_cellar_root` has
  run. **Mitigation**: it's only read from `_cleanup_last_access` and
  `cleanup_bloat`, both of which are only reached via entry points that
  call `_cleanup_cellar_root` first.

## Migration Plan

No data migration — pure internal refactor, no on-disk format or CLI
surface change. Rollback is a plain revert; no version gating needed since
`cleanup`/`bloat` output is unchanged from the user's perspective.

## Open Questions

None blocking.
