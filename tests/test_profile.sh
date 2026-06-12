#!/usr/bin/env bash
# Profile system tests. Uses a temp profiles.toml — no real config touched.
set -uo pipefail

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$DIR/../lib/brewmaster"

# --- temp config dir + fixture profiles.toml ---
CONF_DIR="$(mktemp -d)"
trap 'rm -rf "$CONF_DIR"' EXIT

CONFIG_FILE="$CONF_DIR/profiles.toml"
cat > "$CONFIG_FILE" <<'EOF'
[profiles.work]
description = "Core dev tools"
include = ["node", "python@3.12", "git", "gh", "jq", "ripgrep"]

[profiles.safe]
description = "Low-risk upgrades only"
include = []
exclude = ["openssl", "curl"]
max_risk_score = 3
level = "patch"

[profiles.personal]
description = "Everything allowed, minor and below"
include = []
level = "minor"

[profiles.demo]
description = "Freeze before a client demo"
include = []
exclude = []
require_confirm = true
level = "patch"
EOF

export BREWMASTER_PROFILE_CONFIG="$CONFIG_FILE"

# --- Globals (matching bin/brewmaster defaults) ---
DRY_RUN=false
VERBOSE=false
LEVEL="patch"
LEVEL_EXPLICIT=false
OR_LOWER=false
ALLOW_DATE=false
ONLY_FORMULAE=false
ONLY_CASKS=false
CHECK_DEPS=false
RISK_THRESHOLD=7
YES_FLAG=false
INTERACTIVE=false
PROFILE_NAME=""
PROFILE_INCLUDE=()
PROFILE_EXCLUDE=()
PROFILE_REQUIRE_CONFIRM=false
PROFILE_MAX_RISK=10
PROFILE_LEVEL=""
PACKAGES=()

logv() { $VERBOSE && echo "[v] $*" >&2 || true; }

source "$LIB/core/semver.sh"
source "$LIB/core/outdated.sh"
source "$LIB/upgrade.sh"
source "$LIB/profile.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

# --- 1. _profile_parse_toml_array with items ---
out="$(_profile_parse_toml_array '["node", "git"]')"
count="$(echo "$out" | grep -c .)"
[ "$count" -eq 2 ]                          && ok || bad "parse_array: 2 items, got $count"
echo "$out" | grep -qx "node"               && ok || bad "parse_array: contains node"
echo "$out" | grep -qx "git"                && ok || bad "parse_array: contains git"

# --- 2. _profile_parse_toml_array empty ---
out="$(_profile_parse_toml_array '[]')"
[ -z "$out" ]                               && ok || bad "parse_array empty: no output"

# --- 3. profile_load nonexistent profile ---
err="$(profile_load "nonexistent" 2>&1 >/dev/null)"; ret=$?
[ "$ret" -eq 1 ]                            && ok || bad "load nonexistent: return 1"
echo "$err" | grep -qi "not found"          && ok || bad "load nonexistent: stderr mentions not found"

# --- 4. profile_load "work" → include list ---
profile_load "work" >/dev/null
[ "${#PROFILE_INCLUDE[@]}" -eq 6 ]          && ok || bad "work: include count = 6, got ${#PROFILE_INCLUDE[@]}"
_in_list "git" "${PROFILE_INCLUDE[@]}"      && ok || bad "work: include contains git"

# --- 5. profile_load "safe" → exclude + max_risk_score + level ---
profile_load "safe" >/dev/null
[ "${#PROFILE_EXCLUDE[@]}" -eq 2 ]          && ok || bad "safe: exclude count = 2, got ${#PROFILE_EXCLUDE[@]}"
_in_list "openssl" "${PROFILE_EXCLUDE[@]}"  && ok || bad "safe: exclude contains openssl"
[ "$PROFILE_MAX_RISK" -eq 3 ]               && ok || bad "safe: max_risk_score = 3, got $PROFILE_MAX_RISK"
[ "$PROFILE_LEVEL" = "patch" ]              && ok || bad "safe: level = patch, got $PROFILE_LEVEL"

# --- 6. profile_load "personal" → level override, empty include ---
profile_load "personal" >/dev/null
[ "$PROFILE_LEVEL" = "minor" ]              && ok || bad "personal: level = minor, got $PROFILE_LEVEL"
[ "${#PROFILE_INCLUDE[@]}" -eq 0 ]          && ok || bad "personal: include empty"

# --- 7. profile_load "demo" → require_confirm ---
profile_load "demo" >/dev/null
[ "$PROFILE_REQUIRE_CONFIRM" = "true" ]     && ok || bad "demo: require_confirm = true"

