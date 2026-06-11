#!/usr/bin/env bash
# Cleanup function tests. Uses a mock brew + stat — no real packages touched.
set -uo pipefail

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$DIR/../lib/brewmaster"

NOW="$(date +%s)"
DAY=86400

# --- Fixture epochs ---
IMAGEMAGICK_INSTALLED=$(( NOW - 200*DAY ))   # >180d -> +1
WATCHMAN_INSTALLED=$(( NOW - 30*DAY ))       # <180d
OPENSSL_INSTALLED=$(( NOW - 200*DAY ))       # >180d -> +1
GIT_INSTALLED=$(( NOW - 30*DAY ))
WGET_INSTALLED=$(( NOW - 10*DAY ))

IMAGEMAGICK_ATIME=$(( NOW - 100*DAY ))       # >90d -> +3
WATCHMAN_ATIME=$(( NOW - 100*DAY ))          # >90d -> +3
GIT_ATIME=$(( NOW - 10*DAY ))
WGET_ATIME=$(( NOW - 10*DAY ))
OPENSSL_ATIME=$(( NOW - 10*DAY ))

FALLBACK_EPOCH=$(( NOW - 50*DAY ))           # cellar-mtime fallback for "nosuch"

export NOW DAY
export IMAGEMAGICK_INSTALLED WATCHMAN_INSTALLED OPENSSL_INSTALLED GIT_INSTALLED WGET_INSTALLED
export IMAGEMAGICK_ATIME WATCHMAN_ATIME GIT_ATIME WGET_ATIME OPENSSL_ATIME FALLBACK_EPOCH

# --- Mock environment ---
MOCK_BIN="$(mktemp -d)"
CELLAR_ROOT="$(mktemp -d)"
INFO_JSON_FILE="$(mktemp)"
UNINSTALL_LOG="$(mktemp)"
SNAP_DIR="$(mktemp -d)"
AUDIT_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK_BIN" "$CELLAR_ROOT" "$INFO_JSON_FILE" "$UNINSTALL_LOG" "$SNAP_DIR" "$AUDIT_DIR"' EXIT

export CELLAR_ROOT INFO_JSON_FILE UNINSTALL_LOG
export BREWMASTER_SNAP_DIR="$SNAP_DIR"
export BREWMASTER_AUDIT_LOG="$AUDIT_DIR/audit.log"

mkdir -p "$CELLAR_ROOT/imagemagick" "$CELLAR_ROOT/watchman" "$CELLAR_ROOT/openssl" \
         "$CELLAR_ROOT/git" "$CELLAR_ROOT/wget" "$CELLAR_ROOT/nosuch"

cat > "$INFO_JSON_FILE" <<EOF
{
  "formulae": [
    {
      "name": "imagemagick",
      "pinned": false,
      "installed": [
        {"version": "7.1.1", "installed_on_request": true, "installed_as_dependency": false, "time": $IMAGEMAGICK_INSTALLED}
      ]
    },
    {
      "name": "watchman",
      "pinned": false,
      "installed": [
        {"version": "2024.01.01", "installed_on_request": false, "installed_as_dependency": true, "time": $WATCHMAN_INSTALLED}
      ]
    },
    {
      "name": "openssl",
      "pinned": true,
      "installed": [
        {"version": "3.1.0", "installed_on_request": false, "installed_as_dependency": true, "time": $OPENSSL_INSTALLED},
        {"version": "3.0.0", "installed_on_request": false, "installed_as_dependency": true, "time": $OPENSSL_INSTALLED}
      ]
    },
    {
      "name": "git",
      "pinned": false,
      "installed": [
        {"version": "2.44.0", "installed_on_request": true, "installed_as_dependency": false, "time": $GIT_INSTALLED}
      ]
    },
    {
      "name": "wget",
      "pinned": false,
      "installed": [
        {"version": "1.24.5", "installed_on_request": false, "installed_as_dependency": true, "time": $WGET_INSTALLED}
      ]
    },
    {
      "name": "curl",
      "pinned": false,
      "dependencies": ["openssl"],
      "installed": [
        {"version": "8.4.0", "installed_on_request": false, "installed_as_dependency": true, "time": $WGET_INSTALLED, "runtime_dependencies": [{"full_name": "openssl"}]}
      ]
    },
    {
      "name": "gh",
      "pinned": false,
      "dependencies": ["git"],
      "installed": [
        {"version": "2.40.0", "installed_on_request": true, "installed_as_dependency": false, "time": $WGET_INSTALLED, "runtime_dependencies": [{"full_name": "git"}]}
      ]
    }
  ]
}
EOF

