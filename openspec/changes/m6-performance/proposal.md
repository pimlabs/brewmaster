## Why

`cleanup` and `bloat` walk every installed package and call `brew deps` and
`brew uses` once per package inside the loop. On a machine with ~400 packages
this means hundreds of redundant `brew` subprocess invocations, each with its
own Ruby startup cost, making both commands noticeably slow. The dependency
graph brewmaster needs already exists in bulk via `brew deps --installed
--for-each` and `brew uses --installed --eval-all` — fetching it once and
parsing it from memory removes the per-package subprocess cost entirely.

## What Changes

- Add a shared dependency-cache module that builds the full deps/uses/list
  data in three bulk `brew` calls, once per command invocation.
- Refactor `cleanup_scan` (`lib/brewmaster/cleanup.sh`) and the `bloat` walk
  to read from the cache instead of calling `brew deps` / `brew uses` inside
  their loops.
- Add `VERBOSE`-gated timing output (`logv "[timing] cache built in Xs"`) so
  cache-build cost is visible when debugging.
- No CLI flags, output format, or `--dry-run` semantics change — this is a
  performance-only refactor of the internal walk.

## Capabilities

### New Capabilities
- `dependency-cache`: bulk-fetch and in-memory lookup of package
  dependency/uses/list data (`cache_build`, `cache_deps_for`,
  `cache_uses_for`), replacing per-package `brew` subprocess calls during
  `cleanup` and `bloat` walks.

### Modified Capabilities
(none — no existing `openspec/specs/` entries cover `cleanup` or `bloat`
today; their observable behavior is unchanged by this refactor, only the
internal data-fetch strategy changes)

## Impact

- **Affected code**: `lib/brewmaster/cleanup.sh` (consumes cache instead of
  per-package `brew` calls), new `lib/brewmaster/core/cache.sh`.
- **Affected commands**: `brewmaster cleanup`, `brewmaster bloat` — same
  output and flags, faster execution.
- **Tests**: `tests/test_cleanup.sh` needs cache-fed walk coverage.
- **No dependency, config, or storage-format changes.**
