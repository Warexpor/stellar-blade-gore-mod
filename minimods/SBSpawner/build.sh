#!/usr/bin/env bash
# Build SBSpawner's window DLL (as native/sbslice/build.sh: clang + Rust's lld) and stage the mod, laid out like the
# game folder: build/stage/SB/Binaries/Win64/ue4ss/Mods/{SBSpawner,SBSpawnerWindow}, zipped to build/SBSpawner.zip.
#   ./build.sh            build and stage
#   ./build.sh --install  and copy it into the game (not while it runs)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SB=$HERE/../../native/sbslice
LLD=$(ls -d "$HOME"/.rustup/toolchains/*/lib/rustlib/x86_64-unknown-linux-gnu/bin/rust-lld 2>/dev/null | head -1)
[[ -x $LLD ]] || { echo "need rust-lld (rustup) for linking"; exit 1; }
OUT=$HERE/build
mkdir -p "$OUT"
for d in kernel32 user32 gdi32; do llvm-dlltool -m i386:x86-64 -d "$SB/$d.def" -l "$OUT/$d.lib"; done
clang --target=x86_64-pc-windows-msvc -O2 -ffreestanding -fno-builtin -fno-stack-protector -mno-stack-arg-probe \
  -Wall -Wextra -c "$HERE/native/window.c" -o "$OUT/window.obj"
"$LLD" -flavor link /dll /entry:DllMain /nodefaultlib /subsystem:windows "/out:$OUT/main.dll" \
  "$OUT/window.obj" "$OUT/kernel32.lib" "$OUT/user32.lib" "$OUT/gdi32.lib"
STAGE=$OUT/stage
MODS=$STAGE/SB/Binaries/Win64/ue4ss/Mods
rm -rf "$STAGE"; mkdir -p "$MODS/SBSpawner/Scripts" "$MODS/SBSpawnerWindow/dlls"
cp "$HERE/Scripts/main.lua" "$MODS/SBSpawner/Scripts/"
cp "$OUT/main.dll" "$MODS/SBSpawnerWindow/dlls/main.dll"
touch "$MODS/SBSpawner/enabled.txt" "$MODS/SBSpawnerWindow/enabled.txt"
cp "$HERE/README.md" "$STAGE/SBSpawner-README.md"
rm -f "$OUT/SBSpawner.zip"; (cd "$STAGE" && zip -qr -X "$OUT/SBSpawner.zip" .)
echo "built $OUT/SBSpawner.zip"
if [[ ${1:-} == --install ]]; then
  pgrep -af '[S]B-Win64-Shipping.exe SB' >/dev/null && { echo "the game is running: not installed"; exit 1; }
  GAME=${SB_GAME:-$HOME/.local/share/Steam/steamapps/common/StellarBlade}
  G=$GAME/SB/Binaries/Win64/ue4ss/Mods
  [[ -d $G ]] || { echo "no UE4SS Mods folder in $GAME"; exit 1; }
  rm -rf "$G/SBSpawner/Scripts" "$G/SBSpawnerWindow"
  cp -r "$MODS/SBSpawner" "$MODS/SBSpawnerWindow" "$G/"
  echo "installed into $G"
fi
