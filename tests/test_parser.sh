#!/usr/bin/env bash
# Parser tests for bin/brewmaster: the command may follow flags
# ("brewmaster -n snapshot list" is "brewmaster snapshot list -n"), and a
# value that follows a space-form value flag is never taken as a command.
# Uses a mock `brew` on PATH; safe.
# shellcheck disable=SC2015 # `&& ok || bad` is the assert idiom every test file uses
set -uo pipefail

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BM="$DIR/../bin/brewmaster"

MOCK="$(mktemp -d)"
DATA="$(mktemp -d)"
trap 'rm -rf "$MOCK" "$DATA"' EXIT
export XDG_DATA_HOME="$DATA" XDG_CONFIG_HOME="$DATA" BREWMASTER_AUDIT_LOG="$DATA/audit.log"
cat > "$MOCK/brew" <<'MOCKEOF'
#!/usr/bin/env bash
case "$1" in
  list)     echo "somecask" ;;
  outdated) printf 'foo (1.0.0) < 1.0.5\n' ;;
  upgrade)  echo "upgraded $2" ;;
esac
MOCKEOF
chmod +x "$MOCK/brew"
# A mock fzf, so no case can ever reach the real picker: on a runner with
# fzf installed, fzf blocks on /dev/tty and the suite hangs.
printf '#!/usr/bin/env bash\nexit 130\n' > "$MOCK/fzf"; chmod +x "$MOCK/fzf"
run() { PATH="$MOCK:$PATH" NO_COLOR=1 "$BM" "$@" 2>&1; }

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

# 1. command after a flag: snapshot list, not an upgrade of "snapshot" "list"
out="$(run -n snapshot list)"
echo "$out" | grep -q "No snapshots found" && ok || bad "-n snapshot list runs snapshot list (got: $(echo "$out" | head -1))"
echo "$out" | grep -q "upgrade\|candidate" && bad "-n snapshot list must not run upgrade" || ok

# 2. sub-subcommand still follows the command; flag in between is not hoisted past it
out="$(run -v snapshot list)"
echo "$out" | grep -q "No snapshots found" && ok || bad "-v snapshot list runs snapshot list"

# 3. value of a space-form flag is not a command
out="$(run --level patch -n)"
echo "$out" | grep -q "Unknown command" && bad "--level patch: 'patch' must not be read as a command" || ok
out="$(run --level patch snapshot list)"
echo "$out" | grep -q "No snapshots found" && ok || bad "--level patch snapshot list runs snapshot list"

# 4. a package name after a flag is still a package for the default command
out="$(run -n foo)"
echo "$out" | grep -q "foo" && ok || bad "-n foo is a dry-run upgrade naming foo"
echo "$out" | grep -q "Unknown command" && bad "-n foo must not error" || ok

# 5. help after a flag
out="$(run -v help snapshot)"
echo "$out" | grep -q "SNAPSHOT" && ok || bad "-v help snapshot prints the snapshot help"

# 6. command-first form is unchanged
out="$(run snapshot list -n)"
echo "$out" | grep -q "No snapshots found" && ok || bad "snapshot list -n still works"

# 7. unknown command still errors, wherever it sits (first non-flag word that is not a command is a package, so only $1 can be "unknown")
out="$(run bogus 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && echo "$out" | grep -q "Unknown command: bogus" && ok || bad "bogus as first word is an unknown command"

# 8. --version anywhere still short-circuits
run -n --version | grep -q "^brewmaster " && ok || bad "-n --version prints the version"

echo "Passed: $pass, Failed: $fail"
(( fail == 0 ))
