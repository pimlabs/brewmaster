# cli-spec

## Purpose

TBD — one machine-readable declaration of the CLI surface
(`lib/brewmaster/core/cli_spec.sh`: commands, sub-subcommands,
positionals, flags) from which `docs/gen-completions.sh` generates the
bash, zsh and fish completion scripts, with tests holding the parser in
`bin/brewmaster`, the help table and the committed scripts to that one
list.

## Requirements

### Requirement: One machine-readable source for the CLI surface

The CLI's commands, sub-subcommands, positionals and flags SHALL be
declared once, in `lib/brewmaster/core/cli_spec.sh`, as records with a
documented grammar, and the shell completion scripts SHALL be generated
from those records.

#### Scenario: Completion scripts are generated artifacts
- **WHEN** `docs/gen-completions.sh <shell>` runs for bash, zsh or fish
- **THEN** its output equals the committed `completions/brewmaster.<shell>`
  byte for byte

#### Scenario: Regeneration is deterministic
- **WHEN** the generator runs twice on the same spec
- **THEN** the outputs are identical

### Requirement: The parser and the spec agree

Every command and flag the spec declares SHALL be parsed by
`bin/brewmaster`, and every command and long flag `bin/brewmaster`
parses SHALL be declared in the spec.

#### Scenario: A flag added to the parser only
- **WHEN** a `--flag)` case is added to `bin/brewmaster` without a spec
  record
- **THEN** `tests/test_completions.sh` fails naming the flag

#### Scenario: A flag added to the spec only
- **WHEN** a spec record names a flag the parser does not accept
- **THEN** `tests/test_completions.sh` fails naming the flag

### Requirement: The help text and the spec agree

Every command and long flag in the spec SHALL appear in `help_data.sh`.

#### Scenario: A spec flag missing from help
- **WHEN** a spec flag has no mention in the help text
- **THEN** `tests/test_completions.sh` fails naming the flag

### Requirement: Generated scripts keep the hand-written behavior

For each shell, the generated script SHALL offer the same completions in
the same contexts as the script it replaces: commands with
descriptions, sub-subcommands, flags, enum values, dynamic package and
profile completers, and the default command's flags at top level.

#### Scenario: Top level
- **WHEN** completing after `brewmaster `
- **THEN** every command in the spec is offered
