#!/usr/bin/env bash
# docs/gen-completions.sh — generate a shell completion script for
# brewmaster from lib/brewmaster/core/cli_spec.sh, the single source of
# the CLI surface (commands, sub-subcommands, positionals, flags). The
# counterpart of gen-man.sh: tests/test_completions.sh fails when a
# committed script under completions/ drifts from this generator's output.
# Standalone: sources ONLY cli_spec.sh, so it needs no brew/jq environment.
#
# Usage: docs/gen-completions.sh <bash|zsh|fish> > completions/brewmaster.<shell>
# Args:   $1 shell (bash | zsh | fish)
# Stdout: the completion script
# Return: 0; 1 on a missing spec or an unknown shell
#
# Structure: _spec_load reads the records into parallel indexed arrays
# (bash 3.2: no associative arrays); the _spec_* helpers query them; one
# _emit_<shell> function per dialect renders the script. Only the
# dynamic-completer preambles (brew list packages, profiles.toml profiles,
# snapshot refs) are fixed text — they are shell code, not CLI surface.
# shellcheck disable=SC2016,SC2034 # emitters print literal $var/$(...) shell text; spec arrays are shared across functions
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_SPEC="$SCRIPT_DIR/../lib/brewmaster/core/cli_spec.sh"
if [ ! -f "$CLI_SPEC" ]; then
  echo "gen-completions.sh: cannot find $CLI_SPEC" >&2
  exit 1
fi
# shellcheck source=../lib/brewmaster/core/cli_spec.sh
source "$CLI_SPEC"

# --- spec loader and query helpers ------------------------------------------
# gen-core.sh — spec loader and query helpers shared by the completion
# emitters. Sourced by docs/gen-completions.sh after cli_spec.sh.
# bash 3.2 compatible: parallel indexed arrays, no associative arrays,
# no mapfile.

# _spec_load — parse _cli_spec into arrays.
# Globals (write): SPEC_CMDS[i] name, SPEC_CMD_DESC[i] description,
#   SPEC_DEFAULT (the default command's name), SPEC_SUBS[i] "cmd|name|desc",
#   SPEC_ARGS[i] "scope|pos|type|label", SPEC_FLAGS[i] "scope|names|value|desc[|opts]"
# Return: 0
_spec_load() {
  SPEC_CMDS=(); SPEC_CMD_DESC=(); SPEC_DEFAULT=""
  SPEC_SUBS=(); SPEC_ARGS=(); SPEC_FLAGS=()
  local line kind rest name r2 desc opt
  while IFS= read -r line; do
    kind="${line%%|*}"; rest="${line#*|}"
    case "$kind" in
      cmd)
        name="${rest%%|*}"; r2="${rest#*|}"; desc="${r2%%|*}"; opt=""
        if [[ "$r2" == *"|"* ]]; then opt="${r2#*|}"; fi
        SPEC_CMDS+=("$name"); SPEC_CMD_DESC+=("$desc")
        if [[ "$opt" == "default" ]]; then SPEC_DEFAULT="$name"; fi ;;
      sub)  SPEC_SUBS+=("$rest") ;;
      arg)  SPEC_ARGS+=("$rest") ;;
      flag) SPEC_FLAGS+=("$rest") ;;
    esac
  done < <(_cli_spec)
}

# _spec_subs_of <cmd> — sub-subcommands of a command, "name|desc" per line.
_spec_subs_of()  { local c="$1" s; for s in ${SPEC_SUBS[@]+"${SPEC_SUBS[@]}"};  do if [[ "${s%%|*}" == "$c" ]];  then printf '%s\n' "${s#*|}"; fi; done; return 0; }
# _spec_flags_of <scope> — flags of a scope (global | cmd | cmd.sub), "names|value|desc[|opts]" per line.
_spec_flags_of() { local sc="$1" f; for f in ${SPEC_FLAGS[@]+"${SPEC_FLAGS[@]}"}; do if [[ "${f%%|*}" == "$sc" ]]; then printf '%s\n' "${f#*|}"; fi; done; return 0; }
# _spec_args_of <scope> — positionals of a scope, "pos|type|label" per line.
_spec_args_of()  { local sc="$1" a; for a in ${SPEC_ARGS[@]+"${SPEC_ARGS[@]}"};  do if [[ "${a%%|*}" == "$sc" ]]; then printf '%s\n' "${a#*|}"; fi; done; return 0; }
# _spec_long <names> — the long spelling of a comma-separated names field ("-n,--dry-run" -> "--dry-run").
_spec_long()  { local n; for n in ${1//,/ }; do if [[ "$n" == --* ]]; then printf '%s\n' "$n"; return 0; fi; done; return 0; }
# _spec_short <names> — the short spelling, or nothing ("-n,--dry-run" -> "-n").
_spec_short() { local n; for n in ${1//,/ }; do if [[ "$n" == -[!-]* ]]; then printf '%s\n' "$n"; return 0; fi; done; return 0; }
# _spec_field <record> <n> — the n-th "|"-separated field (1-based) of a record.
_spec_field() { local r="$1" n="$2" i=1; while (( i < n )); do r="${r#*|}"; i=$((i+1)); done; printf '%s\n' "${r%%|*}"; }
# _spec_opt <record> <key> — value of key=... in a record's trailing opts, or nothing.
_spec_opt() { local r="$1" key="$2" f; while [[ "$r" == *"|"* ]]; do r="${r#*|}"; f="${r%%|*}"; if [[ "$f" == "$key="* ]]; then printf '%s\n' "${f#*=}"; return 0; fi; done; return 0; }

# --- bash emitter ----------------------------------------------------------------
# ^ This file is a code generator: nearly every single-quoted string below
#   is literal *output* shell source (containing $vars and $(...) command
#   substitutions) that must NOT expand while _emit_bash itself runs — it
#   is meant to expand later, in the generated completions/brewmaster.bash.
#   SC2016 firing on that is expected and correct; disabled file-wide.
# emit_bash.sh — bash completion emitter for brewmaster.
#
# Defines _emit_bash, which prints a complete bash completion script to
# stdout from the arrays populated by `_spec_load` (see gen-core.sh /
# cli_spec.sh). bash 3.2 compatible: indexed arrays only, no mapfile,
# no ${var^^}.
#
# Public entry point:
#   _emit_bash — Args: none. Reads: SPEC_CMDS/SPEC_CMD_DESC/SPEC_DEFAULT/
#     SPEC_SUBS/SPEC_ARGS/SPEC_FLAGS (via _spec_load) and the _spec_*
#     helpers. Stdout: the full completions/brewmaster.bash script.
#     Return: 0.
#
# All other functions here (_emit_bash_*) are private helpers.

# _emit_bash_wordlist <scope> — space-separated completion word list for a
# flag scope (global | cmd | cmd.sub), in spec order. A boolean flag
# contributes its short spelling (if any) then its long spelling; a
# value-taking flag contributes only its long spelling with a trailing "="
# (e.g. "--level=") so callers can offer it as both a bare word and a
# --flag= prefix.
# Args:   $1 = scope
# Stdout: the word list (may be empty)
# Return: 0
_emit_bash_wordlist() {
  local scope="$1" f names value short long out=""
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    names="$(_spec_field "$f" 1)"
    value="$(_spec_field "$f" 2)"
    short="$(_spec_short "$names")"
    long="$(_spec_long "$names")"
    if [[ -z "$value" ]]; then
      [[ -n "$short" ]] && out="$out $short"
      [[ -n "$long" ]] && out="$out $long"
    else
      [[ -n "$long" ]] && out="$out ${long}="
    fi
  done < <(_spec_flags_of "$scope")
  out="${out# }"
  printf '%s' "$out"
  return 0
}

# _emit_bash_positional_completer <scope> — the runtime completion source
# for the first positional of a scope, as literal text ready to embed
# inside a `compgen -W "..."` word list in the generated script (i.e. it
# may itself contain a literal "$(...)" command substitution which must
# NOT be expanded here). Empty when the scope has no positional, or its
# type has no completion (e.g. "snapshot").
# Args:   $1 = scope (cmd or cmd.sub)
# Stdout: the literal text, or nothing
# Return: 0
_emit_bash_positional_completer() {
  local scope="$1" a type=""
  for a in ${SPEC_ARGS[@]+"${SPEC_ARGS[@]}"}; do
    if [[ "${a%%|*}" == "$scope" ]]; then
      type="$(_spec_field "$a" 3)"
      break
    fi
  done
  case "$type" in
    package) printf '%s' '$(_brewmaster_packages)' ;;
    profile) printf '%s' '$(_brewmaster_profiles)' ;;
    shell)   printf '%s' 'bash zsh fish' ;;
    command) printf '%s' '$commands' ;;
    *)       printf '%s' '' ;;
  esac
  return 0
}

