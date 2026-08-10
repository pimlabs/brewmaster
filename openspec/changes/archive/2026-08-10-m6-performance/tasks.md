## 1. Cellar root cache

- [x] 1.1 Add `_cleanup_cellar_root` to `lib/brewmaster/cleanup.sh`: fetch
      `brew --cellar` once into a global (`CLEANUP_CELLAR_ROOT`), idempotent
      no-op if already set
- [x] 1.2 `_cleanup_cellar_root` emits `logv "[timing] ..."` when `VERBOSE`
      is set, and nothing when it isn't
- [x] 1.3 Call `_cleanup_cellar_root` from `cleanup_scan`, `cleanup_bloat`,
      and (via `bin/brewmaster`'s dispatch) `why` ahead of any per-package
      lookup; `_cleanup_last_access` also self-heals via an internal call
      for standalone use, matching `_cleanup_build`'s existing pattern

## 2. Remove per-package brew calls

- [x] 2.1 Refactor `_cleanup_last_access` to `find` under
      `$CLEANUP_CELLAR_ROOT/$pkg` for `bin`/`sbin` files instead of calling
      `brew list "$pkg"`
- [x] 2.2 Refactor `_cleanup_last_access`'s fallback to use
      `$CLEANUP_CELLAR_ROOT/$pkg` instead of calling `brew --cellar "$pkg"`
- [x] 2.3 Refactor `cleanup_bloat` to use `$CLEANUP_CELLAR_ROOT/$name`
      instead of calling `brew --cellar "$name"`
- [x] 2.4 Confirmed no remaining per-package `brew list "$.../brew --cellar
      "$...` calls
      (`grep -n 'brew list "\|brew --cellar "' lib/brewmaster/cleanup.sh`)

## 3. Tests

- [x] 3.1 Updated `tests/test_cleanup.sh` fixtures: real files under the
      fixture Cellar root (since `find` now hits the real filesystem), a
      mock for bare `brew --cellar`, and coverage for the no-bin/sbin-files
      fallback path (`nosuch`)
- [x] 3.2 Existing assertions (scores, categorization, `why`, `bloat`
      fields) continue to pass unchanged against the same fixture data,
      confirming output parity; added explicit assertions that no
      per-package `brew list`/`brew --cellar` calls occur and the Cellar
      root is fetched exactly once
- [x] 3.3 `--dry-run` behavior unchanged (`cleanup_main` default-path test
      still passes)
- [x] 3.4 Full test suite passes: audit 75, cleanup 45, cli 15, depgraph
      18, profile 45, semver 19, snapshot 19 — no regressions. `shellcheck`
      clean on `bin/brewmaster` and `lib/brewmaster/*.sh` (the CI-gated
      files)

## 4. Verification

- [x] 4.1 Measured on a real machine (403 installed formulae): `brew list
      <pkg>` ~0.5s/call vs the new `find`-based lookup ~0.017s/call, a
      ~29x per-lookup speedup — eliminates what would have been ~200s of
      `brew list` subprocess cost across a full `cleanup`/`bloat` walk
- [x] 4.2 `ROADMAP.md` M6 status and scope description updated to reflect
      the actual bottleneck fixed (Cellar-path lookups, not deps/uses —
      already solved in M2)
