## Approach

Five independent changes, each with its own test, landed as one
milestone because none is worth a release on its own and together they
close every open item from M11–M13.

### Parser: hoisting the command

`_hoist_command` in `bin/brewmaster` runs before the subcommand `case`.
It scans the arguments once: flag words are skipped; a space-form value
flag (the value-taking flags of the spec used without `=`: `--level`,
`--label`, `--risk-threshold`, `--profile`, `--shell`, `--package`,
`--action`, `--since`, `--format`) skips its value too; the first
remaining word decides. If it names a command, that word and the word
right after it (unless that is a flag) move to the front, in order, and
everything else keeps its order; otherwise the arguments are untouched
and the old `$1` logic sees exactly what it saw before. So the existing
`case "$1"` block, the sub-subcommand rule ("the word after the
command") and the flag parser are unchanged; the hoist only rearranges.

Why hoisting instead of scanning inside the parser: the flag loop is a
`while [[ $# -gt 0 ]]` over `$@` with `shift`; the command block reads
`$1` and `$2`. Rewriting `$@` once keeps both untouched and testable in
isolation (`tests/test_parser.sh` exercises the CLI end to end with a
mock `brew`).

Ambiguity accepted: a *package* whose name equals a command
(`why`, `log`, `report`, ...) can no longer be upgraded by bare name
after a flag; `brewmaster upgrade log` still works. No Homebrew formula
is named that way today.

### Completions

The generator already knows which flags take values; the bash emitter
emits that list into the cmd/sub detection loop so it skips a flag's
space-form value exactly as the parser does. The M13 "leading flag →
packages only" branches are removed in all three emitters. For the
`=`-split, the bash script handles `prev == "="` (complete the value of
`COMP_WORDS[COMP_CWORD-2]` against `cur`) and `cur == "="` (complete the
value of `prev` with an empty prefix); the unsplit `--flag=*` arms stay
for shells that removed `=` from `COMP_WORDBREAKS`. Behavior is asserted
with a `COMP_WORDS` harness in `tests/test_completions.sh`.

### Picker render test

`script(1)` allocates the pty on both platforms (BSD: `script -q
/dev/null cmd...`; util-linux: `script -qc "cmd" /dev/null`, detected by
`script --version` succeeding). Keystrokes are written to script's stdin
after a delay so fzf has rendered; the typescript is stripped of ANSI
sequences and inspected: the info line (`101/101 (101)`), the `->`
column on every visible row, the marker glyph for the locale, and the
rows printed after Enter. The test is proven against a copy of
`ui_select` without `--sync` and without `--with-nth=2` (it fails) before
the real one (it passes). CI installs fzf; the test skips only when fzf
or a pty is unavailable.

### Linux baseline

Gate on capability, not OS: `date -u -v-1d +%s` succeeding enables the
BSD-date assertions; otherwise they are skipped with one stderr line and
counted as neither pass nor fail. The TTY test gets a helper that picks
the `script` syntax, so it runs everywhere.

### cleanup

One `jq -r '.formulae[] | "\(.name)\t\(tojson)"'` pass splits the cache
into per-formula files under a temp dir that lives and dies with
`CLEANUP_CACHE`; `_cleanup_formula_json` reads the file. Follow-up
field extractions collapse to one jq per package where the callers'
output is unchanged.
