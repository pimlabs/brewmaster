#!/usr/bin/env bash
# ui_select tests: the fzf invocation the shared picker assembles. fzf is
# mocked by a script that records its argv, so no real fzf or TTY is
# needed. The invariant under test is the one M11 exists for: the
# --header advertises exactly the keys the --bind string binds.
# shellcheck disable=SC2015,SC2317 # `&& ok || bad` is the assert idiom every test file uses
set -uo pipefail

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$DIR/../lib/brewmaster"

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

MOCK_BIN="$(mktemp -d)"
ARGS_LOG="$(mktemp)"
CALLS_LOG="$(mktemp)"
OUT_FILE="$(mktemp)"
trap 'rm -rf "$MOCK_BIN"; rm -f "$ARGS_LOG" "$CALLS_LOG" "$OUT_FILE"' EXIT
export ARGS_LOG CALLS_LOG

# Mock fzf: record argv one per line (last invocation wins), count calls,
# then behave like the old `head -n1` stubs and select the first
# candidate. The probe's --filter call lands here too and exits 0, which
# ui_select reads as "start: supported".
cat > "$MOCK_BIN/fzf" <<'FZFEOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ARGS_LOG"
echo x >> "$CALLS_LOG"
head -n1
FZFEOF
chmod +x "$MOCK_BIN/fzf"
export PATH="$MOCK_BIN:$PATH"

# shellcheck source=../lib/brewmaster/core/ui.sh
source "$LIB/core/ui.sh"
ui_color_init

# arg_value NAME — value of the recorded --NAME=value argument
arg_value()   { grep -m1 -- "^--$1=" "$ARGS_LOG" | cut -d= -f2-; }
# header_keys — keys the header advertises ("tab: toggle · ctrl-a: all" -> tab, ctrl-a)
header_keys() { arg_value header | grep -oE '[a-z-]+:' | tr -d ':'; }
# bind_keys — keys the --bind string binds, minus the start: event
bind_keys()   { arg_value bind | tr ',' '\n' | cut -d: -f1 | grep -vx start; }
calls()       { grep -c x "$CALLS_LOG" || true; }

# --- 1. preselect=all: candidates flow through, the mock's pick comes back ---
unset _UI_FZF_START
sel="$(printf 'alpha\nbeta\n' | ui_select all 'P > ')"; rc=$?
[ "$rc" -eq 0 ]      && ok || bad "ui_select all: exit 0 (got $rc)"
[ "$sel" = "alpha" ] && ok || bad "ui_select all: returns the selection (alpha), got '$sel'"

# --- 2. the invariant: every advertised key is bound, every bound key is advertised ---
missing_bind=""; missing_header=""
while read -r k; do bind_keys   | grep -qx "$k" || missing_bind+=" $k";   done < <(header_keys)
while read -r k; do header_keys | grep -qx "$k" || missing_header+=" $k"; done < <(bind_keys)
[ -z "$missing_bind" ]   && ok || bad "header advertises unbound key(s):$missing_bind"
[ -z "$missing_header" ] && ok || bad "bound key(s) missing from header:$missing_header"
[ "$(header_keys | wc -l | tr -d ' ')" -ge 3 ] && ok || bad "header names at least tab, ctrl-a, ctrl-d"

# --- 3. ctrl-a really means select-all (the original bug) ---
arg_value bind | grep -q 'ctrl-a:select-all' && ok || bad "ctrl-a is bound to select-all"

# --- 4. marker and pointer are both set and differ ---
marker="$(arg_value marker)"; pointer="$(arg_value pointer)"
[ -n "$marker" ] && [ -n "$pointer" ] && [ "$marker" != "$pointer" ] \
  && ok || bad "marker ('$marker') and pointer ('$pointer') set and distinct"

# --- 5. inline picker: a --height is passed ---
[ -n "$(arg_value height)" ] && ok || bad "--height passed (inline, not full screen)"

# --- 6. preselect=all with a capable fzf binds start:select-all ---
arg_value bind | grep -q '^start:select-all,' && ok || bad "preselect=all: start:select-all bound"

# --- 7. preselect=none never binds start: ---
printf 'alpha\nbeta\n' | ui_select none 'P > ' >/dev/null
arg_value bind | grep -q 'start:' && bad "preselect=none: must not bind start:" || ok

# --- 8. extra fzf args pass through verbatim ---
printf 'a|x\n' | ui_select none 'P > ' --delimiter='|' --with-nth=2 >/dev/null
grep -qx -- "--delimiter=|" "$ARGS_LOG" && grep -qx -- "--with-nth=2" "$ARGS_LOG" \
  && ok || bad "extra fzf args passed through"

# --- 9. the probe runs once, then its cached answer is reused (also by
#        subshells, which inherit it; a pick inside $(...) cannot warm the
#        parent's cache, so the cache is warmed here by direct calls) ---
unset _UI_FZF_START; : > "$CALLS_LOG"
_ui_fzf_supports_start; rc1=$?
_ui_fzf_supports_start; rc2=$?
[ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && [ "$(calls)" -eq 1 ] \
  && ok || bad "probe cached: expected 1 fzf call across two checks, got $(calls) (rc $rc1/$rc2)"
: > "$CALLS_LOG"
printf 'alpha\n' | ui_select all 'P > ' >/dev/null
[ "$(calls)" -eq 1 ] && ok || bad "warm cache: a pick makes exactly 1 fzf call, got $(calls)"
unset _UI_FZF_START; : > "$CALLS_LOG"
printf 'alpha\n' | ui_select all 'P > ' >/dev/null
[ "$(calls)" -eq 2 ] && ok || bad "cold cache: a pick makes 2 fzf calls (probe + picker), got $(calls)"

# --- 10. fzf that rejects start: (exit 2 on the probe) degrades to no preselect ---
cat > "$MOCK_BIN/fzf" <<'FZFEOF'
#!/usr/bin/env bash
for a in "$@"; do [[ "$a" == --filter* ]] && exit 2; done
printf '%s\n' "$@" > "$ARGS_LOG"
head -n1
FZFEOF
unset _UI_FZF_START
sel="$(printf 'alpha\nbeta\n' | ui_select all 'P > ')"; rc=$?
[ "$rc" -eq 0 ] && [ "$sel" = "alpha" ] && ok || bad "probe failure: picker still works (rc=$rc sel='$sel')"
arg_value bind | grep -q 'start:' && bad "probe failure: start: must not be bound" || ok
arg_value bind | grep -q 'ctrl-a:select-all' && ok || bad "probe failure: ctrl-a still bound (header stays honest)"

# --- 11. missing fzf: returns 1 without exiting, nothing on stdout ---
#     Run in the current shell (not a $(...) subshell) so an `exit` in the
#     helper would kill this test file, which is exactly what must not happen.
command() { [[ "$1" == "-v" && "${2:-}" == "fzf" ]] && return 1; builtin command "$@"; }
ui_select all 'P > ' < <(printf 'alpha\n') > "$OUT_FILE"; rc=$?
unset -f command
[ "$rc" -eq 1 ]        && ok || bad "missing fzf: returns 1 (got $rc)"
[ ! -s "$OUT_FILE" ]   && ok || bad "missing fzf: writes no selection"

echo "Passed: $pass, Failed: $fail"
(( fail == 0 ))
