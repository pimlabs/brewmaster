# AGENTS.md — brewmaster

> Read PHILOSOPHY.md before proposing or implementing any feature.
> Read docs/ARCHIVE_ROADMAP.md before touching any v1 code.

---

## What This Project Is

`brewmaster` is a Bash CLI tool for selective Homebrew package upgrades on macOS, built around the question: *"What is safe, and what belongs?"*

It is a **personal, present-tense, descriptive** tool. It is not a dotfiles manager, cross-machine sync tool, or dev environment manager.

---

## Project Structure

```
bin/brewmaster          ← entry point, command dispatch
lib/brewmaster/core/    ← modular logic (one file per concern)
config/                 ← default config templates
tests/                  ← test functions (source + assert pattern)
docs/                   ← ARCHIVE_ROADMAP.md and other references
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

## Current Scope: M6 and M7

See ROADMAP.md for full milestone details. In summary:

**M6 — Reliability & Correctness (v0.7.0)**
- Fix `snapshot_restore` versioned install bug
- Fix `cleanup_bloat` variable shadowing
- Fix `_cleanup_last_access` O(n) brew calls
- Fix tmpfile leak in snapshot diff/restore

**M7 — Polish & Completions (v0.8.0)**
- Progress indicator in `run_upgrade`
- Shell completions (bash, zsh, fish)
- Man page (`docs/brewmaster.1`)
- Empty array pattern cleanup
- Error handling audit

Do not implement features outside M6 and M7 without a proposal in ROADMAP.md first.
Before proposing anything new, apply the test in PHILOSOPHY.md.

---

## Explicitly Out of Scope

Do not propose these. The reasoning is in PHILOSOPHY.md.

- Multi-driver support (npm, pip, cargo, gem)
- Cross-machine sync or machine-as-code export
- Plugin or hook system
- Team / org policy enforcement