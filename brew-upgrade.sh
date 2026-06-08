#!/usr/bin/env bash
[ -z "${BASH_VERSION:-}" ] && exec bash "$0" "$@"
set -euo pipefail

LEVEL="minor"        # patch | minor | major  (EKSAK / HANYA kategori ini)
OR_LOWER=false       # jika true: patch<=, minor<= (minor+patch), major<= (semua)
ALLOW_DATE=false
DRY_RUN=false
ONLY_FORMULAE=false
ONLY_CASKS=false
VERBOSE=false

usage() {
  cat <<'USAGE'
Usage: brew-upgrade-minor [options]

Options:
  --level=patch|minor|major  Pilih kategori bump yang DIEKSEKUSI (eksklusif). Default: minor.
  --or-lower                 Jadikan inklusif (mis. minor => minor+patch; major => major+minor+patch).
  --allow-date               Perlakukan versi tanggal (YYYY.MM.DD / YYYY-MM-DD...) sebagai semver-like. Default: false
  -n, --dry-run              Tampilkan rencana tanpa eksekusi.
  --formulae                 Hanya formula (skip casks).
  --casks                    Hanya casks (skip formula).
  -v, --verbose              Output lebih rinci.
  -h, --help                 Tampilkan bantuan ini.

Catatan:
- Pre-release (-0, -rc.1) dan +build diabaikan saat komparasi (hanya M.m.p).
- Versi timestamp/tanggal di-skip kecuali pakai --allow-date.
USAGE
}

logv() { $VERBOSE && echo "[v] $*" >&2 || true; }

# --- Argparse ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --level=patch|--level=minor|--level=major) LEVEL="${1#*=}" ;;
    --or-lower)      OR_LOWER=true ;;
    --allow-date)    ALLOW_DATE=true ;;
    -n|--dry-run)    DRY_RUN=true ;;
    --formulae)      ONLY_FORMULAE=true ;;
    --casks)         ONLY_CASKS=true ;;
    -v|--verbose)    VERBOSE=true ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Argumen tidak dikenal: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if $ONLY_FORMULAE && $ONLY_CASKS; then
  echo "Error: --formulae and --casks are mutually exclusive." >&2
  exit 1
fi

