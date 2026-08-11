## Context

`bin/brewmaster`'s `usage()` renders `--help` from one inline heredoc
(`bin/brewmaster:120-232`) with a per-line styling pass: caps-only lines
become bold section headers, indented `name  description` lines get the
name bolded and `<...>`/`[...]` placeholders underlined, and
`(default...)`/`(also:...)`/`(requires fzf)` parentheticals get dimmed.
This heredoc is the only place command/flag text exists — there is no
per-command `help` dispatch (`bin/brewmaster:226` says so explicitly), and
`docs/brewmaster.1` (317 lines, troff, dated 2026-06-14 at v0.6.1) is a
second, hand-written copy of overlapping content that has already drifted:
it predates profiles, audit log/report, and cleanup scoring, all shipped
since v0.6.1.

`Formula/brewmaster.rb` lives in `pimlabs/homebrew-tap`, not this repo —
confirmed via `gh api repos/pimlabs/homebrew-tap/contents/Formula/brewmaster.rb`
— and already has `man1.install "docs/brewmaster.1"`. `.github/workflows/release.yml`'s
`update-formula` job pushes version/sha256 bumps to that tap repo on tag push.
Nothing in this milestone touches that file or that workflow.

## Goals / Non-Goals

**Goals:**
- One source of truth for command/flag/example content, consumed by three
  renderers: top-level `--help`, new `brewmaster help [command]`, and
  `docs/brewmaster.1`.
- Zero behavior change to today's `--help` output (must stay byte-identical
  to `tests/fixtures/help.txt` under `NO_COLOR`/non-TTY — same fixture,
  same test).
- `docs/brewmaster.1` becomes reproducible: a generator script produces it
  from the shared source, and a test fails if the committed file drifts
  from what the generator would produce.
- `--version` carries a build date so a bug report can pin an exact build.

**Non-Goals:**
- No change to `Formula/brewmaster.rb` or `.github/workflows/release.yml`
  — both live outside this repo's reach (formula) or are already correct
  (release workflow's tap update).
- No auto-computed build date (e.g. from `git log` or file mtime) — see
  Decisions below for why.
- No change to shell completions (`completions/*`) — separate concern,
  not mentioned in ROADMAP M9 scope.
- No CI enforcement wiring beyond the existing `tests/run_all.sh` path —
  the drift-check test rides the existing test suite, no new CI job.

## Decisions

### 1. Shared source stays in the existing heredoc shape, moved to `lib/brewmaster/core/help_data.sh`

The heredoc's line grammar (caps header / indented `name<gap>description`
/ `(parenthetical)` annotations) already carries everything three renderers
need: group boundaries, command names, flag names, descriptions, and inline
examples. Rather than inventing a new declarative format (e.g. nested
associative arrays), extract the heredoc text as-is into a new file,
`lib/brewmaster/core/help_data.sh`, behind a function `_help_source_text()`
that emits it via `cat <<'EOF'`. `bin/brewmaster` sources it like every
other `core/*.sh` module already sourced there.

**Alternative considered:** structured bash arrays (`HELP_COMMANDS=(...)`
with parallel group/usage/flags/example arrays). Rejected: rewriting
`usage()`'s styling loop to render from arrays instead of text risks
changing the byte-identical `--help` output the test suite pins, for no
behavioral gain — the text-as-source approach reuses the existing,
already-correct line-shape parser for all three renderers instead of
building a second rendering path.

### 2. `usage()` keeps its current styling loop, now fed by `_help_source_text()`

`bin/brewmaster:97-233`'s loop is unchanged; only its input source moves
from an inline heredoc to `_help_source_text()`'s output. This is the
change that guarantees zero output drift — same bytes in, same parser,
same bytes out.

### 3. `help_command()` slices the same source by group

New function in `bin/brewmaster`: scans `_help_source_text()` output for
the caps-header line whose group contains the requested command (a small
lookup table maps command name → group name, since one group can hold
several commands, e.g. SNAPSHOT & ROLLBACK holds `save|list|diff|restore|delete`),
then prints that group's block through the same styling helpers `usage()`
already uses (`_help_style_name`, `_help_style_desc`). Unknown command →
error to stderr, exit 1, matching existing error conventions
(`bin/brewmaster:266`, `:305`).

### 4. Add exactly one example line per group where missing

Only UPGRADE currently has an inline `e.g. brewmaster upgrade git node
--minor` example. `tasks.md` adds one comparable example line to each of
the other six groups (DEPENDENCY RISK, SNAPSHOT & ROLLBACK, PROFILES,
CLEANUP & INTENT, AUDIT LOG & REPORTS — GENERAL needs none, it has no
subcommand). This is a content addition inside `help_data.sh`, not a
mechanism change, and does not alter `--help`'s existing fixture since the
top-level view already prints full group bodies (examples were already
part of the printed text where present — adding more only appends within
the same rendering path already covered by the fixture, meaning
`tests/fixtures/help.txt` must be regenerated once and re-pinned, not left
as a silent pass).

