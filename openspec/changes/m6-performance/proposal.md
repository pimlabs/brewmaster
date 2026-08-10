## Why

`cleanup` and `bloat` still call `brew list "$pkg"` and `brew --cellar "$pkg"`
once per installed package inside their walk loops — `_cleanup_last_access`
uses `brew list "$pkg"` to enumerate a package's files for the last-access
heuristic, and `cleanup_bloat` uses `brew --cellar "$name"` to locate each
package's Cellar directory for disk-size accounting. Each is a `brew`
subprocess with its own Ruby/Formulary startup cost, repeated per package.

(The dependency/reverse-dependency graph itself was already fixed this way
in M2 — `depgraph_build` fetches `brew info --json=v2 --installed` once and
derives the full `deps`/`uses` map from it, per the comment at
`lib/brewmaster/depgraph.sh:11-13`. This proposal covers the per-package
`brew list`/`brew --cellar` calls that remain, not that already-solved
problem.)

## What Changes

- Cache the Homebrew Cellar root path (`brew --cellar`, no package
  argument) once per command invocation.
- `_cleanup_last_access` locates a package's bin/sbin files by globbing
  directly under the cached Cellar root instead of calling
  `brew list "$pkg"`.
- `cleanup_bloat`'s per-package Cellar lookup derives the path from the
  cached root instead of calling `brew --cellar "$name"`.
- No CLI flags, output format, or `--dry-run` semantics change.

## Capabilities

### New Capabilities
- `cellar-path-cache`: cache the Homebrew Cellar root path once per
  invocation and derive per-package Cellar paths from it directly,
  eliminating the per-package `brew list`/`brew --cellar` subprocess calls
  remaining in the `cleanup`/`bloat` walks.

### Modified Capabilities
(none — no existing `openspec/specs/` entries cover `cleanup` or `bloat`
today; their observable behavior is unchanged by this refactor)

## Impact

- **Affected code**: `lib/brewmaster/cleanup.sh` —
  `_cleanup_last_access`, `cleanup_bloat`.
- **Affected commands**: `brewmaster cleanup`, `brewmaster bloat` — same
  output and flags, faster execution.
- **Tests**: `tests/test_cleanup.sh` needs coverage for the glob-based
  lookup and cached Cellar root.
- **No dependency, config, or storage-format changes.**
