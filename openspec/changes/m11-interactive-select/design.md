## Approach

One helper in `lib/brewmaster/core/ui.sh` owns every `fzf` invocation in
the CLI. Both call sites stop passing `fzf` options of their own.

```
ui_select "$preselect" "$prompt" [extra fzf args...]
# Reads candidate lines on stdin, writes selected lines to stdout.
# $1 preselect: "all" (opt-out) | "none" (opt-in)
# $2 prompt:    fzf --prompt text
# $3.. extra:   caller-specific fzf args (--delimiter, --with-nth, --preview,
#               --header-lines) passed through verbatim
# Return: 0 with selection on stdout; 1 if fzf is unavailable (caller
#         falls back); 130 if the user aborted (Esc/ctrl-c)
```

The helper always applies:

```bash
--multi --ansi --height=60% --layout=reverse --border
--pointer='>' --marker='x'          # distinct glyphs — see Decisions
--bind 'ctrl-a:select-all,ctrl-d:deselect-all,tab:toggle+down'
--header="$_ui_select_keys"          # generated, not hand-written
```

plus `--bind start:select-all` when `preselect=all` and the probe below
says the running `fzf` supports it.

### The header invariant

`_ui_select_keys` is built in the same function that assembles the
`--bind` string, from the same data. A key appears in the header only if
its bind was added. This is the whole reason the helper exists: today's
bug is two hand-written header strings that drifted from a `--bind`
list that was never written at all. Anything less than generating one
from the other lets the same drift happen again.

### `fzf` capability probe, not version parsing

`start:` as a bind event needs a recent `fzf`. Version-number parsing is
brittle (`0.44.1 (brew)`, distro suffixes, `fzf --version` format has
changed) and would need updating as `fzf` evolves. Instead, probe the
behavior directly, once per process, cached in a global.

**The exit code that matters is 2, not "non-zero."** Measured against
`fzf 0.44.1`:

| Invocation | Exit |
| ---------- | ---- |
| `printf '' \| fzf --bind 'start:select-all' --filter=''` | 1 |
| `printf '' \| fzf --bind 'bogusevent:select-all' --filter=''` | 2 |
| `printf '' \| fzf --bind 'start:bogusaction' --filter=''` | 2 |

Exit 1 is `fzf`'s "no match" for the empty input the probe deliberately
feeds it — the bind was accepted. Exit 2 is the option-parse rejection
that actually signals an unsupported bind. A probe written as
`if fzf ... ; then` would read exit 1 as failure and report every
capable `fzf` as incapable, silently disabling preselect-all and
leaving the opt-in/opt-out split this milestone exists to remove. Test
for 2 explicitly:

```bash
_ui_fzf_supports_start() {
  [[ -n "${_UI_FZF_START:-}" ]] && return "$_UI_FZF_START"
  printf '' | fzf --bind 'start:select-all' --filter='' >/dev/null 2>&1
  # 2 = option parse error (bind unsupported); anything else = accepted.
  # 1 is the expected "no match" for empty input, NOT a failure.
  [[ $? -eq 2 ]] && _UI_FZF_START=1 || _UI_FZF_START=0
  return "$_UI_FZF_START"
}
```

`--filter` runs non-interactively and exits immediately on empty input,
so the probe costs one short-lived process and never touches the
terminal.

When the probe reports no support, `preselect=all` degrades to nothing
preselected, and the generated header omits nothing else — `ctrl-a: all`
is still bound and still honest. The user gets one keystroke of extra
work, not a broken picker.

### Verified against a real fzf

Run on `fzf 0.44.1` (Debian build, older than any current Homebrew
`fzf` — so a floor, not a best case):

- `--bind 'start:select-all'` **works**: three input lines, all three
  returned. Preselect-all is achievable as designed.
- `fzf --multi` with nothing marked returns **exactly one line**, the
  one under the cursor. The Enter-upgrades-one-package defect is
  confirmed, not inferred.
- `--marker='✓' --pointer='▸'` are **accepted** — the multi-byte glyph
  concern behind the ASCII decision below did not reproduce. See
  Decisions.

Still unverified: that `ctrl-a` is bound to `beginning-of-line` by
default rather than `select-all`. Keystroke injection through a pty
failed in the environment used (the control case returned nothing
either, so this is not negative evidence). Task 0.1 keeps it, to be
checked on macOS against the Homebrew `fzf` the tool actually ships
against.

### `upgrade`: opt-out and the risk column

`run_upgrade` currently builds `report_rows` as
`"$name  ${old_sv}  ->  ${new_sv}  [${kind}]"` and passes
`"$name"$'\t'"$row"` to `fzf`, recovering the name with `cut -f1`. That
tab-delimited shape is kept — it is what makes `--with-nth` unnecessary
here — but the row itself is rebuilt through `ui_table_row` so the
picker's columns align like every other table in the CLI, with the risk
score appended when `$CHECK_DEPS` is set (it is already in
`upgrade_meta`, colored via the existing `_depgraph_risk_color`).

The post-selection filter loop currently runs
`echo "$selected" | grep -qFx "$pkg"` once per candidate — a subprocess
per package inside a loop, the exact pattern M2 and M6 removed
elsewhere. Replace with a single associative-array lookup built once
from `$selected`.