# --- 8. profile_filter_package: in include list → allowed ---
profile_load "work" >/dev/null
profile_filter_package "git" >/dev/null     && ok || bad "work: git allowed (in include)"

# --- 9. profile_filter_package: not in include list → skipped ---
PROFILE_INCLUDE=("git")
PROFILE_EXCLUDE=()
profile_filter_package "node" >/dev/null    && bad "filter: node should be skipped (not in include)" || ok
profile_filter_package "git" >/dev/null     && ok || bad "filter: git should be allowed (in include)"

# --- 10. profile_filter_package: in exclude list → skipped ---
profile_load "safe" >/dev/null
profile_filter_package "openssl" >/dev/null && bad "safe: openssl should be skipped (excluded)" || ok

# --- 11. profile_filter_package: empty include/exclude → all allowed ---
profile_load "personal" >/dev/null
profile_filter_package "anything-pkg" >/dev/null && ok || bad "personal: anything-pkg allowed (no filters)"

# --- 12. profile_list shows all profiles ---
out="$(profile_list)"
echo "$out" | grep -q "^work"               && ok || bad "list: contains work"
echo "$out" | grep -q "^safe"               && ok || bad "list: contains safe"
echo "$out" | grep -q "Core dev tools"      && ok || bad "list: shows description"

# --- 13. profile_validate: valid config → return 0, no stderr ---
err="$(profile_validate 2>&1 >/dev/null)"; ret=$?
[ "$ret" -eq 0 ]                            && ok || bad "validate valid: return 0"
[ -z "$err" ]                               && ok || bad "validate valid: no stderr, got: $err"

# --- 14. profile_validate: duplicate section → return 1 ---
DUP_CONFIG="$CONF_DIR/dup.toml"
cat > "$DUP_CONFIG" <<'EOF'
[profiles.work]
description = "A"
include = []

[profiles.work]
description = "B"
include = []
EOF
saved_config="$PROFILE_CONFIG"
PROFILE_CONFIG="$DUP_CONFIG"
err="$(profile_validate 2>&1 >/dev/null)"; ret=$?
[ "$ret" -eq 1 ]                            && ok || bad "validate duplicate: return 1"
echo "$err" | grep -qi "duplicate"          && ok || bad "validate duplicate: stderr mentions duplicate"
PROFILE_CONFIG="$saved_config"

# --- 15. profile_validate: invalid level → return 1 ---
BADLEVEL_CONFIG="$CONF_DIR/badlevel.toml"
cat > "$BADLEVEL_CONFIG" <<'EOF'
[profiles.broken]
description = "Bad level"
include = []
level = "ultra"
EOF
PROFILE_CONFIG="$BADLEVEL_CONFIG"
err="$(profile_validate 2>&1 >/dev/null)"; ret=$?
[ "$ret" -eq 1 ]                            && ok || bad "validate bad level: return 1"
echo "$err" | grep -qi "invalid level"      && ok || bad "validate bad level: stderr mentions invalid level"
PROFILE_CONFIG="$saved_config"

# --- 16. profile_diff: work vs safe (safe has empty include → all of work's diff) ---
out="$(profile_diff "work" "safe")"
plus_count="$(echo "$out" | grep -c '^  + ')"
[ "$plus_count" -eq 6 ]                     && ok || bad "diff work safe: 6 packages only-in-work, got $plus_count"
echo "$out" | grep -q '+ git'               && ok || bad "diff work safe: shows +git"

# --- 17. profile_create: appends new section via piped input ---
out="$(printf 'newprof\nA new profile\nfoo, bar\n' | profile_create 2>&1)"; ret=$?
[ "$ret" -eq 0 ]                            && ok || bad "create: return 0"
grep -q '\[profiles.newprof\]' "$PROFILE_CONFIG" && ok || bad "create: section appended"
grep -q 'include = \["foo", "bar"\]' "$PROFILE_CONFIG" && ok || bad "create: include array correct"

# --- 18. profile_edit: EDITOR=cat shows config; nonexistent profile errors ---
EDITOR=cat
out="$(profile_edit "work")"; ret=$?
[ "$ret" -eq 0 ]                            && ok || bad "edit work: return 0"
echo "$out" | grep -q '\[profiles.work\]'   && ok || bad "edit work: cat shows config content"
profile_edit "doesnotexist" >/dev/null 2>&1 && bad "edit doesnotexist: should return 1" || ok

