# Audit coverage (work in progress)

A checked executable source file has been read through for the current audit. Generated data files are checked structurally and identified separately; their source data still requires independent comparison where noted. Unchecked files may have been sampled or reviewed in an earlier pass but still need a complete file-level pass. A check is not a guarantee of runtime correctness.

## Runtime Lua

- [x] `active.lua` (per-tick clamps already gated/single-read; no change, see audit)
- [x] `after_hit_geometry.lua`
- [x] `blade_decision.lua` (heaviest classify kept; tries/jitter/fallbacks preserved)
- [x] `body_blood.lua`
- [x] `bone_lists.lua`
- [x] `bosses.lua` (offsets/prepare/HP/AI kept; exact restore preserved)
- [x] `cap_geometry.lua`
- [x] `cloth_reset.lua`
- [x] `convulse.lua` (event-driven; pulses/chain guards kept)
- [x] `customrag.lua`
- [x] `death_camera.lua`
- [x] `death_face.lua`
- [x] `death_hud.lua`
- [x] `death_screen.lua`
- [x] `death_slowmo.lua`
- [x] `death_widgets.lua`
- [x] `enemies.lua` (one scan + watch batches kept; mute/fallback/caches preserved)
- [x] `glass.lua` (FindAllOf throttled/cached; hit geometry lethal-only, kept)
- [x] `gore.lua` (pools/staged cuts/deferred work kept; no coalescing)
- [x] `gore_assets.lua`
- [x] `gore_audio.lua`
- [x] `gore_copies.lua`
- [x] `gore_floor.lua`
- [x] `gore_hit_marks.lua`
- [x] `gore_native.lua`
- [x] `gore_ownership.lua`
- [x] `gore_pools.lua`
- [x] `gore_preload.lua`
- [x] `gore_regrow.lua`
- [x] `gore_scheduler.lua`
- [x] `gore_smash.lua` (death-only hides, budgeted chunks, deferred blood kept)
- [x] `gore_smash_select.lua`
- [x] `gore_voice.lua`
- [x] `gore_watch.lua`
- [x] `gui.lua` (icon fallback without LoadAsset kept; tick only input checks)
- [x] `hit_classification.lua`
- [x] `hits_after.lua`
- [x] `juggernaut_finisher.lua`
- [x] `keys.lua`
- [x] `lang_ja.lua` (data only, no tick cost)
- [x] `lang_ko.lua` (data only, no tick cost)
- [x] `lang_ru.lua` (data only, no tick cost)
- [x] `lang_zh.lua` (data only, no tick cost)
- [x] `low_arm.lua`
- [x] `main.lua` (live_chars/near/guard split kept; per-frame safety preserved)
- [x] `manual_slowmo.lua`
- [x] `newobj.lua`
- [x] `object_lifetime.lua`
- [x] `outfit_animation.lua`
- [x] `performance.lua`
- [x] `photo_collision.lua`
- [x] `photo_controls.lua`
- [x] `photo_freeze.lua`
- [x] `photo_guard.lua`
- [x] `photo_visibility.lua`
- [x] `physfix.lua` (once-per-asset borrows/restores kept)
- [x] `projectile_hits.lua`
- [x] `roster.lua` (generated data: all 644 entries match the expected structure, with unique aliases and IDs; not independently compared with the current game table)
- [x] `settings.default.lua`
- [x] `settings_manager.lua`
- [x] `slice_response.lua`
- [x] `slowmo_pp.lua`
- [x] `split_break.lua`
- [x] `split_cut.lua`
- [x] `split_plane.lua`
- [x] `split_rides.lua`
- [x] `stains.lua`
- [x] `struggle.lua` (40 Hz servo/pulse caps and joint guards kept)
- [x] `swing_selection.lua`
- [x] `swing_tracking.lua`
- [x] `tables.lua` (scan memo/retry/gates kept; no per-tick scan)
- [x] `tachy_core.lua` (static data, no tick cost)
- [x] `tachy_geometry.lua`
- [x] `tune.lua` (values only; knobs unchanged)

## Native source

- [x] `native/sbslice/sbslice.c` (reviewed end to end; cutter/centroid/island/sink loops recorded as measurement candidates, no geometry change shipped)
- [x] `native/sbslice/spawner.c`
- [x] `native/sbslice/stats.c` (linear scan noted as sync measurement candidate, unchanged)

## Asset tooling

- [x] `assetkit/summ.py`
- [x] `assetkit/mkusmap.py`
- [x] Remaining asset generators, patchers and verifiers (build-time only: outfits broadphase, patch/verify batching, build parallelization and compression/verify safety reviewed; no runtime weight change)

## Remaining work

- [x] Complete the unchecked runtime Lua files, including large coordinators and all lifecycle paths.
- [x] Complete the native helper, including cutter, stats, spawner, startup and command dispatch.
- [x] Complete asset generation, build, packaging, installation and optional standalone spawner.
- [x] Review relevant test fixtures and coverage for each material change and finding.
- [x] Update the prioritized audit and verify installed files and player settings after changes.
