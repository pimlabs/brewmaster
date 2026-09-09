## Approach

Three parts, in dependency order: the spec (data), the generator (spec
in, one shell dialect out), the tests (spec against parser, help and
committed scripts).

### The spec

`lib/brewmaster/core/cli_spec.sh` defines `_cli_spec`, which prints one
record per line, fields separated by `|`, comments stripped:

```
cmd|<name>|<description>[|default]
sub|<cmd>|<name>|<description>
arg|<scope>|<position>|<type>|<label>          scope = cmd | cmd.sub; position = 1, 2, *
flag|<scope>|<names>|<value>|<description>[|excl=<group>]
```

`names` is the comma-separated spellings (`-n,--dry-run`). `value` is
`""` for a boolean flag, a space-separated enum (`patch minor major`),
`@package`/`@profile` for a dynamic completer, or a placeholder word
(`N`, `TEXT`) for a free value that is not completed. `type` for
positionals is `package | profile | snapshot | shell`. `excl=` groups
mutually exclusive flags within a scope (`--patch/--minor/--major/
--level`). `default` marks the command that runs when none is given,
whose flags and positionals are therefore valid at top level.

`|` is the separator because no description, name or value contains
one, and the codebase already uses it for row records (cleanup rows,
`upgrade_meta`). The file lives in `core/` because it is pure data with
no `brew` call and no I/O.

### The generator

`docs/gen-completions.sh <bash|zsh|fish>` sources `cli_spec.sh`, loads
the records into parallel indexed arrays (`_spec_load`; bash 3.2, so no
associative arrays), and dispatches to `_emit_bash`, `_emit_zsh` or
`_emit_fish`. Query helpers keep the emitters declarative:
`_spec_subs_of <cmd>`, `_spec_flags_of <scope>`, `_spec_args_of <scope>`,
`_spec_long`/`_spec_short <names>`, `_spec_field`, `_spec_opt`.

Each emitter derives every command, subcommand, flag and value from the
spec; only the dynamic-completer preambles (`brew list` packages,
`profiles.toml` profiles, snapshot refs) are fixed strings, since they
are shell code, not CLI surface. Mapping per shell:

| spec | bash | zsh | fish |
| ---- | ---- | --- | ---- |
| boolean flag | word in `compgen -W` list | `'[desc]'` | `-f -l long [-s short]` |
| enum value | `--flag ` prev case and `--flag=` prefix case | `:label:(v1 v2)` | `-a 'v1 v2'` |
| `@package` / `@profile` | `$(_brewmaster_packages)` / `..._profiles` | `:package:_brewmaster_packages` | `-a '(__fish_brewmaster_packages)'` |
| free value | listed with trailing `=`, no completion | `:label:` | value-taking, no `-a` |
| `excl=` group | not expressible | `(--a --b)--c[...]` exclusion list | not expressible |
| `default` command | top-level flags and packages | `*) _brewmaster_<default>` fallback | `or __fish_brewmaster_no_subcommand` |

Output is deterministic (no dates, no environment) so the committed
files are byte-stable and the drift test is a plain `diff`. Every
generated file's header names the generator and the spec and says not
to edit by hand.

### The tests

`tests/test_completions.sh`:

1. **Drift**: `gen-completions.sh <shell>` output equals the committed
   file, for all three; the failure message says how to regenerate.
2. **Spec ↔ parser**: every `cmd` name appears as a case label in
   `bin/brewmaster`'s subcommand parser and every `sub` name in its
   dispatch; every long flag in the spec has a `--flag)` or `--flag=*)`
   label in the flag parser; and every `--x)` label in the parser is in
   the spec (so a flag cannot be added to the CLI without completion).
3. **Spec ↔ help**: every `cmd` and every long flag appears in
   `help_data.sh`'s text.
4. **Syntax**: `bash -n` on the bash script always; `zsh -n` and
   `fish --no-execute` when those shells are installed (CI's macOS
   runner has zsh; fish is optional).

Behavior parity with the hand-written scripts is verified once, during
this change, by diffing generated against hand-written and by
exercising `COMPREPLY` (bash) and `complete -C` (fish) in the
generator's development; after the switch the committed files are the
generated ones and parity is a property of the spec.

## Decisions

- **Spec in `core/`, generator in `docs/`.** Mirrors `help_data.sh` +
  `gen-man.sh`: data ships with the tool (pure, sourceable by tests),
  the generator is a maintainer tool.
- **Descriptions live in the spec, not shared with `help_data.sh`.**
  Completion descriptions are one line; help text is prose. Sharing
  would force one to fit the other. The consistency test guards the
  lists, not the wording.
- **Behavior parity, not improvement.** So the review is a diff, and any
  offered-completion change is a deliberate later edit to the spec.
- **No runtime use of the spec.** `bin/brewmaster` keeps its explicit
  parser; the spec is checked against it, not used to drive it. Driving
  the parser from data would be a rewrite of the entry point for no
  user-visible gain.

## Alternatives rejected

- **Dynamic completion (`brewmaster __complete`).** Three shims are
  still needed, plus a bash process per keystroke and a hidden
  subcommand in the user-facing surface. The static generator gets the
  single source of truth without either.
- **Parse `help_data.sh` as the spec.** Its grammar is for rendering;
  enum values and exclusion groups are in prose there. A second grammar
  bent onto it would be fragile in both directions.
- **Keep hand-written scripts and add only the consistency test.**
  Catches a missing flag, not a wrong value list or a misplaced
  condition, and leaves three dialects to hand-edit.

## Testing

See "The tests" above; plus `shellcheck` on `cli_spec.sh` and
`gen-completions.sh` (both under `lib/` and `docs/`; the CI job covers
`lib/`, and the docs test runs the generator).
