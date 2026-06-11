# ROADMAP — brewmaster

> **For AI coding assistants (Claude Code and others):**
> v1 (M0-M5) is complete and frozen — see
> [`docs/ARCHIVE_ROADMAP.md`](docs/ARCHIVE_ROADMAP.md) for milestone history
> and frozen function contracts referenced by `tests/`.
> v2 scope is not yet defined. Do not invent new milestones or features —
> propose changes (as an issue, or a new section under "v2 — Planning" below)
> before implementing.
> Do not add Co-authored-by or any AI tool attribution to commits.

---

## Philosophy

> **brewmaster knows what's on your machine — and why.**
> Upgrade only what's deliberate. Keep only what's intentional.

v1 built out this philosophy across five pillars:

| Question | Answered by |
|---|---|
| Am I safe to proceed? | M1 — Snapshot |
| What's risky to upgrade? | M2 — Dependency Graph |
| What should I upgrade right now? | M3 — Profile System |
| What belongs on my machine? | M4 — Cleanup & Intent |
| What happened over time? | M5 — Audit Log |

Any future feature should still answer one of these questions, or a new
question in the same spirit. If it doesn't, it's out of scope.

---

## Project Context

`brewmaster` is a CLI tool for selective package upgrades based on semver classification.
Core logic lives in `bin/brewmaster`, modularized across `lib/brewmaster/core/`.

**Stack:** Bash (POSIX-compatible where possible), `jq`, `curl`, `fzf` (optional)
**Target OS:** macOS (Homebrew)
**Distribution:** `brew tap pimlabs/brewmaster`

---

## Status

v1 is complete and shipped:

| Milestone | Version | Status |
|---|---|---|
| M0 — Refactor & Foundation | v0.1.0 | `[x] done` |
| M1 — Snapshot & Rollback | v0.2.0 | `[x] done` |
| M2 — Dependency Graph Awareness | v0.3.0 | `[x] done` |
| M3 — Profile System | v0.4.0 | `[x] done` |
| M4 — Cleanup & Intent | v0.5.0 | `[x] done` |
| M5 — Audit Log & Report | v0.6.0 | `[x] done` |

Full scope, function contracts, and acceptance criteria for each milestone:
see [`docs/ARCHIVE_ROADMAP.md`](docs/ARCHIVE_ROADMAP.md).

---

## Coding Conventions

> These apply to every file, v1 or v2. Read before writing any code.

1. Every public function must have a header comment: purpose, args, stdout, return code
2. Use `local` for all variables inside functions
3. No `set -e` inside functions — handle errors explicitly with `|| return 1`
4. `DRY_RUN` is a global boolean — always check before any destructive action
5. `VERBOSE` is a global boolean — use `logv()` from core for debug output
6. All user-facing paths use `${XDG_DATA_HOME:-$HOME/.local/share}/brewmaster/`
7. All config paths use `${XDG_CONFIG_HOME:-$HOME/.config}/brewmaster/`
8. `jq` is available — declared as hard dependency in formula
9. `fzf` is optional — always degrade gracefully with a clear install message
10. Test functions follow: `test_functionname_condition()` with simple assert helpers
11. Never auto-remove or auto-modify packages without explicit user confirmation or `--force`
12. Never add Co-authored-by or any AI tool attribution to commits

---

## Out of Scope (v1)

These were considered and explicitly deferred:

| Feature | Reason |
|---|---|
| Multi-driver (npm, pip, cargo) | Philosophy needs to mature at brew level first |
| Cross-machine sync | Doesn't fit personal tool philosophy |
| Plugin/hook system | Shell is already composable — not needed at this scale |
| Team/org policy enforcement | Out of solo-tool scope |
| Shell completions (bash/zsh) | Not scoped into any v1 milestone; candidate for v2 |

---

## v2 — Planning

_Not yet defined. Add proposals here before implementation._
