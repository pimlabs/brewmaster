#!/usr/bin/env bash
# CLI-spec tests: the committed completion scripts are what
# docs/gen-completions.sh produces from lib/brewmaster/core/cli_spec.sh,
# and the spec agrees with bin/brewmaster's parser and with help_data.sh.
# One list of commands and flags, four consumers, no drift.
# shellcheck disable=SC2015 # `&& ok || bad` is the assert idiom every test file uses
set -uo pipefail

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$DIR/.."
GEN="$ROOT/docs/gen-completions.sh"
BIN="$ROOT/bin/brewmaster"
HELP="$ROOT/lib/brewmaster/core/help_data.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

# shellcheck source=../lib/brewmaster/core/cli_spec.sh
source "$ROOT/lib/brewmaster/core/cli_spec.sh"

# --- 1. drift: generator output equals each committed script ---
for sh in bash zsh fish; do
  if diff <(bash "$GEN" "$sh") "$ROOT/completions/brewmaster.$sh" >/dev/null; then ok
  else
    bad "completions/brewmaster.$sh has drifted from the spec; regenerate with: docs/gen-completions.sh $sh > completions/brewmaster.$sh"
    diff <(bash "$GEN" "$sh") "$ROOT/completions/brewmaster.$sh" | head -20 >&2
  fi
done

# --- 2. determinism: two runs, same bytes ---
diff <(bash "$GEN" zsh) <(bash "$GEN" zsh) >/dev/null && ok || bad "generator output is not deterministic"

# --- 3. spec <-> parser: commands ---
spec_cmds="$(_cli_spec | awk -F'|' '$1=="cmd"{print $2}' | sort)"
# The subcommand parser is the case block between the two markers; labels
# may be joined with "|" (cleanup|why|bloat|log|report).
parser_cmds="$(sed -n '/^# --- Subcommand/,/^# --- Argument parsing/p' "$BIN" \
  | grep -oE '^ +[a-z|]+\)' | tr -d ' )' | tr '|' '\n' | sort)"
missing_in_parser="$(comm -23 <(echo "$spec_cmds") <(echo "$parser_cmds"))"
missing_in_spec="$(comm -13 <(echo "$spec_cmds") <(echo "$parser_cmds"))"
[ -z "$missing_in_parser" ] && ok || bad "commands in the spec but not parsed by bin/brewmaster: $(echo "$missing_in_parser" | tr '\n' ' ')"
[ -z "$missing_in_spec" ]   && ok || bad "commands parsed by bin/brewmaster but missing from the spec: $(echo "$missing_in_spec" | tr '\n' ' ')"

# --- 4. spec <-> parser: sub-subcommands are dispatch labels inside their command's block ---
missing_subs=""
while IFS='|' read -r cmd name _; do
  sed -n "/^  $cmd)/,/^    ;;/p" "$BIN" | grep -qE "^ +$name\)" || missing_subs+=" $cmd.$name"
done < <(_cli_spec | awk -F'|' '$1=="sub"{print $2"|"$3"|"$4}')
[ -z "$missing_subs" ] && ok || bad "sub-subcommands in the spec without a dispatch label in bin/brewmaster:$missing_subs"

# --- 5. spec <-> parser: long flags, both directions ---
spec_flags="$(_cli_spec | awk -F'|' '$1=="flag"{print $3}' | tr ',' '\n' | grep '^--' | sort -u)"
parser_flags="$(sed -n '/^# --- Argument parsing ---/,/^done/p' "$BIN" \
  | grep -oE '(^ +|\|)--[a-z-]+' | grep -oE -- '--[a-z-]+' | sort -u)"
missing_in_parser="$(comm -23 <(echo "$spec_flags") <(echo "$parser_flags"))"
missing_in_spec="$(comm -13 <(echo "$spec_flags") <(echo "$parser_flags"))"
[ -z "$missing_in_parser" ] && ok || bad "flags in the spec but not parsed by bin/brewmaster: $(echo "$missing_in_parser" | tr '\n' ' ')"
[ -z "$missing_in_spec" ]   && ok || bad "flags parsed by bin/brewmaster but missing from the spec: $(echo "$missing_in_spec" | tr '\n' ' ')"

