#!/usr/bin/env bash
# brewmaster: named upgrade profiles (TOML config).
# Sourced by bin/brewmaster after depgraph.sh (uses _in_list from core/upgrade.sh).
# Globals read:  PROFILE_CONFIG
# Globals set by profile_load: PROFILE_INCLUDE PROFILE_EXCLUDE
#                PROFILE_REQUIRE_CONFIRM PROFILE_MAX_RISK PROFILE_LEVEL

# Config file path (overridable for tests via BREWMASTER_PROFILE_CONFIG).
PROFILE_CONFIG="${BREWMASTER_PROFILE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/brewmaster/profiles.toml}"

# _profile_config_file — print the active profiles.toml path.
_profile_config_file() { echo "$PROFILE_CONFIG"; }

# _profile_ensure_dir — create the config directory if missing.
_profile_ensure_dir() { mkdir -p "$(dirname "$(_profile_config_file)")"; }

# _profile_section — print the body lines of [profiles.$name], excluding the header.
# Args:   $1 profile name; $2 config file path
# Stdout: lines until the next [section] header (or EOF)
_profile_section() {
  local name="$1" file="$2"
  awk -v name="$name" '
    $0 ~ "^\\[profiles\\." name "\\]" { found=1; next }
    /^\[/ { found=0 }
    found { print }
  ' "$file"
}

# _profile_parse_toml_array — split a TOML array literal into one item per line.
# Args:   $1  raw value, e.g. ["node", "python@3.12"] or []
# Stdout: one unquoted item per line (nothing for an empty array)
_profile_parse_toml_array() {
  local raw="$1"
  raw="${raw#*\[}"
  raw="${raw%\]*}"
  [[ -z "${raw//[[:space:]]/}" ]] && return 0
  echo "$raw" | tr ',' '\n' | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//'
}

# profile_load — parse [profiles.$name] and populate PROFILE_* globals.
# Args:   $1 profile name
# Return: 0 on success; 1 if config file or profile section is missing
profile_load() {
  local name="$1"
  local file; file="$(_profile_config_file)"

  [[ -f "$file" ]] || { echo "Error: profile config not found: $file" >&2; return 1; }

  if ! grep -q "^\[profiles\.${name}\]" "$file"; then
    echo "Error: profile '${name}' not found in ${file}" >&2
    return 1
  fi

  PROFILE_INCLUDE=()
  PROFILE_EXCLUDE=()
  PROFILE_REQUIRE_CONFIRM=false
  PROFILE_MAX_RISK=10
  PROFILE_LEVEL=""

  local line key val item
  while IFS= read -r line; do
    line="${line%%#*}"
    [[ -z "${line//[[:space:]]/}" ]] && continue

    key="$(echo "$line" | sed 's/[[:space:]]*=.*//' | tr -d '[:space:]')"
    val="$(echo "$line" | sed -e 's/^[^=]*=[[:space:]]*//' -e 's/[[:space:]]*$//')"

    case "$key" in
      include)
        while IFS= read -r item; do
          [[ -n "$item" ]] && PROFILE_INCLUDE+=("$item")
        done < <(_profile_parse_toml_array "$val") ;;
      exclude)
        while IFS= read -r item; do
          [[ -n "$item" ]] && PROFILE_EXCLUDE+=("$item")
        done < <(_profile_parse_toml_array "$val") ;;
      level)
        PROFILE_LEVEL="$(echo "$val" | tr -d '"')" ;;
      max_risk_score)
        PROFILE_MAX_RISK="$val" ;;
      require_confirm)
        [[ "$val" == "true" ]] && PROFILE_REQUIRE_CONFIRM=true ;;
      *) : ;;
    esac
  done < <(_profile_section "$name" "$file")

  return 0
}

