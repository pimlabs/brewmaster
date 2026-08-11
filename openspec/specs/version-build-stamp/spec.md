# version-build-stamp

## Purpose

TBD: defines the `--version` / `-V` output format, adding a hand-maintained
build date constant alongside the existing semantic version constant near
the top of `bin/brewmaster`.

## Requirements

### Requirement: `--version` includes a build date

`brewmaster --version` / `-V` SHALL print the semantic version and a build
date, in the form `brewmaster <version> (built <YYYY-MM-DD>)`.

#### Scenario: Version output includes build date
- **WHEN** the user runs `brewmaster --version`
- **THEN** stdout matches `brewmaster <BREWMASTER_VERSION> (built
  <BUILD_DATE>)` where both values come from constants near the top of
  `bin/brewmaster`

#### Scenario: Build date is a fixed, hand-maintained constant
- **WHEN** `BUILD_DATE` is inspected in `bin/brewmaster`
- **THEN** it is a literal `YYYY-MM-DD` string bumped by the maintainer at
  release time alongside `BREWMASTER_VERSION`, not computed from file
  metadata or `git log` at runtime