# _emit_bash_first_arg_pos <scope> — the position field of a scope's first
# positional record ("1", "2" or "*"), or nothing when it has none.
# Args:   $1 = scope
# Stdout: the position, or nothing
# Return: 0
_emit_bash_first_arg_pos() {
  local scope="$1" a
  for a in ${SPEC_ARGS[@]+"${SPEC_ARGS[@]}"}; do
    if [[ "${a%%|*}" == "$scope" ]]; then
      _spec_field "$a" 2
      return 0
    fi
  done
  return 0
}

# _emit_bash_has_args <scope> — whether a scope has any positional record.
# Args:   $1 = scope
# Return: 0 if it has at least one arg record, 1 otherwise
_emit_bash_has_args() {
  local scope="$1" a
  for a in ${SPEC_ARGS[@]+"${SPEC_ARGS[@]}"}; do
    [[ "${a%%|*}" == "$scope" ]] && return 0
  done
  return 1
}

# _emit_bash_prev_cases — print the `case "$prev" in ... esac` arms for
# "--flag value" (space-separated) completion: one arm per value-taking
# flag whose value is an enum or a dynamic (@package/@profile) completer,
# plus one combined arm (no completion, just `return`) for every
# free-value (N/TEXT) flag. Long-flag names are deduplicated across scopes.
# Args:   none (reads SPEC_FLAGS)
# Stdout: case arms
# Return: 0
_emit_bash_prev_cases() {
  local f names value long seen="" free=""
  for f in ${SPEC_FLAGS[@]+"${SPEC_FLAGS[@]}"}; do
    # SPEC_FLAGS entries are "scope|names|value|desc[|opts]".
    names="$(_spec_field "$f" 2)"
    value="$(_spec_field "$f" 3)"
    [[ -z "$value" ]] && continue
    long="$(_spec_long "$names")"
    [[ -z "$long" ]] && continue
    case " $seen " in *" $long "*) continue ;; esac
    seen="$seen $long"
    case "$value" in
      @package) printf '    %s) COMPREPLY=( $(compgen -W "$(_brewmaster_packages)" -- "$cur") ); return ;;\n' "$long" ;;
      @profile) printf '    %s) COMPREPLY=( $(compgen -W "$(_brewmaster_profiles)" -- "$cur") ); return ;;\n' "$long" ;;
      N|TEXT)   free="$free|$long" ;;
      *)        printf '    %s) COMPREPLY=( $(compgen -W "%s" -- "$cur") ); return ;;\n' "$long" "$value" ;;
    esac
  done
  free="${free#|}"
  [[ -n "$free" ]] && printf '    %s) return ;;\n' "$free"
  return 0
}

# _emit_bash_eq_cases — print the `case "$cur" in ... esac` arms for
# "--flag=value" (no-space) completion. Free-value (N/TEXT) flags get no
# arm (bash offers nothing for --label=..., matching the hand-written
# script). Long-flag names are deduplicated across scopes.
# Args:   none (reads SPEC_FLAGS)
# Stdout: case arms
# Return: 0
_emit_bash_eq_cases() {
  local f names value long seen=""
  for f in ${SPEC_FLAGS[@]+"${SPEC_FLAGS[@]}"}; do
    # SPEC_FLAGS entries are "scope|names|value|desc[|opts]".
    names="$(_spec_field "$f" 2)"
    value="$(_spec_field "$f" 3)"
    [[ -z "$value" ]] && continue
    long="$(_spec_long "$names")"
    [[ -z "$long" ]] && continue
    case " $seen " in *" $long "*) continue ;; esac
    seen="$seen $long"
    case "$value" in
      N|TEXT)   continue ;;
      @package) printf '    %s=*) COMPREPLY=( $(compgen -W "$(_brewmaster_packages)" -P "%s=" -- "${cur#*=}") ); return ;;\n' "$long" "$long" ;;
      @profile) printf '    %s=*) COMPREPLY=( $(compgen -W "$(_brewmaster_profiles)" -P "%s=" -- "${cur#*=}") ); return ;;\n' "$long" "$long" ;;
      *)        printf '    %s=*) COMPREPLY=( $(compgen -W "%s" -P "%s=" -- "${cur#*=}") ); return ;;\n' "$long" "$value" "$long" ;;
    esac
  done
  return 0
}

