# To do

## 0.4.3

- Photo mode with her head cut off alive: its hair (ponytail or head hair, not told apart yet) snaps towards her body on a pose change, though it rides the piece's copy and its cloth is reset for 10 frames after the change (a pose seems to bring its own hair snapshot, `PonytailSnapshotDataPtr` / `HairSnapshotDataPtr`). Expressions show on the head only in part (its brows, from her face curves) and look at the camera not at all: most of both are facial bones under her head, which the copy doesn't move. Copying them over each frame (sbslice `Z`, tried and rolled back) is the lead.

## 0.4.2

- Steeply leaned arm and leg cuts (25-45 deg along the blade): the stump cap misses part of the ring on many outfits (the 0.4.1 outfit sweep: most of its ~2,990 failing cuts, all failing on 0.4.0 too). The skin's layers are told apart by how far round the bone's point on the cut each section goes (`core_classify`, 11 of 16 directions), and on a leaned cut that point lies near the oval opening's edge. Measuring round the rim points' mean instead fixed some but broke ~300 others (far rims of capes and straps skew the mean), so it was reverted; it needs a centre that ignores loose pieces.
- Waist cuts that still tear or stretch: CH_P_EVE_14 (`waist high blade arms`: 4 torn, 3 stretched), CH_P_EVE_08 and CH_P_EVE_09_V02.
- CH_P_EVE_DX left upper arm at 0.3, leaned 45 deg (dir 7): 6 more triangles stretch (up to 19 cm, shoulder sink) since the 0.4.1 seam move inside the rim.

- Enemies attacking her body after her death (`enemies.afterDeath`, parked behind `tune.enemyAfterDeath`). What works: the trees' target searches take a dead target (`SbDetectTarget`/`SbMoveToHome` bDead, TargetCancel Destroy) and their `SbIsAlive` checks swapped bring them to her body (within 60-360 cm, playtests), and the node lookup runs ahead of the death (no hitch). What doesn't: the game's skills never fire at a dead target, and playing their attack animations by hand (`PlayAnimation`, with a lunge) never ran. The Sawshark's tree skill names aren't its animation names (`M_Sawshark_S01_RightSwing` ...), and in the last playtest `mesh.SkeletalMesh` of the enemies read empty (`its mesh  is in no monster folder`), so no animation was ever found. Next: read the enemy's mesh some other way (its `Mesh` component's `SkeletalMesh` via the character's own mesh slot, or the anim instance's skeleton), or drive a skill through the game (`SbUseSkill` with the target check bypassed). A bare hand's hit after death now rolls a cut (no plane before), which stays on.

Rerun the outfit sweep (`native/sbslice/test/real/sweep/sweep.sh`, ~25 min) and check `compare.sh` against the 0.4.1 results (`results-0.4.1.txt.gz`: 2,985 of 28,408 cuts fail) so nothing that passes now regresses.
