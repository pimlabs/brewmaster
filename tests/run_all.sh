#!/usr/bin/env bash
# tests/run_all.sh — run every tests/test_*.sh in sequence and summarize.
# Same file list as .github/workflows/ci.yml, but keeps going after a
# failing file so a single run reports every failure.
# Args:    none
# Stdout:  each test file's own output, then a summary line
# Return:  0 if every test file passed; 1 otherwise
set -uo pipefail

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failed=()
total=0
for f in "$DIR"/test_*.sh; do
  total=$((total+1))
  echo "=== ${f#"$DIR/"} ==="
  bash "$f" || failed+=("${f#"$DIR/"}")
done

echo
if (( ${#failed[@]} == 0 )); then
  echo "All ${total} test file(s) passed."
  exit 0
fi
echo "Failed ${#failed[@]}/${total} test file(s):" >&2
printf '  - %s\n' "${failed[@]}" >&2
exit 1
