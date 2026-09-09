# ROADMAP — brewmaster

> **For AI coding assistants (Claude Code and others):** M0–M5 is complete and frozen — see [`docs/ARCHIVE_ROADMAP.md`](docs/ARCHIVE_ROADMAP.md) for milestone history
> and frozen function contracts referenced by `tests/`.
> Do not invent new milestones or features —
> propose changes (as an issue, or a new section under "Upcoming Milestones" below)
> before implementing.
> Do not add Co-authored-by or any AI tool attribution to commits.

---

## Philosophy

> **brewmaster knows what's on your machine — and why.** Upgrade only what's deliberate. Keep only what's intentional.

M0–M5 built out this philosophy across five pillars:

| Question                         | Answered by           |
| -------------------------------- | --------------------- |
| Am I safe to proceed?            | M1 — Snapshot         |
| What's risky to upgrade?         | M2 — Dependency Graph |
| What should I upgrade right now? | M3 — Profile System   |
| What belongs on my machine?      | M4 — Cleanup & Intent |
| What happened over time?         | M5 — Audit Log        |

Any future feature should still answer one of these questions, or a new
question in the same spirit. If it doesn't, it's out of scope.

---

## Project Context

`brewmaster` is a CLI tool for selective package upgrades based on semver classification.
`bin/brewmaster` parses arguments and dispatches to command modules in
`lib/brewmaster/*.sh`, which source pure helpers from `lib/brewmaster/core/`
(layout and the `core/` rule: `AGENTS.md`).

**Stack:** Bash (POSIX-compatible where possible), `jq`, `curl`, `fzf` (optional)
**Target OS:** macOS (Homebrew)
**Distribution:** `brew tap pimlabs/brewmaster`

---

## Status

| Milestone                       | Version  | Status        |
| ------------------------------- | -------- | ------------- |
| M0 — Refactor & Foundation      | v0.1.0   | `[x] done`   |
| M1 — Snapshot & Rollback        | v0.2.0   | `[x] done`   |
| M2 — Dependency Graph Awareness | v0.3.0   | `[x] done`   |
| M3 — Profile System             | v0.4.0   | `[x] done`   |
| M4 — Cleanup & Intent           | v0.5.0   | `[x] done`   |
| M5 — Audit Log & Report         | v0.6.0   | `[x] done`   |
| M6 — Performance                | v0.10.0  | `[x] done`   |
| M7 — Upgrade Checklist          | v0.10.0  | `[x] done`   |
| M8 — Visual Polish              | v0.10.0  | `[x] done`   |
| M9 — Manual & Help              | v0.10.0  | `[x] done`   |
| M10 — Colorized Help            | v0.11.0  | `[x] done`   |
| M11 — Interactive Selection UX  | v0.12.0  | `[x] done`   |
| M12 — Completion Guidance       | v0.13.0  | `[x] done`   |
| M13 — CLI Spec & Completions    | v0.14.0  | `[x] done`   |
| M14 — CLI Hardening             | v0.15.0  | `[ ] proposed` |

> Shell completions (bash/zsh) shipped as a patch in v0.6.1 — not a formal milestone.
> M6–M9 shipped together in v0.10.0 (2026-08-11). The `(M6)`/`(M7)` labels on
> CHANGELOG's v0.7.0/v0.8.0 entries predate the current milestone numbering,
> and there was never a v0.9.0.
> Full scope, function contracts, and acceptance criteria for M0–M5:
> see [`docs/ARCHIVE_ROADMAP.md`](docs/ARCHIVE_ROADMAP.md).
> As-built notes for M6 onward (what shipped versus what was planned):
> see [`docs/MILESTONES.md`](docs/MILESTONES.md).

---

## Coding Conventions

> These apply to every file, every milestone. Read before writing any code.

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

## Out of Scope

These were considered and explicitly deferred:

| Feature                        | Reason                                                  |
| ------------------------------ | ------------------------------------------------------- |
| Multi-driver (npm, pip, cargo) | Philosophy needs to mature at brew level first          |
| Cross-machine sync             | Doesn't fit personal tool philosophy                    |
| Plugin/hook system             | Shell is already composable — not needed at this scale  |
| Team/org policy enforcement    | Out of solo-tool scope                                  |

---

## Upcoming Milestones

To propose one, add a section here in the shape the archived milestones
use (Status / Branch / Version / Depends on, Scope, Files, Acceptance
Criteria) after the four-question test, then implement it through the
OpenSpec cycle in `AGENTS.md`.

### Milestone 14 — CLI Hardening

**Status:** `[ ] proposed` **Branch:** `feat/cli-hardening` **Version:** `v0.15.0` **Depends on:** M11, M13

#### Scope

Every item left hanging after M13, none a feature, each a real cost:

- **Parser: flags may precede the command.** `brewmaster -n snapshot list`
  runs an upgrade of packages named `snapshot` and `list` today, because
  the command is read only from `$1`. The first non-flag argument that
  names a command becomes the command; the value of a space-form flag
  (`--level patch`) never does; the sub-subcommand stays the word after
  the command. Completions offer commands after a leading flag again, and
  bash completes `--flag=value` when the shell splits at `=`.
- **Picker render test.** The real fzf under a pseudo-terminal, asserting
  the preselect count, row alignment, the marker glyph and the rows
  returned on Enter — the two bugs users saw in v0.12.0 were exactly
  these, and every existing test mocks fzf. CI installs fzf.
- **Linux-clean test baseline.** BSD-`date` assertions skip with a
  message where `date -v` is absent; the TTY test runs under either
  `script(1)` variant. `bash tests/run_all.sh` reports 0 failures on
  Linux.
- **cleanup: one jq pass.** The `brew info` cache is split per formula
  once instead of one `jq` over the whole cache per package (open since
  M6). Contracts unchanged.

Out of scope: any new command or flag; making the library itself run on
Linux; rewriting history on `main`.

#### Files

- `bin/brewmaster` — `_hoist_command`; `lib/brewmaster/core/help_data.sh` — one note
- `docs/gen-completions.sh`, `completions/` — regenerated
- `lib/brewmaster/cleanup.sh`
- `tests/test_parser.sh`, `tests/test_ui_render.sh` — new; `tests/test_completions.sh`,
  `tests/test_cleanup.sh`, `tests/test_audit.sh`, `tests/test_cli.sh`
- `.github/workflows/ci.yml` — `brew install fzf`

#### Acceptance Criteria

```
brewmaster -n snapshot list            # == brewmaster snapshot list -n
brewmaster --level patch snapshot list # patch is the level, snapshot list the command
bash tests/test_ui_render.sh           # runs fzf in a pty; fails on a copy of ui_select without --sync or --with-nth=2
bash tests/run_all.sh                  # 0 failures on Linux and on macOS CI
# cleanup_scan over a 300-formula cache: jq no longer dominates (timing in the as-built note)
```

See `openspec/changes/m14-cli-hardening/` for the proposal, design, specs,
and tasks.

---


Completed milestones' as-built notes live in
[`docs/MILESTONES.md`](docs/MILESTONES.md); the frozen M0–M5 contracts
that `tests/` reference live in
[`docs/ARCHIVE_ROADMAP.md`](docs/ARCHIVE_ROADMAP.md).
