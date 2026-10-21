#!/usr/bin/env bash
# Build and run the skin cut harness natively (clang, ASan/UBSan), then the split on real outfit meshes when the
# build cache has them (test/real/run.sh).
set -euo pipefail
cd "$(dirname "$0")"
OUT=${TMPDIR:-/tmp}/sbslice-test
clang -O1 -g -fsanitize=address,undefined -w -o "$OUT" test_cut.c
ASAN_OPTIONS=detect_leaks=0 "$OUT" | tee "$OUT.log" | grep -v '^PASS$' || true
fail=0
grep -qx PASS "$OUT.log" || fail=1
if [[ -f ../../../.cache/work/vanilla/SB/Content/Art/Character/PC/CH_P_EVE_09/CH_P_EVE_09.uasset ]]; then
  for m in CH_P_EVE_09 CH_P_EVE_30; do
    for across in "" 1; do
      for posed in "" 1; do
        r=$(ACROSS=$across POSED=$posed real/run.sh "$m" 2>&1 | tail -1)
        echo "real split $m${across:+ across the waist}${posed:+ (posed)}: $r"
        [[ $r == PASS ]] || fail=1
      done
    done
    for posed in "" 1; do
      r=$(WAIST=1 POSED=$posed real/run.sh "$m" 2>&1 | tail -1)
      echo "real waist cut $m${posed:+ (posed)}: $r"
      [[ $r == PASS ]] || fail=1
      r=$(ARM=1 POSED=$posed real/run.sh "$m" 2>&1 | tail -1)
      echo "real arm cut $m (cape kept)${posed:+ (posed)}: $r"
      [[ $r == PASS ]] || fail=1
    done
  done
fi
[[ $fail == 0 ]] && echo PASS || echo FAIL
exit $fail
