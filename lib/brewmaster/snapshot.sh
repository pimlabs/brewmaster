#!/usr/bin/env bash
# brewmaster: snapshot & rollback — save/restore Homebrew package state.
# Sourced by bin/brewmaster; defines functions only (no top-level execution).
# Globals read: DRY_RUN, SNAP_FORCE, VERBOSE

# Storage root (XDG-compliant, overridable for tests).
SNAP_DIR="${BREWMASTER_SNAP_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/brewmaster/snapshots}"

# _snap_ensure_dir — create SNAP_DIR if it doesn't exist.
_snap_ensure_dir() {
  mkdir -p "$SNAP_DIR" || { echo "Error: cannot create $SNAP_DIR" >&2; return 1; }
}

# _snap_list_files — print absolute paths to all .txt snapshots, newest first.
# Stdout: one path per line
_snap_list_files() {
  ls -t "$SNAP_DIR"/*.txt 2>/dev/null || true
}

# _snap_resolve — resolve an index (1-based) or path to an absolute .txt path.
# Args:   $1  integer index or absolute/relative path
# Stdout: absolute path to .txt file
# Return: 1 if not found or invalid
_snap_resolve() {
  local ref="$1"
  if [[ -z "$ref" ]]; then
    echo "Error: snapshot reference required (index or path)." >&2
    return 1
  fi
  if [[ "$ref" =~ ^[0-9]+$ ]]; then
    local path
    path="$(_snap_list_files | sed -n "${ref}p")"
    if [[ -z "$path" ]]; then
      echo "Error: snapshot index $ref not found." >&2
      return 1
    fi
    echo "$path"
  else
    if [[ ! -f "$ref" ]]; then
      echo "Error: snapshot file not found: $ref" >&2
      return 1
    fi
    echo "$ref"
  fi
}

# snapshot_save — capture current brew package state to a snapshot file.
# Args:    $1  optional label (alphanumeric, dashes, underscores)
# Stdout:  path of saved .txt file
# Return:  0 on success
snapshot_save() {
  local label="${1:-}"
  _snap_ensure_dir || return 1

  local ts; ts="$(date +%Y%m%d-%H%M%S)"
  local base="$ts"
  if [[ -n "$label" ]]; then
    # sanitize: keep alphanum + dash + underscore
    label="${label//[^A-Za-z0-9_-]/-}"
    base="${ts}-${label}"
  fi

  local txt="$SNAP_DIR/${base}.txt"
  local meta="$SNAP_DIR/${base}.meta.json"

  brew list --versions 2>/dev/null | awk '{print $1"\t"$NF}' > "$txt"

  local count; count="$(wc -l < "$txt" | tr -d ' ')"
  local brew_ver; brew_ver="$(brew --version 2>/dev/null | head -1 | awk '{print $2}')"

  jq -n \
    --arg label "${label}" \
    --arg brew_version "${brew_ver}" \
    --argjson package_count "${count}" \
    '{ label: $label, brew_version: $brew_version, package_count: $package_count }' \
    > "$meta"

  audit_append "snapshot" "$(jq -nc --arg path "$txt" --arg label "${label}" '{path:$path, label:$label}')"

  echo "$txt"
}

# snapshot_list — print a table of all saved snapshots, newest first.
# Stdout: formatted table: INDEX | TIMESTAMP | LABEL | PACKAGES
snapshot_list() {
  local files=() line
  while IFS= read -r line; do
    [[ -n "$line" ]] && files+=("$line")
  done < <(_snap_list_files)

  if (( ${#files[@]} == 0 )); then
    echo "No snapshots found in $SNAP_DIR"
    return 0
  fi

  printf '%-6s  %-17s  %-24s  %s\n' "INDEX" "TIMESTAMP" "LABEL" "PACKAGES"
  printf '%-6s  %-17s  %-24s  %s\n' "-----" "---------" "-----" "--------"

  local i=1 f base meta label count ts
  for f in "${files[@]}"; do
    base="$(basename "$f" .txt)"
    meta="${f%.txt}.meta.json"
    label=""
    count="?"
    ts="${base:0:15}"
    # reformat timestamp: YYYYMMDD-HHMMSS → YYYY-MM-DD HH:MM:SS
    ts="${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:9:2}:${ts:11:2}:${ts:13:2}"
    if [[ -f "$meta" ]]; then
      label="$(jq -r '.label // ""' "$meta" 2>/dev/null)"
      count="$(jq -r '.package_count // "?"' "$meta" 2>/dev/null)"
    fi
    printf '%-6s  %-17s  %-24s  %s\n' "$i" "$ts" "${label:-(none)}" "$count"
    i=$((i+1))
  done
}

# snapshot_diff — show packages that changed since a snapshot.
# Args:    $1  index or path
# Stdout:  table: pkg  snap_ver  ->  current_ver  [UPGRADE|DOWNGRADE|NEW|REMOVED]
# Return:  0 always (even with no diff)
snapshot_diff() {
  local ref="${1:-}"
  local snap_path
  snap_path="$(_snap_resolve "$ref")" || return 1

  # Build current state: name -> version
  local tmp_cur; tmp_cur="$(mktemp)"
  brew list --versions 2>/dev/null | awk '{print $1"\t"$NF}' > "$tmp_cur"

  local found=false
  local pkg snap_ver cur_ver tag

  # Check packages in snapshot against current
  while IFS=$'\t' read -r pkg snap_ver; do
    cur_ver="$(grep -m1 "^${pkg}	" "$tmp_cur" 2>/dev/null | cut -f2 || true)"
    if [[ -z "$cur_ver" ]]; then
      printf '%-30s  %-14s  ->  %-14s  [%s]\n' "$pkg" "$snap_ver" "(missing)" "REMOVED"
      found=true
    elif [[ "$cur_ver" != "$snap_ver" ]]; then
      # Compare using to_semver_3 if available, else lexicographic
      if declare -f to_semver_3 &>/dev/null; then
        local sv_snap sv_cur
        sv_snap="$(to_semver_3 "$snap_ver" false 2>/dev/null)" || sv_snap="$snap_ver"
        sv_cur="$(to_semver_3 "$cur_ver" false 2>/dev/null)"  || sv_cur="$cur_ver"
        local kind; kind="$(bump_kind "$sv_snap" "$sv_cur" 2>/dev/null)" || kind=""
        case "$kind" in
          major|minor|patch) tag="UPGRADE" ;;
          downgrade) tag="DOWNGRADE" ;;
          *) tag="CHANGED" ;;
        esac
      else
        tag="CHANGED"
      fi
      printf '%-30s  %-14s  ->  %-14s  [%s]\n' "$pkg" "$snap_ver" "$cur_ver" "$tag"
      found=true
    fi
  done < "$snap_path"

  # Check packages added since snapshot (NEW)
  while IFS=$'\t' read -r pkg cur_ver; do
    if ! grep -q "^${pkg}	" "$snap_path" 2>/dev/null; then
      printf '%-30s  %-14s  ->  %-14s  [%s]\n' "$pkg" "(none)" "$cur_ver" "NEW"
      found=true
    fi
  done < "$tmp_cur"

  rm -f "$tmp_cur"
  $found || echo "No changes since snapshot."
}

# snapshot_restore — reinstall packages from a snapshot.
# Args:    $1  index or path
# Globals: DRY_RUN (true → print plan only)
# Return:  0 success; 1 if one or more brew installs failed
snapshot_restore() {
  local ref="${1:-}"
  local snap_path
  snap_path="$(_snap_resolve "$ref")" || return 1

  # Build current state
  local tmp_cur; tmp_cur="$(mktemp)"
  brew list --versions 2>/dev/null | awk '{print $1"\t"$NF}' > "$tmp_cur"

  local -a to_install=()
  local pkg snap_ver cur_ver

  while IFS=$'\t' read -r pkg snap_ver; do
    cur_ver="$(grep -m1 "^${pkg}	" "$tmp_cur" 2>/dev/null | cut -f2 || true)"
    if [[ -z "$cur_ver" ]]; then
      to_install+=("${pkg}@${snap_ver}:missing")
    elif [[ "$cur_ver" != "$snap_ver" ]]; then
      to_install+=("${pkg}@${snap_ver}:changed")
    fi
  done < "$snap_path"

  rm -f "$tmp_cur"

  if (( ${#to_install[@]} == 0 )); then
    echo "Already matches snapshot. Nothing to restore."
    return 0
  fi

  echo "Restore plan (${#to_install[@]} package(s)):"
  local entry pkg_ver reason
  for entry in "${to_install[@]}"; do
    pkg_ver="${entry%%:*}"
    reason="${entry##*:}"
    printf '  - %s  [%s]\n' "$pkg_ver" "$reason"
  done

  $DRY_RUN && return 0

  local fail=0
  for entry in "${to_install[@]}"; do
    pkg_ver="${entry%%:*}"
    echo "==> brew install $pkg_ver"
    if ! brew install "$pkg_ver" 2>&1; then
      echo "Warning: failed to install $pkg_ver" >&2
      fail=$((fail+1))
    fi
  done

  if (( fail > 0 )); then
    echo "Restore done with ${fail} failure(s)." >&2
    return 1
  fi
  echo "Restore done."
}

# snapshot_delete — remove a snapshot (.txt + .meta.json).
# Args:    $1  index or path
# Globals: SNAP_FORCE (true → skip confirmation)
# Return:  0 on success
snapshot_delete() {
  local ref="${1:-}"
  local snap_path
  snap_path="$(_snap_resolve "$ref")" || return 1
  local meta="${snap_path%.txt}.meta.json"

  if ! $SNAP_FORCE; then
    printf "Delete snapshot '%s'? [y/N] " "$(basename "$snap_path")"
    local ans; read -r ans
    [[ "$ans" =~ ^[Yy]$ ]] || { echo "Cancelled."; return 0; }
  fi

  rm -f "$snap_path" "$meta"
  echo "Deleted: $(basename "$snap_path")"
}
