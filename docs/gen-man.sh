#!/usr/bin/env bash
# docs/gen-man.sh — generate the troff source for docs/brewmaster.1 from
# the shared help reference text in lib/brewmaster/core/help_data.sh.
# Standalone: sources ONLY help_data.sh (not bin/brewmaster), so it needs
# no mock brew/jq environment and cannot execute any CLI dispatch logic.
# Walks the same line grammar bin/brewmaster's usage() styling loop
# recognizes (caps-only section headers, indented "name  description"
# definition lines, "label:" lines, plain continuation text) and emits
# troff instead of ANSI styling.
#
# Usage: docs/gen-man.sh > docs/brewmaster.1
# Args:   none
# Stdout: troff man page source (NAME, SYNOPSIS, DESCRIPTION, COMMANDS,
#         FILES, EXAMPLES sections)
# Return: 0, or 1 if help_data.sh cannot be found
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELP_DATA="$SCRIPT_DIR/../lib/brewmaster/core/help_data.sh"
BM_SCRIPT="$SCRIPT_DIR/../bin/brewmaster"

if [ ! -f "$HELP_DATA" ]; then
  echo "gen-man.sh: cannot find $HELP_DATA" >&2
  exit 1
fi
# shellcheck source=../lib/brewmaster/core/help_data.sh
source "$HELP_DATA"

# Version/build date are read by grep (not by sourcing bin/brewmaster,
# which would require the mock brew/jq environment this script must not
# need) so the man page's .TH line stays in step with `brewmaster --version`.
MAN_VERSION="$(grep -m1 '^BREWMASTER_VERSION=' "$BM_SCRIPT" 2>/dev/null | cut -d'"' -f2)"
MAN_VERSION="${MAN_VERSION:-0.0.0}"
MAN_DATE="$(grep -m1 '^BUILD_DATE=' "$BM_SCRIPT" 2>/dev/null | cut -d'"' -f2)"
MAN_DATE="${MAN_DATE:-$(date +%Y-%m-%d)}"

# _man_escape — escape troff-significant characters in plain text so the
# result is safe to place inside a .SH/.TP/.B body without being read as
# a macro request.
# Args:   $1 raw text
# Stdout: escaped text
# Return: 0
_man_escape() {
  local s="$1"
  s="${s//\\/\\e}"
  printf '%s' "$s"
}

# _man_inline — escape then italicize <...>/[...] placeholder spans within
# a line of help text (mirrors _help_style_name's placeholder handling in
# bin/brewmaster, troff form instead of ANSI).
# Args:   $1 raw text
# Stdout: escaped text with \fI...\fR spans around placeholders
# Return: 0
_man_inline() {
  local s
  s="$(_man_escape "$1")"
  printf '%s' "$s" | sed -E 's/<([^>]+)>/\\fI\1\\fR/g; s/\[([^]]+)\]/\\fI[\1]\\fR/g'
}

# _man_safe_line — print one line of body text, guarding against troff
# reading a leading '.' or '\'' as a macro request.
# Args:   $1 text (already escaped/inlined)
# Stdout: the text, prefixed with \& if it would otherwise start a macro
# Return: 0
_man_safe_line() {
  local s="$1"
  case "$s" in
    .*|\'*) printf '\\&%s\n' "$s" ;;
    *)      printf '%s\n' "$s" ;;
  esac
}

# --- Load the shared source text once, as an array of raw lines ---
# (avoid mapfile/readarray: bash4+ only, and macOS ships bash 3.2 as
# /bin/bash — this must run under both, matching bin/brewmaster's own
# process-substitution read loop elsewhere in this project)
HELP_LINES=()
while IFS= read -r _gm_line || [ -n "$_gm_line" ]; do
  HELP_LINES+=("$_gm_line")
done < <(_help_source_text)

# gen_synopsis — emit .SH SYNOPSIS body from the leading "Usage: ..." block
# (the lines from the top of _help_source_text() up to the first blank
# line).
# Args:   none
# Stdout: troff SYNOPSIS body
# Return: 0
gen_synopsis() {
  local line rest first=true
  for line in "${HELP_LINES[@]}"; do
    [ -z "$line" ] && break
    case "$line" in
      "Usage: "*) rest="${line#Usage: }" ;;
      "       "*) rest="${line#       }" ;;
      *)          continue ;;
    esac
    $first || printf '.br\n'
    first=false
    printf '.B brewmaster\n'
    _man_safe_line "$(_man_inline "${rest#brewmaster }")"
  done
}

