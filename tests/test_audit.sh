#!/usr/bin/env bash
# Audit log tests: audit_append, _audit_since_epoch, audit_query, audit_report,
# plus integration with snapshot_save, _cleanup_remove_list, and run_upgrade.
# Uses a mock brew/stat — no real packages touched.
set -uo pipefail

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$DIR/../lib/brewmaster"

NOW="$(date +%s)"
DAY=86400
LEFTPAD_INSTALLED=$(( NOW - 1*DAY ))
LEFTPAD_ATIME=$(( NOW - 1*DAY ))
export LEFTPAD_INSTALLED LEFTPAD_ATIME

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

# Single installed formula "leftpad": no dependents, installed on request,
# recently installed/used -> classified as "orphan" (score 4) by cleanup_scan.
cat > "$INFO_JSON_FILE" <<EOF
{
  "formulae": [
    {
      "name": "leftpad",
      "pinned": false,
      "installed": [
        {"version": "1.0.0", "installed_on_request": true, "installed_as_dependency": false, "time": $LEFTPAD_INSTALLED}
      ]
    }
  ]
}
EOF

cat > "$MOCK_BIN/stat" <<'STATEOF'
#!/usr/bin/env bash
fmt="$2"
case "$3" in
  *leftpad*) [[ "$fmt" == "%a" ]] && echo "$LEFTPAD_ATIME" || echo "$LEFTPAD_INSTALLED" ;;
  *) echo 0 ;;
esac
STATEOF
chmod +x "$MOCK_BIN/stat"

cat > "$MOCK_BIN/brew" <<'BREWEOF'
#!/usr/bin/env bash
case "$*" in
  "info --json=v2 --installed")               cat "$INFO_JSON_FILE" ;;
  "list --formula")                           printf 'leftpad\n' ;;
  "list --cask")                              ;;
  "list --versions")                          printf 'git 2.44.0\nleftpad 1.0.0\n' ;;
  "list leftpad")                             echo "$CELLAR_ROOT/leftpad/1.0.0/bin/leftpad" ;;
  "--cellar leftpad")                         echo "$CELLAR_ROOT/leftpad" ;;
  "--version")                                echo "Homebrew 4.2.0" ;;
  "uses --installed leftpad")                 ;;
  "uses --include-build --installed leftpad") ;;
  "uses --installed git")                     ;;
  "uses --include-build --installed git")     ;;
  "outdated --verbose")                       printf 'git (2.44.0) < 2.44.1\n' ;;
  "upgrade git")                              echo "upgraded git" ;;
  "uninstall leftpad")                        echo "leftpad" >> "$UNINSTALL_LOG" ;;
  "uninstall failpkg")                        exit 1 ;;
esac
BREWEOF
chmod +x "$MOCK_BIN/brew"
export PATH="$MOCK_BIN:$PATH"

# --- Globals expected by sourced modules ---
DRY_RUN=false
INTERACTIVE=false
CLEANUP_FORCE=false
SNAP_FORCE=false
VERBOSE=false
CHECK_DEPS=false
RISK_THRESHOLD=7
YES_FLAG=false
PROFILE_NAME=""
PROFILE_REQUIRE_CONFIRM=false
PROFILE_MAX_RISK=10
ONLY_FORMULAE=false
ONLY_CASKS=false
LEVEL="patch"
OR_LOWER=false
ALLOW_DATE=false
PACKAGES=()

logv() { $VERBOSE && echo "[v] $*" >&2 || true; }

source "$LIB/core/semver.sh"
source "$LIB/core/outdated.sh"
source "$LIB/audit.sh"
source "$LIB/depgraph.sh"
source "$LIB/snapshot.sh"
source "$LIB/cleanup.sh"
source "$LIB/upgrade.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

ts_ago() { date -u -v-"$1" +%Y-%m-%dT%H:%M:%SZ; }

# --- 1. audit_query: missing log file ---
SAVED_AUDIT_LOG="$AUDIT_LOG"
NO_LOG="$(mktemp -u)"
AUDIT_LOG="$NO_LOG"
out="$(audit_query)"
echo "$out" | grep -q "No audit log found at $NO_LOG" && ok || bad "query: missing log -> 'No audit log found'"
AUDIT_LOG="$SAVED_AUDIT_LOG"

