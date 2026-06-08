#!/usr/bin/env bash
# brewmaster core: upgrade execution and reporting.
# Sourced by bin/brewmaster; defines functions only.

# is_cask — check whether a package name is an installed cask.
# Args:    $1  package name
# Return:  0 if cask, 1 otherwise
# Globals: CASK_SET (space-padded list of cask names; built by run_upgrade)
is_cask() { [[ "$CASK_SET" == *" $1 "* ]]; }

# run_upgrade — main flow: read `brew outdated`, classify each package by semver
# bump, gate by level, then print the plan (DRY_RUN) or execute `brew upgrade`.
# Globals (read): LEVEL OR_LOWER ALLOW_DATE ONLY_FORMULAE ONLY_CASKS DRY_RUN VERBOSE
# Uses:           parse_outdated_line, to_semver_3, bump_kind, allow_by_level, logv
# Return:         0 on success; 1 if any upgrade failed.
run_upgrade() {
  CASK_SET=" $(brew list --cask 2>/dev/null | tr '\n' ' ') "

  local out; out="$(brew outdated --verbose 2>/dev/null || true)"
  local -a upgrade_list=() report_rows=()
  local skipped_nonsemver=0
  local ln parsed name old_raw new_raw old_sv new_sv kind

  while IFS= read -r ln; do
    case "$ln" in
      *"("*")"*"<"*|*"("*")"*"!="* )
        if ! parsed="$(parse_outdated_line "$ln")"; then
          logv "Skip (unparseable): $ln"; continue
        fi
        IFS='|' read -r name old_raw new_raw <<<"$parsed"

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
          upgrade_list+=("$name")
          report_rows+=("$name  ${old_sv}  ->  ${new_sv}  [${kind}]")
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

  local fail=0
  for name in "${upgrade_list[@]}"; do
    echo "==> brew upgrade $name"
    if ! brew upgrade "$name"; then
      echo "Failed to upgrade: $name" >&2
      fail=$((fail+1))
    fi
  done

  if (( fail > 0 )); then
    echo "Done with ${fail} failure(s)." >&2
    return 1
  fi

  echo "Done."
  return 0
}