# --- Mock stat (BSD `stat -f <fmt> <path>`) — fixed atime/mtime per fixture ---
cat > "$MOCK_BIN/stat" <<'STATEOF'
#!/usr/bin/env bash
fmt="$2"
path="$3"
case "$path" in
  *imagemagick*) [[ "$fmt" == "%a" ]] && echo "$IMAGEMAGICK_ATIME" || echo "$IMAGEMAGICK_INSTALLED" ;;
  *watchman*)    [[ "$fmt" == "%a" ]] && echo "$WATCHMAN_ATIME"    || echo "$WATCHMAN_INSTALLED" ;;
  *openssl*)     [[ "$fmt" == "%a" ]] && echo "$OPENSSL_ATIME"     || echo "$OPENSSL_INSTALLED" ;;
  *git*)         [[ "$fmt" == "%a" ]] && echo "$GIT_ATIME"         || echo "$GIT_INSTALLED" ;;
  *wget*)        [[ "$fmt" == "%a" ]] && echo "$WGET_ATIME"        || echo "$WGET_INSTALLED" ;;
  *nosuch*)      echo "$FALLBACK_EPOCH" ;;
  *) echo 0 ;;
esac
STATEOF
chmod +x "$MOCK_BIN/stat"

# --- Mock brew ---
cat > "$MOCK_BIN/brew" <<'BREWEOF'
#!/usr/bin/env bash
echo "$*" >> "${BREW_CALL_LOG_PATH:-/dev/null}"
case "$*" in
  "info --json=v2 --installed")  cat "$INFO_JSON_FILE" ;;
  "list --formula")
    printf 'imagemagick\nwatchman\nopenssl\ngit\nwget\n' ;;
  "list --versions")
    printf 'imagemagick 7.1.1\nwatchman 2024.01.01\n' ;;
  "list --cask")                 ;;
  "list imagemagick")            echo "$CELLAR_ROOT/imagemagick/7.1.1/bin/magick" ;;
  "list watchman")                echo "$CELLAR_ROOT/watchman/2024.01.01/bin/watchman" ;;
  "list openssl")                echo "$CELLAR_ROOT/openssl/3.1.0/bin/openssl" ;;
  "list git")                    echo "$CELLAR_ROOT/git/2.44.0/bin/git" ;;
  "list wget")                   echo "$CELLAR_ROOT/wget/1.24.5/bin/wget" ;;
  "list nosuch")                 ;;
  "--cellar imagemagick")         echo "$CELLAR_ROOT/imagemagick" ;;
  "--cellar watchman")            echo "$CELLAR_ROOT/watchman" ;;
  "--cellar openssl")             echo "$CELLAR_ROOT/openssl" ;;
  "--cellar git")                 echo "$CELLAR_ROOT/git" ;;
  "--cellar wget")                echo "$CELLAR_ROOT/wget" ;;
  "--cellar nosuch")               echo "$CELLAR_ROOT/nosuch" ;;
  "--version")                    echo "Homebrew 4.2.0" ;;
  uninstall\ *)                   echo "$2" >> "$UNINSTALL_LOG" ;;
esac
BREWEOF
chmod +x "$MOCK_BIN/brew"
export PATH="$MOCK_BIN:$PATH"

# --- Globals expected by cleanup.sh / depgraph.sh / snapshot.sh ---
DRY_RUN=false
INTERACTIVE=false
CLEANUP_FORCE=false
SNAP_FORCE=false
VERBOSE=false

logv() { $VERBOSE && echo "[v] $*" >&2 || true; }

source "$LIB/core/semver.sh"
source "$LIB/core/outdated.sh"
source "$LIB/audit.sh"
source "$LIB/depgraph.sh"
source "$LIB/snapshot.sh"
source "$LIB/cleanup.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

# --- 1. cleanup_score_from_facts: safe leaf, no other factors -> 4 ---
score="$(cleanup_score_from_facts 1 false true 1 0 0)"
[ "$score" -eq 4 ] && ok || bad "score_from_facts: safe-only expected 4, got $score"

# --- 2. cleanup_score_from_facts: all factors except safe -> 6 ---
score="$(cleanup_score_from_facts 2 true false 0 "$IMAGEMAGICK_INSTALLED" "$IMAGEMAGICK_INSTALLED")"
[ "$score" -eq 6 ] && ok || bad "score_from_facts: stale+vcount+old expected 6, got $score"

# --- 3. _cleanup_days_since(0) -> 0 ---
d="$(_cleanup_days_since 0)"
[ "$d" -eq 0 ] && ok || bad "days_since 0: expected 0, got $d"

