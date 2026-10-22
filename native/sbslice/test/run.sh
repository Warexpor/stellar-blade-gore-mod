#!/usr/bin/env bash
# Build and run the skin cut harness natively (clang, ASan/UBSan), then the cuts on real outfit and enemy meshes when
# the build cache has them (test/real/run.sh). The real-mesh runs go in parallel (JOBS, default the CPU count).
#   test/run.sh [group...]   groups: unit (test_cut.c), stats (test_stats.c), split, waist, arm, enemy; default all
# What to run for a change:
#   stats.c / glass.lua            stats
#   sbslice.c, a limb or neck cut  unit arm enemy
#   sbslice.c, the split (SIDE)    unit split waist
#   sbslice.c, anything shared     everything (no group)
#   Lua alone                      nothing here (the harness doesn't run Lua)
set -euo pipefail
cd "$(dirname "$0")"
OUT=${TMPDIR:-/tmp}/sbslice-test
SEL=" $* "
[[ $# -eq 0 ]] && SEL=" unit stats split waist arm enemy "
on() { [[ $SEL == *" $1 "* ]]; }
fail=0
if on unit; then
  clang -O1 -g -fsanitize=address,undefined -w -o "$OUT" test_cut.c
  ASAN_OPTIONS=detect_leaks=0 "$OUT" | tee "$OUT.log" | grep -v '^PASS$' || true
  grep -qx PASS "$OUT.log" || fail=1
fi
# the actor stats (stats.c, the glass cannon mode) on made-up actors
if on stats; then
  clang -O1 -g -fsanitize=address,undefined -w -o "$OUT-stats" test_stats.c
  r=$(ASAN_OPTIONS=detect_leaks=0 "$OUT-stats" | tail -1)
  echo "stats: $r"
  [[ $r == PASS ]] || fail=1
fi
# the real-mesh runs: one line each, "label|env...|mesh[|vanilla cache]" (the cache's path may have spaces)
jobs=()
if [[ -f ../../../.cache/work/vanilla/SB/Content/Art/Character/PC/CH_P_EVE_09/CH_P_EVE_09.uasset ]]; then
  for m in CH_P_EVE_09 CH_P_EVE_30; do
    for posed in "" 1; do
      p=${posed:+ (posed)}
      if on split; then
        jobs+=("real split $m$p|POSED=$posed|$m" "real split $m across the waist$p|ACROSS=1 POSED=$posed|$m")
      fi
      on waist && jobs+=("real waist cut $m$p|WAIST=1 POSED=$posed|$m")
      on waist && [[ -z $posed ]] && jobs+=("real waist cut $m after the left arm|WAIST=1 ARMFIRST=1|$m")
      if on arm; then
        jobs+=("real arm cut $m (cape cut off)$p|ARM=1 POSED=$posed|$m" "real arm cut $m (cape kept on the body)$p|ARM=1 KEEPCAPE=1 POSED=$posed|$m")
      fi
      # a stub carrier must have held still while she played: helpers that swung, or none watched yet, carry nothing
      if on arm && [[ -z $posed ]]; then
        jobs+=("real arm cut $m, its parent's helpers driven|ARM=1 DRIVEN=1|$m" "real arm cut $m, never watched|ARM=1 UNWATCHED=1|$m")
      fi
    done
  done
  # the outfit the ragdoll-death split sheets came from (playtest 14): its copy's neck skin hung partly on the head the
  # copy lets go. Plain, posed, and with her animation-driven correctives watched (none may be a sink)
  if on split && [[ -f ../../../.cache/work/vanilla/SB/Content/Art/Character/PC/CH_P_EVE_10/CH_P_EVE_10.uasset ]]; then
    jobs+=("real split CH_P_EVE_10|POSED=|CH_P_EVE_10" "real split CH_P_EVE_10 (posed)|POSED=1|CH_P_EVE_10"
           "real split CH_P_EVE_10, correctives driven|DRIVEN=1|CH_P_EVE_10" "real split CH_P_EVE_09, correctives driven|DRIVEN=1|CH_P_EVE_09")
  fi
fi
# the enemies' bodies (tune.enemies.kinds; ./build.sh extracts them for their CPU access): an arm, the head, across
# the waist, with the nosink list gore.lua sends for an enemy (ENEMY=1). ENEMY_VANILLA=<legacy cache> points elsewhere
EV=${ENEMY_VANILLA:-../../../.cache/work/vanilla}
if on enemy; then
  for m in CH_M_NA_16/CH_M_NA_16 CH_M_NA_17/CH_M_NA_17 CH_M_NA_17/CH_M_NA_17_1 CH_M_NA_19/CH_M_NA_19 CH_M_NA_35/CH_M_NA_35 \
           CH_M_NA_40/CH_M_NA_40 CH_M_NA_40/CH_M_NA_40_B CH_M_NA_40/CH_M_NA_40_C CH_M_NA_45/CH_M_NA_45; do
    [[ -f $EV/SB/Content/Art/Character/Monster/$m.uasset ]] || continue
    for cut in LIMB HEAD WAIST; do
      jobs+=("enemy ${m#*/} ${cut,,}|ENEMY=1 $cut=1 PKG=vanilla/SB/Content/Art/Character/Monster/$m|${m#*/}|$(cd "$EV" && pwd)")
    done
  done
fi
if (( ${#jobs[@]} )); then
  RES=$(mktemp -d)
  # the harness is built once up front, so the parallel runs don't all compile it
  first=${jobs[0]}; IFS='|' read -r _ fenv fmesh fvan <<<"$first"
  env $fenv ${fvan:+VANILLA="$fvan"} real/run.sh "$fmesh" >/dev/null 2>&1 || true
  i=0
  for j in "${jobs[@]}"; do
    IFS='|' read -r label envs mesh van <<<"$j"
    printf '%s\n' "$label" > "$RES/$i.label"
    ( env $envs ${van:+VANILLA="$van"} real/run.sh "$mesh" 2>&1 | tail -1 > "$RES/$i.res" ) &
    i=$((i + 1))
    while (( $(jobs -rp | wc -l) >= ${JOBS:-$(nproc)} )); do wait -n || true; done
  done
  wait
  for ((k = 0; k < i; k++)); do
    r=$(cat "$RES/$k.res"); echo "$(cat "$RES/$k.label"): $r"
    [[ $r == PASS ]] || fail=1
  done
  rm -rf "$RES"
fi
[[ $fail == 0 ]] && echo PASS || echo FAIL
exit $fail
