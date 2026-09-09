## Approach

One new library file, `lib/brewmaster/completion.sh`, sourced by
`bin/brewmaster` like the others. Everything is read-only; `DRY_RUN` has
nothing to guard.

```
brewmaster completion                 # status for $SHELL
brewmaster completion --shell=zsh     # status for another shell
brewmaster completion zsh             # print the zsh script to stdout
```

### Shell resolution

`_completion_shell`: `--shell=NAME` wins, else the basename of `$SHELL`.
Anything other than `bash`, `zsh`, `fish` is an error naming the three
supported shells, exit 1. The positional argument (`completion zsh`)
selects print mode and takes the same validation.

### Script lookup

`_completion_script_path <shell>` tries, in order, and prints the first
hit (each attempt is logged with `logv`):

1. the git-checkout layout: `$LIB_DIR/../completions/brewmaster.<ext>`
   (`bash`, `zsh`, `fish`). In a Homebrew install `LIB_DIR` is
   `libexec/brewmaster` and this path does not exist, which is the point.
2. the formula's install targets under `$(brew --prefix)`, fetched once:
   `etc/bash_completion.d/brewmaster`,
   `share/zsh/site-functions/_brewmaster`,
   `share/fish/vendor_completions.d/brewmaster.fish`.

`brew --prefix` is the only `brew` call and it is skipped when the
checkout hit succeeds. Tests mock it on `PATH`.

### "Configured" heuristic

brewmaster cannot see the user's live zsh `FPATH` or bash completion
state from inside a bash script, so the report says what it can verify
and labels it:

| Shell | rc files scanned | counts as configured when a file mentions |
| ----- | ---------------- | ---------------------------------------- |
| zsh   | `${ZDOTDIR:-$HOME}/.zshrc`, `.zprofile`, `.zshenv` | `site-functions` or `brew shellenv` |
| bash  | `~/.bash_profile`, `~/.bashrc`, `~/.profile` | `bash_completion` |
| fish  | none | always (fish loads `vendor_completions.d` itself) |

`brew shellenv` counts for zsh because Homebrew's zsh output prepends
`share/zsh/site-functions` to `fpath`. Comments are not filtered out on
purpose: a commented-out line is rare, and a false "configured" only
withholds a snippet the user can still get from the README. The
heuristic never affects the exit code.

### Output

```
Shell:       zsh (from $SHELL)
Script:      /opt/homebrew/share/zsh/site-functions/_brewmaster
Configured:  ~/.zshrc references Homebrew's site-functions

Completion is installed and your shell is set up to load it.
Open a new shell if it is not working yet.
```

When not configured, the last paragraph is the snippet for that shell
(the same three snippets README documents). When the script is not
found: "Install via `brew install pimlabs/tap/brewmaster`, or from a
checkout: `source <(bin/brewmaster completion zsh)`", exit 1. Labels go
through `ui_table_row` for alignment; no color beyond `COLOR_MUTED` on
the heuristic note, so `NO_COLOR` output is byte-stable for the tests.

### Print mode

`brewmaster completion <shell>` `cat`s the resolved script, nothing
else on stdout, so `source <(...)` and `> file` are clean. Errors go to
stderr with exit 1.

## Decisions

- **Status uses `$SHELL`, not `$0` or `ps`.** `$SHELL` is the login
  shell, which is what completion setup is about; `--shell=` covers the
  rest. No process-tree sniffing.
- **Positional shell = print, no positional = status.** Mirrors
  `kubectl completion zsh` / `gh completion -s zsh`, the idiom users
  already know, while keeping the diagnostic one word long.
- **No `--install`.** See proposal; convention 10's spirit (never modify
  without explicit confirmation) and PHILOSOPHY question 4.
- **No new hard dependency.** `brew --prefix` only runs when the
  checkout layout misses, and `brew` is already a hard dependency.

## Alternatives rejected

- **A `doctor` command.** Broader than the problem; brewmaster's
  scope is completions here, not general environment health.
- **Editing rc files behind a `[y/N]`.** Even confirmed, it leaves
  brewmaster owning a line in a file it does not otherwise touch, and
  every future zsh framework quirk becomes a bug report.
- **Fixing the formula to install into `libexec/completions` too.** Not
  needed: the formula's targets are stable, well-known paths; lookup
  order 2 covers them without a tap change.

## Testing

`tests/test_completion.sh`, sourcing `completion.sh` with `brew` mocked
on `PATH` (`--prefix` → a temp prefix) and `HOME`/`ZDOTDIR`/`SHELL`
pointed at temp dirs:

- resolution: checkout layout first, formula targets second, "not
  found" with exit 1 when neither exists
- `completion zsh` prints exactly the file, exit 0; unknown shell exits
  1 naming bash/zsh/fish
- status: `$SHELL` and `--shell=` selection; configured/not-configured
  for zsh (rc mentions `site-functions`, `brew shellenv`, or nothing),
  bash (`bash_completion`), fish (always)
- exit code follows script presence only
- help fixtures and `test_docs.sh` drift check regenerated; every
  completion script lists `completion` and `--shell=`
