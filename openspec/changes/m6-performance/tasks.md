## 1. Cellar root cache

- [ ] 1.1 Add `_cleanup_cellar_root` to `lib/brewmaster/cleanup.sh`: fetch
      `brew --cellar` once into a global (`CELLAR_ROOT`), idempotent no-op
      if already set
- [ ] 1.2 `_cleanup_cellar_root` emits `logv "[timing] ..."` when `VERBOSE`
      is set, and nothing when it isn't
- [ ] 1.3 Call `_cleanup_cellar_root` from `cleanup_scan`, `cleanup_main`,
      `cleanup_bloat`, and `why` ahead of any per-package lookup

## 2. Remove per-package brew calls

- [ ] 2.1 Refactor `_cleanup_last_access` to glob
      `$CELLAR_ROOT/$pkg/*/bin/*` and `$CELLAR_ROOT/$pkg/*/sbin/*` instead
      of calling `brew list "$pkg"`
- [ ] 2.2 Refactor `_cleanup_last_access`'s fallback to use
      `$CELLAR_ROOT/$pkg` instead of calling `brew --cellar "$pkg"`
- [ ] 2.3 Refactor `cleanup_bloat` to use `$CELLAR_ROOT/$name` instead of
      calling `brew --cellar "$name"`
- [ ] 2.4 Confirm no remaining per-package `brew list "$.../brew --cellar
      "$...` calls
      (`grep -n 'brew list "\|brew --cellar "' lib/brewmaster/cleanup.sh`)

## 3. Tests

- [ ] 3.1 Add/update `tests/test_cleanup.sh` fixtures covering
      `_cleanup_cellar_root` and the glob-based `_cleanup_last_access`
      lookup (including the no-bin/sbin-files fallback path)
- [ ] 3.2 Add a test asserting `cleanup`/`bloat`/`why` output is unchanged
      before/after the refactor for the same fixture package state
- [ ] 3.3 Verify `--dry-run` still behaves correctly post-refactor
- [ ] 3.4 Run full existing test suite and confirm no regressions

## 4. Verification

- [ ] 4.1 Manually time `brewmaster cleanup --dry-run` and `brewmaster
      bloat` on a real machine, confirm a measurable speedup versus the
      pre-refactor version
- [ ] 4.2 Update `ROADMAP.md` M6 status to `[x] done` once merged, and
      correct M6's scope description so it reflects the actual bottleneck
      fixed (Cellar-path lookups, not deps/uses — already solved in M2)