# --- 4. _cleanup_days_since(NOW-100d) -> > 90 ---
d="$(_cleanup_days_since "$IMAGEMAGICK_ATIME")"
[ "$d" -gt 90 ] && ok || bad "days_since 100d ago: expected >90, got $d"

# --- 5. _cleanup_last_access imagemagick -> mocked atime ---
last="$(_cleanup_last_access imagemagick)"
[ "$last" -eq "$IMAGEMAGICK_ATIME" ] && ok || bad "last_access imagemagick: expected $IMAGEMAGICK_ATIME, got $last"

# --- 6. _cleanup_last_access nosuch -> falls back to Cellar mtime ---
last="$(_cleanup_last_access nosuch)"
[ "$last" -eq "$FALLBACK_EPOCH" ] && ok || bad "last_access nosuch: expected fallback $FALLBACK_EPOCH, got $last"

# --- Build caches for facts/score/scan tests ---
depgraph_build
_cleanup_build

# --- 7. _cleanup_facts nosuch -> empty-json guard (vcount=0, safe=1, install=0, last=fallback) ---
f="$(_cleanup_facts nosuch)"
expected="$(printf '0\tfalse\tfalse\t1\t0\t%s' "$FALLBACK_EPOCH")"
[ "$f" = "$expected" ] && ok || bad "facts nosuch: expected '$expected', got '$f'"

# --- 8-10. cleanup_score per fixture ---
score="$(cleanup_score imagemagick)"
[ "$score" -eq 8 ] && ok || bad "cleanup_score imagemagick: expected 8, got $score"

score="$(cleanup_score watchman)"
[ "$score" -eq 7 ] && ok || bad "cleanup_score watchman: expected 7, got $score"

score="$(cleanup_score openssl)"
[ "$score" -eq 3 ] && ok || bad "cleanup_score openssl: expected 3, got $score"

# --- 11-15. cleanup_scan categorization ---
rows="$(cleanup_scan)"
echo "$rows" | grep -q '^imagemagick|orphan|8|'      && ok || bad "scan: imagemagick orphan score 8"
echo "$rows" | grep -q '^watchman|stale|7|'          && ok || bad "scan: watchman stale score 7"
echo "$rows" | grep -q '^openssl|pinned-old|3|'      && ok || bad "scan: openssl pinned-old score 3"
echo "$rows" | grep -q '^git|'                       && bad "scan: git should be excluded" || ok
echo "$rows" | grep -q '^wget|'                      && bad "scan: wget should be excluded" || ok

# --- 16. cleanup_report: header + sorted by score desc ---
report="$(cleanup_report "$rows")"
echo "$report" | grep -q 'CATEGORY'                  && ok || bad "report: header present"
im_line="$(echo "$report" | grep -n 'imagemagick' | cut -d: -f1)"
wa_line="$(echo "$report" | grep -n 'watchman'    | cut -d: -f1)"
op_line="$(echo "$report" | grep -n 'openssl'     | cut -d: -f1)"
{ [[ -n "$im_line" && -n "$wa_line" && -n "$op_line" ]] \
  && (( im_line < wa_line )) && (( wa_line < op_line )); } \
  && ok || bad "report: sorted by score desc (imagemagick > watchman > openssl)"

# --- 17. why git -> mentions dependents ---
out="$(why git)"
echo "$out" | grep -qi 'dependents'                  && ok || bad "why git: mentions Dependents"
echo "$out" | grep -q 'gh'                           && ok || bad "why git: lists 'gh' as dependent"

# --- 18. why imagemagick -> "installed manually" + install date ---
exp_date="$(date -r "$IMAGEMAGICK_INSTALLED" +%Y-%m-%d)"
out="$(why imagemagick)"
echo "$out" | grep -qi 'installed manually'          && ok || bad "why imagemagick: installed manually"
echo "$out" | grep -q "$exp_date"                    && ok || bad "why imagemagick: install date $exp_date"

# --- 19. cleanup_execute DRY_RUN=true -> 'Would run', no log entry ---
DRY_RUN=true
out="$(cleanup_execute imagemagick)"
echo "$out" | grep -q 'Would run: brew uninstall imagemagick' && ok || bad "execute dry-run: prints plan"
[ "$(grep -c '^imagemagick$' "$UNINSTALL_LOG" || true)" -eq 0 ] && ok || bad "execute dry-run: no uninstall logged"

