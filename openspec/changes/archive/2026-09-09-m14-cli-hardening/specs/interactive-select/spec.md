## ADDED Requirements

### Requirement: The picker is verified in a real terminal

A test SHALL run the real fzf inside a pseudo-terminal with the same
arguments `upgrade` uses and SHALL fail if the preselect count, the row
alignment, the marker glyph, or the rows returned on Enter regress.

#### Scenario: All rows preselected
- **WHEN** 101 rows are piped to `ui_select all` under a pty
- **THEN** fzf's info line reads `101/101 (101)` and Enter returns all 101 names in order

#### Scenario: Rows aligned
- **WHEN** rows carry a hidden first field and a padded table line
- **THEN** no visible row contains a tab and the `->` column is the same on every row

#### Scenario: Unavailable terminal
- **WHEN** fzf or a pty cannot be had
- **THEN** the test reports a skip and exits 0 rather than failing
