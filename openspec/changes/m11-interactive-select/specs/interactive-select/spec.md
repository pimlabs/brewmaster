## ADDED Requirements

### Requirement: Advertised keys match bound keys

Any `fzf`-backed selection UI SHALL derive its displayed key header from
the same bind list it passes to `fzf`. A key SHALL NOT appear in the
header unless the corresponding bind was applied, and a bound key
intended for the user SHALL NOT be omitted from the header.

#### Scenario: Header names a key that is bound
- **WHEN** the picker advertises `ctrl-a: all` in its header
- **THEN** the `fzf` invocation includes a bind mapping `ctrl-a` to
  `select-all`

#### Scenario: Unsupported bind is omitted from both
- **WHEN** the running `fzf` does not support a bind the picker would
  otherwise apply
- **THEN** that bind is absent from the invocation AND its key is absent
  from the header

### Requirement: Selection marker is visually distinct from the cursor

The picker SHALL set a marker glyph for selected items that differs from
the cursor pointer glyph, so a selected row is distinguishable from the
row under the cursor.

#### Scenario: Marker and pointer differ
- **WHEN** the picker invokes `fzf`
- **THEN** it passes both `--marker` and `--pointer` with different
  values

### Requirement: Caller chooses the preselect mode

The picker SHALL accept a preselect mode of `all` or `none` from the
caller. Under `all`, every candidate starts selected; under `none`, no
candidate starts selected. The picker SHALL NOT impose one mode on all
callers.

#### Scenario: Opt-out picker preselects everything
- **WHEN** a caller requests preselect mode `all` and the running `fzf`
  supports selecting at startup
- **THEN** the invocation includes a bind that selects all items on
  startup

#### Scenario: Opt-in picker preselects nothing
- **WHEN** a caller requests preselect mode `none`
- **THEN** the invocation includes no startup selection bind

#### Scenario: Preselect degrades when unsupported
- **WHEN** a caller requests preselect mode `all` and the running `fzf`
  does not support selecting at startup
- **THEN** the picker still produces a usable invocation with nothing
  preselected, rather than failing or emitting an invalid bind

### Requirement: Picker renders inline, not full screen

The picker SHALL constrain its height so surrounding terminal output
printed before it remains visible, rather than taking over the
alternate screen.

#### Scenario: Risk warnings stay visible during review
- **WHEN** `run_upgrade` prints MEDIUM-risk warnings and then opens the
  review picker
- **THEN** the picker is invoked with a height constraint and those
  warnings remain on screen

### Requirement: Missing fzf is reported to the caller, not fatal

When `fzf` is not installed, the picker SHALL signal this to its caller
via a non-zero return rather than terminating the process, leaving the
fallback decision to the caller.

#### Scenario: fzf absent
- **WHEN** the picker is called and `fzf` is not on `PATH`
- **THEN** it returns non-zero without calling `exit` and without
  writing a selection to stdout
