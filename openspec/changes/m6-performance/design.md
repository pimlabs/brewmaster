## Context

`cleanup_scan` (`lib/brewmaster/cleanup.sh`) and the `bloat` walk iterate over
every installed package and, for each one, shell out to `brew deps "$pkg"`
and `brew uses --installed "$pkg"`. Each `brew` invocation pays Ruby's
startup cost independently of the actual work done, so on a ~400-package
machine the walk makes ~800 subprocess calls before it can even start
scoring risk. `brew` already exposes bulk equivalents
(`brew deps --installed --for-each`, `brew uses --installed --eval-all`)
that return the same data for every installed package in one call.

## Goals / Non-Goals

**Goals:**
- Replace per-package `brew deps` / `brew uses` calls in the `cleanup` and
  `bloat` walks with three bulk calls (deps, uses, list) executed once per
  command invocation.
- Keep `cleanup` and `bloat` output, flags, and `--dry-run` behavior
  byte-for-byte identical to today — this is an internal data-fetch change,
  not a behavior change.
- Surface cache-build cost via `logv` when `VERBOSE` is set.

**Non-Goals:**
- No new CLI flags or config options.
- No change to risk scoring, cleanup categories, or `bloat` output format
  (covered by existing, frozen M2/M4 contracts).
- No caching for `upgrade`, `profile`, or `snapshot` walks — only `cleanup`
  and `bloat` consume the cache in this milestone. Extending it further is a
  separate proposal if warranted.
- No on-disk/persistent cache — the cache lives only for the lifetime of a
  single command invocation.

## Decisions

- **Bulk fetch via `brew deps --installed --for-each` and
  `brew uses --installed --eval-all`, not N parallelized calls.**
  Alternatives considered: running the existing per-package calls in
  parallel (`xargs -P`) would cut wall-clock time but still pays N times the
  Ruby startup cost and adds complexity around output interleaving. Bulk
  calls pay that cost exactly once.

- **Cache stored in global bash variables (`BM_DEPS_CACHE`, `BM_USES_CACHE`,
  `BM_LIST_CACHE`), parsed on lookup with `grep`/`awk`.**
  Consistent with the existing global-boolean convention (`DRY_RUN`,
  `VERBOSE`) already used across the codebase. Avoids introducing associative
  arrays, which vary in behavior across the Bash versions brewmaster targets.

- **`cache_build` is idempotent: no-op if the cache is already populated.**
  `cleanup_scan` and the `bloat` walk both need the same data; making
  `cache_build` safe to call from either entry point (or both, if `bloat`
  ever calls into `cleanup_scan`) avoids callers having to track whether the
  cache was already built.

- **Cache scope is a single command invocation, not persisted to disk.**
  Package state can change between runs (installs, upgrades, removals), and
  a stale on-disk cache would silently produce wrong risk data. Rebuilding
  per invocation costs three `brew` calls, which is already the whole point
  of this change — there's no correctness/performance tradeoff to make here.

## Risks / Trade-offs

- **[Risk]** `brew`'s bulk-output format for `--for-each` / `--eval-all`
  differs across Homebrew versions → cache parsing breaks silently.
  **Mitigation**: add fixture-based tests in `tests/test_cleanup.sh` against
  captured real `brew` output; fail loudly (non-zero return) if expected
  markers are absent from the bulk output rather than silently returning
  empty results.

- **[Risk]** The three bulk calls are themselves slower on very large
  installs than a handful of per-package calls would be on a small install.
  **Mitigation**: bulk cost is O(1) in call count regardless of package
  count, so it strictly dominates the old O(N) approach past a small
  package count; acceptable for brewmaster's target machines (tens to
  hundreds of packages).

- **[Risk]** A caller reads `BM_DEPS_CACHE`/`BM_USES_CACHE` before
  `cache_build` has run. **Mitigation**: `cache_deps_for`/`cache_uses_for`
  are only ever called from within `cleanup_scan`/`bloat`, which call
  `cache_build` first; no public entry point bypasses that ordering.

## Migration Plan

No data migration — this is a pure internal refactor with no on-disk format
or CLI surface change. Roll out as a normal patch to `cleanup.sh` plus the
new `core/cache.sh`. Rollback is a plain revert; no version gating needed
since `cleanup`/`bloat` behavior is unchanged from the user's perspective.

## Open Questions

None blocking. Whether to extend the cache to `upgrade`/`profile` walks is
left for a future milestone if their walks turn out to have the same
per-package subprocess cost.
