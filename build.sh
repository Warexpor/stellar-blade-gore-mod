#!/usr/bin/env bash
# Build the Stellar Blade Gore Mod's IoStore patch from the installed game.
#   ./build.sh            build dist/ZZ_StellarBladeGore_P (core) and dist/ZZ_StellarBladeGore_Outfits_P (outfit
#                         meshes and physics), {utoc,ucas,pak} each, and verify them
#   ./build.sh --install  also copy them into the game's Paks/~mods
#   ./build.sh --uninstall
# Other mods in Paks/~mods are read as the game loads them: an outfit, face or show they replace is patched in
# their version, not vanilla's. Rebuild after adding or removing such a mod.
# SB_GAME: game install dir; SB_OUTFITS=0: install without the outfits container; SB_COMPRESS: IoStore block compression (zlib default, "none" to store raw)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
CACHE=$ROOT/.cache
GAME=${SB_GAME:-$HOME/.local/share/Steam/steamapps/common/StellarBlade}
PAKS=$GAME/SB/Content/Paks
MODS=$PAKS/~mods
NAME=ZZ_StellarBladeGore_P
OUTFITS=ZZ_StellarBladeGore_Outfits_P
OLD_NAMES=(ZZ_Severed_P ZZ_EveRagdollDeath_P) # earlier names; removed on install / uninstall
SPEC=$ROOT/mod/ragdoll_spec.json
DIST=$ROOT/dist

RETOC_REV=885a8dae740cb1ce1e41ff2e74f67f9f0c118237
UASSETAPI_REV=b4e8a012939295a6fd890ddc64e57ea78b709b95
SBSDK_REV=bed8151334aefdadc76972d68a11f5b07927c336

log() { printf '\033[1m[build]\033[0m %s\n' "$*"; }

if [[ ${1:-} == --uninstall ]]; then
  for n in "$NAME" "$OUTFITS" "${OLD_NAMES[@]}"; do rm -fv "$MODS/$n".{utoc,ucas,pak}; done
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

# assetkit/patches: retoc-compress, block compression for to-zen (RETOC_COMPRESS), which retoc lacks;
# retoc-mixed-toc, reading other mods' containers of an older TOC layout (DirectoryIndex) with the game's
for p in "$ROOT"/assetkit/patches/retoc-*.patch; do
  if ! git -C "$CACHE/retoc" apply --reverse --check "$p" 2>/dev/null; then git -C "$CACHE/retoc" apply "$p"; fi
done
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
SRC=$CACHE/source
# The game's containers and every other mod's in ~mods (any depth), as one directory retoc reads in the game's
# order. The game mounts paks sorted by path, case-insensitively, and a later one wins; retoc picks the highest
# container by (_P suffix, name), case-sensitively. So each mod is linked under a name that ranks the same way:
# zzmod<rank>x_P. Ours and their earlier names are left out; a container retoc can't open (encrypted, another
# version) is skipped with a note. mods.txt: "<mod> <package>" for each package a mod ships, in load order.
rm -rf "$SRC"; mkdir -p "$SRC"
ln -s "$PAKS"/*.utoc "$PAKS"/*.ucas "$SRC/"
: > "$SRC/mods.txt"; : > "$SRC/remount.txt"
load_order() { # ~mods-relative paths on stdin, in the order the game mounts them
  python3 -c 'import sys; print("".join(sorted(sys.stdin, key=str.lower)), end="")'
}
rank=0
while IFS= read -r rel; do
  toc=$MODS/$rel stem=$(basename "$rel" .utoc)
  case " $NAME $OUTFITS ${OLD_NAMES[*]} " in *" $stem "*) continue ;; esac
  [[ -f ${toc%.utoc}.ucas ]] || { log "mods: $rel has no .ucas, skipped"; continue; }
  if ! "$RETOC" info "$toc" >/dev/null 2>&1; then log "mods: $rel can't be read (encrypted or another format), skipped"; continue; fi
  rank=$((rank + 1))
  link=$(printf 'zzmod%04dx_P' "$rank")
  ln -s "$toc" "$SRC/$link.utoc"; ln -s "${toc%.utoc}.ucas" "$SRC/$link.ucas"
  # a mod cooked in a project of another name mounts at ../../../<Project>/Content/ (SBPR does): still /Game/,
  # so its packages replace the game's; remount.txt notes them for legacy() below
  "$RETOC" list --path "$toc" | awk -v m="$stem" -v rm="$SRC/remount.txt" '$NF ~ /\.uasset$/ { p = $NF
    sub(/\.uasset$/, "", p)
    if (!sub(/^.*\/SB\/Content\//, "", p) && match(p, /^(\.\.\/)*[^\/]+\/Content\//)) {
      root = substr(p, 1, RLENGTH - 9); sub(/^(\.\.\/)*/, "", root); p = substr(p, RLENGTH + 1)
      print m, root, p >> rm
    }
    print m, p }' >> "$SRC/mods.txt"
  # a mod mounted after ours wins over it in game, so what it shares with ours stays its own, unpatched
  if [[ $(printf '%s\n' "$rel" "$NAME.utoc" | load_order | tail -1) == "$rel" ]]; then
    log "mods: $rel loads after this mod; rename it to sort before $NAME if it replaces an outfit"
  fi
done < <([[ -d $MODS ]] && (cd "$MODS" && find . -name '*.utoc' -printf '%P\n') | load_order)
(( rank )) && log "mods: reading $rank other mod(s) over the game ($(wc -l < "$SRC/mods.txt") packages)"
mod_of() { awk -v p="$1" '$2 == p { m = $1 } END { if (m) print m }' "$SRC/mods.txt"; }

