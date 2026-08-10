# ui-output

## Purpose

TBD: defines the shared `lib/brewmaster/core/ui.sh` module used by
brewmaster commands for color handling, table rendering, progress lines,
section headers, and score coloring, so that terminal output stays
consistent across commands and degrades correctly for `NO_COLOR` and
non-TTY output.

## Requirements

### Requirement: Color suppression matches existing --help behavior

`ui_color_init` SHALL set `COLOR_OK`, `COLOR_WARN`, `COLOR_HIGH`,
`COLOR_MUTED`, and `COLOR_RESET` to `tput`-derived ANSI sequences, and
SHALL set them all to empty strings when `NO_COLOR` is set, when stdout
is not a TTY, or when `tput` is unavailable — the same three conditions
`bin/brewmaster`'s existing `--help` styling already checks.

#### Scenario: NO_COLOR set
- **WHEN** `NO_COLOR` is set in the environment and `ui_color_init` runs
- **THEN** all `COLOR_*` variables are empty strings

#### Scenario: stdout is not a TTY
- **WHEN** stdout is piped (not a TTY) and `ui_color_init` runs
- **THEN** all `COLOR_*` variables are empty strings

#### Scenario: TTY, no NO_COLOR, tput available
- **WHEN** stdout is a TTY, `NO_COLOR` is unset, and `tput` is available
- **THEN** `COLOR_OK`, `COLOR_WARN`, `COLOR_HIGH` are non-empty ANSI
  sequences

### Requirement: Semantic color constants, not numeric thresholds

`ui.sh` SHALL expose only semantic color constants (`COLOR_OK`,
`COLOR_WARN`, `COLOR_HIGH`, `COLOR_MUTED`, `COLOR_RESET`). It SHALL NOT
define or apply numeric LOW/MEDIUM/HIGH thresholds itself — each caller
maps its own score to a semantic constant using thresholds already
defined in its own file.

#### Scenario: cleanup score and risk score use opposite color mapping for the same number
- **WHEN** a package has `cleanup_score` 8 (safe to remove) and a
  different package has `depgraph_risk_score` 8 (dangerous to upgrade)
- **THEN** the cleanup score is rendered with `COLOR_OK`, and the risk
  score is rendered with `COLOR_HIGH`

### Requirement: Shared table rendering

`ui_table_header` and `ui_table_row` SHALL accept a sequence of
`width value` pairs and print one aligned row per call, using the same
column widths a caller specifies — matching the widths each of the five
migrated tables (`profile list`, `log`, `deps show`, `cleanup` report,
`snapshot list`/`diff`) already uses today. `ui_table_header` SHALL also
print a dashed rule row matching each column's width.

#### Scenario: Existing table output is unchanged after migration
- **WHEN** `profile list`, `log`, `deps show`, `cleanup --dry-run`, or
  `snapshot list` runs with `NO_COLOR=1` (or piped)
- **THEN** its column alignment and content are identical to the
  pre-migration output

### Requirement: Shared progress line

`ui_progress "$current" "$total" "$label"` SHALL print an in-place
`[current/total] label` line (carriage-return, clear-to-end-of-line),
matching the existing pattern already used in `cleanup_scan`,
`cleanup_bloat`, and `run_upgrade` before this migration.

#### Scenario: Progress line format is unchanged after migration
- **WHEN** `cleanup`, `bloat`, or `upgrade` runs a multi-package walk
- **THEN** the progress line format is unchanged from the pre-migration
  `printf '\r\033[K[%d/%d] %s'` output

### Requirement: Shared section header

`ui_section "$title"` SHALL print the title followed by a `─` rule whose
length matches the title's length, generalizing `audit_report`'s
existing title-width rule so other commands (`cleanup bloat`,
`deps show`) can use the same style.

#### Scenario: Section rule matches title length
- **WHEN** `ui_section "Cleanup Report"` is called
- **THEN** the rule printed on the next line has the same character
  count as "Cleanup Report"

### Requirement: Risk and cleanup score coloring

`deps show` and `upgrade`'s risk warnings SHALL color the dependency
risk score using the existing HIGH (>=`RISK_THRESHOLD`, default 7),
MEDIUM (4-6), LOW (0-3) thresholds already defined in `depgraph.sh`.
`cleanup`, `why`, and `bloat` SHALL color the cleanup score using the
same three bands, with the color direction inverted (HIGH cleanup score
= `COLOR_OK`, since a higher cleanup score means safer to remove).

#### Scenario: deps show colors a HIGH-risk package red
- **WHEN** `brewmaster deps show <pkg>` runs for a package with risk
  score >= `RISK_THRESHOLD`
- **THEN** the risk score is rendered with `COLOR_HIGH`

#### Scenario: cleanup colors a HIGH cleanup score green
- **WHEN** `brewmaster cleanup` runs and a candidate has cleanup score
  >= 7
- **THEN** that row's score is rendered with `COLOR_OK`, not `COLOR_HIGH`

### Requirement: Colors never appear in non-TTY or NO_COLOR output

No command's output SHALL contain raw ANSI escape sequences when
`NO_COLOR` is set or when stdout is piped, regardless of which command
or table is rendered.

#### Scenario: Piped cleanup output has no escape sequences
- **WHEN** `brewmaster cleanup | cat` runs
- **THEN** the output contains no `\x1b[` sequences
