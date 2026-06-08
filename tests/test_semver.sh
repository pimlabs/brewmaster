#!/usr/bin/env bash
# Unit tests for lib/brewmaster/core/semver.sh
set -uo pipefail

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOW_DATE=false
# shellcheck source=../lib/brewmaster/core/semver.sh
source "$DIR/../lib/brewmaster/core/semver.sh"

pass=0; fail=0

# assert_eq DESC EXPECTED ACTUAL
assert_eq() {
  local desc="$1" exp="$2" act="$3"
  if [[ "$exp" == "$act" ]]; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); echo "FAIL: $desc (expected '$exp', got '$act')" >&2
  fi
}

# assert_true DESC CMD... — expects zero exit
assert_true() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass=$((pass+1))
  else fail=$((fail+1)); echo "FAIL: $desc (expected success)" >&2; fi
}

# assert_false DESC CMD... — expects non-zero exit
assert_false() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then fail=$((fail+1)); echo "FAIL: $desc (expected failure)" >&2
  else pass=$((pass+1)); fi
}

# --- to_semver_3 ---
assert_eq "plain semver"            "1.2.3"   "$(to_semver_3 1.2.3)"
assert_eq "missing patch -> .0"     "1.2.0"   "$(to_semver_3 1.2)"
assert_eq "strip +build"            "1.2.3"   "$(to_semver_3 1.2.3+build5)"
assert_eq "strip _rev"              "1.2.3"   "$(to_semver_3 1.2.3_1)"
assert_eq "strip pre-release"       "1.2.3"   "$(to_semver_3 1.2.3-rc.1)"
assert_false "garbage non-semver"   to_semver_3 "not-a-version"
assert_false "date rejected (ALLOW_DATE=false)" to_semver_3 "2024.05.01"

ALLOW_DATE=true
assert_eq "date dot form (ALLOW_DATE=true)"  "2024.5.1" "$(to_semver_3 2024.05.01)"
assert_eq "date dash form (ALLOW_DATE=true)" "2024.5.1" "$(to_semver_3 2024-05-01)"
ALLOW_DATE=false

# --- bump_kind ---
assert_eq "major bump"  "major"     "$(bump_kind 1.0.0 2.0.0)"
assert_eq "minor bump"  "minor"     "$(bump_kind 1.1.0 1.2.0)"
assert_eq "patch bump"  "patch"     "$(bump_kind 1.1.1 1.1.2)"
assert_eq "downgrade"   "downgrade" "$(bump_kind 2.0.0 1.0.0)"
assert_eq "none"        "none"      "$(bump_kind 1.0.0 1.0.0)"

# --- allow_by_level ---
assert_true  "patch passes level=patch exclusive"     allow_by_level patch patch false
assert_false "minor blocked at level=patch exclusive" allow_by_level minor patch false
assert_true  "patch passes level=minor inclusive"     allow_by_level patch minor true
assert_false "downgrade never allowed"                allow_by_level downgrade major true

echo "Passed: $pass, Failed: $fail"
(( fail == 0 ))
