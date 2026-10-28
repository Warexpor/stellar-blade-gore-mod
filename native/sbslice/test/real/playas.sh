#!/usr/bin/env bash
# The Play As characters (the Stellar Blade Play As mod, github.com/Warexpor/stellar-blade-play-as: their meshes on
# Eve's own components) through this mod's cut and ragdoll fixes, as for her outfits:
#   cuts: the outfit sweep's jobs (sweep/jobs.sh) on Tachy's NPC body (CH_NPC_TachyNPC_Body) and Scarlet's
#     (CH_M_NA_961, her head in it: a lengthwise split's half keeping the head has no neck lid to send, and a beheading
#     cuts it with the body), Tachy's and Raven's faces as Eve's is cut (HEAD=1 FACESINK=1; Raven's CH_M_NA_53_Facial
#     goes on Eve's face component), Raven's hair (CH_M_NA_53_Hair, at Eve's head) cut at the neck; Raven's suit is CH_P_EVE_11, in the sweep already, and Eve's base body (CH_P_EVE_01_Body)
#     runs with them as the reference. Compared with results-playas.txt.gz: a job that passed there and fails now is
#     a regression (the fails there are the sweep's leaned-cap class, as on Eve's own body)
#   ragdoll: physfix.lua's runtime fix of Tachy's and Scarlet's physics assets held to what the build's outfits job
#     would make of them (phys/parity.py: damping, joint ranges, the collision table, Tachy's loose thigh twists
#     jointed), Eve's base asset alongside
# Needs a build's cache (./build.sh: retoc, the game's containers, meshtool, sbtool) and lua.
#   test/real/playas.sh [--rebase]   --rebase: the results become the new results-playas.txt.gz
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
C=$ROOT/.cache
[[ -x $C/retoc/target/release/retoc && -d $C/source && -f $C/work/vanilla.key ]] || { echo "no build cache (run ./build.sh first)"; exit 2; }
export TMPDIR=${TMPDIR:-/tmp}
OUT=$TMPDIR/sbslice-playas
RS=$TMPDIR/sbslice-real
mkdir -p "$OUT" "$RS"
# their packages, extracted once next to the vanilla cache (a dir named vanilla, as test/real/run.sh wants)
X=$C/work/playas/vanilla
CT=$X/SB/Content
if [[ ! -f $CT/DLC_2/Art/Character/Monster/CH_M_NA_961/CH_M_NA_961.uasset ]]; then
  "$C/retoc/target/release/retoc" to-legacy --no-shaders --no-script-objects -f Content/Art/Character/NPC/CH_NPC_TachyNPC/ \
    -f Content/Art/Character/Monster/CH_M_NA_53/ -f Content/DLC_2/Art/Character/Monster/CH_M_NA_961/ "$C/source" "$X" >/dev/null
fi
TACHY=Art/Character/NPC/CH_NPC_TachyNPC/CH_NPC_TachyNPC_Body
TFACE=Art/Character/NPC/CH_NPC_TachyNPC/CH_NPC_TachyNPC_Face_Jali2
SCARLET=DLC_2/Art/Character/Monster/CH_M_NA_961/CH_M_NA_961
RHAIR=Art/Character/Monster/CH_M_NA_53/CH_M_NA_53_Hair
RFACE=Art/Character/Monster/CH_M_NA_53/CH_M_NA_53_Facial
for p in $TACHY $TFACE $SCARLET $RHAIR $RFACE; do
  [[ -f $RS/$(basename $p).bin ]] || VANILLA=$X PKG=vanilla/SB/Content/$p ARM=1 "$HERE/run.sh" "$(basename $p)" >/dev/null 2>&1 || true
done
for p in CH_P_EVE_11/CH_P_EVE_11 CH_P_EVE_01/CH_P_EVE_01_Body; do
  [[ -f $RS/$(basename $p).bin ]] || PKG=vanilla/SB/Content/Art/Character/PC/$p ARM=1 "$HERE/run.sh" "$(basename $p)" >/dev/null 2>&1 || true
done
for m in CH_NPC_TachyNPC_Body CH_NPC_TachyNPC_Face_Jali2 CH_M_NA_961 CH_M_NA_53_Hair CH_M_NA_53_Facial CH_P_EVE_11 CH_P_EVE_01_Body; do
  [[ -f $RS/$m.bin ]] || { echo "no mesh dump for $m"; exit 1; }
done

