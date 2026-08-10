## Context

`run_upgrade` (`lib/brewmaster/upgrade.sh:26-191`) already builds the full
`upgrade_list`/`report_rows` before doing anything else — candidates are
not confirmed one at a time. Today's actual gaps, versus what the M7
milestone describes:

- The `fzf` multi-select review (lines 109-141) only runs when
  `$INTERACTIVE` is true (`--interactive`/`-i`), and if `fzf` isn't
  installed in that path it `exit 1`s instead of falling back.
- Without `-i`, there is no batch-level confirmation at all — execution
  (lines 153-190) starts right after printing the candidate list.
- `--yes`/`-y` (`$YES_FLAG`) currently only suppresses two conditional
  per-package prompts (MEDIUM-risk warning, profile-require-confirm); it
  has no effect on the (nonexistent) batch confirmation.

## Goals / Non-Goals

**Goals:**
- Make the review-and-confirm step the default for every `upgrade`
  invocation that has candidates and isn't `--dry-run` or `--yes`.
- `fzf` multi-select when available; plain table + single `[y/N]` prompt
  otherwise (no more hard `exit 1` on missing `fzf`).
- `--yes` skips the review step entirely, preserving today's "just run"
  behavior for scripts that opt in.
- Keep the existing MEDIUM-risk/profile-confirm prompts (under
  `--check-deps`) exactly as they are — they run during candidate
  collection, before the new review step, and are unaffected by it.

**Non-Goals:**
- Not touching `cleanup`'s `--interactive`/`--force` behavior — this
  proposal is scoped to `upgrade` only.
- Not adding new risk-scoring or filtering logic — the review step
  operates on the same `upgrade_list`/`report_rows` already computed.
- Not changing `--dry-run`'s output (it already shows the full table and
  exits before any prompt).

## Decisions

- **Review is default, `--yes` is the opt-out — not the other way
  around.** Matches `cleanup_main`'s existing shape (default is
  look-before-you-act; `--force`/`--interactive` are how you actually act
  there). Consistency with an established in-repo pattern outweighs
  strict backward compatibility here, but the compatibility cost is real
  (see Risks) and is called out as **BREAKING** in the proposal.

- **`--interactive`/`-i` becomes a no-op for `upgrade`, not removed.**
  Removing it outright would break any script that already passes `-i`
  expecting the old opt-in behavior; keeping it as an accepted-but-inert
  flag for `upgrade` is the smaller change. It keeps its real meaning for
  `cleanup`, which is untouched here.

- **Non-`fzf` fallback is a single `[y/N]` for the whole batch, not a
  per-package prompt.** A per-package fallback would reintroduce exactly
  the "confirm one at a time" problem this milestone exists to remove.
  The `fzf` path lets a user deselect individual packages; the fallback
  trades that granularity for one prompt, consistent with the
  `checklist_select` contract in `ROADMAP.md` ("Degrades gracefully
  without fzf: print table, single y/N prompt").

- **Reuse the existing `read -r ans </dev/tty` pattern** already used for
  the MEDIUM-risk and profile-confirm prompts in this file, rather than
  inventing a second confirmation mechanism. Consistent within the file;
  also means the new prompt fails the same way those already do when
  there's no controlling TTY (see Risks).

## Risks / Trade-offs

- **[Risk] Breaks unattended callers (cron, CI, scripts) that run
  `brewmaster --minor` (or similar) today without `--yes` and without a
  TTY.** Today that works with zero prompts; after this change, the
  review step tries to read from `/dev/tty`, which doesn't exist in that
  context, and the read fails. **Mitigation**: this is the explicit
  trade-off the proposal makes (see BREAKING note); it can't be fully
  mitigated without abandoning the "review by default" goal. Worth
  calling out prominently in the changelog/release notes when this ships,
  so existing automation gets fixed (`--yes` added) rather than silently
  failing.

- **[Risk] `--interactive`/`-i` becoming inert for `upgrade` is a silent
  behavior change** — a script that still passes `-i` expecting the old
  "only review when I ask" semantics will now always get reviewed).
  **Mitigation**: covered by the same BREAKING note above; no separate
  fix needed since the net effect (review happens) is a superset of what
  `-i` used to opt into.

- **[Risk] `fzf` multi-select and the plain fallback must produce the
  same `upgrade_list`/`report_rows`/`upgrade_meta` narrowing.** A bug
  here could silently upgrade the wrong set of packages.
  **Mitigation**: both paths funnel through the same selection-filtering
  logic already used for the `fzf` case (lines 125-140), just fed by a
  different selector when `fzf` is absent.

## Migration Plan

No data migration. This is a CLI default-behavior change, not a storage
or API change — see the proposal's Impact section for what to update
(help text, one existing test). Document the breaking change in the next
release notes (version bump to `v0.8.0` per `ROADMAP.md`). Rollback is a
plain revert if needed.

## Open Questions

None blocking — scope was confirmed with the user before writing this
document (checklist-by-default over interactive-opt-in).
