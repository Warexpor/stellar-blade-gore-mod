# sb-eve-ragdoll-death

Stellar Blade: Eve ragdolls when she dies, using the game's own ragdoll show key. The ragdoll itself is a pure data mod (one IoStore patch). Gore (dismemberment, blood) is an optional UE4SS script plus a small native DLL, see [Gore](#gore).

## How it works

Deaths are driven by `SBShowData` "shows". `Local/Data/CharacterDeadTable` row `Player` picks the show per death type. Most of them (stand, skill steps, explosions) are the shared `Dead/Dead_Monster_*` shows, which already contain an `SBShowRagdollKey` (channel 23 in `KeyContanerMap`). The player never ragdolls only because the key's constructor sets `bIgnorePlayer = true` (`mov byte [rbx+0x1F0], 1` in `USBShowRagdollKey::USBShowRagdollKey`), and no asset overrides it.

The patch (`mod/ragdoll_spec.json`):

- **clone**: copies the shared `Dead_Monster_EffectType_Stand / Explosion / ExplosionLight` and `SkillType_Step0-3` shows to `CH_P_EVE_01/Ragdoll/EveRD_*` with `bIgnorePlayer=false` and Eve-sized impulses (the enemy values of 5k–18k launched her across the map). The `Player` row of the death table points at the copies, so enemy deaths stay fully vanilla.
- **inject**: adds a ragdoll key, cloned from `Dead_Monster_SkillType_Step1`, to Eve's own death shows: `P_Eve_Dead`, `P_Eve_Dead2`, `P_Eve_Dead3`, `P_Eve_Dead_Nikke`, `Eve_Dead_Down`, `P_Eve_Dead_Falling` and `P_Eve_AirDead`. Each key is tuned per show (impulse, start time), and `bKeepPlaying` is set. Every Eve ragdoll key also gets `ImpulseLimitVelocity=700` and `CapsuleComponentFollowingSocketName=None`. The constructor defaults that to `Bip001-Pelvis`, which drags the player's still-colliding movement capsule onto the ragdoll every frame and flings her around spinning.
- **table**: `Player.AirborneDeadShow` points at the vanilla `CH_P_EVE_01/Basic/P_Eve_Dead_Air`, which does not exist, so airborne deaths had no show at all. It now points at `P_Eve_AirDead`.

- **collision**: Eve's blueprint (`CH_P_EVE_01_Blueprint`) has two components on her own skeleton that block `PhysicsBody`: the sword box `WeaponPhysicsCollision` (on `Bip001-Prop1`) and the `SBHair` mesh. A ragdoll runs on the `Ragdoll` profile (object type `PhysicsBody`), so they shove her own bodies every frame. The patch appends an Ignore entry for `PhysicsBody` to their raw collision responses; nothing else in the blueprint changes. Outfit or hair mods that replace this blueprint will conflict.

- **hit bone**: vanilla keys leave `bOverrideHitBone` false, so every death pushes `ImpulseBoneName` (Spine1). Ragdoll key code (`0x14245eb70`) takes the bone from the hit info when the flag is set and falls back to `ImpulseBoneName` when the hit has none. Eve's keys set it, so a leg hit folds the leg and a head hit snaps the head. Explosions keep the centre push.
- **outfits**: every outfit mesh that `EquipmentTable` can put on Eve (SkeletalMesh on her body skeleton; hair excluded) gets two patches. `assetkit/outfits.py` finds them, and `build.sh` runs it before patching.
  - **physics**: vanilla physics assets let Pelvis collide with both thighs although their capsules overlap by ~10 cm at rest. The solver pushes them apart every frame, which was the flinging. Almost every other pair is disabled, so limbs pass through each other. The patch makes bodies collide across five groups (torso, each arm, each leg). Pairs inside a group never collide: some outfits ship with neighbouring torso bodies colliding, and CH_P_EVE_09 spun from it. Pairs closer than 0.5 cm in that outfit's bind pose stay disabled, for every body, so jiggle, cape and accessory bodies that sit inside another stop colliding with it. These pairs are measured per asset from the mesh's reference skeleton and the body capsules, and for `CH_P_EVE_30` the result matches the hand-checked list. `LinearDamping` drops from 5.0 to 0.2: at 5.0 she fell at about 2 m/s and looked floaty. These bodies are kinematic in gameplay, so only ragdolls change.
  - **cpuaccess**: sets `bAllowCPUAccess` on LOD0. The skin cut reads it (see Gore).

  Every patched mesh is a full copy in the pak (all 134 make it about 560 MB compressed), and it replaces any outfit mod for the same mesh. Use `outfits.only` / `outfits.skip` (mesh-name globs) in the spec to trim the list, or set `outfits.enabled` to false to drop all of it. Meshes and physics assets that don't round-trip byte-exactly through UAssetAPI are skipped and listed in the build log. `ClothingAssetCommon` exports stay raw bytes, because UAssetAPI loses cloth LOD data when it writes them back.

