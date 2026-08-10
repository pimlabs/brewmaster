## Context

Five files each independently format aligned tables the same shape
(header row, dashed underline row matching header width, data rows):
`profile.sh:109-115`, `audit.sh:72-79`, `depgraph.sh:158-163`,
`cleanup.sh:193-199`, `snapshot.sh:96-112,138-163`. Two files independently
format an in-place `[N/total]` progress line: `cleanup.sh:146,320,382`,
`upgrade.sh:184`. `audit.sh:122-124`'s `audit_report` already draws a
title-width `─────` rule under its header — closest thing to a "section
header" in the codebase today, but it's a one-off, not reusable.
`bin/brewmaster:36-50` already has a correct `NO_COLOR`/non-TTY/no-`tput`
detection pattern (`_help_style_vars`), but it only sets bold/underline/
dim variables for `--help`, never actual colors, and nothing outside
`--help` reads it.

Risk levels are already numerically thresholded in two places with the
same LOW/MEDIUM/HIGH bands (0-3 / 4-6 / 7-10): `depgraph.sh`'s
`depgraph_risk_score` (used by `upgrade.sh`'s MEDIUM-warn/HIGH-skip logic
and `deps show`) and `cleanup.sh`'s `cleanup_score_from_facts` (used by
`cleanup`/`why`/`bloat`). Neither is ever rendered with color today.

## Goals / Non-Goals

**Goals:**
- One shared module (`lib/brewmaster/core/ui.sh`) for color constants,
  table rendering, progress lines, section headers, and summary lines.
- Every existing hand-rolled instance of these patterns migrates to the
  shared module — no duplicate formatting logic left behind.
- Risk/score values get color (LOW=green, MEDIUM=yellow, HIGH=red),
  reusing the thresholds already defined in `depgraph.sh`/`cleanup.sh`,
  not redefining them in `ui.sh`.
- Colors and box-drawing characters are suppressed exactly the way
  `--help` already suppresses bold/underline/dim: `NO_COLOR` set, stdout
  not a TTY, or no `tput` available.

**Non-Goals:**
- Not touching `bin/brewmaster`'s existing `--help` styling
  (`_help_style_vars`, `_help_style_name`, `_help_style_desc`) — it
  already works and isn't part of this milestone's gap. `ui.sh` may be
  informed by its detection pattern but doesn't replace it.
- Not adding a background/animated spinner. The existing `[N/total]`
  progress line already gives more information than a spinner would
  (exact position, not just "working") and is proven in production;
  `ui.sh` extracts it into a shared helper rather than replacing it with
  new machinery.
- Not changing any command's flags, exit codes, or the underlying data
  shown — this is presentation-only.
- Not touching `snapshot.sh`'s restore confirmation prompt or other
  non-tabular interactive text.

## Decisions

- **`ui_color_init` extends the existing `bin/brewmaster` detection
  pattern rather than reimplementing it.** Same three suppression
  conditions (`NO_COLOR` set, `command -v tput` missing, stdout not a
  TTY), same `tput`-based approach, but adds `tput setaf {1,2,3}` for
  actual red/green/yellow alongside bold/reset — `_help_style_vars`
  stays as-is for `--help`, `ui_color_init` is the general-purpose
  version other commands need.

- **Colors are semantic (`COLOR_OK`/`COLOR_WARN`/`COLOR_HIGH`/
  `COLOR_MUTED`/`COLOR_RESET`), not numeric.** Callers decide which
  color applies to their own value using their own existing thresholds —
  `ui.sh` doesn't know that 7 is "HIGH" for one caller's scale and would
  be meaningless for another's. This matters because `cleanup_score` and
  `depgraph_risk_score` both run 0-10 but mean opposite things: a HIGH
  *risk* score is dangerous (red), while a HIGH *cleanup* score means
  safer to remove (green). Baking numeric thresholds into `ui.sh` would
  get this backwards for one of the two callers.

- **Progress helper matches the existing `[N/total]` shape exactly
  (`ui_progress "$i" "$total" "$label"`), not a new spinner API.** See
  Non-Goals — this is extraction, not redesign.

- **Table helper takes explicit column widths per call
  (`ui_table_header "$w1" "$label1" "$w2" "$label2" ...` /
  `ui_table_row "$w1" "$val1" "$w2" "$val2" ...`), not a fixed schema.**
  The five existing tables have five different column layouts (2 to 4
  columns, widths from 5 to 24) showing genuinely different data: there's
  no single shape to standardize on, only a shared *mechanism* (build the
  header, build a matching dashed rule, print aligned rows) worth sharing.

- **`ui_section` reuses `audit_report`'s existing rule-matches-title-width
  approach**, generalized: `ui_section "$title"` prints the title then a
  `─` rule of the same length (not a fixed 40-column bar), so it degrades
  sensibly for both short and long titles.

## Risks / Trade-offs

- **[Risk] Touching six files' output functions in one milestone is a
  wide, mechanical-but-invasive change** — every existing test asserting
  on exact output strings needs an ANSI-strip pass, and any width
  mismatch between the old hand-rolled `printf` and the new shared
  helper would silently reflow a table. **Mitigation**: migrate one file
  at a time (see tasks.md's grouping), run that file's test after each
  migration before moving to the next, and keep each table's *column
  widths* identical to what they are today — this is a rendering-path
  change, not a redesign of what each table shows.

- **[Risk] `cleanup_score` and `depgraph_risk_score` coloring is easy to
  get backwards** (see Decisions) — a HIGH cleanup score should be green
  (safe to remove), a HIGH risk score should be red (dangerous to
  upgrade). **Mitigation**: each caller passes an explicit semantic
  color constant (`COLOR_OK`/`COLOR_WARN`/`COLOR_HIGH`), never a raw
  number into `ui.sh`; tests assert on the actual color constant used
  per call site, not just "color present".

- **[Risk] Terminal width assumptions in `ui_section`'s rule length**
  could look wrong on very narrow terminals. **Mitigation**: match
  `audit_report`'s existing approach (rule matches title length, not
  terminal width) — already proven not to need `tput cols`.

## Migration Plan

No data migration — presentation-only. Roll out file by file (`ui.sh`
first, then each consumer) so a partial merge still leaves the tool
working; each file's own test suite is the gate before moving to the
next. Rollback is a plain revert per file if a particular migration
causes issues. Version bump to `v0.9.0` per `ROADMAP.md`.

## Open Questions

None blocking — scope (full refactor across all six files, not a
narrower color-only patch) was confirmed with the user before writing
this document.
