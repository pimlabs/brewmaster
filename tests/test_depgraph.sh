#!/usr/bin/env bash
# Depgraph function tests. Uses a mock brew — no real packages touched.
set -uo pipefail

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$DIR/../lib/brewmaster"

# --- Mock brew (uses "$*" so all args match regardless of count) ---
MOCK_BIN="$(mktemp -d)"
BREW_CALL_LOG="$(mktemp)"
trap 'rm -rf "$MOCK_BIN" "$BREW_CALL_LOG"' EXIT

cat > "$MOCK_BIN/brew" <<'BREWEOF'
#!/usr/bin/env bash
echo "$*" >> "${BREW_CALL_LOG_PATH:-/dev/null}"
case "$*" in
  # runtime deps
  "uses --installed openssl")            echo "curl"; echo "cmake" ;;
  "uses --installed git")                ;;
  "uses --installed node")               echo "yarn"; echo "pnpm"; echo "eslint"; echo "prettier" ;;
  # build deps — openssl: same count (no extra), node: +1 extra (triggers +2)
  "uses --include-build --installed openssl") echo "curl"; echo "cmake" ;;
  "uses --include-build --installed git")     ;;
  "uses --include-build --installed node")    echo "yarn"; echo "pnpm"; echo "eslint"; echo "prettier"; echo "make" ;;
  # outdated list
  "outdated --verbose")
    printf 'git (2.40.0) < 2.44.0\n'
    printf 'openssl (3.0.0) < 3.1.0\n'
    printf 'node (20.0.0) < 21.0.0\n'
    ;;
  "--version") echo "Homebrew 4.2.0" ;;
esac
BREWEOF
chmod +x "$MOCK_BIN/brew"
export PATH="$MOCK_BIN:$PATH"
export BREW_CALL_LOG_PATH="$BREW_CALL_LOG"

# --- Globals ---
DRY_RUN=false
SNAP_FORCE=false
VERBOSE=false
LEVEL="patch"
CHECK_DEPS=false
RISK_THRESHOLD=7
YES_FLAG=false

logv() { $VERBOSE && echo "[v] $*" >&2 || true; }

# Source dependencies
source "$LIB/core/semver.sh"
source "$LIB/core/outdated.sh"
source "$LIB/depgraph.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

# --- 1. depgraph_build creates cache file ---
depgraph_build
[ -f "$DEPGRAPH_CACHE" ]                    && ok || bad "build: cache file created"
[ "$(cat "$DEPGRAPH_CACHE")" = "{}" ]       && ok || bad "build: cache initialized to {}"

# --- 2. depgraph_is_safe "git" → empty array [], return 0 ---
arr="$(depgraph_is_safe "git")"
echo "$arr" | jq -e '. == []' >/dev/null    && ok || bad "is_safe git: stdout []"
depgraph_is_safe "git" >/dev/null           && ok || bad "is_safe git: return 0 (safe)"

# --- 3. depgraph_is_safe "openssl" → non-empty, return 1 ---
arr="$(depgraph_is_safe "openssl")"
echo "$arr" | jq -e 'length > 0' >/dev/null && ok || bad "is_safe openssl: non-empty stdout"
depgraph_is_safe "openssl" >/dev/null       && bad "is_safe openssl: should return 1" || ok

# --- 4. Second call uses cache — brew NOT called again ---
pre_count="$(wc -l < "$BREW_CALL_LOG")"
depgraph_is_safe "openssl" >/dev/null
post_count="$(wc -l < "$BREW_CALL_LOG")"
[ "$pre_count" = "$post_count" ]             && ok || bad "cache hit: brew not called on second lookup"

# --- 5. depgraph_risk_score "git" "patch" → 0 ---
score="$(depgraph_risk_score "git" "patch")"
[ "$score" -eq 0 ]                           && ok || bad "risk_score git patch: expected 0, got $score"

# --- 6. depgraph_risk_score "openssl" "patch" → 3 ---
# +3 (2 runtime>0); no major; 2 not>3; build count == runtime (no extra)
score="$(depgraph_risk_score "openssl" "patch")"
[ "$score" -eq 3 ]                           && ok || bad "risk_score openssl patch: expected 3, got $score"

