-- The in-game settings menu (tune.menuKey F3, or tune.menuPad on the controller): plain UMG widgets made here at
-- runtime in the look of the game's own settings screen (its fonts, colours and layout; nothing in the pak). The
-- world goes on while it is open (it was slowed to a stop: asked not to be); her moving and looking are held. Q/E (LB/RB) switch the tab, Up/Down (or the D-pad) picks a row, < >
-- (or the D-pad) changes it, R / Y (Triangle) puts the tab back to settings.lua, Enter / A presses a button, Backspace / B or the key again closes it. A change applies at once; on
-- closing, the changed values are saved to menu.lua (path = value), which wins over settings.lua, and the settings
-- are read again (the enemies' and the death table's are made over from them). "Reset to settings.lua" deletes it.
-- The Keys tab (keys.lua): Enter on a row, then the new key, which another action had is swapped onto its old one.
local M = {}
local ctx, log, try, valid

M.PATH = "ue4ss/Mods/StellarBladeGore/Scripts/menu.lua"
M.FONT = "/Game/Art/Font/Rajdhani-BoldM_Font.Rajdhani-BoldM_Font"
-- the settings screen's own: labels in Mideum, values and tabs in Bold (M.FONT when one isn't found)
M.FONT_MID = "/Game/Art/Font/Mideum.Mideum"
M.FONT_BOLD = "/Game/Art/Font/Bold.Bold"
-- the menu's languages (tune.language): each but English has its strings in lang_<code>.lua, by row (English is the
-- rows' own). Mideum and Bold carry the game's face for each script, but use it only with the game itself set to
-- that language (their sub-fonts are tied to it): the menu's text is in a copy of them with that face their own and
-- no others, made the first time and kept for good (rooted through sbslice.dll: the engine's font cache keys on the
-- font's address, and a copy freed and another made there would find the old one's)
M.LANGS = { "en", "zh", "ja", "ko", "ru" }
M.LANG_NAMES = { en = "English", zh = "简体中文", ja = "日本語", ko = "한국어", ru = "Русский" }
-- each language's face for Mideum and for Bold (the ones they have for it)
M.FACES = {
  zh = { "/Game/Art/Font/china/MXiangHeHeiSCStd-Light", "/Game/Art/Font/china/MXiangHeHeiSCStd-Regular" },
  ja = { "/Game/Art/Font/Japan/HeiseiKakuGoStd-W3", "/Game/Art/Font/Japan/HeiseiKakuGoStd-W5" },
  ko = { "/Game/Art/Font/korean/KoPubDotumMedium", "/Game/Art/Font/korean/KoPubDotumBold" },
  ru = { "/Game/Art/Font/Cyrillic/TT_Supermolot_Condensed_Light", "/Game/Art/Font/Cyrillic/TT_Supermolot_Condensed_Regular" },
}
-- how far up a language's font draws its line, a share of its size, over the game's (Rajdhani's): the menu's copies
-- of the Chinese and Japanese faces put every line 0.6-0.8 of its size low (playtest screenshots: labels on a focused
-- row's bottom edge, key caps' text below the cap). Korean and Russian sit right. tune.menuTextUp overrides
M.TEXT_UP = { zh = 0.62, ja = 0.76 }
M.fontCode = {} -- a language font's address -> its language
-- the game's own key icons (80 x 80, the key in the middle of each)
M.ICONS = "/Game/Art/UI/Texture/Interaction/"
M.HINTS = {
  kb = { { { "PC/KeyIcon_KeyBoard_Q", "PC/KeyIcon_KeyBoard_E" }, "Tab", "Q E" },
    { { "PC/KeyIcon_KeyBoard_Comma", "PC/KeyIcon_KeyBoard_Period" }, "Adjust", { "<", ">" } },
    { { "PC/KeyIcon_KeyBoard_Enter" }, "Select", "ENTER" },
    { { "PC/KeyIcon_KeyBoard_R" }, "Reset Tab", "R" },
    { { "PC/KeyIcon_KeyBoard_F3" }, "Exit", "F3" } },
  xbox = { { { "XBOX/KeyIcon_XboxOne_Gamepad_LeftShoulder", "XBOX/KeyIcon_XboxOne_Gamepad_RightShoulder" }, "Tab", "LB RB" },
    { { "XBOX/KeyIcon_XboxOne_Gamepad_DPad_X" }, "Adjust", "D-PAD" },
    { { "XBOX/KeyIcon_XboxOne_Gamepad_FaceButton_Bottom" }, "Select", "A" },
    { { "XBOX/KeyIcon_XboxOne_Gamepad_FaceButton_Top" }, "Reset Tab", "Y" },
    { { "XBOX/KeyIcon_XboxOne_Gamepad_FaceButton_Right" }, "Exit", "B" } },
  playstation = { { { "DualSense/KeyIcon_DualSense_Gamepad_LeftShoulder", "DualSense/KeyIcon_DualSense_Gamepad_RightShoulder" }, "Tab", "L1 R1" },
    { { "DualSense/KeyIcon_DualSense_Gamepad_DPad_X" }, "Adjust", "D-PAD" },
    { { "DualSense/KeyIcon_DualSense_Gamepad_FaceButton_Bottom" }, "Select", "X" },
    { { "DualSense/KeyIcon_DualSense_Gamepad_FaceButton_Top" }, "Reset Tab", "TRI" },
    { { "DualSense/KeyIcon_DualSense_Gamepad_FaceButton_Right" }, "Exit", "O" } },
}
-- rows: a tab (section), a setting (bool, num with min/max/step, list of values with their names), or a button
M.ROWS = {
  { section = "Gore" },
  { key = "gore.enabled", label = "Cuts and Blood", kind = "bool", help = "Master switch for all cuts, stumps and blood, on Eve and on enemies. Off: deaths are plain ragdolls." },
  { key = "gore.death.limb", label = "Limb Cut Chance", kind = "num", min = 0, max = 100, step = 1, help = "Rolled when no blade was tracked, or Hit Decides left it aside, leaning to what is near the hit (Chances Follow the Hit). Weight against the other chances: the arm or leg nearest the hit comes off." },
  { key = "gore.death.head", label = "Beheading Chance", kind = "num", min = 0, max = 100, step = 1, help = "Rolled when no blade was tracked, or Hit Decides left it aside, leaning to what is near the hit (Chances Follow the Hit). Weight against the other chances: the head comes off." },
  { key = "gore.death.torso", label = "Waist Cut Chance", kind = "num", min = 0, max = 100, step = 1, help = "Rolled when no blade was tracked, or Hit Decides left it aside, leaning to what is near the hit (Chances Follow the Hit). Weight against the other chances: the body is cut in two at the waist, leaning a little at random." },
  { key = "gore.death.split", label = "Vertical Split Chance", kind = "num", min = 0, max = 100, step = 1, help = "Weight against the other chances: the body splits in two from head to hips. Like the others it is rolled when Hit Decides leaves the cut to chance (a tracked blade decides first); set only this one above 0 and every death splits." },
  { key = "gore.noSplits", label = "No Vertical Splits", kind = "bool", help = "Off by default. On: she is never split in half from head to hips, by any blow, chance or hit after her death. A blade down her length takes the limbs it crossed instead, and the split chance goes to the others." },
  -- (parked) { key = "gore.death.diagonal", label = "Diagonal Cut Chance", kind = "num", min = 0, max = 100, step = 1, help = "Rolled when no blade was tracked, or Hit Decides left it aside, leaning to what is near the hit (Chances Follow the Hit). Weight against the other chances: the body is cut from over one shoulder down to the other hip; the head and the other arm go one way, that arm and the legs the other." },
  { key = "gore.death.moreLimbs", label = "Extra Limb Chance", kind = "num", min = 0, max = 1, step = 0.05, help = "Chance a limb cut takes the next nearest limb too (0-1), and a third at the same chance again. At 0.35: 35% two or more limbs, 12% three. Rolled limb cuts only; a tracked blade cuts every limb it crosses." },
  { key = "gore.followUpCuts", label = "Follow-up Cuts", kind = "bool", help = "One swing cuts everything it went through: both arms and the body, say. Off: one cut a swing, the body when the blade went through it, else the limb it met first (Extra Limb Chance does nothing either). A laser trap still cuts along its beam." },
  { key = "gore.bladeFollow", label = "Hit Decides", kind = "num", min = 0, max = 1, step = 0.05, help = "Share of deaths with a tracked blade where the blade alone decides what is cut (0-1). The rest roll the chances above. At 1 most deaths are waist cuts or splits, since a blade mostly crosses her body." },
  -- (parked) { key = "gore.diagonal.enabled", label = "Diagonal Cuts", kind = "bool", help = "Cuts from over one shoulder down to the other hip: rolled by Diagonal Cut Chance, and from a tracked blade slanting across her body (20-60 degrees off her spine), which otherwise came out a waist cut or a split. Off: none." },
  { key = "gore.oddsNear.enabled", label = "Chances Follow the Hit", kind = "bool", help = "The chances above lean to what is near where the blow landed: a swing at her waist cuts the waist, a nearby arm or leg, or splits her if it came down her length, never her head; a blow at her neck mostly beheads. Set only one chance above 0 and every death still does that one, wherever it hit. Off: the chances as they are." },
  { key = "gore.oddsNear.floor", label = "   Far Part Chance", kind = "num", min = 0, max = 1, step = 0.05, help = "With Chances Follow the Hit: share of its chance a part far from the hit keeps (0-1). 0: never (a waist swing never beheads), 0.1: now and then, 1: as if off." },
  { key = "gore.afterHits.enabled", label = "Hits After Death", kind = "bool", help = "Enemy weapons swinging through Eve's dead body cut it again (a limb, the head or the body), up to 6 times a death. About a quarter leave only a wound." },
  { key = "gore.smash.enabled", label = "Blunt Smash (Experimental)", kind = "bool", help = "Off by default. A killing blow from a blunt weapon (a hammer, a fist, a stomp) smashes the arm, leg or head it hit: the part vanishes and the game's meat chunks burst out with blood, the stump stays. Blades still cut." },
  { key = "gore.smash.always", label = "   Smash Every Death", kind = "bool", help = "With Blunt Smash on: every death smashes a part, whatever hit her. To try the smash out." },
  { key = "gore.laserCut", label = "Laser Cuts Along the Beam", kind = "bool", help = "A laser trap death cuts Eve along the beam that killed her: every arm, leg, her body or her head the beam's plane goes through comes off. Off: laser deaths roll the cut chances like any death with no blade seen." },
  { key = "gore.bluntRagdoll", label = "Blunt Kills Only Ragdoll", kind = "bool", help = "Off by default. A killing blow from a blunt weapon (a hammer, a fist, a stomp) cuts nothing: Eve dies a plain ragdoll, and hits after it cut nothing either. Blades still cut. Goes before Blunt Smash." },
  { key = "gore.throw", label = "Cut Piece Force", kind = "num", min = 0, max = 800, step = 25, unit = " cm/s", help = "Speed a piece flies off with when it wasn't cut by the killing blow, e.g. a hit after death (0: it just drops). The killing blow's pieces fly with the blow (deathThrow in tune.lua)." },
  -- { section = "Stumps" },
  -- { key = "gore.tachyRelief", label = "Stump Detail", kind = "num", min = 0, max = 3, step = 0.25, help = "Depth of the flesh detail on stumps (0: smooth). New cuts." },
  -- { key = "gore.stubBone", label = "Spine Bone Thickness", kind = "num", min = 0.1, max = 0.6, step = 0.02, help = "Share of the cut's width (next cut)." },
  { section = "Death" },
  { key = "deathScreen", label = "Death Screen", kind = "list", values = { "game", "delay", "key" },
    names = { game = "Instant", delay = "Delayed", key = "On Press" },
    help = "When the death screen appears. Instant: as the game shows it. Delayed: after Death Screen Delay. On Press: only when you press Hold the Death (Shift+F4, or D-pad down + R1 held for a second, unless rebound), which also brings it up early or hides it again." },
  { key = "customizedRagdoll", label = "Customized Ragdoll (Redundant)", kind = "bool", help = "Off by default. For Customized Ragdoll (Nexus 3884) installed alongside: its death camera instead of the Free Camera, and the death screen up at once but invisible, its keys (F / R) working, no holding needed (Hold the Death, Shift+F4, shows it). This mod's ragdoll, cuts, struggle and face stay as they are; that mod's own ragdoll physics are kept off her." },
  { key = "hideHud", label = "Hide HUD on Death", kind = "bool", help = "Hides the HUD (HP bar, skills, minimap, notices) through a death, so the body lies on a clean screen. The death screen still comes up as Death Screen says. Off: the HUD stays up, as in the game." },
  { key = "reviveAt", label = "Death Screen Delay", kind = "num", min = 1, max = 60, step = 1, unit = " s", help = "Seconds into a death before the death screen (and the revive item screen) shows. Only used with Death Screen set to Delayed." },
  { key = "gore.voice.enabled", label = "Death Scream", kind = "bool", help = "Eve cries out, from her own voice recordings, the moment she dies. Off: only the game's own death voice." },
  { key = "gore.deathFace.enabled", label = "Death Expression", kind = "bool", help = "Holds a lifeless expression on her face for the whole death, her eyes closing. Off: the game's own face, which goes blank about a second in with her eyes open." },
  { key = "convulse.enabled", label = "Post-Death Movement", kind = "bool", help = "For a few seconds after she falls: winces, gasps, eye flutters and a last breath. Her body itself stays still unless convulse.body is turned on in tune.lua." },
  { key = "convulse.face", label = "   Facial Movement", kind = "bool", help = "The winces, gasps and eyelid flutters on her face. Off: her face stays still (the neck and the breathing can still play)." },
  { key = "convulse.voice.enabled", label = "   Breathing Sounds", kind = "bool", help = "Quiet breaths with her gasps and an occasional moan. Never once she is beheaded, and never over her death scream." },
  { key = "convulse.voice.volume", label = "   Breathing Volume", kind = "num", min = 0, max = 3, step = 0.1, help = "Volume of those breaths and moans (1: default, 0: silent)." },
  { key = "convulse.neck.enabled", label = "   Neck Movement", kind = "bool", help = "Her head strains to lift or turn, shakes with the effort, drops back, then jerks a few times. Not once she is beheaded." },
  { key = "deathMoves", label = "Death Struggle", kind = "bool", help = "On by default. After a ragdoll death with a limb cut off, or cut across the waist, she struggles on the floor over her last seconds: a hand on the stump or going out to it, trying to sit up or crawl, then dies (after a waist cut her upper body clutches the wound and crawls). Her arms also swing in her last movements. Off: her body lies still (her face and breathing still move with Post-Death Movement). Each move is logged (struggle: lines)." },
  { key = "struggle.strength", label = "   Struggle Strength", kind = "num", min = 0.25, max = 3, step = 0.25, unit = "x", help = "With Death Struggle on: how hard she moves in it (1: default)." },
  { key = "struggle.length", label = "   Struggle Length", kind = "num", min = 0.5, max = 3, step = 0.25, unit = "x", help = "With Death Struggle on: how long it lasts before she dies (1: 5-8 s, 2: twice that)." },
  { key = "struggle.rise.alone", label = "   Sit Up Uncut", kind = "num", min = 0, max = 1, step = 0.05, pct = true, help = "With Death Struggle on: the share of ragdoll deaths with nothing cut off in which she still tries to sit up or prop herself up before dying (0: those lie still)." },
  { key = "convulse.armSwing.enabled", label = "   Arm Swings", kind = "bool", help = "With Death Struggle on: her arms lift and drop, or make a crawl's stroke, now and then in her last movements (also beheaded or split). Off: only the struggle moves them." },
  { key = "active.animated", label = "Animated Death Falls", kind = "bool", help = "Standing and light-hit deaths play Eve's own fall animation and hold its end pose; cut pieces still fall by physics. Heavy hits, explosions, mid-air deaths and splits are ragdolls, and so is every death with Cuts and Blood off. Off: every death is a full ragdoll." },
  { key = "gore.headRagdoll", label = "   Ragdoll When Beheaded", kind = "bool", help = "A beheading during an animated fall always switches her to a full ragdoll. Off: the chance below decides." },
  { key = "gore.headRagdollChance", label = "   Beheading Ragdoll Chance", kind = "num", min = 0, max = 1, step = 0.1, help = "With Ragdoll When Beheaded off: the chance a beheading during an animated fall ragdolls her. The rest play the fall on headless." },
  { key = "gore.legRagdoll", label = "   Ragdoll When Leg Cut", kind = "bool", help = "A leg cut during an animated fall switches her to a full ragdoll. Off: she plays the fall to the end without the leg." },
  { key = "gore.armRagdoll", label = "   Ragdoll When Arm Cut", kind = "bool", help = "An arm cut during an animated fall switches her to a full ragdoll. Off: she plays the fall on and the arm drops away." },
  { key = "gore.armRagdollChance", label = "   Arm Cut Ragdoll Chance", kind = "num", min = 0, max = 1, step = 0.1, help = "With Ragdoll When Arm Cut off: the chance an arm cut during an animated fall ragdolls her anyway (each arm rolled, so both off is likelier). 0: she always plays the fall on." },
  { key = "gore.torsoLegs.enabled", label = "   Waist Cut Leg Animation", kind = "bool", help = "A waist cut during an animated death fall: the legs and hips keep playing the fall while the upper body flies off as a ragdoll. Off: the whole body goes ragdoll." },
  { key = "gore.torsoLegs.rolled", label = "   Leg Animation Chance", kind = "num", min = 0, max = 1, step = 0.05, help = "Chance of the leg animation when no blade was tracked (0-1). A level swing uses 0.75 and a slanted one 0.35 (tune.lua)." },
  { key = "active.fallRagdoll", label = "Fall Damage Ragdoll", kind = "bool", help = "A death from fall damage is a ragdoll. Off: a drop that kills her once she has landed plays her animated fall (with Animated Death Falls on), as a stand death." },
  { key = "active.push", label = "Death Push", kind = "num", min = 0, max = 4, step = 0.25, unit = "x", help = "How hard the killing blow throws Eve's body, on top of the game's own throw (1: default, 0: the game's alone, 2: twice the default)." },
  { key = "active.stiffness", label = "Ragdoll Stiffness", kind = "num", min = 0, max = 3, step = 0.25, help = "Muscle tone in her ragdoll as she falls. 0: limp from the start, 1: default (firm, going limp as she lands), 2-3: she holds her shape longer." },
  { key = "active.neutral.enabled", label = "Relaxed Pose In Flight", kind = "bool", help = "Thrown by a hard hit, her joints are pulled towards a relaxed, curled pose (knees and elbows bent, arms forward) until she lands, instead of her limbs flying out straight." },
  { key = "active.jiggle.enabled", label = "Jiggle After Death (Experimental)", kind = "bool", help = "On by default, being tested. In her ragdoll her breasts sway and bounce on a soft spring with her falls and landings. Off: they stay locked to her chest, as before (loose, they used to shake her on the floor)." },
  { section = "Enemies" },
  { key = "enemies.enabled", label = "Enemy Gore", kind = "bool", help = "Cuts and blood on humanoid enemies killed within 25 m of Eve." },
  { key = "enemies.afterDeath.enabled", label = "Attacks After Death (Experimental)", kind = "bool", help = "Off by default, being tested. After Eve dies, the enemies around her keep at her body for 10 s: those within 4.5 m play their own attacks at it, and their weapons cut it through Hits After Death." },
  { key = "enemies.cutChance", label = "   Cut Chance", kind = "num", min = 0, max = 1, step = 0.05, help = "Chance a kill cuts something off (0-1): along your swing when you swung, else a limb, the head or a waist cut at random." },
  { key = "enemies.pushScale", label = "Death Throw", kind = "num", min = 0, max = 4, step = 0.25, unit = "x", help = "Scales the game's own throw of a dying enemy (1: as the game, 0: it drops on the spot, 2: twice as far). Works with Enemy Gore off too." },
  { key = "enemies.push", label = "Extra Death Push", kind = "num", min = 0, max = 1000, step = 50, unit = " cm/s", help = "Speed added to every enemy death along the blow, slightly upward, on top of Death Throw (0: none). Works with Enemy Gore off too." },
  -- (Blood and Dirt: parked, off and hidden till blood on her outfits can look like the game's own; tune.stains)
  -- { section = "Blood and Dirt" },
  -- { key = "stains.enabled", label = "Blood and Dirt (Experimental)", kind = "bool", help = "The game's own blood layer on Eve's skin, cut before release, switched back on. Hits that take HP bloody her, enemies hit near her splash her, falls and knockdowns dirty her, and her death soaks her. Swimming washes it off; a camp rest or her next life cleans her. Off: none, her materials as the game has them." },
  -- { key = "stains.scale", label = "   Blood Amount", kind = "num", min = 0.25, max = 3, step = 0.25, unit = "x", help = "With Blood and Dirt on: how much blood every hit, splash and death puts on her (1: default, 2: twice as much)." },
  -- { key = "stains.wounds.enabled", label = "   Wounds Where Hit", kind = "bool", help = "With Blood and Dirt on: a hit she lives through leaves a bleeding wound on her skin where it landed, drawn in the skin's own blood layer (not a decal), with drops of blood round it. A hit on her outfit soaks the cloth there with blood instead. Wounds pale in water and heal at a camp rest." },
  -- { key = "stains.wounds.size", label = "   Wound Size", kind = "num", min = 2, max = 15, step = 1, unit = " cm", help = "With Wounds Where Hit on: the size of a wound's core (harder hits leave bigger ones). New wounds." },
  -- { key = "stains.splash.enabled", label = "   Enemy Blood Splatter", kind = "bool", help = "With Blood and Dirt on: enemies hit or cut near her splash her with their blood, more the closer they are." },
  -- { key = "stains.splash.range", label = "   Splatter Range", kind = "num", min = 100, max = 800, step = 50, unit = " cm", help = "With Enemy Blood Splatter on: how near an enemy has to be for its blood to reach her." },
  -- { key = "stains.dirt.enabled", label = "   Dirt", kind = "bool", help = "With Blood and Dirt on: hard landings and knockdowns dirty her, and her body gets dirtier the longer it lies dead." },
  -- { key = "stains.cloth.enabled", label = "   Stained Clothing", kind = "bool", help = "With Blood and Dirt on: blood soaks into her outfit where it lands on it (hits, drops), painted into the cloth's own colour, and dirt darkens and greys it. Outfits whose materials lack a colour texture or the game's brightness settings stay as they are." },
  -- { key = "stains.sound.enabled", label = "   Wound Sound", kind = "bool", help = "With Blood and Dirt on: a wet blood sound (the game's own) on each hit that leaves a wound, over the hit's usual sound." },
  -- { key = "stains.spatter.enabled", label = "   Blood Drops", kind = "bool", help = "With Blood and Dirt on: blood lands on her as drops, on her skin and her outfit: round her wounds, from enemies hit near her (on the side facing them), at her death and from Add Blood." },
  -- { key = "stains.wash.enabled", label = "   Water Washes It Off", kind = "bool", help = "With Blood and Dirt on: swimming washes the blood and dirt off her (a few seconds); wounds stay, paler." },
  -- { key = "stains.rest", label = "   Camp Rest Cleans Her", kind = "bool", help = "With Blood and Dirt on: resting at a camp cleans her and heals her wounds. Her next life always starts clean." },
  -- { key = "stains.fade", label = "   Fades By Itself", kind = "num", min = 0, max = 30, step = 1, unit = " min", help = "With Blood and Dirt on: minutes for blood and dirt to fade by themselves (0: never, it stays till washed or rested off). Wounds don't fade." },
  -- { button = "call", call = "stains.test_blood", label = "Add Blood", help = "Puts a quarter more blood on her and a dozen drops over her skin and outfit, to see it." },
  -- { button = "call", call = "stains.test_wound", label = "Add Wound", help = "A wound on her arm, leg or body at random, on the side facing the camera, to see it." },
  -- { button = "call", call = "stains.test_dirt", label = "Add Dirt", help = "Puts a quarter more dirt on her, to see it." },
  -- { button = "call", call = "stains.clean", label = "Clean Her", help = "Takes all the blood, dirt and wounds off her at once." },
  { section = "Gameplay" },
  { key = "holdDown", label = "Stay Down After Knockdown", kind = "bool", help = "When knocked down, Eve stays on the ground until you dodge or jump. Off: she gets up by herself after a second, as in the game." },
  { key = "gore.lowArm.enabled", label = "Lose Arm at Low HP", kind = "bool", help = "A hit that leaves Eve under Arm Comes Off Below of her HP (25% by default) cuts an arm off (Which Arm), and she fights on without it. It dissolves back in when she rests at a camp, or comes back at her next life." },
  { key = "gore.lowArm.below", label = "   Arm Comes Off Below", kind = "num", min = 0.01, max = 0.9, step = 0.01, pct = true, help = "With Lose Arm at Low HP: the share of her HP a hit has to leave her under for the arm to come off (25%: a quarter). Grows Back With HP waits for at least 1% more than this." },
  { key = "gore.lowArm.side", label = "   Which Arm", kind = "list", values = { "hit", "left", "right", "either" },
    names = { hit = "Side Hit", left = "Left", right = "Right", either = "Either" },
    help = "With Lose Arm at Low HP: the arm that comes off. Side Hit (the default): the one on the side of her the blow landed on (one at random when it landed on her middle). Left: no heals or gun without it. Right: no sword without it. Either: one at random each time." },
  { key = "gore.lowArm.noHealGun", label = "   No Heals or Gun Without It", kind = "bool", help = "With Lose Arm at Low HP: while her left arm is off, Eve can't use heal items or shoot the gun, both done with her left hand. The game's own item blocks, lifted when the arm is back." },
  { key = "gore.lowArm.noSword", label = "   No Sword Without It", kind = "bool", help = "With Lose Arm at Low HP: while her right arm is off, Eve can't use her sword. The game's own swordless stance (as where her sword is taken from her): it is folded away; dodges, the gun and heals still work, but there is no lock-on or drone scan. Lifted when the arm is back." },
  { key = "gore.lowArm.notice", label = "   'Cannot Use' Notice", kind = "bool", help = "With No Heals or Gun Without It: her aim or heal key pressed while the arm is off shows the game's own \"Cannot use right now.\" notice, with its sound." },
  { key = "gore.lowArm.healBack", label = "   Grows Back With HP", kind = "bool", help = "Off by default. With Lose Arm at Low HP: the arm also grows back once her HP is back up to Grows Back At, however she healed (gear that restores HP on kills or over time; heal items too with No Heals or Gun off). Off: only a camp rest or her next life bring it back." },
  { key = "gore.lowArm.healAt", label = "   Grows Back At", kind = "num", min = 0.3, max = 1, step = 0.01, pct = true, help = "With Grows Back With HP: the share of her HP bar at which the arm grows back (90% by default)." },
  { key = "gore.lowArm.effect", label = "Regrow Effect", kind = "bool", help = "On by default. A part cut off her alive (Lose Arm at Low HP's arm, F9's) dissolves back in with a glow when it comes back (a camp rest, Grows Back With HP). Off: it is back at once, with no effect." },
  { section = "Sandbox" },
  { key = "bosses.enabled", label = "Sandbox Bosses (Experimental)", kind = "bool", help = "Off by default. Spawn Tachy, Raven, Scarlet or a Royal Guard Sister in front of Eve, anywhere, and kill them like any enemy: no death cutscene, no phase changes to wait out. They are cut as enemies are, then struggle on the floor and wear a dead face. While one you spawned is up, that boss is mortal everywhere, a story fight with it too." },
  { key = "bosses.pick", label = "   Boss", kind = "list", values = { "tachy", "raven", "scarlet", "royalguard" },
    names = { tachy = "Tachy", raven = "Raven", scarlet = "Scarlet (DLC)", royalguard = "Royal Guard Sister" }, help = "With Sandbox Bosses on: the one Spawn Boss brings in." },
  { key = "bosses.hpScale", label = "   Boss HP", kind = "num", min = 0.05, max = 1, step = 0.05, pct = true, help = "With Sandbox Bosses on: their HP and shield, as a share of the game's (25%: a quarter). Takes effect for the next boss once none you spawned is up." },
  { key = "bosses.passive", label = "   Passive Bosses", kind = "bool", help = "With Sandbox Bosses on: a boss you spawned stands where it is and never attacks, so you can cut it at will. Off again, it fights." },
  { key = "bosses.struggle", label = "   Boss Struggle", kind = "bool", help = "With Sandbox Bosses and Death Struggle on: a boss with a limb cut off struggles on the floor before it dies, as Eve does." },
  { key = "bosses.face", label = "   Boss Death Expression", kind = "bool", help = "With Sandbox Bosses and Death Expression on: a dead face held on the boss's face." },
  { button = "call", call = "bosses.spawn_pick", label = "Spawn Boss", help = "With Sandbox Bosses on: the boss picked above, 7 m in front of Eve, facing her. It fights at once." },
  { button = "call", call = "bosses.remove", label = "Remove Spawned", help = "Every boss and enemy spawned here goes, corpses too." },
  { section = "Camera" },
  { key = "cameraStill", label = "Free Camera", kind = "bool", help = "At a death the camera stops riding her pawn and holds where it is until she gets up. Turn it with the mouse or right stick; fly it with WASD, Q/E or the left stick and triggers (Shift: faster); zoom with the mouse wheel or the D-pad (up in, down out), right up to her." },
  { key = "cameraMouse", label = "   Mouse Sensitivity", kind = "num", min = 0.5, max = 10, step = 0.5, help = "How fast the mouse turns the death camera." },
  { key = "cameraStick", label = "   Stick Sensitivity", kind = "num", min = 30, max = 400, step = 10, help = "How fast the right stick turns the death camera, in degrees a second at full tilt." },
  { key = "cameraBody", label = "   Follow Her Body", kind = "bool", help = "On by default. The death camera stays locked on her body as it falls and tumbles, up and down too, while you turn and zoom round it. It stops following once you fly it. Off: it only slides after her on the level (Follow Strength)." },
  { key = "cameraFlyAfter", label = "   Fly After", kind = "num", min = 0, max = 10, step = 0.5, unit = " s", help = "Seconds into her death before WASD, Q/E or the left stick and triggers fly the camera. Till then it stays locked on her body while you turn and zoom round her; the first fly press after that lets go of her and flies it." },
  { key = "cameraBodyBone", label = "   Follow Point", kind = "list", values = { "upper", "pelvis" },
    names = { upper = "Upper Body", pelvis = "Pelvis" }, help = "Which part of her the death camera follows and turns round: her upper body (chest) or her pelvis." },
  { key = "cameraTrack", label = "   Follow Strength", kind = "num", min = 0, max = 10, step = 0.5, help = "With Follow Her Body off: how quickly the death camera slides sideways after her body, never up or down (0: it stays put). It stops following once you fly it." },
  { key = "cameraMove", label = "   Fly Speed", kind = "num", min = 100, max = 2000, step = 50, unit = " cm/s", help = "How fast the death camera flies (Shift: three times that). It stays within 15 m of where it started." },
  { section = "Mod" },
  { key = "language", label = "Language", kind = "list", values = M.LANGS, names = M.LANG_NAMES, help = "The language of this menu: English, Chinese (Simplified), Japanese, Korean or Russian. The rest of the mod (settings.lua, the log, the README) stays in English." },
  { key = "menuPadIcons", label = "Controller Icons", kind = "list", values = { "xbox", "playstation" },
    names = { xbox = "Xbox", playstation = "PlayStation" }, help = "Which controller's buttons this menu shows when you use a controller." },
  { key = "fewerGC", label = "Fewer GC Hitches", kind = "bool", help = "Stops the engine forcing a garbage collection each time it unloads part of the map, one of the causes of the game's own half-second freezes. Its regular pass once a minute still runs. Off: the game's own behaviour. Takes effect within a minute." },
  { key = "smoothAnim", label = "Smooth Character Animation", kind = "bool", help = "Animates every character every frame. The engine updates distant or small characters less often, which can look choppy, most of all when they run. Costs some CPU with many on screen." },
  { key = "verboseLog", label = "Detailed Log", kind = "bool", help = "Writes every per-frame detail to stellarbladegore.log, for bug reports. The log grows much faster; leave it off otherwise." },
  { key = "dev", label = "Developer Keys", kind = "bool", help = "Test keys (F6 struggle test, F7 ragdoll, F9-F11 cuts), and the enemy spawner. See the README." },
  { button = "reset", label = "Reset to settings.lua", help = "Throws away every change made in this menu (deletes menu.lua) and goes back to settings.lua's values." },
  { button = "close", label = "Close", help = "Closes the menu. Changes are already applied, and are saved to menu.lua, which wins over settings.lua." },
}
M.VISIBLE = 12 -- rows on screen at once (a longer tab scrolls)
M.KEYS = {
  -- (the arrow keys come from keys.lua's own binds, ctx.keys.nav: the engine never saw them down)
  up = { "Gamepad_DPad_Up", "Gamepad_LeftStick_Up" },
  down = { "Gamepad_DPad_Down", "Gamepad_LeftStick_Down" },
  -- (< and > on Comma and Period; the arrow keys come from keys.lua's own binds, ctx.keys.nav: the engine never saw
  -- them down)
  left = { "Comma", "Gamepad_DPad_Left", "Gamepad_LeftStick_Left" },
  right = { "Period", "Gamepad_DPad_Right", "Gamepad_LeftStick_Right" },
  ok = { "Enter", "Gamepad_FaceButton_Bottom" },
  back = { "BackSpace", "Gamepad_FaceButton_Right" },
  reset = { "R", "Gamepad_FaceButton_Top" },
  tabl = { "Q", "Gamepad_LeftShoulder" },
  tabr = { "E", "Gamepad_RightShoulder" },
}
-- every controller button a combo can take, and its name on each controller
M.PAD = { "Gamepad_FaceButton_Bottom", "Gamepad_FaceButton_Right", "Gamepad_FaceButton_Left", "Gamepad_FaceButton_Top",
  "Gamepad_LeftShoulder", "Gamepad_RightShoulder", "Gamepad_LeftTrigger", "Gamepad_RightTrigger",
  "Gamepad_LeftThumbstick", "Gamepad_RightThumbstick", "Gamepad_DPad_Up", "Gamepad_DPad_Down", "Gamepad_DPad_Left",
  "Gamepad_DPad_Right", "Gamepad_Special_Left", "Gamepad_Special_Right" }
M.PAD_NAMES = {
  xbox = { "A", "B", "X", "Y", "LB", "RB", "LT", "RT", "LS", "RS", "Up", "Down", "Left", "Right", "View", "Menu" },
  playstation = { "Cross", "Circle", "Square", "Triangle", "L1", "R1", "L2", "R2", "L3", "R3", "Up", "Down", "Left",
    "Right", "Create", "Options" },
}
-- the menu in the language picked: its strings (nil for English), loaded once
M.lang = {}
local function lang()
  local code = ctx.tune.language
  if not M.FACES[code] then return nil, "en" end
  if M.lang[code] == nil then
    local ok, t = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/lang_" .. code .. ".lua")
    if not ok or type(t) ~= "table" then log("menu: lang_" .. code .. ".lua not read: " .. tostring(t)); t = false end
    M.lang[code] = t
  end
  return M.lang[code] or nil, code
end
local function row_id(r) return r.key or r.call or (r.button and ("button." .. r.button)) end
local function row_tr(r) local L = lang(); return L and L.rows and L.rows[row_id(r)] end
-- (a sub-setting keeps its indent: the rows' look of it)
local function label_of(r)
  local t = row_tr(r)
  if not (t and t[1]) then return r.label end
  return (r.label:match("^%s*") or "") .. t[1]
end
local function help_of(r)
  local t = row_tr(r)
  if not (t and t[2]) then return r.help end
  local L = lang()
  if r.kind == "key" and L.ui and L.ui.keySuffix then return t[2] .. " " .. L.ui.keySuffix end
  return t[2]
end
local function ui_text(s) local L = lang(); return L and L.ui and L.ui[s] or s end
local function tab_name(s) local L = lang(); return L and L.tabs and L.tabs[s] or s end
local function pad_show(combo)
  if type(combo) ~= "table" or #combo == 0 then return ui_text("None") end
  local names = M.PAD_NAMES[ctx.tune.menuPadIcons == "xbox" and "xbox" or "playstation"]
  local out = {}
  for i, k in ipairs(combo) do
    local n = k
    for j, p in ipairs(M.PAD) do if p == k then n = names[j] end end
    out[i] = n
  end
  return table.concat(out, " + ")
end
local function same_combo(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
M.state = { open = false, sel = 2, top = 1, ui = nil, held = {}, changed = {}, toggled = 0 }

function M.init(c)
  ctx, log, try, valid = c, c.log, c.try, c.valid
  -- the Keys tab (keys.lua's actions), before Mod
  if ctx.keys and not M.keysAdded then
    M.keysAdded = true
    local at = #M.ROWS + 1
    for i, r in ipairs(M.ROWS) do if r.section == "Mod" then at = i; break end end
    local rows = { { section = "Keys" } }
    for _, a in ipairs(ctx.keys.ACTIONS) do
      rows[#rows + 1] = { key = "keys." .. a.id, id = a.id, label = a.label, kind = "key", dev = a.dev,
        help = a.help .. " Enter, then press the new key (Ctrl, Shift and Alt can go with it); Backspace cancels. A key another action had is swapped with this one's. Keyboard keys only: changed from the keyboard." }
    end
    -- the controller's combos: A, then hold the new buttons together and let go
    rows[#rows + 1] = { key = "menuPad", id = "menuPad", label = "Menu (Controller)", kind = "pad", min = 2, max = 3,
      help = "Opens and closes this menu on the controller, all held together. A, then hold 2 or 3 buttons together and let go; B alone cancels." }
    rows[#rows + 1] = { key = "holdPad", id = "holdPad", label = "Death Hold (Controller)", kind = "pad", min = 2, max = 2,
      help = "Shift+F4 on the controller: both held for a second in a death show the death screen or hide it again. A, then hold 2 buttons together and let go; B alone cancels." }
    for k, r in ipairs(rows) do table.insert(M.ROWS, at + k - 1, r) end
    M.TABS = nil
  end
  M.ALL = M.ALL or M.ROWS
  M.refresh()
  M.prune()
end

-- a setting by its dotted path in the live tune table, and set
local function get_in(t, path)
  for part in path:gmatch("[^.]+") do
    if type(t) ~= "table" then return nil end
    t = t[tonumber(part) or part]
  end
  return t
end
local function get(path)
  local t = ctx.tune
  for part in path:gmatch("[^.]+") do
    if type(t) ~= "table" then return nil end
    t = t[tonumber(part) or part]
  end
  return t
end
local function set(path, v)
  local t, last = ctx.tune, nil
  local parts = {}
  for part in path:gmatch("[^.]+") do parts[#parts + 1] = tonumber(part) or part end
  for i = 1, #parts - 1 do
    if type(t[parts[i]]) ~= "table" then t[parts[i]] = {} end
    t = t[parts[i]]
  end
  last = parts[#parts]
  t[last] = v
end
M.get = get

-- the rows shown: the test keys' only with Developer Keys on (they do nothing without it). M.ALL holds every row;
-- the selection stays on its row
function M.refresh()
  local s, cur, first = M.state, M.ROWS[M.state.sel], M.ROWS[M.state.top]
  local dev = get("dev") == true
  local rows = {}
  for _, r in ipairs(M.ALL or M.ROWS) do if not r.dev or dev then rows[#rows + 1] = r end end
  M.ROWS, M.TABS = rows, nil
  -- (the first row shown too: kept at its old index, Developer Keys turned off scrolled the Mod tab past its own rows
  -- and showed only its last three, playtest)
  local top = nil
  for i, r in ipairs(rows) do
    if r == cur then s.sel = i end
    if r == first then top = i end
  end
  if s.sel > #rows then s.sel = 2 end
  s.top = math.min(top or s.sel, s.sel)
end

-- menu.lua: { ["path"] = value, ... } read over the settings (main.lua's load_tune), written here
function M.overlay(t)
  local ok, m = pcall(dofile, M.PATH)
  if not ok or type(m) ~= "table" then return 0 end
  local n = 0
  for path, v in pairs(m) do
    if type(path) == "string" then
      local parts, x = {}, t
      for part in path:gmatch("[^.]+") do parts[#parts + 1] = tonumber(part) or part end
      for i = 1, #parts - 1 do
        if type(x[parts[i]]) ~= "table" then x[parts[i]] = {} end
        x = x[parts[i]]
      end
      x[parts[#parts]] = v
      n = n + 1
    end
  end
  return n
end
local write_menu
local function save()
  local saved = {}
  local ok, m = pcall(dofile, M.PATH)
  if ok and type(m) == "table" then for k, v in pairs(m) do saved[k] = v end end
  for k in pairs(M.state.changed) do saved[k] = get(k) end
  -- (a value back at settings.lua's, a tab reset, is dropped from menu.lua)
  local base = ctx.base_tune and ctx.base_tune()
  if base then for k in pairs(M.state.changed) do if same_combo(get_in(base, k), saved[k]) then saved[k] = nil end end end
  return write_menu(saved)
end
-- menu.lua written from { path = value } (nothing to write: left as it is)
function write_menu(saved)
  local keys = {}
  for k in pairs(saved) do keys[#keys + 1] = k end
  if #keys == 0 then return true end
  table.sort(keys)
  local f = io.open(M.PATH, "w")
  if not f then log("menu: can't write " .. M.PATH); return false end
  f:write("-- Settings changed in the in-game menu (F3). They win over settings.lua; delete this file (or the menu's\n")
  f:write("-- \"Reset to settings.lua\") to go back to it.\nreturn {\n")
  for _, k in ipairs(keys) do
    local v = saved[k]
    if type(v) == "table" then
      -- (a controller combo: its button names)
      local q = {}
      for i, x in ipairs(v) do q[i] = string.format("%q", tostring(x)) end
      f:write(string.format("  [%q] = { %s },\n", k, table.concat(q, ", ")))
    else
      f:write(string.format("  [%q] = %s,\n", k, type(v) == "string" and string.format("%q", v) or tostring(v)))
    end
  end
  f:write("}\n")
  f:close()
  return true
end
-- a change in menu.lua whose row the menu no longer has (taken out, parked) is dropped from it, the settings read
-- again: it went on winning over settings.lua with no row to see or turn it back (Attacks While Down, taken out of
-- the menu once switched off in it, kept enemies waiting with settings.lua's attackDown true; playtest)
function M.prune()
  local ok, m = pcall(dofile, M.PATH)
  if not ok or type(m) ~= "table" then return end
  local known = {}
  for _, r in ipairs(M.ALL or M.ROWS) do if r.key then known[r.key] = true end end
  local kept, gone = {}, {}
  for k, v in pairs(m) do
    if type(k) == "string" and (known[k] or k:find("^keys%.")) then kept[k] = v else gone[#gone + 1] = tostring(k) end
  end
  if #gone == 0 then return end
  table.sort(gone)
  if next(kept) then
    if not write_menu(kept) then return end
  else
    os.remove(M.PATH)
  end
  log("menu: dropped from menu.lua, no longer in the menu: " .. table.concat(gone, " ") .. " (settings.lua's values apply)")
  if ctx.reload_tune then ctx.reload_tune() end
end

local function value_text(row)
  if row.kind == "key" then
    if M.state.capture and M.state.capture.id == row.id then return ui_text("Press a key...") end
    local k = ctx.keys.show(ctx.keys.binding(row.id))
    return k == "None" and ui_text(k) or k
  end
  if row.kind == "pad" then
    local c = M.state.capture
    if c and c.id == row.id then return #c.combo > 0 and (pad_show(c.combo) .. "...") or ui_text("Hold the buttons...") end
    return pad_show(get(row.key))
  end
  local v = get(row.key)
  if row.kind == "bool" then return ui_text(v and "On" or "Off") end
  if row.kind == "list" then
    local t = row.key ~= "language" and row_tr(row)
    return (t and t.names and t.names[v]) or (row.names and row.names[v]) or tostring(v)
  end
  if type(v) ~= "number" then return tostring(v) end
  -- (a share of her HP, 0-1, shown as a percent)
  if row.pct then return string.format("%d%%", math.floor(v * 100 + 0.5)) end
  local s = row.step < 1 and string.format("%.2f", v):gsub("0$", "") or string.format("%d", math.floor(v + 0.5))
  return s .. (row.unit or "")
end

local function selectable(i) local r = M.ROWS[i]; return r and not r.section end
-- the tabs: { name, first, last } (row indices), one per section
local function tabs()
  if M.TABS then return M.TABS end
  local t = {}
  for i, r in ipairs(M.ROWS) do
    if r.section then t[#t + 1] = { name = r.section, first = i + 1, last = i }
    elseif t[#t] then t[#t].last = i end
  end
  M.TABS = t
  return t
end
local function tab_of(i)
  local T = tabs()
  for k, t in ipairs(T) do if i >= t.first and i <= t.last then return k, t end end
  return 1, T[1]
end

-- a string on a TextBlock. UE4SS makes every FText from Lua (FText(), a UFunction's FText return too) with the
-- engine's FText constructor, which its scan doesn't find in this game without UE4SS_Signatures/FText_Constructor.lua:
-- it called address 0 and the game crashed at the menu's first text (0.4.1 report, then reproduced). That file (UE4SS
-- packs ship it off, as dFText_Constructor.lua) has UE4SS call the constructor as the game starts, and with the Steam
-- overlay on the game closes at launch (the reporter's, and ours on 2026-10-25). So sbslice.dll sets the text ("T":
-- the FText made there, only once the menu is up, handed to SetText), and UE4SS's FText is only the way left when the
-- DLL can't (and its constructor was found: "Failed to find FText::FText" isn't in UE4SS.log, made anew each start)
local ftextMissing
local function ftext_missing()
  if ftextMissing ~= nil then return ftextMissing end
  ftextMissing = false
  local f = io.open("ue4ss/UE4SS.log", "r")
  if not f then return false end
  for line in f:lines() do
    if line:find("Failed to find FText::FText", 1, true) then ftextMissing = true; break end
  end
  f:close()
  return ftextMissing
end
-- the DLL's text: asked once ("T?"), with SetText's address. M.textBy: "dll", "ue4ss" or nil (neither: no menu)
local function text_by()
  if M.textBy ~= nil then return M.textBy or nil end
  local g = ctx.gore
  -- (sbslice not up yet: asked again at the next open)
  if not (g and g.native_ready and g.native_ready() and g.command) then return not ftext_missing() and "ue4ss" or nil end
  local r = g.command("T?")
  local fn = StaticFindObject("/Script/UMG.TextBlock:SetText")
  M.setTextFn = valid(fn) and try(function() return fn:GetAddress() end) or nil
  if r == "ok" and M.setTextFn then M.textBy = "dll"
  elseif not ftext_missing() then M.textBy = "ue4ss"
  else M.textBy = false end
  log(string.format("menu: its text by %s (sbslice: %s)", M.textBy or "nothing", tostring(r)))
  return M.textBy or nil
end
-- (to the DLL past ASCII as \1 and 4 hex digits, decoded there: what UE4SS makes of UTF-8 on its way to an FString
-- isn't ours to count on)
local function escaped(s)
  if not s:find("[\128-\255]") then return s end
  local ok, r = pcall(function()
    return (s:gsub(utf8.charpattern, function(c)
      local cp = utf8.codepoint(c)
      if cp < 128 then return c end
      return cp > 0xffff and "?" or string.format("\1%04x", cp)
    end))
  end)
  return ok and r or s
end
local function set_text(tb, s)
  s = tostring(s or "")
  if M.textBy == "dll" then
    s = escaped(s)
    local a = try(function() return tb:GetAddress() end)
    if a then ctx.gore.fire(string.format("T%x,%x;%s", a, M.setTextFn, s)) end
  else
    tb:SetText(FText(s))
  end
end

-- a language's copy of Mideum (w 1) or Bold (w 2), base the game's: its face found in memory (Mideum and Bold hold
-- them all), the copy made in the transient package with base its template, rooted, its own typeface's fonts given
-- that face and the sub-fonts dropped. Nil (base used) when sbslice.dll can't root it or any step doesn't take
M.fonts = {}
local function lang_font_make(code, w, base)
  local name = "SBGore_Font_" .. code .. w
  if M.fonts[name] ~= nil then return M.fonts[name] or nil end
  M.fonts[name] = false
  local g = ctx.gore
  local function no(why) log("menu: no " .. name .. ": " .. why); return nil end
  if not valid(base) then return no("the game's font isn't loaded") end
  if not (g and g.native_ready and g.native_ready() and g.command) then return no("sbslice.dll isn't up") end
  local path = M.FACES[code][w]
  local face = StaticFindObject(path .. "." .. path:match("[^/]+$"))
  if not valid(face) then return no(path .. " isn't loaded") end
  local f = try(function() return StaticFindObject("/Engine/Transient." .. name) end)
  if not valid(f) then
    -- (the transient package: the game engine's outer; StaticFindObject("/Engine/Transient") throws "Name wasn't
    -- long" in UE4SS, and the menu fell back to the game's fonts, a Simplified Chinese menu missing every character
    -- the English game's sub-fonts don't have, playtest)
    local eng = FindFirstOf("GameEngine")
    local pkg = valid(eng) and try(function() return eng:GetOuter() end)
    if not valid(pkg) then return no("no transient package") end
    f = try(function() return StaticConstructObject(base:GetClass(), pkg, FName(name), 0, 0, false, false, base) end)
    if not valid(f) then return no("not made") end
  end
  local r = g.command(string.format("o%x", f:GetAddress()))
  if not r:match("^ok") then return no("not rooted: " .. r) end
  local ok, err = pcall(function()
    local cf = f.CompositeFont
    local list = cf.DefaultTypeface.Fonts
    local n = list:GetArrayNum()
    if n == 0 then error("the copy has no fonts (its template not copied)") end
    for i = 1, n do list[i].Font.FontFaceAsset = face end
    local got = list[1].Font.FontFaceAsset
    if not (valid(got) and got:GetAddress() == face:GetAddress()) then error("its face didn't take") end
    cf.SubTypefaces:Empty()
  end)
  if not ok then return no(tostring(err)) end
  log("menu: " .. name .. " made (" .. path:match("[^/]+$") .. ")")
  M.fonts[name] = f
  M.fontCode[f:GetAddress()] = code
  return f
end
-- (a step that throws leaves the game's font, never the menu unmade: the language row's change closed the menu,
-- playtest)
local function lang_font(code, w, base)
  local ok, f = pcall(lang_font_make, code, w, base)
  if ok then return f end
  log(string.format("menu: no SBGore_Font_%s%d: %s", code, w, tostring(f)))
  return nil
end

-- ---- the widgets ----
local function build()
  -- each stage logged first (the log is flushed a line at a time): a crash in the game's code here leaves no Lua
  -- error, only the last stage reached
  local function stage(what) log("menu: making it: " .. what) end
  stage("game instance")
  local function cls(p)
    local c = StaticFindObject(p)
    if not valid(c) then error("no class " .. p) end
    return c
  end
  local gi = FindFirstOf("GameInstance")
  if not valid(gi) then error("no game instance") end
  -- layout units: 1920 x 1080 fitted into the viewport (by its height on a wider screen: scaled by the width alone,
  -- a 21:9 screen was 810 units tall and the last rows and the help line fell off its bottom)
  local K = 1.0
  try(function()
    local lib = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    local size, scale = lib:GetViewportSize(gi), lib:GetViewportScale(gi)
    if size.X > 0 and size.Y > 0 and scale > 0 then K = math.min(size.X / 1920, size.Y / 1080) / scale end
  end)
  if K < 0.5 or K > 4 then K = 1.0 end
  -- fonts and icons only as found in memory, never loaded: LoadAsset from her tick is the likely crash of
  -- 0.4.0's F3 for players whose game hadn't loaded them yet (reported: every time). Not found: a
  -- TextBlock's own font, a key cap for an icon
  local function load_font(path)
    local f = StaticFindObject(path)
    return valid(f) and f or nil
  end
  stage("fonts")
  local fallback = load_font(M.FONT)
  local mid, bold = load_font(M.FONT_MID) or fallback, load_font(M.FONT_BOLD) or fallback
  log(string.format("menu: fonts found: %s %s %s", fallback and "yes" or "no", load_font(M.FONT_MID) and "yes" or "no",
    load_font(M.FONT_BOLD) and "yes" or "no"))
  -- the language's, and each language's own name in its Bold (the Language row shows it whatever the menu is in)
  local _, code = lang()
  local enBold = bold -- (a key cap's text is Latin: the game's own, whatever the menu's language)
  local names = { en = bold }
  for c in pairs(M.FACES) do names[c] = lang_font(c, 2, load_font(M.FONT_BOLD)) end
  if code ~= "en" then
    mid = lang_font(code, 1, load_font(M.FONT_MID)) or mid
    bold = names[code] or bold
  end
  -- the viewport's height in layout units (the backdrop covers it)
  local VH, VW = 1080, 1920
  try(function()
    local lib = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    local size, scale = lib:GetViewportSize(gi), lib:GetViewportScale(gi)
    if size.Y > 0 and scale > 0 then VH = size.Y / scale / K end
    if size.X > 0 and scale > 0 then VW = size.X / scale / K end
  end)
  stage("widgets")
  local stamp = string.format("%d%04d", os.time(), math.random(0, 9999))
  local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), gi, FName("SBGore_Menu_" .. stamp))
  local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SBGore_MenuTree"))
  w.WidgetTree = tree
  local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SBGore_MenuCanvas"))
  tree.RootWidget = canvas
  -- (the widgets stage in parts: a 0.4.1 report crashed in it, its last line "making it: widgets")
  stage("widgets: backdrop")
  local n = 0
  -- ax, ay: the slot's alignment (0.5: x / y is its middle)
  local function place(slot, x, y, ww, hh, ax, ay)
    slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
    slot:SetAlignment({ X = ax or 0, Y = ay or 0 })
    slot:SetPosition({ X = x * K, Y = y * K })
    if ww then slot:SetAutoSize(false); slot:SetSize({ X = ww * K, Y = hh * K }) else slot:SetAutoSize(true) end
  end
  local function box(x, y, ww, hh, r, g, b, a)
    n = n + 1
    local im = StaticConstructObject(cls("/Script/UMG.Image"), tree, FName("SBGore_Img" .. n))
    local slot = canvas:AddChildToCanvas(im)
    place(slot, x, y, ww, hh)
    im:SetColorAndOpacity({ R = r, G = g, B = b, A = a })
    return im, slot
  end
  -- o: { font, wrap (the width it breaks at, layout units), boxw + just (in a box that wide: 1 centred, 2 right),
  -- spacing, mid (y is the line's middle: centred on a box's), centre (x is its middle) }
  local function text(x, y, size, s, o)
    o = o or {}
    n = n + 1
    local tb = StaticConstructObject(cls("/Script/UMG.TextBlock"), tree, FName("SBGore_Txt" .. n))
    -- (the glyphs sit a little above their line's middle: 1/12 of the size down; a language's font as far up again
    -- as it draws low, M.TEXT_UP)
    if o.mid then
      y = y + size / 12
      local fo = o.font or mid
      local code = fo and M.fontCode[try(function() return fo:GetAddress() end) or 0]
      local up = code and ((ctx.tune.menuTextUp or {})[code] or M.TEXT_UP[code])
      if up then y = y - size * up end
    end
    place(canvas:AddChildToCanvas(tb), x, y, o.boxw, o.boxw and size * 1.8, o.centre and 0.5, o.mid and 0.5)
    try(function()
      local f = tb.Font
      local fo = o.font or mid
      if fo then f.FontObject = fo end
      f.Size = math.floor(size * K + 0.5)
      if o.spacing then f.LetterSpacing = o.spacing end
    end)
    if o.wrap then try(function() tb.WrapTextAt = o.wrap * K; tb.AutoWrapText = false end) end
    if o.just then
      if not try(function() tb:SetJustification(o.just); return true end) then try(function() tb.Justification = o.just end) end
    end
    set_text(tb, s)
    return tb
  end
  local function tint(tb, r, g, b, a)
    try(function() tb:SetColorAndOpacity({ SpecifiedColor = { R = r, G = g, B = b, A = a or 1 }, ColorUseRule = 0 }) end)
  end
  -- a focus box: white, a blue glow round it (as the game's Slot_Focus); its parts, shown and hidden together
  local function focus(x, y, ww, hh)
    local parts = {}
    for _, gl in ipairs({ { 8, 0.10 }, { 5, 0.22 }, { 2, 0.5 } }) do
      parts[#parts + 1] = box(x - gl[1], y - gl[1], ww + 2 * gl[1], hh + 2 * gl[1], 0.02, 0.22, 0.75, gl[2])
    end
    parts[#parts + 1] = box(x, y, ww, hh, 1, 1, 1, 1)
    return parts
  end

  -- the backdrop: near black, lighter blue-grey to the right, darker to the bottom, the faint crosses of the
  -- game's screen down the left
  box(0, 0, VW, VH, 0.004, 0.006, 0.009, 0.985)
  for i = 0, 39 do
    box(880 + i * (VW - 880) / 40, 0, (VW - 880) / 40 + 1, VH, 0.03, 0.045, 0.065, ((i + 1) / 40) ^ 1.6 * 0.6)
  end
  for i = 0, 9 do
    box(0, VH - 170 + i * 17, VW, 18, 0, 0, 0, (i + 1) / 10 * 0.55)
  end
  for _, c in ipairs({ { 96, 150 }, { 264, 186 }, { 96, 300 }, { 264, 312 }, { 96, 432 }, { 264, 440 }, { 96, 575 },
      { 264, 568 }, { 96, 720 }, { 264, 704 }, { 96, 852 }, { 264, 828 }, { 434, 210 }, { 434, 806 }, { 588, 800 } }) do
    box(c[1] - 30, c[2], 60, 1, 1, 1, 1, 0.06)
    box(c[1], c[2] - 30, 1, 60, 1, 1, 1, 0.06)
  end
  local ui = { w = w, rows = {}, tabs = {}, K = K, tint = tint, gi = gi }
  stage("widgets: title")
  -- the title (the game's orange), the mod's name and version small under it
  tint(text(101, 92, 23, ui_text("Gore Settings")), 0.716, 0.246, 0.034)
  tint(text(101, 196, 9, "STELLAR BLADE GORE MOD  " .. tostring(ctx.version or ""), { font = bold, spacing = 200 }), 0.25, 0.27, 0.3)
  -- tabs and rows on one grid: the same top, height and spacing, so a tab lines up with the row beside it
  local r0, rh, bh = 222, 58, 48
  ui.r0, ui.rh, ui.bh = r0, rh, bh
  stage("widgets: tabs and rows")
  -- the tabs down the left
  for k, t in ipairs(tabs()) do
    local ty = r0 + (k - 1) * rh
    ui.tabs[k] = { focus = focus(101, ty, 208, bh), txt = text(116, ty + bh / 2, 17, tab_name(t.name), { font = bold, mid = true }) }
  end
  -- the rows: label left, value centred (at 945), arrows the same distance either side of it on the focused row
  local vc = 945
  ui.vc = vc
  for i = 1, M.VISIBLE do
    local ry = r0 + (i - 1) * rh
    local cy = ry + bh / 2
    ui.rows[i] = { focus = focus(385, ry, 790, bh),
      lab = text(400, cy, 17, "", { wrap = 360, mid = true }),
      -- (a label too long for one line at 17: this one, smaller, instead; a wrapped one ran into the next row)
      labS = text(400, cy, 13, "", { wrap = 360, mid = true }),
      val = text(vc, cy, 18, "", { font = bold, centre = true, mid = true }),
      la = text(vc - 170, cy, 18, "<", { font = bold, centre = true, mid = true }),
      ra = text(vc + 170, cy, 18, ">", { font = bold, centre = true, mid = true }) }
  end
  -- the Language row's value: each language's name in its own font, one shown over the row's (moved to it)
  ui.langVal, ui.langUp = {}, {}
  for c, f in pairs(names) do
    ui.langVal[c] = text(vc, 0, 18, M.LANG_NAMES[c], { font = f or bold, centre = true, mid = true })
    ui.langUp[c] = f and ((ctx.tune.menuTextUp or {})[c] or M.TEXT_UP[c]) or 0
    try(function() ui.langVal[c]:SetRenderOpacity(0) end)
  end
  -- a thin scroll bar right of the rows, for a tab longer than the screen
  ui.track = { x = 1196, y = r0, h = M.VISIBLE * rh - 10 }
  ui.trackBg = box(ui.track.x, ui.track.y, 2, ui.track.h, 1, 1, 1, 0.08)
  ui.thumb, ui.thumbSlot = box(ui.track.x, ui.track.y, 2, rh, 0.02, 0.32, 0.9, 1)
  stage("widgets: help line")
  -- what the focused row does
  ui.help = text(400, r0 + M.VISIBLE * rh + 14, 15, "", { wrap = 780 })
  tint(ui.help, 0.32, 0.33, 0.35)
  -- the keys, bottom right: the game's key icons and their names, the keyboard's or the controller's (the last one
  -- used; the controller's as menuPadIcons says). An icon that doesn't load is a white key cap with its text
  local function icon_tex(path)
    local tex = StaticFindObject(M.ICONS .. path .. "." .. path:match("[^/]+$"))
    return valid(tex) and tex or nil
  end
  local function hints(list)
    -- each key its own: the game's icon (44 square, the key ~30 of it in the middle) where one is in memory, else a
    -- white key cap of the icon's height, as wide as its text. Caps were one box over the whole hint, sized for the
    -- icons, the text spilling out of them (playtest)
    local IS, GAP, KGAP, CAP, CW = 44, 30, 6, 30, 9 -- icon; between hints; between keys; cap height; a cap letter
    local function ulen(t) return (utf8 and utf8.len(t)) or #t end
    -- (a hint's name as wide as it is drawn: a CJK character about two Latin ones)
    local function wide(t)
      local ok, w = pcall(function()
        local n = 0
        for _, cp in utf8.codes(t) do n = n + (cp >= 0x1100 and 2.25 or 1) end
        return n
      end)
      return ok and w or #t
    end
    local function caps_of(h)
      local c = h[3]
      if type(c) == "table" then return c end
      if #h[1] == 1 then return { c } end
      local t = {}
      for w in tostring(c):gmatch("%S+") do t[#t + 1] = w end
      return t
    end
    local plan, width = {}, 0
    for i, h in ipairs(list) do
      local caps, keys, kw = caps_of(h), {}, 0
      for j, p in ipairs(h[1]) do
        local tex = icon_tex(p)
        local cap = caps[j] or "?"
        local w = tex and (CAP + 2) or math.max(CAP, ulen(cap) * CW + 14)
        keys[j] = { tex = tex, cap = cap, w = w }
        kw = kw + w + (j > 1 and KGAP or 0)
      end
      local name = ui_text(h[2])
      local lw = #name > 0 and (10 + wide(name) * 10) or 0
      -- (a hint with no name shares the next one's: its keys sit close before the next keys)
      local g = i < #list and (h[2] == "" and KGAP * 2 or GAP) or 0
      plan[i] = { keys = keys, kw = kw, lw = lw, g = g, name = name }
      width = width + kw + lw + g
    end
    local x, cy, out = VW - 90 - width, VH - 73, {}
    for _, pl in ipairs(plan) do
      for j, k in ipairs(pl.keys) do
        local made = false
        if k.tex then
          -- (the icon drawn at its full 44, centred on the key's slot: its margins spill either side)
          local im = box(x + k.w / 2 - IS / 2, cy - IS / 2, IS, IS, 1, 1, 1, 1)
          if try(function() im:SetBrushFromTexture(k.tex, false); return true end) then out[#out + 1] = im; made = true
          else try(function() im:SetRenderOpacity(0) end) end
        end
        if not made then
          local w = math.max(CAP, ulen(k.cap) * CW + 14)
          out[#out + 1] = box(x, cy - CAP / 2, w, CAP, 0.95, 0.95, 0.95, 1)
          local kt = text(x + w / 2, cy, 15, k.cap, { font = enBold, centre = true, mid = true })
          tint(kt, 0.03, 0.035, 0.05)
          out[#out + 1] = kt
        end
        x = x + k.w + (j < #pl.keys and KGAP or 0)
      end
      if pl.lw > 0 then out[#out + 1] = text(x + 10, cy, 17, pl.name, { font = bold, mid = true }) end
      x = x + pl.lw + pl.g
    end
    return out
  end
  stage("key icons")
  ui.keys = {}
  -- the keyboard's Exit is the menu's key as bound (a key cap with its name when the game has no icon for it)
  local mk = ctx.keys and ctx.keys.binding("menu") or "F3"
  ui.menuKey = mk
  for set, list in pairs(M.HINTS) do
    if set == "kb" and ctx.keys then
      local l = {}
      for i, h in ipairs(list) do l[i] = h end
      local mods, key = ctx.keys.parse(mk)
      local k = key and ctx.keys.BY_ENUM[key]
      local plain = k and next(mods) == nil
      l[#l] = { { "PC/KeyIcon_KeyBoard_" .. (plain and k.fkey or "None") }, "Exit", ctx.keys.show(mk) }
      list = l
    end
    ui.keys[set] = hints(list)
  end
  stage("on screen")
  try(function() w:SetVisibility(3) end) -- not hit-testable: clicks reach the game's input, read in M.tick
  w:AddToViewport(960)
  return ui
end

-- how wide a line of text is drawn, in layout units, at size (points: 4/3 of a unit each): a CJK character a full
-- em, a Hangul one nearly, Cyrillic and Latin about half (Rajdhani and Supermolot are narrow)
function M.text_width(t, size)
  local ok, n = pcall(function()
    local n = 0
    for _, cp in utf8.codes(t) do n = n + (cp >= 0x2E80 and 1 or cp >= 0x1100 and 0.95 or cp >= 0x400 and 0.55 or 0.47) end
    return n
  end)
  return (ok and n or #t * 0.5) * size * 4 / 3
end
local function show(im, on) try(function() im:SetRenderOpacity(on and 1 or 0) end) end
local function show_all(list, on) for _, x in ipairs(list) do show(x, on) end end
local function render()
  local s, ui = M.state, M.state.ui
  if not ui then return end
  local tint = ui.tint
  local tk, t = tab_of(s.sel)
  -- the selection kept on screen, within its tab
  if s.top < t.first or s.top > t.last then s.top = t.first end
  if s.sel < s.top then s.top = s.sel end
  if s.sel > s.top + M.VISIBLE - 1 then s.top = s.sel - M.VISIBLE + 1 end
  -- (and no empty rows below a tab's end while rows above are scrolled off)
  if s.top > t.first and t.last - s.top + 1 < M.VISIBLE then s.top = math.max(t.first, t.last - M.VISIBLE + 1) end
  local langShown
  for k, tab in ipairs(ui.tabs) do
    local on = k == tk
    show_all(tab.focus, on)
    if on then tint(tab.txt, 0.022, 0.025, 0.05) else tint(tab.txt, 0.62, 0.63, 0.65) end
  end
  for i = 1, M.VISIBLE do
    local r = ui.rows[i]
    local idx = s.top + i - 1
    local row = idx <= t.last and M.ROWS[idx] or nil
    local on = row ~= nil and idx == s.sel
    show_all(r.focus, on)
    local lab, val = row and label_of(row) or "", row and row.key and value_text(row) or ""
    -- (the Language row's value: its name in its own font, over the row's empty one)
    local lv = row and row.key == "language" and ui.langVal and ui.langVal[get("language") or "en"] or nil
    -- (too long for one line at 17: the smaller label)
    local small = r.labS and M.text_width(lab, 17) > 360
    try(function()
      set_text(r.lab, small and "" or lab); set_text(r.val, lv and "" or val)
      if r.labS then set_text(r.labS, small and lab or "") end
    end)
    if lv then
      langShown = lv
      local up = ui.langUp and ui.langUp[get("language") or "en"] or 0
      try(function() lv.Slot:SetPosition({ X = ui.vc * ui.K, Y = (ui.r0 + (i - 1) * ui.rh + ui.bh / 2 + 18 / 12 - 18 * up) * ui.K }) end)
      if on then tint(lv, 0.022, 0.025, 0.05) else tint(lv, 0.85, 0.85, 0.86) end
    end
    -- (no arrows on a key: Enter takes a new one)
    local arrows = on and val ~= "" and row.kind ~= "key" and row.kind ~= "pad"
    show(r.la, arrows); show(r.ra, arrows)
    if on then
      tint(r.lab, 0.022, 0.025, 0.05); tint(r.val, 0.022, 0.025, 0.05)
      if r.labS then tint(r.labS, 0.022, 0.025, 0.05) end
      tint(r.la, 0.02, 0.32, 0.9); tint(r.ra, 0.02, 0.32, 0.9)
    else
      -- a sub-setting (its label indented) a shade dimmer
      local c = lab:sub(1, 1) == " " and 0.38 or 0.6
      tint(r.lab, c, c, c * 1.03); tint(r.val, 0.85, 0.85, 0.86)
      if r.labS then tint(r.labS, c, c, c * 1.03) end
    end
  end
  for _, lv in pairs(ui.langVal or {}) do show(lv, lv == langShown) end
  local cur = M.ROWS[s.sel]
  try(function() set_text(ui.help, cur and help_of(cur) or "") end)
  local padSet = ctx.tune.menuPadIcons == "xbox" and "xbox" or "playstation"
  for set, list in pairs(ui.keys) do show_all(list, set == (s.pad and padSet or "kb")) end
  -- the scroll bar, only on a tab longer than the screen
  local count = t.last - t.first + 1
  local long = count > M.VISIBLE
  show(ui.trackBg, long); show(ui.thumb, long)
  if long then
    local tr, K = ui.track, ui.K
    local th = tr.h * M.VISIBLE / count
    local ty = tr.y + (tr.h - th) * (s.top - t.first) / (count - M.VISIBLE)
    try(function()
      ui.thumbSlot:SetPosition({ X = tr.x * K, Y = ty * K })
      ui.thumbSlot:SetSize({ X = 2 * K, Y = th * K })
    end)
  end
end

-- ---- open, close, her input held ----
local function controller(pawn)
  local gs = ctx.statics and ctx.statics() or StaticFindObject("/Script/Engine.Default__GameplayStatics")
  return gs, valid(gs) and try(function() return gs:GetPlayerController(pawn, 0) end)
end
local function pause(pawn, on)
  local s = M.state
  local gs, pc = controller(pawn)
  if not valid(gs) then return end
  if on and not s.paused then
    s.paused = { pawn = pawn, pc = pc }
    if valid(pc) then
      try(function() pc:SetIgnoreMoveInput(true) end)
      try(function() pc:SetIgnoreLookInput(true) end)
      try(function() pawn:DisableInput(pc) end)
      -- the mouse: its cursor shown, free of the viewport's capture (game and UI), the clicks still read as keys
      s.paused.cursor = try(function() return pc.bShowMouseCursor end)
      try(function() pc.bShowMouseCursor = true end)
      local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
      if valid(wbl) then try(function() wbl:SetInputMode_GameAndUIEx(pc, nil, 0, false) end) end
    end
    -- the world stopped under it (tune.menuPause): the game paused, her actor ticking through it (the menu runs on her
    -- tick, and the mod's own work waits too: main.lua's game_tick runs only the menu meanwhile). A pause already on
    -- (the game's own) is left to the game
    if ctx.tune.menuPause ~= false and valid(pawn) and try(function() return gs:IsGamePaused(pawn) end) ~= true then
      s.paused.tick = try(function() return pawn.PrimaryActorTick.bTickEvenWhenPaused end)
      try(function() pawn:SetTickableWhenPaused(true) end)
      s.paused.world = try(function() return gs:SetGamePaused(pawn, true) end) == true
      if not s.paused.world then try(function() pawn:SetTickableWhenPaused(s.paused.tick == true) end) end
      log("menu: the game " .. (s.paused.world and "paused" or "didn't pause"))
    end
  elseif not on and s.paused then
    local p = s.paused
    s.paused = nil
    if valid(p.pc) then
      try(function() p.pc:ResetIgnoreMoveInput() end)
      try(function() p.pc:ResetIgnoreLookInput() end)
      if valid(pawn) then try(function() pawn:EnableInput(p.pc) end) end
      try(function() p.pc.bShowMouseCursor = p.cursor == true end)
      local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
      if valid(wbl) then try(function() wbl:SetInputMode_GameOnly(p.pc) end) end
    end
    if p.world then
      if valid(pawn) then try(function() gs:SetGamePaused(pawn, false) end) end
      if valid(p.pawn) then try(function() p.pawn:SetTickableWhenPaused(p.tick == true) end) end
    end
  end
end
-- the game paused by the menu (main.lua's game_tick runs only the menu then)
function M.pausing() return M.state.open and M.state.paused ~= nil and M.state.paused.world == true end
function M.open(pawn)
  local s = M.state
  if s.open then return end
  local ok = s.ui and valid(s.ui.w) and try(function() return s.ui.w:IsInViewport() end)
  -- (made again for a menu key rebound since: its Exit hint)
  if ok and ctx.keys and s.ui.menuKey ~= ctx.keys.binding("menu") then
    try(function() s.ui.w:RemoveFromParent() end)
    ok = false
  end
  if not ok and not text_by() then
    log("menu: not made: sbslice.dll can't set its text, and UE4SS didn't find the game's FText constructor "
      .. "(UE4SS.log: \"Failed to find FText::FText\"); settings.lua works as ever")
    return
  end
  if not ok then
    local built, ui = pcall(build)
    if not built then log("menu: couldn't be made: " .. tostring(ui)); return end
    s.ui = ui
  else
    try(function() s.ui.w:SetVisibility(3) end)
  end
  s.open, s.held, s.changed, s.swallow = true, {}, {}, true
  -- (settings.lua read again: a hand edit shows here and applies without a restart, as the old Reload Settings key did)
  if ctx.reload_tune then ctx.reload_tune() end
  M.refresh()
  if not selectable(s.sel) then s.sel = 2 end
  pause(pawn, true)
  log("menu: making it: first draw")
  render()
  log("menu: opened")
end
local function capture_end()
  M.state.capture = nil
  if ctx.keys then ctx.keys.capture = nil end
  -- (the key just taken, still down, isn't a press in the menu)
  M.state.swallow = true
end
function M.close(pawn)
  local s = M.state
  if not s.open then return end
  if s.capture then capture_end() end
  s.open = false
  if s.ui and valid(s.ui.w) then try(function() s.ui.w:SetVisibility(1) end) end
  pause(pawn, false)
  local names = {}
  for k in pairs(s.changed) do names[#names + 1] = k .. "=" .. tostring(get(k)) end
  table.sort(names)
  if #names > 0 then
    save()
    log("menu: closed, saved to menu.lua: " .. table.concat(names, " "))
    if ctx.reload_tune then ctx.reload_tune() end
  else
    log("menu: closed, nothing changed")
  end
end
-- pad: opened from the controller (its key hints shown till a key is pressed)
function M.toggle(pawn, pad)
  local now = os.clock()
  if now - M.state.toggled < 0.3 then return end
  M.state.toggled = now
  if not M.state.open then M.state.pad = pad == true end
  if M.state.open then M.close(pawn) else M.open(pawn) end
end

local function step(dir)
  local s = M.state
  local row = M.ROWS[s.sel]
  if not row or not row.key or row.kind == "key" or row.kind == "pad" then return end
  local v = get(row.key)
  if row.kind == "bool" then v = not (v == true)
  elseif row.kind == "list" then
    local k = 1
    for i, x in ipairs(row.values) do if x == v then k = i end end
    v = row.values[(k - 1 + dir) % #row.values + 1]
  else
    v = math.max(row.min, math.min(row.max, (tonumber(v) or row.min) + dir * row.step))
    v = math.floor(v / row.step + 0.5) * row.step
    if row.step >= 1 then v = math.floor(v + 0.5) end
    -- (whole percents stored clean: 0.27, not 0.27000000000000002)
    if row.pct then v = math.floor(v * 100 + 0.5) / 100 end
  end
  set(row.key, v)
  s.changed[row.key] = true
  if row.key == "dev" then M.refresh() end
  -- (another language: the menu made again, in its strings and fonts)
  if row.key == "language" then
    if s.ui and valid(s.ui.w) then try(function() s.ui.w:RemoveFromParent() end) end
    local built, ui = pcall(build)
    -- (once more on a failure: a font that didn't take is left for the game's the second time)
    if not built then
      log("menu: couldn't be made again: " .. tostring(ui) .. ", trying once more")
      built, ui = pcall(build)
    end
    s.ui = built and ui or nil
    if not built then log("menu: couldn't be made again: " .. tostring(ui)) end
  end
  -- (a row whose change shows at once on what is already out: its function on gore)
  if row.apply and ctx.gore and ctx.gore[row.apply] then
    local ok, err = pcall(ctx.gore[row.apply])
    if not ok then log("menu: " .. row.apply .. " failed: " .. tostring(err)) end
  end
  render()
end
local function press(pawn)
  local s = M.state
  local row = M.ROWS[s.sel]
  if not row then return end
  if row.call then
    -- (a module's function: "bosses.spawn_pick" is ctx.bosses.spawn_pick(pawn))
    local m, f = row.call:match("^(%w+)%.([%w_]+)$")
    local fn = m and ctx[m] and ctx[m][f]
    if fn then
      local ok, err = pcall(fn, pawn)
      log("menu: " .. row.label .. (ok and "" or (" failed: " .. tostring(err))))
    else
      log("menu: " .. row.label .. ": " .. tostring(row.call) .. " not loaded")
    end
  elseif row.button == "close" then M.close(pawn)
  elseif row.button == "reset" then
    os.remove(M.PATH)
    s.changed = {}
    if ctx.reload_tune then ctx.reload_tune() end
    log("menu: back to settings.lua (menu.lua deleted)")
    M.refresh()
    render()
  elseif row.kind == "bool" or row.kind == "list" then step(1)
  elseif row.kind == "pad" then
    -- (read in M.tick: nothing counts till every button is up, A included)
    s.capture = { id = row.id, key = row.key, pad = true, combo = {}, ready = false, t = os.clock(), min = row.min, max = row.max }
    render()
  elseif row.kind == "key" and ctx.keys and s.pad then
    -- (the mod's keys are keyboard keys: A on a controller waited 10 s for one)
    log("menu: " .. tostring(row.id) .. ": a keyboard key, changed from the keyboard")
  elseif row.kind == "key" and ctx.keys then
    -- the next key pressed (keys.lua hands it here instead of to its action)
    s.capture = { id = row.id, key = row.key, t = os.clock() }
    ctx.keys.capture = function(combo)
      local c = s.capture
      capture_end()
      if not c then return end
      local old = ctx.keys.binding(c.id)
      local others = ctx.keys.on_combo(combo, c.id)
      set(c.key, combo)
      s.changed[c.key] = true
      local swapped = {}
      for _, a in ipairs(others) do
        set("keys." .. a.id, old)
        s.changed["keys." .. a.id] = true
        swapped[#swapped + 1] = a.label
      end
      log(string.format("menu: %s on %s%s", c.id, combo, #swapped > 0 and (" (" .. table.concat(swapped, ", ") .. " moved to " .. old .. ")") or ""))
      render()
    end
    render()
  end
end
-- the tab's rows back to settings.lua's values (R / Y / Triangle), applied at once; menu.lua drops them on closing
local function reset_tab()
  local s = M.state
  local base = ctx.base_tune and ctx.base_tune()
  if not base then log("menu: tab reset: settings couldn't be read"); return end
  local _, t = tab_of(s.sel)
  local n, applies = 0, {}
  for i = t.first, t.last do
    local row = M.ROWS[i]
    if row.key then
      local v = get_in(base, row.key)
      -- (a key unset in settings.lua goes back to its default: unset here too)
      if (v ~= nil or row.kind == "key") and v ~= get(row.key) then
        set(row.key, v); s.changed[row.key] = true; n = n + 1
        if row.apply then applies[row.apply] = true end
      end
    end
  end
  for fn in pairs(applies) do
    if ctx.gore and ctx.gore[fn] then
      local ok, err = pcall(ctx.gore[fn])
      if not ok then log("menu: " .. fn .. " failed: " .. tostring(err)) end
    end
  end
  log(string.format("menu: %s tab reset to settings.lua (%d changed)", t.name, n))
  M.refresh()
  render()
end
-- up/down within the tab (round from its last row to its first), the tabs round too
local function move(dir)
  local s = M.state
  local _, t = tab_of(s.sel)
  local i = s.sel
  repeat
    i = i + dir
    if i > t.last then i = t.first elseif i < t.first then i = t.last end
  until selectable(i)
  s.sel = i
  render()
end
local function switch(dir)
  local s = M.state
  local T = tabs()
  local k = (tab_of(s.sel) - 1 + dir) % #T + 1
  s.sel, s.top = T[k].first, T[k].first
  render()
end

-- the mouse: a row or tab under it (once it moves) is picked, a click on a tab opens it, on a row's arrows steps it,
-- elsewhere on a row presses it (as Enter); the wheel moves up and down. Hit-tested here against the layout (the
-- widgets aren't hit-testable), its position in layout units
local function mouse(pawn, pc, down)
  local s, ui = M.state, M.state.ui
  if not ui then return end
  M.wll = valid(M.wll) and M.wll or StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
  local p = valid(M.wll) and try(function() return M.wll:GetMousePositionOnViewport(ui.gi) end)
  if not p then return end
  local x, y = p.X / ui.K, p.Y / ui.K
  local moved = s.mx ~= nil and math.abs(x - s.mx) + math.abs(y - s.my) > 2
  s.mx, s.my = x, y
  local lmb = down("LeftMouseButton")
  local click = lmb and not s.lmb
  s.lmb = lmb
  local function just(k) return try(function() return pc:WasInputKeyJustPressed({ KeyName = FName(k) }) end) == true end
  local wheel = just("MouseScrollUp") and -1 or just("MouseScrollDown") and 1 or nil
  if (moved or click or wheel) and s.pad then s.pad = false; render() end
  if wheel then move(wheel); return end
  if not (moved or click) then return end
  local tk, t = tab_of(s.sel)
  for k in ipairs(ui.tabs) do
    local ty = ui.r0 + (k - 1) * ui.rh
    if x >= 101 and x <= 309 and y >= ty and y <= ty + ui.bh then
      if click and k ~= tk then switch(k - tk) end
      return
    end
  end
  for i = 1, M.VISIBLE do
    local ry = ui.r0 + (i - 1) * ui.rh
    if x >= 385 and x <= 1175 and y >= ry and y <= ry + ui.bh then
      local idx = s.top + i - 1
      if idx > t.last or not selectable(idx) then return end
      if s.sel ~= idx then s.sel = idx; render() end
      if click then
        if x >= ui.vc - 215 and x <= ui.vc - 120 then step(-1)
        elseif x >= ui.vc + 120 and x <= ui.vc + 215 then step(1)
        else press(pawn) end
      end
      return
    end
  end
end
M.FG_S = 0.1
-- every tick of hers: the open combo on the controller, and the menu's keys while it is open (a key held repeats)
function M.tick(pawn)
  local s = M.state
  s.tickAt = os.clock()
  -- (main.lua's watchdog unpaused the game: her tick had stopped under the menu's pause)
  if s.unstuck then
    s.unstuck = nil
    log("menu: her tick stopped under the menu's pause: unpaused, closed")
    if s.open then M.close(pawn) end
    return
  end
  local _, pc = controller(pawn)
  if not valid(pc) then return end
  local function down(name) return try(function() return pc:IsInputKeyDown({ KeyName = FName(name) }) end) == true end
  local pad = ctx.tune.menuPad
  if type(pad) == "table" and #pad > 0 and not s.capture then
    local all = true
    for _, k in ipairs(pad) do if not down(k) then all = false; break end end
    if all and not s.padWas then M.toggle(pawn, true) end
    s.padWas = all
  end
  -- (arrows pressed with the menu shut, or while a key is being taken, don't wait for it)
  if ctx.keys and (not s.open or s.capture) and #ctx.keys.nav > 0 then ctx.keys.nav = {} end
  if not s.open then return end
  local now = os.clock()
  -- the game's window put behind another (alt-tab): closed, her input given back. Left open, the game's pause on losing
  -- focus stopped her tick, which this runs on, and the menu stood frozen over it (reported). Asked of sbslice.dll
  -- (Windows' foreground window) every FG_S s
  if now >= (s.fgNext or 0) then
    s.fgNext = now + M.FG_S
    local g = ctx.gore
    local r = g and g.native_ready and g.native_ready() and g.command and g.command("K")
    if type(r) == "string" and r:match(" fg0") then
      log("menu: the game's window lost focus (alt-tab): closed")
      M.close(pawn)
      return
    end
  end
  -- waiting for a key to bind: only Backspace / B (cancel) is read, and it gives up after 10 s
  if s.capture and s.capture.pad then
    local c = s.capture
    local held = {}
    for _, k in ipairs(M.PAD) do if down(k) then held[#held + 1] = k end end
    local bs = down("BackSpace")
    if not c.ready then
      if #held == 0 then c.ready = true end
    elseif #held > 0 then
      -- the buttons in the order they went down, up to max
      for _, k in ipairs(held) do
        local have = false
        for _, x in ipairs(c.combo) do if x == k then have = true end end
        if not have and #c.combo < c.max then c.combo[#c.combo + 1] = k; c.t = now; render() end
      end
    elseif #c.combo > 0 then
      -- all let go: taken, or (one button) B cancels, anything else too few
      local combo = c.combo
      if #combo >= c.min then
        local old = get(c.key)
        set(c.key, combo)
        s.changed[c.key] = true
        log(string.format("menu: %s on %s (was %s)", c.id, table.concat(combo, "+"), type(old) == "table" and table.concat(old, "+") or tostring(old)))
        capture_end()
      elseif #combo == 1 and combo[1] == "Gamepad_FaceButton_Right" then
        log("menu: " .. c.id .. " not changed (cancelled)")
        capture_end()
      else
        log(string.format("menu: %s needs %d buttons held together, got %d", c.id, c.min, #combo))
        c.combo = {}
      end
      render()
      return
    end
    if bs or now - c.t > 10 then
      log("menu: " .. c.id .. " not changed (" .. (bs and "cancelled" or "no buttons in 10 s") .. ")")
      capture_end()
      render()
    end
    return
  end
  if s.capture then
    local back = false
    for _, k in ipairs(M.KEYS.back) do if down(k) then back = true end end
    if back or now - s.capture.t > 10 then
      log("menu: key not changed (" .. (back and "cancelled" or "no key in 10 s") .. ")")
      capture_end()
      render()
    end
    return
  end
  if not s.swallow then mouse(pawn, pc, down) end
  if ctx.keys and #ctx.keys.nav > 0 then
    local nav = ctx.keys.nav
    ctx.keys.nav = {}
    if s.pad then s.pad = false; render() end
    for _, d in ipairs(nav) do
      if d == "up" then move(-1) elseif d == "down" then move(1) elseif d == "left" then step(-1) else step(1) end
    end
    s.arrow = { what = nav[#nav], next = now + 0.4 }
  end
  -- an arrow held repeats as the controller's do: its state asked of sbslice.dll (Windows' own, the engine never sees
  -- it), only while one is held and only as a repeat is due
  local ar = s.arrow
  if ar and now >= ar.next then
    local g = ctx.gore
    local r = g and g.native_ready and g.native_ready() and g.command and g.command("K26,28,25,27")
    local bits = type(r) == "string" and r:match("^ok ([01][01][01][01])")
    local at = ({ up = 1, down = 2, left = 3, right = 4 })[ar.what]
    if bits and bits:sub(at, at) == "1" then
      ar.next = now + 0.08
      if at == 1 then move(-1) elseif at == 2 then move(1) elseif at == 3 then step(-1) else step(1) end
    else s.arrow = nil end
  end
  if not s.open then return end
  for what, names in pairs(M.KEYS) do
    local on = false
    local pad
    for _, k in ipairs(names) do if down(k) then on = true; pad = k:sub(1, 7) == "Gamepad"; break end end
    local h = s.held[what]
    -- the key hints follow the last key used
    if on and not h and pad ~= s.pad then s.pad = pad; render() end
    if not on then s.held[what] = nil
    elseif s.swallow and not h then s.held[what] = { at = now, next = math.huge } -- down as it opened: not a press
    elseif not h or now >= h.next then
      s.held[what] = { at = h and h.at or now, next = now + (h and 0.08 or 0.4) }
      if what == "up" then move(-1) elseif what == "down" then move(1)
      elseif what == "tabl" and not h then switch(-1) elseif what == "tabr" and not h then switch(1)
      elseif what == "left" then step(-1) elseif what == "right" then step(1)
      elseif what == "ok" and not h then press(pawn)
      elseif what == "reset" and not h then reset_tab()
      elseif what == "back" and not h then M.close(pawn); return end
    end
  end
  s.swallow = false
end

return M
