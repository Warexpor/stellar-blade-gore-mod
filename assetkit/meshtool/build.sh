#!/usr/bin/env bash
# Build meshtool into .cache/meshtool against a pinned CUE4Parse (.cache/cue4parse).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
CUE4PARSE_REV=de0e4e956d33fd6f3a6d417e9faccf24afc5603c
src=$root/.cache/cue4parse
dotnet=${DOTNET:-$root/.cache/dotnet/dotnet}
[[ $dotnet == */* ]] && export DOTNET_ROOT=$(dirname "$dotnet")

if [[ ! -d $src/.git ]]; then
  git clone -q https://github.com/FabianFG/CUE4Parse "$src"
fi
if [[ $(git -C "$src" rev-parse HEAD) != "$CUE4PARSE_REV" ]]; then
  git -C "$src" fetch -q origin
  git -C "$src" checkout -q --force "$CUE4PARSE_REV"
fi
git -C "$src" submodule update -q --init --recursive

# ExportSession.ResolveOutputPath turns '/' into '\' unconditionally, which on Linux makes the whole
# output path one over-long file name. Keep the platform separator.
sed -i "s|return fullPath.Replace('/', '\\\\\\\\');|return fullPath;|" "$src/CUE4Parse-Conversion/ExportSession.cs"
grep -q "return fullPath;" "$src/CUE4Parse-Conversion/ExportSession.cs"

"$dotnet" build "$here/meshtool.csproj" -c Release -o "$root/.cache/meshtool" -v q -nologo