Scripted deaths are left vanilla: swimming, ocean, sliding, desert hole, grinder, laser and balance beam.

## Build / install

Needs `git`, `cargo`, `python3` and `curl`. The .NET 10 SDK is fetched into `.cache/` if it is missing. Point `SB_GAME` at another install if needed.

```bash
./build.sh --install
```

```bash
./build.sh --uninstall
```

The build pins and fetches [retoc](https://github.com/trumank/retoc), [UAssetAPI](https://github.com/atenfyr/UAssetAPI) and the [SB header dump](https://github.com/a5tronomy/SB), generates `.usmap` mappings from the headers (`assetkit/mkusmap.py`), extracts the assets from the installed game, patches them (`assetkit/patch_shows.py`), repacks `dist/ZZ_EveRagdollDeath_P.{utoc,ucas,pak}` (UE4.27 TOC layout, zlib blocks through `assetkit/patches/retoc-compress.patch`; `SB_COMPRESS=none` stores them raw) and reads the result back to verify it (`assetkit/verify.py`). The output lands in `SB/Content/Paks/~mods/`.

Tuning: edit `mod/ragdoll_spec.json` (field names as in `USBShowRagdollKey`) and rebuild. `DirectionType`: 0 Static, 1 HitDirection, 2 TargetToSelf, 3 HitLocationToSelf, 4 Velocity, 5 StaticLocal.

## Gore

The game's own dismemberment (`ASBCharacter` slicing, `0x142129c30`, used by the player's sword on some monsters) can't work on Eve. It copies the cut region into procedural meshes and hides it on the original through a vertex-colour override plus the material parameter `DissolveMaskRadiusFactor`. Only the gore master `MA_CH_DamageGore` has that parameter, and cooked materials can't be given one. So the cut is made in the skinning instead, on her own mesh with her own materials.

`native/sbslice` is a tiny freestanding DLL (clang + lld, no MSVC; `native/sbslice/build.sh`). It loads as a UE4SS C++ mod and waits for `gore.lua` to send it the address of the unused cheat UFunction `SBRewardGroupDropFormationPathLocation`. It then swaps that function's native thunk for its own handler, which takes commands through the cheat's string parameter. No byte signatures and no code patches are involved: the exe has no ASLR, and the thunk is matched by its address.

How a cut works (`c<component>,<lod>,<bone>`, a plane point and a normal):

- **Split.** For a plane through bone B, the DLL reads LOD0's positions, indices and skin weights (CPU copies) and skins every vertex in the current pose. A vertex weighted to B's subtree and in front of the plane joins the limb and keeps only limb bones. Every other vertex keeps only body bones.
- **Seam.** No vertex is shared across the cut any more. Every vertex of a triangle that crosses the plane goes 100 % to a sink on its own side: a helper bone near the joint that sits where the bind pose puts it relative to its parent, preferably a leaf with few vertices of its own, chosen per mesh section. The section has to contain the sink, because the engine drops weights on bones a section doesn't have.
- **Collapse.** The sink's inverse bind matrix becomes a zero scale at its own origin, so the seam collapses onto the sink's live position whatever drives it (animation or physics). Triangles across the cut become lines, and the ring next to them closes the opening. The sink's own vertices move to their strongest other bone first. `HideBone` can't do this: a hidden bone renders at its parent's bind origin and stops updating, which stretched the severed limb back to the cut.
- **Apply and report.** The weights go to the engine's own `USkinnedMeshComponent::SetSkinWeightOverride`. The DLL reports both openings, fitted to the rim vertices in their new pose: centre, axes and an ellipse in the cut plane. Rim points further than 1.6× the median from the cut axis are left out, because a cut near the shoulder or hip also crosses pads and straps that stand off the skin.
- **Open.** The sinks are recorded but collapse only on `k`, a few frames later. Collapsing them under the old weights would pull every vertex those helpers moved onto their origins until the GPU has the new weights.

`x<component>,<lod>` releases the override and restores the matrices. `r` restores every collapsed matrix, since they live on the shared mesh asset.

`probe/EveRagdollProbe/Scripts/gore.lua` drives each cut:

1. It picks the arm or thigh nearest the hit and forces LOD0 while she is cut.
2. Two ticks later it cuts at `tune.gore.cutAt` along the bone, with a random tilt, and places the caps hidden.
3. Two ticks after that it sends `k`, breaks the ragdoll constraint at that bone, so the limb's bodies carry it away (on a living Eve too, for F9), and gives the piece a push (`throw`).
4. It shows the caps. Each is a thin domed lid built as a procedural mesh on the opening's outline (the convex hull of the trimmed rim points, which the DLL sends in order), so its edge sits on the skin. If the procedural mesh can't be made, a flattened sphere fitted to the ellipse is used instead. using the game's cut-flesh material (`MI_CutDamage`), Both are attached to the bone of that side. A limb cut while she stands gets the death ragdoll's collision profile on the mesh until she recovers: her living mesh has no physics collision with the world, so the piece fell through the floor.
5. It spawns the game's Niagara blood (blood splat, bleeding at both sides of the wound for `bleedTime` seconds, floor pool).

