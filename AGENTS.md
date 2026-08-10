# AGENTS.md — brewmaster

> Read `PHILOSOPHY.md` before proposing or implementing any feature.
> Read `ROADMAP.md` for current milestone scope and upcoming work.
> Read `docs/ARCHIVE_ROADMAP.md` before touching any M0–M5 code.

---

## What This Project Is

`brewmaster` is a Bash CLI tool for selective Homebrew package upgrades on macOS,
built around the question: *"What is safe, and what belongs?"*

It is a **personal, present-tense, descriptive** tool. It is not a dotfiles manager,
cross-machine sync tool, or dev environment manager.

---

## Project Structure

```
bin/brewmaster          ← entry point, command dispatch
lib/brewmaster/core/    ← modular logic (one file per concern)
config/                 ← default config templates
tests/                  ← test functions (source + assert pattern)
docs/                   ← ARCHIVE_ROADMAP.md and other references
openspec/               ← OpenSpec change proposals (do not edit manually)
```

---

## Stack

- **Language:** Bash (POSIX-compatible where possible)
- **Hard dependencies:** `jq`, `brew`
- **Optional dependency:** `fzf` — always degrade gracefully with a clear install message
- **Target OS:** macOS (Homebrew)
- **Distribution:** `brew tap pimlabs/brewmaster`

---

## How to Run Tests

```bash
# Run all tests
bash tests/run_all.sh

# Run a specific test file
bash tests/test_snapshot.sh

# Test function naming convention
test_functionname_condition()
```

---

## Coding Conventions

These are non-negotiable. Apply to every file, all milestones.

1. Every public function must have a header comment: purpose, args, stdout, return code
2. Use `local` for all variables inside functions
3. No `set -e` inside functions — handle errors explicitly with `|| return 1`
4. `DRY_RUN` is a global boolean — always check before any destructive action
5. `VERBOSE` is a global boolean — use `logv()` from core for debug output
6. All user-facing data paths: `${XDG_DATA_HOME:-$HOME/.local/share}/brewmaster/`
7. All config paths: `${XDG_CONFIG_HOME:-$HOME/.config}/brewmaster/`
8. `jq` is available — declared as hard dependency in formula
9. `fzf` is optional — always degrade gracefully
10. Never auto-remove or auto-modify packages without explicit user confirmation or `--force`
11. Never add Co-authored-by or any AI tool attribution to commits
12. Empty array checks use `(( ${#arr[@]} == 0 ))` — not `"${arr[@]:-}"` workarounds

---

## Frozen: M0–M5

M0–M5 (v0.1.0–v0.6.x) are complete and frozen. Do not modify v1 function contracts.
Function contracts and acceptance criteria are in `docs/ARCHIVE_ROADMAP.md`.
Tests in `tests/` reference these contracts — do not break them.

---

## Current Scope

See `ROADMAP.md` for the active milestone and full upcoming milestone details.
Do not implement anything outside the current milestone without a proposal first.
Before proposing anything new, apply the four-question test in `PHILOSOPHY.md`.

---

## Implementation Workflow (OpenSpec)

This project uses [OpenSpec](https://github.com/Fission-AI/OpenSpec) for
spec-driven development. Every milestone is implemented through a proposal
cycle — never by jumping directly to code.

### Required workflow for every milestone

```
1. Read ROADMAP.md — understand the milestone scope, files, and acceptance criteria
2. Run: /opsx:propose "<milestone-name>"
   OpenSpec will generate:
     openspec/changes/<milestone-name>/proposal.md   ← why and what
     openspec/changes/<milestone-name>/specs/        ← requirements and scenarios
     openspec/changes/<milestone-name>/design.md     ← technical approach
     openspec/changes/<milestone-name>/tasks.md      ← implementation checklist
3. Review proposal with the maintainer before proceeding
4. Run: /opsx:apply
   Implement tasks one by one — one commit per task
5. Run: /opsx:archive
   Archive the proposal after all tasks are done and tests pass
```

### Rules

- Never implement a milestone without an active OpenSpec proposal
- Never modify `openspec/` files manually — use `/opsx:` commands only
- Proposal content must stay consistent with ROADMAP.md scope — do not expand scope
- If the ROADMAP scope is unclear, ask before proposing

---

## Explicitly Out of Scope

Do not propose these. The full reasoning is in `PHILOSOPHY.md`.

- Multi-driver support (npm, pip, cargo, gem)
- Cross-machine sync or machine-as-code export
- Plugin or hook system
- Team / org policy enforcement