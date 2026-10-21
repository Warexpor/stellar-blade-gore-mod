#!/usr/bin/env bash
# Install UE4SS (Stellar Blade build) + the Stellar Blade Gore Mod script + the SBSlice native helper (gore).
#   ./ue4ss/install.sh            install
#   ./ue4ss/install.sh --uninstall
# Steam launch option needed: WINEDLLOVERRIDES="dwmapi=n,b" ... %command%
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
GAME=${SB_GAME:-$HOME/.local/share/Steam/steamapps/common/StellarBlade}
BIN=$GAME/SB/Binaries/Win64
URL=https://github.com/Chrisr0/RE-UE4SS/releases/download/3.1.0-6/UE4SS_v3.1.0-6.zip
SHA=7c221c66f84ace0cfbb83130197572c455066a513fe315f3797b1da7f965931c
CACHE=$ROOT/.cache/ue4ss
MODS=$BIN/ue4ss/Mods
NEW=$MODS/StellarBladeGore
OLDS=("$MODS/EveRagdollProbe" "$MODS/Severed") # the script's earlier names

[[ -f $BIN/SB-Win64-Shipping.exe ]] || { echo "game not found at $GAME (set SB_GAME)"; exit 1; }

if [[ ${1:-} == --uninstall ]]; then
  rm -fv "$BIN/dwmapi.dll"
  rm -rf "$BIN/ue4ss" && echo "removed $BIN/ue4ss"
  exit 0
fi

mkdir -p "$CACHE"
ZIP=$CACHE/UE4SS_v3.1.0-6.zip
[[ -f $ZIP ]] || curl -sSL "$URL" -o "$ZIP"
echo "$SHA  $ZIP" | sha256sum -c --quiet
rm -rf "$CACHE/x"; unzip -q "$ZIP" -d "$CACHE/x"
SRC=$CACHE/x/UE4SS_v3.1.0-6

if [[ ! -d $BIN/ue4ss ]]; then
  cp "$SRC/dwmapi.dll" "$BIN/"
  cp -r "$SRC/ue4ss" "$BIN/"
fi
# keep the log and the schema-dump marker (also from the old name), replace everything else
KEEP=$(mktemp -d)
for d in "${OLDS[@]}" "$NEW"; do
  for l in probe.log severed.log stellarbladegore.log; do
    [[ -f $d/$l ]] && cat "$d/$l" >> "$KEEP/stellarbladegore.log"
  done
  [[ -f $d/usmap.done ]] && cp "$d/usmap.done" "$KEEP/"
done
rm -rf "${OLDS[@]}" "$NEW"
cp -r "$ROOT/ue4ss/StellarBladeGore" "$MODS/"
cp "$KEEP"/* "$NEW/" 2>/dev/null || true
rm -rf "$KEEP"
touch "$NEW/enabled.txt"
# sbslice.dll makes the gore cuts and unpins the mesh on respawn (see native/sbslice); UE4SS loads it as a C++ mod
"$ROOT/native/sbslice/build.sh" "$CACHE/sbslice" >/dev/null
rm -rf "$MODS/SBSlice"
mkdir -p "$MODS/SBSlice/dlls"
cp "$CACHE/sbslice/main.dll" "$MODS/SBSlice/dlls/main.dll"
cat > "$MODS/mods.txt" <<'EOF'
SBSlice : 1
StellarBladeGore : 1

; Built-in keybinds, do not move up!
Keybinds : 1
EOF
echo "installed UE4SS + StellarBladeGore into $BIN"
echo "log: $NEW/stellarbladegore.log (and $BIN/ue4ss/UE4SS.log)"
