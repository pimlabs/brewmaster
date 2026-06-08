# Contributing to brewmaster

> **For AI coding assistants:**
> Read this file before creating any commit, branch, or file.
> All conventions here are mandatory. Never add AI tool attribution to commits.

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

| Type | When to use |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `refactor` | Code change that doesn't alter behavior |
| `test` | Add or fix tests |
| `docs` | Documentation changes only |
| `chore` | Setup, config, dependencies, tooling |
| `perf` | Performance improvement |
| `style` | Formatting, whitespace — no logic change |
| `revert` | Revert a previous commit |

---

### Valid Scopes

| Scope | Area |
|-------|------|
| `core` | `lib/brewmaster/core/` — semver, outdated, upgrade |
| `semver` | Semver-specific logic |
| `snapshot` | `lib/brewmaster/snapshot.sh` |
| `depgraph` | `lib/brewmaster/depgraph.sh` |
| `profile` | `lib/brewmaster/profile.sh` |
| `sync` | `lib/brewmaster/sync.sh` |
| `drivers` | `lib/brewmaster/drivers/` |
| `cli` | `bin/brewmaster` — entry point, arg parsing |
| `formula` | `Formula/brewmaster.rb` |
| `completions` | Shell completions |
| `test` | Test files in `tests/` |
| `docs` | README, ROADMAP, CONTRIBUTING, CHANGELOG |
| `ci` | GitHub Actions workflows |
| `deps` | Dependency changes |

---

### Correct Commit Examples

```bash
# New features
feat(snapshot): add save command with label support
feat(profile): implement profile_load with toml parsing
feat(drivers): add npm driver with outdated detection
feat(cli): add --profile flag to main entry point

# Bug fixes
fix(semver): handle version string with +build suffix
fix(snapshot): prevent overwrite without confirmation
fix(depgraph): correct risk score when dep count is zero

# Refactor
refactor(core): extract bump_kind to semver.sh
refactor(cli): separate arg parsing from upgrade logic

# Tests
test(semver): add edge cases for date-based versions
test(snapshot): verify restore is idempotent

# Docs
docs(readme): add install instructions via brew tap
docs(roadmap): mark milestone 0 as complete
docs(changelog): add v0.2.0 release notes

# Chore
chore(deps): add jq as required dependency
chore(formula): update sha256 for v0.2.0
chore(ci): add release workflow for formula auto-update

# Breaking change — add footer
refactor(core)!: rename allow_by_level parameter or_lower to inclusive

BREAKING CHANGE: or_lower parameter renamed to inclusive.
Update all callers accordingly.
```

---

### Incorrect Commit Examples

```bash
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

```bash
# Example: disable co-author in Claude Code settings
# Check your tool's documentation for the equivalent setting
```

---

## Branch Naming Convention

```
type/short-description-in-kebab-case
```

### Examples

```bash
feat/snapshot
feat/profile-system
feat/npm-driver
fix/semver-date-parsing
fix/depgraph-risk-score
refactor/foundation
chore/formula-v0-2-0
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

```bash
# Example sequence for Milestone 1 (Snapshot)

chore(snapshot): create snapshot.sh with public interface skeleton
feat(snapshot): implement snapshot_save with metadata json
feat(snapshot): implement snapshot_list with table output
feat(snapshot): implement snapshot_diff against current state
feat(snapshot): implement snapshot_restore with dry-run support
feat(snapshot): implement snapshot_delete with confirmation prompt
feat(cli): add snapshot subcommand to bin/brewmaster
test(snapshot): add acceptance criteria test cases
docs(roadmap): mark milestone 1 as complete
docs(changelog): add milestone 1 release notes
```

One function = one commit. Do not bundle multiple functions in a single commit.

---

## Tagging & Releases

Tags follow strict semver:

```bash
git tag -a v0.1.0 -m "release: v0.1.0 — refactor foundation"
git tag -a v0.2.0 -m "release: v0.2.0 — snapshot and rollback"
```

Tag message format: `release: vX.Y.Z — short milestone description`

---

## Files That Must Not Be Committed

```gitignore
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

- [ ] Type and scope match the tables above
- [ ] Description is lowercase and imperative
- [ ] First line is 72 characters or fewer
- [ ] One commit = one logical change
- [ ] No debug files, logs, or temp files included
- [ ] No `Co-authored-by` or AI attribution in footer
- [ ] Breaking changes have a `BREAKING CHANGE:` footer

---

*These conventions apply to all contributors.*