# --- 2. audit_report: empty audit log + no snapshots -> zeros/n/a, orphan from mock ---
[ ! -f "$AUDIT_LOG" ] && ok || bad "setup: audit log should not exist yet"
out="$(audit_report)"
echo "$out" | head -1 | grep -q 'brewmaster machine report'                        && ok || bad "report: header line"
header_line="$(echo "$out" | sed -n '1p')"
sep_line="$(echo "$out" | sed -n '2p')"
expected_sep="$(printf '─%.0s' $(seq 1 ${#header_line}))"
[ "$sep_line" = "$expected_sep" ]                                                   && ok || bad "report: separator matches header length"
echo "$out" | grep -qE 'Upgrades \(30d\): *0 *\(patch: 0 *minor: 0 *major: 0\)'     && ok || bad "report empty: 0 upgrades"
echo "$out" | grep -qE 'Cleanups \(90d\): *0 *packages removed'                     && ok || bad "report empty: 0 cleanups"
echo "$out" | grep -qE 'Snapshots: *0 *\(none\)'                                    && ok || bad "report empty: 0 snapshots (none)"
echo "$out" | grep -qE 'Orphans now: *1'                                            && ok || bad "report empty: 1 orphan (leftpad)"
echo "$out" | grep -qE 'Avg risk score: *n/a'                                       && ok || bad "report empty: avg risk n/a"

# --- 3. audit_append: writes valid NDJSON; default extra={} -> only ts/action keys ---
audit_append "test"
entry="$(tail -n1 "$AUDIT_LOG")"
echo "$entry" | jq -e . >/dev/null 2>&1                                             && ok || bad "append: valid JSON"
[ "$(echo "$entry" | jq -r '.action')" = "test" ]                                   && ok || bad "append: action set"
echo "$entry" | jq -r '.ts' | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' \
                                                                                     && ok || bad "append: ts is ISO8601 UTC"
[ "$(echo "$entry" | jq -r 'keys | sort | join(",")')" = "action,ts" ]              && ok || bad "append: default extra has only ts/action keys"

# --- 4. audit_append with extra fields merges them in ---
audit_append "upgrade" '{"package":"git","old":"1.0.0","new":"1.1.0","bump":"minor"}'
entry="$(tail -n1 "$AUDIT_LOG")"
[ "$(echo "$entry" | jq -r '.package')" = "git" ]                                   && ok || bad "append: extra field package merged"
[ "$(echo "$entry" | jq -r '.bump')" = "minor" ]                                    && ok || bad "append: extra field bump merged"

# --- 5. _audit_since_epoch: valid specs ---
e7d="$(_audit_since_epoch 7d)"   && ok || bad "_audit_since_epoch 7d should succeed"
e2w="$(_audit_since_epoch 2w)"   && ok || bad "_audit_since_epoch 2w should succeed"
e6h="$(_audit_since_epoch 6h)"   && ok || bad "_audit_since_epoch 6h should succeed"
e30="$(_audit_since_epoch 30)"   && ok || bad "_audit_since_epoch bare 30 (default days) should succeed"
{ [ "$e7d" -lt "$NOW" ] && [ "$e7d" -gt $((NOW - 8*DAY)) ]; }    && ok || bad "_audit_since_epoch 7d: epoch ~7 days ago"
{ [ "$e2w" -lt "$NOW" ] && [ "$e2w" -gt $((NOW - 15*DAY)) ]; }   && ok || bad "_audit_since_epoch 2w: epoch ~2 weeks ago"
{ [ "$e6h" -lt "$NOW" ] && [ "$e6h" -gt $((NOW - 7*3600)) ]; }   && ok || bad "_audit_since_epoch 6h: epoch ~6 hours ago"
{ [ "$e30" -lt "$NOW" ] && [ "$e30" -gt $((NOW - 31*DAY)) ]; }   && ok || bad "_audit_since_epoch 30: bare number defaults to days"

# --- 6. _audit_since_epoch: invalid spec fails with stderr message ---
err="$(_audit_since_epoch "bogus" 2>&1 >/dev/null)"; ret=$?
[ "$ret" -ne 0 ]                       && ok || bad "_audit_since_epoch bogus: nonzero return"
echo "$err" | grep -qi 'invalid'       && ok || bad "_audit_since_epoch bogus: error message"

