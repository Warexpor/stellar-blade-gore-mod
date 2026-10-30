#!/usr/bin/env bash
# The mod's Lua against a made-up game (fake.lua, eve.lua): the shipped scripts, unchanged, copied into a scratch
# game folder; each scenario (sim_*.lua) prints PASS or FAIL lines and leaves the mod's log in the folder.
#   test/run.sh [scenario...]   scenarios: fall, regrow, struggle, struggle_air, waist, f6, after, reload, reload_head, sanity, keys, hairpairs, lemi, outfit, photo, fold, crawl, push, animdeath, odds, diag, lowarm, frame, cape, bosses, grab, corpse, voiceas, customrag, piece, neutral, camera, quitdeath, f7cloth, asyncload, stages, stages_off, followup, followup_off, campreload, charcache, nosplits, customrag_missing, stains; default all but diag (the parked diagonal cut)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/../StellarBladeGore/Scripts
OUT=${TMPDIR:-/tmp}/sbgore-sim
SEL=("$@"); [[ ${#SEL[@]} -eq 0 ]] && SEL=(fall regrow struggle struggle_air waist f6 after reload reload_head sanity keys hairpairs lemi outfit photo fold crawl push animdeath odds lowarm frame cape bosses grab corpse voiceas customrag piece neutral camera quitdeath f7cloth asyncload stages stages_off followup followup_off campreload charcache nosplits customrag_missing stains)
fail=0
for s in "${SEL[@]}"; do
  d=$OUT/$s
  rm -rf "$d"; mkdir -p "$d/ue4ss/Mods/StellarBladeGore"
  cp -r "$SRC" "$d/ue4ss/Mods/StellarBladeGore/Scripts"
  rm -f "$d/ue4ss/Mods/StellarBladeGore/Scripts/settings.lua"
  r=$(cd "$d" && LUA_PATH="$HERE/?.lua;;" lua5.4 "$HERE/sim_$s.lua" 2>&1) || true
  echo "$r" | sed "s/^/$s: /"
  echo "$r" | grep -q '^PASS$' || fail=1
  echo "$s: log $d/ue4ss/Mods/StellarBladeGore/stellarbladegore.log"
done
exit $fail
