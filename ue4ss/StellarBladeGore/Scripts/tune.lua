-- Every knob of the mod, re-read on F6 (no restart). settings.lua overrides these key by key (the player's switches,
-- and dev: the test keys, the spawner and the glass cannon only work with it on). The top ones apply to F7 test
-- ragdolls; the collision switches also apply to real deaths.
return {
  push = 200,                  -- F7: cm/s the whole body is shoved (its centre of mass moves; 0 = none; 450 threw
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
  recoverAfter = 9,            -- seconds of ragdoll before the script gets her up (the death screen, 8 s in, covers it);
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
  deathScreen = "delay",       -- when the death screen comes up: "game" as the game puts it (at once), "delay" reviveAt
                               -- seconds into the death, "key" only on Shift+F4 (or holdPad). Shift+F4 shows it early,
                               -- and hides it again (the death held) once it is up
  hideHud = true,              -- the rest of the HUD (HP bar, skills, minimap, notices) hidden through a death, back as
                               -- she is up again; the death and revive screens keep to deathScreen
  keepFresh = 2,               -- s: a character or widget seen as it spawned is checked alive (sbslice "G") this soon, or
                               -- never held (characters are found again with FindAllOf)
  reviveAt = 7,                -- the death screen (and the revive item's) is held hidden this many seconds into the death
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
  cameraTrack = 2.5,           --   it slides sideways after her pelvis, never up or down, closing this share of the gap a
                               --   second (smoothed, so her ragdoll's shakes don't reach it; 0: it stays put)
  cameraMove = 400,            --   WASD, Q/E (down/up) and the left stick and triggers fly it this many cm a second
                               --   (once flown it stops sliding after her)
  cameraFast = 3,              --   this many times faster with Shift
  cameraRange = 1500,          --   no further than this many cm from where it started
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
    f5Split = true,            -- F5's test death always splits her top to bottom, at once (no death show plays: a
                               -- split never has a fall before it)
    f5Delay = 0.5,             --   with f5Split off: seconds into F5's fall the death starts (the show's ragdoll key
                               --   does nothing while she is alive, so the script starts it)
    death = {                  -- relative odds of what it does (every killing blow cuts, whatever hit her);
                               -- F9 rolls the cuts only, F10 marks, F11 splits
      limb = 42,               --   the arm or thigh nearest the hit comes off
      head = 25,               --   beheaded (the face goes with the head, the neck gets a stump)
      torso = 15,              --   cut in half at the waist
      split = 18,              --   cut in half top to bottom; rolled first on every death, whatever the blade
      moreLimbs = 0.35,        --   a limb cut takes another nearest limb with this chance, and a third with it again
    },                         --   (0.35: 35 % two or more, 12 % three)
    bladeFollow = 0.6,         -- share of deaths with a blade seen that the blade decides; the rest roll the odds above
                               -- (a blade mostly crosses her body: at 1 nearly every death was a waist cut or a split)
                               -- A death whose killing hit the game reported, or whose enemy's weapon swing was
                               -- seen, is otherwise decided by that blade alone, nothing rolled: what its plane goes through
                               -- comes off (the neck, her body along it or in two down her length, the arms and
                               -- legs it crosses); the odds above are rolled only without either
    bladeJitter = 15,          -- for variety, each blade is turned up to this many degrees at random
    bladeShift = 10,           --   and moved up to this many cm along its normal
    bladeTries = 4,            --   turns tried for a death that would take the same first part as the last one
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
      at = 0.3,                --   her eyes stayed open). Shift+F7 shows the moods in turn, 6 s each
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
      moods = {                --   one picked per death by weight (Shift+F7 shows them in turn); the same twice
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
    afterHits = {              -- an enemy's weapon swinging through her once she is dead cuts her again: a limb, the
      enabled = true,          --   head or (while she is whole) her body in two along the swing, else a hit mark
      reach = 35,              --   cm its fastest bone (a hand or weapon bone) passes from a part of her
      max = 6,                 --   hits a death
      from = 0.6,              --   s into the death before the first (the killing swing itself doesn't count twice)
      cutChance = 0.75,        --   share that cut (the rest leave a hit mark, see hitMarks)
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
                               -- opening: "z", "x", "-z", "-x" (F6 re-reads it; the "bleed: opening faces" log line
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
    pool = true,               -- floor blood: a cut's openings (F9, F11 too) drip while they move and pool where they rest
                               -- (without a cut: one pool under the body after 2 s)
    poolScale = 1.0,           --   pool size (a neck or thigh ~55-60 cm radius, a forearm 30, a split 90)
    poolGrow = 5,              --   seconds for a pool to reach most of its size (it keeps spreading slowly)
    poolTime = 12,             --   seconds each opening is followed
    dripEvery = 18,            --   cm between drips while it moves
    maxDecals = 60,            --   drips and pools in all
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
  convulse = {                 -- convulse.lua: her body's last movements once she lies dead (ragdoll or her animated
    enabled = true,            --   fall's end pose): agonal spasms and gasps fading, a last gasp, then small twitches
    strength = 1.0,            -- times every movement's size
    jerk = 260,                -- deg/s a spasm turns a bone at its peak (a gasp about half, a late twitch a third)
    agonal = 4,                -- s of spasms (bursts of a leg kicking or an arm curling, her back arching, her head
                               --   jerking) and gasps; then her last gasp
    fade = 2,                  -- s the spasms take to weaken to about a third (and come further apart)
    duration = 8,              -- s from the first spasm to the last twitch (the death screen comes ~10 s in)
    faceAgonal = 2.5,          -- with body off (her face alone): s of winces and gasps before her last gasp
    faceDuration = 5,          --   and s to the last tic (8 ran on too long, playtest)
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
      speed = 300,             --   deg/s at the shoulder's peak (the elbow 0.5-0.8 of it; 150 showed nothing, playtest)
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
    },
  },
  enemies = {                  -- gore on generic humanoid enemies, and the enemy spawner (enemies.lua; dev only)
    enabled = true,            -- false: no gore on them (the spawner still works)
    attackDown = true,         -- they attack her while she is knocked down (the game holds them till she is up)
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
      -- (Ctrl+F6) drops them
      { alias = "N_AirborneSquad", label = "Airborne Squad angel", id = 30030, face = true, bp = "/Game/Art/Character/NPC/CH_NPC_AirborneSquad/Blueprints/CH_NPC_AirborneSquad" },
    },
  },
  glassCannon = {              -- realistic glass cannon (glass.lua); Shift+F8 turns it on and off in game (dev only)
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
