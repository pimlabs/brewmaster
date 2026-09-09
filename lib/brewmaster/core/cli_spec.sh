#!/usr/bin/env bash
# brewmaster core: the machine-readable CLI surface — every command,
# sub-subcommand, positional and flag, with descriptions. Single source of
# truth for the generated shell completions (docs/gen-completions.sh) and
# for the drift tests that hold bin/brewmaster's parser and help_data.sh
# to the same list. Sourced by the generator and by tests; defines
# functions only.
#
# Line grammar (fields separated by "|", one record per line, "#" comments):
#
#   cmd|<name>|<description>[|default]
#       A top-level command. "default" marks the command that runs when
#       none is given (its flags and positionals are valid at top level).
#   sub|<cmd>|<name>|<description>
#       A sub-subcommand (brewmaster <cmd> <name>).
#   arg|<scope>|<position>|<type>|<label>
#       A positional. scope = <cmd> or <cmd>.<sub>; position = 1, 2 or *
#       (repeatable); type = package | profile | snapshot | shell.
#   flag|<scope>|<names>|<value>|<description>[|excl=<group>]
#       A flag. scope = global | <cmd> | <cmd>.<sub>; names = comma-separated
#       spellings (-n,--dry-run); value = "" for a boolean flag, a
#       space-separated enum (patch minor major), @package / @profile for a
#       dynamic completer, or a placeholder word (N, TEXT) for a free value
#       that is not completed. excl= names a mutually exclusive group.

# _cli_spec — emit the CLI surface, one record per line.
# Args:   none
# Stdout: records (see the grammar above), comments and blank lines stripped
# Return: 0
_cli_spec() {
  grep -vE '^\s*(#|$)' <<'SPEC'
cmd|upgrade|Selective upgrade by semver bump level|default
cmd|snapshot|Save, list, diff, restore, or delete snapshots
cmd|deps|Show dependency risk
cmd|profile|Manage named upgrade profiles
cmd|cleanup|Report orphan, stale, and pinned-old formulae
cmd|why|Explain why a formula is installed
cmd|bloat|Installed package summary and cleanup candidates
cmd|log|Show audit log entries
cmd|report|Machine health summary
cmd|completion|Completion status for your shell, or print a completion script

sub|snapshot|save|Save current state to a snapshot
sub|snapshot|list|List all snapshots
sub|snapshot|diff|Show packages changed since a snapshot
sub|snapshot|restore|Restore packages to a snapshot state
sub|snapshot|delete|Delete a snapshot
sub|deps|show|Show dependency risk for a package, or list all outdated packages by risk
sub|profile|list|List configured profiles
sub|profile|create|Interactive wizard to add a new profile
sub|profile|edit|Open profiles.toml in $EDITOR
sub|profile|diff|Compare include lists between two profiles
sub|profile|validate|Check profiles.toml for errors

arg|upgrade|*|package|package
arg|snapshot.diff|1|snapshot|snapshot
arg|snapshot.restore|1|snapshot|snapshot
arg|snapshot.delete|1|snapshot|snapshot
arg|deps.show|1|package|package
arg|profile.edit|1|profile|profile
arg|profile.diff|1|profile|profile
arg|profile.diff|2|profile|profile
arg|why|1|package|package
arg|completion|1|shell|shell

flag|global|-v,--verbose||Verbose output
flag|global|-V,--version||Print version and exit
flag|global|-h,--help||Show this help

flag|upgrade|--patch||Apply patch bumps only|excl=level
flag|upgrade|--minor||Apply minor bumps only|excl=level
flag|upgrade|--major||Apply major bumps only|excl=level
flag|upgrade|--level|patch minor major|Bump level|excl=level
flag|upgrade|--or-lower||Make level inclusive (e.g. minor includes patch)
flag|upgrade|--allow-date||Treat date versions as semver-like
flag|upgrade|-n,--dry-run||Show the plan without executing
flag|upgrade|--formulae||Formulae only|excl=kind
flag|upgrade|--casks||Casks only|excl=kind
flag|upgrade|--profile|@profile|Filter/level from a named profile
flag|upgrade|-i,--interactive||No effect (candidates are always reviewed)
flag|upgrade|--check-deps||Risk-score each upgrade candidate
flag|upgrade|--risk-threshold|N|High-risk cutoff (default 7)
flag|upgrade|-y,--yes||Auto-confirm medium-risk packages and skip the review

flag|snapshot.save|--label|TEXT|Label for the snapshot
flag|snapshot.restore|-n,--dry-run||Show the plan without executing
flag|snapshot.delete|--force||Skip the y/N confirmation

flag|cleanup|-n,--dry-run||Read-only report (default)
flag|cleanup|-i,--interactive||fzf multi-select packages to remove
flag|cleanup|--force||Auto-remove high-confidence orphans

flag|log|--package|@package|Filter by package name
flag|log|--action|upgrade cleanup snapshot|Filter by action
flag|log|--since|TEXT|Time window, e.g. 7d, 24h, 2w
flag|log|--format|table json csv|Output format

flag|completion|--shell|bash zsh fish|Report for this shell instead of $SHELL
SPEC
}
