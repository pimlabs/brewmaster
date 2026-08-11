# help-color

## Purpose

TBD: defines decorative ANSI color for `brewmaster --help` and
`brewmaster help [command]` structural elements (section headers,
command/flag name-tokens), layered on top of the existing bold/underline/dim
styling. This coloring is decorative rather than semantic — unlike
`ui-output`'s `COLOR_OK`/`COLOR_WARN`/`COLOR_HIGH`, it carries no
score/status meaning — and follows the same `NO_COLOR`/non-TTY/no-`tput`
degradation guarantee every other color surface in this project already has.

## Requirements

### Requirement: Section headers and command/flag names are colored on a TTY

`brewmaster --help` and `brewmaster help [command]` SHALL render section
headers with `COLOR_HEADER` and command/flag name-tokens with
`COLOR_COMMAND`, layered on top of the existing bold styling, when stdout
is a TTY, `NO_COLOR` is unset, and `tput` is available.

#### Scenario: TTY help output is colored
- **WHEN** `brewmaster --help` runs with stdout attached to a TTY,
  `NO_COLOR` unset, and `tput` available
- **THEN** section header lines (e.g. `UPGRADE`) contain `COLOR_HEADER`'s
  ANSI sequence, and command/flag name-tokens (e.g. `--dry-run`) contain
  `COLOR_COMMAND`'s ANSI sequence

#### Scenario: help <command> output is colored the same way
- **WHEN** `brewmaster help cleanup` runs under the same TTY conditions
- **THEN** its section header and command/flag name-tokens are colored
  identically to the equivalent block in `brewmaster --help`

### Requirement: Decorative colors are disjoint from semantic risk/cleanup colors

`COLOR_HEADER` and `COLOR_COMMAND` SHALL use different `tput setaf` codes
than `COLOR_OK`, `COLOR_WARN`, and `COLOR_HIGH`, so help styling never
visually collides with risk-score or cleanup-score coloring.

#### Scenario: No color code overlap
- **WHEN** `COLOR_HEADER`, `COLOR_COMMAND`, `COLOR_OK`, `COLOR_WARN`, and
  `COLOR_HIGH` are compared
- **THEN** all five resolve to distinct `tput setaf` color codes

### Requirement: Plain-text fallback is unchanged

`NO_COLOR` set, non-TTY stdout, or `tput` unavailable SHALL continue to
produce byte-identical plain text to today's `--help`/`help [command]`
output — no `COLOR_HEADER`/`COLOR_COMMAND`/`COLOR_MUTED` escape sequences
appear under any of these three conditions.

#### Scenario: NO_COLOR set
- **WHEN** `NO_COLOR=1 brewmaster --help` runs
- **THEN** stdout is byte-identical to `tests/fixtures/help.txt`

#### Scenario: Piped output
- **WHEN** `brewmaster --help | cat` runs (stdout not a TTY)
- **THEN** the output contains no `\x1b[` escape sequences

#### Scenario: help <command> plain fallback
- **WHEN** `NO_COLOR=1 brewmaster help cleanup` runs
- **THEN** its output matches the pre-this-change plain-text rendering of
  that command's block, byte-for-byte
