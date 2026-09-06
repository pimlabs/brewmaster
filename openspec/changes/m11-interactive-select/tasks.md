## 0. Verify the assumptions before writing code

- [ ] 0.1 On macOS with the Homebrew `fzf`, confirm `ctrl-a` in the
      `upgrade` review gate does not select all. (The other half of this
      check — Enter with nothing marked selecting exactly one row — is
      already confirmed on `fzf 0.44.1`; see task 0.2.) Record the
      `fzf --version` used.
- [x] 0.2 Confirm the `_ui_fzf_supports_start` probe discriminates.
      **Done — and it found the probe as first drafted was wrong.**
      Measured on `fzf 0.44.1`: a supported bind exits **1** (`fzf`'s
      "no match" for the empty probe input), while an unsupported event
      or action exits **2** (option parse error). The original
      `if fzf ...; then` form would have read every capable `fzf` as
      incapable. design.md now specifies testing for exit 2 explicitly.
      Also confirmed in the same run: `start:select-all` genuinely
      preselects all rows, `fzf --multi` with nothing marked returns
      exactly one line, and `--marker='✓' --pointer='▸'` parse fine.

## 1. Add the shared picker helper to ui.sh

- [x] 1.1 Add `_ui_fzf_supports_start` to
      `lib/brewmaster/core/ui.sh` — probe once, cache the result in
      `_UI_FZF_START`, return it on later calls. Discriminate on exit
      **2**, not on non-zero (see design.md; exit 1 means the bind was
      accepted)
- [x] 1.2 Add `ui_select "$preselect" "$prompt" [extra fzf args...]`
      with the header comment convention every public function in this
      project uses (purpose, args, stdout, return code). It applies
      `--multi --ansi --height=60% --layout=reverse --border`,
      `--pointer='>' --marker='x'`, and
      `--bind 'ctrl-a:select-all,ctrl-d:deselect-all,tab:toggle+down'`,
      adding `start:select-all` only when `preselect=all` and the probe
      succeeds
- [x] 1.3 Build the `--header` string in the same function, from the
      same bind list, so a key can only be advertised if it was bound —
      the invariant this milestone exists to establish
- [x] 1.4 Return 1 (not `exit`) when `fzf` is absent, so callers own
      their own fallback

## 2. Route the upgrade review gate through the helper

- [x] 2.1 Replace the inline `fzf` call in `lib/brewmaster/upgrade.sh`
      (currently lines 138-142) with `ui_select all 'Upgrade > '`,
      deleting the hand-written `--header`
- [x] 2.2 Replace the per-candidate `echo "$selected" | grep -qFx`
      filter loop with a single associative-array lookup built once
      from the selection
- [x] 2.3 Confirm `--dry-run` and `--yes` still bypass the gate exactly
      as before, and that a zero-candidate run never reaches `ui_select`

## 3. Show the risk score in the upgrade picker

- [ ] 3.1 Rebuild `report_rows` through `ui_table_row` so picker
      columns align with the rest of the CLI's tables
- [ ] 3.2 Append the risk score column when `$CHECK_DEPS` is set,
      reading it from `upgrade_meta` (already carried, never displayed)
      and coloring it with the existing `_depgraph_risk_color`
- [ ] 3.3 Verify the non-`fzf` fallback table and the `--dry-run` table
      render the same rows — one row builder, three consumers

## 4. Route cleanup --interactive through the helper

- [x] 4.1 Replace the inline `fzf` call in
      `lib/brewmaster/cleanup.sh` (currently lines 343-348) with
      `ui_select none 'Select packages to remove > '`, passing
      `--delimiter='|' --with-nth=2,1,3,4` and the existing `--preview`
      through as extra args, and deleting the hand-written `--header`
- [x] 4.2 Confirm opt-in behavior is preserved — nothing preselected,
      per AGENTS.md convention 10

## 5. Tests

- [ ] 5.1 Replace the `head -1` `fzf` stubs in `tests/test_audit.sh`,
      `tests/test_profile.sh`, and `tests/test_cleanup.sh` with a mock
      that records its own `"$@"`, keeping their existing
      selection-filtering assertions intact
- [ ] 5.2 Add the regression test for the original bug: every key named
      in the generated `--header` appears in the `--bind` string, and
      every bound key appears in the header
- [ ] 5.3 Assert `upgrade` passes `start:select-all` when the probe
      succeeds, and still produces a valid invocation when it fails
- [ ] 5.4 Assert `cleanup --interactive` passes no `start:` bind
- [ ] 5.5 Run all test files and `shellcheck bin/brewmaster` plus
      `find lib/brewmaster -name '*.sh' | xargs shellcheck`

## 6. Docs

- [ ] 6.1 Update the review-gate paragraph in
      `lib/brewmaster/core/help_data.sh` to describe opt-out selection
      ("all candidates start selected; deselect what you don't want")
- [ ] 6.2 Regenerate `docs/brewmaster.1` via `docs/gen-man.sh` and the
      `tests/fixtures/help*.txt` fixtures; confirm `tests/test_docs.sh`
      drift check passes
- [ ] 6.3 Add the `CHANGELOG.md` entry under a new `[0.12.0]` heading
- [ ] 6.4 Flip M11's status to `[x] done` in `ROADMAP.md` and record
      what was actually built versus planned, following the
      scope-note convention M6-M10 established
