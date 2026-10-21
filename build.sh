#!/usr/bin/env bash
# Build the Stellar Blade Gore Mod's IoStore patch from the installed game.
#   ./build.sh            build dist/ZZ_StellarBladeGore_P.{utoc,ucas,pak} and verify it
#   ./build.sh --install  also copy it into the game's Paks/~mods
#   ./build.sh --uninstall
# SB_GAME: game install dir; SB_COMPRESS: IoStore block compression (zlib default, "none" to store raw)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
CACHE=$ROOT/.cache
GAME=${SB_GAME:-$HOME/.local/share/Steam/steamapps/common/StellarBlade}
PAKS=$GAME/SB/Content/Paks
MODS=$PAKS/~mods
NAME=ZZ_StellarBladeGore_P
OLD_NAMES=(ZZ_Severed_P ZZ_EveRagdollDeath_P) # earlier names; removed on install / uninstall
SPEC=$ROOT/mod/ragdoll_spec.json
DIST=$ROOT/dist

RETOC_REV=885a8dae740cb1ce1e41ff2e74f67f9f0c118237
UASSETAPI_REV=b4e8a012939295a6fd890ddc64e57ea78b709b95
SBSDK_REV=bed8151334aefdadc76972d68a11f5b07927c336

log() { printf '\033[1m[build]\033[0m %s\n' "$*"; }

if [[ ${1:-} == --uninstall ]]; then
  for n in "$NAME" "${OLD_NAMES[@]}"; do rm -fv "$MODS/$n".{utoc,ucas,pak}; done
  exit 0
fi

[[ -f $PAKS/pakchunk0-WindowsNoEditor.utoc ]] || { echo "game not found at $GAME (set SB_GAME)"; exit 1; }
mkdir -p "$CACHE"

fetch() { # url dir rev
  if [[ ! -d $2/.git ]]; then git clone -q "$1" "$2"; fi
  git -C "$2" fetch -q --depth 1 origin "$3" 2>/dev/null || true
  git -C "$2" checkout -q "$3"
}

fetch https://github.com/trumank/retoc "$CACHE/retoc" "$RETOC_REV"
fetch https://github.com/atenfyr/UAssetAPI "$CACHE/UAssetAPI" "$UASSETAPI_REV"
fetch https://github.com/a5tronomy/SB "$CACHE/sbsdk" "$SBSDK_REV"

# assetkit/patches/retoc-compress.patch: block compression for to-zen (RETOC_COMPRESS), which retoc lacks
if ! git -C "$CACHE/retoc" apply --reverse --check "$ROOT/assetkit/patches/retoc-compress.patch" 2>/dev/null; then
  git -C "$CACHE/retoc" apply "$ROOT/assetkit/patches/retoc-compress.patch"
fi
RETOC=$CACHE/retoc/target/release/retoc
log "building retoc"
(cd "$CACHE/retoc" && cargo build -q --release -p retoc_cli)

if dotnet --list-sdks 2>/dev/null | grep -q '^10\.'; then
  DOTNET=dotnet
else
  DOTNET=$CACHE/dotnet/dotnet
  if [[ ! -x $DOTNET ]]; then
    log "installing .NET 10 SDK into .cache"
    curl -sSL https://dot.net/v1/dotnet-install.sh -o "$CACHE/dotnet-install.sh"
    bash "$CACHE/dotnet-install.sh" --channel 10.0 --install-dir "$CACHE/dotnet" >/dev/null
  fi
  export DOTNET_ROOT=$CACHE/dotnet
fi
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

log "building sbtool"
"$DOTNET" build -c Release -v q -nologo "$ROOT/assetkit/sbtool" -o "$CACHE/sbtool" >/dev/null
SBTOOL=("$DOTNET" "$CACHE/sbtool/sbtool.dll")

# mappings/SB.usmap is UE4SS's DumpUSMAP of the running game (full engine + SB schema). Without it, fall back
# to mappings generated from the SB header dump, which only covers SB's own classes (enough for the shows).
if [[ -f $ROOT/mappings/SB.usmap ]]; then
  export SB_USMAP=$ROOT/mappings/SB.usmap
else
  log "generating mappings"
  python3 "$ROOT/assetkit/mkusmap.py" "$CACHE/sbsdk" "$CACHE/sb.usmap" | head -1
  export SB_USMAP=$CACHE/sb.usmap
fi

