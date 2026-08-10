# Contributing to brewmaster

> **For AI coding assistants:** Read `AGENTS.md` first, then this file before creating any commit, branch, or file.
> All conventions here are mandatory. Never add AI tool attribution to commits.

---

## AI-Assisted Development

brewmaster uses [OpenSpec](https://github.com/Fission-AI/OpenSpec) for
spec-driven development. Every milestone is implemented through a proposal
cycle — never by jumping directly to code.

### Before writing any code

1. Read `AGENTS.md` — project context, stack, and coding conventions
2. Read `PHILOSOPHY.md` — the four-question test for any new feature
3. Read `ROADMAP.md` — current milestone scope, files affected, acceptance criteria
4. Read `docs/ARCHIVE_ROADMAP.md` — frozen function contracts for M0–M5

### OpenSpec workflow

```bash
# 1. Start a proposal for the active milestone
/opsx:propose "<milestone-name>"

# 2. Review generated proposal before proceeding
# openspec/changes/<milestone-name>/proposal.md   ← why and what
# openspec/changes/<milestone-name>/specs/        ← requirements and scenarios
# openspec/changes/<milestone-name>/design.md     ← technical approach
# openspec/changes/<milestone-name>/tasks.md      ← implementation checklist

# 3. Implement — one commit per task (follow commit conventions below)
/opsx:apply

# 4. Archive after all tasks done and tests pass
/opsx:archive
```

- Never start implementation without an active OpenSpec proposal
- Never expand scope beyond what is defined in the active ROADMAP milestone
- One task from `tasks.md` = one commit

---

## Adding a New Milestone

Before proposing a new milestone, apply the four-question test in `PHILOSOPHY.md`.
If all answers are yes, follow this cycle in order.

### 1. Define the milestone in ROADMAP.md

Add the milestone under `## Upcoming Milestones` following the existing format:

```markdown
### Milestone N — Name

**Status:** `[ ] planned` **Branch:** `type/short-name` **Version:** `vX.Y.0` **Depends on:** Mx, My

#### Scope
Problem statement — what is broken or missing, and why it matters.

#### Files
- `path/to/file.sh` — what changes or gets created

#### Function Contracts
public_function_name "$arg"
# purpose, stdout, return code

#### Tasks
- [ ] Task description

#### Acceptance Criteria
brewmaster command   # expected output or behavior
```

Then add a row to the Status table:

```markdown
| MN — Name | vX.Y.0 | `[ ] planned` |
```

Get maintainer review before proceeding to step 2.

### 2. Update Valid Scopes in CONTRIBUTING.md

If the milestone introduces new files or modules, add the corresponding
scope(s) to the Valid Scopes table so commit messages stay consistent.

### 3. Run the OpenSpec proposal

```bash
/opsx:propose "<milestone-name>"
```

Review the generated proposal against ROADMAP.md scope before running `/opsx:apply`.

### 4. Implement and close

```bash
/opsx:apply      # one commit per task
/opsx:archive    # after all tasks done and tests pass
```

Then:
- Update ROADMAP.md status: `[ ] planned` → `[x] done`
- Tag the release: `git tag -a vX.Y.0 -m "release: vX.Y.0 — milestone name"`
- Add changelog entry: `docs(changelog): add vX.Y.0 release notes`

---

## Commit Message Convention

brewmaster uses **Conventional Commits** — consistent, readable by humans and tooling.

### Format

```
type(scope): short description

[optional body — more detail]

[optional footer — breaking changes, issue references]
```

### Rules

- Description: **lowercase**, **imperative mood** ("add" not "added" or "adds")
- Maximum 72 characters on the first line
- No trailing period
- Body separated from description by one blank line
- Language: **English**

---

### Valid Types

| Type       | When to use                              |
| ---------- | ---------------------------------------- |
| `feat`     | New feature                              |
| `fix`      | Bug fix                                  |
| `refactor` | Code change that doesn't alter behavior  |
| `test`     | Add or fix tests                         |
| `docs`     | Documentation changes only               |
| `chore`    | Setup, config, dependencies, tooling     |
| `perf`     | Performance improvement                  |
| `style`    | Formatting, whitespace — no logic change |
| `revert`   | Revert a previous commit                 |

---

### Valid Scopes

| Scope         | Area                                        |
| ------------- | ------------------------------------------- |
| `core`        | `lib/brewmaster/core/` — semver, outdated   |
| `semver`      | Semver-specific logic                       |
| `snapshot`    | `lib/brewmaster/snapshot.sh`                |
| `depgraph`    | `lib/brewmaster/depgraph.sh`                |
| `profile`     | `lib/brewmaster/profile.sh`                 |
| `cleanup`     | `lib/brewmaster/cleanup.sh`                 |
| `audit`       | `lib/brewmaster/audit.sh`                   |
| `cache`       | `lib/brewmaster/core/cache.sh`              |
| `ui`          | `lib/brewmaster/core/ui.sh`                 |
| `checklist`   | `lib/brewmaster/checklist.sh`               |
| `cli`         | `bin/brewmaster` — entry point, arg parsing |
| `formula`     | `Formula/brewmaster.rb`                     |
| `completions` | Shell completions                           |
| `test`        | Test files in `tests/`                      |
| `docs`        | README, ROADMAP, CONTRIBUTING, CHANGELOG    |
| `ci`          | GitHub Actions workflows                    |
| `deps`        | Dependency changes                          |

---

### Correct Commit Examples

```
# New features
feat(snapshot): add save command with label support
feat(profile): implement profile_load with toml parsing
feat(cli): add --profile flag to main entry point

# Bug fixes
fix(semver): handle version string with +build suffix
fix(snapshot): prevent overwrite without confirmation
fix(depgraph): correct risk score when dep count is zero

# Performance
perf(cache): build deps and uses cache before walk loop
perf(cleanup): replace per-package brew calls with cache lookup

# Refactor
refactor(core): extract bump_kind to semver.sh
refactor(cli): separate arg parsing from upgrade logic

# Tests
test(semver): add edge cases for date-based versions
test(snapshot): verify restore is idempotent

# Docs
docs(readme): add install instructions via brew tap
docs(roadmap): mark milestone 6 as complete
docs(changelog): add v0.7.0 release notes

# Chore
chore(deps): add jq as required dependency
chore(formula): update sha256 for v0.7.0
chore(ci): add release workflow for formula auto-update

# Breaking change — add footer
refactor(core)!: rename allow_by_level parameter or_lower to inclusive

BREAKING CHANGE: or_lower parameter renamed to inclusive.
Update all callers accordingly.
```

---

### Incorrect Commit Examples

```
# ❌ Missing scope
feat: add snapshot feature

# ❌ Not imperative
feat(snapshot): added save command

# ❌ Uppercase description
feat(snapshot): Add save command

# ❌ Trailing period
feat(snapshot): add save command.

# ❌ Invalid type
update(snapshot): add save command

# ❌ Too long (>72 characters)
feat(snapshot): add save command with label support and metadata json file

# ❌ AI attribution — never acceptable
feat(snapshot): add save command

Co-authored-by: Claude <claude@anthropic.com>
Co-authored-by: GitHub Copilot <copilot@github.com>
```

---

## AI Attribution Policy

**All commits must be authored solely by the human developer.**

- Never add `Co-authored-by` trailers for AI coding assistants
- Never add `Generated-by`, `Assisted-by`, or similar footers
- AI tools are development aids — they are not contributors
- Git history must reflect human authorship only

If your AI coding assistant adds these trailers automatically, configure it to stop:

```
# Example: disable co-author in Claude Code settings
# Check your tool's documentation for the equivalent setting
```

---

## Branch Naming Convention

```
type/short-description-in-kebab-case
```

### Examples

```
perf/cache-first-cleanup
feat/upgrade-checklist
feat/visual-polish
feat/manual-and-help
fix/semver-date-parsing
fix/depgraph-risk-score
refactor/foundation
chore/formula-v0-7-0
docs/contributing-guide
```

### Rules

- Use the same type as the commit type
- Description: **lowercase**, **kebab-case**
- Short but clear — 3 to 5 words maximum
- No double slashes or special characters

---

## Commit Sequence per Milestone

Each milestone should have a logical commit order:

```
# Example sequence for Milestone 6 (Performance)

chore(cache): create cache.sh with public interface skeleton
perf(cache): implement cache_build with bulk brew calls
perf(cache): implement cache_deps_for with string parsing
perf(cache): implement cache_uses_for with string parsing
perf(cleanup): refactor cleanup_scan to consume cache
perf(cleanup): refactor bloat walk to consume cache
perf(cleanup): remove per-package brew calls from walk loops
test(cache): add test cases for cache_build and cache_deps_for
test(cleanup): update test_cleanup to cover cache-fed paths
docs(roadmap): mark milestone 6 as complete
docs(changelog): add v0.7.0 release notes
```

One function = one commit. Do not bundle multiple functions in a single commit.

---

## Versioning

brewmaster follows [Semantic Versioning](https://semver.org) strictly.

| Change type                                    | Bump    | Example         |
| ---------------------------------------------- | ------- | --------------- |
| New milestone shipped                          | `minor` | v0.6.0 → v0.7.0 |
| Bug fix or patch within a milestone            | `patch` | v0.7.0 → v0.7.1 |
| Breaking change to public CLI behavior         | `major` | v0.x.x → v1.0.0 |

### Rules

- One milestone = one minor bump
- Never skip versions
- Never release a minor bump mid-milestone
- `patch` is only for: bug fixes, doc corrections, formula updates
- `major` requires explicit maintainer decision — not triggered automatically
- Pre-1.0: breaking changes are allowed on `minor` bumps with a `BREAKING CHANGE:` footer in the commit

### What counts as a breaking change

- Removing or renaming a CLI flag or subcommand
- Changing output format of any command in a way that breaks scripts
- Removing or renaming a public function in any `lib/` module
- Changing the audit log NDJSON schema

---

## Tagging & Releases

Tags follow strict semver:

```
git tag -a v0.7.0 -m "release: v0.7.0 — performance"
git tag -a v0.8.0 -m "release: v0.8.0 — upgrade checklist"
```

Tag message format: `release: vX.Y.Z — short milestone description`

---

## Files That Must Not Be Committed

```
.DS_Store
*.swp
*.swo
/tmp/
*.log
.env
/tests/fixtures/generated/
```

---

## Pre-Commit Checklist (for AI Assistants)

Before making a commit, verify:

- [ ] An active OpenSpec proposal exists for this milestone
- [ ] This commit implements exactly one task from `tasks.md`
- [ ] Type and scope match the tables above
- [ ] Description is lowercase and imperative
- [ ] First line is 72 characters or fewer
- [ ] One commit = one logical change
- [ ] No debug files, logs, or temp files included
- [ ] No `Co-authored-by` or AI attribution in footer
- [ ] Breaking changes have a `BREAKING CHANGE:` footer

---

*These conventions apply to all contributors.*