On revive it undoes all of it: skin weights, collapsed bones, caps, effects, forced LOD and physics state.

Settings live in `tune.lua` under `gore`: `enabled`, `sliceOnDeath`, `sliceChance`, `bone`, `allowTorso`, `cutAt`, `tilt`, `throw`, `caps`, `capScale`, `blood`, `sliceFx`, `bleedTime`, `hitSplat`, `pool`. F9 cuts while she is alive, for testing. The cut needs LOD0 CPU access on the outfit mesh (the `cpuaccess` patch, applied to every outfit). `native/sbslice/test/run.sh` runs the cut natively on a synthetic body and leg, with the engine calls stubbed.

## Asset tools

`assetkit/sbtool`: `dump <uasset> <json>`, `fromjson <json> <uasset>`, `dumpall <content_root> <json_root> [class]` (batch dump with a JSON round-trip check, package paths on stdin), `validate <dir>` (byte-exact round-trip check), all with `SB_USMAP` set. `build.sh` prefers `mappings/SB.usmap` (UE4SS `DumpUSMAP` from the game, full engine schema) over the header-generated one. Only that file decodes engine assets like `SkeletalMesh` and `PhysicsAsset`.

`assetkit/meshtool` (CUE4Parse, built with `assetkit/meshtool/build.sh`) reads meshes from retoc legacy output. `dump` writes bones, sections, positions and skin weights as JSON; `bones` writes only reference skeletons, used by the outfits step; `gltf` writes a `.glb` that imports into Blender with all 323 bones and weights. New meshes can't go back in without the UE editor to cook them. The generated mappings decode 172/197 of Eve's shows byte-exactly. The rest only miss engine structs (camera-shake oscillators, post-process settings) and still round-trip as raw exports.

## Legacy

`legacy/` holds the old 0.x UE4SS Lua mod and the native `PlayShow` log hook. It is superseded: it needed exe byte signatures and a polled text file, and it never worked reliably.

## Probe

`probe/` holds `EveRagdollProbe`, a UE4SS script for the ragdoll flinging (runtime fix + logger). Install it with `./probe/install.sh`, which sets up the Stellar Blade UE4SS build (pinned and checksummed), and add the Steam launch option `WINEDLLOVERRIDES="dwmapi=n,b"`.

The first probe run showed the impulse isn't the problem. Her pelvis barely travels, but every bone keeps 500–1400 cm/s and up to 9000 deg/s and picks up energy again after settling. That points to self-collision. The mesh runs the `Ragdoll` profile (object type `PhysicsBody`, blocks `PhysicsBody`), so the bodies of her outfit's physics asset collide with each other and with `SBHair` (PhysicsOnly, attached to the head).

On each ragdoll the script makes the mesh ignore `PhysicsBody` and turns `SBHair` collision off. It keeps self-collision when the outfit's physics asset carries the patch (`tune.selfCollision = "auto"`, detected by the pelvis body's damping). It restores both on recovery, and re-attaches the mesh to the capsule if respawn left it detached.

The invisible model after respawn had two causes in SB's engine. `ASBCharacter::SetLockupSimulatePhysics(true)` copies each mesh's world transform into `LockupTransform` (an SB addition to `USkeletalMeshComponent`), and the mesh stays pinned there; the script clears that lock on recovery. The death ragdoll also sets a non-reflected counter on `USceneComponent` (+0x180) that stops the parent from moving the component. Only the mesh had it, so the capsule respawned and the body stayed at the death spot. Lua cannot reach it, so `sbslice.dll` clears it (formationPath `u<hex>` on the same cheat), on recovery and once after the respawn. The probe runs from Eve's `ReceiveTick`: this game gives UE4SS no `UEngine::Tick` hook, so `ExecuteInGameThread` callbacks can land on Blueprint worker threads, and one deadlocked the game. It logs bone motion to `Win64/ue4ss/Mods/EveRagdollProbe/probe.log`.

Sandbox keys: F7 ragdolls her on the spot using `Scripts/tune.lua` (impulse, bone, direction, self/hair collision, mass scale), F8 recovers, F6 re-reads `tune.lua` without a restart, F9 cuts a limb off (Gore). (`SBSuicide` is a no-op in the shipping build, so there is no death key.) On first load the script also runs UE4SS `DumpUSMAP` once, giving the full engine schema needed to edit physics assets. Remove it with `./probe/install.sh --uninstall`.