# The source side (extracted packages, their JSON, the outfit scan; "vanilla" below, though other mods' packages are
# in it) only changes with the game, the other mods, the mappings, the tools or the outfits job, so it is kept
# between builds under that key; only the patched side is rebuilt.
KEY=$( { stat -L -c '%n %s %Y' "$SRC"/*.utoc "$SRC"/*.ucas; cat "$SRC/mods.txt"; md5sum "$SB_USMAP" "$ROOT/assetkit/sbtool/Program.cs" \
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
  (( ${#args[@]} )) && "$RETOC" to-legacy --no-shaders --no-script-objects "${args[@]}" "$SRC" "$W/vanilla" >/dev/null
  # a remounted mod's package lands under its own root next to the game's: move it over the game's when that
  # mod is the last to ship it (the one the game loads)
  local mod root f
  while read -r mod root r; do
    [[ -f $W/vanilla/$root/Content/$r.uasset && $(mod_of "$r") == "$mod" ]] || continue
    mkdir -p "$(dirname "$W/vanilla/SB/Content/$r")"; rm -f "$W/vanilla/SB/Content/$r".*
    for f in "$W/vanilla/$root/Content/$r".*; do mv -f "$f" "$W/vanilla/SB/Content/$r.${f##*.}"; done
  done < "$SRC/remount.txt"
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
  python3 "$ROOT/assetkit/outfits.py" meshes "$SPEC" "$O/table.json" "$SRC/mods.txt" > "$O/meshes.txt"
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
  awk '$2 != "-" {print $2}' "$O/pairs.txt" | sort -u > "$O/physics.txt"
  log "outfits: $(wc -l < "$O/pairs.txt") body meshes, $(wc -l < "$O/physics.txt") physics assets"
  awk '$2 == "-" {print "  no physics asset (physfix.lua gives it one in game): " $1}' "$O/pairs.txt"
  legacy < "$O/physics.txt"
  undumped < "$O/physics.txt" | "${SBTOOL[@]}" dumpall "$W/vanilla/SB/Content" "$W/json" PhysicsAsset >> "$O/physics.log"
  grep '^bad' "$O/physics.log" | sort -u | sed 's/^/  skipped: /' || true
  if [[ ! -d $O/bones ]]; then
    awk '$2 != "-"' "$O/pairs.txt" | sort -k2,2 -u | awk '{print "SB/Content/" $1}' \
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

# Two containers: the core (shows, tables, face, voice) and the outfits (every outfit mesh and its physics asset,
# most of the size). Leaving the outfits one out keeps whatever outfit mods there are, without cuts or the
# ragdoll fixes on those outfits (the script falls back to its own physics fixes).
LO=$W/legacy_outfits
rm -rf "$LO"
if [[ -n $MESHINFO ]]; then
  awk '{print $1; if ($2 != "-") print $2}' "$W/outfits/pairs.txt" | sort -u | while read -r rel; do
    for f in "$W/legacy/SB/Content/$rel".*; do
      [[ -f $f ]] || continue
      mkdir -p "$(dirname "$LO/SB/Content/$rel")"
      mv "$f" "$LO/SB/Content/$rel.${f##*.}"
    done
  done
fi

log "packing IoStore"
mkdir -p "$DIST"; rm -f "$DIST/$NAME".* "$DIST/$OUTFITS".*
# zlib: every UE4 build can read it (no Oodle DLL needed here); outfit meshes take the pak from 1.4 GB to ~560 MB
RETOC_COMPRESS=${SB_COMPRESS:-zlib} "$RETOC" to-zen --version UE4_27 "$W/legacy" "$DIST/$NAME.utoc" >/dev/null
if [[ -d $LO ]]; then
  RETOC_COMPRESS=${SB_COMPRESS:-zlib} "$RETOC" to-zen --version UE4_27 "$LO" "$DIST/$OUTFITS.utoc" >/dev/null
fi

# what came from another mod, so a removed mod is known to need a rebuild
: > "$DIST/sources.txt"
lines "${JSON_ASSETS[@]}" "${MESH_ASSETS[@]}" | sort -u | while read -r rel; do
  m=$(mod_of "$rel"); if [[ -n $m ]]; then echo "$m $rel" >> "$DIST/sources.txt"; fi
done
if [[ -s $DIST/sources.txt ]]; then
  log "patched over other mods (rebuild if you remove one):"
  awk '{n[$1]++} END {for (m in n) printf "  %s: %d package(s)\n", m, n[m]}' "$DIST/sources.txt" | sort
fi

log "verifying"
# read back through a composite of global.utoc (script objects) + the mod containers
mkdir -p "$W/composite"
ln -sf "$PAKS/global.utoc" "$PAKS/global.ucas" "$W/composite/"
cp "$DIST/$NAME".* "$W/composite/"
[[ -d $LO ]] && cp "$DIST/$OUTFITS".* "$W/composite/"
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
  for n in "$OUTFITS" "${OLD_NAMES[@]}"; do rm -fv "$MODS/$n".{utoc,ucas,pak}; done
  cp -v "$DIST/$NAME".* "$MODS/"
  if [[ -f $DIST/$OUTFITS.utoc && ${SB_OUTFITS:-1} != 0 ]]; then cp -v "$DIST/$OUTFITS".* "$MODS/"; fi
fi
