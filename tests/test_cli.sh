#!/usr/bin/env bash
# CLI behavior tests for bin/brewmaster using a mock `brew` on PATH.
# Safe: the mock never touches real packages.
set -uo pipefail

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BM="$DIR/../bin/brewmaster"

MOCK="$(mktemp -d)"
AUDIT_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK" "$AUDIT_DIR"' EXIT
export BREWMASTER_AUDIT_LOG="$AUDIT_DIR/audit.log"
cat > "$MOCK/brew" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list)     echo "somecask" ;;                                  # brew list --cask
  outdated) printf 'foo (1.0.0) < 1.0.5\nbar (2.1.0) < 2.4.0\nbaz (3.0.0) < 4.0.0\n' ;;
  upgrade)  echo "upgraded $2" ;;
esac
EOF
chmod +x "$MOCK/brew"

# jq is a real dependency (used for audit log entries); symlink it into MOCK
# so `run_no_fzf` below can drop the rest of PATH (where a real host `fzf`
# might live, e.g. Homebrew's bin) without losing jq too.
ln -s "$(command -v jq)" "$MOCK/jq"

run()  { PATH="$MOCK:$PATH" "$BM" "$@"; }      # brewmaster with mock brew
# Same, but PATH is restricted to MOCK + bare-minimum system dirs, so no real
# `fzf` on the host machine can be found — exercises the no-fzf fallback.
run_no_fzf() { PATH="$MOCK:/usr/bin:/bin" "$BM" "$@"; }
rows() { grep -c '  - ' || true; }             # count candidate rows

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

# 1. default level = patch -> only foo (bar=minor, baz=major excluded)
out="$(run upgrade --dry-run 2>/dev/null)"
echo "$out" | grep -q 'level=patch'  && ok || bad "default level should be patch"
[ "$(echo "$out" | rows)" = "1" ]    && ok || bad "default patch should yield 1 candidate"
echo "$out" | grep -q '  - foo '     && ok || bad "default patch candidate should be foo"

# 2. --major selects baz
out="$(run upgrade --major --dry-run 2>/dev/null)"
echo "$out" | grep -q 'level=major'  && ok || bad "--major header"
echo "$out" | grep -q '  - baz '     && ok || bad "--major candidate should be baz"

# 3. --level=patch alias == --patch
a="$(run upgrade --patch    --dry-run 2>/dev/null | grep '  - ')"
b="$(run upgrade --level=patch --dry-run 2>/dev/null | grep '  - ')"
[ "$a" = "$b" ] && ok || bad "--level=patch should equal --patch"

# 4. level flags are mutually exclusive
run upgrade --patch --minor >/dev/null 2>&1 && bad "--patch --minor should fail" || ok

# 5. package filter (intersect with level)
out="$(run upgrade bar --minor --dry-run 2>/dev/null)"
{ [ "$(echo "$out" | rows)" = "1" ] && echo "$out" | grep -q '  - bar '; } && ok || bad "upgrade bar --minor -> only bar"
out="$(run upgrade foo --minor --dry-run 2>/dev/null)"
[ "$(echo "$out" | rows)" = "0" ] && ok || bad "upgrade foo --minor -> 0 (foo is patch)"

# 6. unknown command fails
run boguscmd >/dev/null 2>&1 && bad "unknown command should fail" || ok

# 7. invalid --level value fails
run upgrade --level=bogus >/dev/null 2>&1 && bad "invalid level should fail" || ok

# 8. execution branch (non-dry-run) upgrades the candidate
#    --yes is required now: without it, execution stops at the review gate.
out="$(run upgrade --patch --yes 2>/dev/null)"; rc=$?
echo "$out" | grep -q 'upgraded foo' && ok || bad "execution should upgrade foo"
[ "$rc" -eq 0 ]                       && ok || bad "execution should exit 0"

# 9. --help degrades to plain text (byte-identical) when NO_COLOR is set or
#    output is piped (non-TTY), regardless of styling added for TTY output
diff <(NO_COLOR=1 "$BM" --help) "$DIR/fixtures/help.txt" >/dev/null \
  && ok || bad "--help with NO_COLOR should match tests/fixtures/help.txt"
