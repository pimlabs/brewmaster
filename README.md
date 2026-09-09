# brewmaster

> Selective package upgrade manager based on semantic versioning.

brewmaster upgrades only what you decide — patch, minor, or major — nothing more.
It understands *why* a package exists on your machine before touching it.

---

## Install

```bash
brew tap pimlabs/tap
brew install brewmaster
```

## Shell Completions

`brew install` sets these up for bash, zsh and fish: the formula installs
them into Homebrew's completion directories, along with the man page
(`man brewmaster`). Nothing to copy.

Not sure whether your shell loads them? Ask brewmaster. It reads your rc
files and never writes to them:

```bash
brewmaster completion                 # status for your shell, and the snippet to add if it isn't loaded
brewmaster completion --shell=bash    # same, for another shell
source <(brewmaster completion zsh)   # or print the script, e.g. from a git checkout
```

If completion doesn't work, your shell isn't loading Homebrew's
completions yet:

```zsh
# zsh — add to ~/.zshrc, before compinit
if type brew &>/dev/null; then
  FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"
  autoload -Uz compinit && compinit
fi
```

```bash
# bash — install bash-completion@2, then add to ~/.bash_profile
[[ -r "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]] && . "$(brew --prefix)/etc/profile.d/bash_completion.sh"
```

fish picks up `vendor_completions.d` on its own.

Running from a git checkout instead? The scripts live in
[`completions/`](./completions):

```bash
source completions/brewmaster.bash                                                            # bash
cp completions/brewmaster.zsh "$(brew --prefix)/share/zsh/site-functions/_brewmaster"        # zsh
cp completions/brewmaster.fish (brew --prefix)/share/fish/vendor_completions.d/brewmaster.fish  # fish
```

## Why brewmaster

Every other upgrade tool asks: *"What packages are outdated?"*

brewmaster asks: *"What is safe to upgrade right now, given everything on this machine?"*

No AI. No guessing. Pure deterministic logic from real data.

---

## Commands at a Glance

| Area | Command | What it does |
|---|---|---|
| Upgrade | `brewmaster [upgrade] [pkgs...] [--patch\|--minor\|--major] [--dry-run]` | Selective upgrade by semver bump (default) |
| Dependency Risk | `brewmaster --check-deps` / `brewmaster deps show [pkg]` | Score upgrade risk before applying |
| Profiles | `brewmaster --profile=NAME` / `brewmaster profile {list,create,edit,diff,validate}` | Named upgrade policies |
| Snapshots | `brewmaster snapshot {save,list,diff,restore,delete}` | Save/restore Homebrew package state |
| Cleanup & Intent | `brewmaster cleanup` / `brewmaster why <pkg>` / `brewmaster bloat` | Find & explain orphan/stale packages |
| Audit & Reports | `brewmaster log` / `brewmaster report` | History and machine health summary |

---

## Quick Start — Upgrades

```bash
# Dry run — see what would be upgraded (default level: patch)
brewmaster --dry-run

# Upgrade minor bumps only
brewmaster --minor

# Upgrade patch + minor (inclusive)
brewmaster --minor --or-lower

# Limit to specific packages
brewmaster upgrade git node --minor
```

## Dependency Risk

Score each candidate before upgrading, based on dependents and bump size.

```bash
# Skip HIGH-risk upgrades (score >= 7), warn + confirm on MEDIUM (4-6)
brewmaster --check-deps --dry-run

# Auto-confirm MEDIUM-risk packages, custom HIGH cutoff
brewmaster --check-deps --risk-threshold=5 --yes

# Risk report for one package, or all outdated packages sorted by risk
brewmaster deps show openssl
brewmaster deps show
```

## Profiles

Named profiles filter which packages get upgraded and how aggressively.
Config lives at `~/.config/brewmaster/profiles.toml`.

```bash
brewmaster --profile=work --dry-run
brewmaster --profile=safe --check-deps

brewmaster profile list
brewmaster profile create
brewmaster profile edit work
brewmaster profile diff work safe
brewmaster profile validate
```

Every upgrade run reviews its candidates before executing: with `fzf`, a
picker where all candidates start checked (deselect what you don't want);
without it, a table and a single `[y/N]`. `--dry-run` and `--yes` skip it.

## Snapshots & Rollback

```bash
brewmaster snapshot save --label="before-work-upgrade"
brewmaster snapshot list
brewmaster snapshot diff 1
brewmaster snapshot restore 1 --dry-run
brewmaster snapshot delete 1 --force
```

## Cleanup & Intent

Find orphan, stale, and old-pinned packages — and the dependency reasoning behind them.

```bash
# Read-only report (also the default with no flags)
brewmaster cleanup --dry-run

# fzf multi-select removal, with a "why" preview pane
brewmaster cleanup --interactive

# Auto-remove orphans with score >= 7
brewmaster cleanup --force

# Why is this package here?
brewmaster why git

# Machine package summary + estimated disk reclaim
brewmaster bloat
```

A snapshot is taken automatically before any `cleanup` removal.

## Audit Log & Reports

Every upgrade, cleanup, and snapshot is recorded to
`~/.local/share/brewmaster/audit.log` (NDJSON).

```bash
# Last 20 entries
brewmaster log

# Filter by package, action, or time window
brewmaster log --package=git
brewmaster log --action=cleanup --since=30d
brewmaster log --format=json

# Machine health summary
brewmaster report
```

---

## Documentation

- [ROADMAP.md](./ROADMAP.md) — current status and v2 planning
- [docs/ARCHIVE_ROADMAP.md](./docs/ARCHIVE_ROADMAP.md) — v1 milestone history and frozen function contracts
- [CONTRIBUTING.md](./CONTRIBUTING.md) — commit conventions and development guide
- [CHANGELOG.md](./CHANGELOG.md) — version history

## License

MIT — see [LICENSE](./LICENSE)
