## Why

Every command that prints a table, a progress count, or a section header
already does it by hand: `profile.sh`, `audit.sh`, `depgraph.sh`,
`cleanup.sh`, and `snapshot.sh` each have their own `printf '%-Ns  ...'`
header/row pair; `cleanup.sh` and `upgrade.sh` each have their own
`printf '\r\033[K[%d/%d] %s'` progress line; `audit_report` draws its own
one-off `─────` rule under its title. None of it is shared, none of it
uses color, and `bin/brewmaster` already has working `NO_COLOR`/non-TTY
detection (`tput`-based, for `--help`'s bold/underline/dim) that nothing
else in the codebase reuses. Risk levels (dependency risk score, cleanup
score) are printed as plain numbers with no visual distinction between
LOW/MEDIUM/HIGH, even though those thresholds are already defined and
used for gating logic in `depgraph.sh`/`upgrade.sh`.

## What Changes

- Add `lib/brewmaster/core/ui.sh`: color constants (extending the
  existing `tput`/`NO_COLOR`/non-TTY detection pattern from
  `bin/brewmaster` to real ANSI colors, not just bold/dim), a shared
  table header/row printer, a shared progress-line helper (`[N/total]`,
  the pattern already used and working — not a new spinner primitive),
  a section-header helper, and a summary-line helper.
- Migrate every existing hand-rolled table/progress/section pattern in
  `profile.sh`, `audit.sh`, `depgraph.sh`, `cleanup.sh`, `upgrade.sh`,
  and `snapshot.sh` to consume `ui.sh` instead of duplicating the
  `printf` formatting locally.
- Apply color to what's genuinely uncolored today: dependency risk score
  (`deps show`, `upgrade` risk warnings) and cleanup score/category
  (`cleanup`, `why`), using the LOW/MEDIUM/HIGH thresholds already
  defined in `depgraph.sh`/`upgrade.sh`/`cleanup.sh`.
- Add a one-line summary at the end of commands that don't already have
  one in some form (`cleanup`, `deps show`, `snapshot list/diff`) —
  `audit_report` and `cleanup_bloat` already print a summary-shaped
  block; those get migrated to the shared helper, not rebuilt.
- Update every test that asserts on this output to strip ANSI codes
  before comparing, per the existing convention already used for
  `--help`'s NO_COLOR test in `tests/test_cli.sh`.

## Capabilities

### New Capabilities
- `ui-output`: shared color/table/progress/section/summary helpers in
  `lib/brewmaster/core/ui.sh`, colors suppressed under `NO_COLOR` or a
  non-TTY stdout (matching the existing `--help` styling contract),
  consumed by every command that prints tabular or leveled output.

### Modified Capabilities
(none — no existing `openspec/specs/` entries cover `cleanup`, `upgrade`,
`profile`, `audit`, `depgraph`, or `snapshot` output formatting today;
this is the first spec written for their visual behavior)

## Impact

- **Affected code**: new `lib/brewmaster/core/ui.sh`; every command file
  that currently formats its own tables/progress/sections —
  `lib/brewmaster/profile.sh`, `audit.sh`, `depgraph.sh`, `cleanup.sh`,
  `upgrade.sh`, `snapshot.sh`.
- **Affected commands**: `cleanup`, `bloat`, `why`, `deps show`,
  `upgrade` (default command), `profile list`, `log`, `report`,
  `snapshot list/diff` — output gains color (when TTY, no `NO_COLOR`)
  and a consistent section/summary shape. No flag or exit-code changes;
  piped/`NO_COLOR` output stays plain text (existing contract, extended).
- **Tests**: every test file that asserts on the affected commands'
  output needs an ANSI-strip step before comparison (`tests/test_cli.sh`,
  `test_cleanup.sh`, `test_audit.sh`, `test_depgraph.sh`,
  `test_profile.sh`, `test_snapshot.sh`).
- **No dependency, config, or storage-format changes.**
