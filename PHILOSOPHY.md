# PHILOSOPHY — brewmaster

> **brewmaster knows what's on your machine — and why.**
> Upgrade only what's deliberate. Keep only what's intentional.

---

## The Core Question

Every other upgrade tool asks: *"What packages are outdated?"*

brewmaster asks: *"What is safe, and what belongs?"*

This is not a subtle distinction. It shapes every decision about what goes into brewmaster and what does not.

---

## The Five Pillars

v1 was built around five questions a developer should be able to answer about their machine at any time:

| Question                         | Answered by           |
| -------------------------------- | --------------------- |
| Am I safe to proceed?            | Snapshot & Rollback   |
| What's risky to upgrade?         | Dependency Graph       |
| What should I upgrade right now? | Profile System        |
| What belongs on my machine?      | Cleanup & Intent      |
| What happened over time?         | Audit Log             |

Any future feature must answer one of these questions — or a new question in the same spirit. If it doesn't, it's out of scope.

---

## What brewmaster Is

- A **personal** tool. It runs on one machine, for one person.
- **Descriptive**, not prescriptive. It tells you what is here and why — not what should be here.
- **Present-tense**. It reasons about the current state of your machine, not a desired future state.
- **Homebrew-native**. Homebrew manages the machine layer on macOS. That is the domain brewmaster operates in.
- **Deterministic**. No AI, no guessing. Pure logic from real data.

---

## What brewmaster Is Not

- A dotfiles manager or machine bootstrapper.
- A cross-machine sync tool.
- A dev environment manager.
- A team or org policy enforcement tool.
- A replacement for `Brewfile`.

---

## Rejected Directions

These directions were considered seriously and rejected. They are documented here so the reasoning is not relitigated.

### Multi-Driver (npm, pip, cargo, gem)

**Rejected because:** Homebrew operates at the *machine layer* — it manages what lives on your system, independent of any project. npm global packages, pip installs, cargo binaries — these belong to the *dev environment layer*. They are scoped to workflows and projects, not to the machine itself.

Extending brewmaster to these drivers would not deepen the philosophy — it would dilute it. brewmaster would no longer be answering "what's on your machine" but "what's on your machine and in your projects", which is a different and much harder question.

If the philosophy matures enough to address the dev environment layer cleanly, that is a new tool — not a new driver in brewmaster.

### Machine-as-Code / Cross-Machine Sync

**Rejected because:** Machine-as-Code is about *reproduction* — exporting state so it can be restored on another machine. That is a prescriptive, future-oriented operation: "this is what should be here."

brewmaster is descriptive and present-tense: "this is what is here, and this is why." The moment brewmaster can export a spec and restore it elsewhere, it becomes a cross-machine sync tool — which is explicitly outside its philosophy.

`Brewfile` already serves the reproducibility use case. brewmaster is not a smarter Brewfile. It is a layer of intentionality *on top of* what Homebrew already manages.

### Plugin / Hook System

**Rejected because:** Shell is already composable. brewmaster's output is plain text and its audit log is NDJSON — both pipe naturally into anything. A plugin system would add complexity without adding capability.

### Team / Org Policy Enforcement

**Rejected because:** brewmaster is a personal tool. The moment it enforces policy across machines or people, it needs a server, a sync mechanism, and a trust model. That is a different product.

---

## The Test for New Features

Before proposing or implementing any new feature, ask:

1. Does it answer one of the five pillar questions — or a new question in the same spirit?
2. Does it stay within the machine layer (Homebrew, macOS)?
3. Does it remain personal, present-tense, and descriptive?
4. Does it keep brewmaster deterministic — no guessing, no AI, no external state?

If any answer is no, the feature is out of scope.