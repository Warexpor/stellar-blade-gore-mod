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

## 0.4.3

- Photo mode with her head cut off alive: its hair (ponytail or head hair, not told apart yet) snaps towards her body on a pose change, though it rides the piece's copy and its cloth is reset for 10 frames after the change (a pose seems to bring its own hair snapshot, `PonytailSnapshotDataPtr` / `HairSnapshotDataPtr`). Expressions show on the head only in part (its brows, from her face curves) and look at the camera not at all: most of both are facial bones under her head, which the copy doesn't move. Copying them over each frame (sbslice `Z`, tried and rolled back) is the lead.

## 0.4.2

- Steeply leaned arm and leg cuts (25-45 deg along the blade): the stump cap misses part of the ring on many outfits (the 0.4.1 outfit sweep: most of its ~2,990 failing cuts, all failing on 0.4.0 too). The skin's layers are told apart by how far round the bone's point on the cut each section goes (`core_classify`, 11 of 16 directions), and on a leaned cut that point lies near the oval opening's edge. Measuring round the rim points' mean instead fixed some but broke ~300 others (far rims of capes and straps skew the mean), so it was reverted; it needs a centre that ignores loose pieces.
- Waist cuts that still tear or stretch: CH_P_EVE_14 (`waist high blade arms`: 4 torn, 3 stretched), CH_P_EVE_08 and CH_P_EVE_09_V02.
- CH_P_EVE_DX left upper arm at 0.3, leaned 45 deg (dir 7): 6 more triangles stretch (up to 19 cm, shoulder sink) since the 0.4.1 seam move inside the rim.

- Enemies attacking her body after her death (`enemies.afterDeath`, parked behind `tune.enemyAfterDeath`). What works: the trees' target searches take a dead target (`SbDetectTarget`/`SbMoveToHome` bDead, TargetCancel Destroy) and their `SbIsAlive` checks swapped bring them to her body (within 60-360 cm, playtests), and the node lookup runs ahead of the death (no hitch). What doesn't: the game's skills never fire at a dead target, and playing their attack animations by hand (`PlayAnimation`, with a lunge) never ran. The Sawshark's tree skill names aren't its animation names (`M_Sawshark_S01_RightSwing` ...), and in the last playtest `mesh.SkeletalMesh` of the enemies read empty (`its mesh  is in no monster folder`), so no animation was ever found. Next: read the enemy's mesh some other way (its `Mesh` component's `SkeletalMesh` via the character's own mesh slot, or the anim instance's skeleton), or drive a skill through the game (`SbUseSkill` with the target check bypassed). A bare hand's hit after death now rolls a cut (no plane before), which stays on.

Rerun the outfit sweep (`native/sbslice/test/real/sweep/sweep.sh`, ~25 min) and check `compare.sh` against the 0.4.1 results (`results-0.4.1.txt.gz`: 2,985 of 28,408 cuts fail) so nothing that passes now regresses.
