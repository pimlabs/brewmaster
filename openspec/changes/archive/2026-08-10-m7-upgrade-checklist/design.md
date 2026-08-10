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

- **The fallback prompt reads from plain stdin (`read -r ans`), not
  `/dev/tty`.** The two existing prompts in this file (MEDIUM-risk,
  profile-confirm) need `</dev/tty` because they run inside
  `while ... done <<<"$out"` — the herestring redirects stdin for the
  whole loop body, so a plain `read` there would consume `brew outdated`
  output instead of a real answer. The new review-gate prompt runs after
  that loop has already finished, so it isn't affected and can read real
  stdin directly — matching the plain `read -r ans` already used in
  `snapshot.sh`'s delete confirmation, and making it possible to test by
  piping input instead of needing a real controlling terminal.

## Risks / Trade-offs

- **[Risk] Breaks unattended callers (cron, CI, scripts) that run
  `brewmaster --minor` (or similar) today without `--yes`.** Today that
  works with zero prompts; after this change, the review step needs an
  answer from stdin. With `fzf` installed but no real terminal, `fzf`
  itself will error; without `fzf` and with stdin closed/empty (the
  common unattended case), `read` hits EOF, the answer doesn't match
  `y`/`Y`, and the run safely declines ("Nothing selected.") rather than
  upgrading anything. **Mitigation**: failing safe (decline, not silently
  upgrade) is the best available outcome short of abandoning the "review
  by default" goal — but it still means unattended callers get nothing
  upgraded instead of what they had before (unprompted, always-upgrade).
  Worth calling out prominently in the changelog/release notes when this
  ships, so existing automation gets fixed (`--yes` added) rather than
  silently doing nothing.

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
