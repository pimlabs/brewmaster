#!/usr/bin/env bash
# brewmaster: cleanup & intent — classify installed formulae as orphan/stale/pinned-old.
# Sourced by bin/brewmaster after depgraph.sh (uses depgraph_build/depgraph_is_safe)
# and snapshot.sh (uses snapshot_save/SNAP_DIR). Formulae only (casks out of scope).
# Globals read:  DRY_RUN INTERACTIVE CLEANUP_FORCE
# Globals set:   CLEANUP_CACHE (by _cleanup_build)

# Cache path — set by _cleanup_build; empty until then.
CLEANUP_CACHE=""

# _cleanup_build — fetch `brew info --json=v2 --installed` once into a cache file.
# Sets a combined EXIT trap covering both this cache and DEPGRAPH_CACHE (must be
# called after depgraph_build — all public functions here need depgraph too).
# Idempotent: a no-op if the cache is already built (avoids re-registering the
# EXIT trap when called from within a command-substitution subshell, e.g. via
# cleanup_scan inside `$(cleanup_scan)`, which would delete the cache file the
# moment that subshell exits — before the caller can read it).
# Return: 0
_cleanup_build() {
  [[ -n "$CLEANUP_CACHE" && -f "$CLEANUP_CACHE" ]] && return 0
  CLEANUP_CACHE="/tmp/brewmaster-cleanup-$$.json"
  brew info --json=v2 --installed 2>/dev/null > "$CLEANUP_CACHE" || true
  # shellcheck disable=SC2064 # expand now: locals are gone by EXIT
  trap "rm -f '${CLEANUP_CACHE}' '${DEPGRAPH_CACHE:-}'" EXIT
}

# _cleanup_formula_json "$pkg" — print this formula's object from the cache, or
# nothing if not present.
_cleanup_formula_json() {
  jq --arg n "$1" '.formulae[] | select(.name == $n)' "$CLEANUP_CACHE" 2>/dev/null
}

