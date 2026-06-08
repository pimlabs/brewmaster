# brewmaster

> Selective package upgrade manager based on semantic versioning.

brewmaster upgrades only what you decide — patch, minor, or major — nothing more.
It understands *why* a package exists on your machine before touching it.

---

## Install

```bash
brew tap pimlabs/brewmaster
brew install brewmaster
```

## Quick Start

```bash
# Dry run — see what would be upgraded
brewmaster --dry-run

# Upgrade minor bumps only (default)
brewmaster --level=minor

# Upgrade patch + minor
brewmaster --level=minor --or-lower

# Upgrade only specific profile
brewmaster --profile=work --dry-run
```

## Why brewmaster

Every other upgrade tool asks: *"What packages are outdated?"*

brewmaster asks: *"What is safe to upgrade right now, given everything on this machine?"*

No AI. No guessing. Pure deterministic logic from real data.

---

## Documentation

- [ROADMAP.md](./ROADMAP.md) — milestones and feature scope
- [CONTRIBUTING.md](./CONTRIBUTING.md) — commit conventions and development guide
- [CHANGELOG.md](./CHANGELOG.md) — version history

## License

MIT — see [LICENSE](./LICENSE)