### 5. `docs/gen-man.sh` — new standalone generator, not wired into `bin/brewmaster`

A new script, sourcing only `lib/brewmaster/core/help_data.sh` (not the
whole CLI, so it needs no mock `brew`/`jq` environment), walks the same
line shapes `usage()` recognizes and emits troff macros (`.SH`, `.TP`,
`.B`, `.I`) to stdout. Maintainer runs `docs/gen-man.sh > docs/brewmaster.1`
by hand when the source changes; there's no build step in this project
(no Makefile, no CI codegen job) to hook it into automatically.

**Alternative considered:** generate `docs/brewmaster.1` at Homebrew
install time via a `def install` step in the formula. Rejected outright —
that file lives in a different repo this proposal can't touch, and
Homebrew formulae are expected to install static, already-built artifacts,
not run generators.

### 6. Drift check: a test, not a git hook

`tests/test_cli.sh` gains an assertion that runs `docs/gen-man.sh`,
diffs its output against the committed `docs/brewmaster.1`, and fails if
they differ. This is the enforcement mechanism for "no duplication" —
whoever edits `help_data.sh` and forgets to regenerate the man page finds
out from `bash tests/run_all.sh`, the same place every other regression
in this project is caught.

### 7. `--version` build date: a hand-maintained constant, not computed

Considered and rejected two auto-computed options:
- **File mtime** (`stat` on the installed script) — git does not preserve
  mtimes on checkout/clone/tag, so this reflects "when Homebrew wrote the
  file to disk," not when the release was cut. Meaningless for bug
  triage.
- **`git log -1 --format=%cd`** — `brew install` copies `bin/brewmaster`
  via `bin.install` with no `.git` directory alongside it in the
  installed prefix, so this only works in a dev checkout, never in an
  actual installed binary. The one case that matters (a user running
  `brewmaster --version` to report a bug) is exactly the case this would
  fail silently or error in.

Decision: add `BUILD_DATE="YYYY-MM-DD"` next to `BREWMASTER_VERSION` at
`bin/brewmaster:5`, bumped by hand at the same time as the version string
(the project already does this manually per the `chore: bump version to
X.Y.0` commit convention — no new process, same discipline extended to
one more constant). `--version` prints
`brewmaster ${BREWMASTER_VERSION} (built ${BUILD_DATE})`.

## Risks / Trade-offs

- **[Risk]** A future edit to `help_data.sh` changes line shapes the
  parser doesn't recognize (e.g. a flag description spanning multiple
  lines) → silently misrenders in one of the three outputs without an
  error. **Mitigation:** the drift-check test (Decision 6) catches man
  page divergence; `--help`'s existing byte-identical fixture test catches
  top-level drift. `help <command>` has no equivalent fixture yet —
  `tasks.md` adds one fixture per group so this surface is covered too.
- **[Risk]** `BUILD_DATE` is forgotten at release time (stale date shipped
  in a real release). **Mitigation:** accepted trade-off — same exposure
  already exists for `BREWMASTER_VERSION` today and the project has
  shipped 9 milestones without that constant going stale, so the existing
  release discipline is trusted to extend to one more line.
- **[Trade-off]** `docs/gen-man.sh` output must be regenerated and
  committed by hand; it is not automatic in CI. Accepted because this
  repo has no build step at all today (completions/* are also hand-
  committed static files) and adding a CI codegen job is out of proportion
  to a milestone whose own ROADMAP acceptance criteria are about `--help`
  and `man brewmaster` output, not CI architecture.

## Migration Plan

1. Extract heredoc → `lib/brewmaster/core/help_data.sh`, source it from
   `bin/brewmaster`, confirm `--help` output is still byte-identical
   before any other change lands (this step alone should be a no-op
   commit, verifiable against the current `tests/fixtures/help.txt`).
2. Add missing per-group examples to `help_data.sh`; regenerate
   `tests/fixtures/help.txt` and re-pin it (expected, intentional fixture
   change — call this out in the task's commit message).
3. Add `help_command()` dispatch + its own fixtures.
4. Add `BUILD_DATE` + `--version` output change + test.
5. Add `docs/gen-man.sh`, run it once, commit the regenerated
   `docs/brewmaster.1`.
6. Add the drift-check test last, once the committed man page is known to
   match generator output.

No rollback complexity — this is additive/refactor-only within one repo,
no data migration, no external system touched.

## Open Questions

None outstanding — both scope questions (Formula location, codegen vs.
test-diff for the man page) were resolved with the maintainer before this
document was written.
