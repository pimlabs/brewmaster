## 1. ui.sh module

- [x] 1.1 Created `lib/brewmaster/core/ui.sh` with `ui_color_init`
      (`COLOR_OK`/`COLOR_WARN`/`COLOR_HIGH`/`COLOR_MUTED`/`COLOR_RESET`,
      suppressed under `NO_COLOR`/non-TTY/no-`tput`, mirroring
      `bin/brewmaster`'s existing `_help_style_vars` detection)
- [x] 1.2 Added `ui_table_header`/`ui_table_row` — width/value pairs
      (width `""` = trailing unpadded column). Verified byte-identical
      output against the hand-written `depgraph_list_risky` table.
      Discovered mid-implementation: rule-dash length in every existing
      table but `audit.sh`'s already matches the *label's* length, not
      the column width — `audit.sh` was the outlier; unified all tables
      on label-length dashes (nothing asserts the exact dash count, so
      this only fixes an existing inconsistency, doesn't break a test)
- [x] 1.3 Added `ui_progress`/`ui_progress_clear` — extracted the
      existing `printf '\r\033[K[%d/%d] %s'`/`printf '\r\033[K'` pattern,
      byte-identical
- [x] 1.4 Added `ui_section "$title"` — title + `─` rule matching title
      length (generalizes `audit_report`'s existing rule)
- [x] 1.5 Added `ui_summary "$msg"` — consistent end-of-command summary
      line wrapper
- [x] 1.6 Sourced `core/ui.sh` from `bin/brewmaster`, `ui_color_init`
      called once after all modules are sourced

## 2. Migrate depgraph.sh (risk score coloring)

- [x] 2.1 `depgraph_list_risky`'s table -> `ui_table_header`/`ui_table_row`.
      Verified byte-identical to the pre-migration output for the
      unpadded RISK score column (also fixed a latent bug: the padded
      score string like "07" is octal in a bare `(( ))` context, so the
      new `_depgraph_risk_color` helper needs `$((10#$score))` at this
      call site specifically — `depgraph_report`'s call site uses an
      unpadded score and needs no such fix)
- [x] 2.2 Added `_depgraph_risk_color`; `depgraph_report`'s risk score
      line now colored via `COLOR_HIGH`/`COLOR_WARN`/`COLOR_OK` using the
      existing HIGH(>=RISK_THRESHOLD)/MEDIUM(4-6)/LOW(0-3) thresholds
- [x] 2.3 Added `ui_colorize` to `ui.sh` (pads before coloring — printf's
      `%-Ns` counts raw ANSI escape bytes, so padding after coloring
      would misalign columns). `tests/test_depgraph.sh` now sources
      `core/ui.sh` and overrides `COLOR_OK`/`WARN`/`HIGH` with
      distinguishable sentinel strings (real `tput` colors are empty
      under the test's own non-TTY capture, which would make every band
      look the same); added 3 cases asserting `_depgraph_risk_color`
      picks the right band at 0/6/10

## 3. Migrate cleanup.sh (cleanup score coloring, progress, section)

- [ ] 3.1 `cleanup_report`'s table -> `ui_table_header`/`ui_table_row`,
      SCORE column colored (HIGH cleanup score = `COLOR_OK`, inverted
      from risk score's direction — see design.md)
- [ ] 3.2 `cleanup_scan`/`cleanup_bloat`'s `[N/total]` lines ->
      `ui_progress`
- [ ] 3.3 `cleanup_bloat`'s summary block -> `ui_section`/`ui_summary`
- [ ] 3.4 `why`'s dependents/last-access output -> `ui_section` for its
      header line
- [ ] 3.5 Update `tests/test_cleanup.sh`: strip ANSI before assertions,
      add a case asserting cleanup score color direction (HIGH=green,
      not red)

## 4. Migrate upgrade.sh (progress, summary)

- [ ] 4.1 `run_upgrade`'s `[N/total] ==> brew upgrade` line ->
      `ui_progress`
- [ ] 4.2 `run_upgrade`'s risk warnings (MEDIUM/HIGH) -> colored via the
      same thresholds as `depgraph_report`
- [ ] 4.3 Final "Done."/"Done with N failure(s)" line -> `ui_summary`
- [ ] 4.4 Update `tests/test_cli.sh`, `tests/test_profile.sh`,
      `tests/test_audit.sh`: strip ANSI before assertions on upgrade
      output

## 5. Migrate profile.sh

- [ ] 5.1 `profile_list`'s table -> `ui_table_header`/`ui_table_row`
      (no color — no risk/score value in this table)
- [ ] 5.2 Update `tests/test_profile.sh`: strip ANSI if any color-neutral
      styling is applied, confirm column output unchanged

## 6. Migrate audit.sh

- [ ] 6.1 `_audit_render`'s table -> `ui_table_header`/`ui_table_row`
      (table format only; `csv` format untouched)
- [ ] 6.2 `audit_report`'s title rule -> `ui_section`
- [ ] 6.3 `audit_report`'s upgrade/cleanup/snapshot summary lines ->
      `ui_summary` where it reads as a single end-of-report line
- [ ] 6.4 Update `tests/test_audit.sh`: strip ANSI before assertions

## 7. Migrate snapshot.sh

- [ ] 7.1 `snapshot_list`'s table -> `ui_table_header`/`ui_table_row`
- [ ] 7.2 `snapshot_diff`'s table -> `ui_table_header`/`ui_table_row`,
      TAG column colored (`NEW`=`COLOR_OK`, `REMOVED`=`COLOR_HIGH`,
      upgraded/downgraded=`COLOR_WARN`)
- [ ] 7.3 Update `tests/test_snapshot.sh`: strip ANSI before assertions,
      add a case asserting TAG color per kind

## 8. Verification

- [ ] 8.1 Run the full test suite; confirm no regressions across all 7
      files
- [ ] 8.2 Manually run each affected command in a real TTY (colors
      visible) and piped through `cat` (no escape sequences) to confirm
      the NO_COLOR/non-TTY contract holds everywhere
- [ ] 8.3 `shellcheck` clean on `bin/brewmaster` and
      `lib/brewmaster/**/*.sh`
- [ ] 8.4 Update `ROADMAP.md` M8 status to `[x] done`, noting the actual
      scope (extraction + coloring of existing patterns, not new
      spinner/UI machinery) versus the original plan
