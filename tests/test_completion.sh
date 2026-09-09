#!/usr/bin/env bash
# `brewmaster completion` tests: script lookup across both install layouts,
# print mode, and the status report's "configured" heuristic. brew is
# mocked on PATH (only --prefix is ever asked); HOME, ZDOTDIR and SHELL
# point at temp dirs, so no real rc file or completion directory is read.
# shellcheck disable=SC2015,SC2317 # `&& ok || bad` is the assert idiom every test file uses
set -uo pipefail

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$DIR/../lib/brewmaster"

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

# Physical path: on macOS mktemp -d returns /var/folders/... which is a
# symlink to /private/var/..., and the lookup normalizes with cd -P.
TMP="$(cd -P "$(mktemp -d)" && pwd)"
trap 'rm -rf "$TMP"' EXIT
MOCK_BIN="$TMP/bin"; PREFIX="$TMP/prefix"; CHECKOUT="$TMP/checkout"; KEG="$TMP/keg"
BREW_LOG="$TMP/brew.log"
mkdir -p "$MOCK_BIN" "$PREFIX/etc/bash_completion.d" "$PREFIX/share/zsh/site-functions" \
         "$PREFIX/share/fish/vendor_completions.d" "$CHECKOUT/lib/brewmaster" \
         "$CHECKOUT/completions" "$KEG/libexec/brewmaster" "$TMP/home"
export HOME="$TMP/home"
unset ZDOTDIR
export BREW_LOG PREFIX
cat > "$MOCK_BIN/brew" <<'BREWEOF'
#!/usr/bin/env bash
echo "$*" >> "$BREW_LOG"
case "$1" in --prefix) echo "$PREFIX" ;; esac
BREWEOF
chmod +x "$MOCK_BIN/brew"
export PATH="$MOCK_BIN:$PATH"

# Fixture scripts with distinct contents, so the lookup order is observable.
for sh in bash zsh fish; do echo "# checkout $sh" > "$CHECKOUT/completions/brewmaster.$sh"; done
echo "# formula bash" > "$PREFIX/etc/bash_completion.d/brewmaster"
echo "# formula zsh"  > "$PREFIX/share/zsh/site-functions/_brewmaster"
echo "# formula fish" > "$PREFIX/share/fish/vendor_completions.d/brewmaster.fish"
restore_zsh() { echo "# formula zsh" > "$PREFIX/share/zsh/site-functions/_brewmaster"; }

logv() { :; }
VERBOSE=false
# shellcheck source=../lib/brewmaster/core/ui.sh
source "$LIB/core/ui.sh"; ui_color_init
# shellcheck source=../lib/brewmaster/completion.sh
source "$LIB/completion.sh"
COMPLETION_SHELL=""; COMPLETION_TARGET=""

# --- 1. _completion_shell: explicit, from $SHELL, unsupported ---
[ "$(_completion_shell zsh)" = "zsh" ]                    && ok || bad "explicit shell name"
[ "$(SHELL=/bin/bash _completion_shell "")" = "bash" ]    && ok || bad "shell derived from \$SHELL"
out="$(_completion_shell tcsh 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && echo "$out" | grep -q 'bash, zsh, fish' && ok || bad "unsupported shell: exit 1 naming bash, zsh, fish"

# --- 2. lookup: the checkout layout wins and brew is never invoked ---
LIB_DIR="$CHECKOUT/lib/brewmaster"; : > "$BREW_LOG"
p="$(_completion_script_path zsh)"; rc=$?
[ "$rc" -eq 0 ] && [ "$p" = "$CHECKOUT/completions/brewmaster.zsh" ] && ok || bad "checkout layout resolved (got '$p')"
[ ! -s "$BREW_LOG" ] && ok || bad "checkout hit: brew not invoked"

# --- 3. lookup: the formula's targets under brew --prefix ---
LIB_DIR="$KEG/libexec/brewmaster"; : > "$BREW_LOG"
[ "$(_completion_script_path bash)" = "$PREFIX/etc/bash_completion.d/brewmaster" ]              && ok || bad "formula bash target"
[ "$(_completion_script_path zsh)"  = "$PREFIX/share/zsh/site-functions/_brewmaster" ]          && ok || bad "formula zsh target"
[ "$(_completion_script_path fish)" = "$PREFIX/share/fish/vendor_completions.d/brewmaster.fish" ] && ok || bad "formula fish target"
grep -qx -- '--prefix' "$BREW_LOG" && ok || bad "formula lookup asks brew --prefix"

# --- 4. lookup: nothing in either layout -> 1 ---
rm "$PREFIX/share/zsh/site-functions/_brewmaster"
_completion_script_path zsh >/dev/null; rc=$?
[ "$rc" -eq 1 ] && ok || bad "missing everywhere: return 1"
restore_zsh

