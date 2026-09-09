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

  local commands="upgrade snapshot deps profile cleanup why bloat log report completion"
  local general="-v --verbose -V --version -h --help"
  local upgrade_flags="--patch --minor --major --level= --or-lower --allow-date -n --dry-run --formulae --casks --profile= -i --interactive --check-deps --risk-threshold= -y --yes"
  local snapshot_subflags="--label= -n --dry-run --force"
  local deps_subflags=""
  local profile_subflags=""
  local cleanup_flags="-n --dry-run -i --interactive --force"
  local why_flags=""
  local bloat_flags=""
  local log_flags="--package= --action= --since= --format="
  local report_flags=""
  local completion_flags="--shell="

  # First two non-flag words after "brewmaster" = command and sub-subcommand.
  cmd=""; sub=""
  for ((i = 1; i < COMP_CWORD; i++)); do
    w="${COMP_WORDS[i]}"
    [[ "$w" == -* ]] && continue
    if [[ -z "$cmd" ]]; then cmd="$w"
    elif [[ -z "$sub" ]]; then sub="$w"; fi
  done

  # "--flag value" (space-separated) completion.
  case "$prev" in
    --level) COMPREPLY=( $(compgen -W "patch minor major" -- "$cur") ); return ;;
    --profile) COMPREPLY=( $(compgen -W "$(_brewmaster_profiles)" -- "$cur") ); return ;;
    --package) COMPREPLY=( $(compgen -W "$(_brewmaster_packages)" -- "$cur") ); return ;;
    --action) COMPREPLY=( $(compgen -W "upgrade cleanup snapshot" -- "$cur") ); return ;;
    --format) COMPREPLY=( $(compgen -W "table json csv" -- "$cur") ); return ;;
    --shell) COMPREPLY=( $(compgen -W "bash zsh fish" -- "$cur") ); return ;;
    --risk-threshold|--label|--since) return ;;
  esac

  # "--flag=value" (no-space) completion.
  case "$cur" in
    --level=*) COMPREPLY=( $(compgen -W "patch minor major" -P "--level=" -- "${cur#*=}") ); return ;;
    --profile=*) COMPREPLY=( $(compgen -W "$(_brewmaster_profiles)" -P "--profile=" -- "${cur#*=}") ); return ;;
    --package=*) COMPREPLY=( $(compgen -W "$(_brewmaster_packages)" -P "--package=" -- "${cur#*=}") ); return ;;
    --action=*) COMPREPLY=( $(compgen -W "upgrade cleanup snapshot" -P "--action=" -- "${cur#*=}") ); return ;;
    --format=*) COMPREPLY=( $(compgen -W "table json csv" -P "--format=" -- "${cur#*=}") ); return ;;
    --shell=*) COMPREPLY=( $(compgen -W "bash zsh fish" -P "--shell=" -- "${cur#*=}") ); return ;;
  esac

  if [[ -z "$cmd" ]]; then
    if [[ "$cur" == -* ]]; then
      COMPREPLY=( $(compgen -W "$general $upgrade_flags" -- "$cur") )
    else
      COMPREPLY=( $(compgen -W "$commands $(_brewmaster_packages)" -- "$cur") )
    fi
    return
  fi

  case "$cmd" in
    upgrade)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$general $upgrade_flags" -- "$cur") )
      else
        COMPREPLY=( $(compgen -W "$(_brewmaster_packages)" -- "$cur") )
      fi
      ;;
    snapshot)
      if [[ -z "$sub" ]]; then
        COMPREPLY=( $(compgen -W "save list diff restore delete" -- "$cur") )
      elif [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$general $snapshot_subflags" -- "$cur") )
      fi
      ;;
    deps)
      if [[ -z "$sub" ]]; then
        COMPREPLY=( $(compgen -W "show" -- "$cur") )
      elif [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$general $deps_subflags" -- "$cur") )
      else
        case "$sub" in
          show) COMPREPLY=( $(compgen -W "$(_brewmaster_packages)" -- "$cur") ) ;;
        esac
      fi
      ;;
    profile)
      if [[ -z "$sub" ]]; then
        COMPREPLY=( $(compgen -W "list create edit diff validate" -- "$cur") )
      elif [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$general $profile_subflags" -- "$cur") )
      else
        case "$sub" in
          edit|diff) COMPREPLY=( $(compgen -W "$(_brewmaster_profiles)" -- "$cur") ) ;;
        esac
      fi
      ;;
    cleanup)
      COMPREPLY=( $(compgen -W "$general $cleanup_flags" -- "$cur") )
      ;;
    why)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$general $why_flags" -- "$cur") )
      else
        COMPREPLY=( $(compgen -W "$(_brewmaster_packages)" -- "$cur") )
      fi
      ;;
    bloat)
      COMPREPLY=( $(compgen -W "$general $bloat_flags" -- "$cur") )
      ;;
    log)
      COMPREPLY=( $(compgen -W "$general $log_flags" -- "$cur") )
      ;;
    report)
      COMPREPLY=( $(compgen -W "$general $report_flags" -- "$cur") )
      ;;
    completion)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$general $completion_flags" -- "$cur") )
      else
        COMPREPLY=( $(compgen -W "bash zsh fish" -- "$cur") )
      fi
      ;;
  esac
}

complete -o default -o bashdefault -F _brewmaster brewmaster
