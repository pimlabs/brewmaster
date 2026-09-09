## 1. Spec

- [ ] 1.1 Add `lib/brewmaster/core/cli_spec.sh` with `_cli_spec` and the
      grammar in its header; records for every command, sub-subcommand,
      positional and flag the CLI parses today

## 2. Generator

- [ ] 2.1 Add `docs/gen-completions.sh` with the loader (`_spec_load`),
      the query helpers and the `bash|zsh|fish` dispatch
- [ ] 2.2 `_emit_bash`, `_emit_zsh`, `_emit_fish`: same completions in
      the same contexts as the hand-written scripts; deterministic
      output; generated-file header
- [ ] 2.3 Regenerate `completions/brewmaster.{bash,zsh,fish}` from the
      spec and commit them

## 3. Tests

- [ ] 3.1 `tests/test_completions.sh`: drift for all three, spec ↔
      parser both directions, spec ↔ help, syntax checks where the
      shell exists
- [ ] 3.2 Run all test files and shellcheck on `bin/brewmaster`,
      `lib/brewmaster/**/*.sh` and `docs/gen-completions.sh`

## 4. Docs and close

- [ ] 4.1 CONTRIBUTING: the "adding a command or flag" recipe; AGENTS.md
      layout line for `cli_spec.sh` and `gen-completions.sh`
- [ ] 4.2 Flip M13 to `[x] done` in `ROADMAP.md`; as-built note in
      `docs/MILESTONES.md` (CHANGELOG lands with the 0.14.0 bump)
