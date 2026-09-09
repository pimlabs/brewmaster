# Fish completion for brewmaster.
#
# GENERATED FILE. Produced by docs/gen-completions.sh from
# lib/brewmaster/core/cli_spec.sh — do not edit by hand, regenerate instead.
#
# Installed by the Homebrew formula (fish_completion.install). From a git
# checkout: cp completions/brewmaster.fish (brew --prefix)/share/fish/vendor_completions.d/brewmaster.fish

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

function __fish_brewmaster_no_subcommand
    not __fish_seen_subcommand_from upgrade snapshot deps profile cleanup why bloat log report completion help
end

# --- Top-level subcommands (default command is "upgrade"; bare package names are also valid) ---
complete -c brewmaster -n '__fish_brewmaster_no_subcommand' -f -a 'upgrade' -d 'Selective upgrade by semver bump level'
complete -c brewmaster -n '__fish_brewmaster_no_subcommand' -f -a 'snapshot' -d 'Save, list, diff, restore, or delete snapshots'
complete -c brewmaster -n '__fish_brewmaster_no_subcommand' -f -a 'deps' -d 'Show dependency risk'
complete -c brewmaster -n '__fish_brewmaster_no_subcommand' -f -a 'profile' -d 'Manage named upgrade profiles'
complete -c brewmaster -n '__fish_brewmaster_no_subcommand' -f -a 'cleanup' -d 'Report orphan, stale, and pinned-old formulae'
complete -c brewmaster -n '__fish_brewmaster_no_subcommand' -f -a 'why' -d 'Explain why a formula is installed'
complete -c brewmaster -n '__fish_brewmaster_no_subcommand' -f -a 'bloat' -d 'Installed package summary and cleanup candidates'
complete -c brewmaster -n '__fish_brewmaster_no_subcommand' -f -a 'log' -d 'Show audit log entries'
complete -c brewmaster -n '__fish_brewmaster_no_subcommand' -f -a 'report' -d 'Machine health summary'
complete -c brewmaster -n '__fish_brewmaster_no_subcommand' -f -a 'completion' -d 'Completion status for your shell, or print a completion script'
complete -c brewmaster -n '__fish_brewmaster_no_subcommand' -f -a 'help' -d 'Show help for a command'
complete -c brewmaster -n '__fish_brewmaster_no_subcommand' -f -a '(__fish_brewmaster_packages)' -d 'package'

# --- General flags (every command) ---
complete -c brewmaster -f -s v -l verbose -d 'Verbose output'
complete -c brewmaster -f -s V -l version -d 'Print version and exit'
complete -c brewmaster -f -s h -l help -d 'Show this help'

# --- upgrade (and the default/no-subcommand case) ---
complete -c brewmaster -n '__fish_seen_subcommand_from upgrade; or __fish_brewmaster_no_subcommand' -f -l patch -d 'Apply patch bumps only'
complete -c brewmaster -n '__fish_seen_subcommand_from upgrade; or __fish_brewmaster_no_subcommand' -f -l minor -d 'Apply minor bumps only'
complete -c brewmaster -n '__fish_seen_subcommand_from upgrade; or __fish_brewmaster_no_subcommand' -f -l major -d 'Apply major bumps only'
complete -c brewmaster -n '__fish_seen_subcommand_from upgrade; or __fish_brewmaster_no_subcommand' -f -r -l level -a 'patch minor major' -d 'Bump level'
complete -c brewmaster -n '__fish_seen_subcommand_from upgrade; or __fish_brewmaster_no_subcommand' -f -l or-lower -d 'Make level inclusive (e.g. minor includes patch)'
complete -c brewmaster -n '__fish_seen_subcommand_from upgrade; or __fish_brewmaster_no_subcommand' -f -l allow-date -d 'Treat date versions as semver-like'
complete -c brewmaster -n '__fish_seen_subcommand_from upgrade; or __fish_brewmaster_no_subcommand' -f -s n -l dry-run -d 'Show the plan without executing'
complete -c brewmaster -n '__fish_seen_subcommand_from upgrade; or __fish_brewmaster_no_subcommand' -f -l formulae -d 'Formulae only'
complete -c brewmaster -n '__fish_seen_subcommand_from upgrade; or __fish_brewmaster_no_subcommand' -f -l casks -d 'Casks only'
complete -c brewmaster -n '__fish_seen_subcommand_from upgrade; or __fish_brewmaster_no_subcommand' -f -r -l profile -a '(__fish_brewmaster_profiles)' -d 'Filter/level from a named profile'
complete -c brewmaster -n '__fish_seen_subcommand_from upgrade; or __fish_brewmaster_no_subcommand' -f -s i -l interactive -d 'No effect (candidates are always reviewed)'
complete -c brewmaster -n '__fish_seen_subcommand_from upgrade; or __fish_brewmaster_no_subcommand' -f -l check-deps -d 'Risk-score each upgrade candidate'
complete -c brewmaster -n '__fish_seen_subcommand_from upgrade; or __fish_brewmaster_no_subcommand' -f -r -l risk-threshold -d 'High-risk cutoff (default 7)'
complete -c brewmaster -n '__fish_seen_subcommand_from upgrade; or __fish_brewmaster_no_subcommand' -f -s y -l yes -d 'Auto-confirm medium-risk packages and skip the review'
complete -c brewmaster -n '__fish_seen_subcommand_from upgrade; or __fish_brewmaster_no_subcommand' -f -a '(__fish_brewmaster_packages)' -d 'package'

