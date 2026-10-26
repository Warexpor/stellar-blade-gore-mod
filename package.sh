#!/usr/bin/env bash
# Build the release zip (Nexus Mods / GitHub): release/StellarBladeGore-<version>.zip, laid out like the game folder,
# so players extract it into StellarBlade/ and nothing else (UE4SS is a separate requirement, see the README).
#   ./package.sh           paks built without the other mods in ~mods (SB_VANILLA=1 ./build.sh into .cache/release)
#   ./package.sh --reuse   take dist/ as it is, if dist/sources.txt says no other mod went into it
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
SCRIPTS=$ROOT/ue4ss/StellarBladeGore/Scripts
VERSION=$(sed -n 's/^local VERSION = "\(.*\)"$/\1/p' "$SCRIPTS/main.lua")
[[ -n $VERSION ]] || { echo "no VERSION in main.lua"; exit 1; }
grep -q "^## $VERSION\b" "$ROOT/CHANGELOG.md" || { echo "CHANGELOG.md has no '## $VERSION' section"; exit 1; }
# the README names the version in its intro, the zip's name and the log line to look for: all of them this one
OTHER=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$ROOT/README.md" | grep -vxF "$VERSION" | grep -vxF "3.1.0" | sort -u || true)
[[ -z $OTHER ]] || { echo "README.md names another version: $OTHER"; exit 1; }
OUT=$ROOT/release
STAGE=$ROOT/.cache/release/stage
PAKDIR=$ROOT/.cache/release/paks

if [[ ${1:-} == --reuse ]]; then
  [[ -f $ROOT/dist/ZZ_StellarBladeGore_P.utoc ]] || { echo "dist/ is empty: run ./build.sh"; exit 1; }
  [[ ! -s $ROOT/dist/sources.txt ]] || { echo "dist/ has other mods' packages in it (dist/sources.txt): run without --reuse"; exit 1; }
  PAKDIR=$ROOT/dist
else
  SB_VANILLA=1 SB_DIST="$PAKDIR" "$ROOT/build.sh"
fi

rm -rf "$STAGE"; mkdir -p "$STAGE" "$OUT"
PAKS=$STAGE/SB/Content/Paks/~mods
MODS=$STAGE/SB/Binaries/Win64/ue4ss/Mods
mkdir -p "$PAKS" "$MODS/StellarBladeGore/Scripts" "$MODS/SBSlice/dlls"
# (not the outfits pak: physfix.lua and sbslice.dll make the same physics fixes in game, on every outfit, any mod's too)
cp "$PAKDIR"/ZZ_StellarBladeGore_P.{utoc,ucas,pak} "$PAKS/"
cp "$SCRIPTS"/*.lua "$MODS/StellarBladeGore/Scripts/"
# (no FText constructor signature: UE4SS calls it as the game starts, and with the Steam overlay on that call
# closes the game at launch, why Stellar Blade's UE4SS packs ship it disabled as dFText_Constructor.lua; 0.4.1 report)
"$ROOT/native/sbslice/build.sh" "$ROOT/.cache/release/sbslice" >/dev/null
cp "$ROOT/.cache/release/sbslice/main.dll" "$MODS/SBSlice/dlls/main.dll"
# enabled.txt turns a mod on without touching mods.txt (UE4SS 3 reads both)
touch "$MODS/StellarBladeGore/enabled.txt" "$MODS/SBSlice/enabled.txt"
sed -n '/^<!-- install -->$/,/^<!-- \/install -->$/p' "$ROOT/README.md" | sed '1d;$d' > "$STAGE/StellarBladeGore-README.md"
[[ -s $STAGE/StellarBladeGore-README.md ]] || { echo "README.md has no <!-- install --> block"; exit 1; }
cp "$ROOT/LICENSE" "$STAGE/StellarBladeGore-LICENSE.txt"

ZIP=$OUT/StellarBladeGore-$VERSION.zip
rm -f "$ZIP"
(cd "$STAGE" && zip -qr -X "$ZIP" .)
ls -l "$ZIP"
(cd "$STAGE" && find . -type f | sort)
