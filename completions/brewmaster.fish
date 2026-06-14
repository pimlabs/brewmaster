# Fish completion for brewmaster.
#
# Manual install (until the Homebrew formula installs this automatically):
#   cp completions/brewmaster.fish (brew --prefix)/share/fish/vendor_completions.d/brewmaster.fish

function __fish_brewmaster_packages
    brew list --formula --cask 2>/dev/null
end

function __fish_brewmaster_profiles
    set -l conf "$HOME/.config/brewmaster/profiles.toml"
    test -n "$XDG_CONFIG_HOME"; and set conf "$XDG_CONFIG_HOME/brewmaster/profiles.toml"
    test -f "$conf"; and string match -r '^\[profiles\.[^]]+\]' < "$conf" | string replace -r '^\[profiles\.(.*)\]$' '$1'
end

function __fish_brewmaster_no_subcommand
    not __fish_seen_subcommand_from upgrade snapshot deps profile cleanup why bloat log report
end

# --- Top-level subcommands (default command is "upgrade"; bare package names are also valid) ---
complete -c brewmaster -n __fish_brewmaster_no_subcommand -f -a upgrade -d 'Selective upgrade by semver bump level'
complete -c brewmaster -n __fish_brewmaster_no_subcommand -f -a snapshot -d 'Save, list, diff, restore, or delete snapshots'
complete -c brewmaster -n __fish_brewmaster_no_subcommand -f -a deps -d 'Show dependency risk'
complete -c brewmaster -n __fish_brewmaster_no_subcommand -f -a profile -d 'Manage named upgrade profiles'
complete -c brewmaster -n __fish_brewmaster_no_subcommand -f -a cleanup -d 'Report orphan/stale/pinned-old formulae'
complete -c brewmaster -n __fish_brewmaster_no_subcommand -f -a why -d 'Explain why a formula is installed'
complete -c brewmaster -n __fish_brewmaster_no_subcommand -f -a bloat -d 'Installed package summary'
complete -c brewmaster -n __fish_brewmaster_no_subcommand -f -a log -d 'Show audit log entries'
complete -c brewmaster -n __fish_brewmaster_no_subcommand -f -a report -d 'Machine health summary'
complete -c brewmaster -n __fish_brewmaster_no_subcommand -f -a '(__fish_brewmaster_packages)'

# --- General flags (every command) ---
complete -c brewmaster -f -s v -l verbose -d 'Verbose output'
complete -c brewmaster -f -s V -l version -d 'Print version and exit'
complete -c brewmaster -f -s h -l help -d 'Show help'

# --- upgrade (and the default/no-subcommand case) ---
set -l __bm_upgrade '__fish_seen_subcommand_from upgrade; or __fish_brewmaster_no_subcommand'
complete -c brewmaster -n "$__bm_upgrade" -f -l patch -d 'Apply patch bumps only'
complete -c brewmaster -n "$__bm_upgrade" -f -l minor -d 'Apply minor bumps only'
complete -c brewmaster -n "$__bm_upgrade" -f -l major -d 'Apply major bumps only'
complete -c brewmaster -n "$__bm_upgrade" -f -l level -a 'patch minor major' -d 'Bump level'
complete -c brewmaster -n "$__bm_upgrade" -f -l or-lower -d 'Make level inclusive (e.g. minor includes patch)'
complete -c brewmaster -n "$__bm_upgrade" -f -l allow-date -d 'Treat date versions as semver-like'
complete -c brewmaster -n "$__bm_upgrade" -f -s n -l dry-run -d 'Show plan without executing'
complete -c brewmaster -n "$__bm_upgrade" -f -l formulae -d 'Formulae only'
complete -c brewmaster -n "$__bm_upgrade" -f -l casks -d 'Casks only'
complete -c brewmaster -n "$__bm_upgrade" -f -l profile -a '(__fish_brewmaster_profiles)' -d 'Filter/level from a named profile'
complete -c brewmaster -n "$__bm_upgrade" -f -s i -l interactive -d 'fzf multi-select among candidates'
complete -c brewmaster -n "$__bm_upgrade" -f -l check-deps -d 'Risk-score each upgrade candidate'
complete -c brewmaster -n "$__bm_upgrade" -f -l risk-threshold -d 'High-risk cutoff (default 7)'
complete -c brewmaster -n "$__bm_upgrade" -f -s y -l yes -d 'Auto-confirm medium-risk packages'
complete -c brewmaster -n "$__bm_upgrade" -f -a '(__fish_brewmaster_packages)'