# --- 6. spec <-> help: every command and long flag is a documented entry in help_data.sh
#        (the word at the start of a usage or option line, not a mention in prose) ---
missing_help=""
while IFS= read -r c; do grep -qE "^ +(brewmaster )?$c( |$)" "$HELP" || missing_help+=" $c"; done <<<"$spec_cmds"
while IFS= read -r f; do grep -qE "^ +(-[A-Za-z], )?$f(=|,| |$)" "$HELP" || missing_help+=" $f"; done <<<"$spec_flags"
[ -z "$missing_help" ] && ok || bad "in the spec but absent from help_data.sh:$missing_help"

# --- 7. syntax: bash always; zsh and fish when installed ---
bash -n "$ROOT/completions/brewmaster.bash" && ok || bad "brewmaster.bash: syntax"
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$ROOT/completions/brewmaster.zsh" && ok || bad "brewmaster.zsh: syntax"
fi
if command -v fish >/dev/null 2>&1; then
  fish --no-execute "$ROOT/completions/brewmaster.fish" && ok || bad "brewmaster.fish: syntax"
fi

# --- 8. generated headers say so ---
for sh in bash zsh fish; do
  head -5 "$ROOT/completions/brewmaster.$sh" | grep -q 'gen-completions.sh' && ok || bad "brewmaster.$sh: header names the generator"
done

# --- 9. behaviour (bash): what _brewmaster offers for a command line ---
#        COMP_WORDS harness: the words readline hands over (the last one is
#        the word being completed; a stock COMP_WORDBREAKS splits "--flag=va"
#        into "--flag" "=" "va"), COMPREPLY back as one line. brew and the
#        profiles file are mocked in a temp dir that is removed afterwards.
tmp="$(mktemp -d)"
cat > "$tmp/brew" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = list ] && printf '%s\n' pkg-a pkg-b
exit 0
EOF
chmod +x "$tmp/brew"
mkdir -p "$tmp/cfg/brewmaster"
printf '[profiles.work]\n[profiles.home]\n' > "$tmp/cfg/brewmaster/profiles.toml"
# complete_bash <word>... — COMPREPLY for that command line, space-joined
complete_bash() {
  ( PATH="$tmp:$PATH" XDG_CONFIG_HOME="$tmp/cfg"
    # shellcheck source=../completions/brewmaster.bash
    source "$ROOT/completions/brewmaster.bash"
    COMP_WORDS=("$@"); COMP_CWORD=$(( $# - 1 )); COMPREPLY=()
    _brewmaster
    printf '%s\n' "${COMPREPLY[*]-}" )
}
# has <list> <word> — word is one of the space-separated list
has() { case " $1 " in *" $2 "*) return 0 ;; *) return 1 ;; esac; }

r="$(complete_bash brewmaster -n "")"
has "$r" snapshot && ok || bad "bash: 'brewmaster -n <TAB>' should offer commands (got: $r)"
has "$r" pkg-a    && ok || bad "bash: 'brewmaster -n <TAB>' should still offer packages (got: $r)"
r="$(complete_bash brewmaster -n snapshot "")"
has "$r" save && ok || bad "bash: a command after a leading flag is the command (got: $r)"
r="$(complete_bash brewmaster --level patch "")"
has "$r" snapshot && ok || bad "bash: the value of '--level patch' is not a command; commands still offered (got: $r)"
r="$(complete_bash brewmaster --level patch snapshot "")"
has "$r" list && ok || bad "bash: command after '--level patch' is the command (got: $r)"
r="$(complete_bash brewmaster --level = pa)"
[ "$r" = "patch" ] && ok || bad "bash: '--level=pa' split at '=' completes the bare value (got: $r)"
r="$(complete_bash brewmaster --level =)"
[ "$r" = "patch minor major" ] && ok || bad "bash: '--level=' split at '=' offers every value (got: $r)"
r="$(complete_bash brewmaster --profile =)"
[ "$r" = "work home" ] && ok || bad "bash: '--profile=' split at '=' runs the dynamic completer (got: $r)"
r="$(complete_bash brewmaster snapshot save --label =)"
[ -z "$r" ] && ok || bad "bash: '--label=' is a free value, nothing offered (got: $r)"
r="$(complete_bash brewmaster --level=pa)"
[ "$r" = "--level=patch" ] && ok || bad "bash: unsplit '--level=pa' still completes with its prefix (got: $r)"
rm -rf "$tmp"

echo "Passed: $pass, Failed: $fail"
(( fail == 0 ))
