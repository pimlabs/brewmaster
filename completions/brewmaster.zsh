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

_brewmaster_commands() {
  local -a commands=(
    'upgrade:selective upgrade by semver bump level'
    'snapshot:save, list, diff, restore, or delete snapshots'
    'deps:show dependency risk'
    'profile:manage named upgrade profiles'
    'cleanup:report orphan, stale, and pinned-old formulae'
    'why:explain why a formula is installed'
    'bloat:installed package summary and cleanup candidates'
    'log:show audit log entries'
    'report:machine health summary'
    'completion:completion status for your shell, or print a completion script'
  )
  _describe -t commands 'command' commands
  _brewmaster_packages
}

_brewmaster_upgrade() {
  _arguments \
    '(--minor --major --level)--patch[apply patch bumps only]' \
    '(--patch --major --level)--minor[apply minor bumps only]' \
    '(--patch --minor --level)--major[apply major bumps only]' \
    '(--patch --minor --major)--level=[bump level]:level:(patch minor major)' \
    '--or-lower[make level inclusive (e.g. minor includes patch)]' \
    '--allow-date[treat date versions as semver-like]' \
    '(-n --dry-run)'{-n,--dry-run}'[show the plan without executing]' \
    '(--casks)--formulae[formulae only]' \
    '(--formulae)--casks[casks only]' \
    '--profile=[filter/level from a named profile]:profile:_brewmaster_profiles' \
    '(-i --interactive)'{-i,--interactive}'[no effect (candidates are always reviewed)]' \
    '--check-deps[risk-score each upgrade candidate]' \
    '--risk-threshold=[high-risk cutoff (default 7)]:risk-threshold:' \
    '(-y --yes)'{-y,--yes}'[auto-confirm medium-risk packages and skip the review]' \
    '(-v --verbose)'{-v,--verbose}'[verbose output]' \
    '(-V --version)'{-V,--version}'[print version and exit]' \
    '(-h --help)'{-h,--help}'[show this help]' \
    '*:package:_brewmaster_packages'
}

_brewmaster_snapshot() {
  local curcontext="$curcontext" state line
  _arguments -C -A '-*' \
    '(-v --verbose)'{-v,--verbose}'[verbose output]' \
    '(-V --version)'{-V,--version}'[print version and exit]' \
    '(-h --help)'{-h,--help}'[show this help]' \
    '1: :->subcommand' \
    '*::arg:->subargs'

  case $state in
    subcommand)
      local -a subcmds=(
        'save:save current state to a snapshot'
        'list:list all snapshots'
        'diff:show packages changed since a snapshot'
        'restore:restore packages to a snapshot state'
        'delete:delete a snapshot'
      )
      _describe -t subcommands 'snapshot subcommand' subcmds
      ;;
    subargs)
      case $line[1] in
        save)
          _arguments \
            '--label=[label for the snapshot]:label:' \
            '(-v --verbose)'{-v,--verbose}'[verbose output]' \
            '(-V --version)'{-V,--version}'[print version and exit]' \
            '(-h --help)'{-h,--help}'[show this help]'
          ;;
        list)
          _arguments \
            '(-v --verbose)'{-v,--verbose}'[verbose output]' \
            '(-V --version)'{-V,--version}'[print version and exit]' \
            '(-h --help)'{-h,--help}'[show this help]'
          ;;
        diff)
          _arguments \
            '(-v --verbose)'{-v,--verbose}'[verbose output]' \
            '(-V --version)'{-V,--version}'[print version and exit]' \
            '(-h --help)'{-h,--help}'[show this help]' \
            '1:snapshot:_brewmaster_snapshot_refs'
          ;;
        restore)
          _arguments \
            '(-n --dry-run)'{-n,--dry-run}'[show the plan without executing]' \
            '(-v --verbose)'{-v,--verbose}'[verbose output]' \
            '(-V --version)'{-V,--version}'[print version and exit]' \
            '(-h --help)'{-h,--help}'[show this help]' \
            '1:snapshot:_brewmaster_snapshot_refs'
          ;;
        delete)
          _arguments \
            '--force[skip the y/N confirmation]' \
            '(-v --verbose)'{-v,--verbose}'[verbose output]' \
            '(-V --version)'{-V,--version}'[print version and exit]' \
            '(-h --help)'{-h,--help}'[show this help]' \
            '1:snapshot:_brewmaster_snapshot_refs'
          ;;
      esac
      ;;
  esac
}

