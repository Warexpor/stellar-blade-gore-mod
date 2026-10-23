# Stellar Blade Gore Mod

When Eve dies she goes limp as a real ragdoll, bleeds, and the killing blow can take an arm, a leg or her head off, or cut her in half. Generic humanoid enemies you kill get the same cuts.

Version 0.2.3. See the [changelog](CHANGELOG.md).

<!-- install -->
## Install

You need the game on Steam (Windows, Linux or Steam Deck) and nothing else. **The game folder** below is `StellarBlade`, the one with `SB` in it: in Steam, right-click Stellar Blade > Manage > Browse local files.

1. **UE4SS** (skip if another mod already had you install it). Download `UE4SS_v3.1.0-6.zip` from [Chrisr0/RE-UE4SS](https://github.com/Chrisr0/RE-UE4SS/releases/tag/3.1.0-6), the Stellar Blade build (the regular UE4SS won't work). Open it, go into its `UE4SS_v3.1.0-6` folder, and copy `dwmapi.dll` and the `ue4ss` folder into `StellarBlade/SB/Binaries/Win64/`, next to `SB-Win64-Shipping.exe`.
2. **This mod.** Extract `StellarBladeGore-0.2.3.zip` straight into the game folder, merging folders when asked. Its `SB` folder lands on the game's `SB`, and it adds:
   - `SB/Content/Paks/~mods/ZZ_StellarBladeGore_P.pak`, `.ucas`, `.utoc`: the ragdoll death, her death face and voice;
   - `SB/Binaries/Win64/ue4ss/Mods/StellarBladeGore`: the script;
   - `SB/Binaries/Win64/ue4ss/Mods/SBSlice`: its native helper, which makes the cuts and fixes every outfit's ragdoll physics as she puts it on.
3. **Linux / Steam Deck only:** in Steam, Stellar Blade > Properties > Launch Options, put `WINEDLLOVERRIDES="dwmapi=n,b" %command%`. (Without it Proton ignores UE4SS.)

Start the game and die. To check it loaded, open `SB/Binaries/Win64/ue4ss/Mods/StellarBladeGore/stellarbladegore.log`: it starts with `Stellar Blade Gore Mod 0.2.3`, and a few seconds later says `sbslice.dll ready`.

**It doesn't work?**
- No log at all: UE4SS isn't loading. `dwmapi.dll` must sit right next to `SB-Win64-Shipping.exe` (not in a `UE4SS_v3.1.0-6` folder), and on Linux the launch option must be set.
- The log has no `sbslice.dll ready`: `ue4ss/Mods/SBSlice` is missing, or lacks its `enabled.txt` or `dlls/main.dll`.
- She ragdolls but nothing is cut: the log's `gore:` lines say why.
- She dies the vanilla way: the pak isn't in `Paks/~mods`, or another mod replaces her death shows (see Compatibility).

**Updating:** extract the new zip over the old one the same way. Your settings stay: the zip only carries `settings.default.lua`, and the mod makes your `settings.lua` from it on its first start. From a self-built copy, also delete `ZZ_StellarBladeGore_Outfits_P.*` from `Paks/~mods` if it's there: nothing replaces it.

**Uninstalling:** delete these, and the game is as it was:
- `SB/Content/Paks/~mods/ZZ_StellarBladeGore_P.pak`, `.ucas` and `.utoc`;
- the `StellarBladeGore` and `SBSlice` folders in `SB/Binaries/Win64/ue4ss/Mods`.

UE4SS stays for your other mods. To remove it too, delete `dwmapi.dll` and the `ue4ss` folder from `SB/Binaries/Win64` and, on Linux, the launch option. The mod changes none of the game's own files.

## Settings

`SB/Binaries/Win64/ue4ss/Mods/StellarBladeGore/Scripts/settings.lua`, a plain text file the mod makes on its first start (delete it to get the defaults back). Save it and press **F6** in game to apply it without a restart.

| Setting | Default | What it does |
|---|---|---|
| `gore.enabled` | `true` | All cuts and blood. |
<!-- | `gore.hitMarks.enabled` | `true` | Slashes of blood from hits she survives. | -->
| `gore.death` | 50 / 30 / 12 / 8 | Odds of a limb, a beheading, a waist cut or a split down the middle, when the blow doesn't decide. |
| `gore.afterHits.enabled` | `true` | Enemies still swinging at her body cut it again. |
| `gore.voice.enabled` | `true` | Her own death cry. |
| `cameraStill` | `true` | After her death you control the camera up to the death screen: mouse or right stick turns it round her, WASD and Q/E (down/up) or the left stick and triggers fly it, Shift flies faster. It slides smoothly after her body till you fly it, and stops short of walls. |
| `cameraMouse` / `cameraStick` | 3 / 150 | Its mouse and stick speed. |
| `cameraTrack` | 2.5 | How closely it slides after her (0: it stays where she died). |
| `cameraMove` | 400 | Flying speed, cm a second (up to 15 m from where it started). |
<!-- | `deathSkip` | `true` | Esc on her death fast forwards to the death screen instead of the wait. | -->
| `enemies.enabled` | `true` | Cuts on the humanoid enemies you kill. |
| `enemies.attackDown` | `true` | Enemies keep attacking her while she is knocked down (`false`: they wait till she is up, as in the game). |
| `dev` | `false` | Test keys, the enemy spawner and the glass cannon mode (see below). |

Every other knob is in `tune.lua` next to it. `settings.lua` wins over it.

## Compatibility

- **Outfit and nude mods** work, installed before or after this one: every outfit gets its ragdoll fixes in game when she puts it on, and its look is left alone.
- **Face mods** for Eve work: the pak carries no face or body mesh of hers or the enemies' (before 0.2.3 it carried her face, and a face replacer stopped the game at launch).
- **Voice mods** that replace Eve's death cries (`vo_eve_die_*`, e.g. Violent Death Mod) work as they are: her death cry plays their recordings. A mod that adds new sounds instead can be pointed at with `gore.voice.sounds` in `settings.lua`.
- **Proper Death Expression** by blabmice is built in, credited below. Don't install it alongside.
- **Mods that replace her death shows or the death table** (`CharacterDeadTable`) conflict. Whichever loads last wins.
<!-- /install -->

## Dev mode

With `dev = true` in `settings.lua`:

| Key | Test |
|---|---|
| F7 / F8 | Ragdoll her with a shove / get her up |
| F9 | Cut a limb, the head or the torso |
<!-- | F10 | A hit mark | -->
| F11 | Split her in half |
| Ctrl+F5 | Play a death |
| Ctrl+Shift+F5 | Cut her along a made-up blade |
| Shift+F7 | Her death face, for 3 s |
| F5 / Shift+F5 | Spawn an enemy / pick the next kind |
| Shift+F6 | The spawner window |
| Ctrl+F6 | Kill the enemy nearest her |
| Shift+F8 | Glass cannon mode: the shield takes the hits, then one hit kills |

F7, F9 and F11 leave her as they are until F8 (a death gets her up on its own).

Shift+F4 during her death holds it: no death screen and she stays down until Shift+F4 again (the screen comes back then), dev or not. P in a death opens the game's photo mode on her dead body (and holds the death, as Shift+F4 does); the game's own photo mode key works with pieces cut off her too (she holds still in it while alive). F6 reloads the settings whether dev is on or not. On its first start with dev on, the mod also dumps the game's reflection schema for the asset tools.

## Building from source

On Linux, with `git`, `cargo`, `clang`, `llvm-dlltool`, `python3` and `curl`. The .NET 10 SDK is fetched if it's missing.

```bash
./build.sh --install
```

```bash
./ue4ss/install.sh
```

`build.sh` builds the paks from your installed game and the other mods in `Paks/~mods`, so a mod's own death shows or face are patched in its version. It installs only the core pak: the outfits pak it also builds is the reference the in-game physics fixes are tested to (`SB_OUTFITS=1` installs it). `ue4ss/install.sh` sets up UE4SS and installs the script and the DLL, keeping your `settings.lua`.

```bash
./package.sh
```

That builds the release zip in `release/`. Its paks are built without the other mods. `native/sbslice/test/run.sh` runs the cut tests on real meshes and must print `PASS`.

How it all works: [docs/TECHNICAL.md](docs/TECHNICAL.md).

## Credits

- Death face: [Proper Death Expression](https://www.nexusmods.com/stellarblade/mods/2716) by **blabmice**, used with credit as its permissions allow (`third_party/proper-death-expression`).
- [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) and its [Stellar Blade build](https://github.com/Chrisr0/RE-UE4SS).
- Build tools: [retoc](https://github.com/trumank/retoc), [UAssetAPI](https://github.com/atenfyr/UAssetAPI) and the [SB header dump](https://github.com/a5tronomy/SB).

## License

GPL-3.0, see [LICENSE](LICENSE). Not covered: `third_party/` keeps its authors' terms, and `mappings/SB.usmap` describes the game's types. The game and its assets are Shift Up's.
