#!/usr/bin/env bash
# Install UE4SS (Stellar Blade build) + the Stellar Blade Gore Mod script + the SBSlice native helper (gore).
#   ./ue4ss/install.sh            install
#   ./ue4ss/install.sh --uninstall       this mod only (UE4SS and other mods stay)
#   ./ue4ss/install.sh --uninstall-all   UE4SS too
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

# every script must load: gore.lua past Lua's 200 locals per chunk loaded as nothing in game, and no cut ran (playtest)
if [[ ${1:-} != --uninstall* ]] && command -v luac >/dev/null; then
  for f in "$ROOT"/ue4ss/StellarBladeGore/Scripts/*.lua; do
    luac -p "$f" || { echo "not installed: $f doesn't load"; exit 1; }
    # and reads no global but Lua's and UE4SS's: a local used above its definition is a nil global at run time
    # (gore.lua's seam hold called addr() before it was defined and never ran, playtest)
    bad=$(luac -l -p "$f" | grep -o 'GETTABUP.*_ENV "[A-Za-z_0-9]*"' | grep -o '"[^"]*"' | tr -d '"' | sort -u |
      grep -vxE 'assert|collectgarbage|debug|dofile|loadfile|load|error|io|ipairs|math|next|os|pairs|pcall|print|rawget|rawset|require|select|setmetatable|getmetatable|string|table|tonumber|tostring|type|xpcall|utf8|FName|FText|LoadAsset|StaticFindObject|StaticConstructObject|FindAllOf|FindFirstOf|FindObject|NotifyOnNewObject|RegisterHook|RegisterKeyBind|ExecuteInGameThread|ExecuteWithDelay|LoopAsync|DumpUSMAP|Key|ModifierKey|EInternalObjectFlags|EObjectFlags|UEHelpers' || true)
    [[ -z $bad ]] || { echo "not installed: $f reads undefined globals: $bad"; exit 1; }
  done
fi

if [[ ${1:-} == --uninstall ]]; then
  # only ours: UE4SS and other mods stay (--uninstall-all removes UE4SS too)
  rm -rf "$NEW" "$MODS/SBSlice" "${OLDS[@]}" && echo "removed StellarBladeGore and SBSlice from $MODS"
  [[ -f $MODS/mods.txt ]] && sed -i -E '/^\s*(SBSlice|StellarBladeGore)\s*:/d' "$MODS/mods.txt"
  exit 0
fi
if [[ ${1:-} == --uninstall-all ]]; then
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
# the player's settings.lua and the in-game menu's menu.lua stay as they left them (main.lua makes settings.lua
# from settings.default.lua when there's none)
for f in settings.lua menu.lua; do [[ -f $NEW/Scripts/$f ]] && cp "$NEW/Scripts/$f" "$KEEP/$f"; done
rm -rf "${OLDS[@]}" "$NEW"
cp -r "$ROOT/ue4ss/StellarBladeGore" "$MODS/"
for f in settings.lua menu.lua; do [[ -f $KEEP/$f ]] && mv "$KEEP/$f" "$NEW/Scripts/$f"; done
cp "$KEEP"/* "$NEW/" 2>/dev/null || true
rm -rf "$KEEP"
touch "$NEW/enabled.txt"
# sbslice.dll makes the gore cuts and unpins the mesh on respawn (see native/sbslice); UE4SS loads it as a C++ mod
"$ROOT/native/sbslice/build.sh" "$CACHE/sbslice" >/dev/null
rm -rf "$MODS/SBSlice"
mkdir -p "$MODS/SBSlice/dlls"
cp "$CACHE/sbslice/main.dll" "$MODS/SBSlice/dlls/main.dll"
touch "$MODS/SBSlice/enabled.txt"
# mods.txt: ours out (enabled.txt turns them on, as the release zip does), every other mod's line kept as it is,
# Keybinds last (UE4SS wants it there)
python3 - "$MODS/mods.txt" <<'PY'
import os, re, sys
p = sys.argv[1]
lines = open(p).read().splitlines() if os.path.exists(p) else []
ours = ("SBSlice", "StellarBladeGore", "Keybinds")
keep = [l for l in lines if re.split(r"\s*:", l.strip(), maxsplit=1)[0] not in ours
        and not l.strip().startswith("; Built-in keybinds")]
while keep and not keep[-1].strip():
    keep.pop()
out = keep + ([""] if keep else []) + ["; Built-in keybinds, do not move up!", "Keybinds : 1"]
open(p, "w").write("\n".join(out) + "\n")
PY
echo "installed UE4SS + StellarBladeGore into $BIN"
echo "log: $NEW/stellarbladegore.log (and $BIN/ue4ss/UE4SS.log)"