# --- 20. cleanup_execute DRY_RUN=false -> logs uninstall ---
DRY_RUN=false
cleanup_execute wget >/dev/null
[ "$(grep -c '^wget$' "$UNINSTALL_LOG" || true)" -eq 1 ] && ok || bad "execute real: uninstall logged"

# --- 21. cleanup_main default: prints report, no extra uninstalls ---
DRY_RUN=false; INTERACTIVE=false; CLEANUP_FORCE=false
pre_count="$(wc -l < "$UNINSTALL_LOG" | tr -d ' ')"
out="$(cleanup_main)"
post_count="$(wc -l < "$UNINSTALL_LOG" | tr -d ' ')"
echo "$out" | head -1 | grep -q 'CATEGORY'           && ok || bad "main default: prints report header"
[ "$pre_count" = "$post_count" ]                     && ok || bad "main default: no uninstalls triggered"

# --- 22. cleanup_main --force: only orphans with score>=7 removed (imagemagick), snapshot taken ---
CLEANUP_FORCE=true
out="$(cleanup_main)"
[ "$(grep -c '^imagemagick$' "$UNINSTALL_LOG" || true)" -eq 1 ] && ok || bad "main --force: imagemagick uninstalled"
[ "$(grep -c '^watchman$' "$UNINSTALL_LOG" || true)" -eq 0 ]    && ok || bad "main --force: watchman not uninstalled (stale, not orphan)"
[ "$(grep -c '^openssl$' "$UNINSTALL_LOG" || true)" -eq 0 ]     && ok || bad "main --force: openssl not uninstalled (pinned-old, not orphan)"
[ -n "$(_snap_list_files)" ]                                    && ok || bad "main --force: snapshot taken before removal"

# --- 23. _cleanup_snapshot_if_needed: skip if today's snapshot already exists ---
pre_snap_count="$(_snap_list_files | wc -l | tr -d ' ')"
_cleanup_snapshot_if_needed
post_snap_count="$(_snap_list_files | wc -l | tr -d ' ')"
[ "$pre_snap_count" = "$post_snap_count" ]           && ok || bad "snapshot_if_needed: skips duplicate same-day snapshot"

# --- 24. cleanup_main --interactive without fzf -> exit 1, mentions fzf ---
CLEANUP_FORCE=false
INTERACTIVE=true
command() {
  [[ "$1" == "-v" && "${2:-}" == "fzf" ]] && return 1
  builtin command "$@"
}
out="$(cleanup_main 2>&1)"; ret=$?
[ "$ret" -eq 1 ]                                     && ok || bad "main --interactive no fzf: exit 1"
echo "$out" | grep -qi 'fzf'                         && ok || bad "main --interactive no fzf: mentions fzf"
unset -f command

# --- 25. cleanup_main --interactive with mock fzf -> selects first row (imagemagick) ---
MOCK_BIN2="$(mktemp -d)"
cat > "$MOCK_BIN2/fzf" <<'FZFEOF'
#!/usr/bin/env bash
head -n1
FZFEOF
chmod +x "$MOCK_BIN2/fzf"
export PATH="$MOCK_BIN2:$PATH"

cleanup_main >/dev/null
[ "$(grep -c '^imagemagick$' "$UNINSTALL_LOG" || true)" -eq 2 ] && ok || bad "main --interactive: imagemagick uninstalled again via fzf selection"
[ "$(grep -c '^watchman$' "$UNINSTALL_LOG" || true)" -eq 0 ]    && ok || bad "main --interactive: watchman never uninstalled"
[ "$(grep -c '^openssl$' "$UNINSTALL_LOG" || true)" -eq 0 ]     && ok || bad "main --interactive: openssl never uninstalled"
[ "$(grep -c '^git$' "$UNINSTALL_LOG" || true)" -eq 0 ]         && ok || bad "main --interactive: git never uninstalled"

export PATH="${PATH#"$MOCK_BIN2:"}"
rm -rf "$MOCK_BIN2"
INTERACTIVE=false

# --- 26. cleanup_bloat: summary fields present ---
out="$(cleanup_bloat)"
echo "$out" | grep -q 'Total installed'              && ok || bad "bloat: Total installed line"
echo "$out" | grep -q 'Orphans'                      && ok || bad "bloat: Orphans line"
echo "$out" | grep -q 'Stale'                        && ok || bad "bloat: Stale line"
echo "$out" | grep -q 'Pinned old'                   && ok || bad "bloat: Pinned old line"
echo "$out" | grep -q 'Est. disk reclaim'            && ok || bad "bloat: disk reclaim line"

echo "Passed: $pass, Failed: $fail"
(( fail == 0 ))
