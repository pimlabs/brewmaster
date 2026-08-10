## Why

`run_upgrade` already collects every upgrade candidate upfront (not a
per-package sequential prompt, as the milestone was originally scoped) and
already has an `fzf` multi-select path — but only behind the opt-in
`--interactive`/`-i` flag, and that path hard-exits (`exit 1`) if `fzf`
isn't installed instead of degrading gracefully. Without `-i`, `brewmaster
--minor` upgrades everything immediately with **no confirmation at all** —
the only existing prompts are conditional per-package risk warnings under
`--check-deps`, not a review of the whole batch.

That's inconsistent with how `cleanup` already works in this codebase:
`cleanup_main`'s default is a read-only report, and it takes explicit
`--force` or `--interactive` to actually remove anything. `upgrade` should
follow the same shape — review before action is the default, `--yes` is
the explicit opt-out for scripts/automation.

## What Changes

- **BREAKING**: the upgrade review/confirm step becomes the default for
  `run_upgrade`, not opt-in via `--interactive`. Running `brewmaster
  --minor` (or any upgrade invocation) with candidates and without
  `--yes` now stops for review instead of upgrading immediately.
  Unattended callers (cron, scripts) that relied on today's "no prompt by
  default" behavior must add `--yes` or they will fail when the review
  step can't reach a controlling TTY.
- The review step reuses the existing `fzf` multi-select when `fzf` is
  installed; when it isn't, it degrades to printing the candidate table
  plus a single `[y/N]` prompt for the whole batch, instead of the current
  hard `exit 1`.
- `--yes`/`-y` gains a second meaning: in addition to auto-confirming
  MEDIUM-risk packages (existing behavior, unchanged), it now also skips
  the review step entirely and upgrades all collected candidates — this
  is what preserves today's "just run" behavior for automation.
- `--interactive`/`-i` becomes a no-op for `upgrade` specifically (review
  is now unconditional there); it keeps its existing meaning for
  `cleanup`, which this proposal does not touch.
- `--dry-run` behavior is unchanged: it already prints the full candidate
  table and exits before any prompt or execution.

## Capabilities

### New Capabilities
- `upgrade-checklist`: default review-and-confirm gate before executing
  upgrades — `fzf` multi-select when available, a plain table + single
  `[y/N]` fallback otherwise, bypassed entirely by `--yes`.

### Modified Capabilities
(none — no existing `openspec/specs/` entry covers `upgrade` today; this
is the first spec written for it)

## Impact

- **Affected code**: `lib/brewmaster/upgrade.sh` (`run_upgrade`'s review
  gate), `bin/brewmaster` (help text for `--interactive`/`-i` and
  `--yes`/`-y` under UPGRADE).
- **Affected commands**: `brewmaster` / `brewmaster upgrade` (default
  command) — behavior change as described above. `cleanup`, `snapshot`,
  `profile` are unaffected.
- **Tests**: `tests/test_cli.sh`'s existing non-dry-run execution test
  needs `--yes` added (it currently relies on the no-prompt default);
  `tests/fixtures/help.txt` needs regenerating for the updated help text.
- **No dependency, config, or storage-format changes.**