# ---- cuts ----
J=$OUT/jobs.txt
{
  PC=$CT/Art/Character MESHES=<(echo NPC/CH_NPC_TachyNPC/CH_NPC_TachyNPC_Body) bash "$HERE/sweep/jobs.sh"
  PC=$CT/DLC_2/Art/Character/Monster MESHES=<(echo CH_M_NA_961/CH_M_NA_961) bash "$HERE/sweep/jobs.sh"
  MESHES=<(printf '%s\n' CH_P_EVE_11/CH_P_EVE_11 CH_P_EVE_01/CH_P_EVE_01_Body) bash "$HERE/sweep/jobs.sh"
  for at in 0.5 0.7 1.0 1.2; do echo "CH_NPC_TachyNPC_Face_Jali2|face $at|HEAD=1 FACESINK=1 HEADAT=$at"; done
  for at in 0.5 0.7 1.0 1.2; do echo "CH_M_NA_53_Facial|face $at|HEAD=1 FACESINK=1 HEADAT=$at"; done
  for at in 0.7 0.85 1.0; do echo "CH_M_NA_53_Hair|head plane $at|HEAD=1 HEADPLANE=1 HEADAT=$at"; done
} > "$J"
MESHES=/dev/null bash "$HERE/sweep/sweep.sh" "$OUT/sweep.txt" "$J" | sed 's/^/cuts: /'
fail=0
r=$(bash "$HERE/sweep/compare.sh" "$OUT/sweep.txt" "$HERE/sweep/results-playas.txt.gz" 2>/dev/null) || r="no results-playas.txt.gz"
echo "cuts: $r" | head -1
if [[ $r != *" 0 pass -> fail"* ]]; then echo "$r" | tail -n +2 | cut -c1-240; fail=1; fi
[[ ${1:-} == --rebase ]] && sort "$OUT/sweep.txt" | gzip -9n > "$HERE/sweep/results-playas.txt.gz" && echo "cuts: results-playas.txt.gz rebased"

# ---- ragdoll: physfix.lua against the outfits job on their physics assets ----
W=$OUT/work
rm -rf "$W"; mkdir -p "$W/outfits/bones/SB/Content"
export SB_USMAP=$ROOT/mappings/SB.usmap
printf '%s\n' "${TACHY}_Physics" "${SCARLET}_Physics" | "$C/dotnet/dotnet" "$C/sbtool/sbtool.dll" dumpall "$CT" "$W/own" PhysicsAsset \
  | grep -v '^ok ' && { echo "ragdoll: their physics assets don't dump"; exit 1; }
# the build's JSON (the donor shows patch_shows.py reads) with theirs over it
cp -rs "$C/work/json" "$W/json"; cp -r "$W/own/." "$W/json/"
for p in $TACHY $SCARLET; do
  mkdir -p "$W/outfits/bones/SB/Content/$(dirname $p)"
  DOTNET_ROOT=$C/dotnet PATH=$C/dotnet:$PATH "$C/meshtool/meshtool" dump "$X" "$SB_USMAP" "vanilla/SB/Content/$p" "$OUT/mesh.json" >/dev/null
  python3 -c 'import json,sys; json.dump({"bones": json.load(open(sys.argv[1]))["bones"]}, open(sys.argv[2], "w"))' "$OUT/mesh.json" \
    "$W/outfits/bones/SB/Content/$p.json"
done
rm -f "$OUT/mesh.json"
E1=Art/Character/PC/CH_P_EVE_01
mkdir -p "$W/outfits/bones/SB/Content/$E1"
cp "$C/work/outfits/bones/SB/Content/$E1/CH_P_EVE_01_Body.json" "$W/outfits/bones/SB/Content/$E1/"
printf '%s %s\n' "$TACHY" "${TACHY}_Physics" "$SCARLET" "${SCARLET}_Physics" "$E1/CH_P_EVE_01_Body" "$E1/CH_P_EVE_01_Physics" \
  > "$W/outfits/pairs.txt"
python3 "$ROOT/assetkit/outfits.py" expand "$ROOT/mod/ragdoll_spec.json" "$W/json" "$W/outfits/bones" "$W/outfits/pairs.txt" \
  "$W/full.json" | sed 's/^/ragdoll: /' | cut -c1-200
# only the physics jobs: the rest of the spec patches shows this doesn't need
python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); s["assets"]={k: v for k, v in s["assets"].items() if v.get("mode") == "physics"}; json.dump(s, open(sys.argv[2], "w"))' \
  "$W/full.json" "$W/spec.json"
python3 "$ROOT/assetkit/patch_shows.py" "$W/spec.json" "$W/json" "$W/json_out" >/dev/null
if r=$(python3 "$HERE/../phys/parity.py" "$W" "$ROOT/ue4ss/StellarBladeGore/Scripts" "$OUT/parity" 2>&1); then
  echo "ragdoll: $(echo "$r" | tail -1)"
else
  echo "$r" | grep -v '^ok ' | sed 's/^/ragdoll: /'; fail=1
fi
echo $([[ $fail == 0 ]] && echo PASS || echo FAIL)
exit $fail