# --- 5. print mode: exactly the script; unsupported shell; missing script ---
COMPLETION_SHELL=zsh
out="$(completion_main)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "# formula zsh" ] && ok || bad "completion zsh prints the script exactly (rc=$rc, out='$out')"
COMPLETION_SHELL=tcsh
completion_main >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok || bad "completion tcsh: exit 1"
COMPLETION_SHELL=zsh; rm "$PREFIX/share/zsh/site-functions/_brewmaster"
out="$(completion_main 2>&1 >/dev/null)"; rc=$?
[ "$rc" -eq 1 ] && echo "$out" | grep -q 'brew install' && ok || bad "print with no script: exit 1 and an install hint on stderr"
restore_zsh
COMPLETION_SHELL=""

# --- 6. status: zsh from $SHELL, installed, not configured -> snippet, exit 0 ---
export SHELL=/bin/zsh
out="$(completion_main)"; rc=$?
[ "$rc" -eq 0 ] && ok || bad "status zsh: exit 0 when installed (rc=$rc)"
echo "$out" | grep -q '^Shell:  *zsh (from \$SHELL)'                                        && ok || bad "status: shell line from \$SHELL"
echo "$out" | grep -q "^Script:  *$PREFIX/share/zsh/site-functions/_brewmaster"              && ok || bad "status: script path"
echo "$out" | grep -q '^Configured:  *no reference in ~/.zshrc, ~/.zprofile, ~/.zshenv'      && ok || bad "status: not configured lists the rc files"
echo "$out" | grep -q 'FPATH='                                                                && ok || bad "status: zsh snippet printed when not configured"
echo "$out" | grep -q 'cannot see the live shell'                                            && ok || bad "status: heuristic is labeled as such"

# --- 7. status: zsh configured via brew shellenv in ~/.zprofile ---
echo 'eval "$(brew shellenv)"' > "$HOME/.zprofile"
out="$(completion_main)"
echo "$out" | grep -q '^Configured:  *~/.zprofile references'  && ok || bad "status: brew shellenv counts as configured"
echo "$out" | grep -q 'set up to load it'                      && ok || bad "status: configured message"
echo "$out" | grep -q 'FPATH='                                 && bad "status: no snippet when configured" || ok
rm "$HOME/.zprofile"

# --- 8. status: ZDOTDIR honored; site-functions in its .zshrc ---
export ZDOTDIR="$TMP/zdot"; mkdir -p "$ZDOTDIR"
echo 'FPATH="/opt/homebrew/share/zsh/site-functions:$FPATH"' > "$ZDOTDIR/.zshrc"
out="$(completion_main)"
echo "$out" | grep -q "^Configured:  *$ZDOTDIR/.zshrc references" && ok || bad "status: ZDOTDIR rc scanned (got: $(echo "$out" | grep '^Configured'))"
unset ZDOTDIR

# --- 9. status: --shell=bash overrides $SHELL; bash heuristic ---
COMPLETION_TARGET=bash
out="$(completion_main)"
echo "$out" | grep -q '^Shell:  *bash (from --shell)' && ok || bad "--shell overrides \$SHELL"
echo "$out" | grep -q 'bash-completion@2'             && ok || bad "bash: snippet when not configured"
echo '[[ -r "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]] && . "$(brew --prefix)/etc/profile.d/bash_completion.sh"' > "$HOME/.bash_profile"
out="$(completion_main)"
echo "$out" | grep -q '^Configured:  *~/.bash_profile references' && ok || bad "bash: bash_completion in .bash_profile counts"
rm "$HOME/.bash_profile"

# --- 10. status: fish never needs configuration ---
COMPLETION_TARGET=fish
out="$(completion_main)"; rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'vendor_completions.d itself' && echo "$out" | grep -q 'set up to load it' \
  && ok || bad "fish: configured by nature (rc=$rc)"

# --- 11. status: not installed -> exit 1 with an install hint, even when configured ---
COMPLETION_TARGET=zsh; echo 'eval "$(brew shellenv)"' > "$HOME/.zshrc"
rm "$PREFIX/share/zsh/site-functions/_brewmaster"
out="$(completion_main)"; rc=$?
[ "$rc" -eq 1 ] && echo "$out" | grep -q '^Script:  *not found' && echo "$out" | grep -q 'not installed' \
  && ok || bad "not installed: exit 1 and install hint (rc=$rc)"
restore_zsh; rm "$HOME/.zshrc"

# --- 12. nothing under $HOME or the prefix is written by a status run ---
inventory() { find "$HOME" "$PREFIX" -type f | sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(wc -c < "$f")"; done; }
before="$(inventory)"
completion_main >/dev/null; COMPLETION_TARGET=bash; completion_main >/dev/null; COMPLETION_TARGET=zsh
after="$(inventory)"
[ "$before" = "$after" ] && ok || bad "status run must not create or change any file"

# --- 13. piped output carries no escape sequences ---
( ui_color_init; completion_main ) | grep -q $'\x1b' && bad "no ANSI escapes in piped output" || ok

echo "Passed: $pass, Failed: $fail"
(( fail == 0 ))
