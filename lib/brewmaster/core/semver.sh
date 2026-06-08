#!/usr/bin/env bash
# brewmaster core: semantic-version parsing and bump classification.
# Sourced by bin/brewmaster; defines functions only (no top-level execution).

# to_semver_3 — normalize a raw version string to "MAJOR.MINOR.PATCH".
# Args:    $1  raw version (e.g. "1.2", "1.2.3_1", "1.2.3-rc.1", "2024.05.01")
# Stdout:  normalized "M.m.p"
# Return:  0 on success; 1 if not parseable, or a date version while ALLOW_DATE=false
# Globals: ALLOW_DATE (bool) — when false, date-style versions are rejected.
to_semver_3() {
  local raw="$1"
  local s="$raw"

  # Date/timestamp format (YYYY.MM.DD / YYYY-MM-DD, optional T... / -hash)
  if [[ "$raw" =~ ^([0-9]{4})[.-]([0-9]{2})[.-]([0-9]{2})(T[^ ]*)?([_-][^ ]*)?$ ]]; then
    $ALLOW_DATE || return 1
    local yy=$((10#${BASH_REMATCH[1]}))
    local mm=$((10#${BASH_REMATCH[2]}))
    local dd=$((10#${BASH_REMATCH[3]}))
    echo "${yy}.${mm}.${dd}"
    return 0
  fi

  # Semver-like: strip +build, _rev, and pre-release suffixes before matching.
  s="${s%%+*}"
  s="${s%%_*}"
  s="${s%%-*}"

  if [[ "$s" =~ ^([0-9]+)\.([0-9]+)(\.([0-9]+))?$ ]]; then
    local maj="${BASH_REMATCH[1]}"
    local min="${BASH_REMATCH[2]}"
    local pat="${BASH_REMATCH[4]:-0}"
    echo "${maj}.${min}.${pat}"
    return 0
  fi
  return 1
}

# bump_kind — classify the change between two normalized versions.
# Args:   $1  old "M.m.p"
#         $2  new "M.m.p"
# Stdout: one of: major | minor | patch | downgrade | none
# Return: 0
bump_kind() {
  local old="$1" new="$2"
  local oM oN oP nM nN nP
  IFS=. read -r oM oN oP <<<"$old"
  IFS=. read -r nM nN nP <<<"$new"
  oM=$((10#$oM)); oN=$((10#$oN)); oP=$((10#$oP))
  nM=$((10#$nM)); nN=$((10#$nN)); nP=$((10#$nP))

  if   (( nM > oM )); then echo "major"
  elif (( nM < oM )); then echo "downgrade"
  else
    if   (( nN > oN )); then echo "minor"
    elif (( nN < oN )); then echo "downgrade"
    else
      if   (( nP > oP )); then echo "patch"
      elif (( nP < oP )); then echo "downgrade"
      else echo "none"
      fi
    fi
  fi
}

# allow_by_level — decide whether a bump kind passes the chosen level gate.
# Args:   $1  kind  (patch|minor|major|downgrade|none)
#         $2  level (patch|minor|major)
#         $3  or_lower (true|false) — true = inclusive (<=), false = exclusive (==)
# Return: 0 if allowed, 1 otherwise. downgrade/none are never allowed.
allow_by_level() {
  local kind="$1" lvl="$2" incl="$3"
  local k=0 l=0
  case "$kind" in
    patch) k=1 ;; minor) k=2 ;; major) k=3 ;;
    none|downgrade) return 1 ;;
    *) return 1 ;;
  esac
  case "$lvl" in
    patch) l=1 ;; minor) l=2 ;; major) l=3 ;;
  esac
  if $incl; then
    (( k <= l ))     # inclusive
  else
    (( k == l ))     # exclusive
  fi
}
