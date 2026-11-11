# To do

- Native baseline: enemy waist tests for CH_M_NA_05, CH_M_NA_05_Var01 and CH_M_NA_31 fail with respectively 2, 2 and 5 additional visible stretched triangles when the upper body is flung. Investigate before using these cases to judge cutter optimization; in-game appearance is unknown.

## 0.7.0: next in-game checks

- Retest death cuts and smashes for stutter. The latest changes retain late asset-preload retries and spread smash chunks; native cut work and cold asset spawns may still hitch. Compare new log timings with the November 5 playtest.
- Check uncut bodies lying on either side or face down for visible struggle, and verify recovery. The selection fix passes simulation but its real physics is unverified.
- Check that cut and smash stumps show the 0.5.5 pulsing blood effect, including both sides of ordinary cuts, and that it stops on time and clears on recovery.
- The refactored Lua passes the default simulations, but actual split appearance, physics, and compatibility with external mesh-copy mods still require playtesting.

## Reports without logs (2026-11-02)

- Startup crashes: the locally reproduced UE4SS FText signature crash is documented in Install. Native watcher failure no longer silently selects the known unsafe general UE4SS callback path, but neither proves the cause of the reports. The immediate photo-mode pawn callback remains a UE4SS callback. Test both UE4SS builds and collect UE4SS.log, stellarbladegore.log and any crash dump.
- Blood and Dirt plus Ultra Violence: an attack crash is reported; the other mod is not installed here and no stack was supplied. Compatibility is unconfirmed. Test each feature alone and together with the exact versions, logging and crash dump; do not copy another mod's implementation without checking permissions.
- Breakable Sword: duplicate weapon-slot candidates are now deduplicated; an earlier fix already guarded repeated split callbacks by address. Neither proves the reported whole sword plus half is fixed; reproduce a guard-break death.
- Play As Scarlet skin: fixed-slot hiding replaced by recognized material names; test the reported Ocean string boss replacer. Unrecognized hair may stay visible, and the separate Eve hairstyle can retain the hat.
- Raven NPC skin: Play As uses Eve's CH_P_EVE_11 outfit, not Raven's boss mesh, so NPC-only replacements do not affect it. Boss mesh compatibility with Eve's skeleton, materials, physics and cuts needs investigation before swapping.
- NPC vertical splits are intentionally disabled because the player split path assumes Eve-specific components. Enabling them requires an enemy-safe split/cleanup path and real mesh tests. Player vertical splits that fail the geometry check intentionally retry then fall back to a waist cut; reproduce with the named NPC replacers before changing that safety check.
- Death camera vertical inversion is now available in F3 Camera and settings.lua; verify mouse and controller directions in game.

## Sandbox: first playtest (untried in game)