# gen_commands — emit .SH COMMANDS body: one .SS per caps-header group,
# walking each group's lines with the same shapes usage()'s styling loop
# recognizes (definition lines become .TP entries, "label:" lines become
# bold paragraph headers, everything else is continuation text). A blank
# source line marks a paragraph boundary: continuation text immediately
# after a .TP entry with NO blank line between (e.g. an example line right
# under a command's own description) stays part of that .TP's body, but
# continuation text preceded by a blank line starts its own .PP — without
# this, standalone notes would silently render as if they were still
# describing whichever flag happened to be the last .TP before them.
# Args:   none
# Stdout: troff COMMANDS body
# Return: 0
gen_commands() {
  local line in_group=false name desc cont pending_break=true
  for line in "${HELP_LINES[@]}"; do
    if [[ "$line" =~ ^([A-Z][A-Z\ \&]*)(.*)$ ]] && [ "${#BASH_REMATCH[1]}" -ge 2 ]; then
      in_group=true
      pending_break=false
      printf '.SS %s%s\n' "$(_man_escape "${BASH_REMATCH[1]}")" "$(_man_escape "${BASH_REMATCH[2]}")"
      continue
    fi
    $in_group || continue
    if [ -z "$line" ]; then
      pending_break=true
      continue
    elif [[ "$line" =~ ^(\ \ |\ \ \ \ )([^\ ]+(\ [^\ ]+)*)(\ \ +)(.*)$ ]]; then
      name="${BASH_REMATCH[2]}"
      desc="${BASH_REMATCH[5]}"
      printf '.TP\n.B %s\n' "$(_man_inline "$name")"
      _man_safe_line "$(_man_inline "$desc")"
      pending_break=false
    elif [[ "$line" =~ ^(\ \ )([^\ ].*:)$ ]]; then
      printf '.PP\n.B %s\n' "$(_man_escape "${BASH_REMATCH[2]}")"
      pending_break=false
    else
      cont="$(printf '%s' "$line" | sed -E 's/^ +//')"
      if $pending_break; then
        printf '.PP\n'
        pending_break=false
      fi
      _man_safe_line "$(_man_inline "$cont")"
    fi
  done
}

# gen_files — emit .SH FILES body, extracted from the storage-path lines
# inside each group's body ("  <description>: ~/<path> <annotation>."),
# not from a separate Notes section (there isn't one — each group states
# its own on-disk location where relevant).
# Args:   none
# Stdout: troff FILES body
# Return: 0
gen_files() {
  local line desc path extra found=false
  for line in "${HELP_LINES[@]}"; do
    if [[ "$line" =~ ^\ \ (.+):\ (~[^\ ]+)\ (.*)$ ]]; then
      desc="${BASH_REMATCH[1]}"
      path="${BASH_REMATCH[2]}"
      extra="${BASH_REMATCH[3]}"
      found=true
      printf '.TP\n.I %s\n' "$(_man_escape "$path")"
      _man_safe_line "$(_man_escape "${desc}. ${extra}")"
    fi
  done
  if ! $found; then
    printf '.PP\nNone.\n'
  fi
}

# gen_examples — emit .SH EXAMPLES body from every "e.g. brewmaster ..."
# span found anywhere in the source text (one per group, per help_data.sh's
# convention).
# Args:   none
# Stdout: troff EXAMPLES body
# Return: 0
gen_examples() {
  local line example found=false
  for line in "${HELP_LINES[@]}"; do
    if [[ "$line" =~ e\.g\.\ (brewmaster\ .*)$ ]]; then
      example="${BASH_REMATCH[1]}"
      example="${example%.}"
      found=true
      printf '.TP\n.B %s\n' "$(_man_escape "$example")"
    fi
  done
  if ! $found; then
    printf '.PP\nNone.\n'
  fi
}

# --- Assemble the page ---
printf '.TH BREWMASTER 1 "%s" "brewmaster %s" "User Commands"\n' "$MAN_DATE" "$MAN_VERSION"

printf '.SH NAME\n'
printf 'brewmaster \\- selective Homebrew package upgrades by semver bump level\n'

printf '.SH SYNOPSIS\n'
gen_synopsis

printf '.SH DESCRIPTION\n'
cat <<'EOF'
.B brewmaster
upgrades only what you decide \(em patch, minor, or major \(em nothing more.
It classifies every outdated package by its semantic-versioning bump, gates
the upgrade by the requested level, and understands
.I why
a package exists on your machine before touching it.
.PP
brewmaster is deterministic: no AI, no guessing, no network calls beyond
.BR brew (1)
itself. Run
.B brewmaster help
.I command
for a per-command reference, or
.B brewmaster --help
for the full flag reference.
EOF

printf '.SH COMMANDS\n'
gen_commands

printf '.SH FILES\n'
gen_files

printf '.SH EXAMPLES\n'
gen_examples
