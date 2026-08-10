#!/usr/bin/env bash
# Snapshot function tests. Uses a temp SNAP_DIR and a mock brew — no real packages touched.
set -uo pipefail

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$DIR/../lib/brewmaster"

# --- Mock brew ---
MOCK_BIN="$(mktemp -d)"
trap 'rm -rf "$MOCK_BIN" "$SNAP_DIR"' EXIT

cat > "$MOCK_BIN/brew" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list)    printf 'git\t2.44.0\nnode\t20.10.0\njq\t1.7.0\n' ;;   # --versions output
  install) echo "installed $2" ;;
  --version) echo "Homebrew 4.2.0" ;;
esac
EOF
chmod +x "$MOCK_BIN/brew"
export PATH="$MOCK_BIN:$PATH"

# --- Isolated snapshot dir ---
SNAP_DIR="$(mktemp -d)"
export BREWMASTER_SNAP_DIR="$SNAP_DIR"

# --- Isolated audit log ---
export BREWMASTER_AUDIT_LOG="$(mktemp -d)/audit.log"

# --- Globals expected by snapshot.sh ---
DRY_RUN=false
SNAP_FORCE=false
VERBOSE=false
LEVEL="patch"

logv() { $VERBOSE && echo "[v] $*" >&2 || true; }

# Source core (needed by snapshot_diff for bump_kind / to_semver_3)
# shellcheck source=../lib/brewmaster/core/semver.sh
source "$LIB/core/semver.sh"
# shellcheck source=../lib/brewmaster/core/ui.sh
source "$LIB/core/ui.sh"
ui_color_init
# shellcheck source=../lib/brewmaster/audit.sh
source "$LIB/audit.sh"
# shellcheck source=../lib/brewmaster/snapshot.sh
source "$LIB/snapshot.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

# --- 1. snapshot_save creates .txt + .meta.json, prints path ---
txt="$(snapshot_save)"
[ -f "$txt" ]                              && ok || bad "save: .txt created"
[ -f "${txt%.txt}.meta.json" ]             && ok || bad "save: .meta.json created"
echo "$txt" | grep -q '.txt$'             && ok || bad "save: stdout is .txt path"
grep -q "git" "$txt"                       && ok || bad "save: git in snapshot"

# --- 2. snapshot_save with label embeds label in filename ---
txt2="$(snapshot_save "mytest")"
basename "$txt2" | grep -q 'mytest'        && ok || bad "save label: filename contains label"

# --- 3. snapshot_list shows entries ---
out="$(snapshot_list)"
echo "$out" | grep -q 'mytest'             && ok || bad "list: label visible"
echo "$out" | grep -qE '^[[:space:]]*1[[:space:]]' && ok || bad "list: index 1 present"
echo "$out" | grep -qE '[0-9]+'            && ok || bad "list: package count shown"

# --- 4. _snap_resolve integer returns newest path ---
resolved="$(_snap_resolve 1)"
[ -f "$resolved" ]                         && ok || bad "resolve: index 1 gives valid path"
# newest = txt2 (saved last); ls -t puts newest first
[ "$resolved" = "$txt2" ]                  && ok || bad "resolve: index 1 is newest"

# --- 5. _snap_resolve path passthrough ---
resolved_path="$(_snap_resolve "$txt")"
[ "$resolved_path" = "$txt" ]              && ok || bad "resolve: direct path passthrough"

# --- 6. _snap_resolve invalid index → exit non-zero ---
_snap_resolve 999 2>/dev/null && bad "resolve: invalid index should fail" || ok

# --- 7. snapshot_diff shows REMOVED for package not in current brew ---
# Inject a snapshot that contains an extra package (oldpkg) not in mock brew
fake_snap="$SNAP_DIR/20200101-000000-old.txt"
printf 'git\t2.44.0\noldpkg\t1.0.0\n' > "$fake_snap"
jq -n '{ label:"old", brew_version:"4.0", package_count:2 }' > "${fake_snap%.txt}.meta.json"
diff_out="$(snapshot_diff "$fake_snap")"
echo "$diff_out" | grep -q 'REMOVED'      && ok || bad "diff: REMOVED for missing package"

# --- 8. snapshot_diff shows UPGRADE for newer version ---
# Inject snapshot where git is older (2.40.0), current mock is 2.44.0
fake_old="$SNAP_DIR/20200101-010000-fortest.txt"
printf 'git\t2.40.0\n' > "$fake_old"
jq -n '{ label:"fortest", brew_version:"4.0", package_count:1 }' > "${fake_old%.txt}.meta.json"
diff_out2="$(snapshot_diff "$fake_old")"
echo "$diff_out2" | grep -q 'UPGRADE'     && ok || bad "diff: UPGRADE for newer current version"

# --- 9. snapshot_diff shows NEW for package added since snapshot ---
fake_nonode="$SNAP_DIR/20200101-020000-nonode.txt"
printf 'git\t2.44.0\n' > "$fake_nonode"
jq -n '{ label:"nonode", brew_version:"4.0", package_count:1 }' > "${fake_nonode%.txt}.meta.json"
diff_out3="$(snapshot_diff "$fake_nonode")"
echo "$diff_out3" | grep -q 'NEW'         && ok || bad "diff: NEW for packages added since snapshot"

# --- 10. snapshot_restore --dry-run prints plan, brew install NOT called ---
brew_called=false
cat > "$MOCK_BIN/brew" <<'EOF2'
#!/usr/bin/env bash
case "$1" in
  list)    printf 'git\t2.44.0\nnode\t20.10.0\n' ;;
  install) echo "BREW_CALLED"; exit 0 ;;
  --version) echo "Homebrew 4.2.0" ;;
esac
EOF2
fake_restore="$SNAP_DIR/20200101-030000-restore.txt"
printf 'git\t2.40.0\noldpkg\t9.9.9\n' > "$fake_restore"
jq -n '{ label:"restore", brew_version:"4.0", package_count:2 }' > "${fake_restore%.txt}.meta.json"
DRY_RUN=true
restore_out="$(snapshot_restore "$fake_restore")"
DRY_RUN=false
echo "$restore_out" | grep -q 'Restore plan'      && ok || bad "restore dry-run: prints plan"
echo "$restore_out" | grep -qv 'BREW_CALLED'       && ok || bad "restore dry-run: brew NOT called"

# --- 11. snapshot_delete --force removes both files ---
SNAP_FORCE=true
del_txt="$SNAP_DIR/20200101-040000-del.txt"
del_meta="${del_txt%.txt}.meta.json"
printf 'git\t2.44.0\n' > "$del_txt"
jq -n '{ label:"del", brew_version:"4.0", package_count:1 }' > "$del_meta"
snapshot_delete "$del_txt"
[ ! -f "$del_txt" ]  && ok || bad "delete: .txt removed"
[ ! -f "$del_meta" ] && ok || bad "delete: .meta.json removed"
SNAP_FORCE=false

echo "Passed: $pass, Failed: $fail"
(( fail == 0 ))
