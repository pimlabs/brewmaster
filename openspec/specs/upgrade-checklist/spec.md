# upgrade-checklist

## Purpose

TBD — adds a review gate before `run_upgrade` executes any `brew upgrade`
call, letting the user confirm or trim the candidate list (via the
shared `fzf` picker with every candidate preselected when `fzf` is
available, or a plain table plus a single `[y/N]` prompt otherwise), while `--yes` and `--dry-run` keep their existing
bypass behavior.

## Requirements

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

When `fzf` is installed, the review step SHALL present the full
candidate list via the shared picker with preselect mode `all`: every
candidate starts selected and the user deselects the ones to skip. Only
the packages remaining selected SHALL be upgraded. This matches the
no-`fzf` fallback's whole-batch semantics, so the selection model does
not depend on whether `fzf` happens to be installed.

#### Scenario: User confirms without deselecting anything
- **WHEN** the review step runs with `fzf` installed and the user
  confirms without changing the selection
- **THEN** every collected candidate is upgraded

#### Scenario: User deselects a package
- **WHEN** the review step runs with `fzf` installed and the user
  deselects one candidate before confirming
- **THEN** that package is excluded from the upgrade execution and no
  `brew upgrade` call is made for it

#### Scenario: User deselects everything
- **WHEN** the review step runs with `fzf` installed and the user
  deselects every candidate before confirming
- **THEN** no `brew upgrade` call is made and the command prints
  "Nothing selected." and exits 0

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

### Requirement: Risk score is visible in the review list

When dependency checking is active, each row in the review list SHALL
display the package's dependency risk score alongside its version bump,
so the score is available at the moment the user decides whether to keep
the package selected.

#### Scenario: Risk score shown for a candidate
- **WHEN** the review step runs with dependency checking active
- **THEN** each candidate row includes its risk score

#### Scenario: No risk score without dependency checking
- **WHEN** the review step runs with dependency checking disabled
- **THEN** candidate rows omit the risk score column rather than showing
  an empty one