# _emit_bash_default_block — print the top-level ("$cmd" still empty)
# dispatch: SPEC_DEFAULT's own flags when $cur looks like a flag, else
# the command list plus SPEC_DEFAULT's positional completer (if any).
# Args:   none (reads SPEC_DEFAULT, SPEC_ARGS)
# Stdout: the `if [[ -z "$cmd" ]]; then ... fi` block
# Return: 0
_emit_bash_default_block() {
  local def="$SPEC_DEFAULT" completer list
  completer="$(_emit_bash_positional_completer "$def")"
  if [[ -n "$completer" ]]; then
    list="\$commands $completer"
  else
    list='$commands'
  fi
  echo '  if [[ -z "$cmd" ]]; then'
  echo '    if [[ "$cur" == -* ]]; then'
  printf '      COMPREPLY=( $(compgen -W "$general $%s_flags" -- "$cur") )\n' "$def"
  echo '    elif [[ "${COMP_WORDS[1]}" == -* ]]; then'
  echo '      # A leading flag: bin/brewmaster only reads a command from $1, so'
  printf '      # the default command runs and only its positional applies.\n'
  if [[ -n "$completer" ]]; then
    printf '      COMPREPLY=( $(compgen -W "%s" -- "$cur") )\n' "$completer"
  else
    echo '      COMPREPLY=()'
  fi
  echo '    else'
  printf '      COMPREPLY=( $(compgen -W "%s" -- "$cur") )\n' "$list"
  echo '    fi'
  echo '    return'
  echo '  fi'
  echo
  return 0
}

