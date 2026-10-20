# Changelog

## Unreleased

- Ragdoll spinning on some outfits (seen on CH_P_EVE_09, a caped outfit): its vanilla physics asset lets neighbouring torso bodies collide (Pelvis/Spine/Spine1/Spine2), as well as the hip jiggle bodies with the pelvis, the cape links and the neck accessory with the chest. All of them overlap at rest, so the solver shoved them apart every frame (pelvis at 1000–4000°/s after a second, against ~70 on CH_P_EVE_30). The physics patch now disables every pair inside a group, and the rest-overlap measurement covers every body, not just the grouped ones.
- Gore caps: second in-game test showed them misaligned and up to 12 cm thick. The DLL now also sends each opening's outline (the convex hull of the trimmed rim points, in order), and the cap is a thin domed lid built on it as a procedural mesh. A flattened sphere, at most 2.5 cm thick, is the fallback. `capScale` defaults to 1.05.
- Limbs cut off a living Eve (F9) fell through the floor: her living mesh has no physics collision with the world. The mesh now takes the Ragdoll collision profile until she recovers.
- Gore, rebuilt as a skin cut on Eve's own mesh. The game's slicer could not hide the cut region on her: it relies on a material parameter only its gore master has, so the limb kept rendering and the pieces were untextured. `sbslice.dll` now splits her skin weights at the cut plane through the engine's `SetSkinWeightOverride`, with limb vertices on limb bones only and body vertices on body bones only. It collapses the triangles across the cut onto helper bones next to the joint by zeroing their inverse bind matrix, so the seam follows the bone under animation and physics alike. `HideBone` was tried first: it renders at the parent's bind origin and stops updating, which stretched the limb back to the cut. `gore.lua` breaks the ragdoll constraint so the limb falls away, caps both openings with the game's cut-flesh material and adds blood. Revive undoes everything, including the matrices on the shared mesh asset. Checked with a Linux harness on a synthetic mesh (the moved limb leaves no triangle spanning the gap). The slicer call and its render-thread null-check patch are gone, so the DLL patches no code any more. New `tune.gore` options: `throw`, `caps`, `capScale`; `cutAt` `auto` is now 0.15. Forearms and calves can be named in `bone`. First in-game test: the caps were sized off pads and straps the cut also crosses, and the bleed never stopped. Caps now fit a trimmed ellipse in the cut plane. The cut runs in stages (weights, then the collapse a few frames later), and the bleed stops after `bleedTime` (2.5 s). New options: `sliceFx` (off: the game's slice burst drops a static meat stub made for monster stumps), `bleedTime`. F9 no longer logs a format error (`PredictedLODLevel` isn't reflected, so the script now just waits two ticks after forcing LOD0).
- Respawn invisible model, verified in game (Boss Challenge, 4 deaths and 2 revives): a death ragdoll sets a hidden counter SB's engine adds to `USceneComponent` (+0x180), which stops the capsule from moving the mesh. Nothing clears it, so the mesh stayed where she died. `sbslice.dll` gains an unpin command (formationPath `u<hex>`), and the probe calls it on recovery and again after the game's respawn. The `LockupTransform` pin (cleared since the first fix) was a separate cause. Setting the same relative offset is a no-op in UE, so the recovery now nudges it to rebuild the transform.
- Probe crashes and a deadlock found in game: UE4SS cannot hook `UEngine::Tick` here, so `ExecuteInGameThread` ran the probe on Blueprint worker threads. A recovery there deadlocked the game on PhysX. The probe now ticks from Eve's `ReceiveTick` (game thread), and F6–F9 queue onto it. Cached Niagara systems were freed by GC between deaths (crash on the second death's blood); the cache now re-validates.
- Ragdoll impulse goes to the bone that was hit (`bOverrideHitBone`). Before, it always went to Spine1. Explosions are unchanged.
- Physics patch for every outfit (found through `EquipmentTable`): the Pelvis–thigh overlap that flung her is removed. Limbs now collide with each other, and linear damping drops from 5.0 to 0.2 (it was floaty). The pairs that overlap at rest are measured per outfit (`assetkit/outfits.py`). Every outfit mesh also gets LOD0 CPU access, so gore works on all of them. `patch_shows.py` gains `physics` and `cpuaccess` modes, streams its outputs, and restores `RF_Public` on exports that other patched packages import, which retoc needs. `sbtool` keeps `ClothingAssetCommon` raw, because UAssetAPI truncated it on write.
- The pak is now zlib-compressed (retoc patch `assetkit/patches/retoc-compress.patch`). With every outfit mesh in it, it is 558 MB instead of 1.4 GB.
- `assetkit/meshtool`: CUE4Parse mesh dump and glTF export (Blender-ready). Its build script patches CUE4Parse writing `\` paths on Linux.

## 1.0.0 — 2026-10-19

- Rewrite as a data-only IoStore patch (`ZZ_EveRagdollDeath_P`), built by `build.sh` from the installed game. UE4SS and the native DLL are gone (moved to `legacy/`).
- Root cause found in the exe: `USBShowRagdollKey` defaults `bIgnorePlayer` to true, so the ragdoll keys already in the player's shared death shows never applied to Eve. Injected a tuned ragdoll key into 7 Eve death shows. The 7 shared enemy death shows are cloned as `CH_P_EVE_01/Ragdoll/EveRD_*` with player-sized impulses, and the death table points at the clones, so enemies stay vanilla. First in-game test with enemy impulses (up to 18000) launched Eve; impulses are now 400–2500 with `ImpulseLimitVelocity=700`. Lower impulses alone did not stop the flinging: the key defaults `CapsuleComponentFollowingSocketName` to `Bip001-Pelvis`, dragging the live player capsule into the ragdoll, so Eve keys now set it to None. Still flung after that: Eve's sword collision box and hair component sit on her own skeleton and block PhysicsBody, so the blueprint now makes both ignore it.
- Death/respawn UI now waits 3.5 s (`CharacterDeadTable` `*DeadUIDelayTime`, vanilla 0) on every ragdolled death type.
- Airborne deaths: `CharacterDeadTable` pointed at a non-existent `P_Eve_Dead_Air`; now `P_Eve_AirDead`.
- 0.9.x bugs left behind with the old mod: the throw direction was constant, a stale `last_show.txt` could trigger a ragdoll at load, repeat deaths of the same type never re-triggered, and UObject calls ran off the game thread.

## 0.9.3 — 2026-08-13

- 0.9.2: UE4SS treated `dlls/` as a C++ mod; `package.loadlib` used the wrong path. DLL sits next to `main.lua`.

## 0.9.2 — 2026-08-13

- Lua UFunction hooks never see death play. Native detour of the `PlayShow : %s` logger; death show names call the existing ragdoll.

## 0.9.1-hunt — 2026-08-13

- 0.9.0: `PlayShow` UFunctions do not exist. Show key classes have 0 functions. `SBShowActorInterface:PlaySingleShow` is the play call.
- Hook `PlaySingleShow` / `ActorPlayCustomAnim*` (log only). No auto-ragdoll.

## 0.9.0-hunt — 2026-08-13

- 0.8.3: NotifyShowEvent / NotifyBPEvent / ChangeCrowdControl registered, never fired on death. Play is native.
- EXE: `PlayShow` / `FSBShowStage` / `USBShowPlayShowKey` / `USBShowRagdollKey`. Dump those classes; hook `PlayShow` UFunctions if present.

## 0.8.3-hunt — 2026-08-13

- 0.8.2 dump: 251 `SBCharacter` UFunctions, none named Play/Die/Dead. Eve BP extras are VFX/input, not death play.
- Removed `LoopAsync` knock poll and auto class dump (likely exit crash). Hook `NotifyBPEvent`, `NotifyBP_ChangeCrowdControl`, Eve `AddBlood` (log only).

## 0.8.2-hunt — 2026-08-13

- 0.8.1: `NotifyShowEvent` registered, never fired on combat knock or death.
- Dump every `SBCharacter` UFunction name at main menu. Extra NotifyShowEvent hooks (Implementation / Eve BP).

## 0.8.1-hunt — 2026-08-13

- Menu dump: `SBCharacter` has 251 UFunctions. Hits: `NotifyShowEvent`, `IsShowCharacter`, `IsRagdollSimulate`. Also `RagdollInfo` / `ShowKeyTagMap`.
- Hook `NotifyShowEvent` (log only). Filter Eve death show names.

## 0.8.0-hunt — 2026-08-13

- SBShowData has 0 UFunctions. List `SBCharacter` class UFunctions at main menu (F9 / auto 4s). No calls, no fight.

## 0.7.4-hunt — 2026-08-13

- 0.7.3 F9: `Eve_Dead_Down` is valid `SBShowData`; `obj.ForEachFunction` was a nullptr UFunction lookup (not a real iterate).
- F9 calls `:ForEachFunction` / `:GetClass()` correctly.

## 0.7.3-hunt — 2026-08-13

- 0.7.2: `Play`/`PlayShow` UFunctions do not exist. `NotifyOnNewObject` fires when death **shows stream in with the level**, not when they play. F9 vs combat-knock vs death `FindAllOf` dumps were identical; pawn show fields all nil.
- F9 lists UFunctions/properties on `Eve_Dead_Down` / `SBShowData` CDO only.

## 0.7.2-hunt — 2026-08-13

- 0.7.1: `AnimNotify:Received_Notify` hooked but never fired; all death `AnimSequence`s already loaded at idle.
- Two knock-rises (combat then death) confirmed shared IK. AnimBP_New has no death clips.
- Death is ShiftUp **SBShowData** (`/Game/Art/Show/CH_P_EVE_01/Basic/Eve_Dead_*`, `CharacterDeadTable`). Probe those shows.

## 0.7.1-hunt — 2026-08-13

- 0.7.0: F9 found `CH_P_EVE_01_AnimBP_New`; death raised `KnockDown_FullBodyIK_Alpha` to 0.72. SequencePlayer scan was 195 ghost names, no clip refs.
- Probe: hook `AnimNotify` / `PlaySound` `Received_Notify` and match death clip names. F9 checks whether those sequences are loaded.

## 0.7.0-hunt — 2026-08-12

- Offline: death clip names from `death_anim_P.utoc` (vanilla paths under `CH_P_EVE_01/Animation`).
- Probe: poll AnimGraph SequencePlayer/Evaluator `Sequence` refs + F9 dump. No auto-ragdoll, no speculative UFunctions.

## 0.6.7-parked — 2026-08-11

- 0.6.6 crashed on **combat knockdown** during speculative UFunction calls (`GetPlayState` / `IsDead` / `GetCustom*`) — not on death.
- Parked: hunt/auto removed. Manual F8/F7 only. **Undeployed** from game Mods; `mods.txt` set `EveRagdollDeath : 0`.

## 0.6.6-hunt — 2026-08-11

- 0.6.5: death-HUD detector false-fired; ForEachProperty returned 0; still only HitStop + KnockDown (+ `IsActiveFullBodyIK`).
- Probe: call `IsActiveFullBodyIK` / `GetPlayState` / `GetCustomBool|Float`, dump interesting `ForEachFunction` names. No `GetCurrentStateName` / `GetCurrentStanceName`.
- **Crashed** on knockdown mid-dump (native; Lua pcall does not catch).

## 0.6.5-hunt — 2026-08-11

- 0.6.4 death dump: only `KnockDown_FullBodyIK_Alpha` + `IsActiveFullBodyIK_HitStop`; no SHOW/ActorDead; HP/`bDead` not readable via Lua.
- Broader anim scalar dump (no name filter), stance/life known reads, HitStop broadcast hook, late death-HUD **label only** (not trigger).
- Test: combat knockdown once, then die once — compare dump #1 vs #2.

## 0.6.4-hunt — 2026-08-11

- 0.6.3 crashed mid-dump on `GetCurrentStateName` (same native crash as 0.3.4).
- Safe knock-rise dump only: direct props + ForEachProperty numbers/bools. No state-name API.

## 0.6.3-hunt — 2026-08-11

- Confirmed knock-rise still fires; dump never finished (crash).
