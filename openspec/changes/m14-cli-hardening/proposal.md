## Why

Five items were left hanging after M13, each small, each a real cost:

- `bin/brewmaster` reads a command only from `$1`, so
  `brewmaster -n snapshot list` runs an *upgrade* of packages named
  `snapshot` and `list`. Every shell's completion used to suggest exactly
  that form; M13 made the completions mirror the parser instead of fixing
  it.
- The fzf picker has no test that runs fzf. The two bugs users saw
  (`101/101 (0)` from the `start:select-all` race; rows misaligned by
  tab stops) were both integration bugs that a rendered-screen test
  would have caught; every existing test mocks fzf.
- `bash tests/run_all.sh` on Linux reports 13 failures that are
  macOS-only (`date -v`, BSD `script`), so the baseline has to be
  remembered instead of being zero.
- The bash completion's `--flag=value` arms never fire in a real shell,
  because `=` is in `COMP_WORDBREAKS` and bash splits the word.
- `cleanup_scan` runs one `jq` over the whole `brew info` cache per
  package (left open by M6).

None adds a feature; all make the existing surface hold. The
four-question test in PHILOSOPHY: no new capability, no new state, no
writing on the user's behalf, every change describes or verifies what is
already there.

## What Changes

- **Parser: flags may precede the command.** The first non-flag argument
  that names a command is the command, wherever it sits; the word after a
  space-form value flag (`--level patch`, `--profile work`, ...) is that
  flag's value and never the command; the sub-subcommand is still the
  word right after the command. `brewmaster -n snapshot list` ==
  `brewmaster snapshot list -n`. A package name after a flag is still a
  package for the default command.
- **Completions follow the parser again**: commands are offered after a
  leading flag in bash, zsh and fish (reverting M13's mirror of the old
  parser), and bash completes `--flag=value` in a real shell by handling
  the `=`-split words.
- **Picker render test**: `tests/test_ui_render.sh` runs the real fzf in
  a pseudo-terminal (`script(1)`, BSD and util-linux forms), asserts the
  `N/N (N)` preselect count, row alignment, the marker glyph, and that
  Enter returns every row; skips only when fzf or a pty is unavailable.
  CI installs fzf so the test runs there.
- **Linux-clean test baseline**: assertions that need BSD `date -v` are
  skipped with a message where it is absent; the TTY test runs under
  either `script` variant.
- **cleanup: one jq pass**: the cache is split into per-formula objects
  once; `_cleanup_formula_json` becomes a file read. Contracts unchanged.

## Out of Scope

- Any new command or flag.
- Rewriting `Co-authored-by` trailers on `main` (history rewrite; only
  from the maintainer's machine).
- Making the library itself run on Linux (`date -v` stays; only tests
  skip).

## Capabilities

### New Capabilities

- `cli-parser`: where the command may appear on the command line.

### Modified Capabilities

- `interactive-select`: the picker's rendering is verified in a real
  terminal, not only its argv.

## Impact

- `bin/brewmaster` (parser), `lib/brewmaster/core/help_data.sh` (one
  note), `lib/brewmaster/cleanup.sh`, `docs/gen-completions.sh` and the
  generated `completions/`, `.github/workflows/ci.yml` (fzf install).
- Tests: `tests/test_parser.sh` (new), `tests/test_ui_render.sh` (new),
  `tests/test_completions.sh`, `tests/test_cleanup.sh`,
  `tests/test_audit.sh`, `tests/test_cli.sh`.