# --- 7. seed mixed audit entries for audit_query tests ---
: > "$AUDIT_LOG"
now_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -nc --arg ts "$now_ts"        '{ts:$ts, action:"upgrade", package:"git", old:"1.0.0", new:"1.1.0", bump:"patch", risk:2, profile:"", dry_run:false}'   >> "$AUDIT_LOG"
jq -nc --arg ts "$(ts_ago 5d)"   '{ts:$ts, action:"upgrade", package:"node", old:"20.0.0", new:"20.1.0", bump:"minor", risk:5, profile:"", dry_run:false}' >> "$AUDIT_LOG"
jq -nc --arg ts "$(ts_ago 10d)"  '{ts:$ts, action:"upgrade", package:"jq", old:"1.6.0", new:"2.0.0", bump:"major", profile:"", dry_run:false}'             >> "$AUDIT_LOG"
jq -nc --arg ts "$(ts_ago 40d)"  '{ts:$ts, action:"upgrade", package:"oldpkg", old:"0.9.0", new:"1.0.0", bump:"major", profile:"", dry_run:false}'         >> "$AUDIT_LOG"
jq -nc --arg ts "$now_ts"        '{ts:$ts, action:"cleanup", package:"foo", category:"orphan", score:8, dry_run:false}'                                    >> "$AUDIT_LOG"
jq -nc --arg ts "$(ts_ago 100d)" '{ts:$ts, action:"cleanup", package:"bar", category:"stale", score:3, dry_run:false}'                                     >> "$AUDIT_LOG"
jq -nc --arg ts "$now_ts"        '{ts:$ts, action:"snapshot", path:"/tmp/snaps/20260610-120000-mytest.txt", label:"mytest"}'                               >> "$AUDIT_LOG"
jq -nc --arg ts "$now_ts"        '{ts:$ts, action:"snapshot", path:"/tmp/snaps/20260610-130000.txt", label:""}'                                            >> "$AUDIT_LOG"

AUDIT_PACKAGE=""; AUDIT_ACTION=""; AUDIT_SINCE=""; AUDIT_FORMAT="table"

# --- 8. audit_query default: table, no cap (8 entries) ---
out="$(audit_query)"
echo "$out" | head -1 | grep -q 'TIMESTAMP'         && ok || bad "query default: table header"
[ "$(echo "$out" | wc -l | tr -d ' ')" -eq 10 ]      && ok || bad "query default: header(2) + 8 rows = 10 lines"

# --- 9. audit_query --package=git ---
AUDIT_PACKAGE="git"
out="$(audit_query)"
[ "$(echo "$out" | wc -l | tr -d ' ')" -eq 3 ]       && ok || bad "query --package=git: header(2)+1 row"
echo "$out" | grep -q 'git'                          && ok || bad "query --package=git: shows git row"
echo "$out" | grep -q '1.0.0 -> 1.1.0 \[patch\]'     && ok || bad "query --package=git: DETAIL = old -> new [bump]"
AUDIT_PACKAGE=""

# --- 10. audit_query --action=cleanup ---
AUDIT_ACTION="cleanup"
out="$(audit_query)"
[ "$(echo "$out" | wc -l | tr -d ' ')" -eq 4 ]       && ok || bad "query --action=cleanup: header(2)+2 rows"
echo "$out" | grep -q 'orphan score=8'               && ok || bad "query --action=cleanup: DETAIL = category score=N (foo)"
echo "$out" | grep -q 'stale score=3'                && ok || bad "query --action=cleanup: DETAIL = category score=N (bar)"
AUDIT_ACTION=""

# --- 11. audit_query --action=snapshot: DETAIL formatting (with/without label) ---
AUDIT_ACTION="snapshot"
out="$(audit_query)"
echo "$out" | grep -q '20260610-120000-mytest.txt (mytest)'  && ok || bad "query snapshot DETAIL: filename + (label)"
echo "$out" | grep -qE '20260610-130000\.txt$'                && ok || bad "query snapshot DETAIL: filename without label, no trailing paren"
AUDIT_ACTION=""

