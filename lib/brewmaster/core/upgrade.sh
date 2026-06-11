#!/usr/bin/env bash
# brewmaster core: upgrade execution and reporting.
# Sourced by bin/brewmaster; defines functions only.

# is_cask — check whether a package name is an installed cask.
# Args:    $1  package name
# Return:  0 if cask, 1 otherwise
# Globals: CASK_SET (space-padded list of cask names; built by run_upgrade)
is_cask() { [[ "$CASK_SET" == *" $1 "* ]]; }

# _in_list — return 0 if $1 equals any of the remaining arguments.
# Args: $1 needle; $2.. haystack items
_in_list() {
  local needle="$1"; shift
  local x
  for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
  return 1
}

# run_upgrade — main flow: read `brew outdated`, classify each package by semver
# bump, gate by level, then print the plan (DRY_RUN) or execute `brew upgrade`.
# Globals (read): LEVEL OR_LOWER ALLOW_DATE ONLY_FORMULAE ONLY_CASKS DRY_RUN VERBOSE
#                 INTERACTIVE PROFILE_NAME PROFILE_MAX_RISK PROFILE_REQUIRE_CONFIRM
# Uses:           parse_outdated_line, to_semver_3, bump_kind, allow_by_level, logv
# Return:         0 on success; 1 if any upgrade failed.
run_upgrade() {
  $CHECK_DEPS && depgraph_build
  CASK_SET=" $(brew list --cask 2>/dev/null | tr '\n' ' ') "

  local out; out="$(brew outdated --verbose 2>/dev/null || true)"
  local -a upgrade_list=() report_rows=() upgrade_meta=()
  local skipped_nonsemver=0
  local ln parsed name old_raw new_raw old_sv new_sv kind

  while IFS= read -r ln; do
    case "$ln" in
      *"("*")"*"<"*|*"("*")"*"!="* )
        if ! parsed="$(parse_outdated_line "$ln")"; then
          logv "Skip (unparseable): $ln"; continue
        fi
        IFS='|' read -r name old_raw new_raw <<<"$parsed"

        if ((${#PACKAGES[@]})) && ! _in_list "$name" "${PACKAGES[@]}"; then
          logv "Skip (not in package filter): $name"; continue
        fi

        if $ONLY_FORMULAE && is_cask "$name"; then
          logv "Skip cask (formulae only): $name"; continue
        elif $ONLY_CASKS && ! is_cask "$name"; then
          logv "Skip formula (casks only): $name"; continue
        fi

        if ! old_sv="$(to_semver_3 "$old_raw" "$ALLOW_DATE")"; then
          logv "Skip (old non-semver): $name $old_raw -> $new_raw"
          skipped_nonsemver=$((skipped_nonsemver+1)); continue
        fi
        if ! new_sv="$(to_semver_3 "$new_raw" "$ALLOW_DATE")"; then
          logv "Skip (new non-semver): $name $old_raw -> $new_raw"
          skipped_nonsemver=$((skipped_nonsemver+1)); continue
        fi

        kind="$(bump_kind "$old_sv" "$new_sv")"
        if allow_by_level "$kind" "$LEVEL" "$OR_LOWER"; then
          if [[ -n "${PROFILE_NAME:-}" ]]; then
            profile_filter_package "$name" || { logv "Skip (profile filter): $name"; continue; }
          fi
          if $CHECK_DEPS; then
            local score; score="$(depgraph_risk_score "$name" "$kind")"
            if (( score >= RISK_THRESHOLD )); then
              echo "Warning: skipping $name (risk ${score}/10 — HIGH)" >&2
              logv "Dependents: $(depgraph_is_safe "$name" || true)"
              continue
            elif [[ -n "${PROFILE_NAME:-}" ]] && (( PROFILE_MAX_RISK < 10 )) && (( score > PROFILE_MAX_RISK )); then
              echo "Warning: skipping $name (risk ${score}/10 > profile max ${PROFILE_MAX_RISK})" >&2
              continue
            elif (( score >= 4 )); then
              echo "Warning: $name risk ${score}/10 (MEDIUM)" >&2
              if ! $YES_FLAG; then
                printf "Upgrade %s anyway? [y/N] " "$name" >&2
                local ans; read -r ans </dev/tty
                [[ "$ans" =~ ^[Yy]$ ]] || continue
              fi
            fi
          fi
          if ${PROFILE_REQUIRE_CONFIRM:-false} && ! $YES_FLAG; then
            printf "Profile requires confirmation for %s. Upgrade? [y/N] " "$name" >&2
            local ans; read -r ans </dev/tty
            [[ "$ans" =~ ^[Yy]$ ]] || continue
          fi
          upgrade_list+=("$name")
          report_rows+=("$name  ${old_sv}  ->  ${new_sv}  [${kind}]")
          if $CHECK_DEPS; then
            upgrade_meta+=("${old_sv}|${new_sv}|${kind}|${score}")
          else
            upgrade_meta+=("${old_sv}|${new_sv}|${kind}|")
          fi
        else
          logv "Skip by level ($LEVEL, or-lower=$OR_LOWER): $name ${old_sv} -> ${new_sv} [${kind}]"
        fi
      ;;
      *) : ;;
    esac
  done <<<"$out"

  if (( skipped_nonsemver > 0 )); then
    echo "Note: ${skipped_nonsemver} package(s) skipped (non-semver version)." >&2
  fi

  if $INTERACTIVE && ((${#upgrade_list[@]} > 0)); then
    if ! command -v fzf >/dev/null 2>&1; then
      echo "Error: --interactive requires fzf. Install with: brew install fzf" >&2
      exit 1
    fi
    local -a fzf_display=()
    local i
    for i in "${!upgrade_list[@]}"; do
      fzf_display+=("${upgrade_list[$i]}"$'\t'"${report_rows[$i]}")
    done
    local selected
    selected="$(printf '%s\n' "${fzf_display[@]}" | \
      fzf --multi --ansi \
          --header='tab: toggle · ctrl-a: all · enter: upgrade' \
          --prompt='Select packages > ' | \
      cut -f1)"
    local -a new_list=() new_rows=() new_meta=()
    for i in "${!upgrade_list[@]}"; do
      echo "$selected" | grep -qFx "${upgrade_list[$i]}" || continue
      new_list+=("${upgrade_list[$i]}")
      new_rows+=("${report_rows[$i]}")
      new_meta+=("${upgrade_meta[$i]}")
    done
    upgrade_list=("${new_list[@]:-}")
    report_rows=("${new_rows[@]:-}")
    upgrade_meta=("${new_meta[@]:-}")
    if [[ "${upgrade_list[0]:-}" == "" ]]; then
      upgrade_list=()
      report_rows=()
      upgrade_meta=()
    fi
  fi

  if $DRY_RUN; then
    if ((${#upgrade_list[@]}==0)); then
      echo "No upgrade candidates (level=${LEVEL}, or-lower=${OR_LOWER})."
      return 0
    fi
    echo "Upgrade candidates (${#upgrade_list[@]}) [level=${LEVEL}, or-lower=${OR_LOWER}]:"
    printf '  - %s\n' "${report_rows[@]}"
    return 0
  fi

  if ((${#upgrade_list[@]}==0)); then
    echo "No packages to upgrade (level=${LEVEL}, or-lower=${OR_LOWER})."
    return 0
  fi

  echo "Upgrading ${#upgrade_list[@]} package(s) [level=${LEVEL}, or-lower=${OR_LOWER}]:"
  printf '  - %s\n' "${report_rows[@]}"

  local fail=0 i score extra
  for i in "${!upgrade_list[@]}"; do
    name="${upgrade_list[$i]}"
    IFS='|' read -r old_sv new_sv kind score <<<"${upgrade_meta[$i]}"
    echo "==> brew upgrade $name"
    if ! brew upgrade "$name"; then
      echo "Failed to upgrade: $name" >&2
      fail=$((fail+1))
      continue
    fi
    if [[ -n "$score" ]]; then
      extra="$(jq -nc --arg pkg "$name" --arg old "$old_sv" --arg new "$new_sv" \
        --arg bump "$kind" --arg profile "${PROFILE_NAME:-}" --argjson risk "$score" \
        '{package:$pkg, old:$old, new:$new, bump:$bump, risk:$risk, profile:$profile, dry_run:false}')"
    else
      extra="$(jq -nc --arg pkg "$name" --arg old "$old_sv" --arg new "$new_sv" \
        --arg bump "$kind" --arg profile "${PROFILE_NAME:-}" \
        '{package:$pkg, old:$old, new:$new, bump:$bump, profile:$profile, dry_run:false}')"
    fi
    audit_append "upgrade" "$extra"
  done

  if (( fail > 0 )); then
    echo "Done with ${fail} failure(s)." >&2
    return 1
  fi

  echo "Done."
  return 0
}