# --- 19. Level override logic (CLI explicit wins; profile level applies otherwise) ---
profile_load "personal" >/dev/null
LEVEL="patch"; LEVEL_EXPLICIT=false
[[ -n "$PROFILE_LEVEL" ]] && ! $LEVEL_EXPLICIT && LEVEL="$PROFILE_LEVEL"
[ "$LEVEL" = "minor" ]                      && ok || bad "level override: profile level applied (not explicit)"

LEVEL="patch"; LEVEL_EXPLICIT=true
[[ -n "$PROFILE_LEVEL" ]] && ! $LEVEL_EXPLICIT && LEVEL="$PROFILE_LEVEL"
[ "$LEVEL" = "patch" ]                      && ok || bad "level override: CLI level wins (explicit)"

# --- 20. Integration: PROFILE_NAME=work → only included packages reach the plan ---
MOCK_BIN="$(mktemp -d)"
cat > "$MOCK_BIN/brew" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "list --cask") ;;
  "outdated --verbose")
    printf 'git (2.40.0) < 2.40.1\n'
    printf 'wget (1.21.0) < 1.21.1\n'
    ;;
  "--version") echo "Homebrew 4.2.0" ;;
esac
EOF
chmod +x "$MOCK_BIN/brew"
OLD_PATH="$PATH"
export PATH="$MOCK_BIN:$PATH"

profile_load "work" >/dev/null
PROFILE_NAME="work"
DRY_RUN=true
LEVEL="patch"; LEVEL_EXPLICIT=false; OR_LOWER=false; ALLOW_DATE=false
ONLY_FORMULAE=false; ONLY_CASKS=false
CHECK_DEPS=false
PACKAGES=()

out="$(run_upgrade 2>&1)"
echo "$out" | grep -q "git"                 && ok || bad "profile filter: git (in include) appears"
echo "$out" | grep -q "wget"                && bad "profile filter: wget (not in include) should be skipped" || ok

export PATH="$OLD_PATH"
PROFILE_NAME=""
rm -rf "$MOCK_BIN"

# --- 21. --interactive without fzf → error + exit 1 ---
MOCK_BIN3="$(mktemp -d)"
cat > "$MOCK_BIN3/brew" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "list --cask") ;;
  "outdated --verbose") printf 'git (2.40.0) < 2.40.1\n' ;;
  "--version") echo "Homebrew 4.2.0" ;;
esac
EOF
chmod +x "$MOCK_BIN3/brew"
export PATH="$MOCK_BIN3:$OLD_PATH"

command() {
  [[ "$1" == "-v" && "${2:-}" == "fzf" ]] && return 1
  builtin command "$@"
}

INTERACTIVE=true
DRY_RUN=true
LEVEL="patch"; LEVEL_EXPLICIT=false; OR_LOWER=false; ALLOW_DATE=false
ONLY_FORMULAE=false; ONLY_CASKS=false
CHECK_DEPS=false
PACKAGES=()

out="$(run_upgrade 2>&1)"; ret=$?
[ "$ret" -eq 1 ]                            && ok || bad "interactive no fzf: exit 1"
echo "$out" | grep -qi "fzf"                && ok || bad "interactive no fzf: mentions fzf"

unset -f command
export PATH="$OLD_PATH"
rm -rf "$MOCK_BIN3"

# --- 22. --interactive with fzf: selection filters the plan ---
MOCK_BIN4="$(mktemp -d)"
cat > "$MOCK_BIN4/brew" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "list --cask") ;;
  "outdated --verbose")
    printf 'git (2.40.0) < 2.40.1\n'
    printf 'jq (1.6.0) < 1.7.0\n'
    ;;
  "--version") echo "Homebrew 4.2.0" ;;
esac
EOF
chmod +x "$MOCK_BIN4/brew"
cat > "$MOCK_BIN4/fzf" <<'EOF'
#!/usr/bin/env bash
# Mock fzf: simulate selecting only the first candidate.
head -n1
EOF
chmod +x "$MOCK_BIN4/fzf"
export PATH="$MOCK_BIN4:$OLD_PATH"

INTERACTIVE=true
DRY_RUN=true
PACKAGES=()

out="$(run_upgrade 2>&1)"
echo "$out" | grep -q "git"                 && ok || bad "interactive fzf: selected candidate (git) in plan"
echo "$out" | grep -q "jq"                  && bad "interactive fzf: unselected candidate (jq) should be excluded" || ok

export PATH="$OLD_PATH"
INTERACTIVE=false
rm -rf "$MOCK_BIN4"

echo "Passed: $pass, Failed: $fail"
(( fail == 0 ))
