## 1. Review gate in run_upgrade

- [ ] 1.1 After the candidate-collection loop in `run_upgrade`
      (`lib/brewmaster/upgrade.sh`), and before the DRY_RUN check, add the
      review gate: skip it entirely when `$DRY_RUN` or `$YES_FLAG` is
      true, or when `upgrade_list` is empty
- [ ] 1.2 When `fzf` is installed, reuse the existing multi-select block
      (currently gated by `$INTERACTIVE`) unconditionally as the review
      step
- [ ] 1.3 When `fzf` is not installed, print the candidate table (same
      format as the `--dry-run` table) and prompt once with `[y/N]` for
      the whole batch via `read -r ans </dev/tty`
- [ ] 1.4 Wire the fallback's y/N answer to either proceed with the full
      `upgrade_list` unchanged, or clear it (mirroring how the `fzf` path
      already clears `upgrade_list`/`report_rows`/`upgrade_meta` when
      nothing is selected)

## 2. Flag semantics

- [ ] 2.1 Remove the `$INTERACTIVE`-gated hard `exit 1` for missing
      `fzf` in the upgrade path (folded into the fallback in 1.3)
- [ ] 2.2 Confirm `--interactive`/`-i` is still accepted (no parse error)
      but has no additional effect on `upgrade` beyond what the new
      default review already does
- [ ] 2.3 Confirm `--yes`/`-y` still auto-confirms MEDIUM-risk packages
      as before, in addition to its new review-skip effect

## 3. Help text

- [ ] 3.1 Update `bin/brewmaster`'s UPGRADE section: `--interactive, -i`
      description reflects that review now happens by default;
      `--yes, -y` description reflects that it also skips the review step
- [ ] 3.2 Regenerate `tests/fixtures/help.txt` to match

## 4. Tests

- [ ] 4.1 Update `tests/test_cli.sh`'s existing non-dry-run execution
      test to pass `--yes` (it currently relies on the no-prompt default
      that this change removes)
- [ ] 4.2 Add a test for the no-`fzf` fallback: candidates present,
      mocked `[y/N]` answer `y` upgrades, answer `n` (or EOF) does not
- [ ] 4.3 Add a test confirming `--yes` skips the review step entirely
      (no prompt, all candidates upgraded)
- [ ] 4.4 Add a test confirming `--dry-run` never triggers the review
      step (candidate table only, no prompt, no execution)
- [ ] 4.5 Run the full test suite and confirm no other regressions

## 5. Docs

- [ ] 5.1 Update `ROADMAP.md` M7 status to `[x] done` once merged, noting
      the actual scope (review-by-default, not opt-in) versus the
      original plan
