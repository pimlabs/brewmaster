## Why

The CLI surface is written down in five places: the subcommand and flag
parsers in `bin/brewmaster`, the shared help table in
`help_data.sh`, and three hand-written completion scripts, one per
shell dialect. M12 added one subcommand and had to touch all five; the
tap formula installs the completion scripts, so any one of them
drifting is a user-visible bug with no test to catch it. The help table
already solved this shape once for the man page: `docs/gen-man.sh`
generates `brewmaster.1` from it and `tests/test_docs.sh` fails on
drift. Completions deserve the same treatment.

"From brewmaster itself" cannot mean the tool completing at Tab time:
each shell runs its own completion API (`compgen`, `_arguments`,
`complete -c`) from a file it loaded at startup, so three files are
unavoidable. What can change is where the truth lives. A dynamic model
(a thin shim per shell calling `brewmaster __complete` on every Tab)
still needs the three shims and adds a process spawn per keystroke;
generating the three static scripts from one machine-readable spec
keeps them fast and testable and removes the duplication.

## What Changes

- **`lib/brewmaster/core/cli_spec.sh`** — the machine-readable CLI
  surface: every command, sub-subcommand, positional and flag with its
  description, value kind (boolean, enum, dynamic completer, free) and
  exclusion group, as `|`-separated records with a documented grammar.
- **`docs/gen-completions.sh <bash|zsh|fish>`** — generates a completion
  script from the spec, the counterpart of `gen-man.sh`. The three
  committed scripts under `completions/` become generated artifacts
  (header says so) with the same completions in the same contexts as
  the hand-written ones.
- **`tests/test_completions.sh`** — drift: generator output equals each
  committed script; consistency: every command and flag the spec lists
  is parsed by `bin/brewmaster`, and vice versa; every spec command and
  flag appears in `help_data.sh`; syntax checks where the shell is
  available.
- **CONTRIBUTING** — the recipe for adding a command or flag: spec,
  parser, help text, regenerate; the tests name what was missed.

## Out of Scope

- **Generating `help_data.sh` from the spec.** Help is prose with
  paragraphs and examples; the spec carries one-line descriptions. The
  consistency test holds them to the same list without merging them.
- **Dynamic (`__complete`) completion.** See Why.
- **Changing what any completion offers.** Behavior parity with the
  hand-written scripts is the acceptance bar; improvements are a later
  change against the spec.
- **Shells beyond bash, zsh, fish.**

## Capabilities

### New Capabilities

- `cli-spec`: one machine-readable source for the CLI surface, from which
  the completion scripts are generated and against which the parser and
  help text are checked.

## Impact

- `lib/brewmaster/core/cli_spec.sh` — new (pure data; no `brew`, no I/O)
- `docs/gen-completions.sh` — new
- `completions/brewmaster.{bash,zsh,fish}` — regenerated
- `tests/test_completions.sh` — new
- `CONTRIBUTING.md` — "adding a command" recipe; `AGENTS.md` layout line
