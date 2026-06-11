#!/usr/bin/env bash
# brewmaster: audit log — append-only NDJSON record of upgrades, cleanups, snapshots.
# Sourced by bin/brewmaster; defines functions only.
# Globals read:  BREWMASTER_AUDIT_LOG, XDG_DATA_HOME,
#                AUDIT_PACKAGE, AUDIT_ACTION, AUDIT_SINCE, AUDIT_FORMAT (audit_query)

# Storage path — single NDJSON file, XDG-compliant, overridable for tests.
AUDIT_LOG="${BREWMASTER_AUDIT_LOG:-${XDG_DATA_HOME:-$HOME/.local/share}/brewmaster/audit.log}"

# _audit_ensure_dir — create the audit log's parent directory if missing.
# Return: 1 if the directory cannot be created.
_audit_ensure_dir() {
  mkdir -p "$(dirname "$AUDIT_LOG")" || { echo "Error: cannot create $(dirname "$AUDIT_LOG")" >&2; return 1; }
}

# audit_append "$action" "$extra_json"
# Append one NDJSON line to AUDIT_LOG: {"ts":..., "action":..., ...extra_json}.
# Args:    $1  action ("upgrade"|"cleanup"|"snapshot")
#          $2  optional extra JSON object (string, default "{}"), built by the
#              caller via `jq -nc`, merged into the entry.
# Return:  1 if the log directory cannot be created or jq fails.
audit_append() {
  local action="$1" extra="${2:-}"
  [[ -z "$extra" ]] && extra='{}'
  _audit_ensure_dir || return 1
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -nc --arg ts "$ts" --arg action "$action" --argjson extra "$extra" \
    '{ts:$ts, action:$action} + $extra' >> "$AUDIT_LOG" || return 1
}

# _audit_since_epoch "$spec" -> epoch seconds (now minus the given duration)
# Args:    $1  duration spec: "Nd", "Nh", "Nw", or bare "N" (defaults to days)
# Stdout:  epoch seconds
# Return:  1 if $spec doesn't match the expected format
_audit_since_epoch() {
  local spec="$1" num unit
  if [[ "$spec" =~ ^([0-9]+)([dhw]?)$ ]]; then
    num="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]:-d}"
  else
    echo "Error: invalid --since value '$spec' (expected Nd, Nh, or Nw)." >&2
    return 1
  fi
  case "$unit" in
    h) date -u -v-"${num}H" +%s ;;
    d) date -u -v-"${num}d" +%s ;;
    w) date -u -v-"${num}w" +%s ;;
  esac
}

# _audit_render "table|csv" "$ndjson"
# Render filtered NDJSON entries as a 4-column table or CSV:
# TIMESTAMP | ACTION | PACKAGE | DETAIL (action-specific summary).
_audit_render() {
  local fmt="$1" filtered="$2"
  local jq_prog='
    .ts as $ts | .action as $action | (.package // "-") as $pkg
    | (
        if   $action == "upgrade"  then "\(.old) -> \(.new) [\(.bump)]"
        elif $action == "cleanup"  then "\(.category) score=\(.score)"
        elif $action == "snapshot" then (.path | split("/") | last)
                                          + (if .label != "" then " (" + .label + ")" else "" end)
        else "" end
      ) as $detail
    | [$ts, $action, $pkg, $detail]'

  if [[ "$fmt" == "csv" ]]; then
    printf '%s\n' "$filtered" | jq -r "$jq_prog | @csv"
    return 0
  fi

  printf '%-20s  %-10s  %-16s  %s\n' "TIMESTAMP" "ACTION" "PACKAGE" "DETAIL"
  printf '%-20s  %-10s  %-16s  %s\n' "--------------------" "----------" "----------------" "------"
  printf '%s\n' "$filtered" | jq -r "$jq_prog | @tsv" | \
    while IFS=$'\t' read -r ts action pkg detail; do
      printf '%-20s  %-10s  %-16s  %s\n' "$ts" "$action" "$pkg" "$detail"
    done
}

# audit_query — filter and print audit log entries.
# Globals read: AUDIT_PACKAGE AUDIT_ACTION AUDIT_SINCE AUDIT_FORMAT
# Default (no filters): last 20 entries, table format. With any filter set,
# all matches are shown (no 20-entry cap).
# Return: 1 if --since has an invalid format.
audit_query() {
  [[ -f "$AUDIT_LOG" ]] || { echo "No audit log found at $AUDIT_LOG"; return 0; }

  local jq_filter='true'
  [[ -n "${AUDIT_PACKAGE:-}" ]] && jq_filter+=" and (.package == \$pkg)"
  [[ -n "${AUDIT_ACTION:-}"  ]] && jq_filter+=" and (.action == \$act)"
  local since_epoch=0
  if [[ -n "${AUDIT_SINCE:-}" ]]; then
    since_epoch="$(_audit_since_epoch "$AUDIT_SINCE")" || return 1
    jq_filter+=" and ((.ts | fromdateiso8601) >= \$since)"
  fi

  local filtered
  filtered="$(jq -c \
    --arg pkg "${AUDIT_PACKAGE:-}" --arg act "${AUDIT_ACTION:-}" --argjson since "$since_epoch" \
    "select($jq_filter)" "$AUDIT_LOG")"

  local has_filter=false
  [[ -n "${AUDIT_PACKAGE:-}${AUDIT_ACTION:-}${AUDIT_SINCE:-}" ]] && has_filter=true
  ! $has_filter && filtered="$(printf '%s\n' "$filtered" | tail -n 20)"

  if [[ -z "$filtered" ]]; then
    echo "No matching audit entries."
    return 0
  fi

  case "${AUDIT_FORMAT:-table}" in
    json)    printf '%s\n' "$filtered" ;;
    csv)     _audit_render csv   "$filtered" ;;
    table|*) _audit_render table "$filtered" ;;
  esac
}

