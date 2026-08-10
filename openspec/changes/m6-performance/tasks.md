## 1. Cache module

- [ ] 1.1 Create `lib/brewmaster/core/cache.sh` with `cache_build`,
      `cache_deps_for`, `cache_uses_for` per the function contracts in
      `ROADMAP.md` / `design.md`
- [ ] 1.2 `cache_build` runs the three bulk `brew` calls (`brew deps
      --installed --for-each`, `brew uses --installed --eval-all`,
      `brew list --installed`) and populates `BM_DEPS_CACHE`,
      `BM_USES_CACHE`, `BM_LIST_CACHE`
- [ ] 1.3 `cache_build` is a no-op if the cache globals are already
      populated
- [ ] 1.4 `cache_deps_for`/`cache_uses_for` parse the cache globals with
      `grep`/`awk` and never invoke `brew`
- [ ] 1.5 `cache_build` emits `logv "[timing] cache built in Xs"` when
      `VERBOSE` is set, and nothing when it isn't

## 2. Consume cache in cleanup and bloat

- [ ] 2.1 Refactor `cleanup_scan` in `lib/brewmaster/cleanup.sh` to call
      `cache_build` before its per-package walk loop
- [ ] 2.2 Replace per-package `brew deps`/`brew uses` calls in
      `cleanup_scan` with `cache_deps_for`/`cache_uses_for`
- [ ] 2.3 Refactor the `bloat` walk to call `cache_build` and consume
      `cache_deps_for`/`cache_uses_for` the same way
- [ ] 2.4 Confirm no remaining per-package `brew deps`/`brew uses` calls in
      either walk (`grep -n "brew deps\|brew uses" lib/brewmaster/cleanup.sh`)

## 3. Tests

- [ ] 3.1 Add fixture-based tests to `tests/test_cleanup.sh` covering
      `cache_build`/`cache_deps_for`/`cache_uses_for` against captured
      `brew --for-each`/`--eval-all` output
- [ ] 3.2 Add a test asserting `cleanup`/`bloat` output is unchanged
      before/after the refactor for the same fixture package state
- [ ] 3.3 Verify `--dry-run` still behaves correctly post-refactor
- [ ] 3.4 Run full existing test suite and confirm no regressions

## 4. Verification

- [ ] 4.1 Manually time `brewmaster cleanup --dry-run` and `brewmaster
      bloat` on a real machine, confirm completion well under the 5s
      target from `ROADMAP.md`'s acceptance criteria
- [ ] 4.2 Update `ROADMAP.md` M6 status to `[x] done` once merged
