## 1. Add decorative colors to ui.sh

- [ ] 1.1 Add `COLOR_HEADER` (`tput setaf 6`, cyan) and `COLOR_COMMAND`
      (`tput setaf 4`, blue) to `ui_color_init` in
      `lib/brewmaster/core/ui.sh`, set to empty strings under the same
      `NO_COLOR`/non-TTY/no-`tput` conditions as the existing four
      constants
- [ ] 1.2 Update `ui_color_init`'s header comment to list the two new
      constants

## 2. Source ui.sh early, alongside help_data.sh

- [ ] 2.1 Move `source "$LIB_DIR/core/ui.sh"` and the `ui_color_init`
      call from their current position (after argument parsing) to right
      after `source "$LIB_DIR/core/help_data.sh"` near the top of
      `bin/brewmaster`
- [ ] 2.2 Run the full test suite (`bash tests/test_*.sh`, all 8 files)
      and confirm every existing assertion still passes — this step must
      be behavior-neutral for every command other than help output

## 3. Unify the dim/muted path, apply new colors to help rendering

- [ ] 3.1 Remove `D` from `_help_style_vars`; update `_help_style_desc`
      to use `$COLOR_MUTED`/`$COLOR_RESET` instead of `$D`/`$R`
- [ ] 3.2 In `_help_render_line`, add `$COLOR_HEADER` to the section
      header branch (caps-header lines) and `$COLOR_RESET` after it,
      alongside the existing bold
- [ ] 3.3 In `_help_style_name`, add `$COLOR_COMMAND` to the bolded
      name-token portions (not the underlined placeholder portions) and
      `$COLOR_RESET` after each, alongside the existing bold
- [ ] 3.4 Manually verify on a real TTY: `brewmaster --help` and
      `brewmaster help cleanup` show colored headers/commands; compare
      against the "before" look to confirm placeholders stay
      underline-only (no third color)

## 4. Tests and fixtures

- [ ] 4.1 Confirm `tests/fixtures/help.txt` and any `help-<command>.txt`
      fixtures are still produced byte-identical under
      `NO_COLOR=1 bin/brewmaster --help`/`help <command>` — no
      regeneration should be needed if the plain-text path is truly
      unchanged; if it differs, that's a bug in this change, not an
      expected fixture update
- [ ] 4.2 Add a `tests/test_cli.sh` (or wherever the project's existing
      color-selection tests live) assertion using the same sentinel-
      override pattern as `test_depgraph.sh`/`test_cleanup.sh`: after
      `ui_color_init`, override `COLOR_HEADER`/`COLOR_COMMAND` with
      distinguishable strings and confirm `--help`'s rendered output
      contains them in the right places
- [ ] 4.3 Add an assertion confirming `COLOR_HEADER`/`COLOR_COMMAND`
      resolve to `tput setaf` codes distinct from `COLOR_OK`/`WARN`/
      `HIGH` (e.g. compare the real `tput setaf N` sequences, not just
      that they're non-empty)
- [ ] 4.4 Run `bash tests/run_all.sh`-equivalent (the existing
      `for f in tests/test_*.sh` loop) and `shellcheck bin/brewmaster
      lib/brewmaster/core/ui.sh` — everything must pass, zero findings
