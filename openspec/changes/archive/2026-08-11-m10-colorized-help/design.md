## Context

`bin/brewmaster`'s help styling is currently bold/underline/dim only,
computed by `_help_style_vars` (sets `B`/`R`/`U`/`UR`/`D` from `tput`,
predates `ui.sh`) and applied by `_help_style_name`/`_help_style_desc`/
`_help_render_line`. `usage()` and `help_command()` both call
`_help_style_vars` and render through `_help_render_line` — the shared
path M9 built so both surfaces stay in sync.

`ui.sh` (M8) already has a working `NO_COLOR`/non-TTY/no-`tput`
degradation check in `ui_color_init`, and four semantic constants:
`COLOR_OK` (green), `COLOR_WARN` (yellow), `COLOR_HIGH` (red),
`COLOR_MUTED` (dim), `COLOR_RESET`. It is sourced and initialized late in
`bin/brewmaster` (`source core/ui.sh` then `ui_color_init`, both after
argument parsing, around the module-sourcing block) — too late for
`usage()`/`help_command()`, which can run before argument parsing even
starts (`-h`/`--help` inside the parse loop, and the unknown-command
error path before the parse loop begins). M9 hit this exact ordering
problem for `help_data.sh` and fixed it by moving `LIB_DIR` resolution
and that one `source` call to the top of the file. The same fix applies
here for `ui.sh`.

