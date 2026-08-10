## ADDED Requirements

### Requirement: Review gate is the default before executing upgrades

`run_upgrade` SHALL, after collecting all upgrade candidates and when not
running under `--dry-run` or `--yes`, present a review step covering the
full candidate list before executing any `brew upgrade` call. It SHALL
NOT execute any upgrade until the user has confirmed via that review
step.

#### Scenario: Default invocation with candidates stops for review
- **WHEN** `brewmaster --minor` runs with one or more upgrade candidates,
  without `--dry-run` or `--yes`
- **THEN** it presents the review step before any `brew upgrade` call is
  made

#### Scenario: No candidates skips the review step
- **WHEN** `run_upgrade` collects zero candidates
- **THEN** it prints "No packages to upgrade..." and returns, without
  presenting a review step

### Requirement: --yes bypasses the review step

`--yes`/`-y` SHALL skip the review step entirely and proceed directly to
executing all collected candidates, in addition to its existing behavior
of auto-confirming MEDIUM-risk packages.

#### Scenario: --yes upgrades without review
- **WHEN** `brewmaster --minor --yes` runs with one or more candidates
- **THEN** it executes `brew upgrade` for every collected candidate
  without presenting a review step

### Requirement: fzf multi-select review when fzf is available

When `fzf` is installed, the review step SHALL present the full candidate
list via `fzf` multi-select, allowing the user to deselect individual
packages before confirming. Only the packages remaining selected SHALL be
upgraded.

#### Scenario: User deselects a package in fzf
- **WHEN** the review step runs with `fzf` installed and the user
  deselects one candidate before confirming
- **THEN** that package is excluded from the upgrade execution and no
  `brew upgrade` call is made for it

### Requirement: Plain table + single y/N fallback when fzf is unavailable

When `fzf` is not installed, the review step SHALL print the full
candidate table and prompt once with a single `[y/N]` confirmation for
the whole batch, instead of exiting with an error.

#### Scenario: No fzf, user confirms
- **WHEN** the review step runs without `fzf` installed and the user
  answers `y`
- **THEN** all collected candidates are upgraded

#### Scenario: No fzf, user declines
- **WHEN** the review step runs without `fzf` installed and the user
  answers anything other than `y`/`Y`
- **THEN** no `brew upgrade` call is made and the command exits 0

### Requirement: --dry-run is unaffected

`--dry-run` SHALL continue to print the full candidate table and exit
before any review step or execution, exactly as it does today.

#### Scenario: --dry-run never triggers review
- **WHEN** `brewmaster --minor --dry-run` runs with one or more
  candidates
- **THEN** it prints the candidate table and exits without presenting a
  review step or executing any upgrade
