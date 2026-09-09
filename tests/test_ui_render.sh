#!/usr/bin/env bash
# ui_select render test: the real fzf, inside a real pseudo-terminal.
# Every other test mocks fzf, which is why two rendering bugs shipped
# unnoticed: preselect-all raced fzf's async input and the info line
# read "101/101 (0)" (fixed with --sync), and the name<TAB>row lines
# upgrade.sh feeds the picker were rendered to 8-column tab stops, so
# rows with different name lengths misaligned (fixed with --with-nth=2).
# This file drives fzf under script(1), captures the typescript, strips
# the escape sequences into a flat "screen" and asserts on what the
# user would have seen, plus on what the picker returned.
#
# Skips (exit 0, "Passed: 0, Failed: 0") when fzf or script is missing,
# or when the pty run produced no fzf output at all (some sandboxes
# cannot allocate a pty). Once fzf has rendered, every assertion counts.
# shellcheck disable=SC2015 # `&& ok || bad` is the assert idiom every test file uses
set -uo pipefail

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$DIR/../lib/brewmaster"

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

# skip "$reason" — leave without a verdict: nothing here could run.
# Args:   $1 reason
# Stdout: the summary line run_all.sh expects
# Return: exits 0
skip() {
  echo "skip: $1" >&2
  echo "Passed: 0, Failed: 0"
  exit 0
}

command -v fzf    >/dev/null 2>&1 || skip "fzf not installed"
command -v script >/dev/null 2>&1 || skip "script(1) not installed"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The picker's fzf sees exactly this environment: no user options, a
# fixed terminal size, a known TERM. The child also sets the pty's
# window size with stty, because script(1) gives the pty no size when
# its own stdin is not a terminal (0x0, and fzf renders nothing useful).
export FZF_DEFAULT_OPTS="" FZF_DEFAULT_OPTS_FILE="" COLUMNS=120 LINES=40 TERM=xterm-256color
unset FZF_DEFAULT_COMMAND

# The marker/pointer glyphs the test expects, decided by the same
# locale rule ui_select applies (the child inherits this environment).
POINTER='>' MARKER='x'
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) POINTER='▸' MARKER='✓' ;;
esac