# --- Helpers ---
to_semver_3() {
  local raw="$1"
  local s="$raw"

  # Format tanggal/timestamp (YYYY.MM.DD / YYYY-MM-DD, opsional T... / -hash)
  if [[ "$raw" =~ ^([0-9]{4})[.-]([0-9]{2})[.-]([0-9]{2})(T[^ ]*)?([_-][^ ]*)?$ ]]; then
    $ALLOW_DATE || return 1
    local yy=$((10#${BASH_REMATCH[1]}))
    local mm=$((10#${BASH_REMATCH[2]}))
    local dd=$((10#${BASH_REMATCH[3]}))
    echo "${yy}.${mm}.${dd}"
    return 0
  fi

  # Semver-like: buang +build, _rev, dan pre-release
  s="${s%%+*}"
  s="${s%%_*}"
  s="${s%%-*}"

  if [[ "$s" =~ ^([0-9]+)\.([0-9]+)(\.([0-9]+))?$ ]]; then
    local maj="${BASH_REMATCH[1]}"
    local min="${BASH_REMATCH[2]}"
    local pat="${BASH_REMATCH[4]:-0}"
    echo "${maj}.${min}.${pat}"
    return 0
  fi
  return 1
}

bump_kind() {
  local old="$1" new="$2"
  local oM oN oP nM nN nP
  IFS=. read -r oM oN oP <<<"$old"
  IFS=. read -r nM nN nP <<<"$new"
  oM=$((10#$oM)); oN=$((10#$oN)); oP=$((10#$oP))
  nM=$((10#$nM)); nN=$((10#$nN)); nP=$((10#$nP))

  if   (( nM > oM )); then echo "major"
  elif (( nM < oM )); then echo "downgrade"
  else
    if   (( nN > oN )); then echo "minor"
    elif (( nN < oN )); then echo "downgrade"
    else
      if   (( nP > oP )); then echo "patch"
      elif (( nP < oP )); then echo "downgrade"
      else echo "none"
      fi
    fi
  fi
}

allow_by_level() {
  local kind="$1" lvl="$2" incl="$3"  # incl = true/false (OR_LOWER)
  # Pemetaan bobot
  local k=0 l=0
  case "$kind" in
    patch) k=1 ;; minor) k=2 ;; major) k=3 ;;
    none|downgrade) return 1 ;;
    *) return 1 ;;
  esac
  case "$lvl" in
    patch) l=1 ;; minor) l=2 ;; major) l=3 ;;
  esac
  if $incl; then
    (( k <= l ))     # inklusif (≤)
  else
    (( k == l ))     # eksklusif (==)  <<— ini perubahan penting
  fi
}

parse_outdated_line() {
  local line="$1"
  local re='^([A-Za-z0-9@._/+:-]+)[[:space:]]+\(([^)]+)\)[[:space:]]+(<|<=|!=)[[:space:]]+([^[:space:]]+)'
  if [[ $line =~ $re ]]; then
    local name="${BASH_REMATCH[1]}"
    local olds="${BASH_REMATCH[2]}"
    local op="${BASH_REMATCH[3]}"
    local new="${BASH_REMATCH[4]}"
    local old
    old="$(echo "$olds" | awk -F',' '{gsub(/^[ \t]+|[ \t]+$/,"",$NF); print $NF}')"
    echo "${name}|${old}|${new}|${op}"
    return 0
  fi
  return 1
}

# --- Proses brew outdated ---
CASK_SET=" $(brew list --cask 2>/dev/null | tr '\n' ' ') "
is_cask() { [[ "$CASK_SET" == *" $1 "* ]]; }

OUT="$(brew outdated --verbose 2>/dev/null || true)"
UPGRADE_LIST=()
REPORT_ROWS=()
SKIPPED_NONSEMVER=0

while IFS= read -r ln; do
  case "$ln" in
    *"("*")"*"<"*|*"("*")"*"!="* )
      if ! parsed="$(parse_outdated_line "$ln")"; then
        logv "Lewati (tak ter-parse): $ln"; continue
      fi
      IFS='|' read -r name old_raw new_raw op <<<"$parsed"

      if $ONLY_FORMULAE && is_cask "$name"; then
        logv "Lewati cask (hanya formulae): $name"; continue
      elif $ONLY_CASKS && ! is_cask "$name"; then
        logv "Lewati formula (hanya casks): $name"; continue
      fi

      if ! old_sv="$(to_semver_3 "$old_raw")"; then
        logv "Lewati (old non-semver): $name $old_raw -> $new_raw"
        SKIPPED_NONSEMVER=$((SKIPPED_NONSEMVER+1)); continue
      fi
      if ! new_sv="$(to_semver_3 "$new_raw")"; then
        logv "Lewati (new non-semver): $name $old_raw -> $new_raw"
        SKIPPED_NONSEMVER=$((SKIPPED_NONSEMVER+1)); continue
      fi

      kind="$(bump_kind "$old_sv" "$new_sv")"
      if allow_by_level "$kind" "$LEVEL" "$OR_LOWER"; then
        UPGRADE_LIST+=("$name")
        REPORT_ROWS+=("$name  ${old_sv}  ->  ${new_sv}  [${kind}]")
      else
        logv "Skip by level ($LEVEL, or-lower=$OR_LOWER): $name ${old_sv} -> ${new_sv} [${kind}]"
      fi
    ;;
    *) : ;;
  esac
done <<<"$OUT"

if (( SKIPPED_NONSEMVER > 0 )); then
  echo "Note: ${SKIPPED_NONSEMVER} package(s) skipped (non-semver version)." >&2
fi

# --- Output / eksekusi ---
if $DRY_RUN; then
  if ((${#UPGRADE_LIST[@]}==0)); then
    echo "Tidak ada kandidat upgrade (LEVEL=${LEVEL}, or-lower=${OR_LOWER})."
    exit 0
  fi
  echo "Kandidat upgrade (${#UPGRADE_LIST[@]}) [LEVEL=${LEVEL}, or-lower=${OR_LOWER}]:"
  printf '  - %s\n' "${REPORT_ROWS[@]}"
  exit 0
fi

if ((${#UPGRADE_LIST[@]}==0)); then
  echo "Tidak ada paket untuk di-upgrade (LEVEL=${LEVEL}, or-lower=${OR_LOWER})."
  exit 0
fi

echo "Meng-upgrade ${#UPGRADE_LIST[@]} paket [LEVEL=${LEVEL}, or-lower=${OR_LOWER}]:"
printf '  - %s\n' "${REPORT_ROWS[@]}"

fail=0
for name in "${UPGRADE_LIST[@]}"; do
  echo "==> brew upgrade $name"
  if ! brew upgrade "$name"; then
    echo "Gagal upgrade: $name" >&2
    fail=$((fail+1))
  fi
done

if (( fail > 0 )); then
  echo "Selesai dengan ${fail} kegagalan." >&2
  exit 1
fi

echo "Sukses."