# --- 12. audit_query --since=1d: only 'now' entries, no cap ---
AUDIT_SINCE="1d"
out="$(audit_query)"
[ "$(echo "$out" | wc -l | tr -d ' ')" -eq 6 ]       && ok || bad "query --since=1d: header(2)+4 rows (now-only entries)"
echo "$out" | grep -qE '\bnode\b' && bad "query --since=1d: should exclude node (5d old)" || ok
AUDIT_SINCE=""

# --- 13. audit_query: filter matching nothing ---
AUDIT_PACKAGE="doesnotexist"
out="$(audit_query)"
echo "$out" | grep -q 'No matching audit entries.' && ok || bad "query: no matches -> 'No matching audit entries.'"
AUDIT_PACKAGE=""

# --- 14. audit_query --format=json ---
AUDIT_FORMAT="json"
out="$(audit_query)"
[ "$(echo "$out" | wc -l | tr -d ' ')" -eq 8 ]       && ok || bad "query --format=json: 8 lines (no header, no cap)"
all_valid=true
while IFS= read -r line; do echo "$line" | jq -e . >/dev/null 2>&1 || all_valid=false; done <<<"$out"
$all_valid && ok || bad "query --format=json: every line is valid JSON"
AUDIT_FORMAT="table"

# --- 15. audit_query --format=csv ---
AUDIT_ACTION="upgrade"; AUDIT_FORMAT="csv"
out="$(audit_query)"
[ "$(echo "$out" | wc -l | tr -d ' ')" -eq 4 ]       && ok || bad "query --action=upgrade --format=csv: 4 rows, no header"
echo "$out" | grep -q 'git'                          && ok || bad "query csv: contains git row"
field_count="$(echo "$out" | head -1 | awk -F',' '{print NF}')"
[ "$field_count" -ge 4 ]                             && ok || bad "query csv: at least 4 comma-separated fields"
AUDIT_ACTION=""; AUDIT_FORMAT="table"

# --- 16. 20-entry cap on default (no-filter) query; filtered queries show all ---
for i in $(seq 1 17); do
  jq -nc --arg ts "$now_ts" --arg pkg "pad${i}" \
    '{ts:$ts, action:"upgrade", package:$pkg, old:"1.0.0", new:"1.0.1", bump:"patch", profile:"", dry_run:false}' \
    >> "$AUDIT_LOG"
done
total_lines="$(wc -l < "$AUDIT_LOG" | tr -d ' ')"
[ "$total_lines" -eq 25 ]                            && ok || bad "seed: 25 total entries (8 + 17 pad)"

out="$(audit_query)"
[ "$(echo "$out" | wc -l | tr -d ' ')" -eq 22 ]      && ok || bad "query default: capped at header(2)+20 rows"

AUDIT_ACTION="upgrade"
out="$(audit_query)"
[ "$(echo "$out" | wc -l | tr -d ' ')" -eq 23 ]      && ok || bad "query --action=upgrade: no cap, header(2)+21 rows"
AUDIT_ACTION=""

# --- 17. audit_report with seeded data: 30d/90d windows, avg risk, snapshots, orphans ---
: > "$AUDIT_LOG"
jq -nc --arg ts "$now_ts"        '{ts:$ts, action:"upgrade", package:"git", old:"1.0.0", new:"1.1.0", bump:"patch", risk:2, profile:"", dry_run:false}'    >> "$AUDIT_LOG"
jq -nc --arg ts "$(ts_ago 10d)"  '{ts:$ts, action:"upgrade", package:"node", old:"20.0.0", new:"20.0.1", bump:"patch", risk:4, profile:"", dry_run:false}'  >> "$AUDIT_LOG"
jq -nc --arg ts "$(ts_ago 20d)"  '{ts:$ts, action:"upgrade", package:"jq", old:"1.6.0", new:"1.7.0", bump:"minor", risk:6, profile:"", dry_run:false}'      >> "$AUDIT_LOG"
jq -nc --arg ts "$(ts_ago 40d)"  '{ts:$ts, action:"upgrade", package:"oldpkg", old:"1.0.0", new:"2.0.0", bump:"major", profile:"", dry_run:false}'          >> "$AUDIT_LOG"
jq -nc --arg ts "$now_ts"        '{ts:$ts, action:"cleanup", package:"foo", category:"orphan", score:8, dry_run:false}'                                     >> "$AUDIT_LOG"
jq -nc --arg ts "$(ts_ago 50d)"  '{ts:$ts, action:"cleanup", package:"bar", category:"stale", score:3, dry_run:false}'                                      >> "$AUDIT_LOG"
jq -nc --arg ts "$(ts_ago 100d)" '{ts:$ts, action:"cleanup", package:"baz", category:"orphan", score:9, dry_run:false}'                                     >> "$AUDIT_LOG"

