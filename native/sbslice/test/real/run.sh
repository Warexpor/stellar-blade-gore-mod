#!/usr/bin/env bash
# The vertical split on a real outfit mesh (both halves on one shared mesh asset, as in game): kept skin must not
# move when the sinks collapse, nor follow the limbs each half drops. Needs the vanilla cache of ./build.sh.
#   test/real/run.sh [outfit, default CH_P_EVE_09] [obj prefix]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
MESH=${1:-CH_P_EVE_09}
OUT=${TMPDIR:-/tmp}/sbslice-real
mkdir -p "$OUT"
PKG=vanilla/SB/Content/Art/Character/PC/$MESH/$MESH
[[ -f $ROOT/.cache/work/$PKG.uasset ]] || { echo "no $PKG in .cache/work (run ./build.sh first)"; exit 2; }
if [[ ! -f $OUT/$MESH.bin ]]; then
  DOTNET_ROOT=$ROOT/.cache/dotnet PATH=$ROOT/.cache/dotnet:$PATH \
    "$ROOT/.cache/meshtool/meshtool" dump "$ROOT/.cache/work/vanilla" "$ROOT/mappings/SB.usmap" "$PKG" "$OUT/$MESH.json" >/dev/null
  python3 "$HERE/pack.py" "$OUT/$MESH.json" "$OUT/$MESH.bin"
fi
clang -O1 -g -fsanitize=address,undefined -w -o "$OUT/real_split" "$HERE/real_split.c"
ASAN_OPTIONS=detect_leaks=0 "$OUT/real_split" "$OUT/$MESH.bin" ${2:+"$2"} | cut -c1-240