# _emit_bash_cmd_block_subs <cmd> <subs> — print the `<cmd>) ... ;;` case
# arm for a command that has sub-subcommands: offer sub names when none is
# chosen yet, the command's (union of all its subs') flags when $cur looks
# like a flag, else group subs by their positional completer and dispatch
# on $sub (subs with no completable positional get no arm, so bash offers
# nothing there — e.g. `snapshot diff <TAB>`).
# Args:   $1 = command name, $2 = `_spec_subs_of` output ("name|desc" lines)
# Stdout: one case arm
# Return: 0
_emit_bash_cmd_block_subs() {
  local c="$1" subs="$2" line sname completer sublist="" i found
  local gcompleter=() gsubs=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    sname="${line%%|*}"
    sublist="$sublist $sname"
    completer="$(_emit_bash_positional_completer "$c.$sname")"
    [[ -z "$completer" ]] && continue
    found=0
    for ((i = 0; i < ${#gcompleter[@]}; i++)); do
      if [[ "${gcompleter[i]}" == "$completer" ]]; then
        gsubs[i]="${gsubs[i]}|$sname"
        found=1
        break
      fi
    done
    if [[ $found -eq 0 ]]; then
      gcompleter+=("$completer")
      gsubs+=("$sname")
    fi
  done <<EOF
$subs
EOF
  sublist="${sublist# }"

  printf '    %s)\n' "$c"
  printf '      if [[ "$cur" == -* ]]; then\n'
  printf '        COMPREPLY=( $(compgen -W "$general $%s_subflags" -- "$cur") )\n' "$c"
  printf '      elif [[ -z "$sub" ]]; then\n'
  printf '        COMPREPLY=( $(compgen -W "%s" -- "$cur") )\n' "$sublist"
  if (( ${#gcompleter[@]} > 0 )); then
    printf '      else\n'
    printf '        case "$sub" in\n'
    for ((i = 0; i < ${#gcompleter[@]}; i++)); do
      printf '          %s) COMPREPLY=( $(compgen -W "%s" -- "$cur") ) ;;\n' "${gsubs[i]}" "${gcompleter[i]}"
    done
    printf '        esac\n'
  fi
  printf '      fi\n'
  printf '      ;;\n'
  return 0
}

# _emit_bash_cmd_block <cmd> — print the `<cmd>) ... ;;` case arm for one
# top-level command: delegates to _emit_bash_cmd_block_subs when the
# command has sub-subcommands; otherwise prints a flags-vs-positional
# dispatch (guarded on $cur looking like a flag) when the command has a
# positional, or an unconditional flags offer when it has neither subs nor
# a positional (matches the hand-written script's cleanup/log/bloat/report
# arms, which always offer flags regardless of $cur).
# Args:   $1 = command name
# Stdout: one case arm
# Return: 0
_emit_bash_cmd_block() {
  local c="$1" subs completer
  subs="$(_spec_subs_of "$c")"
  if [[ -n "$subs" ]]; then
    _emit_bash_cmd_block_subs "$c" "$subs"
    return 0
  fi

  printf '    %s)\n' "$c"
  if _emit_bash_has_args "$c"; then
    completer="$(_emit_bash_positional_completer "$c")"
    printf '      if [[ "$cur" == -* ]]; then\n'
    printf '        COMPREPLY=( $(compgen -W "$general $%s_flags" -- "$cur") )\n' "$c"
    if [[ "$(_emit_bash_first_arg_pos "$c")" == '*' ]]; then
      printf '      else\n'
    else
      # One positional: once it is typed ($sub), offer nothing more.
      printf '      elif [[ -z "$sub" ]]; then\n'
    fi
    if [[ -n "$completer" ]]; then
      printf '        COMPREPLY=( $(compgen -W "%s" -- "$cur") )\n' "$completer"
    fi
    printf '      fi\n'
  else
    printf '      COMPREPLY=( $(compgen -W "$general $%s_flags" -- "$cur") )\n' "$c"
  fi
  printf '      ;;\n'
  return 0
}

# _emit_bash — print the complete generated bash completion script.
# Args:   none
# Reads:  SPEC_CMDS, SPEC_CMD_DESC, SPEC_DEFAULT, SPEC_SUBS, SPEC_ARGS,
#         SPEC_FLAGS (populated by _spec_load) and the _spec_* helpers.
# Stdout: the full completions/brewmaster.bash script
# Return: 0
_emit_bash() {
  local c subs sname line union sw

  cat <<'HEADER'
# Bash completion for brewmaster.
#
# GENERATED FILE — produced by docs/gen-completions.sh from
# lib/brewmaster/core/cli_spec.sh. Do not edit by hand; regenerate instead.
#
# Installed by the Homebrew formula (bash_completion.install). From a git
# checkout: source completions/brewmaster.bash, or copy it into
#   "$(brew --prefix)/etc/bash_completion.d/brewmaster"

_brewmaster_packages() {
  brew list --formula --cask 2>/dev/null
}

_brewmaster_profiles() {
  local conf="${XDG_CONFIG_HOME:-$HOME/.config}/brewmaster/profiles.toml"
  [[ -f "$conf" ]] || return 0
  grep -oE '^\[profiles\.[^]]+\]' "$conf" | sed -E 's/^\[profiles\.(.*)\]$/\1/'
}

_brewmaster() {
  local cur prev cmd sub i w
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

HEADER

  # commands word list
  local commands=""
  for c in "${SPEC_CMDS[@]}"; do commands="$commands $c"; done
  commands="${commands# }"
  printf '  local commands="%s"\n' "$commands"

  # general (global) flags word list
  printf '  local general="%s"\n' "$(_emit_bash_wordlist global)"

  # per-command flags / subflags word lists
  for c in "${SPEC_CMDS[@]}"; do
    subs="$(_spec_subs_of "$c")"
    if [[ -n "$subs" ]]; then
      union="$(_emit_bash_wordlist "$c")"
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        sname="${line%%|*}"
        sw="$(_emit_bash_wordlist "$c.$sname")"
        [[ -n "$sw" ]] && union="$union $sw"
      done <<EOF
$subs
EOF
      union="${union# }"
      printf '  local %s_subflags="%s"\n' "$c" "$union"
    else
      printf '  local %s_flags="%s"\n' "$c" "$(_emit_bash_wordlist "$c")"
    fi
  done
  echo

  cat <<'MIDDLE'
  # First two non-flag words after "brewmaster" = command and sub-subcommand.
  # bin/brewmaster recognises a command only as its first argument, so a
  # leading flag means the default command runs and no command is looked for.
  cmd=""; sub=""
  if [[ "${COMP_WORDS[1]}" != -* ]]; then
    for ((i = 1; i < COMP_CWORD; i++)); do
      w="${COMP_WORDS[i]}"
      [[ "$w" == -* ]] && continue
      if [[ -z "$cmd" ]]; then cmd="$w"
      elif [[ -z "$sub" ]]; then sub="$w"; fi
    done
  fi

MIDDLE

  echo '  # "--flag value" (space-separated) completion.'
  echo '  case "$prev" in'
  _emit_bash_prev_cases
  echo '  esac'
  echo

  echo '  # "--flag=value" (no-space) completion.'
  echo '  case "$cur" in'
  _emit_bash_eq_cases
  echo '  esac'
  echo

  _emit_bash_default_block

  echo '  case "$cmd" in'
  for c in "${SPEC_CMDS[@]}"; do
    _emit_bash_cmd_block "$c"
  done
  echo '  esac'
  echo '}'
  echo
  echo 'complete -o default -o bashdefault -F _brewmaster brewmaster'
  return 0
}

# --- zsh emitter ----------------------------------------------------------------
# emit_zsh.sh — zsh completion emitter. Sourced by docs/gen-completions.sh
# after cli_spec.sh and gen-core.sh; call _emit_zsh after _spec_load.
# bash 3.2 compatible: no associative arrays, no mapfile, no case-modifying
# expansions. Output is deterministic (nothing environment-dependent).
# (SC2016: the single-quoted printf formats are zsh source text and must not
# expand here.)

# _emit_zsh_q — quote a string for use inside a single-quoted zsh word that
#   is later parsed by _arguments ("'" -> "'\''", "[" / "]" escaped).
# Args:   $1 string
# Stdout: the escaped string
# Return: 0
_emit_zsh_q() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\'/\'\\\'\'}"
  s="${s//\[/\\[}"
  s="${s//\]/\\]}"
  printf '%s\n' "$s"
}

# _emit_zsh_desc — turn a spec description into a zsh completion
#   description: first character lowercased (zsh convention), escaped.
# Args:   $1 description
# Stdout: the description ready to be placed inside '[...]'
# Return: 0
_emit_zsh_desc() {
  local s="$1" c
  c=$(printf '%s' "${s:0:1}" | tr '[:upper:]' '[:lower:]')
  _emit_zsh_q "$c${s:1}"
}

# _emit_zsh_item — a "name:desc" entry for _describe (":" and "'" escaped).
# Args:   $1 name, $2 description
# Stdout: the quoted entry, e.g. 'save:save current state to a snapshot'
# Return: 0
_emit_zsh_item() {
  local name="$1" desc
  desc=$(_emit_zsh_desc "$2")
  desc="${desc//:/\\:}"
  printf "'%s:%s'\n" "$name" "$desc"
}

# _emit_zsh_pos_action — the _arguments action for a positional type.
# Args:   $1 type (package | profile | snapshot | shell | other)
# Stdout: the action ("" for a free value)
# Return: 0
_emit_zsh_pos_action() {
  case "$1" in
    package)  printf '%s\n' '_brewmaster_packages' ;;
    profile)  printf '%s\n' '_brewmaster_profiles' ;;
    snapshot) printf '%s\n' '_brewmaster_snapshot_refs' ;;
    shell)    printf '%s\n' '(bash zsh fish)' ;;
    command)  printf '(%s)\n' "${SPEC_CMDS[*]}" ;;
    *)        printf '\n' ;;
  esac
}

# _emit_zsh_pos_spec — the _arguments spec for one positional record.
# Args:   $1 record "pos|type|label"
# Stdout: e.g. '1:snapshot:_brewmaster_snapshot_refs'
# Return: 0
_emit_zsh_pos_spec() {
  local pos type label action
  pos=$(_spec_field "$1" 1); type=$(_spec_field "$1" 2); label=$(_spec_field "$1" 3)
  action=$(_emit_zsh_pos_action "$type")
  printf "'%s:%s:%s'\n" "$pos" "$(_emit_zsh_q "$label")" "$action"
}

# _emit_zsh_flag_spec — the _arguments spec for one flag record.
# Args:   $1 scope, $2 record "names|value|desc[|opts]"
# Stdout: e.g. '(--minor --major --level)--patch[apply patch bumps only]'
#         or '(-n --dry-run)'{-n,--dry-run}'[show the plan without executing]'
# Return: 0
_emit_zsh_flag_spec() {
  local scope="$1" rec="$2"
  local names value desc group long short excl other onames og os ol
  local label tail out
  names=$(_spec_field "$rec" 1); value=$(_spec_field "$rec" 2)
  desc=$(_emit_zsh_desc "$(_spec_field "$rec" 3)")
  group=$(_spec_opt "$rec" excl)
  long=$(_spec_long "$names"); short=$(_spec_short "$names")
  if [[ -z "$long" ]]; then long="$short"; short=""; fi

  # Exclusion list: own spellings (short+long pairs) plus every spelling of
  # the other flags in the same excl= group of the same scope, in spec order.
  excl=""
  if [[ -n "$short" ]]; then excl="$short $long"; fi
  if [[ -n "$group" ]]; then
    while IFS= read -r other; do
      [[ -n "$other" ]] || continue
      onames=$(_spec_field "$other" 1)
      [[ "$onames" != "$names" ]] || continue
      og=$(_spec_opt "$other" excl)
      [[ "$og" == "$group" ]] || continue
      os=$(_spec_short "$onames"); ol=$(_spec_long "$onames")
      if [[ -n "$os" ]]; then excl="${excl:+$excl }$os"; fi
      if [[ -n "$ol" ]]; then excl="${excl:+$excl }$ol"; fi
    done < <(_spec_flags_of "$scope")
  fi

  # Value part: "" boolean; enum list; @package / @profile dynamic; free word.
  label="${long#--}"; label="${label#-}"
  case "$value" in
    '')        tail="[$desc]" ;;
    @package)  tail="=[$desc]:package:_brewmaster_packages" ;;
    @profile)  tail="=[$desc]:profile:_brewmaster_profiles" ;;
    *' '*)     tail="=[$desc]:$label:($value)" ;;
    *)         tail="=[$desc]:$label:" ;;
  esac

  if [[ -n "$short" ]]; then
    out="'($excl)'{$short,$long}'$tail'"
  elif [[ -n "$excl" ]]; then
    out="'($excl)$long$tail'"
  else
    out="'$long$tail'"
  fi
  printf '%s\n' "$out"
}

