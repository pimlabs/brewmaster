#!/usr/bin/env bash
# brewmaster core: parse `brew outdated --verbose` output.
# Sourced by bin/brewmaster; defines functions only.

# parse_outdated_line — extract fields from a single `brew outdated --verbose` line.
# Args:   $1  line, e.g. "name (1.0) < 2.0" or "name (1.0, 1.1) != 2.0"
# Stdout: "name|old|new|op" where old is the newest installed version
#         when several are present.
# Return: 0 on match, 1 otherwise.
parse_outdated_line() {
  local line="$1"
  local re='^([A-Za-z0-9@._/+:-]+)[[:space:]]+\(([^)]+)\)[[:space:]]+(<|<=|!=)[[:space:]]+([^[:space:]]+)'
  if [[ $line =~ $re ]]; then
    local name="${BASH_REMATCH[1]}"
    local olds="${BASH_REMATCH[2]}"
    local op="${BASH_REMATCH[3]}"
    local new="${BASH_REMATCH[4]}"
    local old
    old="$(echo "$olds" | awk -F',' '{gsub(/^[ \t]+|[ \t]+$/,"",$NF); print $NF}')"
    echo "${name}|${old}|${new}|${op}"
    return 0
  fi
  return 1
}
