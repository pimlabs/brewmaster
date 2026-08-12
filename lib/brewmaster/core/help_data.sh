#!/usr/bin/env bash
# brewmaster core: shared help/reference text, source of truth for
# --help, `brewmaster help <command>`, and the generated man page.
# Sourced by bin/brewmaster; defines functions only.

# _help_source_text — emit the raw help reference text (line grammar:
# caps-only lines are section headers, indented "name  description" lines
# are command/flag definitions, "(parenthetical)" spans are annotations).
# Consumed by usage()'s styling loop and by help_command()'s group slicer.
# Args:   none
# Stdout: help reference text, unstyled
# Return: 0
_help_source_text() {
  cat <<'EOF'
Usage: brewmaster [upgrade] [packages...] [options]
       brewmaster snapshot <save|list|diff|restore|delete> [ref] [options]
       brewmaster deps show [package]
       brewmaster profile <list|create|edit|diff|validate> [args]
       brewmaster cleanup [--dry-run|--interactive|--force]
       brewmaster why <package>
       brewmaster bloat
       brewmaster log [--package=NAME] [--action=upgrade|cleanup|snapshot] [--since=Nd] [--format=table|json|csv]
       brewmaster report

Each section below groups a set of commands with the flags that apply to them.

UPGRADE (default command)
  upgrade [packages...]      Selective upgrade by semver bump level.
                             Pass package names to limit the upgrade to those:
                             e.g. brewmaster upgrade git node --minor

  Level (mutually exclusive; default: patch):
    --patch                  Apply patch bumps only (default).
    --minor                  Apply minor bumps only.
    --major                  Apply major bumps only.
    --level=patch|minor|major  Same as the flags above (also: --level minor).

  Flags:
    --or-lower               Make it inclusive (e.g. --minor => minor+patch; --major => all).
    --allow-date             Treat date versions (YYYY.MM.DD / YYYY-MM-DD...) as semver-like. Default: false.
    -n, --dry-run            Show the plan without executing.
    --formulae               Formulae only (skip casks).
    --casks                  Casks only (skip formulae).
    --profile=NAME           Filter/level from a named profile (see PROFILES).
    --interactive, -i        No effect (review below is now always shown; kept for compatibility).

  Before executing, candidates are always shown for review: fzf multi-select if
  installed, else a table plus a single [y/N] for the whole batch. --dry-run and
  --yes both skip this (--dry-run shows the table and stops; --yes upgrades all).

  Version comparison ignores pre-release (-rc.1) and +build metadata (only
  M.m.p is compared); date/timestamp versions (YYYY.MM.DD) are skipped
  unless --allow-date is set.

DEPENDENCY RISK
  deps show [package]        Show dependency risk for one package, or list all
                             outdated packages sorted by risk score.
                             e.g. brewmaster deps show node

  Flags (apply to upgrade):
    --check-deps             Risk-score each upgrade candidate; skip HIGH-risk, warn on MEDIUM.
    --risk-threshold=N       HIGH-risk cutoff (default: 7; range 0-10).
    --yes, -y                Auto-confirm MEDIUM-risk packages, and skip the upgrade review step.

  Risk score is 0-10, higher = more dangerous to upgrade: HIGH >= threshold
  (default 7), MEDIUM 4-6, LOW 0-3. Opposite direction from cleanup score
  (see CLEANUP & INTENT).

SNAPSHOT & ROLLBACK
  snapshot save              Save current Homebrew state to a snapshot.
  snapshot list              List all snapshots.
  snapshot diff [ref]        Show packages changed since a snapshot.
  snapshot restore [ref]     Restore packages to a snapshot state.
  snapshot delete [ref]      Delete a snapshot.
                             e.g. brewmaster snapshot restore 0

  Flags:
    --label=TEXT             Label for 'snapshot save'.
    -n, --dry-run            Show plan without executing for 'snapshot restore'.
    --force                  Skip the y/N confirmation for 'snapshot delete' (differs from cleanup's --force).

  [ref] accepts either the numeric index shown by 'snapshot list', or a
  direct path to a saved snapshot file.

  Snapshots stored in: ~/.local/share/brewmaster/snapshots/ (XDG_DATA_HOME respected).

PROFILES
  profile list               List configured profiles.
  profile create              Interactive wizard to add a new profile.
  profile edit [name]         Open profiles.toml in $EDITOR.
  profile diff <profile_a> <profile_b>  Compare include lists between two profiles.
  profile validate             Check profiles.toml for errors.
                             e.g. brewmaster upgrade --profile=work

  Flags (apply to upgrade):
    --profile=NAME           Apply a profile's package filter and level.
    --interactive, -i        No effect (upgrade always reviews candidates before executing).

  Profiles read from: ~/.config/brewmaster/profiles.toml (XDG_CONFIG_HOME respected).

CLEANUP & INTENT
  cleanup                    Report orphan/stale/pinned-old formulae (read-only by default).
  why <package>              Explain why a formula is installed (dependents,
                             install date, last-access heuristic).
  bloat                      Summary of installed package counts and estimated
                             disk reclaim from cleanup candidates.
                             e.g. brewmaster cleanup --interactive

  Flags (apply to cleanup):
    -n, --dry-run            Read-only report (also the default with no flags).
    --interactive, -i        fzf multi-select packages to remove (requires fzf).
    --force                  Auto-remove orphans with cleanup score >= 7, no confirmation (differs from snapshot's --force).

  Cleanup score is 0-10, higher = safer to remove: the opposite direction
  from dependency risk score (see DEPENDENCY RISK).

AUDIT LOG & REPORTS
  log                        Show recent audit log entries (last 20 by default).
  report                     Machine health summary: upgrades, cleanups,
                             snapshots, orphans, and risk trend.
                             e.g. brewmaster log --action=upgrade --since=7d

  Flags (apply to log):
    --package=NAME           Filter entries by package name.
    --action=ACTION          Filter by action: upgrade|cleanup|snapshot.
    --since=Nd|Nh|Nw         Only entries within this time window (default unit: days).
    --format=table|json|csv  Output format (default: table).

  Audit log stored in: ~/.local/share/brewmaster/audit.log (XDG_DATA_HOME respected).

GENERAL
  -v, --verbose              More detailed output.
  -V, --version              Print version and exit.
  -h, --help                 Show this help.

  -h/--help prints this full reference; use `brewmaster help <command>` for
  a shorter, per-command reference instead.
EOF
}
