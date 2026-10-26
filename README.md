# Stellar Blade Gore Mod

When Eve dies she goes limp as a real ragdoll, bleeds, and the killing blow can take an arm, a leg or her head off, or cut her in half. Generic humanoid enemies you kill get the same cuts.

Version 0.4.4. See the [changelog](CHANGELOG.md).

<!-- install -->
## Install

You need the game on Steam (Windows, Linux or Steam Deck) and nothing else. **The game folder** below is `StellarBlade`, the one with `SB` in it: in Steam, right-click Stellar Blade > Manage > Browse local files.

1. **UE4SS** (skip if another mod already had you install it). Download `UE4SS_v3.1.0-6.zip` from [Chrisr0/RE-UE4SS](https://github.com/Chrisr0/RE-UE4SS/releases/tag/3.1.0-6), the Stellar Blade build (the regular UE4SS won't work). Open it, go into its `UE4SS_v3.1.0-6` folder, and copy `dwmapi.dll` and the `ue4ss` folder into `StellarBlade/SB/Binaries/Win64/`, next to `SB-Win64-Shipping.exe`.
2. **This mod.** Extract `StellarBladeGore-0.4.4.zip` straight into the game folder, merging folders when asked. Its `SB` folder lands on the game's `SB`, and it adds:
   - `SB/Content/Paks/~mods/ZZ_StellarBladeGore_P.pak`, `.ucas`, `.utoc`: the ragdoll death, her death face and voice;
   - `SB/Binaries/Win64/ue4ss/Mods/StellarBladeGore`: the script;
   - `SB/Binaries/Win64/ue4ss/Mods/SBSlice`: its native helper, which makes the cuts and fixes every outfit's ragdoll physics as she puts it on.
3. **Linux / Steam Deck only:** in Steam, Stellar Blade > Properties > Launch Options, put `WINEDLLOVERRIDES="dwmapi=n,b" %command%`. (Without it Proton ignores UE4SS.) **On Windows leave Launch Options empty**: that line is for Proton and Windows can't run it.

Start the game and die. To check it loaded, open `SB/Binaries/Win64/ue4ss/Mods/StellarBladeGore/stellarbladegore.log`: it starts with `Stellar Blade Gore Mod 0.4.4`, and a few seconds later says `sbslice.dll ready`. It is made anew each start; the previous session's is kept as `stellarbladegore.log.old`.

**It doesn't work?**
- No log at all: UE4SS isn't loading. `dwmapi.dll` must sit right next to `SB-Win64-Shipping.exe` (not in a `UE4SS_v3.1.0-6` folder), and on Linux the launch option must be set.
- The log has no `sbslice.dll ready`: `ue4ss/Mods/SBSlice` is missing, or lacks its `enabled.txt` or `dlls/main.dll`.
- Your antivirus deleted `SBSlice/dlls/main.dll`: a false positive (a few scanners' machine-learning guesses, not a known threat; the source is in this repo and the DLL is built from it). Restore it from quarantine and add an exclusion for the `ue4ss/Mods/SBSlice` folder, or extract it from the zip again after adding the exclusion.
- The log says `sbslice.dll refused: ...`: the game's exe isn't the Steam build the helper was made for, and it couldn't find all the engine functions it needs in it (it looks for them by their code), so nothing is cut and outfits' ragdoll physics aren't fixed. Send the log; after a game update, wait for a mod update.
- She ragdolls but nothing is cut: the log's `gore:` lines say why.
- She dies the vanilla way: the pak isn't in `Paks/~mods`, or another mod replaces her death shows (see Compatibility).

**Updating:** extract the new zip over the old one the same way. Your settings stay: the zip only carries `settings.default.lua`, and the mod makes your `settings.lua` from it on its first start. From a self-built copy, also delete `ZZ_StellarBladeGore_Outfits_P.*` from `Paks/~mods` if it's there: nothing replaces it.

**Uninstalling:** delete these, and the game is as it was:
- `SB/Content/Paks/~mods/ZZ_StellarBladeGore_P.pak`, `.ucas` and `.utoc`;
- the `StellarBladeGore` and `SBSlice` folders in `SB/Binaries/Win64/ue4ss/Mods`.

UE4SS stays for your other mods. To remove it too, delete `dwmapi.dll` and the `ue4ss` folder from `SB/Binaries/Win64` and, on Linux, the launch option. The mod changes none of the game's own files.

## Settings

`SB/Binaries/Win64/ue4ss/Mods/StellarBladeGore/Scripts/settings.lua`, a plain text file the mod makes on its first start (delete it to get the defaults back). Save it and open the F3 menu in game to apply it without a restart.

| Setting | Default | What it does |
|---|---|---|
| `gore.enabled` | `true` | All cuts and blood. |
<!-- | `gore.hitMarks.enabled` | `true` | Slashes of blood from hits she survives. | -->
| `gore.death` | 42 / 25 / 15 / 18 | Odds of a limb, a beheading, a cut across her body (under the bust, leaning a little at random) or a split down the middle (running a little diagonally), when the blow doesn't decide. All split (`0` for the rest) splits every death; otherwise a blade seen decides first (`bladeFollow`). |
| `gore.death.moreLimbs` | 0.35 | Chance a rolled limb cut takes the next nearest limb too, and a third at the same chance again. |
| `gore.bladeFollow` | 0.75 | Share of deaths with a tracked blade that the blade alone decides; the rest roll `gore.death`. At `1` most deaths were waist cuts or splits, as a blade mostly crosses her body. |
| `gore.torsoLegs.enabled` | `true` | A cut across her waist sometimes leaves her legs playing her death fall while the upper body flies off in the ragdoll: most often from a level swing, less from a slanted one, half the time when the blow wasn't seen (`level` / `slant` / `rolled` in `tune.lua`). `false`: all of her ragdolls. |
| `gore.afterHits.enabled` | `true` | Enemies still swinging at her body cut it again. |
| `gore.lowArm.enabled` | `false` | A hit that leaves her under a quarter of her HP cuts her left arm off, and she fights on without it (once a life; it grows back with her HP full again, or at her next life). F3 → Lose Arm at Low HP. |
| `gore.throw` | 250 | How fast a cut-off piece flies off, cm a second (`0`: it just drops). |
| `active.animated` | `true` | Light deaths play her own fall animation, and only the cut-off pieces fall by physics; heavy hits, explosions, falls, waist cuts and splits are ragdolls anyway. `false`: every death is a full ragdoll. |
| `gore.headRagdoll` / `legRagdoll` / `armRagdoll` | `false` / `true` / `false` | A beheading, a leg cut or an arm cut during her animated fall turns it into a full ragdoll (`false`: she falls on without it). |
| `gore.armRagdollChance` | `0.4` | With `armRagdoll` off, the chance an arm cut during her animated fall ragdolls her anyway (each arm rolled). |
| `gore.headRagdollChance` | `0.6` | With `headRagdoll` off, the chance a beheading during her animated fall ragdolls her (the rest play the fall on headless). |
| `gore.armsOverSplit` | `0.6` | When a split's blade crossed both her arms, the chance it takes both arms instead of splitting her. |
| `active.push` | `1.0` | How hard the killing blow throws her body, times the default (`0`: no push of the mod's). |
| `convulse.enabled` | `true` | After her death her face winces, gasps, sobs, quivers and twitches for a while (a different face every death), fading out, with quiet breaths and moans (beheaded or split down her length by a vertical slash: her face stays still, no gasps, no voice). `convulse.body = true` makes her body spasm too. |
| `gore.voice.enabled` | `true` | Her own death cry. |
| `gore.deathFace.enabled` | `true` | A dead face on her as she dies, her eyes closing (`false`: the game's own, gone a second in). |
| `convulse.face` | `true` | Her face moving after her death (`false`: it stays as the death face left it). |
| `convulse.voice.enabled` | `true` | The quiet breaths and moans after her death (`false`: silent). |
| `convulse.voice.volume` | `1.0` | How loud those breaths and moans are, times the default (`0.5`: half). |
| `convulse.neck.enabled` | `true` | Her neck straining after her death: her head trying to lift or turn, shaking with the effort, dropping back, then sharp jerks (`false`: her head lies still). |
| `active.stiffness` | `1.0` | How stiff her ragdoll is: `0` limp as a sack, `1` as made, `2`-`3` she keeps her shape as she falls and lies. |
| `deathScreen` | `"delay"` | When the death screen comes up: `"game"` at once, as in the game; `"delay"` `reviveAt` seconds into her death; `"key"` (On Press in the F3 menu) only when you press Shift+F4. Shift+F4 shows it early, and once it is up hides it again (the death held, she stays down). |
| `fewerGC` | `false` | Fewer garbage collection hitches: the engine no longer forces a pass every time it unloads part of the map (its regular pass once a minute still runs). Off puts the game's own behaviour back. |
| `hideHud` | `true` | The HUD (HP bar, skills, minimap, notices) is hidden through her death and comes back when she is up again. The death screen still follows `deathScreen`. |
| `reviveAt` | 10 | Seconds into her death the screen comes up with `"delay"`. |
| `holdPad` | D-pad down + R1 | Shift+F4 on the controller, both held for `holdPadFor` (1 s) (`false`: none). |
| `menuPadIcons` | `"playstation"` | The settings menu's controller key icons: `"playstation"` or `"xbox"` (also in the menu). |
| `cameraStill` | `true` | After her death you control the camera up to the death screen: mouse or right stick turns it round her, WASD and Q/E (down/up) or the left stick and triggers fly it, Shift flies faster. It slides smoothly after her body till you fly it, and stops short of walls. |
| `cameraMouse` / `cameraStick` | 3 / 150 | Its mouse and stick speed. |
| `cameraTrack` | 2.5 | How closely it slides after her (0: it stays where she died). |
| `cameraMove` | 400 | Flying speed, cm a second (up to 15 m from where it started). |
<!-- | `deathSkip` | `true` | Esc on her death fast forwards to the death screen instead of the wait. | -->
| `holdDown` | `true` | Knocked down, she stays on the floor till you dodge or jump (the game's fast getup); `false`: she gets up on her own after a second, as in the game. Air juggles' knockdowns aren't held. |
| `enemies.enabled` | `true` | Cuts on the humanoid enemies you kill. |
| `enemies.cutChance` | `1.0` | Chance a kill cuts something off (0-1). |
| `enemies.pushScale` | `1.0` | Times the game's own throw of a dying enemy (`0`: it drops on the spot, `2`: twice as far). Works with the cuts off too. |
| `enemies.push` | 0 | Cm a second every dying enemy is pushed along the blow on top. |
| `enemies.attackDown` | `true` | Enemies keep attacking her while she is knocked down (`false`: they wait till she is up, as in the game). |
| `smoothAnim` | `false` | Every character animated every frame. The engine skips animation frames on characters further off or small on screen, which can look choppy next to a smooth world, most when they run. Costs some CPU with many characters around. |
| `verboseLog` | `false` | A detailed log (every death's bone speeds, each cut stage, every slow frame...), for a bug report when asked for one. Off, slow frames are summed up once a minute. |
| `dev` | `false` | Test keys, the enemy spawner and the glass cannon mode (see below). |

In game, **F3** (on a controller LB + RB + L3, `menuPad`) opens a menu with most of these, in the look of the game's own settings screen: the world goes on (she doesn't move), Q/E (LB/RB) switch the tab, the arrow keys pick (Up/Down) and change (Left/Right, or < and >), R (Y / Triangle) puts the open tab back to `settings.lua`, Enter / A presses, Backspace / B or F3 closes. The mouse works too: hover picks, click presses (or steps, on a value's arrows), the wheel scrolls. Its key hints are the game's own icons, the keyboard's or the controller's, whichever you used last (`menuPadIcons`: Xbox or PlayStation buttons). Changes apply at once and are saved to `menu.lua` next to `settings.lua`, which they win over ("Reset to settings.lua" deletes it). The menu needs no `FText_Constructor.lua` in `UE4SS_Signatures` (leave it as UE4SS shipped it, `dFText_Constructor.lua`: turned on, it closes the game at launch with the Steam overlay on). If F3 does nothing, the log's `menu:` lines say why; `settings.lua` sets everything without the menu.

Every key of the mod can be changed in the menu's Keys tab: Enter on an action, then press the new key, with Ctrl, Shift or Alt if you like (Backspace cancels). A key another action had is swapped onto the old one. In `settings.lua` it's `keys = { split = "Ctrl+F11", menu = "F2" }` (UE4SS's key names: `F1`-`F12`, `A`-`Z`, `ZERO`-`NINE`, `NUM_ZERO`-`NUM_NINE`, `INS`, `DEL`, `HOME`, `END`, `PAGE_UP`, `PAGE_DOWN`; `"None"` unbinds one). The test keys show there only with Developer Keys on. The actions: `menu`, `hold`, `photo`, and the test keys `slice`, `split`, `mark`, `ragdoll`, `recover`, `face`, `death`, `blade`, `spawn`, `nextEnemy`, `spawner`, `kill`, `glass`. Another mod on the same key (a body slider's menu on F11) still gets it too, so move ours off it.

Every other knob is in `tune.lua` next to it. `settings.lua` wins over it.

## Compatibility

- **Outfit and nude mods** work, installed before or after this one: every outfit gets its ragdoll fixes in game when she puts it on, and its look is left alone.
- **Face mods** for Eve work: the pak carries no face or body mesh of hers or the enemies' (older versions carried her face, and a face replacer stopped the game at launch).
- **Voice mods** that replace Eve's death cries (`vo_eve_die_*`, e.g. Violent Death Mod) work as they are: her death cry plays their recordings. A mod that adds new sounds instead can be pointed at with `gore.voice.sounds` in `settings.lua`.
- **Proper Death Expression** by blabmice is built in, credited below. Don't install it alongside.
- **Ultra Violence** (blood on Eve and her outfit) works alongside: its outfit and face blood, drawn on a see-through copy of her mesh, is cut with her, and its blood comes off her when she respawns after a death (on its own it would stay). Both need the same UE4SS 3.1.0 (Git SHA `d3d1004`, the one this mod installs).
- **UUEPBS** (the body slider) works alongside: her sliders stay on through her deaths and cuts (before the next release, her deaths froze where she was cut).
- **Mods that edit the game's data tables** (movesets, shops, items, effects) work: the mod no longer ships whole `CharacterDeadTable` and `EffectTable` copies, it changes only its own rows in game. A mod that changes the `Player` row's death shows conflicts with it: the mod's are written over them.
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
| Shift+F7 | Her death face, the next mood each press, for 6 s |
| F5 / Shift+F5 | Spawn an enemy / pick the next kind |
| Shift+F6 | The spawner window |
| Ctrl+F6 | Kill the enemy nearest her |
| Shift+F8 | Glass cannon mode: the shield takes the hits, then one hit kills |

For testing a game without this mod, the repo has the spawner on its own (`minimods/SBSpawner`, `./build.sh`; not released).

These are the defaults; the F3 menu's Keys tab changes them. Its last two rows are the controller's combos (`menuPad`, `holdPad`): A, then hold the new buttons together and let go. With Ultra Violence installed, F9, F10 and F11 default to Alt+F9, Alt+F10 and Alt+F11 (it has its menu, outfit blood and blood stages on F9-F11).

F7, F9 and F11 leave her as they are until F8 (a death gets her up on its own).

Shift+F4 during her death brings up the death screen if it isn't up yet (`deathScreen`), and holds the death once it is: no death screen and she stays down until Shift+F4 again (the screen comes back then), dev or not. On a controller it's D-pad down + R1 held for a second (`holdPad`, `holdPadFor`). P (on a controller the game's own photo mode combo, D-pad left + R1 unless rebound) in a death opens the game's photo mode on her dead body (and holds the death, as Shift+F4 does); the game's own photo mode key works with pieces cut off her too (while she lives, what was cut off stays where it fell and its poses and expressions apply to her; its hide option hides her caps and stubs too). Photo mode's camera up close no longer hides her (`photoUnhide`, `photoNearClip` in tune.lua). On its first start with dev on, the mod also dumps the game's reflection schema for the asset tools.

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
