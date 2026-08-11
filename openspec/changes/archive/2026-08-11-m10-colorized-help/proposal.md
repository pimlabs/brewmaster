## Why

`--help` and `brewmaster help [command]` style with bold/underline/dim
only (`_help_style_vars`/`_help_style_name`/`_help_style_desc` in
`bin/brewmaster`), a scheme that predates `ui.sh` and was never given real
ANSI color. Every other command's output got color in M8. The help
reference is the one surface still visually flat next to the rest of the
CLI, and the user asked for it to look modern and colorful to match.

## What Changes

- Section headers, command names, flags, and placeholders in `--help`
  and `brewmaster help [command]` gain real ANSI color on a TTY, on top
  of the existing bold/underline/dim (not a replacement for it).
- `NO_COLOR`, non-TTY, and no-`tput` environments continue to produce
  today's byte-identical plain text — `tests/fixtures/help*.txt` stay
  pinned exactly as they are.
- `docs/brewmaster.1` (troff, no ANSI concept) is untouched.
- No change to help *content* — this is styling only, not a repeat of
  M9's `command-help`/`man-page-generation` work.

## Capabilities

### New Capabilities
- `help-color`: real ANSI color for `--help`/`help [command]` structural
  elements (section headers, command names, flags, placeholders),
  decorative rather than semantic (no score/status meaning, unlike
  `ui-output`'s `COLOR_OK`/`WARN`/`HIGH`/`MUTED`), with the same
  `NO_COLOR`/non-TTY/no-`tput` degradation guarantee every other color
  surface in this project already has.

### Modified Capabilities
(none — `ui-output`'s existing requirements are semantic/score-based and
stay as they are; `command-help`'s existing requirements are about
content, not styling, and this change doesn't alter content)

## Impact

- `bin/brewmaster` — `_help_style_vars`, `_help_style_name`,
  `_help_style_desc`, `_help_render_line` (or their replacement)
- Possibly `lib/brewmaster/core/ui.sh` — if new decorative color
  constants live there instead of staying local to `bin/brewmaster`
  (design decision, not settled here)
- `tests/fixtures/help*.txt` — must remain unaffected under `NO_COLOR`
- No change to `docs/gen-man.sh`/`docs/brewmaster.1`, `help_data.sh`'s
  source text, or any command's actual behavior