W=$CACHE/work
# The vanilla side (extracted packages, their JSON, the outfit scan) only changes with the game, the mappings, the
# tools or the outfits job, so it is kept between builds under that key; only the patched side is rebuilt.
KEY=$( { stat -c '%n %s %Y' "$PAKS"/*.utoc "$PAKS"/*.ucas; md5sum "$SB_USMAP" "$ROOT/assetkit/sbtool/Program.cs" \
  "$ROOT/assetkit/meshtool/Program.cs"; echo "$RETOC_REV $UASSETAPI_REV"
  python3 -c 'import json,sys; j=json.load(open(sys.argv[1])).get("outfits", {}); print({k: j.get(k) for k in ("enabled", "table", "skeleton", "only", "skip")})' "$SPEC"
} | md5sum | cut -d' ' -f1)
if [[ $(cat "$W/vanilla.key" 2>/dev/null) != "$KEY" ]]; then
  log "vanilla cache is stale or missing: extracting everything"
  rm -rf "$W"
fi
rm -f "$W/vanilla.key" # written back once the vanilla side is complete
rm -rf "$W/json_out" "$W/legacy" "$W/verify" "$W/composite" "$W/vendor"
mkdir -p "$W/vanilla" "$W/json" "$W/json_out" "$W/legacy" "$W/verify"
legacy() { # extract packages (SB/Content-relative, one per line on stdin) to $W/vanilla, unless already there
  local args=() r
  while read -r r; do [[ -f $W/vanilla/SB/Content/$r.uasset ]] || args+=(-f "Content/$r."); done
  (( ${#args[@]} )) && "$RETOC" to-legacy --no-shaders --no-script-objects "${args[@]}" "$PAKS" "$W/vanilla" >/dev/null
  return 0
}
undumped() { # the packages on stdin that have no JSON yet
  local r
  while read -r r; do [[ -f $W/json/$r.json ]] || echo "$r"; done
}

# Outfits: expand the spec's "outfits" job into cpuaccess + physics jobs for every Eve outfit (assetkit/outfits.py).
# Meshes never go through JSON: sbtool reads what the scan needs (meshinfo) and flips their CPU access in place.
MESHINFO=
if python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("outfits", {}).get("enabled") else 1)' "$SPEC"; then
  log "building meshtool"
  DOTNET=$DOTNET "$ROOT/assetkit/meshtool/build.sh" >/dev/null
  O=$W/outfits; mkdir -p "$O"
  TABLE=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["outfits"]["table"])' "$SPEC")
  if [[ ! -f $O/table.json ]]; then
    echo "$TABLE" | legacy
    "${SBTOOL[@]}" dump "$W/vanilla/SB/Content/$TABLE.uasset" "$O/table.json"
  fi
  python3 "$ROOT/assetkit/outfits.py" meshes "$SPEC" "$O/table.json" > "$O/meshes.txt"
  log "outfits: reading $(wc -l < "$O/meshes.txt") meshes"
  legacy < "$O/meshes.txt"
  MESHINFO=$O/meshinfo.log
  if [[ ! -f $MESHINFO ]]; then
    "${SBTOOL[@]}" meshinfo "$W/vanilla/SB/Content" < "$O/meshes.txt" > "$MESHINFO.tmp"
    mv "$MESHINFO.tmp" "$MESHINFO"
  fi
  grep '^bad' "$MESHINFO" | sed 's/^/  skipped: /' || true
  grep -c '^missing' "$MESHINFO" | sed 's/$/ table entries not shipped in the game/; s/^/  /' || true
  python3 "$ROOT/assetkit/outfits.py" physics "$SPEC" "$MESHINFO" | sort > "$O/pairs.txt"
  awk '{print $2}' "$O/pairs.txt" | sort -u > "$O/physics.txt"
  log "outfits: $(wc -l < "$O/pairs.txt") body meshes, $(wc -l < "$O/physics.txt") physics assets"
  legacy < "$O/physics.txt"
  undumped < "$O/physics.txt" | "${SBTOOL[@]}" dumpall "$W/vanilla/SB/Content" "$W/json" PhysicsAsset >> "$O/physics.log"
  grep '^bad' "$O/physics.log" | sort -u | sed 's/^/  skipped: /' || true
  if [[ ! -d $O/bones ]]; then
    sort -k2,2 -u "$O/pairs.txt" | awk '{print "SB/Content/" $1}' \
      | "$DOTNET" "$CACHE/meshtool/meshtool.dll" bones "$W/vanilla/SB" "$SB_USMAP" - "$O/bones.tmp"
    mv "$O/bones.tmp" "$O/bones"
  fi
  python3 "$ROOT/assetkit/outfits.py" expand "$SPEC" "$W/json" "$O/bones" "$O/pairs.txt" "$W/spec.json" > "$O/overlaps.txt"
  SPEC=$W/spec.json
fi

# json: patched through JSON (shows, tables, physics, blueprint); mesh: cpuaccess, patched by sbtool
mapfile -t JSON_ASSETS < <(python3 -c 'import json,sys; print("\n".join(r for r, j in json.load(open(sys.argv[1]))["assets"].items() if j["mode"] != "cpuaccess"))' "$SPEC")
mapfile -t MESH_ASSETS < <(python3 -c 'import json,sys; print("\n".join(r for r, j in json.load(open(sys.argv[1]))["assets"].items() if j["mode"] == "cpuaccess"))' "$SPEC")
MESH_LODS=$(python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print(",".join(str(l) for l in sorted({l for j in s["assets"].values() if j["mode"] == "cpuaccess" for l in j.get("lods", [0])})) or "0")' "$SPEC")
mapfile -t SOURCES < <(python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print("\n".join(sorted({j.get("from", r) for r, j in s["assets"].items() if j["mode"] not in ("cpuaccess", "vendor")} | {s["donor"]})))' "$SPEC")
lines() { (( $# )) && printf '%s\n' "$@"; return 0; }

log "extracting ${#SOURCES[@]} assets"
lines "${SOURCES[@]}" | legacy
lines "${MESH_ASSETS[@]}" | legacy
for rel in "${SOURCES[@]}"; do
  [[ -f $W/vanilla/SB/Content/$rel.uasset ]] || { echo "missing in game: $rel"; exit 1; }
done
lines "${SOURCES[@]}" | undumped | "${SBTOOL[@]}" dumplist "$W/vanilla/SB/Content" "$W/json"
echo "$KEY" > "$W/vanilla.key"

# vendor: third-party packages shipped as they are (third_party/), dumped to JSON like the vanilla side
export SB_VENDOR_JSON=$W/vendor
mkdir -p "$SB_VENDOR_JSON"
while read -r rel file; do
  [[ -n $rel ]] || continue
  mkdir -p "$(dirname "$SB_VENDOR_JSON/$rel")"
  "${SBTOOL[@]}" dump "$ROOT/$file.uasset" "$SB_VENDOR_JSON/$rel.json" >/dev/null
done < <(python3 -c 'import json,sys; [print(r, j["file"]) for r, j in json.load(open(sys.argv[1]))["assets"].items() if j["mode"] == "vendor"]' "$SPEC")

log "patching"
python3 "$ROOT/assetkit/patch_shows.py" "$SPEC" "$W/json" "$W/json_out" ${MESHINFO:+"$MESHINFO"}
lines "${JSON_ASSETS[@]}" | "${SBTOOL[@]}" fromjsonall "$W/json_out" "$W/legacy/SB/Content"
if (( ${#MESH_ASSETS[@]} )); then
  lines "${MESH_ASSETS[@]}" | "${SBTOOL[@]}" cpuaccess "$W/vanilla/SB/Content" "$W/legacy/SB/Content" "$MESH_LODS" > "$W/cpuaccess.log"
  if grep '^bad' "$W/cpuaccess.log"; then echo "cpuaccess failed"; exit 1; fi
fi

log "packing IoStore"
mkdir -p "$DIST"; rm -f "$DIST/$NAME".*
# zlib: every UE4 build can read it (no Oodle DLL needed here); outfit meshes take the pak from 1.4 GB to ~560 MB
RETOC_COMPRESS=${SB_COMPRESS:-zlib} "$RETOC" to-zen --version UE4_27 "$W/legacy" "$DIST/$NAME.utoc" >/dev/null

log "verifying"
# read back through a composite of global.utoc (script objects) + the mod container
mkdir -p "$W/composite"
ln -sf "$PAKS/global.utoc" "$PAKS/global.ucas" "$W/composite/"
cp "$DIST/$NAME".* "$W/composite/"
"$RETOC" to-legacy --no-shaders --no-script-objects "$W/composite" "$W/verify" >/dev/null
lines "${JSON_ASSETS[@]}" | "${SBTOOL[@]}" dumplist "$W/verify/SB/Content" "$W/verify/json"
SB_PATCHED_JSON=$W/json_out python3 "$ROOT/assetkit/verify.py" "$SPEC" "$W/json" "$W/verify/json" --no-meshes
if (( ${#MESH_ASSETS[@]} )); then
  lines "${MESH_ASSETS[@]}" | "${SBTOOL[@]}" checkcpu "$W/vanilla/SB/Content" "$W/verify/SB/Content" "$MESH_LODS" > "$W/checkcpu.log"
  if grep '^bad' "$W/checkcpu.log"; then echo "VERIFY FAILED: meshes"; exit 1; fi
  echo "ok  cpuaccess $(grep -c '^ok' "$W/checkcpu.log") meshes, LOD$MESH_LODS CPU access and nothing else"
fi
ls -l "$DIST"

if [[ ${1:-} == --install ]]; then
  mkdir -p "$MODS"
  for n in "${OLD_NAMES[@]}"; do rm -fv "$MODS/$n".{utoc,ucas,pak}; done
  cp -v "$DIST/$NAME".* "$MODS/"
fi