### `cleanup`: same helper, opt-in

`cleanup_main`'s call keeps its `--delimiter='|' --with-nth=2,1,3,4` and
its `--preview`, passed through as extra args, and passes
`preselect=none`. Its hand-written header string goes away.

Note the existing `--with-nth=2,1,3,4` reorders columns to
`category name score reason`; if a `--header-lines=1` column header is
added, the header row must be written in *input* order (`name|category|
score|reason`) so the reorder lands correctly.

## Frozen contract conflict

`docs/ARCHIVE_ROADMAP.md` is frozen (M0–M5). Two of its statements are
in play, and they pull in opposite directions:

**Supports this milestone.** The `[x]`/`[ ]` markers, the
`ctrl-a: select all · ctrl-d: deselect` key row, and the visible risk
score are all specified in the frozen mockups (:355-372, :478-495).
Implementing them is closing a drift between the frozen contract and
what shipped — not redesigning the contract.

**Blocks one task.** ARCHIVE_ROADMAP.md:370 states plainly: *"`fzf` is
an optional dependency — if not installed, `--interactive` exits with a
clear error message pointing to `brew install fzf`"*. That is the
frozen contract for the hard `exit 1` at `cleanup.sh:324`, and
`tests/test_cleanup.sh` test 24 asserts it directly (`exit 1`, output
mentions `fzf`).

So the proposal's `cleanup` no-`fzf` fallback is **not** the
convention-9 violation it first appears to be. AGENTS.md convention 9 requires
"degrade gracefully with a clear install message"; a clear install
message is exactly what the current code emits. The frozen design chose
hard-exit deliberately, and M7 superseded that choice for `upgrade`
only — because there the gate became mandatory, so exiting would have
made the command unusable without `fzf`. `cleanup --interactive` is an
explicitly requested optional mode; refusing it is defensible.

**Decision required from the maintainer before task 6 is implemented.**
Implementing it means editing a frozen contract line and rewriting a
frozen test — both forbidden by AGENTS.md without an explicit
exemption. Task 6 is isolated so the rest of the milestone lands either
way. If it goes ahead, ARCHIVE_ROADMAP.md:370 must be amended in the
same commit with a note pointing at this change, so the archive stays
truthful rather than silently contradicted.

## Decisions

- **Marker/pointer glyphs.** ARCHIVE_ROADMAP draws `[x]`/`[ ]`. `fzf`'s
  `--marker`/`--pointer` take a single display cell, so literal `[x]`
  is not expressible. `--marker='x' --pointer='>'` is the closest
  faithful ASCII rendering and is the default choice, since this output
  is not covered by `NO_COLOR` and has to survive any terminal font.
  The original reason to rule out `✓`/`▸` — that older `fzf` might
  reject multi-byte markers — was tested and did not hold (accepted on
  0.44.1), so this is now purely a taste call the maintainer can flip
  in task 1.2 at no technical cost.
- **`--height=60%` inline rather than full screen.** The risk warnings
  `run_upgrade` prints before the gate (`Warning: <pkg> risk N/10`) are
  the context the user needs while deciding. Full-screen `fzf` erases
  them.
- **Preselect mode is an argument, not a policy in the helper.**
  `upgrade` is opt-out, `cleanup` is opt-in, and that asymmetry is
  intentional (upgrading is reversible via snapshot; removal is the
  destructive one AGENTS.md convention 10 guards). The helper stays unopinionated.
- **Enter with no marks stays fzf-native for `cleanup`.** In opt-in
  mode, Enter on an unmarked list returns the cursor line. For
  `cleanup` that is a deliberate single-select idiom and the removal
  still prints `==> brew uninstall <pkg>` per package. For `upgrade`
  the trap disappears because everything starts marked.

## Alternatives rejected

- **Fix the two call sites separately without a helper.** Cheaper now,
  but keeps the header string and the bind list in two files with
  nothing tying them together — the exact condition that produced this
  bug. Rejected for the same reason M8 rejected five hand-rolled table
  implementations.
- **Parse `fzf --version` to gate `start:select-all`.** Brittle against
  a format that has already changed once. The probe tests the thing
  that actually matters.
- **Make `upgrade` opt-in but treat "no marks" as "all".**
  Indistinguishable at the `fzf` boundary from a deliberate
  single-package Enter, so it would break the one selection users can
  currently make on purpose.

## Testing

`fzf` is mocked in three test files today, and every mock is a
`head -1` stub that only proves selection filtering works. Two things
need coverage the mocks cannot give:

- **Options actually passed.** Replace the stubs with a mock that
  records its own `"$@"` to a file, then assert the bind string
  contains every key named in the header and vice versa. This is the
  regression test for the original bug and it needs no real `fzf`.
- **Preselect default.** Assert `upgrade`'s invocation carries
  `start:select-all` when the probe succeeds, and that a probe failure
  still produces a valid invocation.

The `NO_COLOR`/non-TTY guarantee is unaffected: `ui_select` only runs
under `! $YES_FLAG` on an interactive path, and `[ -t 1 ]` already
makes every captured test output colorless.
