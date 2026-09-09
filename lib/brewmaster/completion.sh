#!/usr/bin/env bash
# brewmaster: shell completion status and printing (`brewmaster completion`).
# Sourced by bin/brewmaster; defines functions only. Read-only by design:
# nothing here writes to rc files or completion directories.

# _completion_shell — resolve which shell the command is about.
# Args:    $1 explicit shell name, or "" to derive it from $SHELL
# Stdout:  bash | zsh | fish
# Return:  0, or 1 (with a stderr message) for an unsupported shell
_completion_shell() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then name="${SHELL##*/}"; fi
  case "$name" in
    bash|zsh|fish) echo "$name"; return 0 ;;
    *)
      echo "Error: unsupported shell '${name}'. Supported: bash, zsh, fish (pick one with --shell=NAME)." >&2
      return 1 ;;
  esac
}

# _completion_tilde — show a path under $HOME as ~/..., for the report.
# Args:    $1 path
# Stdout:  the path, with a leading $HOME replaced by ~
# Return:  0
_completion_tilde() {
  case "$1" in
    "$HOME"/*) echo "~${1#"$HOME"}" ;;
    *)         echo "$1" ;;
  esac
}

# _completion_script_path — locate a shell's completion script: the git
# checkout's completions/ (two levels above LIB_DIR) first, then the tap
# formula's install targets under `brew --prefix`, which is only invoked
# when the checkout layout misses.
# Args:    $1 shell (bash|zsh|fish)
# Stdout:  the first readable path, normalized
# Return:  0 if found, 1 otherwise
# Globals: LIB_DIR (read)
_completion_script_path() {
  local shell="$1" candidate prefix
  candidate="$LIB_DIR/../../completions/brewmaster.${shell}"
  logv "completion: trying $candidate"
  if [[ -r "$candidate" ]]; then
    echo "$(cd -P "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"
    return 0
  fi
  prefix="$(brew --prefix 2>/dev/null)" || prefix=""
  if [[ -z "$prefix" ]]; then logv "completion: brew --prefix unavailable"; return 1; fi
  case "$shell" in
    bash) candidate="$prefix/etc/bash_completion.d/brewmaster" ;;
    zsh)  candidate="$prefix/share/zsh/site-functions/_brewmaster" ;;
    fish) candidate="$prefix/share/fish/vendor_completions.d/brewmaster.fish" ;;
  esac
  logv "completion: trying $candidate"
  if [[ -r "$candidate" ]]; then echo "$candidate"; return 0; fi
  return 1
}

# _completion_rc_files — the rc files the "configured" heuristic scans.
# Args:    $1 shell (bash|zsh)
# Stdout:  one path per line (fish: nothing)
# Return:  0
_completion_rc_files() {
  case "$1" in
    zsh)  printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc" "${ZDOTDIR:-$HOME}/.zprofile" "${ZDOTDIR:-$HOME}/.zshenv" ;;
    bash) printf '%s\n' "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile" ;;
  esac
}

# _completion_rc_mentions — the "configured" heuristic. brewmaster runs
# under bash and cannot see the user's live zsh FPATH or bash completion
# state, so it reports whether the shell's rc files mention a pattern.
# Args:    $1 shell (bash|zsh); $2 extended regex
# Stdout:  the first matching rc file, with $HOME shown as ~
# Return:  0 if a readable rc file matches, 1 otherwise
_completion_rc_mentions() {
  local shell="$1" pattern="$2" f
  while IFS= read -r f; do
    [[ -n "$f" && -r "$f" ]] || continue
    if grep -qE "$pattern" "$f" 2>/dev/null; then
      _completion_tilde "$f"
      return 0
    fi
  done < <(_completion_rc_files "$shell")
  return 1
}

# _completion_snippet — the shell snippet that makes a shell load
# Homebrew's completions; the same three README documents.
# Args:    $1 shell
# Stdout:  snippet text
# Return:  0
_completion_snippet() {
  case "$1" in
    zsh) cat <<'SNIP'
Add to ~/.zshrc before compinit, then open a new shell:

  if type brew &>/dev/null; then
    FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"
    autoload -Uz compinit && compinit
  fi
SNIP
    ;;
    bash) cat <<'SNIP'
Install bash-completion@2, add to ~/.bash_profile, then open a new shell:

  [[ -r "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]] && \
    . "$(brew --prefix)/etc/profile.d/bash_completion.sh"
SNIP
    ;;
    fish) echo "fish loads vendor_completions.d on its own; open a new shell." ;;
  esac
}

# completion_main — `brewmaster completion [shell]`. With a shell argument,
# print that shell's completion script (for `source <(...)`). Without one,
# report status for $SHELL, or --shell=NAME: the script's path, whether the
# rc files reference Homebrew's completion setup, and the snippet to add
# when they do not.
# Globals (read): COMPLETION_SHELL (positional shell), COMPLETION_TARGET
#                 (--shell=NAME), LIB_DIR, COLOR_MUTED, COLOR_RESET
# Stdout:  the script, or the status report
# Return:  0 when the script is found; 1 when it is not or the shell is
#          unsupported. The "configured" heuristic never changes the code.
completion_main() {
  local shell path
  if [[ -n "${COMPLETION_SHELL:-}" ]]; then
    shell="$(_completion_shell "$COMPLETION_SHELL")" || return 1
    if path="$(_completion_script_path "$shell")"; then
      cat "$path"
      return 0
    fi
    echo "Error: no ${shell} completion script found. Install with: brew install pimlabs/tap/brewmaster" >&2
    return 1
  fi

  shell="$(_completion_shell "${COMPLETION_TARGET:-}")" || return 1
  local origin='from $SHELL'
  if [[ -n "${COMPLETION_TARGET:-}" ]]; then origin='from --shell'; fi
  ui_table_row 12 "Shell:" "" "${shell} (${origin})"

  local found=true
  if path="$(_completion_script_path "$shell")"; then
    ui_table_row 12 "Script:" "" "$path"
  else
    found=false
    ui_table_row 12 "Script:" "" "not found"
  fi

  local configured=true rc="" scanned="" f
  case "$shell" in
    zsh)  rc="$(_completion_rc_mentions zsh 'site-functions|brew shellenv')" || configured=false ;;
    bash) rc="$(_completion_rc_mentions bash 'bash_completion')" || configured=false ;;
  esac
  if [[ "$shell" == fish ]]; then
    ui_table_row 12 "Configured:" "" "fish loads vendor_completions.d itself"
  else
    if $configured; then
      ui_table_row 12 "Configured:" "" "${rc} references Homebrew's completion setup"
    else
      while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        scanned="${scanned:+$scanned, }$(_completion_tilde "$f")"
      done < <(_completion_rc_files "$shell")
      ui_table_row 12 "Configured:" "" "no reference in ${scanned}"
    fi
    echo "${COLOR_MUTED}(Configured is read from those files; brewmaster cannot see the live shell.)${COLOR_RESET}"
  fi
  echo

  if ! $found; then
    echo "Completion is not installed. Install with: brew install pimlabs/tap/brewmaster"
    echo "From a git checkout: source <(bin/brewmaster completion ${shell})"
    return 1
  fi
  if $configured; then
    echo "Completion is installed and your shell is set up to load it."
    echo "Open a new shell if it is not working yet."
    return 0
  fi
  _completion_snippet "$shell"
  return 0
}
