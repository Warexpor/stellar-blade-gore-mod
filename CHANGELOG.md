# Changelog

## Unreleased

- Test fixes: the crash after a death's reload is gone (the new Eve was picked up cleanly), the split's copy simulates and falls, and she settles. Her hair still stayed whole on the split (its skeleton has no Spine1): the borrowed sink is now the first body bone the hair has. A face copy once came out uncut (stale pose); face and hair copies now get their pose copied before the cut. The sword's box was 217 cm long (padded bounds): it uses the imported bounds, capped at `weaponMaxCm` (120).
- She jittered on the floor once she fell (head and limbs turning at 50-80°/s for seconds, the trace shows it): the muscle tone pulled against the floor and accessory bodies were 25x lighter than the main ones. Once she lies still the tone goes and her bodies sleep (`tune.active.settle`); accessories are capped at 0.8 kg instead of 0.3.
- Crash after a death (access violation in UE4SS): the level reloads on respawn and frees the old Eve, and the script asked UE4SS whether its cached pawn was valid, which reads the freed object. The script now follows the actor whose tick runs it and drops everything held from the old one without touching it.
- Deaths had no direction: the skill-hit hook never fired in single player (0 calls), so nothing knew where the blow came from, the body dropped on the spot and every cut was a roll. The killing blow now also comes from her mesh's hit reaction (`PhysicalHitForce*`, `VertexShakeInfo`) or the nearest enemy, a swing is made up across it, and both the impact push and the blade cut use it (`attackerReach`, `meshHitWindow`; `impact` 450).
- Ragdoll less like a sack: the muscle tone fades over 2.5 s to a resting 15 % instead of to nothing, with more damping, and the random twist is down to 35°/s. Her sword falls out of her hand and tumbles to the floor (an invisible box of its size carries it) instead of hanging in the air; it goes back on revive (`dropWeapon`, `weaponKg`, `weaponToss`).
- The split's copy stood frozen and whole: it was made without collision, and a collision profile change never creates physics bodies, so it never simulated. It now gets its bodies by `SetCollisionEnabled` (logged: `split copy ragdoll`, `split copy at ...`). A split head splits her hair too, the copy gets its own instead of a bald half head.
- Blunt blows and stabs press her in instead of punching a hole: the old wound collapsed a patch of skin into one point under a sunken lid, which looked like a puckered star. `sbslice.dll` gains Dent mode (5): the skin around where the ray leaves the body sinks smoothly onto a plane under it, deepest in the middle and fading to nothing at the rim, each vertex keeping its own weights. A killing hit whose attack group or show name reads as a stab or a blunt blow (`stabWords`, `bluntWords`, logged per hit to fit them) dents where it landed: blunt wide and shallow, a stab narrow and deep with a bleed. Rolled wounds are blunt dents. F10 alternates blunt and stab. Harness tests for the dent and its layers.
- Deaths cut along the killing blade: the plane of the reported hit's swing and the attacker's forward, through where it hit, decides between the limb it meets, a beheading or the body in two along the blade at any angle (`gore.blow`, `bladeChance`; the roll is the fallback). The split now takes any plane: the deep part behind it collapses to points on the plane per band instead of flattening, the half with the head keeps her own mesh, the face is split only when the blade passes near the head, and a cut through the spine breaks both halves' ragdolls there. F5 cuts along a random blade. Harness test for a cut across the body.
- Cuts stretched clothing across the body: a seam ran through straps, plates, neck chains and hair too, and collapsed onto whatever bone their mesh section had (a hair bone, a neck accessory 26 cm off the cut, a clavicle). Now only the body is cut: a section that doesn't go round the cut gets no seam, each piece of it crossing the cut goes along whole with its side or, tied to both, vanishes whole (`pieces=`). Holes only go through the skin and what sits tight on it; a plate over it stays (`layersoff=`). Lua sends the bones that may never be a sink (`n`): the main skeleton, hair, capes, breasts and accessories. The pelvis, the head and a clavicle had been sinks, which broke the body around them.
- The vertical split was built wrong: each half collapsed everything behind the plane into one point per mesh section, so the other half, legs and all, went into one spot by the chest, and every triangle on the midline stretched from the hips or the neck to it. Now the torso behind the plane is flattened onto it by projecting sinks (one per band along the opening, in their bones' frames), the other half's arms and legs collapse to a point where they joined, the kept half's limbs stay whole even across the plane, and kept skin ignores the other half's helpers, so the re-cut loop is gone. Lua tells the DLL which limbs go (`g`); the ragdoll breaks exactly those. Harness tests for the flattening (also on a turned pose), the limb point, forbidden sinks, hanging pieces and a plate over a hole.
- The hit hook read `ClientBroadcast_SkillHitResult`'s parameters shifted by two (it took the turn counter for the caster and an id for the hit location), so no hit ever registered on Eve and a killing blow from above could never split her. Parameters now follow the SDK dump; hits log the result (hit, guard, parry...), the attack direction (left-to-right, right-to-left, front), skill, caster and target.
- The hit hook logs its first 12 hits that aren't on Eve (caster, target, distance from her pelvis), and the death line says how often it fired and how many hits were on her. A real death logged `last hit none` without showing whether the hook fired at all.
- Renamed to **Stellar Blade Gore Mod** (was Severed): pak `ZZ_StellarBladeGore_P`, UE4SS mod `StellarBladeGore`, log `Mods/StellarBladeGore/stellarbladegore.log`, script folder `ue4ss/StellarBladeGore`. The installers remove the old pak and mod folder and carry the log over; `sbslice.dll` must be rebuilt (`install.sh` does it) since its request files moved with the mod folder.
- Crash on the first head cut (F9 or a death): UE4SS's `GetFName` on a null object is an access violation that pcall can't catch, and the face lookup called it on components without a mesh. Mesh names are now read only from a valid mesh.
- Severed limbs ended in a cone instead of a flat cut: a limb's sink could be a twist bone at the shoulder or hip, above a cut 15 % down the bone, so its seam collapsed out past the cap. Sinks on the wrong side of the plane now cost more in every mode, and a sink whose origin is still outside its own side collapses to a point 2 cm inside it (the zeroed inverse bind matrix keeps a translation; `sinkmoved=` in the log). Harness test added.
- An upper body cut off a standing Eve spun wildly: breaking the constraint also drops its no-collision pair, and the two bodies overlap at the joint, so the piece was shoved against her kinematic hips every frame. It also weighed the outfit's 100 kg chest bodies. After a cut her bodies stop colliding with each other until she recovers, and a piece cut off a living Eve gets `active.lua`'s human masses (put back on F8).
- Vertical split: a killing blow that comes down from above may cut her in half top to bottom along the blade (`gore.death.split`, 10). `main.lua` now hooks the game's per-hit message (`ClientBroadcast_SkillHitResult`) for the swing's direction and logs every hit on Eve. `sbslice.dll` gains Side mode (keep one side of a plane, the rest folds into the half; opening fitted in four bands), a borrowed sink for sections with nothing to collapse onto (added to the BoneMap in place, made to follow the head through `MasterBoneMap` on `k`), and `p` (pose copy). `gore.lua` clones the body and face, cuts one half on each, gives the copy its own ragdoll, drops the limbs each half left behind, caps both halves and undoes all of it on revive. F11 splits for testing. Harness test for Side mode, the borrowed sink and the pose copy.
- Death face: Eve's death expression is now blabmice's [Proper Death Expression](https://www.nexusmods.com/stellarblade/mods/2716) (credited, as its permissions ask), not the vanilla blank stare. Its animation ships as is (`vendor` job, `third_party/proper-death-expression/`). Its fix for grapple, explosive and falling deaths is rebuilt cleanly: a silent `DIE3` voice in `CSS_PC_EVE` (`voice` job) and a new notify in each of the four death animations (`notify` job), so their cloth and footstep sounds, which the original fix overwrote, stay. All three modes are checked by `verify.py`.
- Beheading, cutting her in half and blunt wounds. `sbslice.dll` gains cut modes: whole (a component goes along entirely: the face, weighted to head and neck), plane (cut by position: the neck under the face, which has no head bone in the outfit skin) and hole (the skin around where a ray leaves the body collapses into a crater). Limb-side vertices with nothing to collapse onto now vanish into the stump instead of stretching. `gore.lua` rolls what a death does (`gore.death`: limb 45, head 20, torso 15, wound 20; the game exposes no weapon type), gives wounds a sunken flesh lid and a bleed, and F10 makes a wound for testing. The face mesh gets LOD0 CPU access in the pak. `allowTorso` is replaced by the odds. Harness tests for the three modes.
- Death cuts follow the killing blow: the plane leans towards the death key's impulse direction, up to `gore.blowTilt` (35°) off square.
- Faster builds: the vanilla side is cached between builds (keyed on the game's paks, mappings and tools), outfit meshes are patched and verified in place by sbtool instead of a JSON round trip each way, sbtool runs batches in parallel and in one process, and retoc compresses blocks in parallel (packing 3 min → 24 s).
- Renamed to **Severed**, since it is a gore mod now: pak `ZZ_Severed_P`, UE4SS mod `Severed` (was `EveRagdollProbe`), log `Mods/Severed/severed.log`, script folder `ue4ss/` (was `probe/`). The installers remove the old pak and mod folder and carry the log over.
- Arms bent and stretched in ragdolls on caped outfits (seen on CH_P_EVE_09), and the severed arm looked broken: the upper-arm twist bones carry a body (the cape's anchor) that no constraint holds. Kinematic in gameplay, free in a ragdoll, so the skin weighted to them was dragged off by the falling cape. 25 physics assets have such bodies (twist, venter and helper bones). The physics patch now adds a locked joint from each to the nearest ancestor body, framed at the bind pose; the frame math reproduces the vanilla frames of PhAT-made joints. `verify.py` checks the new joints.
- Gore caps covered straps, plates and capes in meat. The DLL now groups rim points by mesh section and caps only the sections that go round the limb, innermost and tight ones (skin, suits). Harness test added.
- The severed piece bled from its middle (the effect sat on the next bone down, e.g. the elbow). Both bleeds now ride on their cap, at the opening.
- New `active.lua` (`tune.active`): human masses instead of the 100 kg chest bodies and 20–80 kg cape links the outfits ship, momentum from before death carried into the fall, a push along the killing blow with a little twist, and muscle tone that follows the animation and fades out over 1.4 s, legs first.

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
