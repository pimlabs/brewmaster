#!/usr/bin/env bash
# Documentation drift tests: guards against docs/brewmaster.1 falling out
# of step with the generator that derives it from help_data.sh.
set -uo pipefail

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$DIR/../docs/gen-man.sh"
MAN="$DIR/../docs/brewmaster.1"

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

# 1. committed man page must equal the generator's current output
diff <(bash "$GEN") "$MAN" >/dev/null \
  && ok || bad "docs/brewmaster.1 has drifted from docs/gen-man.sh output; regenerate with: docs/gen-man.sh > docs/brewmaster.1"

echo "Passed: $pass, Failed: $fail"
(( fail == 0 ))
