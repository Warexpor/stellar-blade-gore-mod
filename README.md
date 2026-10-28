# Stellar Blade Gore Mod

When Eve dies she goes limp as a real ragdoll, bleeds, and the killing blow can take an arm, a leg or her head off, or cut her in half. Generic humanoid enemies you kill get the same cuts.

Version 0.5.2. See the [changelog](CHANGELOG.md).

<!-- install -->
## Install

You need the game on Steam (Windows, Linux or Steam Deck) and nothing else. **The game folder** below is `StellarBlade`, the one with `SB` in it: in Steam, right-click Stellar Blade > Manage > Browse local files.

1. **UE4SS** (skip if another mod already had you install it). Download `UE4SS_v3.1.0-6.zip` from [Chrisr0/RE-UE4SS](https://github.com/Chrisr0/RE-UE4SS/releases/tag/3.1.0-6), the Stellar Blade build (the regular UE4SS won't work). The Nexus "SB UE4SS" build ([mod 2952](https://www.nexusmods.com/stellarblade/mods/2952), 1.3) works too. Open it, go into its `UE4SS_v3.1.0-6` folder, and copy `dwmapi.dll` and the `ue4ss` folder into `StellarBlade/SB/Binaries/Win64/`, next to `SB-Win64-Shipping.exe`.
2. **This mod.** Extract `StellarBladeGore-0.5.2.zip` straight into the game folder, merging folders when asked. Its `SB` folder lands on the game's `SB`, and it adds:
   - `SB/Content/Paks/~mods/ZZ_StellarBladeGore_P.pak`, `.ucas`, `.utoc`: the ragdoll death and her death voice;
   - `SB/Content/Paks/~mods/ZZ_StellarBladeGore_Face_P.pak`, `.ucas`, `.utoc`: her death face (delete it with Customized Ragdoll or Proper Death Expression installed, below);
   - `SB/Binaries/Win64/ue4ss/Mods/StellarBladeGore`: the script;
   - `SB/Binaries/Win64/ue4ss/Mods/SBSlice`: its native helper, which makes the cuts and fixes every outfit's ragdoll physics as she puts it on.
3. **Linux / Steam Deck only:** in Steam, Stellar Blade > Properties > Launch Options, put `WINEDLLOVERRIDES="dwmapi=n,b" %command%`. (Without it Proton ignores UE4SS.) **On Windows leave Launch Options empty**: that line is for Proton and Windows can't run it.

Start the game and die. To check it loaded, open `SB/Binaries/Win64/ue4ss/Mods/StellarBladeGore/stellarbladegore.log`: it starts with `Stellar Blade Gore Mod 0.5.2`, and a few seconds later says `sbslice.dll ready`. It is made anew each start; the previous session's is kept as `stellarbladegore.log.old`.

**It doesn't work?**
- No log at all: UE4SS isn't loading. `dwmapi.dll` must sit right next to `SB-Win64-Shipping.exe` (not in a `UE4SS_v3.1.0-6` folder), and on Linux the launch option must be set.
- The log has no `sbslice.dll ready`: `ue4ss/Mods/SBSlice` is missing, or lacks its `enabled.txt` or `dlls/main.dll`.
- Your antivirus deleted `SBSlice/dlls/main.dll`: a false positive (a few scanners' machine-learning guesses, not a known threat; the source is in this repo and the DLL is built from it). Restore it from quarantine and add an exclusion for the `ue4ss/Mods/SBSlice` folder, or extract it from the zip again after adding the exclusion.
- The log says `sbslice.dll refused: ...`: the game's exe isn't the Steam build the helper was made for, and it couldn't find all the engine functions it needs in it (it looks for them by their code), so nothing is cut and outfits' ragdoll physics aren't fixed. Send the log; after a game update, wait for a mod update.
- She ragdolls but nothing is cut: the log's `gore:` lines say why.
- She dies the vanilla way: the pak isn't in `Paks/~mods`, or another mod replaces her death shows (see Compatibility).

**Updating:** extract the new zip over the old one the same way. Your settings stay: the zip only carries `settings.default.lua`, and the mod makes your `settings.lua` from it on its first start. From a self-built copy, also delete `ZZ_StellarBladeGore_Outfits_P.*` from `Paks/~mods` if it's there: nothing replaces it.

**Uninstalling:** delete these, and the game is as it was:
- `SB/Content/Paks/~mods/ZZ_StellarBladeGore_P.pak`, `.ucas` and `.utoc`, and `ZZ_StellarBladeGore_Face_P` the same;
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
| `gore.followUpCuts` | `true` | One swing cuts everything it went through (both arms and her body, say). `false`: one cut a swing, her body when the blade went through it, else the limb it met; no extra limbs from `moreLimbs` either. A laser trap still cuts along its beam. F3 → Follow-up Cuts. |
| `gore.bladeFollow` | 0.75 | Share of deaths with a tracked blade that the blade alone decides; the rest roll `gore.death`. At `1` most deaths were waist cuts or splits, as a blade mostly crosses her body. |
| `gore.oddsNear.enabled` | true | The odds above, when rolled, lean to what is near where the blow landed: a swing at her waist cuts the waist, a nearby arm or leg, or splits her if it came down her length, never her head; one at her neck mostly beheads. Odds with only one kind above 0 still do that one every death, wherever it hit. F3 → Chances Follow the Hit. |
| `gore.oddsNear.floor` | 0 | Share of its odds a part far from the hit keeps (0-1): `0.1` lets a waist swing behead now and then, `1` is as if off. F3 → Far Part Chance. |
| `gore.torsoLegs.enabled` | `true` | A cut across her waist sometimes leaves her legs playing her death fall while the upper body flies off in the ragdoll: most often from a level swing, less from a slanted one, half the time when the blow wasn't seen (`level` / `slant` / `rolled` in `tune.lua`). `false`: all of her ragdolls. |
| `gore.asyncLoad` | `true` | The cuts' effects, materials and sounds load ahead through the game's async loader (no stutters at the start); `false`: one at a time on the game thread. |
| `gore.afterHits.enabled` | `true` | Enemies still swinging at her body cut it again: in an attack, the weapon at `minSpeed` (500) cm/s or more within `reach` (25) cm of her. |
| `enemies.grab.enabled` | `true` | A death in an enemy's grab waits for the grab to end (at most `most`, 6 s): the cut and the ragdoll come as it lets go. |
<!-- | `gore.smash.enabled` | `false` | Experimental. A blunt killing blow (a hammer, a fist, a stomp) smashes the arm, leg, head or upper body it hit instead of cutting it (no blow seen: rolled on the death odds): the part vanishes, the game's own meat chunks and a burst of blood fly out where it was, and the stump stays as a cut's. What hit her is told by name (the enemy's weapon, the bone it swung, the enemy itself: `smash.sharp` / `smash.blunt` in `tune.lua`); blades still cut. F3 → Blunt Smash. `gore.smash.always`: with it on, every death smashes, to try it. | -->
| `gore.laserCut` | `true` | A laser trap death cuts her along the beam: every arm, leg, her body or her head its plane goes through comes off (a level beam cuts her at its height). The beam that hit her, else one within `laserReach` (40) cm of her. Off: the death odds. F3 → Laser Cuts Along the Beam. |
| `gore.bluntRagdoll` | `false` | A blunt killing blow (a hammer, a fist, a stomp) cuts nothing: her death is a plain ragdoll, and hits after it cut nothing either; blades still cut. What hit her is told by name (the enemy's weapon, the bone it swung, the enemy itself: `smash.sharp` / `smash.blunt` in `tune.lua`). F3 → Blunt Kills Only Ragdoll. |
| `gore.lowArm.enabled` | `false` | A hit (a blow, not a fall) that leaves her under `below` (a quarter) of her HP cuts an arm off (`side`), and she fights on without it. It dissolves back in when she rests at a camp, or comes back at her next life. It stays off through a level change and its cutscene; a save loaded brings it back. F3 → Gameplay → Lose Arm at Low HP. |
| `gore.lowArm.side` | `"hit"` | Which arm comes off: `"hit"` the one on the side of her the blow landed on (one at random when it landed on her middle or the game gave no hit), `"left"`, `"right"` or `"either"` (one at random each time). F3 → Gameplay → Which Arm (Side Hit, Left, Right, Either). |
| `gore.lowArm.below` | `0.25` | The share of her HP (25%) a hit has to leave her under for the arm to come off. F3 → Gameplay → Arm Comes Off Below, in 1% steps. |
| `gore.lowArm.noHealGun` | `true` | While her left arm is off she can't use heal items or shoot the gun (both need her left hand). F3 → Gameplay → No Heals or Gun Without It. |
| `gore.lowArm.notice` | `true` | With `noHealGun`: pressing her aim or heal key while the arm is off shows the game's own "Cannot use right now." notice, with its sound. F3 → Gameplay → 'Cannot Use' Notice. |
| `gore.lowArm.noSword` | `true` | While her right arm is off she can't use her sword: the game's own swordless stance (as where her sword is taken from her), the sword folded away. Dodges, the gun and heals still work; no lock-on or drone scan meanwhile. F3 → Gameplay → No Sword Without It. |
| `gore.lowArm.healBack` | `false` | The arm also grows back once her HP is back at `healAt` (0.9), however she healed (gear that restores HP on kills or over time), and at least 1% over `below`. F3 → Gameplay → Grows Back With HP, Grows Back At (1% steps). |
| `gore.lowArm.effect` | `true` | A part cut off her alive (that arm, F9's) dissolves back in with a glow when it comes back. Off: it is back at once, with no effect. F3 → Gameplay → Regrow Effect. |
| `gore.throw` | 250 | How fast a cut-off piece flies off, cm a second (`0`: it just drops). |
| `active.animated` | `true` | Light deaths play her own fall animation, and only the cut-off pieces fall by physics; heavy hits, explosions, falls and fall damage, waist cuts and splits are ragdolls anyway. `false`: every death is a full ragdoll. |
| `active.fallRagdoll` | `true` | A death within 2 s of landing from a 4 m drop or more is a ragdoll, not her animated stand death. A fall damage death cuts nothing. A minor fall itself leaves her at 1 HP, as in the unmodded game; a high one plays the game's falling death, a ragdoll already. F3 → Fall Damage Ragdoll. |
| `gore.headRagdoll` / `legRagdoll` / `armRagdoll` | `false` / `true` / `false` | A beheading, a leg cut or an arm cut during her animated fall turns it into a full ragdoll (`false`: she falls on without it). |
| `gore.armRagdollChance` | `0.4` | With `armRagdoll` off, the chance an arm cut during her animated fall ragdolls her anyway (each arm rolled). |
| `gore.headRagdollChance` | `0.6` | With `headRagdoll` off, the chance a beheading during her animated fall ragdolls her (the rest play the fall on headless). |
| `gore.armsOverSplit` | `0.6` | When a split's blade crossed both her arms, the chance it takes both arms instead of splitting her. |
| `active.push` | `1.0` | How hard the killing blow throws her body, times the default (`0`: no push of the mod's). |
| `convulse.enabled` | `true` | After her death her face winces, gasps, sobs, quivers and twitches for a while (a different face every death), fading out, with quiet breaths and moans (beheaded or split down her length by a vertical slash: her face stays still, no gasps, no voice). `convulse.body = true` makes her body spasm too. |
| `gore.voice.enabled` | `true` | Her own death cry. |
| `gore.voice.asHer` | `true` | Played as Tachy, Raven or Scarlet (the Stellar Blade Play As mod, or any mod putting their meshes on Eve), her death cry and the breaths and moans after it are that character's own recordings (`false`: Eve's). Not with `gore.voice.sounds` set. |
| `gore.deathFace.enabled` | `true` | A dead face on her as she dies, her eyes closing (`false`: the game's own, gone a second in). |
| `convulse.face` | `true` | Her face moving after her death (`false`: it stays as the death face left it). |
| `convulse.voice.enabled` | `true` | The quiet breaths and moans after her death (`false`: silent). |
| `convulse.voice.volume` | `1.0` | How loud those breaths and moans are, times the default (`0.5`: half). |
| `convulse.neck.enabled` | `true` | Her neck straining after her death: her head trying to lift or turn, shaking with the effort, dropping back, then sharp jerks (`false`: her head lies still). |
| `deathMoves` | `true` | After a ragdoll death with a limb cut off, or cut across the waist, she struggles on the floor over her last seconds (a hand on the stump or going out to it, trying to sit up or crawl; after a waist cut her upper body clutches the wound and crawls), and her arms swing in her last movements (`false`: her body lies still, her face and breathing still move). F3 → Death → Death Struggle. |
| `struggle.strength` | `1.0` | How hard she moves in the struggle, times the default. F3 → Death → Struggle Strength. |
| `struggle.length` | `1.0` | How long the struggle lasts, times the default (5-8 s). F3 → Death → Struggle Length. |
| `struggle.rise.alone` | `0.5` | The share of ragdoll deaths with nothing cut off in which she still tries to sit up or prop herself up (`0`: they lie still). F3 → Death → Sit Up Uncut. |
| `convulse.armSwing.enabled` | `true` | With `deathMoves`: her arms lift and drop, or make a crawl's stroke, now and then in her last movements (`false`: only the struggle moves them). F3 → Death → Arm Swings. |
| `active.stiffness` | `1.0` | How stiff her ragdoll is: `0` limp as a sack, `1` as made, `2`-`3` she keeps her shape as she falls and lies. |
| `active.neutral.enabled` | `true` | Relaxed Pose In Flight: thrown by a hard hit, her joints are pulled towards a relaxed, curled pose until she lands (needs `sbslice.dll`). `active.neutral.pose` holds the pose, `stiffness` how hard it pulls. |
| `deathScreen` | `"delay"` | When the death screen comes up: `"game"` at once, as in the game; `"delay"` `reviveAt` seconds into her death; `"key"` (On Press in the F3 menu) only when you press Shift+F4. Shift+F4 shows it early, and once it is up hides it again (the death held, she stays down). |
| `fewerGC` | `false` | Fewer garbage collection hitches: the engine no longer forces a pass every time it unloads part of the map (its regular pass once a minute still runs). Off puts the game's own behaviour back. |
| `customizedRagdoll` | `false` | Support for [Customized Ragdoll](https://www.nexusmods.com/stellarblade/mods/3884) (F3 → Death, Customized Ragdoll Support): its death camera instead of the Free Camera, and the death screen up at once but invisible, its F / R working with no holding needed (Shift+F4 shows it). This mod's ragdoll, cuts, struggle and face stay as they are. |
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
| `enemies.attackDown` | `true` | Enemies keep attacking her while she is knocked down (`false`: they wait till she is up, as in the game). Still in the works (it does little yet): settings.lua only, out of the F3 menu. |
| `enemies.afterDeath.enabled` | `false` | Being tested: after her death the enemies around her keep at her body for `time` (10) s, playing their own attacks at it, and their weapons cut it (Hits After Death). F3 → Attacks After Death (experimental). |
| `bosses.enabled` | `false` | Sandbox Bosses: F3 → Sandbox → Spawn Boss brings Tachy, Raven or Scarlet (`bosses.pick`; Scarlet needs her DLC) in 7 m in front of Eve, anywhere, fighting at once. Killed, a boss dies like any enemy: no death cutscene, no phase change to wait out; it is cut, struggles on the floor (`bosses.struggle`, with Death Struggle on) and wears a dead face (`bosses.face`, with Death Expression on). Their HP and shield are `bosses.hpScale` (25%) of the game's. `bosses.passive` (Passive Bosses) keeps a spawned one standing still, never attacking (its own behaviour tree stopped, its AI controller off it). A boss that stops taking damage (held invincible by a phase change it can't play: a passive one's, or Scarlet's outside her arena) is taken down after a few blows that take none of its HP (`bosses.stuckHits` over `bosses.stuckS`; its HP is read from its memory). While one you spawned is up, that boss is mortal everywhere, a story fight with it too; once none is, the game's own boss is back. Remove Spawned takes them all away. |
| `smoothAnim` | `false` | Every character animated every frame. The engine skips animation frames on characters further off or small on screen, which can look choppy next to a smooth world, most when they run. Costs some CPU with many characters around. |
| `verboseLog` | `false` | A detailed log (every death's bone speeds, each cut stage, every slow frame...), for a bug report when asked for one. Off, slow frames are summed up once a minute. |
| `dev` | `false` | Test keys and the enemy spawner (see below). |

In game, **F3** (on a controller LB + RB + L3, `menuPad`) opens a menu with most of these, in the look of the game's own settings screen: the world goes on (she doesn't move), Q/E (LB/RB) switch the tab, the arrow keys pick (Up/Down) and change (Left/Right, or < and >), R (Y / Triangle) puts the open tab back to `settings.lua`, Enter / A presses, Backspace / B or F3 closes. The mouse works too: hover picks, click presses (or steps, on a value's arrows), the wheel scrolls. Its key hints are the game's own icons, the keyboard's or the controller's, whichever you used last (`menuPadIcons`: Xbox or PlayStation buttons). Changes apply at once and are saved to `menu.lua` next to `settings.lua`, which they win over (a change to a setting the menu no longer has is dropped from it as the menu starts) ("Reset to settings.lua" deletes it). The menu needs no `FText_Constructor.lua` in `UE4SS_Signatures` (leave it as UE4SS shipped it, `dFText_Constructor.lua`: turned on, it closes the game at launch with the Steam overlay on). If F3 does nothing, the log's `menu:` lines say why; `settings.lua` sets everything without the menu.

Every key of the mod can be changed in the menu's Keys tab: Enter on an action, then press the new key, with Ctrl, Shift or Alt if you like (Backspace cancels). A key another action had is swapped onto the old one. In `settings.lua` it's `keys = { split = "Ctrl+F11", menu = "Ctrl+F3" }` (UE4SS's key names: `F1`-`F12`, `A`-`Z`, `ZERO`-`NINE`, `NUM_ZERO`-`NUM_NINE`, `INS`, `DEL`, `HOME`, `END`, `PAGE_UP`, `PAGE_DOWN`; `"None"` unbinds one). The test keys show there only with Developer Keys on. The actions: `menu`, `hold`, `photo`, and the test keys `slice`, `split`, `mark`, `ragdoll`, `recover`, `face`, `death`, `blade`, `spawn`, `nextEnemy`, `spawner`, `kill`, `glass`. Another mod on the same key (a body slider's menu on F11) still gets it too, so move ours off it.

Every other knob is in `tune.lua` next to it. `settings.lua` wins over it.

## Compatibility

- **Outfit and nude mods** work, installed before or after this one: every outfit gets its ragdoll fixes in game when she puts it on, and its look is left alone.
- **Face mods** for Eve work: the pak carries no face or body mesh of hers or the enemies' (older versions carried her face, and a face replacer stopped the game at launch).
- **Voice mods** that replace Eve's death cries (`vo_eve_die_*`, e.g. Violent Death Mod) work as they are: her death cry plays their recordings. A mod that adds new sounds instead can be pointed at with `gore.voice.sounds` in `settings.lua`.
- **Proper Death Expression** by blabmice is built in (`ZZ_StellarBladeGore_Face_P`), credited below. To install it anyway, delete `ZZ_StellarBladeGore_Face_P.*` from `Paks/~mods`: two paks with the same asset keep the game loading forever.
- **Alternative Death Animations** by boogibogie works alongside: its stand, down and explosion deaths play, and her ragdoll, cuts and death face come on top.
- **[Customized Ragdoll](https://www.nexusmods.com/stellarblade/mods/3884)**: turn on Customized Ragdoll Support (F3 → Death, `customizedRagdoll`). Its death camera follows her, and the death screen comes up at once but invisible, F / R working; this mod's ragdoll, cuts, struggle and face as ever. Its own ragdoll physics (and its `[` `]` `\` keys) stay off: they would undo the cuts. **Delete `ZZ_StellarBladeGore_Face_P.pak`, `.ucas` and `.utoc` from `Paks/~mods`**: its `death_expression_p` carries a death face of its own (and its camera, so keep that one), and with both the game loads forever (reported). Its face plays then. It ships the same `death_anim_p` pak name as Alternative Death Animations, so one replaces the other. Off, its ragdoll swaps her physics asset at her death and fights this mod's.
- **Ultra Violence** (blood on Eve and her outfit) works alongside: its outfit and face blood, drawn on a see-through copy of her mesh, is cut with her, and its blood comes off her when she respawns after a death (on its own it would stay). Both need the same UE4SS 3.1.0 (Git SHA `d3d1004`, the one this mod installs).
- **[ESE](https://www.nexusmods.com/stellarblade/mods/672)** (Shield and Destroyed) works alongside, in any load order: a part cut off her stays off when it puts her in another suit as her shield breaks or she dies.
- **UUEPBS** (the body slider) works alongside: her sliders stay on through her deaths and cuts (before the next release, her deaths froze where she was cut).
- **[Stellar Blade Play As](https://github.com/Warexpor/stellar-blade-play-as)** (play as Tachy, Raven or Scarlet, a mod of its own) works alongside: the cuts, struggle and dead face are hers as they are Eve's, and her death cry and moans are that character's own.
- **Character swap mods** (EVE2Tachy, EVE2Raven) work: the cuts follow the meshes on Eve. Don't use them with Play As set to anyone but Eve: both put meshes on her.
- **Mods that edit the game's data tables** (movesets, shops, items, effects) work: the mod no longer ships whole `CharacterDeadTable` and `EffectTable` copies, it changes only its own rows in game. A mod that changes the `Player` row's death shows conflicts with it: the mod's are written over them.
<!-- /install -->

## Dev mode

With `dev = true` in `settings.lua`:

| Key | Test |
|---|---|
| F7 / F8 | Ragdoll her with a shove / get her up |
| Alt+F7 / Alt+F8 | Lose Arm at Low HP's cut now: her left arm (no heals or gun) / her right arm (no sword). Needs Lose Arm at Low HP on |
| F9 | Cut a limb, the head or the torso (grows back at a camp rest) |
<!-- | F10 | A hit mark | -->
| F11 | Split her in half |
| F6 | Test the struggle: a ragdoll death with set cuts, the next each press (right arm, left leg, waist, left arm and right leg, both legs, left forearm, no cut), with F7's shove; she lies till F8 |
| Alt+F6 | Test the animated death: plays the game's own death animations on her, the next each press (standing, two hit deaths, lying down), so a death animation mod's show; always the animated death, no cut; she lies till F8 |
| Delete | Cut her along a made-up blade |
| Page Up | Her death face, the next mood each press, for 6 s |
| F5 / Insert | Spawn an enemy / pick the next kind |
| Home | The spawner window |
| End | Kill the enemy nearest her |

For testing a game without this mod, the repo has the spawner on its own (`minimods/SBSpawner`, `./build.sh`; not released).

These are the defaults; the F3 menu's Keys tab changes them. Its last two rows are the controller's combos (`menuPad`, `holdPad`): A, then hold the new buttons together and let go. With Ultra Violence installed, F9, F10 and F11 default to Alt+F9, Alt+F10 and Alt+F11 (it has its menu, outfit blood and blood stages on F9-F11).

F7, F9 and F11 leave her as they are until F8 (a death gets her up on its own; a camp rest grows back what F9 cut off her alive).

Shift+F4 during her death brings up the death screen if it isn't up yet (`deathScreen`), and holds the death once it is: no death screen and she stays down until Shift+F4 again (the screen comes back then), dev or not. On a controller it's D-pad down + R1 held for a second (`holdPad`, `holdPadFor`). P (on a controller the game's own photo mode combo, D-pad left + R1 unless rebound) in a death opens the game's photo mode on her dead body; the death waits while it is open and goes on as it closes (held with Shift+F4 first, it stays held); the game's own photo mode key works with pieces cut off her too (while she lives, what was cut off stays where it fell and its poses and expressions apply to her; its hide option hides her caps and stubs too). Photo mode's camera up close no longer hides her (`photoUnhide`, `photoNearClip` in tune.lua). On its first start with dev on, the mod also dumps the game's reflection schema for the asset tools.

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

That builds the release zip in `release/`. Its paks are built without the other mods. `native/sbslice/test/run.sh` runs the cut tests on real meshes and must print `PASS`. `ue4ss/test/run.sh` runs the scripts against a made-up game (no game needed: a fall death, the regrow, the struggle, attacks after death, a level reload with an arm or her head off, the stumps' left-right mirroring, a cape on an arm cut, the death camera after a zoomed-in death, the async preloads, a cut's stages in fewer frames, and a sweep of every key and many deaths) and must print `PASS` for each scenario.

How it all works: [docs/TECHNICAL.md](docs/TECHNICAL.md).

## Credits

- Death face: [Proper Death Expression](https://www.nexusmods.com/stellarblade/mods/2716) by **blabmice**, used with credit as its permissions allow (`third_party/proper-death-expression`).
- [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) and its [Stellar Blade build](https://github.com/Chrisr0/RE-UE4SS).
- Build tools: [retoc](https://github.com/trumank/retoc), [UAssetAPI](https://github.com/atenfyr/UAssetAPI) and the [SB header dump](https://github.com/a5tronomy/SB).

## License

GPL-3.0, see [LICENSE](LICENSE). Not covered: `third_party/` keeps its authors' terms, and `mappings/SB.usmap` describes the game's types. The game and its assets are Shift Up's.
