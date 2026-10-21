# Proper Death Expression

Eve's death face, by **blabmice** (uploaded by labrat00): [Proper Death Expression](https://www.nexusmods.com/stellarblade/mods/2716) on Nexus Mods, version 1.3, main file "Death Expression" (`Death Expression-2716-1-0-1768978846.zip`).

`EVE_Facial_ActionVoice_DIE1.uasset` / `.uexp` is the author's facial animation (300 frames, 11.96 s), extracted unchanged from the mod's IoStore container to a legacy package. Severed ships it in its own pak in place of the vanilla `Art/Character/PC/CH_P_EVE_01/Animation/Facial/EVE_Facial_ActionVoice_DIE1`.

The mod's "Fixes for other Deaths" file (grapple, explosive and falling deaths) is not shipped; Severed does the same through its build instead (`voice` and `notify` jobs in `mod/ragdoll_spec.json`). It adds the silent `DIE3` voice the author added to `CSS_PC_EVE`, which plays this animation, and gives each of the four death animations a new notify for it at the author's time. The author's file reused existing notifies for that, which silenced a cloth or footstep sound in each; Severed's notify is added alongside them.

Permissions, from the mod page: asset use is allowed without asking as long as the author is credited; modification and redistribution with credit are allowed; not allowed in mods that are sold. Severed is free and credits the author here and in the main README.
