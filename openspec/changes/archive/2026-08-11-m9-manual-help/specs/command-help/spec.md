## ADDED Requirements

### Requirement: Per-command help dispatch
`brewmaster help <command>` SHALL print that command's usage line, its
applicable flags, and at least one worked example, sourced from the same
shared help data (`lib/brewmaster/core/help_data.sh`) that drives the
top-level `--help` output.

#### Scenario: Known command
- **WHEN** the user runs `brewmaster help cleanup`
- **THEN** stdout shows `cleanup`'s purpose, its applicable flags
  (`--dry-run`, `--interactive`, `--force`), and one practical example
  command line

#### Scenario: Known subcommand under a multi-command group
- **WHEN** the user runs `brewmaster help snapshot`
- **THEN** stdout shows the SNAPSHOT & ROLLBACK group's commands
  (`save|list|diff|restore|delete`), their shared flags, and one worked
  example

#### Scenario: Unknown command
- **WHEN** the user runs `brewmaster help nosuchcommand`
- **THEN** the program prints an error to stderr naming the unknown
  command and exits with a non-zero status, without printing partial help
  content

### Requirement: Bare `help` shows the existing grouped reference
`brewmaster help` with no command argument SHALL produce the same grouped,
byte-identical (under `NO_COLOR`/non-TTY) output as `brewmaster --help` /
`-h`.

#### Scenario: Bare help invocation
- **WHEN** the user runs `brewmaster help` with no further arguments
- **THEN** stdout matches `brewmaster --help`'s output exactly under
  `NO_COLOR=1`

### Requirement: Top-level `--help` output is unchanged
`brewmaster --help` / `-h` SHALL continue to print the same grouped
reference it prints today, now rendered from the shared help data instead
of an inline heredoc, with no observable output difference for existing
commands and flags.

#### Scenario: Byte-identical under NO_COLOR
- **WHEN** `NO_COLOR=1 brewmaster --help` is run
- **THEN** stdout is byte-identical to the pre-change reference output for
  every group, command, and flag that existed before this change (new
  per-group example lines are the only intentional additions, tracked in
  a re-pinned fixture)
