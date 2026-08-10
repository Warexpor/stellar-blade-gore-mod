# sb-eve-ragdoll-death

UE4SS Lua mod: replace Eve death knockdown anim with in-engine ragdoll + hit throw.

## Status

`0.3.3-probe` — auto-ragdoll on `KnockDown_FullBodyIK_Alpha`; death throw from velocity/hit; respawn restore. Soft jiggle kept; hair pinned.

## Requirements

- Stellar Blade PC
- [UE4SS Build 6 (Stellar Blade)](https://github.com/Chrisr0/RE-UE4SS/releases/tag/3.1.0-6)
- Disable conflicting death-anim pak mods while testing (`death_anim_P`, `death_expression_P`, etc.)

## Install

1. UE4SS in `...\StellarBlade\SB\Binaries\Win64\` (`dwmapi.dll` + `ue4ss\`).
2. Copy `EveRagdollDeath\` into `...\Win64\ue4ss\Mods\`.
3. Ensure `enabled.txt` exists; mod enabled in `mods.txt`.
4. Launch; check `UE4SS.log` for `[EveRagdollDeath`.

## Hotkeys

| Key | Action |
|-----|--------|
| F7 | Undo ragdoll (stuck after death) |
| F8 | Force ragdoll |
| F9 | Dump knock / AnimBP context |
| F10 | Toggle auto-ragdoll |

## Test plan

1. Die to an enemy hit — expect ragdoll throw, not full knockdown anim.
2. Respawn — expect normal control (not stuck ragdoll / map fall).
3. Check log for `knock rise` and `throw from=`.
