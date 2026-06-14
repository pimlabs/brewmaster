# ROADMAP — brewmaster

> **For AI coding assistants (Claude Code and others):** v1 (M0-M5) is complete and frozen — see [`docs/ARCHIVE_ROADMAP.md`](docs/ARCHIVE_ROADMAP.md) for milestone history and frozen function contracts referenced by `tests/`.
> Do not modify v1 function contracts or implement features outside the scope below.
> Propose changes as an issue, or under the relevant planning section, before implementing.
> Do not add Co-authored-by or any AI tool attribution to commits.
> Coding conventions: see [AGENTS.md](AGENTS.md).

---

## Project Context

`brewmaster` is a CLI tool for selective package upgrades based on semver classification.
Core logic lives in `bin/brewmaster`, modularized across `lib/brewmaster/core/`.

**Stack:** Bash (POSIX-compatible where possible), `jq`, `fzf` (optional)
**Target OS:** macOS (Homebrew)
**Distribution:** `brew tap pimlabs/brewmaster`

See [PHILOSOPHY.md](PHILOSOPHY.md) for design rationale and the test for evaluating new features.

---

## Status

| Milestone                         | Version | Status      |
| --------------------------------- | ------- | ----------- |
| M0 — Refactor & Foundation        | v0.1.0  | `[x] done`  |
| M1 — Snapshot & Rollback          | v0.2.0  | `[x] done`  |
| M2 — Dependency Graph Awareness   | v0.3.0  | `[x] done`  |
| M3 — Profile System               | v0.4.0  | `[x] done`  |
| M4 — Cleanup & Intent             | v0.5.0  | `[x] done`  |
| M5 — Audit Log & Report           | v0.6.0  | `[x] done`  |
| M6 — Reliability & Correctness    | v0.7.0  | `[x] done`  |
| M7 — Polish & Completions         | v0.8.0  | `[x] done`  |
| M8 — Stable Release               | v1.0.0  | `[ ] open`  |

Full scope and function contracts for M0–M5: see [`docs/ARCHIVE_ROADMAP.md`](docs/ARCHIVE_ROADMAP.md).

---

## M6 — Reliability & Correctness

> Fix what is broken before adding what is missing.
> A tool that touches package state must produce correct output and reliable operations.

| # | Issue | File | Acceptance criteria | Status |
|---|-------|------|---------------------|--------|
| 1 | `snapshot_restore` calls `brew install pkg@ver` — only works for versioned taps, silently fails for most packages | `snapshot.sh` | Limitation documented clearly in output; or reliable restore path implemented if feasible | `[x] done` |
| 2 | `cleanup_bloat` — `local total` declared twice; installed count overwritten by scan row count | `cleanup.sh` | Variable renamed; "Total installed" shows correct value | `[x] done` |
| 3 | `_cleanup_last_access` calls `brew list $pkg` per formula inside `cleanup_scan` loop — O(n) brew invocations | `cleanup.sh` | Replaced with single upfront file map; `cleanup_scan` completes in < 10s for 200 packages | `[x] done` |
| 4 | Tmpfile `$tmp_cur` in `snapshot_diff` and `snapshot_restore` not removed on early exit | `snapshot.sh` | Trap added; tmpfile cleaned on all exit paths | `[x] done` |
| 5 | `upgrade.sh` misplaced in `core/` — touches brew and user I/O, not a pure function | `lib/brewmaster/core/upgrade.sh` | Moved to `lib/brewmaster/upgrade.sh`; all source paths in `bin/brewmaster` updated | `[x] done` |

---

## M7 — Polish & Completions

> Add what is missing before calling it stable.

| # | Feature | Notes | Status |
|---|---------|-------|--------|
| 1 | Progress indicator in `run_upgrade` | Match `\r\033[K[i/total]` pattern already in `cleanup_scan` | `[x] done` |
| 2 | Shell completions — bash, zsh, fish | `completions/brewmaster.bash`, `completions/brewmaster.zsh`, `completions/brewmaster.fish` | `[x] done` |
| 3 | Man page | `docs/brewmaster.1` — install via Homebrew formula pending in tap repo | `[x] done` |
| 4 | Empty array pattern cleanup | Replace `"${arr[@]:-}"` workarounds with `(( ${#arr[@]} == 0 ))` across all files | `[x] done` |
| 5 | Error handling audit | Review all `\|\| return 1` paths in `semver.sh` and `audit.sh`; no silent failures | `[x] done — all return-1 paths print or propagate an error message` |

---

## M8 — Stable Release

> No new features. Tag after M7 is complete and battle-tested in daily use.

Criteria before tagging v1.0.0:
- All M6 and M7 items complete and passing CI
- Used daily without friction for at least 2 weeks post-M7
- No open 🔴 issues

---

## Post-v1.0 Candidates

*Not yet scoped. Propose as issues before implementing. Each must pass the test in PHILOSOPHY.md.*

- `brewmaster why` — richer reasoning (install date, source, last-used heuristic)
- `brewmaster report` — machine health timeline (trend, not just snapshot)
- `brewmaster pin` — intent annotation (`--reason="legacy project XYZ"`)

---

## Out of Scope

These were considered and explicitly rejected. See [PHILOSOPHY.md](PHILOSOPHY.md) for the full reasoning.

| Feature                        | Reason                                                      |
| ------------------------------ | ----------------------------------------------------------- |
| Multi-driver (npm, pip, cargo) | Dev environment layer — different domain from machine layer |
| Cross-machine sync             | Prescriptive and future-tense — against brewmaster philosophy |
| Plugin/hook system             | Shell is already composable — not needed at this scale      |
| Team/org policy enforcement    | Out of solo-tool scope                                      |