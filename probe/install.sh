#!/usr/bin/env bash
# Install UE4SS (Stellar Blade build) + the EveRagdollProbe script + the SBSlice native helper (gore).
#   ./probe/install.sh            install
#   ./probe/install.sh --uninstall
# Steam launch option needed: WINEDLLOVERRIDES="dwmapi=n,b" ... %command%
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
GAME=${SB_GAME:-$HOME/.local/share/Steam/steamapps/common/StellarBlade}
BIN=$GAME/SB/Binaries/Win64
URL=https://github.com/Chrisr0/RE-UE4SS/releases/download/3.1.0-6/UE4SS_v3.1.0-6.zip
SHA=7c221c66f84ace0cfbb83130197572c455066a513fe315f3797b1da7f965931c
CACHE=$ROOT/.cache/ue4ss

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
# keep the old log, replace everything else
LOGF=$BIN/ue4ss/Mods/EveRagdollProbe/probe.log
[[ -f $LOGF ]] && mv "$LOGF" "$BIN/ue4ss/Mods/probe.log.prev"
rm -rf "$BIN/ue4ss/Mods/EveRagdollProbe"
cp -r "$ROOT/probe/EveRagdollProbe" "$BIN/ue4ss/Mods/"
[[ -f $BIN/ue4ss/Mods/probe.log.prev ]] && mv "$BIN/ue4ss/Mods/probe.log.prev" "$LOGF"
touch "$BIN/ue4ss/Mods/EveRagdollProbe/enabled.txt"
# sbslice.dll makes the gore cuts and unpins the mesh on respawn (see native/sbslice); UE4SS loads it as a C++ mod
"$ROOT/native/sbslice/build.sh" "$CACHE/sbslice" >/dev/null
rm -rf "$BIN/ue4ss/Mods/SBSlice"
mkdir -p "$BIN/ue4ss/Mods/SBSlice/dlls"
cp "$CACHE/sbslice/main.dll" "$BIN/ue4ss/Mods/SBSlice/dlls/main.dll"
cat > "$BIN/ue4ss/Mods/mods.txt" <<'EOF'
SBSlice : 1
EveRagdollProbe : 1

; Built-in keybinds, do not move up!
Keybinds : 1
EOF
echo "installed UE4SS + EveRagdollProbe into $BIN"
echo "log: $BIN/ue4ss/Mods/EveRagdollProbe/probe.log (and $BIN/ue4ss/UE4SS.log)"
