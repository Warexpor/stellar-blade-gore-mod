-- Every knob of the mod, re-read as the F3 menu opens (no restart). settings.lua overrides these key by key (the player's switches,
-- and dev: the test keys, the spawner and the glass cannon only work with it on). The top ones apply to F7 test
-- ragdolls; the collision switches also apply to real deaths.
return {
  push = 300,                  -- F7: cm/s the whole body is shoved (its centre of mass moves; 0 = none; 450 threw
                               --   her 5-8 m/s, far harder than any death)
  impulse = 400,               --   cm/s the upper body gets on top (spread over chest, neck, head, arms; 0 = none)
  legKick = 250,               --   cm/s her feet (calves less) are swept the other way, so she goes over and lands on
                               --   her back with "back"
  direction = "back",          -- "back", "forward", "left", "right" of...
  relativeTo = "eve",          --   ..."eve" (her own facing) or "camera" (the camera's view)
  up = 0.1,                    -- upward share of the shove
  selfCollision = false,       -- her bodies collide with each other: an arm landing on her body set her spinning
                               -- and folding at wild angles (eighteenth playtest), so off; "auto": on for physics
                               -- assets the data mod fixed, off for vanilla ones (vanilla overlaps Pelvis/Thigh at
                               -- rest and flings her); true forces it
  hairCollision = false,       -- true = SBHair keeps PhysicsOnly collision during the ragdoll
  massScale = 1.0,             -- SetAllMassScale on every body
  recoverAfter = 12,           -- seconds of ragdoll before the script gets her up (the death screen, 10 s in, covers it);
                               -- not the test keys' (F7, F11, F9 on a ragdoll): those wait for F8
  recoverOn = "button",        -- "button": a death waits past recoverAfter till a death screen button is pressed (the
                               -- game respawns her after that), so her cut body stays behind the screen; "timer": at
                               -- recoverAfter, under the screen
  screenWait = 4,              --   seconds past recoverAfter a death with no death screen at all (F5's) waits for one
  photoUnhide = true,          -- photo mode's camera up close doesn't hide her (she is shown again every frame)
  photoNearClip = 1,           -- cm: the near clip plane while photo mode is on (the game's 10 cut into her up close; 0 leaves it)
  holdDown = true,             -- knocked down, she stays down till you dodge or jump (the game's fast getup); false: she
                               -- gets up on her own after 1 s, as in the game (needs the data pak and sbslice.dll)
  verboseLog = false,          -- the log's per-poll and per-frame watches (a death's bone speeds, her attachments, face
                               -- and camera, hooks, each cut stage, each slow tick and frame hitch): for chasing a bug
  smoothAnim = false,          -- every character's animation updated every frame (the engine skips frames on characters
                               -- further off or small on screen: they can look choppy next to the world, running
                               -- most; costs some CPU with many on screen)
  menuPad = { "Gamepad_LeftShoulder", "Gamepad_RightShoulder", "Gamepad_LeftThumbstick" }, -- the settings menu (F3) on
                               -- the controller: all held (false: none)
  keys = {},                   -- the mod's keys by action (keys.lua has them and their defaults), e.g. { split = "Ctrl+F11" };
                               -- "None" unbinds one. The F3 menu's Keys tab sets them
  menuPadIcons = "playstation", -- the menu's controller key icons: "playstation" or "xbox"
  menuPause = true,            -- the F3 menu pauses the game while it is open (false: the world goes on under it)
  language = "en",             -- the F3 menu's language: "en", "zh" (Chinese, Simplified), "ja", "ko" or "ru"
  deathScreen = "delay",       -- when the death screen comes up: "game" as the game puts it (at once), "delay" reviveAt
                               -- seconds into the death, "key" only on Shift+F4 (or holdPad). Shift+F4 shows it early,
                               -- and hides it again (the death held) once it is up
  fewerGC = false,             -- fewer garbage collection passes: the engine's pass forced as each streamed level goes
                               -- out (and its incremental ones while one waits) off, the 61 s timed pass kept; false (the default)
                               -- the game's own values back
  customizedRagdoll = false,   -- Customized Ragdoll (Nexus 3884) support (customrag.lua): its death camera instead of
                               -- cameraStill's, the death screen up as the game puts it but see-through, its keys
                               -- (F / R) working; the mod's ragdoll and cuts as ever (that mod's physics kept off her)
  hideHud = true,              -- the rest of the HUD (HP bar, skills, minimap, notices) hidden through a death, back as
                               -- she is up again; the death and revive screens keep to deathScreen
  newObjectWatch = true,       -- characters, the death and photo mode widgets, photo mode's pawn and knockdown checks
                               -- caught as they are made (newobj.lua: sbslice.dll's listener, or UE4SS's NotifyOnNewObject
                               -- without it). false: none caught, characters found by FindAllOf every 10 s, photo mode's
                               -- early freeze lost. "ue4ss": NotifyOnNewObject for all, as up to 0.5.0 (UE4SS 3.1.0-6 only)
  keepFresh = 2,               -- s: a character or widget seen as it spawned is checked alive (sbslice "G") this soon, or
                               -- never held (characters are found again with FindAllOf)
  reviveAt = 10,               -- the death screen (and the revive item's) is held hidden this many seconds into the death
  deathPhoto = true,           -- while a death is held (Shift+F4) the game's photo mode opens (P, or D-pad left + R1),
                               -- which the game turns down while she is dead
  capsuleStill = true,         -- her capsule, which the camera rides, stays where she died: SB's ragdoll dragged it
                               -- after her pelvis a step a tick and the camera stuttered after her (playtest 38)
  capsuleUnstick = true,       -- as she gets up, her capsule (dragged after her body unswept) is swept from where she
                               -- went limp to where it is, stopping at walls: revived, she stood inside one (Nexus)
  cameraStill = true,          -- at a death the view holds still where it is till she gets up: the game moves her pawn
                               -- after the ragdoll and the view rode it, jerking after her body (playtest 41)
  cameraMouse = 3,             --   the held view turns this many degrees a unit of mouse input, all the way round, up and
                               --   down (SB reads about 0.06 a frame for a slow move)
  cameraStick = 150,           --   and this many degrees a second at the right stick's full tilt
  cameraBody = true,           --   the point it turns about rides her pelvis, up and down too, every frame (as Customized
                               --   Ragdoll's camera does), till it is flown; false: it slides after her (cameraTrack)
  cameraBodyBone = "upper",    --   which part of her: "upper" (her chest, Spine2) or "pelvis" (Customized Ragdoll's)
  cameraMotionBlur = false,    --   the game's motion blur in the death camera's view (false: none; on, the stump caps smeared
                               --   the way the blow went as the camera rode her body)
  cameraBodyRate = 15,         --   how tightly it rides her pelvis, a second (0: rigidly, her ragdoll's shakes and all)
  cameraBodyBlend = 0.5,       --   where it looked at her death eases onto her pelvis over about this many seconds
  cameraFlyAfter = 1.5,        --   WASD / Q/E and the left stick and triggers fly it only from this many seconds into the
                               --   death: till then it stays locked on her body; the first press after lets go of her
  cameraZoomEase = 10,         --   the zoom eases to where the wheel sets it at this rate a second (0: at once)
  cameraWallEase = 4,          --   pushed in by a wall, it eases back out at this rate a second once the way clears
  cameraTrack = 2.5,           --   (cameraBody off) it slides sideways after her pelvis, never up or down, closing this share of the gap a
                               --   second (smoothed, so her ragdoll's shakes don't reach it; 0: it stays put)
  cameraMove = 400,            --   WASD, Q/E (down/up) and the left stick and triggers fly it this many cm a second
                               --   (once flown it stops sliding after her)
  cameraFast = 3,              --   this many times faster with Shift
  cameraRange = 1500,          --   no further than this many cm from where it started (and zoomed out no further)
  cameraZoomMin = 15,          --   the mouse wheel and the D-pad (up in, down out) zoom it in down to this many cm
  holdPad = { "Gamepad_DPad_Down", "Gamepad_RightShoulder" }, -- Shift+F4 on the controller: both down in a death
                               -- shows the death screen, or hides it again (false: none)
  holdPadFor = 1.0,           -- seconds both are held before it counts (a quick press of both in a fight came by accident)
  uvClean = true,              -- with Ultra Violence on, its blood comes off her at a respawn (it keeps it through one
                               -- on its own): she reads as swimming for 1.2 s as she gets up, its water clear
  deathSkip = true,            -- Esc on her death fast forwards the game to its death screen instead of the wait
                               -- (parked for now: its key is commented out in main.lua)
  deathSkipSpeed = 6,          --   this many times as fast till the screen shows
  cameraFollow = false,        -- during a ragdoll her capsule (and the camera on it) drifts after her body, loosely
                               -- (off: it fought how the death plays out, and the game died a second after it moved
                               -- the capsule of a really dead Eve, thirteenth playtest)
  cameraSlack = 40,            --   cm she may move before it follows
  cameraRate = 0.06,           --   share of the rest it closes a tick (30 a second): it lags, it doesn't track
  cameraLift = 95,             --   cm over her pelvis it is held (about where it stands over the floor)
  gore = {
    enabled = true,            -- false = no cutting, no blood (sbslice.dll stays idle)
    sliceOnDeath = true,       -- a killing blow leaves a mark (see death)
    sliceChance = 1.0,         -- 0..1, per death
    death = {                  -- relative odds of what it does (every killing blow cuts, whatever hit her);
                               -- F9 rolls the cuts only, F10 marks, F11 splits
      limb = 42,               --   the arm or thigh nearest the hit comes off
      head = 25,               --   beheaded (the face goes with the head, the neck gets a stump)
      torso = 15,              --   cut in half at the waist
      split = 18,              --   cut in half top to bottom; rolled when no blade decides (bladeFollow)
      diagonal = 0,            --   cut diagonally from over a shoulder down to the other hip (see diagonal; 0 here so
                               --   a settings.lua from before it, its odds set to one kind alone, still does that one
                               --   every death; settings.default.lua has 15)
      moreLimbs = 0.35,        --   a limb cut takes another nearest limb with this chance, and a third with it again
    },                         --   (0.35: 35 % two or more, 12 % three)
    followUpCuts = true,       -- one swing cuts every arm, leg, her body and neck it went through (multiCut), and a
                               --   rolled limb cut takes more (death.moreLimbs); false: one cut a swing, her body over
                               --   the limbs it crossed (laserCut still cuts along the beam)
    bladeFollow = 0.8,         -- share of deaths with a blade seen that the blade decides; the rest roll the odds above
                               -- (a blade mostly crosses her body: at 1 nearly every death was a waist cut or a split)
                               -- A death whose killing hit the game reported, or whose enemy's weapon swing was
                               -- seen, is otherwise decided by that blade alone, nothing rolled: what its plane goes through
                               -- comes off (the neck, her body along it or in two down her length, the arms and
                               -- legs it crosses); the odds above are rolled only without either
    oddsNear = {               -- the odds above, when rolled, follow where the blow landed (gore.lua's near_odds):
      enabled = true,          --   each kind's odds times how near the hit was to what it cuts (false: as they are)
      near = 15,               --   cm from the neck, her waist, her length or a limb within which its odds count in full
      far = 35,                --   cm from it at which they are down to floor (her skin is 10-15 cm off the bones)
      floor = 0,               --   share of its odds a part this far from the hit keeps (0: never; 1: as if off)
      across = 0.25,           --   share of the waist cut's a blade down her length keeps (a blade across her: no split)
      noPlane = 0.5,           --   share of the split's (and the diagonal's) with no blade's plane to go by
      offSlant = 0.3,          --   share of the diagonal's from a blade not slanting diagonal.bladeFrom-bladeTo
    },                         --   (odds whose only kinds above 0 are all far from the hit are rolled as they are)
    diagonal = {               -- the diagonal cut (gore.lua's diag_plane): from over one shoulder down across her to over
      enabled = false,         --   the other hip, her half keeping the head and the other arm, the copy that arm and
                               --   both legs (false: none, rolled or from a blade). Parked: off, out of F3 and the
                               --   keys, sbslice.c's fixes for it off (DIAG_PARKED)
      lift = 6,                --   cm over the shoulder's joint the cut starts
      hip = 8,                 --   cm over the other hip's joint it ends
      out = 7,                 --   and cm out past it (6 / 8 / 7: about 36 degrees off her spine)
      jitter = 2,              --   cm lift and hip each move at random (33-40 degrees)
      bladeFrom = 20,          --   a blade through her body this many degrees off her spine
      bladeTo = 60,            --   up to this many cuts diagonally (else across her, or a split down her length)
    },
    bladeJitter = 15,          -- for variety, each blade is turned up to this many degrees at random
    bladeShift = 10,           --   and moved up to this many cm along its normal
    bladeTries = 4,            --   turns tried for a death that would take the same first part as the last one
    noSplits = false,          -- vertical splits off altogether: no blow, roll or after-death hit splits her down her
                               --   length; the blade's limbs come off instead, the odds' split share goes to the others
                               --   (the F11 / F5 test keys still split)
    deathSplit = true,         -- a blade down her length at death splits her (false: the limbs it crosses come off
                               --   instead, else the odds above; F11 and F5 still split)
    armsOverSplit = 0.6,       -- share of splits (rolled, or a blade down her length) whose blade crossed both arms
                               --   within multiCut's reach that take both arms instead (the split won nearly always)
    splitArms = true,          -- the arms such a blade crosses within multiCut's reach cm of the hit (an arm raised to
                               --   block) come off first, then the split; each half takes the cut arm whose shoulder
                               --   it keeps (false: they stay whole on their half)
    multiCut = {               -- one killing swing cuts every arm and leg (and the neck) its plane crosses within
      enabled = true,          --   reach cm of the hit, at most max cuts, one after the other
      reach = 40,
      max = 3,
      body = true,             -- an arm or leg it took first doesn't stop it: where its plane goes on
      bodyReach = 60,          --   through her spine within bodyReach cm of the hit, her body is cut too
      bodyGraze = 10,          --   (and a plane passing this close beside her spine goes through her flank: cut on it)
                               --   with her body cut, one leg at most comes off with it (no pelvis left on its own)
    },
    woundAtHit = true,         -- the killing blow's blood and slice the tick her HP bar reaches 0 (the death itself is
                               --   only seen 0.2-0.5 s later, at the death show's ragdoll key)
    cutAtHit = true,           -- a limb, the head or her body the killing blade took is cut then too; a split (and the
                               --   blow's other cuts) wait for the death
    openWait = 0,              -- frames between a cut's stubs and its piece coming off (1 before: ~50 ms later)
    openTime = 0.05,           -- a cut opens over this many seconds: the piece hangs on by a joint whose give widens
                               --   every tick, sagging and sliding along the cut, then lets go and flies (0: at once)
    openGap = 8,               -- the joint's give at the end of it, cm
    openSwing = 35,            -- and its swing, degrees (twist half that)
    openPush = 40,             -- a nudge out along the cut as it starts, cm/s
    queueGap = 1,              -- frames between one cut of a swing and the next (the engine catches up in between)
    stageBudgetMs = 8,         -- ms of a cut's caps, stubs and opening run in one frame: the next stage goes on in the
                               --   same frame while the ones so far took under half of it (0: a stage a frame)
    sliceTilt = 45,            -- a limb cut along a blade leans with it at most this many degrees off square
    bodyTilt = 15,             -- a cut across her body (under her bust) leans at most this many degrees off square to
                               --   her spine, whatever the blade or blow did: more ran through a breast
    bodyLeanSide = 20,         -- a waist cut with no blade angle (rolled) leans at random up to this many degrees to
    bodyLeanFront = 10,        --   either side, and up to this with her front lower (front higher ran into her bust)
    splitYaw = 15,             -- a split down her length turns at most this many degrees from her left/right middle
                               --   (never front from back: a slab of her chest)
    limbReach = 12,            -- a blade meeting an arm or leg this close to the hit, with the hit
    spineReach = 15,           --   further than this from the spine, takes that limb (else the plane decides)
    splitDown = 0.6,           -- how steeply a swing must come down to split (share of its direction pointing down);
                               --   a blow this steep never cuts her across the waist, it cuts down through her
    stompSpeed = 250,          -- an enemy coming down this fast (cm/s) as she dies, with no blade seen: the blow
                               --   came straight down (a stomp)
    weaponSwing = true,        -- the killing blade follows the nearest enemy's weapon (its weapon meshes' blade line,
                               --   else its weapon bones by name, else its hands), sampled every tick while she
                               --   lives; false: a made-up swing
    swingReach = 500,          --   cm: the enemies followed are the nearest this close
    swingKeep = 2.5,           --   one followed stays followed (its trail kept) out to this many times swingReach
    swingFollow = 3,          --   how many of them, each with its own trail (the killing swing: the blade that swept nearest her)
    swingWindow = 0.6,         --   seconds of its weapon kept; the step in them whose blade swept nearest her is the killing swing
    swingMinSpeed = 300,       --   cm/s it must reach to count (slower: the made-up swing)
    swingSpeedPull = 30,       --   cm nearer a step counts at swingSpeedFull and up (the fast strike over a slow brush)
    swingSpeedFull = 9000,     --   cm/s: the speed that gets all of swingSpeedPull (less in proportion below it)
    swingAgeCost = 60,         --   cm farther a step counts per second before the death (the slash that killed her over
                               --   the wind-up brushing past a leg before it)
    photoGrace = 0.5,          --   seconds after photo mode closes before hits after death count again
    swingMiss = 45,            --   cm: a blade whose nearest step stayed this far from every part of her missed her, its
                               --   plane isn't the cut's
    swingAwayCost = 60,        --   cm farther a step counts when its blade moved away from her part (the pull-back after the blow)
    swingSnap = 30,            --   cm: a plane passing her this close stays where the weapon put it (further: moved
                               --   onto the part of her nearest it, at the same angle)
    swingBones = 8,            --   most weapon bones followed per enemy
    blowPose = true,           --   her pose is noted with each sample, and the killing blade is judged on her body as
                               --   the weapon met it (false: as it is when the death starts, the death show's first
                               --   moves on: an arm raised to block had swung away and only her body was cut)
    attackerIgnore = { "Drone", "CH_P_", "AirborneSquad" }, -- class names (parts) never taken for her killer: her drone, playable characters, the passive angels
    legRagdoll = true,         -- a leg cut on her own death fall switches to the ragdoll first (she can't fall on it)
    headRagdoll = false,       -- a beheading on it too, always (false: headRagdollChance of the time, else her body
    headRagdollChance = 0.6,   --   plays the fall on headless)
    armRagdoll = false,        -- an arm cut on it too (false: she falls on, the arm drops)
    armRagdollChance = 0.4,    -- with armRagdoll off: the share of arm cuts on her fall that ragdoll her anyway, her legs
                               --   still on (each arm rolled: both off, likelier)
    deathFace = {              -- a dead face held on her face mesh's morph targets from `at` s into a death, faded in
      enabled = true,          --   over `fade` s, until she gets up (the game's own death face was gone 1 s in and
      at = 0.3,                --   her eyes stayed open). Page Up shows the moods in turn, 6 s each
      fade = 0.5,
      morphs = {               --   { JALI morph, its ARKit twin, weight }: the first one her face mesh has is used;
                               --   from = its weight as the face comes on, easing to weight over `over` s. These on
                               --   every death; a mood's own entries added (a morph in both: the mood's)
        -- her eyes half open, closing slowly as she goes (how far: lidsShut)
        { "upLid_down_L", "eyeBlinkLeft", 1.0, from = 0.45, over = 7 },
        { "upLid_down_R", "eyeBlinkRight", 1.0, from = 0.5, over = 7.5 },
        { "loLid_up_L", 0.15 }, { "loLid_up_R", 0.15 },
        -- her pupils widening as she goes
        { "eye_dilate_open_L", 0.5, from = 0, over = 5 }, { "eye_dilate_open_R", 0.5, from = 0, over = 5 },
      },
      jitter = 0.25,           --   each weight, start weight and time scaled by up to this share either way, each side
                               --   on its own (her face never the same twice, never quite symmetric)
      lidsShut = { 0.7, 1.0 }, --   how far her eyes end up shut, picked per death (below 1: a dead stare through
                               --   half-closed lids)
      gaze = 0.35,             --   most her eyes drift off (up, down or aside, both the same way), picked per death
      jawSide = 0.25,          --   most her slack jaw hangs to one side
      mouthMax = { jaw_open = 0.5, jawOpen = 0.5, lowerLip_down = 0.45, wholeMouth_down = 0.35 }, -- most her mouth drops open, the
                               --   mood and the convulsions' gasps and winces added up (a gasp's 0.55 x faceOpen on a
                               --   shocked face's 0.3 opened it all the way, playtest)
      moods = {                --   one picked per death by weight (Page Up shows them in turn); the same twice
                               --   running only when there is no other
        { name = "agony", weight = 3, morphs = {   -- brows knit, eyes squeezed, nose and lips pulled, slackening
          { "brow_furrow", 0.08, from = 0.6, over = 6 },
          { "brow_down", 0.05, from = 0.35, over = 6 },
          { "brow_in", "browInnerUp", 0.2, from = 0.4, over = 6 },
          { "squint", 0.05, from = 0.45, over = 5 },
          { "nose_wrinkle", 0.0, from = 0.3, over = 4 },
          { "lip_stretch", 0.0, from = 0.3, over = 4 },
          { "upperLip_up", 0.0, from = 0.15, over = 4 },
          { "lipCorner_down_left", "mouthFrownLeft", 0.3, from = 0.45, over = 6 },
          { "lipCorner_down_right", "mouthFrownRight", 0.3, from = 0.4, over = 6 },
          { "jaw_open", "jawOpen", 0.2, from = 0.08, over = 7 },
        } },
        { name = "grit", weight = 2, morphs = {    -- teeth bared and clenched, letting go late
          { "brow_furrow", 0.1, from = 0.75, over = 7 },
          { "brow_down", 0.05, from = 0.5, over = 7 },
          { "squint", 0.05, from = 0.6, over = 6 },
          { "squint_lower", 0.0, from = 0.4, over = 6 },
          { "nose_wrinkle", 0.0, from = 0.45, over = 5 },
          { "lip_stretch", 0.1, from = 0.65, over = 6 },
          { "upperLip_up", 0.0, from = 0.4, over = 6 },
          { "lowerLip_down", 0.05, from = 0.4, over = 6 },
          { "grimace_neck", 0.0, from = 0.5, over = 4 },
          { "jaw_open", "jawOpen", 0.22, from = 0.0, over = 8 },
          { "lipCorner_down", 0.25, from = 0.2, over = 6 },
        } },
        { name = "shock", weight = 2, morphs = {   -- eyes and mouth wide, brows up, staring
          { "upLid_down_L", "eyeBlinkLeft", 0.75, from = 0.05, over = 8 },
          { "upLid_down_R", "eyeBlinkRight", 0.75, from = 0.1, over = 8.5 },
          { "upLid_up_L", 0.0, from = 0.35, over = 4 }, { "upLid_up_R", 0.0, from = 0.35, over = 4 },
          { "innerBrow_up", 0.25, from = 0.7, over = 6 },
          { "outerBrow_up", 0.05, from = 0.5, over = 5 },
          { "jaw_open", "jawOpen", 0.3, from = 0.4, over = 6 },
          { "lowerLip_down", 0.1, from = 0.3, over = 5 },
          { "nostrill_flare", 0.0, from = 0.4, over = 3 },
          { "lipCorner_down", 0.2, from = 0.1, over = 6 },
        } },
        { name = "sorrow", weight = 2, morphs = {  -- brows raised in the middle, mouth turned down, chin trembling up
          { "innerBrow_up", 0.3, from = 0.65, over = 7 },
          { "brow_in", 0.25, from = 0.45, over = 7 },
          { "squint", 0.1, from = 0.3, over = 6 },
          { "lipCorner_down", 0.4, from = 0.6, over = 7 },
          { "sadSmile", 0.1, from = 0.35, over = 6 },
          { "chin_up", 0.05, from = 0.45, over = 5 },
          { "lowerLip_down", 0.1, from = 0.0, over = 6 },
          { "jaw_open", "jawOpen", 0.16, from = 0.04, over = 7 },
        } },
        { name = "dread", weight = 3, mirror = true, morphs = { -- died frightened: one eye half shut, the other
                               --   staring, brows up and uneven, the mouth twisted (pulled down and aside on one side,
                               --   the lip up on the other, the jaw off to it); mirror: either side, per death. (The
                               --   half-shut lid at 0.55 with the lower lid and squint up read as shut, playtest)
          { "upLid_down_L", "eyeBlinkLeft", 0.3, from = 0.2, over = 6 },
          { "loLid_up_L", 0.1 },
          { "squint_left", 0.08 },
          { "upLid_down_R", "eyeBlinkRight", 0.0 },
          { "upLid_up_R", 0.2, from = 0.45, over = 6 },
          { "loLid_up_R", 0.0 },
          { "innerBrow_up", 0.45, from = 0.75, over = 7 },
          { "outerBrow_up_right", 0.3, from = 0.5, over = 6 },
          { "brow_down_left", 0.2 },
          { "lipCorner_down_left", "mouthFrownLeft", 0.55, from = 0.4, over = 5 },
          { "lip_stretch_left", 0.45, from = 0.6, over = 6 },
          { "upperLip_sneer_right", 0.3, from = 0.45, over = 6 },
          { "lipCorner_pull_right", 0.15 },
          { "lipCorner_down_right", "mouthFrownRight", 0.1 },
          { "lowerLip_down", 0.2 },
          { "jaw_open", "jawOpen", 0.25, from = 0.35, over = 6 },
          { "jaw_left", "jawLeft", 0.3 },
          { "grimace_neck", 0.15, from = 0.4, over = 5 },
          { "nostrill_flare", 0.2, from = 0.5, over = 4 },
        } },
        { name = "scream", weight = 3, morphs = {  -- died screaming: eyes torn wide and staring, brows high and
                               --   pulled together, the mouth stretched open, the neck's cords taut; her eyes stay open
                               --   a long while, closing only partway
          { "upLid_down_L", "eyeBlinkLeft", 0.35, from = 0.0, over = 10 },
          { "upLid_down_R", "eyeBlinkRight", 0.35, from = 0.0, over = 10.5 },
          { "upLid_up_L", 0.1, from = 0.55, over = 7 }, { "upLid_up_R", 0.1, from = 0.55, over = 7 },
          { "loLid_up_L", 0.0 }, { "loLid_up_R", 0.0 },
          { "innerBrow_up", "browInnerUp", 0.35, from = 0.85, over = 8 },
          { "brow_in", 0.25, from = 0.5, over = 8 },
          { "outerBrow_up", 0.15, from = 0.45, over = 7 },
          { "jaw_open", "jawOpen", 0.35, from = 0.5, over = 8 },
          { "lip_stretch", 0.2, from = 0.6, over = 7 },
          { "lowerLip_down", 0.2, from = 0.45, over = 7 },
          { "upperLip_up", 0.05, from = 0.25, over = 6 },
          { "lipCorner_down", 0.2, from = 0.35, over = 7 },
          { "grimace_neck", 0.1, from = 0.7, over = 6 },
          { "nostrill_flare", 0.1, from = 0.6, over = 5 },
        } },
        { name = "horror", weight = 2, morphs = {  -- frozen on what she saw: a silent scream, the mouth fallen open
                               --   and rounded, eyes wide and rolled a little up, brows raised; set till the end
          { "upLid_down_L", "eyeBlinkLeft", 0.2, from = 0.0, over = 12 },
          { "upLid_down_R", "eyeBlinkRight", 0.2, from = 0.0, over = 12 },
          { "upLid_up_L", 0.25, from = 0.45, over = 8 }, { "upLid_up_R", 0.25, from = 0.45, over = 8 },
          { "loLid_up_L", 0.0 }, { "loLid_up_R", 0.0 },
          { "eye_up_L", 0.2, from = 0.0, over = 4 }, { "eye_up_R", 0.2, from = 0.0, over = 4 },
          { "innerBrow_up", "browInnerUp", 0.5, from = 0.8, over = 8 },
          { "outerBrow_up", 0.35, from = 0.6, over = 8 },
          { "jaw_open", "jawOpen", 0.45, from = 0.35, over = 4 },
          { "lowerLip_funnel", 0.2, from = 0.3, over = 6 }, { "upperLip_funnel", 0.15, from = 0.25, over = 6 },
          { "lowerLip_down", 0.15, from = 0.25, over = 6 },
          { "nostrill_flare", 0.05, from = 0.35, over = 5 },
        } },
        { name = "fading", weight = 1, morphs = {  -- quiet: the pain already leaving, eyes closing sooner
          { "upLid_down_L", "eyeBlinkLeft", 1.0, from = 0.65, over = 4 },
          { "upLid_down_R", "eyeBlinkRight", 1.0, from = 0.7, over = 4.5 },
          { "brow_in", 0.1, from = 0.3, over = 4 },
          { "innerBrow_up", 0.12, from = 0.25, over = 4 },
          { "lipCorner_down", 0.15, from = 0.25, over = 5 },
          { "jaw_open", "jawOpen", 0.14, from = 0.05, over = 6 },
        } },
      },
    },
    laserCut = true,           -- a laser trap death is cut along the beam: every arm, leg and her body (or her head)
    laserReach = 40,           --   its plane goes through. The beam that hit her, else one passing within laserReach cm
                               --   of her parts; false: the death odds, as any death with no blade seen
    bluntRagdoll = false,      -- a blunt killing blow (a hammer, a fist, a stomp: told as smash's below, smash.sharp /
                               --   smash.blunt) cuts nothing: the death is a plain ragdoll, hits after it cut nothing
                               --   either. Goes before smash; blades still cut
    lowArm = {                 -- a hit that leaves her HP under a quarter takes an arm off as she fights on
      enabled = false,         --   (once till it is back: it grows back at a camp rest, or at her next life)
      side = "hit",            --   which: "hit" the side of her the blow landed on (at random when it landed on her
                               --   middle or nothing tells), "left", "right" or "either" (one at random each time)
      below = 0.25,            --   the share of her HP bar under which it goes
      noHealGun = true,        --   while it is off she can't use heal items or shoot (the game's own blocks on her,
                               --   ActorState_BlockItemUseHeal and _BlockItemUseBullet)
      notice = true,           --   and her aim or heal key pressed meanwhile shows the game's "Cannot use right now."
                               --   with its sound (the HUD's system notice)
      noSword = true,          --   with the right arm off she can't use her sword (the game's own swordless stance,
                               --   P_Eve_BlockSword: her gun and heals work, no lock-on or drone scan meanwhile)
      effect = true,           --   it comes back with an effect (F3 → Regrow Effect; false: back at once, no effect)
      dissolve = {             --   at a camp rest it dissolves back in (the game's corpse dissolve run backwards, her
        time = 3,              --   own textures on it), over time s (false: grown back over regrow s instead)
        glow = 10,             --   the glow it peaks at halfway (the despawn's EmissiveBright starts at 10)
        morph = true,          --   its surface ripples in with it (the despawn's Morph)
        maskScale = 200,       --   the dissolve pattern's scale
        fade = 0.6,            --   then her own skin back under it, the copy dissolving out over it in fade s (0:
                               --   swapped at once)
      },
      regrow = 1.5,            --   without the dissolve: s it takes to grow back out of her shoulder, the upper arm,
                               --   then the forearm, then the hand (0: back at once)
      restDelay = 5,           --   s at a camp's chair (its Interaction_Camp_Chair sequence) till the rest's restore
      restWindow = 20,         --   s after she sat down out of battle (her movement mode none: the camp's seat)
                               --   within which her HP bar full again is the rest's heal
      healBack = false,        --   it also grows back once her HP bar is back at healAt, however it got there (gear
      healAt = 0.9,            --   that heals on kills or over time; heal items too with noHealGun off)
    },
    smash = {                  -- (experimental) a blunt killing blow (a hammer, a fist, a stomp) smashes the arm, leg
      enabled = false,         --   or head it landed on to meat: the part comes off and vanishes, the game's meat chunks
                               --   (SM_meat_01-04) and a burst of blood fly out where it was; its stump stays as a cut's
      always = false,          --   every death smashes, blunt or not (to try it)
      chunks = 3,              --   meat chunks for an arm
      chunksLeg = 4,           --   for a leg
      chunksHead = 4,          --   for the head
      chunksBody = 7,          --   for her upper body (smashed from the waist up)
      sizeMin = 5,             --   cm across, the smallest chunk
      sizeMax = 11,            --   the biggest
      speed = 350,             --   cm/s they burst out at (half to one and a half times), along the blow and every way
      kg = 0.3,                --   each chunk's mass
      drips = 3,               --   chunks that drip blood as they fly and pool where they land
      splash = false,          --   the game's meat splash effect (NS_A_MeatSplash) on top of the hit blood
      -- material = "...",     --   the chunks' material (default: the stumps' meat, MI_A_Meat_01_1; false: the
      --                            meshes' own, an effect material)
      bareHands = true,        --   a bare hand, foot, knee or elbow swinging (no weapon mesh) is blunt
      -- names (any part, any case) of what hit her, sharp checked first: the swinging enemy's weapon meshes, its
      -- swinging bone, then the enemy's name and class. A blow from above with no weapon (a stomp) is blunt too
      sharp = { "sword", "blade", "claw", "knife", "axe", "spear", "lance", "scythe", "saw", "sickle", "katana",
        "dagger", "cutter", "spike", "thorn", "lion", "mite", "raven", "tachy", "gorgon", "lurker", "weaponmaster",
        "behemoth" },
      blunt = { "hammer", "club", "mace", "fist", "punch", "gorilla", "juggernaut", "brute", "exosuit",
        "hunchback", "statue", "bodybag", "lump", "roadblock", "hedgeboar" },
    },
    afterHits = {              -- an enemy's weapon swinging through her once she is dead cuts her again: a limb, the
      enabled = true,          --   head or (while she is whole) her body in two along the swing, else a hit mark
      reach = 25,              --   cm its weapon's blade passes from a part of her...
      handReach = 40,          --   ...or its hand bone, with no weapon mesh (the fingers or claws past it: a hands-only
                               --   enemy's second blow on her went unseen at 25, playtest)
      minSpeed = 500,          --   cm/s it moves at least, in an attack (one of its montages that isn't a walk, turn,
                               --   hit reaction...): 300 and any weapon passing by cut her (a brush, reported)
      max = 6,                 --   hits a death
      from = 0.6,              --   s into the death before the first (the killing swing itself doesn't count twice)
      rearm = 0.35,            --   s after an enemy's last cut (or the death) it may cut again, slowed down or not (a
                               --   combo's next blow came with its hands never slowing, and cut nothing, playtest)
      cutChance = 0.75,        --   share that cut (the rest leave a hit mark, see hitMarks; with the marks off all cut)
    },
    hitWindow = 0.6,           -- seconds before death the game's last hit on her still counts as the killing blow
    splitPush = 140,           -- cm/s the halves get away from each other (300 flung them apart, fifteenth playtest)
    splitTip = 110,            -- cm/s more on each half's upper body (Spine2 up), so a cut down her length falls open
    splitBleedDelay = 0.3,     -- seconds after a split opens before it bleeds (the halves come apart first)
    splitSpine = false,        -- a split down her length shows the spine halved along each lid (GM_Brokenbone pieces;
                               --   off: they read as loose bones on the lid)
    splitSpineWidth = 3.0,     --   cm wide in the plane
    splitSpineFlat = 1.2,      --   cm thick out of it
    splitBeside = 2,           -- cm beside her neck an F11 / F5 / odds split passes (leaning from her crotch up, between
                               --   her breasts), so the head stays whole on one half; 0 = straight up her spine through
                               --   the head. At 10 it ran through a breast
    splitHipShift = 4,         -- cm its lower end moves off her crotch to either side at random, so it runs a little
                               --   diagonally (the hip joints sit 10 cm off; an odds split with no swing also turns at
                               --   random within splitYaw)
    splitMinShare = 0.12,      -- a split leaving either half less than this share of her body is a waist cut instead
    splitLidGrow = 0.4,        -- cm a split's flat lid reaches past the skin round its edge
    splitLidPush = 0.2,        -- cm it sits out of the half, over the flattened skin
    splitLidSkin = true,       -- the lid in one piece that bends with her spine (false: a rigid piece per spine bone,
                               --   which cracked into shards as she bent)
    splitLidFollow = 0,        -- seconds the bending lid follows her, then it stays as it lies (0: as long as it is on
                               --   her; it updates only while she moves. After 12 s it stayed put, and a ragdoll
                               --   nudged later left it off her)
    splitRigOff = true,        -- a split turns the outfit's post-process AnimBP off on both halves: it moved the rig's
                               --   Dm- drivers after the limbs each half keeps, and the skin collapsed onto them came
                               --   out through the lid as spikes and patches
    probes = false,            -- diagnostics after a split or limb cut: the stretch probe (skins every vertex on the
                               --   CPU at 0.5 and 2 s, a stutter of its own), the helper drift and the masses read
                               --   back (dev turned them on too, and stuttered every playtest)
    slowMs = 15,               -- a split stage or sbslice command taking this long is logged (stutter hunt)
    asyncLoad = true,          -- the cuts' effects, materials and sounds loaded ahead by the game's async loader
                               --   (sbslice "J"), not on the game thread (the first blood effect held a frame 1.4 s,
                               --   each sound 30 ms, playtest); false: one a look on the game thread as before
    splitAnim = 0,             -- a split on her death fall (tune.active.animated): her fall plays on while it is cut,
                               -- then both halves play on with it for this many seconds once it opens and come apart
                               -- by physics at the speed it had. 0 = they come apart as it opens
    bone = "auto",             -- "auto" = the roll above, or always one of: Bip001-Head, Bip001-Spine1,
                               -- Bip001-L/R-UpperArm, Bip001-L/R-Forearm, Bip001-L/R-Thigh, Bip001-L/R-Calf
    cutAt = "auto",            -- where along the limb, 0 = joint, 1 = next joint; "auto" = 0.4 (torso 0.5, the head
                               -- headAt; a blade's cut at least 0.3 down the limb)
    headAt = 1.0,              -- a beheading's plane between the neck bone (0) and the head bone (1, under her jaw):
                               -- 0.7 took the head off with a long neck (the face mesh's, whole). Past ~1.2 it cuts
                               -- the jaw
    faceCut = true,            -- the face mesh is cut at the plane too, its neck stays on her (false = it goes whole
                               -- with the head, and headAt is 0.7: above the body's neck there's nothing to cut)
    jawClear = 0.5,            -- with faceCut, the plane goes down until her jaw is this many cm above it (a nod or a
                               -- leaning blow put her chin under the head bone's plane, and a slice of it stayed on
                               -- the neck); false = the plane stays at headAt
    jawDrop = 3,               --   at most this many cm down; past it the plane leans back toward her head's own axis
    hitMarks = {               -- a hit she lives through leaves a slash of blood on her skin (no cut): a decal
      enabled = false,         --   on the skin where it landed (the DLL finds it), along the swing, riding that skin's
                               --   bone. F10 puts one on a part at random. false = living hits leave nothing (parked
                               --   for now: off, and out of settings.lua and the README)
      delay = 0.25,            --   s after the hit (a killing blow's hit gets the death cut instead)
      needDamage = true,       --   only a hit that took HP off her bar (a guarded or parried one leaves none)
      length = 14,             --   cm long (a forearm's or calf's shorter: it stays on the part's curve)
      width = 4,               --   cm wide, the box: the sword scar's streak fills about a third of it
      scale = 1.0,             --   both, each mark 75-125 % of it at random
      depth = 0.5,             --   how far its box reaches into her, times the part's radius
      max = 12,                --   on her at once, the oldest goes first
      healFade = 2.5,          --   s a mark takes to fade once healing has brought her HP bar back to where it was
                               --   before its hit (all go when she recovers or respawns)
      blood = true,            --   the hit's blood burst on the mark
      reach = 40,              --   cm the hit may be from her nearest part
    },
    voice = {                  -- her own death cry (Eve's action-voice recordings) the moment she dies, nothing after
      enabled = true,          --   false: the game's own death voice only
      volume = 1.0,
      cutFade = 0.08,          --   s the cry fades out in when her head comes off (cut off, but no click)
      rest = 8,                --   s a recording rests before it can play again
      sounds = nil,            --   recordings to pick from (nil: vo_eve_die_01-05): names under
                               --   Sound/Dialogue/ActionVoice/Eve ("vo_eve_die_fall_01") or full paths of any
                               --   SoundWave / SoundCue ("/Game/Mods/MyVoice/scream_01"). A voice mod that replaces
                               --   vo_eve_die_* in place needs nothing here
      asHer = true,            --   played as another character (the Stellar Blade Play As mod, or any mod putting her meshes on
                               --   Eve: seen by them), her death cry and the breaths and moans after it are that
                               --   character's own recordings (`as` below), unless `sounds` is set (false: Eve's)
      as = {
        tachy = { die = { "/Game/Sound/Dialogue/ActionVoice/Tachy/vo_Tachy_dmg_xl1_VO",
            "/Game/Sound/Dialogue/ActionVoice/Tachy/vo_Tachy_dmg_xl2_VO", "/Game/Sound/Dialogue/ActionVoice/Tachy/vo_Tachy_dmg_xl3_VO" },
          breaths = { "/Game/Sound/Dialogue/ActionVoice/Tachy/vo_Tachy_breath_s1_VO",
            "/Game/Sound/Dialogue/ActionVoice/Tachy/vo_Tachy_breath_s2_VO" },
          moans = { "/Game/Sound/Dialogue/ActionVoice/Tachy/vo_Tachy_dmg_s1_VO", "/Game/Sound/Dialogue/ActionVoice/Tachy/vo_Tachy_dmg_s2_VO",
            "/Game/Sound/Dialogue/ActionVoice/Tachy/vo_Tachy_dmg_s3_VO", "/Game/Sound/Dialogue/ActionVoice/Tachy/vo_Tachy_dmg_s4_VO",
            "/Game/Sound/Dialogue/ActionVoice/Tachy/vo_Tachy_dmg_s5_VO" } },
        -- (Raven has no death line: her heaviest hurt screams)
        raven = { die = { "/Game/Sound/Dialogue/ActionVoice/Raven/vo_Raven_dmg_xl1_VO", "/Game/Sound/Dialogue/ActionVoice/Raven/vo_Raven_dmg_xl2_VO",
            "/Game/Sound/Dialogue/ActionVoice/Raven/vo_Raven_dmg_xl3_VO", "/Game/Sound/Dialogue/ActionVoice/Raven/vo_Raven_dmg_xl4_VO" },
          breaths = { "/Game/Sound/Dialogue/ActionVoice/Raven/vo_Raven_breath_s1_VO", "/Game/Sound/Dialogue/ActionVoice/Raven/vo_Raven_breath_s2_VO",
            "/Game/Sound/Dialogue/ActionVoice/Raven/vo_Raven_breath_s3_VO", "/Game/Sound/Dialogue/ActionVoice/Raven/vo_Raven_breath_s4_VO" },
          moans = { "/Game/Sound/Dialogue/ActionVoice/Raven/vo_Raven_dmg_xs2_VO", "/Game/Sound/Dialogue/ActionVoice/Raven/vo_Raven_dmg_xs3_VO",
            "/Game/Sound/Dialogue/ActionVoice/Raven/vo_Raven_dmg_s1_VO", "/Game/Sound/Dialogue/ActionVoice/Raven/vo_Raven_dmg_s2_VO",
            "/Game/Sound/Dialogue/ActionVoice/Raven/vo_Raven_dmg_s3_VO" } },
        scarlet = { die = { "/Game/Sound/Dialogue/ActionVoice/Scarlet/vo_Scarlet_Dead_1_VO", "/Game/Sound/Dialogue/ActionVoice/Scarlet/vo_Scarlet_Dead_2_VO",
            "/Game/Sound/Dialogue/ActionVoice/Scarlet/vo_Scarlet_Dead_3_VO", "/Game/Sound/Dialogue/ActionVoice/Scarlet/vo_Scarlet_Dead_4_VO",
            "/Game/Sound/Dialogue/ActionVoice/Scarlet/vo_Scarlet_Dead_5_VO" },
          breaths = { "/Game/Sound/Dialogue/ActionVoice/Scarlet/vo_Scarlet_groggy_S_1_VO", "/Game/Sound/Dialogue/ActionVoice/Scarlet/vo_Scarlet_groggy_S_2_VO",
            "/Game/Sound/Dialogue/ActionVoice/Scarlet/vo_Scarlet_groggy_S_3_VO", "/Game/Sound/Dialogue/ActionVoice/Scarlet/vo_Scarlet_groggy_S_4_VO",
            "/Game/Sound/Dialogue/ActionVoice/Scarlet/vo_Scarlet_groggy_S_5_VO" },
          moans = { "/Game/Sound/Dialogue/ActionVoice/Scarlet/vo_Scarlet_Dmg_S_1_VO", "/Game/Sound/Dialogue/ActionVoice/Scarlet/vo_Scarlet_Dmg_S_2_VO",
            "/Game/Sound/Dialogue/ActionVoice/Scarlet/vo_Scarlet_Dmg_S_3_VO", "/Game/Sound/Dialogue/ActionVoice/Scarlet/vo_Scarlet_Dmg_S_4_VO",
            "/Game/Sound/Dialogue/ActionVoice/Scarlet/vo_Scarlet_Dmg_S_5_VO", "/Game/Sound/Dialogue/ActionVoice/Scarlet/vo_Scarlet_groggy_L_1_VO",
            "/Game/Sound/Dialogue/ActionVoice/Scarlet/vo_Scarlet_groggy_L_3_VO" } },
      },
    },
    sounds = true,             -- the game's own gore sounds on cuts and splits
    soundVolume = 1.0,
    tilt = 0.25,               -- random tilt of the cut plane
    blowTilt = 35,             -- death cuts lean towards the killing blow's direction, at most this many degrees
                               -- off square (0 = always square to the limb)
    chains = "detach",         -- an accessory chain hanging off a cut limb (CH_P_EVE_09's capes off the upper arms):
                               -- "detach" cuts it off and lets it fall on its own, "body" hangs it on the body
    throw = 250,               -- cm/s the severed piece gets, away from the body (0 = it just drops)
    deathThrow = 280,          -- cm/s a piece cut off by a killing blow flies with, the way the blow went (650 with
                               --   pieceGravity sent it 5-10 m)
    afterThrow = 500,          -- cm/s a piece cut off by a hit after her death flies with (her body woken for it first)
    legThrow = 1.4,            -- a cut-off leg gets this many times the throw when it just drops off (it dropped at
                               --   her feet); not on a killing blow's
    legLift = 0.35,            --   and leans this much more upward
    throwUp = 0.25,            -- steepest a thrown piece climbs (the sine of its angle: 0.25 = 14 deg; they flew up
                               --   at 45 and arced over her)
    pieceGravity = 0.55,       -- share of gravity a cut-off arm or leg falls with, for its first pieceFloat s (1 = full:
    pieceFloat = 3,            --   it dropped like a stone)
    throwTicks = 3,           -- ticks after a cut the piece is kept at least as fast as its throw (the throw went in
                               --   the tick its bodies started simulating and was mostly lost)
    splitFly = 200,            -- cm/s both halves of a death split fly with, the way the blow went
    splitFlyUpper = 300,       --   and the upper body of one across the waist (at 200 it dropped at her feet)
    caps = true,               -- flesh caps over both openings
    capScale = 1.05,           -- cap size relative to the opening's outline (1 = ends exactly on the skin)
    boneStubs = true,          -- a bone in each stump: Tachy's metal bone and tubes in a limb's (tachy_core.lua), her
                               -- bone alone at the spine in a neck's or waist's
    torsoLegs = {              -- a death's cut across her waist while her fall plays: her legs and hips play the fall on
      enabled = true,          --   while the upper body flies off in the ragdoll (else all of her goes to the ragdoll)
      level = 0.75,            --   odds when the killing blade swung level across her (within levelDeg of flat)
      slant = 0.35,            --   odds when it swung slanted
      rolled = 0.5,            --   odds with no blade seen (the death odds' torso)
      levelDeg = 30,
    },
    tachyCore = 1.0,           --   tachy: its bone and tubes' size, times the opening's
    tachyCoreMax = 6,          --   tachy: cm the opening counts as at most (a thigh's core stays bone sized)
    tachyCoreLeg = 1.4,        --   tachy: a leg's bone and tubes, times the above (thin in a thigh, playtest)
    tachyCoreLook = {          --   tachy: her bone and tubes, a dark grey near the flesh (hers: 1, 0, white; near
      brightness = 0.8,        --   black in the dark, at Brightness 1.8 too light, playtest); false: hers as is
      desaturation = 0.7,      --   towards grey
      tint = { 1, 0.8, 0.78 }, --   a little of the flesh's red
    },
    tachyRelief = 1.0,         --   how deep the flesh's torn relief is, times the default (0: smooth)
    tachyDome = 0.2,           --   how far the flesh bulges out of the cut, as a share of a dome (0: flat; a little
                               --   covers the cut's closed skin where it stands proud)
    -- tachyLids = false,         -- tachy: her flesh disc on the caps too (off: 0.3.0's meat lids; on the procedural
    --                            --   lids her flesh read pale and washed out, playtest). The bone and tubes are hers
    -- tachyFlesh = {             -- the caps' flesh, on their own instance of Tachy's material: her own values (her
    --   enabled = true,          --   master's defaults, Roughness Min 0.3, no glow) look as in the cutscene. Brightness
    --                            --   8-10 here (it read near black on the texture) blew it out pale and washed in game
    --                            --   (playtest); false: her material as is
    --   brightness = 1,          --   her material's Brightness (hers 1)
    --   tint = { 1, 1, 1 },      --   its Base Color Tint (hers white; under 1 in green and blue: a deeper red)
    --   roughness = 0.9,         --   its Roughness Min (hers 0.3: her texture's own is near mirror smooth; the
    --                            --   room's light off it is the pale haze, rough spreads it thin)
    --   metallic = 1,            --   its Metallic, times her texture's (hers 1)
    --   desaturation = 0,        --   its Desaturation (hers 0)
    --   contrast = 0,            --   its Contrast (hers 0)
    --   roughnessMax = 1,        --   its Roughness Max (hers 1)
    --   ao = 0.5,                --   its AOMultiply: how much of the room's light and reflections reach it (hers 1),
    --   aoTint = { 1, 1, 1 },    --   and the AO Tint they take (hers white) (the core keeps hers)
    --   emissive = { power = 8, color = { 1, 0.02, 0.05 } }, -- a crimson glow, her texture's red times this (hers
    --                            --   0): its own colour whatever the light. At Brightness 1-10 the flesh stayed pale in
    --                            --   game, the room's light off it over its dark red (playtest)
    -- },
    -- boneSilver = false,        --   tachy: her bone on the metal of her texture (it is painted ivory, read as pale dirt)
    tachyCapScale = 1.0,       --   tachy: the flesh's size against the opening (at 1.05 it ran over the cut's edge)
    stubBone = 0.3,            --   the spine's bone: its shaft's thickness, as a share of the opening's width (at most
                               --   spineBoneMax cm)
    spineBoneMax = 3.5,        --   cm the spine's bone is at most thick (a waist's was a pipe)
    spineBoneOut = 1.2,        --   how far it sticks out, times her bone's own height (a third of its width)
    spineBoneWaist = 1.6,      --   a waist cut's spine bone that much wider, no taller (thin there, playtest)
    blood = true,              -- hit/cut/bleed effects
    sliceFx = false,           -- the game's flesh-slice burst at the cut: it drops a static meat stub made for
                               -- monster stumps, which hangs in the air where she was cut
    bleedTime = 2.5,           -- seconds both openings keep bleeding (0 = until she recovers)
    bleedAxis = "z",           -- the bleed effect's (NS_Hit_Flesh_Slice_BloodOnly) cone axis, pointed out of each
                               -- opening: "z", "x", "-z", "-x" (the F3 menu re-reads it; the "bleed: opening faces" log line
                               -- shows where the effect's Z and X really point: pick the one matching the opening)
    bleedSize = 0.6,           -- the bleed's size (the effect's scale; the spurts are as many)
    bleedPulse = 0.35,         -- seconds between spurts while an opening bleeds (each follows the stump's turn)
    capMaterial = "/Game/Art/FX/MA/Enviroment/MI_A_Meat_01_1.MI_A_Meat_01_1", -- the flesh on caps and lids
    capMatte = {               -- caps and lids matte: the meat's textures on the game's character gore master
      enabled = false,         --   (the meat material's shine is baked in, the stumps looked wet; matte, they looked too
                               --   rough, playtest); false: the meat as is
      material = "/Game/Art/Character/Generic/GlobalMasterMaterials/MA_CH_Standard_Gore.MA_CH_Standard_Gore",
      roughness = { 0.75, 1.0 }, -- its Roughness Min / Max (1 = no shine at all)
      splitLids = false,       -- a split's lids on it too (false: the meat material: on it they didn't look solid)
    },
    debugCaps = false,         -- every cap and lid glows bright green (a test: are the split's shards lids or skin?)
    bloodTint = {              -- her bleed's and hit blood's colour (MPC_BloodParameters, global: the game's own blood
      DefaultBlood = { 0.06, 0.002, 0.005 },   -- on her too); the game's 0.15, 0, 0 / 0.23, 0.05, 0 / 0.15 sprayed
      DefaultBlood2 = { 0.08, 0.004, 0.008 },  -- bright red. false = the game's
      EmissiveBloodMinValue = 0.02,
    },
    capBloodColor = { 0.12, 0.005, 0.002 }, -- its glow (BloodColor, emissive: the material's own 10, 2.4, 0 lit the
                               -- stumps bright orange); nil = the material as it is
    bodyBlood = {              -- her skin's own blood layer (MPC_PCDirtyOffset, read by Eve's skin material) raised on
      enabled = true,          -- any cut (F9, F11 too), all of her at once (it is global); put back when she recovers
      factor = 1.0,            --   BloodFactor to reach (the log shows the value it had)
      offset = 0.5,            --   BloodOffset to reach (its default is 0, BloodFactor's already 1; a first guess:
                               --   if she shows no blood, try 1.0 or -0.5)
      time = 1.5,              --   seconds to get there
    },
    hitSplat = true,           -- blood decal under every hit
    splatSize = 14,            --   cm across the splat under a cut or a hit is, about (radius; the pools' blood)
    splatLife = 30,            --   s the splat under a hit she lives through stays (a death's stay till she is up)
    pool = true,               -- floor blood: a cut's openings (F9, F11 too) drip while they move and pool where they rest
                               -- (without a cut: one pool under the body after 2 s)
    poolScale = 1.0,           --   pool size (a neck or thigh ~55-60 cm radius, a forearm 30, a split 90)
    poolGrow = 5,              --   seconds for a pool to reach most of its size (it keeps spreading slowly)
    poolTime = 12,             --   seconds each opening is followed
    dripEvery = 18,            --   cm between drips while it moves
    maxDecals = 150,           --   drips and pools in all (at the cap the oldest drip goes, a pool only when no
                               --   drip is left)
  },
  physfix = {                  -- physfix.lua: every outfit's ragdoll fixes, made in game (the build's outfits container
                               -- has the same ones, and isn't shipped)
    enabled = true,            -- false = leave such an outfit's physics as it ships
    linearDamping = 0.2,       -- the main bodies' damping, as the data mod sets it (vanilla 5.0: she falls slowly)
    angularDamping = 1.0,      --   (vanilla 10: she turns as if under water)
    hardLimits = true,         -- the main joints' limits stop dead instead of giving way
    lockBelow = 6,             --   and a motion limited to fewer degrees than this is locked (a few degrees of hard
                               --   limit sat at the limit all the time: every joint buzzed)
    ranges = {                 -- how far each main joint's far end (end) swings towards her front and her back from the
                               -- bind pose, degrees: the twist is centred there from the bind pose (sbslice.dll's "b").
                               -- The same as mod/ragdoll_spec.json's outfits.ranges (test/run.sh phys checks it)
      ["Bip001-L-Calf"] = { e = "Bip001-L-Foot", front = 3, back = 140 },
      ["Bip001-R-Calf"] = { e = "Bip001-R-Foot", front = 3, back = 140 },
      ["Bip001-L-Forearm"] = { e = "Bip001-L-Hand", front = 145, back = 3 },
      ["Bip001-R-Forearm"] = { e = "Bip001-R-Hand", front = 145, back = 3 },
      ["Bip001-L-Thigh"] = { e = "Bip001-L-Calf", front = 110, back = 20, inward = 15, outward = 45 },
      ["Bip001-R-Thigh"] = { e = "Bip001-R-Calf", front = 110, back = 20, inward = 15, outward = 45 },
      ["Bip001-L-UpperArm"] = { e = "Bip001-L-Forearm", front = 120, back = 40, inward = 25, outward = 50 },
      ["Bip001-R-UpperArm"] = { e = "Bip001-R-Forearm", front = 120, back = 40, inward = 25, outward = 50 },
      ["Bip001-Spine1"] = { e = "Bip001-Spine2", front = 15, back = 8 },
      ["Bip001-Spine2"] = { e = "Bip001-Neck", front = 15, back = 8 },
      ["Bip001-Neck"] = { e = "Bip001-Head", front = 25, back = 15 },
    },                         -- inward / outward (shoulders, hips): how far it swings sideways towards her midline and away,
                               -- from the bind pose (the engine's +-45 round the A pose folded an arm into her chest, the
                               -- hips' +-30 crossed her legs)
    swing = {},                -- cone limits set outright, by joint
    collisionTable = true,     -- none of her bodies collide with each other, only the world: sbslice.dll fills the
                               -- asset's collision table (its "t"); without the DLL quietJiggle stands in
    armCollision = true,       --   but her arms collide with her hips, chest and thighs and with each other, and her
                               --   legs with each other (an arm went through her body in the ragdoll); a pair whose
                               --   bodies' shapes are within armGap cm
                               --   of each other as she goes limp is left out (overlapping bodies fling apart)
    breastCollision = true,    --   and her forearms and hands with her breasts' bodies (her hands sank into her chest)
    armGap = 2,
    pieceCollision = true,     --   and a cut-off arm, leg or head with the rest of her (it fell through her); the pairs
                               --   touching where she is cut are left out, as armGap
    weldKinematic = true,      -- every outfit: the joints of the bodies its asset makes kinematic (breasts, neck pieces,
                               -- arm twists, armour plates) are locked solid, so in the ragdoll they ride their bone
                               -- instead of buzzing against soft 0.1-1 deg limits
    quietJiggle = true,        -- the torso's jiggle bodies (breasts) collide with nothing: inside her chest they shoved
                               -- her arms and torso every frame and she buzzed on the floor
    lockLoose = true,          -- bodies with no joint (cape and skirt anchors) are locked to the body above them
    steady = true,             -- every outfit: solver iterations raised on every body, and the ends turn-damped (joints
    positionIterations = 16,   --   came apart and snapped back with the engine's 8 / 1: she was shot off at 10-23 m/s
    velocityIterations = 4,    --   and her hands and head spun at the cap for seconds)
    endsAngularDamping = { head = 2.0, hands = 3.0, feet = 3.0 },
    complete = true,           -- an asset missing main bodies (CH_P_EVE_21: no thighs) is swapped for completeWith: a
                               -- body-less thigh stayed on the hip while the cut calf flew, its clothes stretched
    completeWith = "/Game/Art/Character/PC/CH_P_EVE_InnerSuit/CH_P_EVE_InnerSuit_Physics.CH_P_EVE_InnerSuit_Physics",
    borrow = true,             -- a mesh with no physics asset (no ragdoll) gets <mesh>_Physics, else fallback
    fallback = "/Game/Art/Character/PC/CH_P_EVE_01/CH_P_EVE_01_Physics.CH_P_EVE_01_Physics",
  },
  deathMoves = true,           -- her body moving after death (convulse.lua's arm swings, struggle.lua; not the neck's;
                               -- settings.lua's deathMoves, F3 -> Death -> Death Struggle); her face and voice play
                               -- either way
  struggle = {                 -- struggle.lua: a maimed Eve fighting on the floor after a ragdoll death, as a run of
    enabled = true,            --   acts picked by what the cuts left her and how she lies (a hand on the stump,
                               --   a hand going out to the stump, rolling onto her front and crawling, trying to sit
                               --   or prop up, heels shoving her along with no arms, doubling over, lying still), over
                               --   her bleeding out: frantic, weakening, dying. Breathing and stump reflexes through
                               --   it. Ragdoll deaths with a limb cut off (rise.alone of those without), not beheaded,
                               --   split or cut at the waist
    strength = 1.0,            -- times every speed and strength below (settings.lua's struggle.strength)
    time = { 5, 8 },           -- s it lasts, from her coming to rest to her death (8-12 dragged on, playtest)...
    length = 1.0,              --   ...times this (F3 -> Struggle Length)
    startMax = 0.8,            -- s into the ragdoll it starts at the latest (else once she has come to rest; 2.5
                               --   came far too late, playtest)
    rate = 60,                 -- times a second she is steered at most
    animated = false,          -- an animated death's fall: maimed, she goes limp as she lies once it rests (a quiet
    quietWait = 0.4,           --   ragdoll: no blow, no momentum) and struggles from there, quietWait s later. Off:
                               --   the switch from the held end pose to a limp body looked wrong (playtest)
    log = true,                -- a log line for each act
    gain = 5,                  -- a joint turns at gain x the angle it is off by, deg/s, plus what the gap has summed
    hold = 8,                  --   to (hold x angle x s, at most holdMax: gravity and the floor take a steady share of
    holdMax = 200,             --   every turn, and without it a limb sagged short; 5/220/3000/0.08 barely moved her)...
    speed = 160,               --   ...at most this (320 with accel 6000 and a 1.3 surge looked frantic, playtest)
    accel = 2500,              -- deg/s^2 a joint's turn may change by at most (her muscles' strength: an arm held up
                               --   against gravity needs about 1400)
    response = 0,              -- s a joint takes to get to the speed asked (0: at once, each step)
    shake = 0.6,               -- cm the hand on a stump trembles
    wrist = 0.6,               -- times the strength her wrists are held in line with the forearm while an arm moves
                               --   (0: limp, as they flopped about before)
    reachMax = 0.88,           -- share of a limb's length its end is sent out to at most: the elbow or knee always a
                               --   little bent (0.97 reached with her arms straight as a mannequin's, playtest)
    drag = {                   -- a hand or foot planted and pulling (crawl, heels, scrabbling knees) moves her torso
      enabled = true,          --   along the floor up to speed cm/s, accel cm/s^2 at most: the floor's grip. Without
      speed = 35,              --   it every stroke swept the air and she stayed put (playtest)
      accel = 250,
    },
    bleed = {                  -- her strength over the struggle: 1 + surge at the start, falling off over the first
      frantic = 0.25,          --   frantic share, down to low by last, then to nothing as she dies (her acts slower as
      surge = 0.1,             --   she weakens: down to half the pace)
      low = 0.25,
      last = 0.85,             --   share in that she dies: last tremors, a last breath, her head rolling aside
    },
    weights = {                -- how likely each act is when she can do it (the same one again: x0.3, but the
      clutch = 3, reach = 1.5, --   clutch, crawl and push go on)
      turn = 0.8, crawl = 3,
      rise = 1, prop = 1,
      push = 3, curl = 0.5, lie = 0.6,
    },
    acts = {                   -- s each act takes at full strength (slower as she weakens)
      clutch = { 2, 3.5 }, reach = { 1.8, 2.5 }, turn = { 2, 2.8 }, crawl = { 2.5, 4 },
      push = { 2.5, 4 }, curl = { 1.0, 1.8 }, lie = { 0.6, 1.2 },
    },
    kick = {                   -- her legs drawing up and kicking out (clutching, reaching, turning), each on its own
      depth = { 0.3, 0.65 },   --   clock: how far up a knee comes (1: to her chest, a tuck that read as comic)
      held = { 0.7, 1.5 },     --   s it stays drawn up
      out = { 1.0, 2.2 },      --   s it stays out
    },
    reach = {
      within = 1.3,            -- a stump gone out to when it lies within this many of the hand's arm lengths (it
                               --   was a reach for the cut-off limb: not what people do)
      hover = 14,              -- cm in front of it the hand hovers before closing in and flinching back
    },
    roll = {                   -- her rolling about her length
      side = 55,               --   deg over towards her side in a clutch, the wound up (90: fully on her side)...
      rock = 25,               --   ...rocking back by up to this
      gain = 2.5, speed = 70, accel = 400,
    },
    rise = {                   -- trying to sit up (or prop up on an elbow), on her back: her belly curling her chest
      enabled = true,          --   and head up, shaking, feet braced, a groan, then giving out and dropping back
      alone = 0.5,             --   share of ragdoll deaths with no limb cut that do only this
      tries = { 1, 3 },        --   how many in one struggle, each weaker (x0.75)
      least = 0.4,             --   not once her strength has fallen below this
      time = { 1.0, 1.8 },     --   s each strains
      give = 0.4,              --   s letting go
      curl = 1.0,              --   times the curl: spine 20, chest 40, neck 60 deg forward (propping: 0.8 of it)
      power = 1.5,             --   times strength for the curl (her trunk is heavy)
      shake = 2,               --   deg the chest and neck shake at 8-11 Hz
    },
    push = {                   -- no arms: her heels shoving her along on her back
      bend = 0.55,             --   share of a push drawing the feet up (the rest driving them out)
      press = 10,              --   cm her heels press below her hips as they drive
    },
    breath = {                 -- her chest heaving
      enabled = true,
      depth = 4,               --   deg her chest tilts at full strength (a third of it as she fades)
      fast = 1.1,              --   s a breath at full strength...
      slow = 2.6,              --   ...and nearly gone
    },
    reflex = {                 -- a stump's stub jerking on its own: 1-2 jerks with a quiver, more often while strong
      enabled = true,
      speed = 80,              --   deg/s at a jerk's peak
      quiver = 15,             --   deg/s of 10-14 Hz quiver on it
    },
  },
  convulse = {                 -- convulse.lua: her body's last movements once she lies dead (ragdoll or her animated
    enabled = true,            --   fall's end pose): agonal spasms and gasps fading, a last gasp, then small twitches
    strength = 1.0,            -- times every movement's size
    jerk = 260,                -- deg/s a spasm turns a bone at its peak (a gasp about half, a late twitch a third)
    jolt = {                   -- a gasp jerks her whole body slightly (a ragdoll death; not beheaded or split, which
      enabled = true,          --   never gasp): a short upward pulse, the chest most, the head lagging, hips and arms barely
      lift = 1.2,              --   cm the chest comes up (her face's fade weakens it to about 0.6 of that; 2.5 was too deep, playtest)
      rise = 0.14,             --   s the pulse takes (the rest a little longer); then she falls back on her own
      last = 1.3,              --   her last gasp's, times lift
    },
    steer = false,             -- each movement steered to the speed it asks every tick (closed loop); off: each tick's
                               --   change of speed added, as the neck's struggle was made. The arm swings are steered
                               --   either way (open, they turned 0-10 deg of a swing, playtest)
    accel = 6000,              --   deg/s^2 a steered turn may change by at most each tick (gravity on a lifted arm
                               --   takes about 1500 deg/s^2)
    agonal = 4,                -- s of spasms (bursts of a leg kicking or an arm curling, her back arching, her head
                               --   jerking) and gasps; then her last gasp
    fade = 2,                  -- s the spasms take to weaken to about a third (and come further apart)
    duration = 8,              -- s from the first spasm to the last twitch (the death screen comes ~10 s in)
    faceAgonal = 2.5,          -- with body off (her face alone): s of winces and gasps before her last gasp
    faceDuration = 5,          --   and s to the last tic (8 ran on too long, playtest)
    blinks = 0.3,              --   chance a wince, gasp or tic in her first seconds comes with a blink (later ones
                               --   are slow blinks, slower as she goes)
    glances = 0.2,             --   chance her eyes dart a little aside and back with one (later: drift, smaller)
    body = false,              -- her body convulses too; off: it lies still and her face alone moves (winces with a moan,
                               --   gasps, a swallow, sobs, tics on one side, her jaw trembling or lip quivering, her
                               --   eyes rolling up, sighs, her eyelids fluttering)
    gasps = true,              -- gasps (her chest heaving, shoulders rising, jaw dropping); never once she is beheaded
    gaspGap = 1.5,             --   s at least between two
    face = true,               -- her face along (main.lua's death face): eyelids fluttering, the jaw on a gasp, winces
    faceJitter = 0.3,          --   each face movement's morphs scaled by up to this share either way (no two alike)
    faceOpen = 1.8,            --   how far her mouth drops open: times the morphs pulling it down (jaw_open, lowerLip_down,
                               --   wholeMouth_down); at 1 a gasp dropped her chin barely 1.4 cm, a wince's 0.5 cm
    faceIn = 0.8,              --   s the face's movements ease in over from the first one (it snapped from the death face
                               --   into a full wince as she came to lie still, playtest)
    startMax = 2,              -- s after her death they begin at the latest (else once she lies still); the first
                               --   spasm always has a moan
    animStartMax = 6,          -- the same for an animated fall, once its pelvis and head are both still (at 2 s the
                               --   neck's struggle took the head of a fall still playing and snapped it)
    settleAfter = 0.4,         -- s a ragdoll is kept awake after a movement, before it may settle again
    log = true,                -- a line per movement
    arms = false,              -- her arms jerk too (curls, hand and forearm twitches, the shoulders on a gasp); off:
                               --   they looked like the ragdoll glitching
    armSwing = {               -- her arm swinging (also with body off, beheaded or split): lifting slowly from the
      enabled = true,          --   shoulder and falling back, the elbow a beat later, the hand turning after it; now
      chance = 0.35,           --   and then back the other way. Share of her movements that are one (later: half)
      speed = 150,             --   deg/s at the shoulder's peak (the elbow 0.5-0.8 of it; at 150 and 300 the swings showed nothing
                               --   while they were impulses, which never landed: set as velocity now)
      time = { 0.7, 1.2 },     --   s each swing takes, speeding up and slowing down smoothly
      hand = 0.5,              --   the hand's turn, times speed
      back = 0.4,              --   share that swing back the other way before dropping
      crawl = 0.35,            --   share that are a crawl's stroke instead: reaching past her head, then dragging back
                               --   with the elbow bending and the hand clawing (the next most likely the other arm)
      late = 0.6,              --   size after her last gasp
    },
    voice = {                  -- her voice along, quiet: a breath with each gasp, now and then a moan with a spasm
      enabled = true,          --   (never once beheaded, never over her death cry)
      volume = 1.0,            --   times both below (settings.lua's convulse.voice.volume)
      breathVolume = 0.25,     --   (0.35 and 0.3 were too loud, playtest)
      moanVolume = 0.15,
      moanChance = 0.5,        --   share of spasms (bursts, her back arching) or winces with a moan
      gap = 1.2,               --   s at least between two
      breaths = { "vo_eve_cinematic_breath_01", "vo_eve_cinematic_breath_02", "vo_eve_cinematic_breath_03",
        "vo_eve_cinematic_breath_04", "vo_eve_cinematic_breath_05", "vo_eve_cinematic_breath_06",
        "vo_eve_cinematic_breath_07", "vo_eve_cinematic_breath_08", "vo_eve_cinematic_breath_09",
        "vo_eve_cinematic_breath_10" },
      moans = { "vo_eve_cinematic_dmg_01", "vo_eve_cinematic_dmg_02", "vo_eve_cinematic_dmg_03",
        "vo_eve_cinematic_dmg_04", "vo_eve_cinematic_dmg_05", "vo_eve_cinematic_endure_01",
        "vo_eve_cinematic_endure_02", "vo_eve_cinematic_endure_03" },
    },
    neck = {                   -- her neck muscles struggling (also with body off): her head straining to lift or
      enabled = true,          --   turn, shaking with the effort, giving out and dropping back, then sharp jerks of it
      chance = 0.3,            --   share of her face's movements that are one (later: half that, the strain weaker)
      strain = 110,            --   deg/s at the strain's peak (a slow push, `strainTime` s)
      strainTime = { 0.7, 1.3 },
      tremor = 55,             --   deg/s of the shaking over it, `hz` times a second, half of it crossways
      hz = { 7, 11 },
      jerk = 170,              --   deg/s of each jerk after it gives out (2-4, a quarter second apart, weakening)
      animScale = 0.35,        --   all of that in an animated death: its head simulates alone off an animated neck, nothing
                               --   holding it in her neck's range, and at full strength it bent ~70 deg, a snapped neck
    },
    animBody = false,          -- an animated death's end pose moves too (a limb, the head or an arm simulating for a
                               --   twitch); off: her face and voice only (the limbs flopping off the held pose looked
                               --   wrong, playtest), but a waist cut's upper body flying in the ragdoll still moves
    anim = {                   -- an animated death: the limb twitching simulates, held to her pose by a drive
      weak = 40,               --   its strength while the twitch runs
      strong = 600,            --   and after it, pulling the limb back to the pose
      damping = 0.15,          --   angular velocity drive, a share of the strength
      back = 0.3,              --   s pulled back before it is blended into the animation again
      blend = 0.15,            --   s of that blend
    },
  },
  active = {                   -- active.lua, real deaths and F7
    enabled = true,            -- false = the plain ragdoll the death show makes
    animated = true,           -- stand and light-hit deaths play her own fall (the death show's animation) and
                               -- hold its end pose; cuts happen on it, the cut piece falls by physics. A waist cut,
                               -- a split, heavy hits, explosions, airborne and ledge deaths stay ragdolls. false =
                               -- every death a ragdoll (the death shows' own key still fires, just not muted)
    fallRagdoll = true,        -- a fall damage death is a ragdoll (false: the stand death's animated fall, as the game)
    landDrop = 400,            -- a death within landWindow s of landing from a drop of this many cm is a ragdoll, not
    landWindow = 2.0,          -- the animated stand death (a minor fall itself leaves her at 1 HP, as the game does)
    deathFreeze = true,        -- an animated death's pose held from its start till the cut is chosen, and through a
                               -- split till it ragdolls (she turned round in her fall before the cut came)
    animatedPool = false,      -- an animated death picks its fall at random from her death show's own and 8 made
                               -- from her knockdown falls (the knockdown itself is untouched); false = her own only
    massScale = 1.0,           -- times the built-in human masses (~60 kg); the outfits ship 100 kg chest bodies
    accessoryMaxKg = 0.8,      -- cap for every other body (cape, hair, jiggle, accessories), so they trail behind
    accessoryShare = 0.15,     -- all the accessories hanging off one body part weigh at most this share of it
                               -- (the cape's 8 bodies a side hang off the upper arm, the hair's 9 off the head:
                               -- heavier, they pulled both out of their joints)
    accessoryMinKg = 0.05,     -- ...but none lighter than this
    capeHang = true,           -- in a ragdoll a cape hung off the upper arms (CH_P_EVE_09's two 7-link chains) hangs
                               -- off the shoulder instead, so the flailing arm doesn't drag and tear it
    capeKg = 0.12,             -- each of its links then weighs this (they hang off the 1.4 kg clavicle, not the arm)
    capeSwing = 45,            -- degrees the cape swings at the shoulder, each way
    capeTwist = 20,            -- degrees it turns about itself there
    jiggle = {                 -- Jiggle After Death (experimental, on by default): her breasts' bodies sway on a
      enabled = true,          --   damped spring of their own in the ragdoll instead of riding her chest locked
      swing = 12,              --   degrees each way they may swing from where they sat as she died
      twist = 6,               --   degrees they may turn about themselves
      stiffness = 600,         --   the spring back to there (higher: a quicker, tighter bounce)
      damping = 12,            --   how fast it settles (higher: less bounce, 0: it never stops)
      kg = 0.4,                --   what each weighs then
    },
    buzzLog = false,           -- log which bodies shake over a ragdoll's first 2 s (reads every body every tick)
    bisect = false,            -- buzz hunt: F7 / F11 ragdolls take turns at 1 as it is, 2 plain engine
                               --   ragdoll, 3 heavy accessories; each logs which bodies shake over its first 2 s
    momentum = 1.0,            -- share of her speed before death carried into the fall (0 = drops on the spot)
    momentumMax = 1500,        -- cm/s
    push = 1.0,                -- times impact and launch below: how hard her death throws her (0: none of ours)
    impact = 120,              -- cm/s extra push along the killing blow, spread over the upper body (deaths only;
                               -- from the attacker when the game gives no direction)
    impactUp = 0.15,           -- upward share of that push
    launch = 200,              -- cm/s her whole body is launched along the killing blow on top (deaths only): the
    launchUp = 0.2,            --   upper body's push alone toppled her on the spot, feet stuck to the floor; upward
                               --   share lifts her feet off it so she flies (0 = no launch; never on a split)
    launchTicks = 4,           --   ticks after the push every body on her is kept at least that fast along it
    twist = 35,                -- deg/s random turn about the vertical as she goes down (0 = none)
    dropWeapon = true,         -- her sword falls out of her hand (it hung in the air where she died)
    weaponKg = 1.5,            --   its weight
    weaponToss = 150,          --   cm/s it is thrown off on top of her hand's speed
    weaponCut = {              --   the killing blade through her sword (a blow she blocked) cuts it in two, each half
      enabled = true,          --   falling on its own
      reach = 80,              --   cm from the hit the blade's plane may cross it (40 missed one 52 cm off, by her thigh)
      ends = 0.08,             --   share of its length at either end that isn't cut (the tip, the pommel)
      breakAt = { 0.55, 0.68 }, --  the break, along it from the pommel: nearest the hit within these, on the bare blade
                               --   (at 0.3 it broke through the frame over the grip, both halves looking like a hilted
                               --   sword; at 0.40-0.45, where the frame ends, the blade came off whole, a whole sword
                               --   beside the hilt). A blocked blow, or one crossing it outside these, breaks it here
      across = 0.6,            --   a plane closer to the sword's length than this (|cos| of its normal to it, 0.6 = 37
                               --   deg) breaks it there too: it sliced it lengthwise, one half the whole sword still
      blockWindow = 0.5,       --   s: a killing blow this soon after her guard was up (guard key, montage or stance) breaks the sword
      guardKeys = { "E", "Gamepad_LeftShoulder" }, --   her guard keys, held (the game's input mappings read none)
                               --   whatever the plane did (across its middle when the plane missed it)
      apart = 60,              --   cm/s the halves are pushed apart along the plane's normal (120 threw the tip off fast)
      gap = 1.5,               --   cm each half's box stops short of the break (boxes meeting there pushed a half off)
      spin = 0.5,              --   their turn, a share of a thrown weapon's
    },
    grip = {                   --   a ragdoll death: the weapon in her hand rides with it, then slips out as her grip
      enabled = true,          --   eases (false: thrown off at once, as before)
      holdMin = 0.35,          --   s it is held at least
      holdMax = 0.9,           --   and at most (picked between)
      toss = 30,               --   cm/s on top of her hand's speed as it slips
      spin = 0.2,              --   its turn, a share of a thrown one's
      open = 0.8,              --   once the weapon is out of her hand, its fingers ease this far to the open hand (0: the
      openTime = 0.6,          --   fist stays), over this many seconds
    },
    weaponMaxCm = 120,         --   its box is never longer than this
    stiffness = 1.0,           -- how stiff her ragdoll is: times the tone's strength and resting share below (0: limp
                               --   from the start, 2-3: she keeps her shape, and lands without going limp)
    tone = {                   -- muscle tone: joints pulled towards the animated pose, fading out
      enabled = true,
      strength = 800,          -- drive strength at full tone (legs get ~40 %, so the knees go first)
      damping = 0.3,           -- angular velocity drive, as a share of strength (less flailing)
      hold = 0.35,             -- seconds at full strength
      fade = 2.5,              -- seconds to fade down to rest
      rest = 0.1,              -- share that stays until she settles: some stiffness, so she doesn't fold flat at
                               -- every joint like a sack (0 = fully limp)
      landOff = true,          -- tone off once she lands (her pelvis fell faster than fallSpeed cm/s, then slowed
      fallSpeed = 150,         --   under landSpeed): towards a standing pose on the floor every joint jittered
      landSpeed = 40,
    },
    neutral = {                -- the neutral pose: while her ragdoll flies, each joint below is pulled towards a relaxed,
      enabled = true,          --   curled body (knees and elbows bent, arms forward: a body's pose in free fall), so a
      stiffness = 250,         --   hard push doesn't throw her limbs out straight. Drives physfix.lua puts in her
      damping = 25,            --   physics asset (needs sbslice.dll's bind pose), on from the ragdoll's start
      most = 4,                --   s at most
      landOff = true,          --   off as she lands (as the tone's landOff), and as she settles
      pose = {                 --   degrees from the bind pose its far end swings towards her front (- her back) and
                               --   out (- in), as physfix.ranges count them; k: a share of the strength
        ["Bip001-L-UpperArm"] = { front = 30, out = 5, k = 0.6 }, ["Bip001-R-UpperArm"] = { front = 30, out = 5, k = 0.6 },
        ["Bip001-L-Forearm"] = { front = 70, k = 0.5 }, ["Bip001-R-Forearm"] = { front = 70, k = 0.5 },
        ["Bip001-L-Thigh"] = { front = 35, out = 5 }, ["Bip001-R-Thigh"] = { front = 35, out = 5 },
        ["Bip001-L-Calf"] = { front = -50, k = 0.7 }, ["Bip001-R-Calf"] = { front = -50, k = 0.7 },
        ["Bip001-Spine1"] = { front = 5 }, ["Bip001-Spine2"] = { front = 5 },
        ["Bip001-Neck"] = { front = 10, k = 0.5 },
      },
    },
    spin = {                   -- deg/s a body may turn at most: lying still, her head and hands shook at 500-5000
      enabled = true,          -- deg/s (thirteenth playtest), and anything cut off with them
      main = 720,              --   torso, arms and legs
      ends = 360,              --   head, hands, feet and every accessory body (hair, cape, jiggle)
      clamp = true,            --   enforced every tick as well (the engine's own cap didn't hold: 1000-8000 deg/s)
      splitMain = 360,         --   the same on a split's halves, which spun at up to 1000 deg/s as they fell
      splitEnds = 240,
      linear = true,           -- a main body flying off faster than her torso by more than linearOver cm/s (and
      linearOver = 1200,       --   faster than linearFloor) is slowed to that every tick (a hand shot off at 15000
      linearFloor = 1500,      --   cm/s, nineteenth playtest)
      launchTime = 0.5,        -- s: over the start every main body, torso too, is held to her momentum + impact +
      launchOver = 250,        --   launchOver cm/s (+ the fall since): a leg cut mid-fall shot her off at 16 m/s
    },
    fall = {                   -- a death in the air fell at a steady 2 m/s: from when her pelvis drops faster than
      enabled = true,          --   start cm/s until it slows under land cm/s, the bodies still on her are kept at
      start = 100,             --   least as fast downward as a free fall from then (gravity: share of it), up to
      land = 60,               --   max cm/s
      gravity = 1.0,
      max = 1500,
    },
    settle = {                 -- lying still: tone off and every body asleep, so she stops jittering on the floor
      enabled = true,
      after = 1.0,             -- not before this many seconds of ragdoll
      speed = 15,              -- cm/s: main bodies all slower than this, or...
      drift = 4,               -- cm: ...none of them got further than this over the last window (shivering in place)
      window = 0.5,            -- seconds the drift is measured over
      time = 0.5,              -- lying still this long (tone off from the start of it), then every body sleeps
      most = 2.5,              -- seconds: past this she settles once her bodies drift less than driftMost, however
      driftMost = 12,          --   fast they shiver (6 left CH_P_EVE_29's feet shaking on the floor for 6 s)
      splitMost = 1.5,         -- the same for a split's halves (they shivered on the floor for 3 s)
      wake = 60,               -- cm/s: something moved her this fast, she settles again
      air = 60,                -- cm: her pelvis higher than this over the floor never settles (she hung in mid-air)
    },
  },
  enemies = {                  -- gore on generic humanoid enemies, and the enemy spawner (enemies.lua; dev only)
    enabled = true,            -- false: no gore on them (the spawner still works)
    attackDown = true,         -- they attack her while she is knocked down (the game holds them till she is up)
    afterDeath = {             -- after her death the enemies around her keep at her as if she lived (the game drops her)
      enabled = false,
      time = 10,               --   seconds they keep at her
      reach = 3000,            --   cm: enemies within this of her
      swing = true,            --   an enemy near her body plays its own attacks at it (the game's skills don't fire
      swingReach = 450,        --   at a dead target); within this many cm of her body, lunging in to lunge cm
      lunge = 120,             --   off it as the swing starts (their trees stop them at their attack range)
      scanClear = 1500,        --   cm: the trees are looked up ahead (not in the death) when no enemy is this near her
    },
    grab = {                   -- a death in an enemy's grab (Raven holding her and hitting) waits for the grab to end:
      enabled = true,          --   a limb or the head the killing blow cuts falls off at once; her ragdoll, a split or a
      reach = 40,              --   cut across her waist come as it lets go (it came at once, and Raven went on hitting
      hold = 0.4,              --   thin air). Held: its hand within reach cm of her body (or her attached to it) for
      most = 6,                --   hold s; it lasts while its montage plays, without one (Raven's grab) while its hand
                               --   stays on her; waits at most `most` s
    },
    nativeSlice = false,       -- the game's own monster slicer on them (off: it hides parts its own way, on top of ours)
    reach = 2500,              -- cm from Eve: enemies further off are left alone (their hits aren't followed)
    cutChance = 1.0,           -- a kill near her takes something off
    bladeChance = 0.85,        --   ...along her swing (her right hand's arc) when she swung, else a rolled kind
    swingMinSpeed = 250,       -- cm/s her hand must reach to count as a swing
    swingWindow = 0.5,         -- seconds of her hand's path before the hit (else before its ragdoll) her swing is looked for in
    hitWindow = 1.0,           -- seconds a hit on its mesh is where the killing blow landed (moved onto its body when
                               -- the game put it off it)
    odds = { limb = 0.55, head = 0.3, torso = 0.15 }, -- a rolled kill (torso: across the waist; never a split)
    killWait = 2.0,            -- seconds a kill's cut waits for another cut to finish opening
    push = 0,                  -- cm/s every enemy death's ragdoll is pushed along the blow on top of the game's throw
    pushUp = 0.2,              --   upward share of it
    pushScale = 1.0,           -- times the game's own throw of a dying enemy (0: it drops on the spot; 2: twice as far)
    capFade = 1.5,             -- seconds a dissolving corpse's caps and bone stubs shrink away over (0: gone at once)
    maxCorpses = 6,            -- cut corpses at once; past it a kill is left whole (each holds caps, effects and its
                               -- kind's collapsed helpers, which bend every live enemy of that kind near the cut)
    corpseHits = {             -- her swings through a corpse cut it again
      enabled = true,
      reach = 35,              -- cm her swing's plane passes from one of its parts...
      blade = 130,             --   ...within this many cm of her hand (her sword's reach)
      max = 4,                 -- per corpse
      from = 0.6,              -- seconds after the kill (the killing swing itself)
      gap = 0.5,               -- seconds between two of its hits (one cut a swing)
      cutChance = 0.7,         -- else a hit mark
    },
    spawnDistance = 450,       -- F5 / the window: cm in front of her, in a row spawnSpread cm apart, facing her
    spawnSpread = 160,
    spawnLift = 30,
    -- the kinds (Naytiba on the Bip001 skeleton, each cut offline on its mesh: native/sbslice/test/real, ENEMY=1):
    -- alias (CharacterTable row), id (its ID), bp (its Blueprint, CharacterAppearanceTable). Not here: the
    -- hunchbacks (no Bip001 spine), the VIP guard (its head only knows hair bones: the face vanished)
    kinds = {
      { alias = "M_SkullSword", label = "Skull, sword", id = 50170, bp = "/Game/Art/Character/Monster/CH_M_NA_17/BluePrints/CH_M_NA_17_Blueprint" },
      { alias = "M_SkullSpear", label = "Skull, spear", id = 50180, bp = "/Game/Art/Character/Monster/CH_M_NA_18/BluePrints/CH_M_NA_18_Blueprint" },
      { alias = "M_SkullHammer", label = "Skull, hammer", id = 50160, bp = "/Game/Art/Character/Monster/CH_M_NA_16/BluePrints/CH_M_NA_16_Blueprint" },
      { alias = "M_SkullGunner", label = "Skull, gunner", id = 50190, bp = "/Game/Art/Character/Monster/CH_M_NA_19/BluePrints/CH_M_NA_19_Blueprint" },
      { alias = "M_LabMutant", label = "Lab mutant", id = 50350, bp = "/Game/Art/Character/Monster/CH_M_NA_35/Blueprints/CH_M_NA_35_Blueprint" },
      { alias = "M_StatueA", label = "Statue A", id = 50400, bp = "/Game/Art/Character/Monster/CH_M_NA_40/BluePrints/CH_M_NA_40_Blueprint" },
      { alias = "M_StatueB", label = "Statue B", id = 50401, bp = "/Game/Art/Character/Monster/CH_M_NA_40/BluePrints/CH_M_NA_40_Type_B_Blueprint" },
      { alias = "M_StatueC", label = "Statue C", id = 50402, bp = "/Game/Art/Character/Monster/CH_M_NA_40/BluePrints/CH_M_NA_40_Type_C_Blueprint" },
      { alias = "M_LurkerA", label = "Lurker A", id = 50450, bp = "/Game/Art/Character/Monster/CH_M_NA_45/Blueprints/CH_M_NA_45_Blueprint" },
      { alias = "M_LurkerB", label = "Lurker B", id = 50452, bp = "/Game/Art/Character/Monster/CH_M_NA_45/Blueprints/CH_M_NA_45_Type_B_Blueprint" },
      -- the Airborne Squad (the angels of the endings): Eve's skeleton, physics and a face mesh of their own (face:
      -- cut with her rules, the face goes with the head). Passive NPCs, unhurt by her blows: the spawner's Kill nearest
      -- (End) drops them
      { alias = "N_AirborneSquad", label = "Airborne Squad angel", id = 30030, face = true, bp = "/Game/Art/Character/NPC/CH_NPC_AirborneSquad/Blueprints/CH_NPC_AirborneSquad" },
    },
  },
  bosses = {                   -- Sandbox Bosses (bosses.lua, F3 → Sandbox): humanoid bosses spawned and killed like any enemy
    enabled = false,           -- off by default: while on, a boss you spawn is mortal (its CharacterTable row changed in game)
    pick = "tachy",            -- the one Spawn Boss makes (a kinds key)
    hpScale = 0.25,            -- its MaxHP and MaxShield times this (1: the game's)
    deadAs = "M_SkullSword",   -- the death rows it dies by (CharacterDeadTable: the common deaths, each with a ragdoll)
    despawn = 120,             -- s its corpse stays at least (Raven's went after 1 s)
    zeroKill = true,           -- one still up with its HP at 0 is taken down (the mod's kill; its phases' floors are off
                               --   while one of yours is up, so the game's own death comes first)
    zeroWait = 1.5,            --   s its HP (unread: the boss bar, hit in the last 10 s) may read 0 with it still up
    barReach = 3000,           --   cm: only one this near her is taken for the one the bar shows
    passive = false,           -- one spawned here stands still and never attacks (its AI stopped), for cutting at will
    struggle = true,           -- its death struggle on the floor (struggle.lua's, with Death Struggle on)
    face = true,               -- a dead face held on its face mesh (with Death Expression on)
    -- each: key (pick), alias, label, CharacterTable ID and row, its Blueprint, face (cut with Eve's rules: the face
    -- goes with the head), distance (cm in front of her). All on Bip001 skeletons Eve's cuts know (Scarlet on hers)
    kinds = {
      -- (physics: its body's physics asset as the game has it, put back over an outfit mod's: bosses.lua own_physics)
      { key = "tachy", alias = "B_Tachy", label = "Tachy (boss)", id = 50210, row = "M_Tachy", face = true, distance = 700,
        bp = "/Game/Art/Character/Monster/CH_M_NA_21/Blueprints/CH_M_NA_21_Blueprint",
        physics = "/Game/Art/Character/Monster/CH_M_NA_21/CH_M_NA_21_Body_Physics" },
      { key = "raven", alias = "B_Raven", label = "Raven (boss)", id = 50530, row = "M_Raven", face = true, distance = 700,
        bp = "/Game/Art/Character/Monster/CH_M_NA_53/Blueprints/CH_M_NA_53_Blueprint" },
      { key = "scarlet", alias = "B_Scarlet", label = "Scarlet (boss, DLC)", id = 59610, row = "M_Scarlet", face = true, distance = 700,
        bp = "/Game/DLC_2/Art/Character/Monster/CH_M_NA_961/Blueprints/CH_M_NA_961_Blueprint" },
      -- the Royal Guard Sister (the Wasteland's Royal Guard fight: M_RoyalGuardFemale, an elite immortal as the bosses
      -- are; her actor is Rael's, CH_NPC_Rael, on Bip001 with a face mesh of its own)
      { key = "royalguard", alias = "B_RoyalGuard", label = "Royal Guard Sister", id = 50500, row = "M_RoyalGuardFemale", face = true,
        distance = 600, bp = "/Game/Art/Character/NPC/CH_NPC_Rael/Blueprints/CH_NPC_Rael_Blueprint",
        physics = "/Game/Art/Character/NPC/CH_NPC_Rael/CH_NPC_Rael_Physics" },
    },
  },
  stains = {                   -- blood and dirt on her (stains.lua): the game's own, cut before release, switched on again
    enabled = false,           -- (parked: off, its F3 tab hidden) off: none, her materials as the game has them
    scale = 1,                 -- all the blood below times this
    max = 1,                   -- the most blood or dirt she takes (0-1)
    hit = { base = 0.04,       -- a hit that takes HP: this much blood,
      perHp = 0.9 },           --   and this times the share of her HP bar it took
    splash = { enabled = true, -- enemies hit near her splash her
      range = 350,             --   within this many cm (less the further off)
      amount = 0.04,           --   a hit on one right beside her
      cut = 0.12 },            --   a part cut off one (enemy gore)
    death = { blood = 0.35,    -- her death: this much blood at once,
      perCut = 0.15 },         --   and this for each part cut off her
    dirt = { enabled = true,   -- dirt from landings, knockdowns and lying dead
      land = 0.15,             --   a hard landing (past landSpeed cm/s down; more the harder)
      landSpeed = 900,
      knock = 0.12,            --   a knockdown
      death = 0.6,             --   lying dead it rises to this,
      rate = 0.08 },           --   this much a second
    wash = { enabled = true,   -- swimming washes blood and dirt off (wounds stay, paler)
      rate = 0.35 },           --   this much a second
    rest = true,               -- a camp rest cleans her and heals the wounds
    fade = 0,                  -- minutes for blood and dirt to fade by themselves (0: they stay till washed or rested)
    wounds = { enabled = true, -- a hit she lives through leaves a wound where it landed, in her skin's own blood layer
      size = 6,                --   cm across the wound's core (bigger for harder hits)
      uvCm = 150,              --   cm of her skin over the whole texture, about (sizes the wounds on the mask)
      splatter = 8,            --   drops round each wound
      background = 0.8,        --   the game's own blood mask under the wounds (0-1: lower, the blood spreads from
                               --   the wounds longer before it shows elsewhere)
      res = 512,               --   the skin's wound mask (px; a render target a wounded skin slot)
      floor = 0.35,            --   the blood offset a wounded skin material keeps however clean she is (the wounds show)
      color = { 0.2, 0.012, 0.01 }, -- a painted wound's colour (paintMasters' skin, linear RGB): the skin's goes toward it
      max = 24 },              --   wounds kept on one material, the oldest goes first
    cloth = { enabled = true,  -- blood on her outfit (painted into its colour where it lands) and dirt (darker, greyer)
      soak = 1.6,              --   blood on cloth spreads this many times wider than on skin
      bloodColor = { 0.2, 0.012, 0.01 }, -- fully soaked cloth's colour (linear RGB): the cloth's goes toward it
      levels = { 0.15, 0.3, 0.45, 0.6, 0.8, 1 }, -- the strengths a mark on it is drawn at (one blob each)
      res = 2048,              --   its colour texture copied at up to this size (px; a render target a stained slot)
      format = 3,              --   the render target's format (3: RGBA8 sRGB)
      coat = { enabled = true, --   blood over all of it as hers rises, the way the game's own layer covers her skin suit
        strength = 0.85,       --     how far the cloth's colour goes to blood's where it's covered (0-1)
        tile = 4,              --     the blood's pattern (the game's own noise) repeated this many times over its UV (4: as the skin suits' BloodTile)
        from = 1.05, to = 0.2, --     the noise level it shows from at no blood and at full (lower: more of it)
        soft = 5,              --     its edges' sharpness
        step = 0.08,           --     redrawn when the blood moves this much
        res = 512 },           --     the pattern's size (px)
      darken = 0.45, desaturate = 0.35, tint = 0.5, dirtTint = { 0.62, 0.52, 0.4 } }, -- dirt on it
    sound = { enabled = true,  -- a wet blood sound on each wound (the game's blood cues; none with gore.sounds off)
      volume = 0.7 },          --   times gore.soundVolume
    spatter = { enabled = true, -- blood lands on her as drops (skin or cloth) under points round her parts
      size = 1.5,              --   cm across a drop, about
      minPx = 2.5,             --   a splatter drop's radius at least this many px on the texture (smaller ones came out pixelated)
      perBlood = 40,           --   drops for a whole blood's worth splashed on her (enemy hits near her)
      hit = 3,                 --   drops round each wound of hers
      death = 14, perCut = 6,  --   at her death, and for each part cut off her
      menu = 12,               --   the menu's Add Blood
      perTick = 1,             --   skin queries a tick (0.1 s) for them
      queue = 40, max = 60 },  --   drops waiting at most; drops kept on one material (the oldest go first)
    skinMasters = { "MA_Skin", "MA_CH_P_EVE_34_BB" }, -- her skin's masters whose blood layer shows (her head, the skin suits)
    paintMasters = { "MA_Skin_EVE", "MA_Skin_EVE_Ver02", "MA_HumanSkin_Ver01" }, -- her skin's masters whose blood layer
                               -- doesn't show on her body (playtest: none at full blood): wounds painted into its colour
    matEvery = 0.5,            -- s between her materials' updates (at once on a wound)
  },
  glassCannon = {              -- realistic glass cannon (glass.lua); Page Down turns it on and off in game (dev only)
    enabled = false,           -- off by default
    shieldGuard = true,        -- while her shield is up a hit takes the shield, never HP; with it down any hit kills
    barDrop = 0.002,           -- her HP bar dropping more than this since the last tick is a hit with the shield down: she dies
    damageMult = 8,            -- what enemies near her lose (HP and shield) is multiplied by this
    foeReach = 4000,           -- cm: enemies this near her get it
    reach = 60,                -- cm: the enemy weapon's step passing this near a part of her landed there
    swingBack = 0.45,          -- s of the weapon's trail looked back over at a hit
    meshHitWindow = 0.6,       -- s: else her mesh's hit this recent says where
    deathWait = 0.3,           -- s: HP 0 not taken as a death by then, the game's ActorDead is called; as long again, the mod's own death
  },
}
