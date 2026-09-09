## 1. Library

- [x] 1.1 Add `lib/brewmaster/completion.sh` with `_completion_shell`,
      `_completion_script_path`, `_completion_rc_mentions`,
      `_completion_snippet`, and `completion_main`, each with the
      header comment convention (purpose, args, stdout, return code),
      `local` everywhere, no `set -e`, `logv` for each lookup attempt
- [x] 1.2 Source it from `bin/brewmaster` alongside the other modules

## 2. CLI

- [x] 2.1 Parse `completion` as a subcommand with an optional positional
      shell (`bash|zsh|fish`) into `COMPLETION_SHELL`
- [x] 2.2 Add `--shell=NAME` / `--shell NAME` to the flag parser
- [x] 2.3 Dispatch: positional shell → print mode; none → status mode

## 3. Help and docs

- [x] 3.1 Add a SHELL COMPLETION section and usage line to
      `help_data.sh`; regenerate `docs/brewmaster.1` and
      `tests/fixtures/help*.txt`; `tests/test_docs.sh` passes
- [x] 3.2 Add `completion`, its shell argument and `--shell=` to
      `completions/brewmaster.{bash,zsh,fish}`
- [x] 3.3 README Shell Completions: lead with `brewmaster completion`

## 4. Tests

- [x] 4.1 `tests/test_completion.sh`: lookup order, print mode, unknown
      shell, status for zsh/bash/fish, configured heuristic, exit codes
- [x] 4.2 Run all test files and shellcheck on `bin/brewmaster` and
      `lib/brewmaster/**/*.sh`

## 5. Close

- [ ] 5.1 Flip M12 to `[x] done` in `ROADMAP.md` with the as-built note
      (CHANGELOG entry lands with the 0.13.0 bump)
