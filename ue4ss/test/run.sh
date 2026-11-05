#!/usr/bin/env bash
# The mod's Lua against a made-up game (fake.lua, eve.lua): the shipped scripts, unchanged, copied into a scratch
# game folder; each scenario (sim_*.lua) prints PASS or FAIL lines and leaves the mod's log in the folder.
#   test/run.sh [scenario...]   scenarios: default list in SEL below (all sim_*.lua but diag, the parked diagonal cut)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/../StellarBladeGore/Scripts
bash "$HERE/../check_scripts.sh"
OUT=${TMPDIR:-/tmp}/sbgore-sim
SEL=("$@"); [[ ${#SEL[@]} -eq 0 ]] && SEL=(newobj_fallback sword_return fall regrow struggle struggle_air waist f6 after after_nomontage reload reload_head sanity keys rebind hairpairs lemi outfit photo photo_hold capsule fold crawl push animdeath odds lowarm frame cap_fallback swing_perf hook_perf cape bosses grab grab_cut corpse voiceas customrag piece piece_create_fail neutral camera quitdeath f7cloth asyncload cutscene_hair stages stages_off followup followup_off campreload charcache clothscan nosplits nosplits_blade customrag_missing stains menu_layout revival_screen smash smash_area smash_hits rock blast smash_pose smash_lifecycle smash_stress smash_effects scheduler_reentry enemy_tracker smash_material smash_key smash_voice smash_struggle split lid_cadence spin_cadence revive_cadence cutlist ragdoll_probe perf_probe death_face script_preflight gore_native gore_copies hit_classification hits_after split_plane split_break split_cut outfit_animation hit_marks body_blood death_hud death_slowmo after_geometry settings_manager tachy_geometry tables_fight)
fail=0
LUA_TEST_PATH=$HERE
[[ ${MSYSTEM:-} ]] && LUA_TEST_PATH=$(cygpath -m "$HERE")
for s in "${SEL[@]}"; do
  # The scenario becomes a scratch directory which is removed below.
  if [[ ! $s =~ ^[a-zA-Z0-9_]+$ ]]; then
    echo "invalid scenario name: $s" >&2
    fail=1
    continue
  fi
  d=$OUT/$s
  rm -rf "$d"; mkdir -p "$d/ue4ss/Mods/StellarBladeGore"
  cp -r "$SRC" "$d/ue4ss/Mods/StellarBladeGore/Scripts"
  rm -f "$d/ue4ss/Mods/StellarBladeGore/Scripts/settings.lua"
  status=0
  r=$(cd "$d" && LUA_PATH="$LUA_TEST_PATH/?.lua;;" lua5.4 "$HERE/sim_$s.lua" 2>&1) || status=$?
  echo "$r" | sed "s/^/$s: /"
  if (( status != 0 )) || ! grep -q '^PASS$' <<< "$r" || grep -qE '^FAIL($|[[:space:]:])' <<< "$r"; then
    echo "$s: scenario failed (exit $status)"
    fail=1
  fi
  echo "$s: log $d/ue4ss/Mods/StellarBladeGore/stellarbladegore.log"
done
exit $fail
