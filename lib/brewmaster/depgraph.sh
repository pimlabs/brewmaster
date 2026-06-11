#!/usr/bin/env bash
# brewmaster: dependency graph risk analysis.
# Sourced by bin/brewmaster after core modules (uses parse_outdated_line, to_semver_3, bump_kind).
# Globals read: CHECK_DEPS, RISK_THRESHOLD, YES_FLAG, VERBOSE

# Cache path — set by depgraph_build; empty until then.
DEPGRAPH_CACHE=""

# depgraph_build — initialize cache + register EXIT cleanup.
# Call once before any other depgraph_* functions.
# Idempotent: a no-op if the cache is already built (avoids re-registering the
# EXIT trap when called from within a command-substitution subshell, which
# would delete the cache file the moment that subshell exits — before the
# caller can read it).
# Return: 0
depgraph_build() {
  [[ -n "$DEPGRAPH_CACHE" && -f "$DEPGRAPH_CACHE" ]] && return 0
  DEPGRAPH_CACHE="/tmp/brewmaster-depgraph-$$.json"
  echo '{}' > "$DEPGRAPH_CACHE"
  # shellcheck disable=SC2064 # expand now: $DEPGRAPH_CACHE is local and gone by EXIT
  trap "rm -f '${DEPGRAPH_CACHE}'" EXIT
}

# _depgraph_query — lazy-populate cache for a package's dep list.
# Args:   $1  package name
#         $2  query type: "" for runtime only; "build" for --include-build
# Stdout: JSON array of dependent package names
# Return: 0
_depgraph_query() {
  local pkg="$1"
  local qtype="${2:-}"
  local cache_key="${pkg}${qtype:+:$qtype}"

  # Cache hit
  local cached
  cached="$(jq --arg k "$cache_key" 'if has($k) then .[$k] else empty end' \
    "$DEPGRAPH_CACHE" 2>/dev/null)"
  if [[ -n "$cached" ]]; then
    echo "$cached"
    return 0
  fi

  # Fresh query
  local -a brew_args=("uses" "--installed")
  [[ "$qtype" == "build" ]] && brew_args=("uses" "--include-build" "--installed")

  local deps_output
  deps_output="$(brew "${brew_args[@]}" "$pkg" 2>/dev/null || true)"

  local arr
  if [[ -z "$deps_output" ]]; then
    arr='[]'
  else
    arr="$(echo "$deps_output" | jq -R 'select(length>0)' | jq -s '.')"
  fi

  # Write back to cache (atomic: write to tmp then mv)
  local tmp; tmp="$(mktemp)"
  jq --arg k "$cache_key" --argjson v "$arr" '. + {($k): $v}' \
    "$DEPGRAPH_CACHE" > "$tmp" && mv "$tmp" "$DEPGRAPH_CACHE"

  echo "$arr"
}

# depgraph_is_safe — check whether a package has any installed dependents.
# Args:   $1  package name
# Stdout: JSON array of runtime dependents
# Return: 0 if no dependents (safe); 1 if has dependents
depgraph_is_safe() {
  local pkg="$1"
  local arr; arr="$(_depgraph_query "$pkg" "")"
  echo "$arr"
  local count; count="$(echo "$arr" | jq 'length')"
  (( count == 0 ))
}

# depgraph_risk_score — compute a 0–10 risk score for upgrading a package.
# Args:   $1  package name
#         $2  bump kind (optional: patch|minor|major; if empty, major factor skipped)
# Scoring:
#   +3  if runtime dependents count > 0
#   +3  if kind == major
#   +2  if runtime dependents count > 3
#   +2  if --include-build adds extra dependents beyond runtime (build-time dep)
# Stdout: integer 0–10
# Return: 0
depgraph_risk_score() {
  local pkg="$1"
  local kind="${2:-}"
  local score=0

  local runtime_arr; runtime_arr="$(_depgraph_query "$pkg" "")"
  local runtime_count; runtime_count="$(echo "$runtime_arr" | jq 'length')"

  (( runtime_count > 0 )) && score=$((score+3))
  [[ "$kind" == "major" ]]  && score=$((score+3))
  (( runtime_count > 3 ))   && score=$((score+2))

  local build_arr; build_arr="$(_depgraph_query "$pkg" "build")"
  local build_count; build_count="$(echo "$build_arr" | jq 'length')"
  (( build_count > runtime_count )) && score=$((score+2))

  echo "$score"
}

# depgraph_report — print a human-readable dependency + risk summary for one package.
# Args:   $1  package name
#         $2  bump kind (optional)
# Stdout: dependents table + risk score line
# Return: 0
depgraph_report() {
  local pkg="$1"
  local kind="${2:-}"

  local arr; arr="$(_depgraph_query "$pkg" "")"
  local count; count="$(echo "$arr" | jq 'length')"
  local score; score="$(depgraph_risk_score "$pkg" "$kind")"

  echo "Package: $pkg"
  if (( count == 0 )); then
    echo "  Dependents: none"
  else
    echo "  Dependents ($count):"
    echo "$arr" | jq -r '.[]' | while IFS= read -r dep; do
      printf '    - %s\n' "$dep"
    done
  fi
  if [[ -n "$kind" ]]; then
    printf '  Risk score: %d/10  (kind=%s)\n' "$score" "$kind"
  else
    printf '  Risk score: %d/10  (base; bump type not specified)\n' "$score"
  fi
}

# depgraph_list_risky — list all outdated packages sorted by risk score, highest first.
# Reads brew outdated --verbose; computes bump kind + risk score for each package.
# Stdout: formatted table: RISK | PACKAGE | KIND | DEPS
# Return: 0
depgraph_list_risky() {
  local out; out="$(brew outdated --verbose 2>/dev/null || true)"
  local -a entries=()
  local ln parsed name old_raw new_raw old_sv new_sv kind score dep_count

  while IFS= read -r ln; do
    case "$ln" in
      *"("*")"*"<"*|*"("*")"*"!="*)
        parsed="$(parse_outdated_line "$ln")" || continue
        IFS='|' read -r name old_raw new_raw <<<"$parsed"
        old_sv="$(to_semver_3 "$old_raw" false 2>/dev/null)" || continue
        new_sv="$(to_semver_3 "$new_raw" false 2>/dev/null)" || continue
        kind="$(bump_kind "$old_sv" "$new_sv")"
        score="$(depgraph_risk_score "$name" "$kind")"
        dep_count="$(_depgraph_query "$name" "" | jq 'length')"
        entries+=("$(printf '%02d\t%s\t%s\t%s' "$score" "$name" "$kind" "$dep_count")")
      ;;
    esac
  done <<<"$out"

  if (( ${#entries[@]} == 0 )); then
    echo "No outdated packages."
    return 0
  fi

  printf '%-5s  %-28s  %-8s  %s\n' "RISK" "PACKAGE" "KIND" "DEPS"
  printf '%-5s  %-28s  %-8s  %s\n' "----" "-------" "----" "----"
  printf '%s\n' "${entries[@]}" | sort -t$'\t' -k1 -rn | \
    while IFS=$'\t' read -r score name kind deps; do
      printf '%-5s  %-28s  %-8s  %s\n' "$score" "$name" "$kind" "$deps"
    done
}
