## 1. Parser

- [ ] 1.1 `_hoist_command` in `bin/brewmaster`; note in `help_data.sh`;
      regenerate the man page and fixtures
- [ ] 1.2 `tests/test_parser.sh`: flag-first forms, space-form values,
      package after flag, help after flag, command-first unchanged

## 2. Completions

- [ ] 2.1 Emitters offer commands after a leading flag again and skip
      space-form values in bash's command detection
- [ ] 2.2 bash `=`-split completion; behavioral assertions in
      `tests/test_completions.sh`; regenerate `completions/`

## 3. Tests

- [ ] 3.1 `tests/test_ui_render.sh` (pty, real fzf) with regression
      proofs; `brew install fzf` in CI
- [ ] 3.2 `tests/test_audit.sh` / `tests/test_cli.sh` Linux-clean

## 4. cleanup

- [ ] 4.1 Per-formula split of the cache; contracts unchanged; timing
      before/after; assertions in `tests/test_cleanup.sh`

## 5. Close

- [ ] 5.1 All test files pass on Linux (0 failures) and macOS CI;
      shellcheck clean
- [ ] 5.2 ROADMAP M14 `[x] done`; as-built note in `docs/MILESTONES.md`;
      archive; CHANGELOG with the 0.15.0 bump
