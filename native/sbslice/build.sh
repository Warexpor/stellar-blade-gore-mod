#!/usr/bin/env bash
# Build sbslice.dll with clang + the lld that ships with Rust (no MSVC or Windows SDK needed).
set -euo pipefail
cd "$(dirname "$0")"
LLD=$(ls -d "$HOME"/.rustup/toolchains/*/lib/rustlib/x86_64-unknown-linux-gnu/bin/rust-lld 2>/dev/null | head -1)
[[ -x $LLD ]] || { echo "need rust-lld (rustup) for linking"; exit 1; }
OUT=${1:-build}
mkdir -p "$OUT"
llvm-dlltool -m i386:x86-64 -d kernel32.def -l "$OUT/kernel32.lib"
clang --target=x86_64-pc-windows-msvc -O2 -ffreestanding -fno-math-errno -fno-stack-protector -fno-builtin -mno-stack-arg-probe \
  -Wall -Wextra -c sbslice.c -o "$OUT/sbslice.obj"
"$LLD" -flavor link /dll /entry:DllMain /nodefaultlib /subsystem:windows "/out:$OUT/main.dll" \
  "$OUT/sbslice.obj" "$OUT/kernel32.lib"
echo "built $OUT/main.dll"
