#!/usr/bin/env bash
# brewmaster: dependency graph risk analysis.
# Sourced by bin/brewmaster after core modules (uses parse_outdated_line, to_semver_3, bump_kind).
# Globals read: CHECK_DEPS, RISK_THRESHOLD, YES_FLAG, VERBOSE

# Cache path — set by depgraph_build; empty until then.
DEPGRAPH_CACHE=""

# depgraph_build — fetch `brew info --json=v2 --installed` once and derive
# reverse-dependency maps into DEPGRAPH_CACHE: {"runtime": {pkg: [dependents]},
# "build": {pkg: [dependents]}}. Replaces the old per-package `brew uses`
# calls (each `brew` invocation pays ~5-10s of Ruby/Formulary startup, so
# 200+ packages took tens of minutes); this is a single brew call.
#   runtime[pkg] = installed formulae whose installed[0].runtime_dependencies
#                  includes pkg
#   build[pkg]   = installed formulae that declare pkg in dependencies,
#                  build_dependencies, optional_dependencies, or
#                  recommended_dependencies (superset of runtime, mirrors
#                  `brew uses --include-build`)
# Idempotent: a no-op if the cache is already built (avoids re-registering the
# EXIT trap when called from within a command-substitution subshell, which
# would delete the cache file the moment that subshell exits — before the
# caller can read it).
# Return: 0
depgraph_build() {
  [[ -n "$DEPGRAPH_CACHE" && -f "$DEPGRAPH_CACHE" ]] && return 0
  DEPGRAPH_CACHE="/tmp/brewmaster-depgraph-$$.json"
  brew info --json=v2 --installed 2>/dev/null | jq '
    reduce .formulae[] as $f (
      {runtime: {}, build: {}};
      reduce (($f.installed[0].runtime_dependencies // [])[].full_name) as $d (.;
        .runtime[$d] = ((.runtime[$d] // []) + [$f.name])
      ) |
      reduce ((($f.dependencies // []) + ($f.build_dependencies // [])
               + ($f.optional_dependencies // []) + ($f.recommended_dependencies // [])
               | unique)[]) as $d (.;
        .build[$d] = ((.build[$d] // []) + [$f.name])
      )
    )
  ' > "$DEPGRAPH_CACHE" 2>/dev/null
  [[ -s "$DEPGRAPH_CACHE" ]] || echo '{"runtime":{},"build":{}}' > "$DEPGRAPH_CACHE"
  # shellcheck disable=SC2064 # expand now: $DEPGRAPH_CACHE is local and gone by EXIT
  trap "rm -f '${DEPGRAPH_CACHE}'" EXIT
}

# _depgraph_query — look up a package's dependent list from DEPGRAPH_CACHE.
# Args:   $1  package name
#         $2  query type: "" for runtime only; "build" for --include-build
# Stdout: JSON array of dependent package names
# Return: 0
_depgraph_query() {
  local pkg="$1"
  local qtype="${2:-}"
  local key="runtime"
  [[ "$qtype" == "build" ]] && key="build"
  jq --arg p "$pkg" --arg k "$key" '.[$k][$p] // []' "$DEPGRAPH_CACHE" 2>/dev/null
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

# _depgraph_risk_color "$score" — map a 0-10 risk score to a semantic
# color constant using the thresholds already used to gate upgrades:
# HIGH >= RISK_THRESHOLD (default 7), MEDIUM 4-6, LOW 0-3.
# Args:   $1 score (integer 0-10)
# Stdout: COLOR_HIGH, COLOR_WARN, or COLOR_OK
# Return: 0
_depgraph_risk_color() {
  local score="$1"
  if (( score >= RISK_THRESHOLD )); then echo "$COLOR_HIGH"
  elif (( score >= 4 )); then echo "$COLOR_WARN"
  else echo "$COLOR_OK"
  fi
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
  local color; color="$(_depgraph_risk_color "$score")"
  local score_str; score_str="$(ui_colorize "" "$color" "${score}/10")"

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
    printf '  Risk score: %s  (kind=%s)\n' "$score_str" "$kind"
  else
    printf '  Risk score: %s  (base; bump type not specified)\n' "$score_str"
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

  ui_table_header 5 "RISK" 28 "PACKAGE" 8 "KIND" "" "DEPS"
  printf '%s\n' "${entries[@]}" | sort -t$'\t' -k1 -rn | \
    while IFS=$'\t' read -r score name kind deps; do
      local color risk_field
      color="$(_depgraph_risk_color "$((10#$score))")"
      risk_field="$(ui_colorize 5 "$color" "$score")"
      ui_table_row "" "$risk_field" 28 "$name" 8 "$kind" "" "$deps"
    done
}
