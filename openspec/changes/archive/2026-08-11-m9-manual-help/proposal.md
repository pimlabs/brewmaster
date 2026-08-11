## Why

`brewmaster --help` already groups commands by area, but there is no
per-command detail: `bin/brewmaster` explicitly documents "there is no
per-subcommand --help" (line 226). After a break, the user has no quick way
to recall one command's flags and a working example without reading source.
`docs/brewmaster.1` exists but was hand-written at v0.6.1 and has drifted —
it predates profiles, audit log, and cleanup, and nothing keeps it in sync
with `--help`. `--version` prints only a semver string with no build date,
so a bug report can't pin which exact build the user is on.

## What Changes

- Add `brewmaster help [command]` — per-command usage, flags, and one
  worked example, sourced from a single per-command metadata table.
- Reuse that same metadata table to drive the existing top-level
  `brewmaster --help` grouped output (no behavior change to its content,
  only its source — output must stay byte-identical to
  `tests/fixtures/help.txt` under `NO_COLOR`/non-TTY).
- Regenerate `docs/brewmaster.1` from the same metadata table, so the man
  page and both help surfaces can never drift from each other again. This
  refreshes the man page's stale content to current v0.8.x commands
  (profiles, audit log, report, cleanup) as a byproduct of the mechanism,
  not a separate hand edit.
- `brewmaster --version` / `-V` output gains a build date, e.g.
  `brewmaster 0.8.1 (built 2026-08-11)`.
- Out of scope: `Formula/brewmaster.rb` — it does not live in this repo.
  It lives in `pimlabs/homebrew-tap` and already installs the man page
  (`man1.install "docs/brewmaster.1"`); nothing to change there.

## Capabilities

### New Capabilities
- `command-help`: per-command help dispatch (`brewmaster help [command]`),
  backed by a single per-command metadata table that also drives the
  existing top-level `--help` grouped output.
- `man-page-generation`: generates `docs/brewmaster.1` (troff) from the
  same per-command metadata table used by `command-help`, keeping content
  and command coverage in sync with the CLI by construction.
- `version-build-stamp`: `--version`/`-V` output includes a build date
  alongside the semver string.

### Modified Capabilities
(none — no existing `openspec/specs/` capability covers help/version/man
page output; `ui-output`, `upgrade-checklist`, and `cellar-path-cache` are
unrelated to this change)

## Impact

- `bin/brewmaster` — add `help` dispatch case, per-command metadata table,
  refactor `usage()` to read from that table, add build-date stamping to
  `--version`.
- `docs/brewmaster.1` — becomes a generated artifact instead of hand-edited
  (generation script/target added under a small helper, e.g.
  `lib/brewmaster/core/` or a one-off `scripts/` generator invoked at
  release time — exact placement decided in design.md).
- `tests/fixtures/help.txt` — unaffected in content, but the mechanism
  producing it changes; add new fixtures for `help <command>` output.
- `tests/test_cli.sh` — new assertions for `help <command>`, top-level
  `help` (no args), and `--version` build-date format.
- No change to `Formula/brewmaster.rb` (lives in `pimlabs/homebrew-tap`,
  out of this repo's reach).
