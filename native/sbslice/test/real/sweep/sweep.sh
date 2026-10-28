#!/usr/bin/env bash
# The outfit sweep: every job of jobs.sh on its vanilla mesh (~28,000 cuts, about 25 minutes on 12 cores), one line per
# job, mesh|label|PASS/FAIL/ERR|its first FAIL lines. Needs the vanilla cache of ./build.sh (meshes are dumped once,
# by ../run.sh, into $TMPDIR/sbslice-real).
#   sweep.sh [out, default sweep.txt] [jobs file]       JOBS=<parallel>, default every core
#   compare.sh [out] to see what changed against results-0.4.1.txt.gz
#   MESHES=<list>: the meshes dumped first (default meshes.txt; /dev/null when they are, test/real/playas.sh)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${1:-sweep.txt}")
export TMPDIR=${TMPDIR:-/tmp}
RS=$TMPDIR/sbslice-real
mkdir -p "$RS"
JOBSF=${2:-}
if [[ -z $JOBSF ]]; then JOBSF=$TMPDIR/sweep-jobs.txt; "$HERE/jobs.sh" > "$JOBSF"; fi
# each mesh dumped once (run.sh does it, then a quick arm cut we don't need)
while read -r p; do m=$(basename "$p")
  [[ -f $RS/$m.bin ]] && continue
  PKG=vanilla/SB/Content/Art/Character/PC/$p ARM=1 "$HERE/../run.sh" "$m" > /dev/null 2>&1 || true
  [[ -f $RS/$m.bin ]] || echo "no mesh for $p" >&2
done < "${MESHES:-$HERE/meshes.txt}"
# the harness, optimized without the sanitizers (the suite runs those)
clang -O2 -w -o "$RS/real_split_sweep" "$HERE/../real_split.c" -lm
one() {
  IFS='|' read -r m label e <<< "$1"
  local out last st f
  out=$(ASAN_OPTIONS=detect_leaks=0 env $e timeout 120 "$RS/real_split_sweep" "$RS/$m.bin" 2>&1 | cut -c1-300) || true
  last=$(printf '%s\n' "$out" | tail -1)
  case "$last" in PASS) st=PASS;; FAIL) st=FAIL;; *) st=ERR;; esac
  f=$(printf '%s\n' "$out" | grep -E "^FAIL:|ERROR|runtime error|AddressSanitizer" | head -4 | tr '\n' ';') || true
  [[ $st == ERR ]] && f="$f last=$(printf '%s' "$last" | cut -c1-120)"
  echo "$m|$label|$st|$f"
}
export -f one
export RS
cd "$HERE/.."
xargs -d '\n' -P "${JOBS:-$(nproc)}" -I{} bash -c 'one "$1"' _ {} < "$JOBSF" > "$OUT"
cut -d'|' -f3 "$OUT" | sort | uniq -c