# --- rows: 101 candidates, built the way upgrade.sh builds fzf_display ---
# name<TAB><padded table row>, name lengths spanning several tab stops
# (p1 .. p101xxxxxxxxxx) so a tab rendered to 8-column stops shows up as
# misaligned "->" columns. The type column carries an SGR sequence like
# upgrade.sh's ui_colorize output, so --ansi is exercised too.
# shellcheck source=../lib/brewmaster/core/ui.sh
source "$LIB/core/ui.sh"
COLOR_RESET=$'\033[0m'
names=(); olds=(); news=()
name_w=0; old_w=0; new_w=0
for ((i = 1; i <= 101; i++)); do
  pad=""
  for ((k = 0; k < i % 11; k++)); do pad+="x"; done
  names+=("p${i}${pad}"); olds+=("1.${i}.0"); news+=("1.$((i + 1)).0")
  (( ${#names[$((i-1))]} > name_w )) && name_w=${#names[$((i-1))]}
  (( ${#olds[$((i-1))]}  > old_w  )) && old_w=${#olds[$((i-1))]}
  (( ${#news[$((i-1))]}  > new_w  )) && new_w=${#news[$((i-1))]}
done
ROWS="$WORK/rows.txt"; EXPECTED="$WORK/expected.txt"
: > "$ROWS"
for ((i = 0; i < 101; i++)); do
  if (( i % 5 == 0 )); then
    m_type="$(ui_colorize 7 "" "cask")"
  else
    m_type="$(ui_colorize 7 $'\033[2m' "formula")"
  fi
  row="$(ui_table_row "$name_w" "${names[$i]}" "" "$m_type" \
    "$old_w" "${olds[$i]}" "" "->" "$new_w" "${news[$i]}" "" "[minor]")"
  printf '%s\t%s\n' "${names[$i]}" "$row" >> "$ROWS"
done
printf '%s\n' "${names[@]}" > "$EXPECTED"

# --- the command that runs inside the pty ---
# Args: preselect rows out done. Mirrors upgrade.sh's review gate call,
# records ui_select's exit status, and raises a done flag the keystroke
# feeder polls for.
CHILD="$WORK/child.sh"
cat > "$CHILD" <<CHILDEOF
#!/usr/bin/env bash
set -uo pipefail
source "$LIB/core/ui.sh"
stty cols "\$COLUMNS" rows "\$LINES" 2>/dev/null || true
ui_select "\$1" 'Upgrade > ' --delimiter=\$'\\t' --with-nth=2 < "\$2" | cut -f1 > "\$3"
echo "\${PIPESTATUS[0]}" > "\$3.rc"
touch "\$4"
CHILDEOF

# feed_keys "$done_flag" — press Enter every 1.5s until the child raises
# its done flag (20 tries at most). Repetition is deliberate: fzf's
# --height renderer opens by querying the terminal (ESC[6n cursor
# position, and on newer versions bracketed-paste mode) and consumes the
# first write(s) on the pty as the reply, so a single early Enter is
# silently swallowed; a keystroke that lands before fzf switched the tty
# to raw mode is lost too. Extra Enters after fzf has accepted reach a
# pty nobody reads. Keeping stdin open until the child is done also
# stops BSD script from injecting an EOF into the pty.
# Args:   $1 done-flag path
# Stdout: keystrokes (meant to be piped into script's stdin)
# Return: 0
feed_keys() {
  local i
  for ((i = 0; i < 20; i++)); do
    sleep 1.5
    [ -e "$1" ] && return 0
    printf '\r' || return 0
  done
  return 0
}

# pty_run "$typescript" "$done_flag" cmd args... — run cmd inside a pty
# allocated by script(1), feeding Enter until the done flag appears, with
# the terminal output (both forms echo the session to stdout) captured
# in $typescript. util-linux script takes -c "cmd string" before the
# file; BSD script (macOS) takes the file then the argv. A watchdog
# kills the run after 45s so a picker that never accepts cannot hang
# the suite.
# Args:   $1 typescript path, $2 done-flag path, $3.. the command
# Stdout: none
# Return: script's status, 124 when the watchdog fired
pty_run() {
  local ts="$1" done_flag="$2"; shift 2
  local pid i cmd
  if script --version >/dev/null 2>&1; then
    cmd="$(printf '%q ' "$@")"
    feed_keys "$done_flag" | script -q -c "$cmd" /dev/null > "$ts" 2>&1 &
  else
    feed_keys "$done_flag" | script -q /dev/null "$@" > "$ts" 2>&1 &
  fi
  pid=$!
  for ((i = 0; i < 90; i++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null; sleep 0.5; kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 124
  fi
  wait "$pid"
}

# flatten "$typescript" — turn fzf's --height output into one line per
# drawn segment. The light renderer draws each screen line as
# "\r ESC[nC <SGR..> text": carriage return, cursor forward past the
# border, styled text. Split on \r, replay the leading cursor-forward
# (C), cursor-back (D) and column-absolute (G) moves as indentation,
# drop every other escape sequence, and print what would be visible.
# Column arithmetic is relative, so it holds whether awk counts bytes or
# characters in the multi-byte glyphs.
# Args:   $1 typescript path
# Stdout: flattened screen lines
# Return: 0
flatten() {
  awk '
    BEGIN { esc = sprintf("%c", 27); csi = esc "\\[[^@-~]*[@-~]" }
    {
      n = split($0, segs, "\r")
      for (s = 1; s <= n; s++) {
        seg = segs[s]; col = 0
        while (match(seg, "^" esc "\\[[0-9;?]*[@-~]")) {
          code = substr(seg, RSTART, RLENGTH); seg = substr(seg, RLENGTH + 1)
          fin = substr(code, length(code), 1)
          num = substr(code, 3, length(code) - 3) + 0
          if (fin == "C") col += (num == 0 ? 1 : num)
          else if (fin == "D") col -= (num == 0 ? 1 : num)
          else if (fin == "G") col = (num == 0 ? 0 : num - 1)
        }
        gsub(csi, "", seg)
        gsub(esc "[()][A-Za-z0-9]", "", seg)
        gsub(esc "[^[]", "", seg)
        if (seg == "") continue
        pad = ""; while (length(pad) < col) pad = pad " "
        print pad seg
      }
    }' "$1"
}

# last_info "$screen" — the info line as fzf left it ("101/101 (101)"):
# the last "found/total [(selected)]" token in drawing order.
# Args:   $1 flattened screen path
# Stdout: the token, empty when fzf drew no info line
# Return: 0
last_info() {
  grep -oE '[0-9]+/[0-9]+( \([0-9/]+\))?' "$1" | tail -n 1
}

# --- run 1: preselect=all, the upgrade review gate ---
TS_ALL="$WORK/all.ts"; SEL_ALL="$WORK/all.sel"; DONE_ALL="$WORK/all.done"
pty_run "$TS_ALL" "$DONE_ALL" bash "$CHILD" all "$ROWS" "$SEL_ALL" "$DONE_ALL"
SCREEN_ALL="$WORK/all.screen"
flatten "$TS_ALL" > "$SCREEN_ALL"
grep -q 'Upgrade >' "$SCREEN_ALL" || skip "pty run produced no fzf output (cannot allocate a pty here?)"

# (a) every row starts selected: the info line settles on 101/101 (101)
info="$(last_info "$SCREEN_ALL")"
[ "$info" = "101/101 (101)" ] && ok || bad "preselect=all info line: want '101/101 (101)', got '${info:-<none>}'"

# (b) visible rows: no tab, and "->" in the same column on every row
rows_seen=0; cols=""; tabs=0
while IFS= read -r line; do
  rows_seen=$((rows_seen+1))
  prefix="${line%%->*}"
  cols+="${#prefix}"$'\n'
  case "$line" in *$'\t'*) tabs=$((tabs+1)) ;; esac
done < <(grep -- '->' "$SCREEN_ALL")
distinct="$(printf '%s' "$cols" | sort -u | grep -c .)"
[ "$rows_seen" -ge 10 ]  && ok || bad "expected at least 10 rendered rows, saw $rows_seen"
[ "$tabs" -eq 0 ]        && ok || bad "$tabs rendered row(s) contain a literal tab"
[ "$distinct" -eq 1 ]    && ok || bad "'->' sits in $distinct different columns across rendered rows (want 1): $(printf '%s' "$cols" | sort -u | tr '\n' ' ')"

# (c) the selection marker is drawn on every rendered row
marked="$(grep -- '->' "$SCREEN_ALL" | grep -cE "^ *(${POINTER} |  )${MARKER} ")"
[ "$marked" -eq "$rows_seen" ] && ok || bad "marker '${MARKER}' on $marked of $rows_seen rendered rows"

# (d) Enter confirmed the whole batch, names in input order, exit 0
rc="$(cat "$SEL_ALL.rc" 2>/dev/null || echo none)"
[ "$rc" = "0" ] && ok || bad "preselect=all: ui_select exit status $rc"
cmp -s "$SEL_ALL" "$EXPECTED" && ok || bad "preselect=all: stdout after cut -f1 is not the 101 names in order ($(grep -c . "$SEL_ALL" 2>/dev/null || echo 0) lines)"

# --- run 2: preselect=none, opt-in ---
TS_NONE="$WORK/none.ts"; SEL_NONE="$WORK/none.sel"; DONE_NONE="$WORK/none.done"
pty_run "$TS_NONE" "$DONE_NONE" bash "$CHILD" none "$ROWS" "$SEL_NONE" "$DONE_NONE"
SCREEN_NONE="$WORK/none.screen"
flatten "$TS_NONE" > "$SCREEN_NONE"
grep -q 'Upgrade >' "$SCREEN_NONE" && ok || bad "preselect=none: fzf rendered nothing"

# nothing selected: fzf 0.44 and current versions print "(0)" in --multi
# mode; accept a bare count too, reject anything selected.
info="$(last_info "$SCREEN_NONE")"
case "$info" in
  "101/101 (0)"|"101/101") ok ;;
  *) bad "preselect=none info line: want '101/101 (0)' (or bare '101/101'), got '${info:-<none>}'" ;;
esac
marked="$(grep -- '->' "$SCREEN_NONE" | grep -cE "^ *(${POINTER} |  )${MARKER} ")"
[ "$marked" -eq 0 ] && ok || bad "preselect=none: marker drawn on $marked row(s)"

# Enter with nothing selected returns the current row only: the first
# candidate (--layout=reverse starts at the top).
rc="$(cat "$SEL_NONE.rc" 2>/dev/null || echo none)"
[ "$rc" = "0" ] && ok || bad "preselect=none: ui_select exit status $rc"
[ "$(cat "$SEL_NONE" 2>/dev/null)" = "${names[0]}" ] && ok \
  || bad "preselect=none: want only '${names[0]}', got '$(tr '\n' ' ' < "$SEL_NONE" 2>/dev/null)'"

echo "Passed: $pass, Failed: $fail"
[ "$fail" -eq 0 ]
