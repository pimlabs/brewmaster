## 1. Extract shared help data (no behavior change)

- [x] 1.1 Create `lib/brewmaster/core/help_data.sh` with a
      `_help_source_text()` function containing the exact current heredoc
      content moved out of `bin/brewmaster`'s `usage()`
- [x] 1.2 Source `core/help_data.sh` from `bin/brewmaster`, refactor
      `usage()` to pipe `_help_source_text()` through its existing styling
      loop instead of an inline heredoc
- [x] 1.3 Run `bash tests/test_cli.sh` and confirm the existing `--help`
      byte-identical assertion still passes unmodified — this step must be
      a pure refactor with zero output change

## 2. Add missing per-group examples

- [x] 2.1 Add one `e.g. brewmaster ...` example line to each group in
      `help_data.sh` that doesn't already have one: DEPENDENCY RISK,
      SNAPSHOT & ROLLBACK, PROFILES, CLEANUP & INTENT, AUDIT LOG & REPORTS
- [x] 2.2 Regenerate `tests/fixtures/help.txt`
      (`NO_COLOR=1 bin/brewmaster --help > tests/fixtures/help.txt`) and
      confirm the new example lines are the only diff from the previous
      fixture

## 3. `brewmaster help [command]` dispatch

- [x] 3.1 Add a command-name → group-name lookup in `bin/brewmaster`
      covering every command listed across all groups (`upgrade`,
      `snapshot save|list|diff|restore|delete`, `deps show`,
      `profile list|create|edit|diff|validate`, `cleanup`, `why`, `bloat`,
      `log`, `report`)
- [x] 3.2 Implement `help_command()`: slice `_help_source_text()` output
      by group header, print the matching group's block through the
      existing `_help_style_name`/`_help_style_desc` helpers
- [x] 3.3 Add `help` dispatch case: `brewmaster help` (no args) calls
      `usage()`; `brewmaster help <command>` calls `help_command
      <command>`; unknown command prints an error to stderr and exits 1
- [x] 3.4 Add fixtures under `tests/fixtures/help-<command>.txt` (or one
      per group) and assertions in `tests/test_cli.sh` for: a known
      single-command group, a known multi-command group (`snapshot`), and
      an unknown command's error + exit code

## 4. `--version` build date

- [x] 4.1 Add `BUILD_DATE="YYYY-MM-DD"` next to `BREWMASTER_VERSION` at
      `bin/brewmaster:5`, set to the date this task is implemented
- [x] 4.2 Change the `--version`/`-V` output to
      `brewmaster ${BREWMASTER_VERSION} (built ${BUILD_DATE})`
- [x] 4.3 Add a `tests/test_cli.sh` assertion matching the new
      `--version` output format

## 5. Man page generator

- [ ] 5.1 Create `docs/gen-man.sh`: source `lib/brewmaster/core/help_data.sh`
      only (no CLI dispatch), walk `_help_source_text()`'s line shapes,
      emit troff with `.SH NAME`, `.SH SYNOPSIS`, `.SH DESCRIPTION`,
      `.SH COMMANDS`, `.SH FILES`, `.SH EXAMPLES`
- [ ] 5.2 Run `docs/gen-man.sh > docs/brewmaster.1`, confirm it renders
      cleanly via `man ./docs/brewmaster.1` with no troff errors, and that
      COMMANDS reflects current v0.9.x+ commands (profiles, audit
      log/report, cleanup — the content this milestone's research found
      missing from the old hand-written page)
- [ ] 5.3 Commit the regenerated `docs/brewmaster.1`

## 6. Drift enforcement

- [ ] 6.1 Add a `tests/test_cli.sh` (or new `tests/test_docs.sh`)
      assertion that runs `docs/gen-man.sh`, diffs its stdout against the
      committed `docs/brewmaster.1`, and fails on any difference
- [ ] 6.2 Run `bash tests/run_all.sh` and `shellcheck` on
      `bin/brewmaster`, `lib/brewmaster/core/help_data.sh`, and
      `docs/gen-man.sh`; fix anything flagged
- [ ] 6.3 Update `bin/brewmaster --help`'s own "Notes:" section — remove
      the now-false "there is no per-subcommand --help" line and mention
      `brewmaster help <command>` instead; re-regenerate
      `tests/fixtures/help.txt` for this final content change
