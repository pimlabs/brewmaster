## 1. ui.sh module

- [ ] 1.1 Create `lib/brewmaster/core/ui.sh` with `ui_color_init`
      (`COLOR_OK`/`COLOR_WARN`/`COLOR_HIGH`/`COLOR_MUTED`/`COLOR_RESET`,
      suppressed under `NO_COLOR`/non-TTY/no-`tput`, mirroring
      `bin/brewmaster`'s existing `_help_style_vars` detection)
- [ ] 1.2 Add `ui_table_header "$w1" "$label1" ...` / `ui_table_row "$w1"
      "$val1" ...` — width/value pairs, dashed rule row on header
- [ ] 1.3 Add `ui_progress "$current" "$total" "$label"` — extract the
      existing `printf '\r\033[K[%d/%d] %s'` pattern, byte-identical
      output
- [ ] 1.4 Add `ui_section "$title"` — title + `─` rule matching title
      length (generalizes `audit_report`'s existing rule)
- [ ] 1.5 Add `ui_summary "$msg"` — consistent end-of-command summary
      line wrapper
- [ ] 1.6 Source `core/ui.sh` from `bin/brewmaster` alongside the other
      `core/*.sh` modules

## 2. Migrate depgraph.sh (risk score coloring)

- [ ] 2.1 `depgraph_list_risky`'s table -> `ui_table_header`/`ui_table_row`
- [ ] 2.2 `depgraph_report`'s risk score line -> colored via
      `COLOR_HIGH`/`COLOR_WARN`/`COLOR_OK` using the existing
      HIGH/MEDIUM/LOW thresholds
- [ ] 2.3 Update `tests/test_depgraph.sh`: strip ANSI before string
      assertions, add a case asserting the correct color constant per
      risk band

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
