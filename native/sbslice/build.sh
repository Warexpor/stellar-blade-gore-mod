#!/usr/bin/env bash
# Build sbslice.dll with clang + the lld that ships with Rust (no MSVC or Windows SDK needed).
set -euo pipefail
cd "$(dirname "$0")"
LLD=$(ls -d "$HOME"/.rustup/toolchains/*/lib/rustlib/x86_64-unknown-linux-gnu/bin/rust-lld 2>/dev/null | head -1)
[[ -x $LLD ]] || { echo "need rust-lld (rustup) for linking"; exit 1; }
OUT=${1:-build}
mkdir -p "$OUT"
VER=$(sed -n 's/^local VERSION = "\(.*\)"$/\1/p' ../../ue4ss/StellarBladeGore/Scripts/main.lua)
IFS=. read -r V1 V2 V3 <<< "$VER"
clang -E -P -x c -DSB_VER="$V1,$V2,$V3,0" -DSB_VER_STR="\"$VER\"" sbslice.rc -o "$OUT/sbslice.i.rc"
llvm-rc -no-preprocess -fo "$OUT/sbslice.res" "$OUT/sbslice.i.rc"
for d in kernel32 user32 gdi32; do llvm-dlltool -m i386:x86-64 -d $d.def -l "$OUT/$d.lib"; done
clang --target=x86_64-pc-windows-msvc -O2 -ffreestanding -fno-math-errno -fno-stack-protector -fno-builtin -mno-stack-arg-probe \
  -Wall -Wextra -c sbslice.c -o "$OUT/sbslice.obj"
clang --target=x86_64-pc-windows-msvc -O2 -ffreestanding -fno-builtin -fno-stack-protector -mno-stack-arg-probe \
  -Wall -Wextra -c spawner.c -o "$OUT/spawner.obj"
clang --target=x86_64-pc-windows-msvc -O2 -ffreestanding -fno-builtin -fno-stack-protector -mno-stack-arg-probe \
  -Wall -Wextra -c stats.c -o "$OUT/stats.obj"
"$LLD" -flavor link /dll /entry:DllMain /nodefaultlib /subsystem:windows "/out:$OUT/main.dll" \
  "$OUT/sbslice.obj" "$OUT/spawner.obj" "$OUT/stats.obj" "$OUT/sbslice.res" "$OUT/kernel32.lib" "$OUT/user32.lib" "$OUT/gdi32.lib"
echo "built $OUT/main.dll"
