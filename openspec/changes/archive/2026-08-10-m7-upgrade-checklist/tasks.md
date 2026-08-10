## 1. Review gate in run_upgrade

- [x] 1.1 After the candidate-collection loop in `run_upgrade`
      (`lib/brewmaster/upgrade.sh`), and before the DRY_RUN check, add the
      review gate: skip it entirely when `$DRY_RUN` or `$YES_FLAG` is
      true, or when `upgrade_list` is empty
- [x] 1.2 When `fzf` is installed, reuse the existing multi-select block
      (formerly gated by `$INTERACTIVE`) unconditionally as the review
      step
- [x] 1.3 When `fzf` is not installed, print the candidate table (same
      format as the `--dry-run` table) and prompt once with `[y/N]` for
      the whole batch. Uses plain `read -r ans` (real stdin), not
      `</dev/tty` — this prompt runs after the `while ... <<<"$out"` loop
      has closed, so stdin is free, unlike the two pre-existing
      MEDIUM-risk/profile-confirm prompts inside that loop
- [x] 1.4 Wired the fallback's y/N answer to either proceed with the full
      `upgrade_list` unchanged, or clear it (mirrors how the `fzf` path
      already clears `upgrade_list`/`report_rows`/`upgrade_meta` when
      nothing is selected); either path now prints "Nothing selected."
      and returns 0 if the result is empty

## 2. Flag semantics

- [x] 2.1 Removed the `$INTERACTIVE`-gated hard `exit 1` for missing
      `fzf` in the upgrade path (folded into the fallback in 1.3)
- [x] 2.2 `--interactive`/`-i` is still accepted (no parse error) but has
      no effect on `upgrade` — `$INTERACTIVE` is no longer read anywhere
      in `run_upgrade`; header comment updated accordingly
- [x] 2.3 `--yes`/`-y` still auto-confirms MEDIUM-risk packages as before
      (unchanged code path), in addition to its new review-skip effect

## 3. Help text

- [x] 3.1 Updated `bin/brewmaster`'s UPGRADE and PROFILES sections:
      `--interactive, -i` now documented as a no-op kept for
      compatibility; `--yes, -y` documented as also skipping the review
      step; added a paragraph explaining the default review behavior
- [x] 3.2 Regenerated `tests/fixtures/help.txt` to match

## 4. Tests

- [x] 4.1 Updated `tests/test_cli.sh`'s existing non-dry-run execution
      test to pass `--yes` (it relied on the no-prompt default this
      change removes)
- [x] 4.2 Added a no-`fzf` fallback test in `tests/test_cli.sh`
      (`run_no_fzf` helper strips PATH to MOCK + bare system dirs, with
      `jq` symlinked into MOCK since it's a real dependency but shares a
      directory with the host's real `fzf`): `y` upgrades, `n` doesn't
- [x] 4.3 Added a test confirming `--yes` skips the review step entirely
      (no `[y/N]` prompt text in output, all candidates upgraded)
- [x] 4.4 Added a test confirming `--dry-run` never triggers the review
      step (candidate table only, no prompt, no execution) — also fixed
      two now-obsolete tests in `tests/test_profile.sh` (21, 22) that
      exercised the *old* `--interactive --dry-run` combination, which
      used to consult `fzf` even under dry-run; that combination no
      longer applies since dry-run now always short-circuits before the
      review gate (see design.md's Non-Goals)
- [x] 4.5 Ran the full test suite: all 7 files pass, 246 assertions, 0
      failures. Also fixed two `run_upgrade` calls in `tests/test_audit.sh`
      (tests 22-24) that hung/would hang waiting on a real `fzf` reachable
      via PATH once the review gate became unconditional — added
      `YES_FLAG=true` there since those tests are about audit-log
      content, not the review gate (test 25 already exercises the gate
      via a mocked `fzf` and needed no logic change, just a comment
      update). shellcheck clean on `bin/brewmaster` and
      `lib/brewmaster/*.sh`

## 5. Docs

- [x] 5.1 `ROADMAP.md` M7 status and scope description updated to reflect
      actual scope (review-by-default, not opt-in via `--interactive`)
      versus the original plan