printf 'git\t2.44.0\n' > "$SNAP_DIR/20250410-000000-old.txt"
jq -n '{label:"old", brew_version:"4.0", package_count:1}' > "$SNAP_DIR/20250410-000000-old.meta.json"
touch -t 202504100000 "$SNAP_DIR/20250410-000000-old.txt"

printf 'git\t2.44.0\n' > "$SNAP_DIR/20260601-000000-new.txt"
jq -n '{label:"new", brew_version:"4.0", package_count:1}' > "$SNAP_DIR/20260601-000000-new.meta.json"
touch -t 202606010000 "$SNAP_DIR/20260601-000000-new.txt"

out="$(audit_report)"
echo "$out" | grep -qE 'Upgrades \(30d\): *3 *\(patch: 2 *minor: 1 *major: 0\)'                && ok || bad "report: upgrades(30d)=3, patch=2 minor=1 major=0"
echo "$out" | grep -qE 'Cleanups \(90d\): *2 *packages removed'                                && ok || bad "report: cleanups(90d)=2"
echo "$out" | grep -qE 'Snapshots: *2 *\(oldest: 2025-04-10, latest: 2026-06-01\)'             && ok || bad "report: snapshots=2, oldest/latest dates"
echo "$out" | grep -qE 'Orphans now: *1'                                                       && ok || bad "report: orphans now=1"
echo "$out" | grep -qE 'Avg risk score: *4\.0 *\(last 10 upgrades\)'                           && ok || bad "report: avg risk = 4.0"

# --- 18. snapshot_save appends a "snapshot" audit entry ---
: > "$AUDIT_LOG"
txt="$(snapshot_save "inttest")"
entry="$(tail -n1 "$AUDIT_LOG")"
[ "$(echo "$entry" | jq -r '.action')" = "snapshot" ]   && ok || bad "snapshot_save: appends action=snapshot"
[ "$(echo "$entry" | jq -r '.path')" = "$txt" ]         && ok || bad "snapshot_save: path matches saved file"
[ "$(echo "$entry" | jq -r '.label')" = "inttest" ]     && ok || bad "snapshot_save: label recorded"

# --- 19. _cleanup_remove_list: real removal appends "cleanup" entry ---
: > "$AUDIT_LOG"
DRY_RUN=false
printf 'leftpad|orphan|4|installed manually, 0 dependents\n' | _cleanup_remove_list
entry="$(tail -n1 "$AUDIT_LOG")"
[ "$(echo "$entry" | jq -r '.action')" = "cleanup" ]    && ok || bad "_cleanup_remove_list real: appends action=cleanup"
[ "$(echo "$entry" | jq -r '.package')" = "leftpad" ]   && ok || bad "_cleanup_remove_list real: package=leftpad"
[ "$(echo "$entry" | jq -r '.category')" = "orphan" ]   && ok || bad "_cleanup_remove_list real: category=orphan"
[ "$(echo "$entry" | jq -r '.score')" = "4" ]           && ok || bad "_cleanup_remove_list real: score=4"
[ "$(echo "$entry" | jq -r '.dry_run')" = "false" ]     && ok || bad "_cleanup_remove_list real: dry_run=false"

# --- 20. _cleanup_remove_list: DRY_RUN=true appends nothing ---
DRY_RUN=true
pre_lines="$(wc -l < "$AUDIT_LOG" | tr -d ' ')"
printf 'leftpad|orphan|4|installed manually, 0 dependents\n' | _cleanup_remove_list
post_lines="$(wc -l < "$AUDIT_LOG" | tr -d ' ')"
[ "$pre_lines" = "$post_lines" ]                        && ok || bad "_cleanup_remove_list dry-run: no audit entry"
DRY_RUN=false