# audit_report — print a machine health summary.
# Calls depgraph_build/_cleanup_build in the main shell before cleanup_scan
# (cache/EXIT-trap convention shared with cleanup_main/cleanup_bloat).
audit_report() {
  local header; header="brewmaster machine report  (as of $(date +%Y-%m-%d))"
  echo "$header"
  printf '─%.0s' $(seq 1 ${#header}); echo

  local up_total=0 up_patch=0 up_minor=0 up_major=0 cleanup_count=0 avg_risk="n/a"
  if [[ -f "$AUDIT_LOG" ]]; then
    local since30 since90
    since30="$(_audit_since_epoch "30d")"
    since90="$(_audit_since_epoch "90d")"

    local up_counts
    up_counts="$(jq -s --argjson since "$since30" '
      [ .[] | select(.action=="upgrade" and (.ts|fromdateiso8601) >= $since) ]
      | { total: length,
          patch: ([.[] | select(.bump=="patch")] | length),
          minor: ([.[] | select(.bump=="minor")] | length),
          major: ([.[] | select(.bump=="major")] | length) }
    ' "$AUDIT_LOG")"
    up_total="$(jq -r '.total' <<<"$up_counts")"
    up_patch="$(jq -r '.patch' <<<"$up_counts")"
    up_minor="$(jq -r '.minor' <<<"$up_counts")"
    up_major="$(jq -r '.major' <<<"$up_counts")"

    cleanup_count="$(jq -s --argjson since "$since90" '
      [ .[] | select(.action=="cleanup" and (.ts|fromdateiso8601) >= $since) ] | length
    ' "$AUDIT_LOG")"

    local avg_risk_raw
    avg_risk_raw="$(jq -s -r '
      [ .[] | select(.action=="upgrade" and has("risk")) ] | .[-10:] |
      if length == 0 then "n/a" else (([.[] | .risk] | add) / length | tostring) end
    ' "$AUDIT_LOG")"
    if [[ "$avg_risk_raw" != "n/a" ]]; then
      avg_risk="$(printf '%.1f' "$avg_risk_raw")"
    fi
  fi

  local snap_files=() snap_count=0 snap_oldest="" snap_latest=""
  mapfile -t snap_files < <(_snap_list_files)
  snap_count="${#snap_files[@]}"
  if (( snap_count > 0 )); then
    local latest_base oldest_base
    latest_base="$(basename "${snap_files[0]}")"
    oldest_base="$(basename "${snap_files[$((snap_count-1))]}")"
    snap_latest="${latest_base:0:4}-${latest_base:4:2}-${latest_base:6:2}"
    snap_oldest="${oldest_base:0:4}-${oldest_base:4:2}-${oldest_base:6:2}"
  fi

  depgraph_build
  _cleanup_build
  local rows orphan_count
  rows="$(cleanup_scan)"
  orphan_count="$(printf '%s\n' "$rows" | awk -F'|' '$2=="orphan"' | grep -c . || true)"

  printf 'Upgrades (30d):   %3d  (patch: %d  minor: %d  major: %d)\n' \
    "$up_total" "$up_patch" "$up_minor" "$up_major"
  printf 'Cleanups (90d):   %3d  packages removed\n' "$cleanup_count"
  if (( snap_count > 0 )); then
    printf 'Snapshots:        %3d  (oldest: %s, latest: %s)\n' "$snap_count" "$snap_oldest" "$snap_latest"
  else
    printf 'Snapshots:        %3d  (none)\n' "$snap_count"
  fi
  printf 'Orphans now:      %3d  → run: brewmaster cleanup --dry-run\n' "$orphan_count"
  printf 'Avg risk score:   %s  (last 10 upgrades)\n' "$avg_risk"
}