diff <("$BM" --help | cat) "$DIR/fixtures/help.txt" >/dev/null \
  && ok || bad "--help piped (non-TTY) should match tests/fixtures/help.txt"

# 10. --dry-run never triggers the review step (no prompt, no execution),
#     even with a real fzf reachable on PATH — proves the table-only
#     dry-run path returns before the review gate is reached at all.
out="$(run upgrade --patch --dry-run 2>/dev/null)"; rc=$?
echo "$out" | grep -q '  - foo '  && ok || bad "dry-run: still shows candidate table"
echo "$out" | grep -q 'upgraded' && bad "dry-run: must not execute" || ok
[ "$rc" -eq 0 ]                  && ok || bad "dry-run: exits 0"

# 11. no fzf (run_no_fzf strips PATH down to MOCK + bare system dirs),
#     review declined -> nothing upgraded, exits 0
#     (prompt itself goes to stderr, so keep it merged for this assertion)
out="$(echo n | run_no_fzf upgrade --patch 2>&1)"; rc=$?
echo "$out" | grep -q 'Upgrade all?' && ok || bad "no-fzf fallback: shows [y/N] prompt"
echo "$out" | grep -q 'upgraded'     && bad "no-fzf fallback, declined: must not execute" || ok
[ "$rc" -eq 0 ]                      && ok || bad "no-fzf fallback, declined: exits 0"

# 12. no fzf, review confirmed -> upgrades
out="$(echo y | run_no_fzf upgrade --patch 2>/dev/null)"
echo "$out" | grep -q 'upgraded foo' && ok || bad "no-fzf fallback, confirmed: upgrades foo"

# 13. --yes skips the review step entirely (no prompt) even with no input piped
out="$(run_no_fzf upgrade --patch --yes 2>&1)"
echo "$out" | grep -q 'Upgrade all?' && bad "--yes: must not show review prompt" || ok
echo "$out" | grep -q 'upgraded foo' && ok || bad "--yes: still upgrades foo"

# 14. `help <command>` dispatch: known single-command group (cleanup)
diff <(NO_COLOR=1 "$BM" help cleanup) "$DIR/fixtures/help-cleanup.txt" >/dev/null \
  && ok || bad "help cleanup should match tests/fixtures/help-cleanup.txt"

# 15. `help <command>` dispatch: known multi-command group (snapshot)
diff <(NO_COLOR=1 "$BM" help snapshot) "$DIR/fixtures/help-snapshot.txt" >/dev/null \
  && ok || bad "help snapshot should match tests/fixtures/help-snapshot.txt"

# 16. `help <command>` dispatch: unknown command -> stderr error, exit 1, no
#     partial help content on stdout
out="$("$BM" help nosuchcommand 2>/dev/null)"; rc=$?
err="$("$BM" help nosuchcommand 2>&1 >/dev/null)"
[ -z "$out" ]                                  && ok || bad "help nosuchcommand: stdout must be empty"
echo "$err" | grep -q 'Unknown command: nosuchcommand' && ok || bad "help nosuchcommand: stderr should name the unknown command"
[ "$rc" -eq 1 ]                                && ok || bad "help nosuchcommand: exits 1"

# 17. bare `help` (no argument) behaves exactly like --help
diff <(NO_COLOR=1 "$BM" help) <(NO_COLOR=1 "$BM" --help) >/dev/null \
  && ok || bad "bare help should match --help output"

# 18. `--version`/`-V` output includes the build date
out="$("$BM" --version)"
echo "$out" | grep -qE '^brewmaster [0-9]+\.[0-9]+\.[0-9]+ \(built [0-9]{4}-[0-9]{2}-[0-9]{2}\)$' \
  && ok || bad "--version should print 'brewmaster <version> (built <date>)'"
[ "$("$BM" -V)" = "$out" ] && ok || bad "-V should match --version output"

echo "Passed: $pass, Failed: $fail"
(( fail == 0 ))
