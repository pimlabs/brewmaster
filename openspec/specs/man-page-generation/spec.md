# man-page-generation

## Purpose

TBD: defines `docs/gen-man.sh`, which generates the `docs/brewmaster.1`
troff man page from the shared help data module
(`lib/brewmaster/core/help_data.sh`), so the man page stays in sync with
the CLI's own `--help` output instead of drifting as a separately
hand-maintained document.

## Requirements

### Requirement: Man page generated from shared help data

`docs/brewmaster.1` SHALL be produced by `docs/gen-man.sh` reading
`lib/brewmaster/core/help_data.sh`, in valid troff format with sections
NAME, SYNOPSIS, DESCRIPTION, COMMANDS, FILES, and EXAMPLES, rendering
correctly via `man(1)`.

#### Scenario: Generator produces valid troff
- **WHEN** a maintainer runs `docs/gen-man.sh`
- **THEN** it prints troff content to stdout containing `.SH NAME`,
  `.SH SYNOPSIS`, `.SH DESCRIPTION`, `.SH COMMANDS`, `.SH FILES`, and
  `.SH EXAMPLES` sections

#### Scenario: Renders via man(1)
- **WHEN** a user runs `man ./docs/brewmaster.1` (or `man brewmaster` once
  installed)
- **THEN** the page renders without troff formatting errors and shows
  current commands and flags matching `brewmaster --help`

### Requirement: Committed man page matches generator output

The committed `docs/brewmaster.1` SHALL always equal what
`docs/gen-man.sh` currently produces from `help_data.sh` — no independent
hand edits.

#### Scenario: No drift between source and committed file
- **WHEN** the test suite runs the man-page drift check
- **THEN** `docs/gen-man.sh`'s stdout is diffed against the committed
  `docs/brewmaster.1`, and the test fails if they differ

#### Scenario: Content reflects current commands
- **WHEN** `docs/brewmaster.1` is regenerated after `help_data.sh` gains
  or changes a command
- **THEN** the man page's COMMANDS section reflects that change with no
  separate manual edit required
