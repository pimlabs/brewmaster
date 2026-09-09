## ADDED Requirements

### Requirement: The command may follow flags

`bin/brewmaster` SHALL take as the command the first non-flag argument
that names a command, wherever it appears; the word after a space-form
value flag SHALL be that flag's value and never the command; the
sub-subcommand SHALL remain the word immediately after the command.

#### Scenario: Flag before the command
- **WHEN** `brewmaster -n snapshot list` runs
- **THEN** it behaves exactly as `brewmaster snapshot list -n`

#### Scenario: Space-form value is not a command
- **WHEN** `brewmaster --level patch snapshot list` runs
- **THEN** `patch` is the level and `snapshot list` is the command

#### Scenario: Package after a flag
- **WHEN** `brewmaster -n foo` runs and `foo` is not a command name
- **THEN** it is a dry-run upgrade of `foo`, as before

#### Scenario: Command-first form unchanged
- **WHEN** `brewmaster snapshot list -n` runs
- **THEN** it behaves as it did before this change

### Requirement: Completions offer commands wherever the parser accepts one

The generated completion scripts SHALL offer command names after a
leading flag, SHALL not offer them for the value of a space-form value
flag, and the bash script SHALL complete `--flag=value` when bash splits
the word at `=`.

#### Scenario: Command after a leading flag
- **WHEN** completing `brewmaster -n <TAB>`
- **THEN** every command is offered (plus the default command's packages)

#### Scenario: bash `=` split
- **WHEN** bash presents `--level`, `=`, `pa` as the last words
- **THEN** `patch` is offered