# _emit_zsh_arguments — print one complete _arguments call. Dispatchers pass
#   "-C -A '-*'": -A stops the dispatcher from consuming options that belong
#   to the command word that follows (brewmaster upgrade -n <TAB>).
# Args:   $1 indent, $2 _arguments options ("-C -A '-*'") or "", $3 scope (global | cmd | cmd.sub),
#         $4 "pos" to append the scope's positionals, else "",
#         $5.. extra specs appended verbatim after the flags
# Stdout: the _arguments call, one spec per continuation line
# Return: 0
_emit_zsh_arguments() {
  local ind="$1" cflag="$2" scope="$3" withpos="$4"
  shift 4
  local -a specs
  local rec n i
  specs=()
  if [[ "$scope" != "global" ]]; then
    while IFS= read -r rec; do
      [[ -n "$rec" ]] || continue
      specs+=("$(_emit_zsh_flag_spec "$scope" "$rec")")
    done < <(_spec_flags_of "$scope")
  fi
  while IFS= read -r rec; do
    [[ -n "$rec" ]] || continue
    specs+=("$(_emit_zsh_flag_spec global "$rec")")
  done < <(_spec_flags_of global)
  if [[ "$withpos" == "pos" ]]; then
    while IFS= read -r rec; do
      [[ -n "$rec" ]] || continue
      specs+=("$(_emit_zsh_pos_spec "$rec")")
    done < <(_spec_args_of "$scope")
  fi
  while (( $# > 0 )); do specs+=("$1"); shift; done

  n=${#specs[@]}
  if (( n == 0 )); then
    printf '%s_arguments%s\n' "$ind" "${cflag:+ $cflag}"
    return 0
  fi
  printf '%s_arguments%s \\\n' "$ind" "${cflag:+ $cflag}"
  i=0
  while (( i < n )); do
    if (( i + 1 < n )); then
      printf '%s  %s \\\n' "$ind" "${specs[$i]}"
    else
      printf '%s  %s\n' "$ind" "${specs[$i]}"
    fi
    i=$((i+1))
  done
  return 0
}

# _emit_zsh_command — print the _brewmaster_<cmd> function for one command:
#   a plain _arguments call, or (with sub-subcommands) a state machine that
#   describes the subs and dispatches to a per-sub _arguments call.
# Args:   $1 command name
# Stdout: the function definition
# Return: 0
_emit_zsh_command() {
  local cmd="$1" sub name desc
  local -a subs
  subs=()
  while IFS= read -r sub; do
    [[ -n "$sub" ]] || continue
    subs+=("$sub")
  done < <(_spec_subs_of "$cmd")

  printf '_brewmaster_%s() {\n' "$cmd"
  if (( ${#subs[@]} == 0 )); then
    _emit_zsh_arguments '  ' '' "$cmd" pos
    printf '}\n'
    return 0
  fi

  printf '  local curcontext="$curcontext" state line\n'
  _emit_zsh_arguments '  ' "-C -A '-*'" "$cmd" '' "'1: :->subcommand'" "'*::arg:->subargs'"
  printf '\n  case $state in\n'
  printf '    subcommand)\n'
  printf '      local -a subcmds=(\n'
  for sub in "${subs[@]}"; do
    name="${sub%%|*}"; desc="${sub#*|}"
    printf '        %s\n' "$(_emit_zsh_item "$name" "$desc")"
  done
  printf '      )\n'
  printf "      _describe -t subcommands '%s subcommand' subcmds\n" "$cmd"
  printf '      ;;\n'
  printf '    subargs)\n'
  printf '      case $line[1] in\n'
  for sub in "${subs[@]}"; do
    name="${sub%%|*}"
    printf '        %s)\n' "$name"
    _emit_zsh_arguments '          ' '' "$cmd.$name" pos
    printf '          ;;\n'
  done
  printf '      esac\n'
  printf '      ;;\n'
  printf '  esac\n'
  printf '}\n'
  return 0
}

# _emit_zsh — print the complete zsh completion script for brewmaster,
#   derived from the loaded spec (call _spec_load first).
# Args:   none
# Stdout: the completion script (#compdef brewmaster first)
# Return: 0
_emit_zsh() {
  local i cmd rec type action

  cat <<'HEADER'
#compdef brewmaster
#
# Zsh completion for brewmaster.
#
# GENERATED FILE — do not edit by hand. Produced by docs/gen-completions.sh
# from lib/brewmaster/core/cli_spec.sh; change the spec and regenerate.
#
# Installed by the Homebrew formula (zsh_completion.install). From a git
# checkout: cp completions/brewmaster.zsh "$(brew --prefix)/share/zsh/site-functions/_brewmaster"
# then start a new shell (or run `compinit`).

_brewmaster_packages() {
  local -a pkgs
  pkgs=(${(f)"$(brew list --formula --cask 2>/dev/null)"})
  _describe -t packages 'package' pkgs
}

_brewmaster_profiles() {
  local conf="${XDG_CONFIG_HOME:-$HOME/.config}/brewmaster/profiles.toml"
  local -a profiles
  [[ -f $conf ]] && profiles=(${(f)"$(grep -oE '^\[profiles\.[^]]+\]' $conf | sed -E 's/^\[profiles\.(.*)\]$/\1/')"})
  _describe -t profiles 'profile' profiles
}

_brewmaster_snapshot_refs() {
  local dir="${XDG_DATA_HOME:-$HOME/.local/share}/brewmaster/snapshots"
  _files -W $dir -g '*.txt'
}

HEADER

  # Top-level command list; the default command's first positional is
  # offered alongside the commands (brewmaster <package> == brewmaster <default> <package>).
  printf '_brewmaster_commands() {\n'
  printf '  # bin/brewmaster reads a command only from $1: after a leading flag\n'
  printf '  # the default command runs, so offer only its positional.\n'
  printf '  if [[ ${words[2]} == -* ]]; then\n'
  if [[ -n "$SPEC_DEFAULT" ]]; then
    while IFS= read -r rec; do
      [[ -n "$rec" ]] || continue
      case "$(_spec_field "$rec" 1)" in 1|'*') ;; *) continue ;; esac
      type=$(_spec_field "$rec" 2)
      action=$(_emit_zsh_pos_action "$type")
      case "$action" in
        '')   ;;
        '('*) action="${action#(}"; printf '    compadd -- %s\n' "${action%)}" ;;
        *)    printf '    %s\n' "$action" ;;
      esac
    done < <(_spec_args_of "$SPEC_DEFAULT")
  fi
  printf '    return\n'
  printf '  fi\n'
  printf '  local -a commands=(\n'
  i=0
  while (( i < ${#SPEC_CMDS[@]} )); do
    printf '    %s\n' "$(_emit_zsh_item "${SPEC_CMDS[$i]}" "${SPEC_CMD_DESC[$i]}")"
    i=$((i+1))
  done
  printf '  )\n'
  printf "  _describe -t commands 'command' commands\n"
  if [[ -n "$SPEC_DEFAULT" ]]; then
    while IFS= read -r rec; do
      [[ -n "$rec" ]] || continue
      case "$(_spec_field "$rec" 1)" in 1|'*') ;; *) continue ;; esac
      type=$(_spec_field "$rec" 2)
      action=$(_emit_zsh_pos_action "$type")
      case "$action" in
        '')   ;;
        '('*) action="${action#(}"; printf '  compadd -- %s\n' "${action%)}" ;;
        *)    printf '  %s\n' "$action" ;;
      esac
    done < <(_spec_args_of "$SPEC_DEFAULT")
  fi
  printf '}\n\n'

  for cmd in "${SPEC_CMDS[@]}"; do
    _emit_zsh_command "$cmd"
    printf '\n'
  done

  # Entry point: the default command's flags (with their exclusion groups)
  # and the global flags, the command word, then dispatch on it. An unknown
  # first word falls through to the default command.
  printf '_brewmaster() {\n'
  printf '  local curcontext="$curcontext" state line\n'
  printf '  typeset -A opt_args\n\n'
  _emit_zsh_arguments '  ' "-C -A '-*'" "${SPEC_DEFAULT:-global}" '' "'1: :_brewmaster_commands'" "'*::arg:->args'"
  printf '\n  case $state in\n'
  printf '    args)\n'
  printf '      case $line[1] in\n'
  for cmd in "${SPEC_CMDS[@]}"; do
    printf '        %-13s _brewmaster_%s ;;\n' "$cmd)" "$cmd"
  done
  if [[ -n "$SPEC_DEFAULT" ]]; then
    printf '        %-13s _brewmaster_%s ;;\n' '*)' "$SPEC_DEFAULT"
  fi
  printf '      esac\n'
  printf '      ;;\n'
  printf '  esac\n'
  printf '}\n\n'
  printf '_brewmaster "$@"\n'
  return 0
}

