#!/usr/bin/env bash
# brewmaster core: shared color/table/progress/section output helpers.
# Sourced by bin/brewmaster; defines functions only.
# Extends bin/brewmaster's existing --help NO_COLOR/non-TTY/no-tput
# detection pattern to real ANSI colors for the rest of the CLI's output.

# ui_color_init — set COLOR_OK, COLOR_WARN, COLOR_HIGH, COLOR_MUTED,
# COLOR_HEADER, COLOR_COMMAND, COLOR_RESET to tput-derived ANSI sequences,
# or all-empty when styling should be suppressed (non-TTY, NO_COLOR set,
# or no tput available).
# COLOR_OK/WARN/HIGH are semantic — callers map their own numeric
# thresholds to these; ui.sh has no opinion on what "high" means for a
# given score. COLOR_HEADER/COLOR_COMMAND are decorative (no score/status
# meaning) and use color codes distinct from OK/WARN/HIGH on purpose, so
# help-text styling never visually collides with risk/cleanup coloring.
# Args:   none
# Stdout: none (sets globals COLOR_OK COLOR_WARN COLOR_HIGH COLOR_MUTED
#         COLOR_HEADER COLOR_COMMAND COLOR_RESET)
# Return: 0
ui_color_init() {
  COLOR_OK="" COLOR_WARN="" COLOR_HIGH="" COLOR_MUTED="" \
    COLOR_HEADER="" COLOR_COMMAND="" COLOR_RESET=""
  [ -t 1 ] || return 0
  [ -n "${NO_COLOR:-}" ] && return 0
  command -v tput >/dev/null 2>&1 || return 0
  COLOR_OK="$(tput setaf 2 2>/dev/null || true)"
  COLOR_WARN="$(tput setaf 3 2>/dev/null || true)"
  COLOR_HIGH="$(tput setaf 1 2>/dev/null || true)"
  COLOR_MUTED="$(tput dim 2>/dev/null || true)"
  COLOR_HEADER="$(tput setaf 6 2>/dev/null || true)"
  COLOR_COMMAND="$(tput setaf 4 2>/dev/null || true)"
  COLOR_RESET="$(tput sgr0 2>/dev/null || true)"
}

# ui_colorize "$width" "$color" "$value"
# Pad $value to $width *before* wrapping it in color — printf's %-Ns
# padding counts raw bytes, so padding after adding ANSI escape codes
# would misalign the column by the invisible escape sequence's length.
# Pass the result to ui_table_row/ui_table_header with an empty width
# ("") since it is already padded.
# Args:   $1 width (integer, or "" for no padding), $2 color code, $3 value
# Stdout: padded, colored value (colorless passthrough if $2 is empty)
# Return: 0
ui_colorize() {
  local w="$1" color="$2" val="$3" padded
  if [[ -n "$w" ]]; then padded="$(printf -- "%-${w}s" "$val")"; else padded="$val"; fi
  [[ -z "$color" ]] && { printf '%s' "$padded"; return 0; }
  printf '%s%s%s' "$color" "$padded" "${COLOR_RESET}"
}