# --- 7. depgraph_risk_score "openssl" "major" → 6 ---
# +3 (runtime) + +3 (major)
score="$(depgraph_risk_score "openssl" "major")"
[ "$score" -eq 6 ]                           && ok || bad "risk_score openssl major: expected 6, got $score"

# --- 8. depgraph_risk_score "node" "major" → 10 ---
# +3 (4 runtime) + +3 (major) + +2 (4>3) + +2 (5 build > 4 runtime)
score="$(depgraph_risk_score "node" "major")"
[ "$score" -eq 10 ]                          && ok || bad "risk_score node major: expected 10, got $score"

# --- 9. depgraph_risk_score with empty kind → major factor skipped ---
score_empty="$(depgraph_risk_score "openssl" "")"
[ "$score_empty" -eq 3 ]                     && ok || bad "risk_score empty kind: expected 3, got $score_empty"

# --- 10. depgraph_report "openssl" → shows deps and score ---
report="$(depgraph_report "openssl")"
echo "$report" | grep -qi 'Dependents'      && ok || bad "report: shows Dependents header"
echo "$report" | grep -q 'Risk score'       && ok || bad "report: shows Risk score"

# --- 11. depgraph_list_risky → sorted descending; node before git ---
list_out="$(depgraph_list_risky)"
node_line="$(echo "$list_out" | grep -n 'node' | head -1 | cut -d: -f1)"
git_line="$(echo "$list_out"  | grep -n '\bgit\b' | grep -v 'PACKAGE\|----' | head -1 | cut -d: -f1)"
[ -n "$node_line" ] && [ -n "$git_line" ]   && ok || bad "list_risky: node and git both present"
{ [[ -n "$node_line" ]] && [[ -n "$git_line" ]] && (( node_line < git_line )); } \
  && ok || bad "list_risky: node (high risk) should appear before git (low risk)"

# --- 12. Upgrade flow: CHECK_DEPS=true, node@major skipped (score >= RISK_THRESHOLD) ---
source "$LIB/core/upgrade.sh"

MOCK_BIN2="$(mktemp -d)"
cat > "$MOCK_BIN2/brew" <<'BREW2EOF'
#!/usr/bin/env bash
case "$*" in
  "list --cask")                              ;;
  "outdated --verbose")                       printf 'node (20.0.0) < 21.0.0\n' ;;
  "upgrade node")                             echo "upgraded node" ;;
  "uses --installed node")                    echo "yarn"; echo "pnpm"; echo "eslint"; echo "prettier" ;;
  "uses --include-build --installed node")    echo "yarn"; echo "pnpm"; echo "eslint"; echo "prettier"; echo "make" ;;
  "--version")                                echo "Homebrew 4.2.0" ;;
esac
BREW2EOF
chmod +x "$MOCK_BIN2/brew"

OLD_PATH="$PATH"
export PATH="$MOCK_BIN2:$PATH"

CHECK_DEPS=true
LEVEL="major"
OR_LOWER=false
ALLOW_DATE=false
ONLY_FORMULAE=false
ONLY_CASKS=false
DRY_RUN=true
PACKAGES=()
CASK_SET=""

DEPGRAPH_CACHE="$(mktemp)"
echo '{}' > "$DEPGRAPH_CACHE"

upgrade_out="$(run_upgrade 2>&1)"
# node risk score 10 >= RISK_THRESHOLD(7) → skipped with "Warning"
echo "$upgrade_out" | grep -qi 'warning.*node\|skipping.*node' \
  && ok || bad "upgrade CHECK_DEPS: high-risk node flagged in output"
# upgrade_list should be empty → dry-run says "No upgrade candidates"
echo "$upgrade_out" | grep -qi 'No upgrade candidates\|skipping node' \
  && ok || bad "upgrade CHECK_DEPS: node not in final upgrade list"

export PATH="$OLD_PATH"
rm -rf "$MOCK_BIN2"

echo "Passed: $pass, Failed: $fail"
(( fail == 0 ))
