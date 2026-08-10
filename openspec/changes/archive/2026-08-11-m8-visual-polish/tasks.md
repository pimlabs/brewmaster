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

- [x] 3.1 Added `_cleanup_score_color`; `cleanup_report`'s table ->
      `ui_table_header`/`ui_table_row`, SCORE column colored (HIGH
      cleanup score = `COLOR_OK`, inverted from risk score's direction —
      see design.md)
- [x] 3.2 `cleanup_scan`/`cleanup_bloat`'s `[N/total]` lines ->
      `ui_progress`/`ui_progress_clear`. Found a third instance not in
      the original task list: `cleanup_main`'s `--interactive` selection
      loop (building `why` previews for `fzf`) has its own `[N/total]`
      progress line too — migrated that as well
- [x] 3.3 `cleanup_bloat`'s "Machine package report" line -> `ui_section`;
      its closing "Run: brewmaster cleanup --dry-run..." line, and
      `cleanup_main`'s closing "Run with --interactive..." line, ->
      `ui_summary`
- [x] 3.4 Reconsidered after reading `why()`: it's a compact key-value
      output ("Package: x" / "Installed..." / "Dependents..."), not a
      table with a title — wrapping "Package: $pkg" in `ui_section` would
      add a rule line that wasn't there before and doesn't read better.
      Left `why()` unchanged; no section header added
- [x] 3.5 `tests/test_cleanup.sh` sources `core/ui.sh` and overrides
      `COLOR_OK`/`WARN`/`HIGH` with sentinels (same reasoning as
      `test_depgraph.sh`); added 3 cases asserting `_cleanup_score_color`
      picks OK/WARN/HIGH at 8/5/2 — explicitly confirming the inverted
      direction (score 8 -> OK not HIGH, score 2 -> HIGH not OK)

## 4. Migrate upgrade.sh (progress, summary)

- [x] 4.1 Reconsidered after reading the code: `run_upgrade`'s
      `[%d/%d] ==> brew upgrade %s\n` line ends with a real newline and
      stays on screen as a permanent per-package log entry — unlike
      `ui_progress`'s in-place, overwritten-next-iteration contract. The
      leading `\r\033[K` here just defensively clears any stray partial
      line, it isn't the same pattern despite the superficial format
      similarity. Left unchanged rather than forcing it into `ui_progress`
- [x] 4.2 `run_upgrade`'s MEDIUM/HIGH risk warnings -> colored via
      `_depgraph_risk_color` (same thresholds `depgraph_report` uses)
- [x] 4.3 Final "Done."/"Done with N failure(s)" line -> `ui_summary`
- [x] 4.4 No test changes needed: `ui_color_init`'s `[ -t 1 ]` check means
      every `$(...)`-captured test output is already colorless (command
      substitution is never a TTY) — confirmed `test_cli.sh`,
      `test_profile.sh`, `test_audit.sh` still pass unmodified. The
      ANSI-strip mitigation from design.md's Risks section turns out to
      be unnecessary in practice; only the two direct color-function unit
      tests (2.3, 3.5) needed sentinel overrides, and those don't need
      stripping either since they assert exact sentinel equality

## 5. Migrate profile.sh

- [x] 5.1 `profile_list`'s table -> `ui_table_header`/`ui_table_row`
      (no color — no risk/score value in this table)
- [x] 5.2 No ANSI-stripping needed (see 4.4); `tests/test_profile.sh`
      passes unmodified, column output confirmed unchanged

## 6. Migrate audit.sh

- [x] 6.1 `_audit_render`'s table -> `ui_table_header`/`ui_table_row`
      (table format only; `csv` format untouched)
- [x] 6.2 `audit_report`'s title rule -> `ui_section` (replaces the
      original one-off `printf '─%.0s' $(seq 1 ${#header})`, the exact
      pattern `ui_section` generalizes)
- [x] 6.3 Reconsidered after reading the code: `audit_report`'s
      upgrade/cleanup/snapshot/orphans/avg-risk lines are five metric
      rows in one aligned block, not one final wrap-up line — there's no
      single line that reads as "the summary" the way `cleanup_bloat`'s
      closing hint line did. Left the metrics block as plain `printf`,
      no `ui_summary` applied
- [x] 6.4 No ANSI-stripping needed (see 4.4); `tests/test_audit.sh`
      passes unmodified

## 7. Migrate snapshot.sh

- [x] 7.1 `snapshot_list`'s table -> `ui_table_header`/`ui_table_row`
- [x] 7.2 Reconsidered scope: `snapshot_diff` was never a header+rule+rows
      table (no header row at all) and its row format mixes fixed
      decoration (`  ->  `, `[...]`) with padded columns in a shape
      `ui_table_row` doesn't fit cleanly. Left the `printf` structure
      as-is and applied `ui_colorize` only to the TAG value (the actual
      goal): added `_snapshot_tag_color` (`NEW`=`COLOR_OK`,
      `REMOVED`=`COLOR_HIGH`, `UPGRADE`/`DOWNGRADE`/`CHANGED`=`COLOR_WARN`)
- [x] 7.3 `tests/test_snapshot.sh` sources `core/ui.sh` and overrides
      `COLOR_OK`/`WARN`/`HIGH` with sentinels; confirmed existing
      `grep -q 'REMOVED'`-style substring assertions still pass (the
      sentinel text concatenates right before the tag, e.g.
      "HIGHREMOVED", which still contains "REMOVED"). Added 4 cases
      asserting `_snapshot_tag_color` per tag

## 8. Verification

- [x] 8.1 Full test suite: all 7 files pass, 256 assertions, 0 failures
- [x] 8.2 Verified with a real pty (`script -q /dev/null`): `deps show`
      shows an actual `ESC[32m` (green) sequence around a LOW risk score
      on a real TTY, zero ESC bytes with `NO_COLOR=1` even on that same
      real TTY, and zero ESC bytes on stdout when piped (`grep -c $'\x1b'`
      confirmed empty in both suppressed cases)
- [x] 8.3 `shellcheck` clean on `bin/brewmaster` and every
      `lib/brewmaster/**/*.sh` file, including the new `core/ui.sh`
- [x] 8.4 `ROADMAP.md` M8 status and scope description updated to reflect
      the actual work (extraction + coloring of already-existing
      patterns, not new spinner/UI machinery) versus the original plan