_brewmaster_deps() {
  local curcontext="$curcontext" state line
  _arguments -C -A '-*' \
    '(-v --verbose)'{-v,--verbose}'[verbose output]' \
    '(-V --version)'{-V,--version}'[print version and exit]' \
    '(-h --help)'{-h,--help}'[show this help]' \
    '1: :->subcommand' \
    '*::arg:->subargs'

  case $state in
    subcommand)
      local -a subcmds=(
        'show:show dependency risk for a package, or list all outdated packages by risk'
      )
      _describe -t subcommands 'deps subcommand' subcmds
      ;;
    subargs)
      case $line[1] in
        show)
          _arguments \
            '(-v --verbose)'{-v,--verbose}'[verbose output]' \
            '(-V --version)'{-V,--version}'[print version and exit]' \
            '(-h --help)'{-h,--help}'[show this help]' \
            '1:package:_brewmaster_packages'
          ;;
      esac
      ;;
  esac
}

_brewmaster_profile() {
  local curcontext="$curcontext" state line
  _arguments -C -A '-*' \
    '(-v --verbose)'{-v,--verbose}'[verbose output]' \
    '(-V --version)'{-V,--version}'[print version and exit]' \
    '(-h --help)'{-h,--help}'[show this help]' \
    '1: :->subcommand' \
    '*::arg:->subargs'

  case $state in
    subcommand)
      local -a subcmds=(
        'list:list configured profiles'
        'create:interactive wizard to add a new profile'
        'edit:open profiles.toml in $EDITOR'
        'diff:compare include lists between two profiles'
        'validate:check profiles.toml for errors'
      )
      _describe -t subcommands 'profile subcommand' subcmds
      ;;
    subargs)
      case $line[1] in
        list)
          _arguments \
            '(-v --verbose)'{-v,--verbose}'[verbose output]' \
            '(-V --version)'{-V,--version}'[print version and exit]' \
            '(-h --help)'{-h,--help}'[show this help]'
          ;;
        create)
          _arguments \
            '(-v --verbose)'{-v,--verbose}'[verbose output]' \
            '(-V --version)'{-V,--version}'[print version and exit]' \
            '(-h --help)'{-h,--help}'[show this help]'
          ;;
        edit)
          _arguments \
            '(-v --verbose)'{-v,--verbose}'[verbose output]' \
            '(-V --version)'{-V,--version}'[print version and exit]' \
            '(-h --help)'{-h,--help}'[show this help]' \
            '1:profile:_brewmaster_profiles'
          ;;
        diff)
          _arguments \
            '(-v --verbose)'{-v,--verbose}'[verbose output]' \
            '(-V --version)'{-V,--version}'[print version and exit]' \
            '(-h --help)'{-h,--help}'[show this help]' \
            '1:profile:_brewmaster_profiles' \
            '2:profile:_brewmaster_profiles'
          ;;
        validate)
          _arguments \
            '(-v --verbose)'{-v,--verbose}'[verbose output]' \
            '(-V --version)'{-V,--version}'[print version and exit]' \
            '(-h --help)'{-h,--help}'[show this help]'
          ;;
      esac
      ;;
  esac
}

_brewmaster_cleanup() {
  _arguments \
    '(-n --dry-run)'{-n,--dry-run}'[read-only report (default)]' \
    '(-i --interactive)'{-i,--interactive}'[fzf multi-select packages to remove]' \
    '--force[auto-remove high-confidence orphans]' \
    '(-v --verbose)'{-v,--verbose}'[verbose output]' \
    '(-V --version)'{-V,--version}'[print version and exit]' \
    '(-h --help)'{-h,--help}'[show this help]'
}