# _cleanup_last_access "$pkg"
# Heuristic: max atime (epoch) of this formula's bin/sbin files (BSD `stat -f %a`).
# Falls back to Cellar dir mtime if formula installs no bin/sbin files.
# stdout: epoch seconds (0 if nothing found)
_cleanup_last_access() {
  local pkg="$1" f max=0 t
  while IFS= read -r f; do
    [[ "$f" == */bin/* || "$f" == */sbin/* ]] || continue
    t="$(stat -f %a "$f" 2>/dev/null || echo 0)"
    (( t > max )) && max=$t
  done < <(brew list "$pkg" 2>/dev/null || true)
  if (( max == 0 )); then
    local cellar; cellar="$(brew --cellar "$pkg" 2>/dev/null || true)"
    [[ -n "$cellar" && -d "$cellar" ]] && max="$(stat -f %m "$cellar" 2>/dev/null || echo 0)"
  fi
  echo "$max"
}

# _cleanup_days_since "$epoch" -> integer days (0 if epoch empty/0)
_cleanup_days_since() {
  local epoch="${1:-0}" now
  [[ -z "$epoch" || "$epoch" == "0" ]] && { echo 0; return; }
  now="$(date +%s)"
  echo $(( (now - epoch) / 86400 ))
}

# _cleanup_facts "$pkg"
# Single per-package gather point — exactly ONE _cleanup_last_access (brew list +
# stat) and ONE depgraph_is_safe call. Both cleanup_score and cleanup_scan go
# through this, so a full scan never repeats the I/O-heavy atime lookup.
# stdout (TSV): vcount  pinned(true/false)  on_request(true/false)  is_safe(0/1)
#               install_epoch  last_access_epoch
_cleanup_facts() {
  local pkg="$1" json safe=1 last
  json="$(_cleanup_formula_json "$pkg")"
  depgraph_is_safe "$pkg" >/dev/null || safe=0
  last="$(_cleanup_last_access "$pkg")"
  if [[ -z "$json" ]]; then
    printf '0\tfalse\tfalse\t%s\t0\t%s\n' "$safe" "$last"
    return 0
  fi
  echo "$json" | jq -r --arg safe "$safe" --arg last "$last" \
    '[(.installed|length), (.pinned // false),
      (([.installed[].installed_on_request]|any)//false),
      $safe, (.installed[0].time // 0), $last] | @tsv'
}

# cleanup_score_from_facts vcount pinned on_request is_safe install_epoch last_access_epoch
# Pure scoring — no I/O. Shared by cleanup_score and cleanup_scan.
#   +4 zero dependents (is_safe==1)
#   +3 last_access > 90 days
#   +2 version_count > 1 (newer version also installed)
#   +1 install_epoch > 180 days ago
# stdout: integer 0-10 (capped at 10)
cleanup_score_from_facts() {
  local vcount="$1" pinned="$2" on_request="$3" safe="$4" install_epoch="$5" last_epoch="$6"
  local score=0
  (( safe == 1 )) && score=$((score+4))
  (( $(_cleanup_days_since "$last_epoch") > 90 )) && score=$((score+3))
  (( vcount > 1 )) && score=$((score+2))
  [[ "$install_epoch" != "0" ]] && (( $(_cleanup_days_since "$install_epoch") > 180 )) && score=$((score+1))
  (( score > 10 )) && score=10
  echo "$score"
}

# cleanup_score "$pkg" — public single-arg wrapper (ROADMAP contract).
# For standalone/single-package use (e.g. `why`, tests). Calls _cleanup_facts
# itself — fine because it's not used in the per-formula scan loop.
# Precondition: depgraph_build and _cleanup_build already called.
# stdout: integer 0-10
cleanup_score() {
  local f vcount pinned on_request safe install_epoch last_epoch
  f="$(_cleanup_facts "$1")"
  IFS=$'\t' read -r vcount pinned on_request safe install_epoch last_epoch <<<"$f"
  cleanup_score_from_facts "$vcount" "$pinned" "$on_request" "$safe" "$install_epoch" "$last_epoch"
}

# cleanup_scan
# Calls depgraph_build + _cleanup_build internally.
# stdout: "name|category|cleanup_score|reason" per installed formula that falls
#         into a category. Category priority: pinned-old > orphan > stale.
# Return: 0
cleanup_scan() {
  depgraph_build
  _cleanup_build
  local -a names=()
  while IFS= read -r name; do
    [[ -n "$name" ]] && names+=("$name")
  done < <(brew list --formula 2>/dev/null)
  local total=${#names[@]} i=0
  local name f vcount pinned on_request safe install_epoch last_epoch days score category reason
  for name in "${names[@]}"; do
    i=$((i+1))
    printf '\r\033[K[%d/%d] %s' "$i" "$total" "$name" >&2
    f="$(_cleanup_facts "$name")"
    IFS=$'\t' read -r vcount pinned on_request safe install_epoch last_epoch <<<"$f"
    score="$(cleanup_score_from_facts "$vcount" "$pinned" "$on_request" "$safe" "$install_epoch" "$last_epoch")"
    days="$(_cleanup_days_since "$last_epoch")"

    if [[ "$pinned" == "true" && "$vcount" -gt 1 ]]; then
      category="pinned-old"; reason="newer version also installed"
    elif (( safe == 1 )) && [[ "$on_request" == "true" ]]; then
      category="orphan"; reason="installed manually, 0 dependents"
    elif (( safe == 1 )) && (( days > 90 )); then
      category="stale"; reason="last used ~${days}d ago"
    else
      continue
    fi
    printf '%s|%s|%s|%s\n' "$name" "$category" "$score" "$reason"
  done
  (( total > 0 )) && printf '\r\033[K' >&2
}

# cleanup_execute "$pkg" — brew uninstall "$pkg"; respects $DRY_RUN.
# Return: 0 on success (or DRY_RUN); 1 if brew uninstall failed.
cleanup_execute() {
  local pkg="$1"
  if $DRY_RUN; then
    echo "Would run: brew uninstall $pkg"
    return 0
  fi
  brew uninstall "$pkg" >/dev/null 2>&1
}

# _cleanup_installed_date "$pkg" -> "YYYY-MM-DD" or "unknown"
_cleanup_installed_date() {
  local epoch
  epoch="$(_cleanup_formula_json "$1" | jq -r '.installed[0].time // 0')"
  [[ -z "$epoch" || "$epoch" == "0" ]] && { echo "unknown"; return; }
  date -r "$epoch" +%Y-%m-%d 2>/dev/null || echo "unknown"
}

# cleanup_report "$rows" — print CATEGORY | PACKAGE | INSTALLED | SCORE | REASON
# table from cleanup_scan output, sorted by score (descending).
cleanup_report() {
  local rows="$1"
  if [[ -z "$rows" ]]; then
    echo "Nothing to clean up."
    return 0
  fi
  printf '%-12s  %-24s  %-12s  %-5s  %s\n' "CATEGORY" "PACKAGE" "INSTALLED" "SCORE" "REASON"
  printf '%-12s  %-24s  %-12s  %-5s  %s\n' "--------" "-------" "---------" "-----" "------"
  local name category score reason installed
  while IFS='|' read -r name category score reason; do
    [[ -z "$name" ]] && continue
    installed="$(_cleanup_installed_date "$name")"
    printf '%-12s  %-24s  %-12s  %-5s  %s\n' "$category" "$name" "$installed" "$score" "$reason"
  done < <(printf '%s\n' "$rows" | sort -t'|' -k3 -rn)
}

# why "$pkg" — explain why a formula is on the machine.
# Precondition: depgraph_build and _cleanup_build already called.
# Return: 1 if package is not installed.
why() {
  local pkg="$1"
  if [[ -z "$pkg" ]]; then
    echo "Usage: brewmaster why <package>" >&2
    return 1
  fi

  local json; json="$(_cleanup_formula_json "$pkg")"
  if [[ -z "$json" ]]; then
    echo "Error: $pkg is not installed (or not a formula)." >&2
    return 1
  fi

  echo "Package: $pkg"

  local on_request epoch installed_str
  on_request="$(echo "$json" | jq -r '([.installed[].installed_on_request]|any)//false')"
  epoch="$(echo "$json" | jq -r '.installed[0].time // 0')"
  if [[ "$epoch" == "0" ]]; then
    installed_str="an unknown date"
  else
    installed_str="$(date -r "$epoch" +%Y-%m-%d 2>/dev/null || echo "an unknown date")"
  fi
  if [[ "$on_request" == "true" ]]; then
    echo "  Installed manually on ${installed_str}."
  else
    echo "  Installed as a dependency on ${installed_str} (not requested directly)."
  fi

  local arr count
  arr="$(_depgraph_query "$pkg" "")"
  count="$(echo "$arr" | jq 'length')"
  if (( count == 0 )); then
    echo "  Dependents: none — nothing currently depends on it."
  else
    echo "  Dependents (${count}):"
    echo "$arr" | jq -r '.[]' | while IFS= read -r dep; do
      printf '    - %s\n' "$dep"
    done
  fi

  local last days
  last="$(_cleanup_last_access "$pkg")"
  days="$(_cleanup_days_since "$last")"
  if [[ "$last" == "0" ]]; then
    echo "  Last access: unknown."
  elif (( days == 0 )); then
    echo "  Last access: today."
  else
    echo "  Last access: ~${days} day(s) ago."
  fi

  local vcount; vcount="$(echo "$json" | jq '.installed | length')"
  (( vcount > 1 )) && echo "  Versions installed: ${vcount} (older version(s) may be removable)."
}

# _cleanup_snapshot_if_needed — snapshot_save (labelled "pre-cleanup") unless a
# snapshot for today already exists. No-op under DRY_RUN.
_cleanup_snapshot_if_needed() {
  $DRY_RUN && return 0
  _snap_ensure_dir
  local today; today="$(date +%Y%m%d)"
  if ls "$SNAP_DIR/${today}"-*.txt >/dev/null 2>&1; then
    return 0
  fi
  snapshot_save "pre-cleanup" >/dev/null
}

# _cleanup_remove_list — uninstall each package on stdin (full
# "name|category|score|reason" rows). On real (non-DRY_RUN) success, appends
# a "cleanup" audit entry.
# Return: 0 if all succeeded; 1 if any failed.
_cleanup_remove_list() {
  local name category score reason fail=0
  while IFS='|' read -r name category score reason; do
    [[ -z "$name" ]] && continue
    echo "==> brew uninstall $name"
    if cleanup_execute "$name"; then
      $DRY_RUN || audit_append "cleanup" "$(jq -nc --arg pkg "$name" --arg cat "$category" \
        --argjson score "$score" '{package:$pkg, category:$cat, score:$score, dry_run:false}')"
    else
      echo "Failed to remove: $name" >&2
      fail=$((fail+1))
    fi
  done
  (( fail == 0 ))
}

# cleanup_main — entry point for `brewmaster cleanup`.
# DRY_RUN/INTERACTIVE/CLEANUP_FORCE control behavior; default (none set) is a
# read-only report (never auto-remove without --interactive or --force).
cleanup_main() {
  depgraph_build
  _cleanup_build
  local rows; rows="$(cleanup_scan)"
  if [[ -z "$rows" ]]; then
    echo "Nothing to clean up."
    return 0
  fi

  if $INTERACTIVE; then
    if ! command -v fzf >/dev/null 2>&1; then
      echo "Error: --interactive requires fzf. Install with: brew install fzf" >&2
      exit 1
    fi
    local tmpdir; tmpdir="$(mktemp -d)"
    # shellcheck disable=SC2064 # expand now: locals are gone by EXIT
    trap "rm -rf '$tmpdir'; rm -f '${CLEANUP_CACHE}' '${DEPGRAPH_CACHE:-}'" EXIT

    local total; total="$(printf '%s\n' "$rows" | grep -c .)"
    local i=0 name category score reason
    while IFS='|' read -r name category score reason; do
      [[ -z "$name" ]] && continue
      i=$((i+1))
      printf '\r\033[K[%d/%d] %s' "$i" "$total" "$name" >&2
      why "$name" > "$tmpdir/${name}.why" 2>/dev/null || true
    done <<<"$rows"
    printf '\r\033[K' >&2

    local selected
    selected="$(printf '%s\n' "$rows" | fzf --multi --ansi \
      --delimiter='|' --with-nth=2,1,3,4 \
      --preview="cat '$tmpdir/{1}.why'" \
      --header='tab: toggle . ctrl-a: all . enter: remove selected' \
      --prompt='Select packages to remove > ')"

    if [[ -z "$selected" ]]; then
      echo "Nothing selected."
      return 0
    fi

    _cleanup_snapshot_if_needed
    printf '%s\n' "$selected" | _cleanup_remove_list
    return $?
  fi

  if $CLEANUP_FORCE; then
    local to_remove
    to_remove="$(printf '%s\n' "$rows" | awk -F'|' '$2=="orphan" && $3+0>=7 {print}')"
    if [[ -z "$to_remove" ]]; then
      echo "No orphans with score >= 7."
      return 0
    fi
    _cleanup_snapshot_if_needed
    printf '%s\n' "$to_remove" | _cleanup_remove_list
    return $?
  fi

  cleanup_report "$rows"
  echo
  echo "Run with --interactive to select packages to remove, or --force to auto-remove orphans (score >= 7)."
}

# cleanup_bloat — print a machine package summary: totals, category counts, and
# an estimated disk reclaim (sum of Cellar sizes for flagged packages).
cleanup_bloat() {
  depgraph_build
  _cleanup_build
  local rows; rows="$(cleanup_scan)"

  local total_formulae total_casks total
  total_formulae="$(brew list --formula 2>/dev/null | grep -c . || true)"
  total_casks="$(brew list --cask 2>/dev/null | grep -c . || true)"
  total=$((total_formulae + total_casks))

  local orphans stale pinned
  orphans="$(printf '%s\n' "$rows" | awk -F'|' '$2=="orphan"' | grep -c . || true)"
  stale="$(printf '%s\n' "$rows" | awk -F'|' '$2=="stale"'  | grep -c . || true)"
  pinned="$(printf '%s\n' "$rows" | awk -F'|' '$2=="pinned-old"' | grep -c . || true)"

  local kb=0 total i=0 name category score reason cellar size
  total="$(printf '%s\n' "$rows" | grep -c .)"
  while IFS='|' read -r name category score reason; do
    [[ -z "$name" ]] && continue
    i=$((i+1))
    printf '\r\033[K[%d/%d] %s' "$i" "$total" "$name" >&2
    cellar="$(brew --cellar "$name" 2>/dev/null || true)"
    if [[ -n "$cellar" && -d "$cellar" ]]; then
      size="$(du -sk "$cellar" 2>/dev/null | awk '{print $1}')"
      kb=$((kb + size))
    fi
  done <<<"$rows"
  (( total > 0 )) && printf '\r\033[K' >&2
  local mb=$((kb / 1024))

  echo "Machine package report"
  printf '  Total installed:   %d\n' "$total"
  printf '  Orphans:           %3d   (could be removed)\n' "$orphans"
  printf '  Stale (>90d):      %3d   (last-access heuristic)\n' "$stale"
  printf '  Pinned old:        %3d\n' "$pinned"
  printf '  Est. disk reclaim: ~%d MB\n' "$mb"
  echo
  echo "Run: brewmaster cleanup --dry-run  to review candidates"
}