# --- 21. _cleanup_remove_list: failed removal appends nothing, returns nonzero ---
pre_lines="$(wc -l < "$AUDIT_LOG" | tr -d ' ')"
printf 'failpkg|orphan|5|some reason\n' | _cleanup_remove_list; ret=$?
post_lines="$(wc -l < "$AUDIT_LOG" | tr -d ' ')"
[ "$ret" -ne 0 ]                                        && ok || bad "_cleanup_remove_list failure: nonzero return"
[ "$pre_lines" = "$post_lines" ]                        && ok || bad "_cleanup_remove_list failure: no audit entry"

# --- 22. run_upgrade: real execution appends "upgrade" entry (no risk when CHECK_DEPS=false) ---
: > "$AUDIT_LOG"
DRY_RUN=false; CHECK_DEPS=false; LEVEL="patch"; OR_LOWER=false
run_upgrade >/dev/null
entry="$(tail -n1 "$AUDIT_LOG")"
[ "$(echo "$entry" | jq -r '.action')" = "upgrade" ]    && ok || bad "run_upgrade real: appends action=upgrade"
[ "$(echo "$entry" | jq -r '.package')" = "git" ]       && ok || bad "run_upgrade real: package=git"
[ "$(echo "$entry" | jq -r '.old')" = "2.44.0" ]        && ok || bad "run_upgrade real: old=2.44.0"
[ "$(echo "$entry" | jq -r '.new')" = "2.44.1" ]        && ok || bad "run_upgrade real: new=2.44.1"
[ "$(echo "$entry" | jq -r '.bump')" = "patch" ]        && ok || bad "run_upgrade real: bump=patch"
[ "$(echo "$entry" | jq -r '.dry_run')" = "false" ]     && ok || bad "run_upgrade real: dry_run=false"
[ "$(echo "$entry" | jq -r 'has("risk")')" = "false" ]  && ok || bad "run_upgrade real (CHECK_DEPS=false): no risk field"

# --- 23. run_upgrade: DRY_RUN=true appends nothing ---
DRY_RUN=true
pre_lines="$(wc -l < "$AUDIT_LOG" | tr -d ' ')"
run_upgrade >/dev/null
post_lines="$(wc -l < "$AUDIT_LOG" | tr -d ' ')"
[ "$pre_lines" = "$post_lines" ]                        && ok || bad "run_upgrade dry-run: no audit entry"
DRY_RUN=false

# --- 24. run_upgrade: CHECK_DEPS=true includes risk field (reused score, no extra calls) ---
CHECK_DEPS=true
run_upgrade >/dev/null
entry="$(tail -n1 "$AUDIT_LOG")"
[ "$(echo "$entry" | jq -r '.action')" = "upgrade" ]    && ok || bad "run_upgrade CHECK_DEPS=true: appends action=upgrade"
[ "$(echo "$entry" | jq -r '.risk')" = "0" ]            && ok || bad "run_upgrade CHECK_DEPS=true: risk=0 (no dependents)"
CHECK_DEPS=false

# --- 25. run_upgrade --interactive: logs only the selected package ---
MOCK_FZF="$(mktemp -d)"
cat > "$MOCK_FZF/fzf" <<'FZFEOF'
#!/usr/bin/env bash
head -n1
FZFEOF
chmod +x "$MOCK_FZF/fzf"
export PATH="$MOCK_FZF:$PATH"

: > "$AUDIT_LOG"
INTERACTIVE=true
run_upgrade >/dev/null
entry="$(tail -n1 "$AUDIT_LOG")"
[ "$(echo "$entry" | jq -r '.action')" = "upgrade" ]      && ok || bad "run_upgrade interactive: appends action=upgrade"
[ "$(echo "$entry" | jq -r '.package')" = "git" ]         && ok || bad "run_upgrade interactive: package=git (selected via fzf)"
[ "$(wc -l < "$AUDIT_LOG" | tr -d ' ')" -eq 1 ]           && ok || bad "run_upgrade interactive: only 1 entry logged"
INTERACTIVE=false

export PATH="${PATH#"$MOCK_FZF:"}"
rm -rf "$MOCK_FZF"

echo "Passed: $pass, Failed: $fail"
(( fail == 0 ))
