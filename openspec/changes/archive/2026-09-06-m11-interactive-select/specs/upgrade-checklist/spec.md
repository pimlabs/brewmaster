## MODIFIED Requirements

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

## ADDED Requirements

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