# --- fish emitter ----------------------------------------------------------------
# emit_fish.sh — fish completion emitter for the brewmaster completion
# generator. Sourced by docs/gen-completions.sh after cli_spec.sh and
# gen-core.sh (i.e. after _spec_load has populated the SPEC_* arrays).
# bash 3.2 compatible: parallel indexed arrays, no associative arrays,
# no mapfile, no ${var^^}.

# _emit_fish_quote <text> — print <text> as a single-quoted fish string
# literal, safe for any content (', ", $, \, backticks): fish recognizes
# only \\ and \' as escapes inside single quotes, so escaping those two
# is sufficient and everything else (including $VARS) stays literal.
# Args:   $1 = raw text
# Stdout: '<escaped text>'
# Return: 0
_emit_fish_quote() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\'/\\\'}"
  printf "'%s'" "$s"
  return 0
}

# _emit_fish_join <word...> — space-join positional args.
# Stdout: the words separated by single spaces, no trailing space
# Return: 0
_emit_fish_join() {
  local out="" w
  for w in "$@"; do
    if [[ -z "$out" ]]; then out="$w"; else out="$out $w"; fi
  done
  printf '%s' "$out"
  return 0
}

# _emit_fish_header — fixed file header: generated-file notice + install note.
# Stdout: header comment block
# Return: 0
_emit_fish_header() {
  cat <<'EOF'
# Fish completion for brewmaster.
#
# GENERATED FILE. Produced by docs/gen-completions.sh from
# lib/brewmaster/core/cli_spec.sh — do not edit by hand, regenerate instead.
#
# Installed by the Homebrew formula (fish_completion.install). From a git
# checkout: cp completions/brewmaster.fish (brew --prefix)/share/fish/vendor_completions.d/brewmaster.fish
EOF
  return 0
}