# ui_table_header "$w1" "$label1" ["$w2" "$label2" ...]
# Print an aligned header row followed by a dashed rule row. Column
# widths are per-call, not fixed — each table already has its own shape;
# this shares the render mechanism, not a schema. A width of "" means
# "trailing unpadded column" (plain %s) — matches how every existing
# table already leaves its last column unpadded. Rule dashes are always
# sized to each label's own length (the convention already used by every
# existing table but audit.sh's, which sized them to column width
# instead — unified here since nothing asserts on that exact length).
# Args:   width/value pairs (width first: a plain integer, or "")
# Stdout: header row, then a rule row
# Return: 0
ui_table_header() {
  local fmt="" rule_fmt=""
  local -a vals=() rule_vals=()
  while (( $# >= 2 )); do
    local w="$1" label="$2"; shift 2
    if [[ -n "$w" ]]; then fmt+="%-${w}s"; rule_fmt+="%-${w}s"
    else fmt+="%s"; rule_fmt+="%s"
    fi
    vals+=("$label")
    rule_vals+=("$(printf -- '-%.0s' $(seq 1 "${#label}"))")
    (( $# > 0 )) && { fmt+="  "; rule_fmt+="  "; }
  done
  fmt+="\n"; rule_fmt+="\n"
  # shellcheck disable=SC2059 # fmt is built from trusted literal pieces above
  printf -- "$fmt" "${vals[@]}"
  # shellcheck disable=SC2059
  printf -- "$rule_fmt" "${rule_vals[@]}"
}

# ui_table_row "$w1" "$val1" ["$w2" "$val2" ...]
# Print one aligned row matching ui_table_header's column widths. A width
# of "" means a trailing unpadded column (plain %s), same as
# ui_table_header.
# Args:   width/value pairs (same shape as ui_table_header)
# Stdout: one aligned row
# Return: 0
ui_table_row() {
  local fmt=""
  local -a vals=()
  while (( $# >= 2 )); do
    local w="$1" val="$2"; shift 2
    if [[ -n "$w" ]]; then fmt+="%-${w}s"; else fmt+="%s"; fi
    vals+=("$val")
    (( $# > 0 )) && fmt+="  "
  done
  fmt+="\n"
  # shellcheck disable=SC2059
  printf -- "$fmt" "${vals[@]}"
}

# ui_progress "$current" "$total" "$label"
# Print an in-place "[current/total] label" line: carriage return, clear
# to end of line, no trailing newline. Matches the pattern already used
# by cleanup_scan/cleanup_bloat/run_upgrade before this was extracted.
# Args:    $1 current index, $2 total count, $3 label text
# Stderr:  "\r\033[K[current/total] label" (stderr, matching prior use —
#          keeps progress out of piped/captured stdout)
# Return:  0
ui_progress() {
  printf '\r\033[K[%d/%d] %s' "$1" "$2" "$3" >&2
}

# ui_progress_clear — clear the current in-place progress line.
# Args:    none
# Stderr:  "\r\033[K"
# Return:  0
ui_progress_clear() {
  printf '\r\033[K' >&2
}

# ui_section "$title"
# Print a title followed by a rule of matching length, generalizing
# audit_report's existing title-width rule for reuse elsewhere.
# Args:   $1 section title
# Stdout: title line, then a rule line of the same character count
# Return: 0
ui_section() {
  local title="$1"
  echo "$title"
  printf -- '─%.0s' $(seq 1 "${#title}"); echo
}

# ui_summary "$msg"
# Print a consistent end-of-command summary line.
# Args:   $1 summary text
# Stdout: "$msg"
# Return: 0
ui_summary() {
  echo "$1"
}

# _ui_fzf_supports_start — probe once whether the running fzf accepts the
# `start:` bind event (what preselect-all needs), caching the answer in
# _UI_FZF_START so the probe costs one short-lived fzf per process. The
# probe feeds fzf empty input under --filter: exit 1 is fzf's "no match"
# and means the bind was accepted; exit 2 (option parse error) is the
# only result that means "unsupported".
# Args:   none
# Stdout: none (sets global _UI_FZF_START: 0 supported, 1 unsupported)
# Return: 0 if supported, 1 otherwise
_ui_fzf_supports_start() {
  if [[ -n "${_UI_FZF_START:-}" ]]; then return "$_UI_FZF_START"; fi
  local rc=0
  printf '' | fzf --bind 'start:select-all' --filter='' >/dev/null 2>&1 || rc=$?
  if (( rc == 2 )); then _UI_FZF_START=1; else _UI_FZF_START=0; fi
  return "$_UI_FZF_START"
}

# ui_select "$preselect" "$prompt" [extra fzf args...]
# The one fzf multi-select in the CLI. Reads candidate lines on stdin and
# prints the confirmed selection on stdout, one line each. Every option
# the call sites share lives here, and the key header is generated from
# the same table as the --bind string, so a key can only be advertised
# if it is actually bound.
# Args:   $1 preselect: "all" (every row starts selected; the user
#            deselects — opt-out) or "none" (nothing selected — opt-in)
#         $2 prompt text
#         $3.. extra fzf args passed through verbatim (--delimiter,
#            --with-nth, --preview, ...)
# Stdout: selected lines (empty when nothing was confirmed)
# Return: 1 if fzf is not installed (no exit — the caller owns its
#         fallback); otherwise fzf's own status (0 confirmed, 1 nothing
#         selected, 130 aborted with Esc/ctrl-c)
ui_select() {
  local preselect="$1" prompt="$2"; shift 2
  command -v fzf >/dev/null 2>&1 || return 1
  # key|action|label — one table drives both --bind and --header.
  local -a keys=(
    "tab|toggle+down|toggle"
    "ctrl-a|select-all|all"
    "ctrl-d|deselect-all|none"
    "enter|accept|confirm"
  )
  local entry key action label binds="" header=""
  for entry in "${keys[@]}"; do
    IFS='|' read -r key action label <<<"$entry"
    binds+="${binds:+,}${key}:${action}"
    header+="${header:+ · }${key}: ${label}"
  done
  # start: is an event, not a key — it never appears in the header.
  if [[ "$preselect" == "all" ]] && _ui_fzf_supports_start; then
    binds="start:select-all,${binds}"
  fi
  fzf --multi --ansi --height=60% --layout=reverse --border \
      --pointer='>' --marker='x' \
      --bind="$binds" --header="$header" --prompt="$prompt" "$@"
}
