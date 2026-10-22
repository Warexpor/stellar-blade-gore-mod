#!/usr/bin/env bash
# Build and run the skin cut harness natively (clang, ASan/UBSan), then the cuts on real outfit and enemy meshes when
# the build cache has them (test/real/run.sh). The real-mesh runs go in parallel (JOBS, default the CPU count).
#   test/run.sh [group...]   groups: unit (test_cut.c), stats (test_stats.c), split, waist, arm, mark, enemy; default all
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
[[ $# -eq 0 ]] && SEL=" unit stats split waist arm mark enemy "
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
        jobs+=("real split $m$p|POSED=$posed|$m" "real split $m across the waist$p|ACROSS=1 POSED=$posed|$m"
               "real split $m beside the neck$p|BESIDE=2 POSED=$posed|$m")
      fi
      on waist && jobs+=("real waist cut $m$p|WAIST=1 POSED=$posed|$m")
      on waist && [[ -z $posed ]] && jobs+=("real waist cut $m after the left arm|WAIST=1 ARMFIRST=1|$m")
      if on arm; then
        jobs+=("real arm cut $m (cape cut off)$p|ARM=1 POSED=$posed|$m" "real arm cut $m (cape kept on the body)$p|ARM=1 KEEPCAPE=1 POSED=$posed|$m")
      fi
      # a living hit's mark: rays out of the torso, an arm and a thigh meet the skin on that part
      on mark && jobs+=("real hit mark $m$p|MARK=1 POSED=$posed|$m")
      # a thigh cut in a fall, her left elbow by the hip: no sink of the hip's seam on the arm (twenty-seventh playtest)
      on arm && [[ -z $posed ]] && jobs+=("real thigh cut $m, her elbow by the hip|ARM=1 ARMBONE=Bip001-L-Thigh ARMEND=Bip001-L-Calf ARMAT=0.47 ELBOWHIP=1|$m")
      # thigh cuts near the knee and mid-thigh with the hip's correctives moving (in play and after the cut): the
      # seam's point rides a still helper of the stump's body, nothing stretches to a moving one or to the chest
      on arm && [[ -z $posed ]] && jobs+=("real thigh cut $m near the knee, hip helpers moving|HIPMOVED=1 ARM=1 ARMBONE=Bip001-R-Thigh ARMEND=Bip001-R-Calf ARMAT=0.81|$m"
                                         "real thigh cut $m, hip helpers moving|HIPMOVED=1 ARM=1 ARMBONE=Bip001-L-Thigh ARMEND=Bip001-L-Calf ARMAT=0.47|$m")
      # both thighs off (the right first), the hip's correctives moving: the second seam never collapses into the first
      # stump (twenty-ninth playtest: the crotch stretched between them)
      on arm && [[ -z $posed ]] && jobs+=("real thigh cuts $m, both legs|HIPMOVED=1 ARM=1 ARMBONE=Bip001-L-Thigh ARMEND=Bip001-L-Calf ARMAT=0.4 LEGFIRST=Bip001-R-Thigh|$m")
      # a calf cut: its stub's carrier rides the thigh, never the hip's jiggle body (a body of its own)
      on arm && [[ -z $posed ]] && jobs+=("real calf cut $m|ARM=1 ARMBONE=Bip001-L-Calf ARMEND=Bip001-L-Foot ARMAT=0.5|$m")
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
  # a waist cut once the watch has seen every helper move (playtest 30, InnerSuit after an arm and the head came off):
  # a moved helper still takes each side's seam, none stays on its old weights stretched between the halves
  on waist && [[ -f ../../../.cache/work/vanilla/SB/Content/Art/Character/PC/CH_P_EVE_InnerSuit/CH_P_EVE_InnerSuit.uasset ]] &&
    jobs+=("real waist cut CH_P_EVE_InnerSuit, every helper moved|WAIST=1 ALLMOVED=1|CH_P_EVE_InnerSuit"
           "real waist cut CH_P_EVE_InnerSuit after the left arm, every helper moved|WAIST=1 ARMFIRST=1 ALLMOVED=1|CH_P_EVE_InnerSuit")
  # side panels under her arms tied to both halves by weight, few vertices over the cut: cut with the body, not sent
  # whole with the legs to stand up off her hips (thirty-seventh playtest)
  on waist && [[ -f ../../../.cache/work/vanilla/SB/Content/Art/Character/PC/CH_P_EVE_29/CH_P_EVE_29.uasset ]] &&
    jobs+=("real waist cut CH_P_EVE_29|WAIST=1|CH_P_EVE_29" "real waist cut CH_P_EVE_29 (posed)|WAIST=1 POSED=1|CH_P_EVE_29")
  on arm && [[ -f ../../../.cache/work/vanilla/SB/Content/Art/Character/PC/CH_P_EVE_10/CH_P_EVE_10.uasset ]] &&
    jobs+=("real thigh cut CH_P_EVE_10, her elbow by the hip|ARM=1 ARMBONE=Bip001-L-Thigh ARMEND=Bip001-L-Calf ARMAT=0.47 ELBOWHIP=1|CH_P_EVE_10"
           "real calf cut CH_P_EVE_10|ARM=1 ARMBONE=Bip001-L-Calf ARMEND=Bip001-L-Foot ARMAT=0.5|CH_P_EVE_10"
           "real thigh cuts CH_P_EVE_10, both legs|HIPMOVED=1 ARM=1 ARMBONE=Bip001-L-Thigh ARMEND=Bip001-L-Calf ARMAT=0.4 LEGFIRST=Bip001-R-Thigh|CH_P_EVE_10"
           "real thigh cut CH_P_EVE_10 near the knee, hip helpers moving|HIPMOVED=1 ARM=1 ARMBONE=Bip001-R-Thigh ARMEND=Bip001-R-Calf ARMAT=0.81|CH_P_EVE_10"
           "real thigh cut CH_P_EVE_10, hip helpers moving|HIPMOVED=1 ARM=1 ARMBONE=Bip001-L-Thigh ARMEND=Bip001-L-Calf ARMAT=0.47|CH_P_EVE_10"
           "real thigh cut CH_P_EVE_10, ActiveBoneIndices not found|NOACTIVE=1 ARM=1 ARMBONE=Bip001-L-Thigh ARMEND=Bip001-L-Calf ARMAT=0.47|CH_P_EVE_10"
           "real split CH_P_EVE_10, ActiveBoneIndices not found|NOACTIVE=1 POSED=|CH_P_EVE_10")
  on mark && [[ -f ../../../.cache/work/vanilla/SB/Content/Art/Character/PC/CH_P_EVE_10/CH_P_EVE_10.uasset ]] &&
    jobs+=("real hit mark CH_P_EVE_10|MARK=1|CH_P_EVE_10" "real hit mark CH_P_EVE_10 (posed)|MARK=1 POSED=1|CH_P_EVE_10")
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