_brewmaster_why() {
  _arguments \
    '(-v --verbose)'{-v,--verbose}'[verbose output]' \
    '(-V --version)'{-V,--version}'[print version and exit]' \
    '(-h --help)'{-h,--help}'[show this help]' \
    '1:package:_brewmaster_packages'
}

_brewmaster_bloat() {
  _arguments \
    '(-v --verbose)'{-v,--verbose}'[verbose output]' \
    '(-V --version)'{-V,--version}'[print version and exit]' \
    '(-h --help)'{-h,--help}'[show this help]'
}

_brewmaster_log() {
  _arguments \
    '--package=[filter by package name]:package:_brewmaster_packages' \
    '--action=[filter by action]:action:(upgrade cleanup snapshot)' \
    '--since=[time window, e.g. 7d, 24h, 2w]:since:' \
    '--format=[output format]:format:(table json csv)' \
    '(-v --verbose)'{-v,--verbose}'[verbose output]' \
    '(-V --version)'{-V,--version}'[print version and exit]' \
    '(-h --help)'{-h,--help}'[show this help]'
}

_brewmaster_report() {
  _arguments \
    '(-v --verbose)'{-v,--verbose}'[verbose output]' \
    '(-V --version)'{-V,--version}'[print version and exit]' \
    '(-h --help)'{-h,--help}'[show this help]'
}

_brewmaster_completion() {
  _arguments \
    '--shell=[report for this shell instead of $SHELL]:shell:(bash zsh fish)' \
    '(-v --verbose)'{-v,--verbose}'[verbose output]' \
    '(-V --version)'{-V,--version}'[print version and exit]' \
    '(-h --help)'{-h,--help}'[show this help]' \
    '1:shell:(bash zsh fish)'
}

_brewmaster() {
  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C -A '-*' \
    '(--minor --major --level)--patch[apply patch bumps only]' \
    '(--patch --major --level)--minor[apply minor bumps only]' \
    '(--patch --minor --level)--major[apply major bumps only]' \
    '(--patch --minor --major)--level=[bump level]:level:(patch minor major)' \
    '--or-lower[make level inclusive (e.g. minor includes patch)]' \
    '--allow-date[treat date versions as semver-like]' \
    '(-n --dry-run)'{-n,--dry-run}'[show the plan without executing]' \
    '(--casks)--formulae[formulae only]' \
    '(--formulae)--casks[casks only]' \
    '--profile=[filter/level from a named profile]:profile:_brewmaster_profiles' \
    '(-i --interactive)'{-i,--interactive}'[no effect (candidates are always reviewed)]' \
    '--check-deps[risk-score each upgrade candidate]' \
    '--risk-threshold=[high-risk cutoff (default 7)]:risk-threshold:' \
    '(-y --yes)'{-y,--yes}'[auto-confirm medium-risk packages and skip the review]' \
    '(-v --verbose)'{-v,--verbose}'[verbose output]' \
    '(-V --version)'{-V,--version}'[print version and exit]' \
    '(-h --help)'{-h,--help}'[show this help]' \
    '1: :_brewmaster_commands' \
    '*::arg:->args'

  case $state in
    args)
      case $line[1] in
        upgrade)      _brewmaster_upgrade ;;
        snapshot)     _brewmaster_snapshot ;;
        deps)         _brewmaster_deps ;;
        profile)      _brewmaster_profile ;;
        cleanup)      _brewmaster_cleanup ;;
        why)          _brewmaster_why ;;
        bloat)        _brewmaster_bloat ;;
        log)          _brewmaster_log ;;
        report)       _brewmaster_report ;;
        completion)   _brewmaster_completion ;;
        *)            _brewmaster_upgrade ;;
      esac
      ;;
  esac
}

_brewmaster "$@"