`COLOR_OK`/`WARN`/`HIGH` are score-semantic (tied to risk/cleanup
thresholds elsewhere in the codebase) — reusing green/yellow/red for
decorative help elements would create a false semantic association (a
flag colored the same green as a "safe" cleanup score implies a meaning
it doesn't have). `COLOR_MUTED`, on the other hand, is not
score-semantic — it's `tput dim`, general de-emphasis, and it happens to
be exactly what `_help_style_desc`'s local `D` already does independently
today.

## Goals / Non-Goals

**Goals:**
- Real ANSI color for `--help`/`help [command]` section headers and
  command/flag names, layered on top of (not replacing) the existing
  bold/underline.
- One color definition surface (`ui.sh`), not a second parallel color
  system living in `bin/brewmaster` — matching the "single source, no
  duplication" principle M9 already established for help *content*.
- Zero change to `NO_COLOR`/non-TTY/no-`tput` output — `tests/fixtures/
  help*.txt` stay byte-identical.
- New decorative colors stay visually and semantically distinct from
  `COLOR_OK`/`WARN`/`HIGH` — no green/yellow/red reuse.

**Non-Goals:**
- No change to help *content*, wording, or which commands/flags are
  documented — that's M9's territory, already shipped.
- No change to `docs/gen-man.sh`/`docs/brewmaster.1` — troff has no ANSI
  concept, this is a TTY-only concern.
- No full unification of `_help_style_vars` and `ui_color_init` into one
  function — see Decision 3 for why.

## Decisions

### 1. New decorative colors live in `ui.sh`, not locally in `bin/brewmaster`

Add two new constants to `ui_color_init`: `COLOR_HEADER` (cyan,
`tput setaf 6`) for section headers, `COLOR_COMMAND` (blue,
`tput setaf 4`) for command/flag name-tokens. Both are visually and
numerically distinct from `COLOR_OK`(2)/`WARN`(3)/`HIGH`(1), so there is
no accidental overlap with the semantic risk/cleanup palette anywhere in
the same terminal session.

**Alternative considered:** define `COLOR_HEADER`/`COLOR_COMMAND` locally
in `bin/brewmaster`, next to `_help_style_vars`. Rejected: this recreates
exactly the "two independent copies of the same kind of thing" pattern
M9's `help_data.sh` extraction was built to eliminate, just for colors
instead of content. `ui.sh` already states its own purpose as the shared
color surface for the whole CLI; help text is part of the CLI.

### 2. Source `ui.sh` and call `ui_color_init` early, alongside `help_data.sh`

Move `source "$LIB_DIR/core/ui.sh"` and the `ui_color_init` call from
their current late position (after argument parsing) to right after
`source "$LIB_DIR/core/help_data.sh"` at the top of the file. This is
safe: `ui_color_init` only sets five (soon seven) global string
variables with no side effects beyond that, so calling it earlier does
not change behavior for any of its existing late callers (`deps show`,
`cleanup`, `snapshot diff`, etc.) — they still read the same
already-set globals whenever they run later in the same process.

**Verification required before this lands:** confirm no code between the
old and new call sites reads `COLOR_*` before `ui_color_init` used to run
(the risk/cleanup-score colorers in `depgraph.sh`/`cleanup.sh` are only
invoked from command dispatch, which is always after this point either
way — moving the init earlier only ever makes the globals available
*sooner*, never later, so this should be a no-risk move, but tasks.md
must run the full existing test suite to confirm).

### 3. `_help_style_vars` keeps its own bold/underline vars; only the dim path is unified

`_help_style_vars` still independently sets `B`/`R`/`U`/`UR` (bold,
reset, underline-on, underline-off) — `ui.sh` has no bold/underline
equivalents, so there's nothing to unify there, and duplicating a
4-line TTY/`NO_COLOR`/`tput` check twice in the same file is a small,
acceptable cost versus a larger merge that would touch already-tested
bold/underline behavior for no behavioral gain.

`_help_style_desc`'s local `D` (dim) IS a duplicate of `COLOR_MUTED`
(`tput dim`) once `ui.sh` is sourced early — replace `_help_style_desc`'s
use of `$D`/`$R` with `$COLOR_MUTED`/`$COLOR_RESET` and drop `D` from
`_help_style_vars`. One less parallel copy, zero behavior change (same
`tput dim` sequence either way).

**Alternative considered:** fully merge `_help_style_vars` into
`ui_color_init` (one init function for everything). Rejected as
disproportionate for this change — `_help_style_vars`'s bold/underline
logic is help-specific and not needed by `ui.sh`'s other callers
(tables/progress/scores never use bold or underline); forcing them into
one function couples two things that don't need to be coupled.

### 4. Color mapping: headers and command/flag names only, placeholders stay underline-only

- Section headers (`UPGRADE`, `DEPENDENCY RISK`, …): bold (unchanged) +
  `COLOR_HEADER` (new).
- Command/flag name-tokens (`upgrade`, `--dry-run`, …), via
  `_help_style_name`: bold (unchanged) + `COLOR_COMMAND` (new).
- `<placeholder>`/`[placeholder]` groups inside a name-token: underline
  only (unchanged) — no color added.
- Parenthetical annotations (`(default: patch)`, `(requires fzf)`):
  `COLOR_MUTED` (was local dim, now shared, see Decision 3) — unchanged
  visually.

**Alternative considered:** color placeholders too (a third accent
color). Rejected: restraint reads as "modern" (this is the look most
current CLI tools — `rg --help`, `bat --help` — actually use, two accent
colors plus one muted tone), where a third arbitrary hue for placeholders
starts to look busy without adding information; underline already
distinguishes them from surrounding text on both a color and a plain
terminal.

## Risks / Trade-offs

- **[Risk]** Moving `ui.sh`'s sourcing/init earlier could theoretically
  interact with some later code path in an unexamined way.
  **Mitigation:** `ui_color_init` is a pure global-variable setter with
  no other side effects (confirmed by reading `ui.sh` in full) — this
  class of risk is the same one M9 already accepted for `help_data.sh`'s
  identical early-sourcing move, and the full test suite is the
  guardrail either way.
- **[Risk]** `COLOR_HEADER`/`COLOR_COMMAND` are new globals with no
  existing test coverage for their color-selection logic.
  **Mitigation:** follow the same sentinel-override pattern already used
  in `tests/test_depgraph.sh`/`test_cleanup.sh`/`test_snapshot.sh`
  (override `COLOR_*` with distinguishable string sentinels after
  `ui_color_init` runs, since a test's own command substitution is never
  a TTY and would otherwise make every color path look identical/empty).
- **[Trade-off]** Two independent TTY/`NO_COLOR`/`tput` checks
  (`_help_style_vars` and `ui_color_init`) remain in the codebase instead
  of one. Accepted per Decision 3 — the two init functions serve
  genuinely different purposes (bold/underline vs. color) and forcing a
  merge would touch more tested surface than this change needs to.

## Open Questions

None outstanding — color choice, ownership location, and the early-init
mechanism are all settled above, following the same pattern M9 already
proved out for content sharing.
