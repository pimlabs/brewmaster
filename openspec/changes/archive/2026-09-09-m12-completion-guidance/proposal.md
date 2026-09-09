## Why

Shell completions have shipped since v0.8.0 and the tap formula installs
them for bash, zsh and fish, yet the maintainer's own first reaction was
"I want a command that installs completions". The gap is not the files:
it is the one line of shell configuration Homebrew needs (zsh's `FPATH`
before `compinit`, bash's `bash-completion@2` profile) and the fact that
nothing in brewmaster tells the user whether that line is in place. The
README was even stale on this until v0.12.2, telling users to copy files
by hand.

Writing that line for the user is the wrong fix: editing `~/.zshrc` is
external state (PHILOSOPHY question 4), and every well-behaved CLI in
this space (starship, zoxide, direnv, gh, kubectl) prints and explains
rather than edits. The right fix for a tool whose character is
*descriptive* is to describe: which shell, whether the script is
installed, whether the shell is set up to load it, and the exact snippet
to add when it is not.

## What Changes

- **New subcommand `brewmaster completion`** (no argument): a status
  report for the user's shell (`$SHELL`, or `--shell=NAME`) — the
  completion script's resolved path or "not found", whether the shell's
  rc files reference Homebrew's completion setup, and the snippet to add
  when they do not. Read-only; exit 0 when the script is found, 1
  otherwise.
- **`brewmaster completion <bash|zsh|fish>`** prints that shell's
  completion script to stdout, so `source <(brewmaster completion zsh)`
  and non-Homebrew installs (git checkout) work without knowing where the
  file lives.
- Script lookup covers both layouts: the git checkout
  (`completions/` next to `lib/`) and the Homebrew install (formula
  targets under `$(brew --prefix)`).
- Help text, man page, README and the three completion scripts learn the
  new subcommand.

## Out of Scope

- **Writing to rc files or completion directories.** No `--install`.
  The user adds one line themselves; brewmaster tells them which.
- **Inspecting the live shell.** brewmaster runs under bash; it cannot
  read zsh's `FPATH`. "Configured" is a documented heuristic over rc
  files, and it never affects the exit code.
- **Changing the tap formula.** It already installs the scripts.
- **Shells other than bash, zsh, fish.** Those are the three the repo
  ships scripts for.

## Capabilities

### New Capabilities

- `completion-guidance`: a read-only diagnostic and printer for the
  shipped shell completions.

## Impact

- `lib/brewmaster/completion.sh` — new: `completion_main` and helpers
- `bin/brewmaster` — `completion` subcommand, `--shell=NAME` flag,
  dispatch, sourcing
- `lib/brewmaster/core/help_data.sh`, `docs/brewmaster.1`,
  `tests/fixtures/help*.txt` — new SHELL COMPLETION section
- `completions/brewmaster.{bash,zsh,fish}` — complete `completion`,
  its shell argument and `--shell=`
- `tests/test_completion.sh` — new
- `README.md` — Shell Completions section points at the subcommand