# _emit_fish_preamble — fixed dynamic-completer functions, copied verbatim
# from the hand-written script (not derived from the spec).
# Stdout: the __fish_brewmaster_packages / __fish_brewmaster_profiles fish functions
# Return: 0
_emit_fish_preamble() {
  cat <<'EOF'
# brewmaster takes no file arguments: never fall back to file names.
complete -c brewmaster -f

function __fish_brewmaster_packages
    brew list --formula --cask 2>/dev/null
end

function __fish_brewmaster_profiles
    set -l conf "$HOME/.config/brewmaster/profiles.toml"
    test -n "$XDG_CONFIG_HOME"; and set conf "$XDG_CONFIG_HOME/brewmaster/profiles.toml"
    test -f "$conf"; and string match -r '^\[profiles\.[^]]+\]' < "$conf" | string replace -r '^\[profiles\.(.*)\]$' '$1'
end
EOF
  return 0
}

# _emit_fish_no_subcommand — the __fish_brewmaster_no_subcommand fish
# function, generated from SPEC_CMDS (never hardcoded).
# Globals (read): SPEC_CMDS
# Stdout: the fish function definition
# Return: 0
_emit_fish_no_subcommand() {
  local names
  names=$(_emit_fish_join "${SPEC_CMDS[@]}")
  cat <<EOF
function __fish_brewmaster_no_subcommand
    not __fish_seen_subcommand_from $names
end

# bin/brewmaster reads a command only from its first argument: after a
# leading flag the default command runs, so command names are not offered.
function __fish_brewmaster_command_slot
    __fish_brewmaster_no_subcommand; and not string match -q -- '-*' (commandline -opc)[2]
end
EOF
  return 0
}

# _emit_fish_arg_line <cond> <type> — one `complete -a` line for a
# positional's dynamic/static value list, or nothing for types the
# hand-written script does not complete (snapshot refs).
# Args:   $1 = base fish condition (unquoted), $2 = arg type,
#         $3 = description (optional; adds -d)
# Stdout: one `complete` line, or nothing
# Return: 0
_emit_fish_arg_line() {
  local cond="$1" type="$2" desc="${3:-}" a=""
  case "$type" in
    package) a="(__fish_brewmaster_packages)" ;;
    profile) a="(__fish_brewmaster_profiles)" ;;
    command)
      a="${SPEC_CMDS[*]}"
      # Exactly "brewmaster <cmd>" so far: the command slot is next.
      cond="$cond; and test (count (commandline -opc)) -eq 2"
      ;;
    shell)
      a="bash zsh fish"
      # Shell names double as the value list here (like a sub-subcommand
      # list), so guard against re-suggesting once one has been typed.
      cond="$cond; and not __fish_seen_subcommand_from bash zsh fish"
      ;;
    snapshot) return 0 ;;
    *) return 0 ;;
  esac
  if [[ -n "$desc" ]]; then
    printf 'complete -c brewmaster -n %s -f -a %s -d %s\n' \
      "$(_emit_fish_quote "$cond")" "$(_emit_fish_quote "$a")" "$(_emit_fish_quote "$desc")"
  else
    printf 'complete -c brewmaster -n %s -f -a %s\n' \
      "$(_emit_fish_quote "$cond")" "$(_emit_fish_quote "$a")"
  fi
  return 0
}

# _emit_fish_positionals <scope> <cond> — emit one arg_line per distinct
# positional type in <scope> (a scope with two same-typed positionals,
# e.g. profile.diff, gets a single completion — fish's -a is not
# position-sensitive within one `complete` condition).
# Args:   $1 = scope (cmd or cmd.sub), $2 = base fish condition
# Globals (read via _spec_args_of): SPEC_ARGS
# Stdout: zero or more `complete` lines
# Return: 0
_emit_fish_positionals() {
  local scope="$1" cond="$2" line type desc seen=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    type=$(_spec_field "$line" 2)
    # "pos|type|label[|desc]": the description falls back to the label.
    case "$line" in
      *"|"*"|"*"|"*) desc=$(_spec_field "$line" 4) ;;
      *)             desc=$(_spec_field "$line" 3) ;;
    esac
    case " $seen " in
      *" $type "*) continue ;;
    esac
    seen="$seen $type"
    _emit_fish_arg_line "$cond" "$type" "$desc"
  done < <(_spec_args_of "$scope")
  return 0
}

# _emit_fish_flag_line <cond> <flag-record> — one `complete` line for a flag.
# Args:   $1 = base fish condition ("" for none, e.g. global flags),
#         $2 = "names|value|desc[|opts]" (as from _spec_flags_of)
# Stdout: one `complete` line
# Return: 0
_emit_fish_flag_line() {
  local cond="$1" rec="$2" names value desc long short a=""
  names=$(_spec_field "$rec" 1)
  value=$(_spec_field "$rec" 2)
  desc=$(_spec_field "$rec" 3)
  long=$(_spec_long "$names")
  short=$(_spec_short "$names")
  case "$value" in
    "") : ;;
    "@package") a="(__fish_brewmaster_packages)" ;;
    "@profile") a="(__fish_brewmaster_profiles)" ;;
    *" "*) a="$value" ;;
    *) : ;;  # TEXT / N placeholder: value-taking, no completion list
  esac
  local out="complete -c brewmaster"
  if [[ -n "$cond" ]]; then
    out="$out -n $(_emit_fish_quote "$cond")"
  fi
  out="$out -f"
  # A value-taking flag requires its parameter (-r); with -f that means
  # `--label <TAB>` offers nothing rather than files.
  if [[ -n "$value" ]]; then
    out="$out -r"
  fi
  if [[ -n "$short" ]]; then
    out="$out -s ${short#-}"
  fi
  if [[ -n "$long" ]]; then
    out="$out -l ${long#--}"
  fi
  if [[ -n "$a" ]]; then
    out="$out -a $(_emit_fish_quote "$a")"
  fi
  out="$out -d $(_emit_fish_quote "$desc")"
  printf '%s\n' "$out"
  return 0
}

