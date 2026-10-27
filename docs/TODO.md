# To do

## Planned: the head and hair split down their length

Parked for later (2026-10-26). A vertical split carried on up through her head, or a head alone split in two. Harness: `HEADSPLIT=1` in `native/sbslice/test/real/real_split.c` on her face mesh (`CH_P_EVE_Face_Jali3`, the one in game):

```
HEADSPLIT=1 HEADN=y HEADSINKB=Bip001-Spine1 HEADSHEET=0.3 HEADOBJ=/tmp/sbslice-real/hs PKG=vanilla/SB/Content/Art/Character/PC/CH_P_EVE_Head/CH_P_EVE_Face_Jali3 native/sbslice/test/real/run.sh CH_P_EVE_Face_Jali3
```

- The face has no facial bones (Root, the Bip001 spine, Head, `Dm-NeckSub`, `Ab-NeckSub`); expressions are morph targets. Half A takes the two neck helpers as flattening sinks, and half B has none left (one mesh asset), so B's seam goes on a borrowed `Bip001-Spine1` that follows the head (as the beheading's `FACESINK`). Both halves: 0 stretched triangles, a straight cut.
- The split's sheet sits `SHEET_IN` (2 cm) inside the kept side: on the head its nose and lips stood out of the cheek as a slab. A head doesn't bend, so 0.3 cm (`sheet_in`, `HEADSHEET`) hides it. Still to do: the lid over the opening (none yet), and the mouth and eye shells, which show as specks through the flat sheet.
- Hair (`00_HR/EVE_HR_01`, in the head's frame with its Root at the head bone; the ponytail `EVE_HR_01_Tail`, a 9-bone chain) can't be cut by weights: every bone of theirs is skinned, so there is no bone to sink the dropped side on. Ideas: the dropped side's skin on one of that side's chain bones, scaled to nothing in the half's pose each frame, or a copy of the hair mesh asset per half. The ponytail goes whole to the half its tie is on. Its physics on the copy's half needs her animation Blueprint (or a ragdoll of its own).
- Renders: `test/real/head/compose.py` (her face half, the hair clipped along the plane in Python as a preview, not sbslice's, and the ponytail) and `render_head.py` (headless Blender; `VIEWS`, `SIZE`, `CENTER`). The hair meshes are extracted into `.cache/work/hair` with retoc (`-f SB/Content/Art/Character/PC/00_HR/EVE_HR_01/...`).

## Parked: Blunt Smash

Parked for now (2026-10-26), in the game but not a main feature: off by default (`tune.gore.smash.enabled`), out of the README and `settings.default.lua`; F3 → Blunt Smash and Smash Every Death still switch it. A blunt killing blow (by name: `smash.blunt` / `smash.sharp`) smashes the arm, leg, head or upper body it hit to the game's meat chunks (`SM_meat_01`-`04`) instead of cutting it; see TECHNICAL.md's Blunt smash.

- Playtested on F6 only (Smash Every Death): limbs smash, the chunks lie where they land. The first upper body smash (F6, 2026-10-26) froze the game 0.1 s in, no crash dump: its seven chunks came out inside her hidden chest's still-simulating bodies; the chunks now collide with the level alone, untried since. Head smashes, the blunt/sharp judgement on real enemies (the name lists are from the asset list, unchecked) and its sounds are untried.
- Its own stump look: for now a cut's stump.

## 0.4.3

- Photo mode with her head cut off alive: its hair (ponytail or head hair, not told apart yet) snaps towards her body on a pose change, though it rides the piece's copy and its cloth is reset for 10 frames after the change (a pose seems to bring its own hair snapshot, `PonytailSnapshotDataPtr` / `HairSnapshotDataPtr`). Expressions show on the head only in part (its brows, from her face curves) and look at the camera not at all: most of both are facial bones under her head, which the copy doesn't move. Copying them over each frame (sbslice `Z`, tried and rolled back) is the lead.

## 0.4.2

- Steeply leaned arm and leg cuts (25-45 deg along the blade): the stump cap misses part of the ring on many outfits (the 0.4.1 outfit sweep: most of its ~2,990 failing cuts, all failing on 0.4.0 too). The skin's layers are told apart by how far round the bone's point on the cut each section goes (`core_classify`, 11 of 16 directions), and on a leaned cut that point lies near the oval opening's edge. Measuring round the rim points' mean instead fixed some but broke ~300 others (far rims of capes and straps skew the mean), so it was reverted; it needs a centre that ignores loose pieces.
- Waist cuts that still tear or stretch: CH_P_EVE_14 (`waist high blade arms`: 4 torn, 3 stretched), CH_P_EVE_08 and CH_P_EVE_09_V02.
- CH_P_EVE_DX left upper arm at 0.3, leaned 45 deg (dir 7): 6 more triangles stretch (up to 19 cm, shoulder sink) since the 0.4.1 seam move inside the rim.

- Enemies attacking her body after her death (`enemies.afterDeath`, off by default, F3 → Attacks After Death): unparked in 0.4.7. Its swings never found an attack because UE4SS has no `GetPathName` (every enemy's mesh read `in no monster folder`); paths come from `GetFullName` now, and `ue4ss/test/run.sh after` passes end to end on made-up enemies. Still to see in game: an enemy's own attack animation played on its mesh by hand (`PlayAnimation`) moving its weapon through her, with its animation Blueprint taken off meanwhile, and whether the Sawshark's mesh is under /Game/Art/Character/Monster/.
- The struggle and the arm swings (`deathMoves`, off by default, F3 → Death → Death Struggle (Testing) since 0.4.7): on the test's made-up ragdoll the struggle keeps 86% of each turn and plays out; in game 0%. Next playtest with it on (Alt+F8 then a death, or any limb death): each act's `(N% read back at once)` and `meanwhile her turns zeroed N times` say whether the engine never took the turns or something undid them between steps.

Rerun the outfit sweep (`native/sbslice/test/real/sweep/sweep.sh`, ~25 min) and check `compare.sh` against the 0.4.1 results (`results-0.4.1.txt.gz`: 2,985 of 28,408 cuts fail) so nothing that passes now regresses.
