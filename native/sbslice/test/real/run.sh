#!/usr/bin/env bash
# The vertical split on a real outfit mesh (both halves on one shared mesh asset, as in game): kept skin must not
# move when the sinks collapse, nor follow the limbs each half drops. Needs the vanilla cache of ./build.sh.
#   test/real/run.sh [outfit, default CH_P_EVE_09] [obj prefix]
# VANILLA=<a legacy cache dir named vanilla> and PKG=vanilla/SB/Content/... (an enemy's body, say) override the outfit's
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
CACHE=${SB_CACHE:-$ROOT/.cache}
MESH=${1:-CH_P_EVE_09}
OUT=${TMPDIR:-/tmp}/sbslice-real
mkdir -p "$OUT"
VANILLA=${VANILLA:-$CACHE/work/vanilla}
PKG=${PKG:-vanilla/SB/Content/Art/Character/PC/$MESH/$MESH}
[[ -f $(dirname "$VANILLA")/$PKG.uasset ]] || { echo "no $PKG in $VANILLA (run ./build.sh first)"; exit 2; }
meshbin=$OUT/$MESH.bin
if [[ ! -f $meshbin ]]; then
  jobdir=$(mktemp -d "$OUT/dump.XXXXXXXX")
  trap 'rm -rf "$jobdir"' EXIT
  meshbin=$jobdir/mesh.bin
  if [[ ${MSYSTEM:-} ]]; then
    "$CACHE/dotnet/dotnet.exe" "$CACHE/meshtool/meshtool.dll" dump "$VANILLA" "$ROOT/mappings/SB.usmap" "$PKG" "$jobdir/mesh.json" >/dev/null
  else
    DOTNET_ROOT=$CACHE/dotnet PATH=$CACHE/dotnet:$PATH \
      "$CACHE/meshtool/meshtool" dump "$VANILLA" "$ROOT/mappings/SB.usmap" "$PKG" "$jobdir/mesh.json" >/dev/null
  fi
  python3 "$HERE/pack.py" "$jobdir/mesh.json" "$meshbin"
  rm -f "$jobdir/mesh.json"
fi
# built once, again only when the harness or the DLL source changed (parallel runs: built to a temp name, renamed in)
BIN=$OUT/real_split
if [[ ! -x $BIN || $HERE/real_split.c -nt $BIN || $HERE/../../sbslice.c -nt $BIN ]]; then
  clang -O1 -g -fsanitize=address,undefined -w -o "$BIN.$BASHPID" "$HERE/real_split.c" -lm || exit 1
  mv -f "$BIN.$BASHPID" "$BIN"
fi
ASAN_OPTIONS=detect_leaks=0 "$BIN" "$meshbin" ${2:+"$2"} | cut -c1-240
