#!/usr/bin/env bash
# Test a locally extracted, packed CNS wedding dress mesh; no third-party assets are distributed here.
# Usage: test_cns_wedding.sh /path/to/dress.bin
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
mesh=${1:?pass a packed dress mesh (see pack.py)}
bin=${TMPDIR:-/tmp}/sbslice-cns-wedding
clang -O1 -g -fsanitize=address,undefined -w -o "$bin" "$here/real_split.c" -lm
for side in L R; do
  other=L; [[ $side == L ]] && other=R
  for first in "" "Bip001-$other-Thigh"; do
    echo "Wedding dress: $side thigh${first:+ after $other thigh}"
    ASAN_OPTIONS=detect_leaks=0 ARM=1 ARMBONE="Bip001-$side-Thigh" ARMEND="Bip001-$side-Calf" \
      LEGFIRST="$first" ARMFLUNG=60 "$bin" "$mesh" | tail -5
  done
done
