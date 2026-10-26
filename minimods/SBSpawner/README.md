# SBSpawner

The Stellar Blade Gore mod's enemy spawner on its own: spawn enemies in front of Eve in a game without the gore mod (or any other). Needs [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) for Stellar Blade.

<!-- install -->
**Installing:** extract the zip into the game's folder (`StellarBlade/`), so `SBSpawner` and `SBSpawnerWindow` land in `SB/Binaries/Win64/ue4ss/Mods`. **Uninstalling:** delete those two folders.

| Key | What it does |
|---|---|
| F5 | Spawns the kind picked, 4.5 m in front of Eve, facing her |
| Insert | Picks the next kind |
| Backspace | Removes every enemy spawned |
| Home | Shows or hides the spawner window: pick a kind, Spawn, Spawn 3, Remove all, Kill nearest. The mouse is freed while it shows |
| End | Kills the spawned enemy nearest Eve (the game's own death) |

The kinds: the skulls (sword, spear, hammer, gunner), the lab mutant, the three statues, the two lurkers, and an Airborne Squad angel. More can be added to `KINDS` in `Scripts/main.lua` by their CharacterTable ID.

With the gore mod's Developer Keys on as well, F5, Insert, Home and End do both mods' spawns: use one at a time. The log is `SBSpawner/sbspawner.log`.
<!-- /install -->

Built with `./build.sh` (clang and Rust's lld, as `native/sbslice`): `build/SBSpawner.zip`, `./build.sh --install` to copy it into the game. The window is `native/sbslice/spawner.c`, the gore mod's, built alone (`native/window.c`); spawning goes through the game's `SBNetworkPlayerController:ServerRequest_CreateActor` from Eve's tick.