# --- snapshot ---
set -l __bm_snapshot_sub 'not __fish_seen_subcommand_from save list diff restore delete'
complete -c brewmaster -n "__fish_seen_subcommand_from snapshot; and $__bm_snapshot_sub" -f -a save -d 'Save current state to a snapshot'
complete -c brewmaster -n "__fish_seen_subcommand_from snapshot; and $__bm_snapshot_sub" -f -a list -d 'List all snapshots'
complete -c brewmaster -n "__fish_seen_subcommand_from snapshot; and $__bm_snapshot_sub" -f -a diff -d 'Show packages changed since a snapshot'
complete -c brewmaster -n "__fish_seen_subcommand_from snapshot; and $__bm_snapshot_sub" -f -a restore -d 'Restore packages to a snapshot state'
complete -c brewmaster -n "__fish_seen_subcommand_from snapshot; and $__bm_snapshot_sub" -f -a delete -d 'Delete a snapshot'

complete -c brewmaster -n '__fish_seen_subcommand_from snapshot; and __fish_seen_subcommand_from save' -f -l label -d 'Label for the snapshot'
complete -c brewmaster -n '__fish_seen_subcommand_from snapshot; and __fish_seen_subcommand_from restore' -f -s n -l dry-run -d 'Show plan without executing'
complete -c brewmaster -n '__fish_seen_subcommand_from snapshot; and __fish_seen_subcommand_from delete' -f -l force -d 'Skip the y/N confirmation'

# --- deps ---
complete -c brewmaster -n '__fish_seen_subcommand_from deps; and not __fish_seen_subcommand_from show' -f -a show -d 'Show dependency risk for a package'
complete -c brewmaster -n '__fish_seen_subcommand_from deps; and __fish_seen_subcommand_from show' -f -a '(__fish_brewmaster_packages)'

# --- profile ---
set -l __bm_profile_sub 'not __fish_seen_subcommand_from list create edit diff validate'
complete -c brewmaster -n "__fish_seen_subcommand_from profile; and $__bm_profile_sub" -f -a list -d 'List configured profiles'
complete -c brewmaster -n "__fish_seen_subcommand_from profile; and $__bm_profile_sub" -f -a create -d 'Interactive wizard to add a new profile'
complete -c brewmaster -n "__fish_seen_subcommand_from profile; and $__bm_profile_sub" -f -a edit -d 'Open profiles.toml in $EDITOR'
complete -c brewmaster -n "__fish_seen_subcommand_from profile; and $__bm_profile_sub" -f -a diff -d 'Compare include lists between two profiles'
complete -c brewmaster -n "__fish_seen_subcommand_from profile; and $__bm_profile_sub" -f -a validate -d 'Check profiles.toml for errors'

complete -c brewmaster -n '__fish_seen_subcommand_from profile; and __fish_seen_subcommand_from edit diff' -f -a '(__fish_brewmaster_profiles)'

# --- cleanup ---
complete -c brewmaster -n '__fish_seen_subcommand_from cleanup' -f -s n -l dry-run -d 'Read-only report (default)'
complete -c brewmaster -n '__fish_seen_subcommand_from cleanup' -f -s i -l interactive -d 'fzf multi-select packages to remove'
complete -c brewmaster -n '__fish_seen_subcommand_from cleanup' -f -l force -d 'Auto-remove high-confidence orphans'

# --- why ---
complete -c brewmaster -n '__fish_seen_subcommand_from why' -f -a '(__fish_brewmaster_packages)'

# --- log ---
complete -c brewmaster -n '__fish_seen_subcommand_from log' -f -l package -a '(__fish_brewmaster_packages)' -d 'Filter by package name'
complete -c brewmaster -n '__fish_seen_subcommand_from log' -f -l action -a 'upgrade cleanup snapshot' -d 'Filter by action'
complete -c brewmaster -n '__fish_seen_subcommand_from log' -f -l since -d 'Time window, e.g. 7d, 24h, 2w'
complete -c brewmaster -n '__fish_seen_subcommand_from log' -f -l format -a 'table json csv' -d 'Output format'