# _emit_fish_flags_for_scope <scope> <cond> — emit a flag_line for every
# flag in <scope>, in spec order.
# Args:   $1 = scope, $2 = base fish condition ("" for none)
# Stdout: zero or more `complete` lines
# Return: 0
_emit_fish_flags_for_scope() {
  local scope="$1" cond="$2" line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    _emit_fish_flag_line "$cond" "$line"
  done < <(_spec_flags_of "$scope")
  return 0
}

# _emit_fish_top_level — the top-level "which command" completions
# (offered when no subcommand has been seen yet), plus the bare-package
# completion for the default command's positional.
# Globals (read): SPEC_CMDS, SPEC_CMD_DESC, SPEC_DEFAULT
# Stdout: comment + `complete` lines
# Return: 0
_emit_fish_top_level() {
  printf '# --- Top-level subcommands (default command is "%s"; bare package names are also valid) ---\n' "$SPEC_DEFAULT"
  local i
  for i in "${!SPEC_CMDS[@]}"; do
    printf 'complete -c brewmaster -n %s -f -a %s -d %s\n' \
      "$(_emit_fish_quote "__fish_brewmaster_command_slot")" \
      "$(_emit_fish_quote "${SPEC_CMDS[$i]}")" \
      "$(_emit_fish_quote "${SPEC_CMD_DESC[$i]}")"
  done
  _emit_fish_positionals "$SPEC_DEFAULT" "__fish_brewmaster_no_subcommand"
  return 0
}

# _emit_fish_general_flags — global flags, valid with no scoping condition.
# Globals (read via _spec_flags_of): SPEC_FLAGS
# Stdout: comment + `complete` lines
# Return: 0
_emit_fish_general_flags() {
  printf '# --- General flags (every command) ---\n'
  _emit_fish_flags_for_scope "global" ""
  return 0
}

# _emit_fish_cmd_body <cmd> <cond> — sub-subcommand, flag and positional
# completions for one top-level command (its own scope plus every
# cmd.sub scope), using <cond> as the base condition for the command's
# own scope (sub scopes always use "seen <cmd>; and seen <sub>").
# Args:   $1 = command name, $2 = base fish condition for the bare-cmd scope
# Stdout: zero or more `complete`/`set` lines
# Return: 0
_emit_fish_cmd_body() {
  local cmd="$1" cond="$2" subs names="" guard line sname sdesc sub subcond
  subs=$(_spec_subs_of "$cmd")

  if [[ -n "$subs" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      sname=$(_spec_field "$line" 1)
      names="$names $sname"
    done <<< "$subs"
    names="${names# }"
    guard="not __fish_seen_subcommand_from $names"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      sname=$(_spec_field "$line" 1)
      sdesc=$(_spec_field "$line" 2)
      printf 'complete -c brewmaster -n %s -f -a %s -d %s\n' \
        "$(_emit_fish_quote "__fish_seen_subcommand_from $cmd; and $guard")" \
        "$(_emit_fish_quote "$sname")" \
        "$(_emit_fish_quote "$sdesc")"
    done <<< "$subs"
  fi

  _emit_fish_flags_for_scope "$cmd" "$cond"
  _emit_fish_positionals "$cmd" "$cond"

  if [[ -n "$subs" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      sub=$(_spec_field "$line" 1)
      subcond="__fish_seen_subcommand_from $cmd; and __fish_seen_subcommand_from $sub"
      _emit_fish_flags_for_scope "$cmd.$sub" "$subcond"
      _emit_fish_positionals "$cmd.$sub" "$subcond"
    done <<< "$subs"
  fi
  return 0
}

# _emit_fish_cmd_section <cmd> <default|normal> — one command's section,
# with a comment header, but only when it has anything to say (a command
# with no subs, flags or positionals of its own, e.g. bloat/report, gets
# no section at all).
# Args:   $1 = command name, $2 = "default" (adds the
#         __fish_brewmaster_no_subcommand fallback to its condition) or
#         "normal"
# Stdout: comment header + `_emit_fish_cmd_body` output, or nothing
# Return: 0
_emit_fish_cmd_section() {
  local cmd="$1" kind="$2" cond header body
  if [[ "$kind" == "default" ]]; then
    cond="__fish_seen_subcommand_from $cmd; or __fish_brewmaster_no_subcommand"
    header="# --- $cmd (and the default/no-subcommand case) ---"
  else
    cond="__fish_seen_subcommand_from $cmd"
    header="# --- $cmd ---"
  fi
  body=$(_emit_fish_cmd_body "$cmd" "$cond")
  if [[ -n "$body" ]]; then
    printf '%s\n' "$header"
    printf '%s\n' "$body"
  fi
  return 0
}

# _emit_fish — print the complete fish completion script for brewmaster.
# Must be called after _spec_load.
# Globals (read): SPEC_CMDS, SPEC_CMD_DESC, SPEC_DEFAULT, SPEC_SUBS,
#   SPEC_ARGS, SPEC_FLAGS
# Stdout: the full fish completion script
# Return: 0
_emit_fish() {
  _emit_fish_header
  echo
  _emit_fish_preamble
  echo
  _emit_fish_no_subcommand
  echo
  _emit_fish_top_level
  echo
  _emit_fish_general_flags
  echo
  _emit_fish_cmd_section "$SPEC_DEFAULT" default

  local c sec
  for c in "${SPEC_CMDS[@]}"; do
    if [[ "$c" == "$SPEC_DEFAULT" ]]; then
      continue
    fi
    sec=$(_emit_fish_cmd_section "$c" normal)
    if [[ -n "$sec" ]]; then
      echo
      printf '%s\n' "$sec"
    fi
  done
  return 0
}

# --- entry point -------------------------------------------------------------
case "${1:-}" in
  bash|zsh|fish)
    _spec_load
    "_emit_$1" ;;
  *)
    echo "Usage: docs/gen-completions.sh <bash|zsh|fish>" >&2
    exit 1 ;;
esac