# --- snapshot ---
complete -c brewmaster -n '__fish_seen_subcommand_from snapshot; and not __fish_seen_subcommand_from save list diff restore delete' -f -a 'save' -d 'Save current state to a snapshot'
complete -c brewmaster -n '__fish_seen_subcommand_from snapshot; and not __fish_seen_subcommand_from save list diff restore delete' -f -a 'list' -d 'List all snapshots'
complete -c brewmaster -n '__fish_seen_subcommand_from snapshot; and not __fish_seen_subcommand_from save list diff restore delete' -f -a 'diff' -d 'Show packages changed since a snapshot'
complete -c brewmaster -n '__fish_seen_subcommand_from snapshot; and not __fish_seen_subcommand_from save list diff restore delete' -f -a 'restore' -d 'Restore packages to a snapshot state'
complete -c brewmaster -n '__fish_seen_subcommand_from snapshot; and not __fish_seen_subcommand_from save list diff restore delete' -f -a 'delete' -d 'Delete a snapshot'
complete -c brewmaster -n '__fish_seen_subcommand_from snapshot; and __fish_seen_subcommand_from save' -f -r -l label -d 'Label for the snapshot'
complete -c brewmaster -n '__fish_seen_subcommand_from snapshot; and __fish_seen_subcommand_from restore' -f -s n -l dry-run -d 'Show the plan without executing'
complete -c brewmaster -n '__fish_seen_subcommand_from snapshot; and __fish_seen_subcommand_from delete' -f -l force -d 'Skip the y/N confirmation'

# --- deps ---
complete -c brewmaster -n '__fish_seen_subcommand_from deps; and not __fish_seen_subcommand_from show' -f -a 'show' -d 'Show dependency risk for a package, or list all outdated packages by risk'
complete -c brewmaster -n '__fish_seen_subcommand_from deps; and __fish_seen_subcommand_from show' -f -a '(__fish_brewmaster_packages)' -d 'package'

# --- profile ---
complete -c brewmaster -n '__fish_seen_subcommand_from profile; and not __fish_seen_subcommand_from list create edit diff validate' -f -a 'list' -d 'List configured profiles'
complete -c brewmaster -n '__fish_seen_subcommand_from profile; and not __fish_seen_subcommand_from list create edit diff validate' -f -a 'create' -d 'Interactive wizard to add a new profile'
complete -c brewmaster -n '__fish_seen_subcommand_from profile; and not __fish_seen_subcommand_from list create edit diff validate' -f -a 'edit' -d 'Open profiles.toml in $EDITOR'
complete -c brewmaster -n '__fish_seen_subcommand_from profile; and not __fish_seen_subcommand_from list create edit diff validate' -f -a 'diff' -d 'Compare include lists between two profiles'
complete -c brewmaster -n '__fish_seen_subcommand_from profile; and not __fish_seen_subcommand_from list create edit diff validate' -f -a 'validate' -d 'Check profiles.toml for errors'
complete -c brewmaster -n '__fish_seen_subcommand_from profile; and __fish_seen_subcommand_from edit' -f -a '(__fish_brewmaster_profiles)' -d 'profile'
complete -c brewmaster -n '__fish_seen_subcommand_from profile; and __fish_seen_subcommand_from diff' -f -a '(__fish_brewmaster_profiles)' -d 'profile'

# --- cleanup ---
complete -c brewmaster -n '__fish_seen_subcommand_from cleanup' -f -s n -l dry-run -d 'Read-only report (default)'
complete -c brewmaster -n '__fish_seen_subcommand_from cleanup' -f -s i -l interactive -d 'fzf multi-select packages to remove'
complete -c brewmaster -n '__fish_seen_subcommand_from cleanup' -f -l force -d 'Auto-remove high-confidence orphans'

# --- why ---
complete -c brewmaster -n '__fish_seen_subcommand_from why' -f -a '(__fish_brewmaster_packages)' -d 'package'

# --- log ---
complete -c brewmaster -n '__fish_seen_subcommand_from log' -f -r -l package -a '(__fish_brewmaster_packages)' -d 'Filter by package name'
complete -c brewmaster -n '__fish_seen_subcommand_from log' -f -r -l action -a 'upgrade cleanup snapshot' -d 'Filter by action'
complete -c brewmaster -n '__fish_seen_subcommand_from log' -f -r -l since -d 'Time window, e.g. 7d, 24h, 2w'
complete -c brewmaster -n '__fish_seen_subcommand_from log' -f -r -l format -a 'table json csv' -d 'Output format'

# --- completion ---
complete -c brewmaster -n '__fish_seen_subcommand_from completion' -f -r -l shell -a 'bash zsh fish' -d 'Report for this shell instead of $SHELL'
complete -c brewmaster -n '__fish_seen_subcommand_from completion; and not __fish_seen_subcommand_from bash zsh fish' -f -a 'bash zsh fish' -d 'Print this shell\'s completion script'

# --- help ---
complete -c brewmaster -n '__fish_seen_subcommand_from help; and test (count (commandline -opc)) -eq 2' -f -a 'upgrade snapshot deps profile cleanup why bloat log report completion help' -d 'command'