# profile_list — print all configured profiles with their descriptions.
# Stdout: NAME | DESCRIPTION table
profile_list() {
  local file; file="$(_profile_config_file)"
  if [[ ! -f "$file" ]]; then
    echo "No profiles configured. Create one with: brewmaster profile create" >&2
    return 1
  fi

  local -a names=()
  while IFS= read -r line; do
    names+=("$(echo "$line" | sed -E 's/^\[profiles\.(.*)\]$/\1/')")
  done < <(grep -E '^\[profiles\.[^]]+\]' "$file")

  if (( ${#names[@]} == 0 )); then
    echo "No profiles configured in $file"
    return 0
  fi

  printf '%-16s  %s\n' "NAME" "DESCRIPTION"
  printf '%-16s  %s\n' "----" "-----------"
  local n desc
  for n in "${names[@]}"; do
    desc="$(_profile_section "$n" "$file" | grep '^description' | sed -e 's/^[^=]*=[[:space:]]*//' -e 's/^"//' -e 's/"$//')" || true
    printf '%-16s  %s\n' "$n" "${desc:--}"
  done
}

# profile_filter_package — decide whether $pkg is allowed under the active profile.
# Args:   $1 package name
# Return: 0 if allowed; 1 if it should be skipped
# Reads:  PROFILE_INCLUDE PROFILE_EXCLUDE
profile_filter_package() {
  local pkg="$1"

  if (( ${#PROFILE_INCLUDE[@]} > 0 )); then
    _in_list "$pkg" "${PROFILE_INCLUDE[@]}"
    return $?
  fi

  if (( ${#PROFILE_EXCLUDE[@]} > 0 )) && _in_list "$pkg" "${PROFILE_EXCLUDE[@]}"; then
    return 1
  fi

  return 0
}

# profile_diff — show which packages differ between two profiles' include lists.
# Args:   $1 profile name A; $2 profile name B
# Stdout: "+ pkg (only in A)" / "- pkg (only in B)" lines
# Return: 1 if either profile is missing
profile_diff() {
  local a="$1" b="$2"
  if [[ -z "$a" || -z "$b" ]]; then
    echo "Usage: brewmaster profile diff <profile_a> <profile_b>" >&2
    return 1
  fi

  profile_load "$a" || return 1
  local -a inc_a=()
  (( ${#PROFILE_INCLUDE[@]} > 0 )) && inc_a=("${PROFILE_INCLUDE[@]}")

  profile_load "$b" || return 1
  local -a inc_b=()
  (( ${#PROFILE_INCLUDE[@]} > 0 )) && inc_b=("${PROFILE_INCLUDE[@]}")

  if (( ${#inc_a[@]} == 0 )) && (( ${#inc_b[@]} == 0 )); then
    echo "Profile '$a' vs '$b': both allow all packages (no include list to compare)."
    return 0
  fi

  echo "Profile '$a' vs '$b':"
  local pkg
  for pkg in "${inc_a[@]:-}"; do
    [[ -z "$pkg" ]] && continue
    if (( ${#inc_b[@]} == 0 )) || ! _in_list "$pkg" "${inc_b[@]}"; then
      echo "  + $pkg  (only in $a)"
    fi
  done
  for pkg in "${inc_b[@]:-}"; do
    [[ -z "$pkg" ]] && continue
    if (( ${#inc_a[@]} == 0 )) || ! _in_list "$pkg" "${inc_a[@]}"; then
      echo "  - $pkg  (only in $b)"
    fi
  done
}

# profile_create — interactive wizard; appends a new [profiles.NAME] section.
# Reads name/description/include list from stdin.
# Return: 1 if name is empty or already exists
profile_create() {
  local file; file="$(_profile_config_file)"
  _profile_ensure_dir

  local name desc include_csv
  printf "Profile name: " >&2
  read -r name
  [[ -z "$name" ]] && { echo "Error: profile name required." >&2; return 1; }

  if [[ -f "$file" ]] && grep -q "^\[profiles\.${name}\]" "$file"; then
    echo "Error: profile '${name}' already exists in ${file}" >&2
    return 1
  fi

  printf "Description: " >&2
  read -r desc

  printf "Packages to include (comma-separated, empty = all): " >&2
  read -r include_csv

  {
    echo ""
    echo "[profiles.${name}]"
    echo "description = \"${desc}\""
    if [[ -z "${include_csv// }" ]]; then
      echo "include = []"
    else
      local -a items=() out=()
      IFS=',' read -ra items <<< "$include_csv"
      local it
      for it in "${items[@]}"; do
        it="$(echo "$it" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -n "$it" ]] && out+=("\"$it\"")
      done
      local joined="" sep=""
      for it in "${out[@]}"; do
        joined+="${sep}${it}"
        sep=", "
      done
      echo "include = [${joined}]"
    fi
  } >> "$file"

  echo "Profile '${name}' created in ${file}"
}

# profile_edit — open profiles.toml in $EDITOR (fallback: nano).
# Args:   $1 profile name (optional; validated if non-empty)
# Return: 1 if config or named profile is missing
profile_edit() {
  local name="$1"
  local file; file="$(_profile_config_file)"

  [[ -f "$file" ]] || { echo "Error: profile config not found: $file" >&2; return 1; }

  if [[ -n "$name" ]] && ! grep -q "^\[profiles\.${name}\]" "$file"; then
    echo "Error: profile '${name}' not found in ${file}" >&2
    return 1
  fi

  "${EDITOR:-nano}" "$file"
}

# profile_validate — check profiles.toml for duplicate sections and bad values.
# Stdout: nothing on success; errors on stderr
# Return: 1 if any error found
profile_validate() {
  local file; file="$(_profile_config_file)"
  [[ -f "$file" ]] || { echo "Error: profile config not found: $file" >&2; return 1; }

  local -a errors=()
  local -a seen=()
  local line name

  while IFS= read -r line; do
    name="$(echo "$line" | sed -E 's/^\[profiles\.(.*)\]$/\1/')"
    if (( ${#seen[@]} > 0 )) && _in_list "$name" "${seen[@]}"; then
      errors+=("duplicate profile section: [profiles.${name}]")
    fi
    seen+=("$name")
  done < <(grep -E '^\[profiles\.[^]]+\]' "$file")

  local n lvl
  for n in "${seen[@]:-}"; do
    [[ -z "$n" ]] && continue
    lvl="$(_profile_section "$n" "$file" | grep '^level' | sed -e 's/^[^=]*=[[:space:]]*//' -e 's/"//g')" || true
    if [[ -n "$lvl" ]]; then
      case "$lvl" in
        patch|minor|major) ;;
        *) errors+=("profile '${n}': invalid level '${lvl}' (expected patch|minor|major)") ;;
      esac
    fi
  done

  if (( ${#errors[@]} > 0 )); then
    printf 'Error: %s\n' "${errors[@]}" >&2
    return 1
  fi

  return 0
}
