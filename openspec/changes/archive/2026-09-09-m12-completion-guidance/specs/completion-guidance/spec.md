## ADDED Requirements

### Requirement: Completion status is descriptive and read-only

`brewmaster completion` SHALL report, for the shell named by `--shell`
or else by `$SHELL`, the resolved path of that shell's completion script
(or that none was found), whether the shell's rc files reference the
Homebrew completion setup, and the configuration snippet to add when
they do not. It SHALL NOT write to any file.

#### Scenario: Installed and configured
- **WHEN** the script is found and the rc files reference the setup
- **THEN** the report shows the path, says the shell is set up, and
  exits 0

#### Scenario: Installed but not configured
- **WHEN** the script is found and no rc file references the setup
- **THEN** the report shows the path and prints the snippet for that
  shell, and exits 0

#### Scenario: Not installed
- **WHEN** no script is found in either layout
- **THEN** the report says so, prints how to install, and exits 1

#### Scenario: Unsupported shell
- **WHEN** the shell is not bash, zsh or fish
- **THEN** an error names the three supported shells and the command
  exits 1

### Requirement: Completion scripts can be printed

`brewmaster completion <bash|zsh|fish>` SHALL print that shell's
completion script to stdout with nothing else on stdout, exiting 0, or
exit 1 with an error on stderr when the script cannot be found.

#### Scenario: Print for sourcing
- **WHEN** `brewmaster completion zsh` runs with the script available
- **THEN** stdout is exactly the script's contents

### Requirement: Both install layouts are resolved

Script lookup SHALL try the git-checkout layout (`completions/` beside
`lib/`) before the Homebrew formula targets under `brew --prefix`, and
SHALL only invoke `brew` when the checkout layout misses.

#### Scenario: Checkout wins
- **WHEN** both layouts contain a script
- **THEN** the checkout's script is used and `brew` is not invoked
