## Why

The `fzf` multi-select shipped in M4 (`cleanup --interactive`) and M7
(`upgrade`'s review gate) never matched the UI its own frozen design
documented. `docs/ARCHIVE_ROADMAP.md` already specifies, for both
commands, `[x]`/`[ ]` checkbox markers, a `ctrl-a: select all` /
`ctrl-d: deselect` key row, and a visible risk score per row
(ARCHIVE_ROADMAP.md:355-372 for upgrade, :478-495 for cleanup).

What actually shipped is a bare `fzf --multi --ansi` with no `--bind`,
no `--marker`, no `--pointer`, and no `--height`. Three consequences,
in descending order of severity:

1. **The header advertises a key that is not bound.** Both call sites
   print `ctrl-a: all` (`lib/brewmaster/upgrade.sh:140`,
   `lib/brewmaster/cleanup.sh:346`) while `ctrl-a` remains bound to
   fzf's default `beginning-of-line`. The advertised action does not
   exist.

2. **Enter with nothing marked upgrades exactly one package.**
   `fzf --multi` returns the line under the cursor when no item is
   marked. A user who runs `brewmaster --minor`, sees the candidate
   list, and presses Enter to confirm the batch gets a single-package
   upgrade instead. This contradicts the documented contract in
   `--help`: *"candidates are always shown for review... a single
   `[y/N]` for the whole batch"*.

3. **The two selection models disagree.** With `fzf` installed,
   `upgrade` starts with zero candidates selected (opt-in). Without
   `fzf`, it asks `Upgrade all? [y/N]` (opt-out, everything). The same
   command presents two different mental models depending on whether an
   optional dependency happens to be installed. This is the root of the
   "does not feel like a normal CLI checklist" report that prompted
   this milestone.

Underneath all three: the `fzf` invocation is hand-rolled twice, in two
files, with no shared contract binding the header text to the keys
actually bound. That is the same duplication M8 removed for tables and
progress lines by introducing `lib/brewmaster/core/ui.sh` — the
selection UI is the one interactive surface that pass did not reach.

## What Changes

- **New shared picker helper** in `lib/brewmaster/core/ui.sh`. It owns
  every `fzf` option both call sites need, and — critically — derives
  the displayed key header from the binds it actually applies, so a
  header can never again advertise a key that is not bound.
- **`upgrade` review gate becomes opt-out**: all candidates start
  selected, the user deselects what they do not want. This matches the
  no-`fzf` `[y/N]` fallback, removing the model split, and makes the
  Enter-with-no-marks trap unreachable.
- **`cleanup --interactive` stays opt-in** (nothing preselected).
  Removal is destructive; per AGENTS.md convention 10 it stays explicit. The
  helper takes the preselect mode as an argument rather than assuming
  one.
- **Checkbox markers and inline layout** for both: `[x]`/`[ ]`-style
  marker distinct from the cursor pointer, and `--height`/`--layout`
  so the picker renders inline instead of taking over the alternate
  screen and erasing the risk warnings printed moments earlier.
- **Risk score becomes visible in the `upgrade` picker.** The score is
  already computed and carried in `upgrade_meta` but never reaches the
  row the user reads while deciding. ARCHIVE_ROADMAP's mockup shows it.
- **`cleanup --interactive` gains a no-`fzf` fallback** (table plus a
  single `[y/N]`), replacing today's hard `exit 1`. **This one
  contradicts a frozen M4 contract and a frozen test — see design.md
  "Frozen contract conflict". It needs an explicit maintainer decision
  before implementation, and is isolated to its own task so it can be
  dropped without affecting the rest.**

## Out of Scope

- **A hand-rolled checklist UI that does not need `fzf`.** Raw-mode
  terminal handling for arrow keys and redraw is ~150 lines of fragile
  code to reimplement what `fzf` already does. `fzf` stays optional;
  the non-`fzf` path stays a table plus `[y/N]`.
- **Changing what `--dry-run` or `--yes` do.** Both keep their M7
  bypass behavior exactly.
- **Colorizing the picker rows beyond the risk score.** `--ansi` is
  already passed and currently a no-op; this milestone makes it carry
  the risk score only, not a general row-coloring scheme.
- **Preview panes for `upgrade`.** ARCHIVE_ROADMAP:371 sketches one
  ("dependent list, risk score, last version bump date"); building it
  means computing per-package data for every candidate up front, the
  same cost profile M6 flagged as unresolved. Not this milestone.
- **The `cleanup_scan` `jq` bottleneck** left open by M6
  (ROADMAP.md:130-135). Unrelated to selection UX.

## Capabilities

### New Capabilities

- `interactive-select`: a single contract for every `fzf`-backed
  multi-select in the CLI — marker and pointer distinct from each
  other, inline height, binds that match the advertised header,
  caller-chosen preselect mode, and a documented degradation path when
  `fzf` is absent or too old to support a requested bind.

### Modified Capabilities

- `upgrade-checklist`: the review gate's `fzf` branch changes from
  opt-in to opt-out, gains a risk-score column, and routes through
  `interactive-select` instead of calling `fzf` directly. The existing
  requirements about *when* the gate runs (`--dry-run`, `--yes`, zero
  candidates) are unchanged.

## Impact

- `lib/brewmaster/core/ui.sh` — new picker helper and its `fzf`
  capability probe
- `lib/brewmaster/upgrade.sh` — review gate consumes the helper;
  risk score added to the displayed row
- `lib/brewmaster/cleanup.sh` — `--interactive` consumes the helper;
  no-`fzf` fallback (contested task only)
- `bin/brewmaster`, `lib/brewmaster/core/help_data.sh` — help text for
  the review gate now describes opt-out selection
- `docs/brewmaster.1`, `tests/fixtures/help*.txt` — regenerated, since
  help text changes
- `tests/test_audit.sh`, `tests/test_profile.sh`, `tests/test_cleanup.sh`
  — the `fzf` mocks assert selection filtering, not selection *defaults*
  or key binds; both need coverage