Built and passing `ue4ss/test/run.sh bosses voiceas` and `native/sbslice/test/real/playas.sh`; nothing of it seen in game yet. F3 → Sandbox, Sandbox Bosses on, Spawn Boss; the `bosses:` log lines say what happened. Play As is its own mod now ([Stellar Blade Play As](https://github.com/Warexpor/stellar-blade-play-as), its own TODO.md); here only what this mod does to her as them: the gore log's `voice: she looks like ...`.

- Does a boss spawned outside its arena fight (its tree may wait on its arena's zone events, or play an entrance show)? Tachy's `M_Tachy_Default` effect plays a show of its own at spawn.
- Does it die by `M_SkullSword`'s rows with a ragdoll (`... died (the game's death)`), or is it held at a floor (`the next hit takes it down`, then `kill: ..., ragdolled`)? Raven's `bDisableCollisionWhenDead`: does her ragdoll stay on the floor?
- Its cut: does `enemy_cut` find its face (Tachy: `CH_M_NA_21_Face`; Raven's and Scarlet's faces are in their bodies, so `face (...): none of deathFace.morphs on ...` is expected for them)? Its struggle: `boss struggle:` lines, joints kept.
- Played as Tachy, Raven or Scarlet (Stellar Blade Play As): a cut and her ragdoll on each (Tachy's 40 hair bodies stay out of her ragdoll's collision, `physfix:` names her asset and `loose bodies jointed: Ab-L-Thigh-Tw0 ...`), Raven's hair coming off with her head, Scarlet's head (in her body) cut with the body, her death cry and the moans after it in the character's voice.

## Parked: diagonal cut

- The diagonal cut (over one shoulder down to the other hip, `gore.diagonal`): built in the 0.5.0 work, parked by the user before it shipped. Off in tune.lua (`diagonal.enabled` false), out of settings.default.lua, F3 and the keys (Alt+Delete); sbslice.c's two fixes for it (`SHEET_OUT`, `NECK_PAST`) off under `DIAG_PARKED`. To pick it up: `DIAG_PARKED` 0, `native/sbslice/test/run.sh diag`, `ue4ss/test/run.sh diag`. Open: CH_P_EVE_10's shoulder gear about 5 cm past the copy's plane; the upper piece's thin hip tip (maybe real wedge geometry).

## Planned: the head and hair split down their length

Parked for later (2026-10-26). A vertical split carried on up through her head, or a head alone split in two. Harness: `HEADSPLIT=1` in `native/sbslice/test/real/real_split.c` on her face mesh (`CH_P_EVE_Face_Jali3`, the one in game):

```
HEADSPLIT=1 HEADN=y HEADSINKB=Bip001-Spine1 HEADSHEET=0.3 HEADOBJ=/tmp/sbslice-real/hs PKG=vanilla/SB/Content/Art/Character/PC/CH_P_EVE_Head/CH_P_EVE_Face_Jali3 native/sbslice/test/real/run.sh CH_P_EVE_Face_Jali3
```

- The face has no facial bones (Root, the Bip001 spine, Head, `Dm-NeckSub`, `Ab-NeckSub`); expressions are morph targets. Half A takes the two neck helpers as flattening sinks, and half B has none left (one mesh asset), so B's seam goes on a borrowed `Bip001-Spine1` that follows the head (as the beheading's `FACESINK`). Both halves: 0 stretched triangles, a straight cut.
- The split's sheet sits `SHEET_IN` (2 cm) inside the kept side: on the head its nose and lips stood out of the cheek as a slab. A head doesn't bend, so 0.3 cm (`sheet_in`, `HEADSHEET`) hides it. Still to do: the lid over the opening (none yet), and the mouth and eye shells, which show as specks through the flat sheet.
- Hair (`00_HR/EVE_HR_01`, in the head's frame with its Root at the head bone; the ponytail `EVE_HR_01_Tail`, a 9-bone chain) can't be cut by weights: every bone of theirs is skinned, so there is no bone to sink the dropped side on. Ideas: the dropped side's skin on one of that side's chain bones, scaled to nothing in the half's pose each frame, or a copy of the hair mesh asset per half. The ponytail goes whole to the half its tie is on. Its physics on the copy's half needs her animation Blueprint (or a ragdoll of its own).
- Renders: `test/real/head/compose.py` (her face half, the hair clipped along the plane in Python as a preview, not sbslice's, and the ponytail) and `render_head.py` (headless Blender; `VIEWS`, `SIZE`, `CENTER`). The hair meshes are extracted into `.cache/work/hair` with retoc (`-f SB/Content/Art/Character/PC/00_HR/EVE_HR_01/...`).

## Blunt Smash: in-game validation

Development resumed 2026-10-31; still experimental and on by default; Smash Every Death remains off. Dedicated sims now cover selection/classification, all ten parts, 90 death/respawn cycles, delayed work and recovery, bounded configuration, effects/audio and the chunks sharing the current seam's material/colour. Run `bash ue4ss/test/run.sh smash smash_hits smash_lifecycle smash_stress smash_effects smash_material`.

The first upper-body playtest on 2026-10-26 froze 0.1 s into the smash. Chunks now explicitly ignore Pawn/PhysicsBody and collide only with the world; invisible smashed parts no longer receive the cut piece's throw/float steering, gradual-opening constraints or new piece/body collision. Offline sims verify those contracts, but cannot exercise the actual engine solver. In game, enable Blunt Smash and Smash Every Death, set death odds to Torso only for a deterministic torso trial, then check head and limb smashes, floor collisions and recovery. Restore the normal odds afterwards. Also check a Skull Hammer kill (internal Blueprint aliases now resolve), the blunt crunch/wet burst, and chunk colour beside the surviving seam under the same light. The stump still uses the normal cut geometry.

## 0.4.3

- Photo mode with her head cut off alive: its hair (ponytail or head hair, not told apart yet) snaps towards her body on a pose change, though it rides the piece's copy and its cloth is reset for 10 frames after the change (a pose seems to bring its own hair snapshot, `PonytailSnapshotDataPtr` / `HairSnapshotDataPtr`). Expressions show on the head only in part (its brows, from her face curves) and look at the camera not at all: most of both are facial bones under her head, which the copy doesn't move. Copying them over each frame (sbslice `Z`, tried and rolled back) is the lead.

## 0.4.2

- Steeply leaned arm and leg cuts (25-45 deg along the blade): the stump cap misses part of the ring on many outfits (the 0.4.1 outfit sweep: most of its ~2,990 failing cuts, all failing on 0.4.0 too). The skin's layers are told apart by how far round the bone's point on the cut each section goes (`core_classify`, 11 of 16 directions), and on a leaned cut that point lies near the oval opening's edge. Measuring round the rim points' mean instead fixed some but broke ~300 others (far rims of capes and straps skew the mean), so it was reverted; it needs a centre that ignores loose pieces.
- Waist cuts that still tear or stretch: CH_P_EVE_14 (`waist high blade arms`: 4 torn, 3 stretched), CH_P_EVE_08 and CH_P_EVE_09_V02.
- CH_P_EVE_DX left upper arm at 0.3, leaned 45 deg (dir 7): 6 more triangles stretch (up to 19 cm, shoulder sink) since the 0.4.1 seam move inside the rim.

- Enemies attacking her body after her death (`enemies.afterDeath`, off by default, F3 → Attacks After Death (experimental)): unparked in 0.5.0. Its swings never found an attack because UE4SS has no `GetPathName` (every enemy's mesh read `in no monster folder`); paths come from `GetFullName` now, and `ue4ss/test/run.sh after` passes end to end on made-up enemies. Still to see in game: an enemy's own attack animation played on its mesh by hand (`PlayAnimation`) moving its weapon through her, with its animation Blueprint taken off meanwhile, and whether the Sawshark's mesh is under /Game/Art/Character/Monster/.
- The struggle and the arm swings (`deathMoves`, on by default since 0.5.0, F3 → Death → Death Struggle): on the test's made-up ragdoll the struggle keeps 86% of each turn and plays out; in game 0%. Next playtest with it on (Alt+F8 then a death, or any limb death): each act's `(N% read back at once)` and `meanwhile her turns zeroed N times` say whether the engine never took the turns or something undid them between steps.

Rerun the outfit sweep (`native/sbslice/test/real/sweep/sweep.sh`, ~25 min) and check `compare.sh` against the 0.4.1 results (`results-0.4.1.txt.gz`: 2,985 of 28,408 cuts fail) so nothing that passes now regresses.
