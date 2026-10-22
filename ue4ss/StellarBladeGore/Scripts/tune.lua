-- Sandbox tuning, re-read on F6 (no restart). Applies to F7 test ragdolls; the collision switches also
-- apply to real deaths.
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
  recoverAfter = 9,            -- seconds of ragdoll before the script gets her up (the death screen, 8 s in, covers it)
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
      limb = 30,               --   the arm or thigh nearest the hit comes off
      head = 30,               --   beheaded (the face goes with the head, the neck gets a stump)
      torso = 30,              --   cut in half at the waist
      split = 10,              --   cut in half top to bottom along the blade; only counts when the killing blow
                               --   came down from above (else the others are rolled)
    },
    bladeChance = 0.85,        -- a death whose killing hit the game reported cuts along that blade: the neck
                               -- (beheading), the body in two along the blade's plane, or the limb it crosses;
                               -- otherwise (and without a reported hit) the odds above are rolled
    deathSplit = true,         -- a blade down her length at death splits her (false: the limbs it crosses come off
                               --   instead, else the odds above; F11 and F5 still split)
    multiCut = {               -- one killing swing cuts every arm and leg (and the neck) its plane crosses within
      enabled = true,          --   reach cm of the hit, at most max cuts, one after the other
      reach = 40,
      max = 3,
      body = true,             -- an arm it took first (raised to block) doesn't stop it: where its plane goes on
      bodyReach = 60,          --   through her spine within bodyReach cm of the hit, her body is cut too
    },
    bladeSplit = 0.2,          --   share of those blades through her body that split her in two (else the odds above
                               --   are rolled): a blade made up for a death the game reported no hit for always
                               --   crossed the spine, so every real death was a split
    bodyBias = 0.5,            -- share of killing blades that would take an arm or leg that take the head or cut her
                               --   across the waist instead (by the head : torso odds above); enemy swings mostly
                               --   cross a limb, so beheadings and waist cuts were rare (0 = the blade decides)
    sliceTilt = 50,            -- a limb cut along a blade leans with it at most this many degrees off square
    limbReach = 12,            -- a blade meeting an arm or leg this close to the hit, with the hit
    spineReach = 15,           --   further than this from the spine, takes that limb (else the plane decides)
    splitDown = 0.6,           -- how steeply a swing must come down to split (share of its direction pointing down)
    weaponSwing = true,        -- the killing blade follows the nearest enemy's weapon (its weapon bones by name, else
                               --   its hands), sampled every tick while she lives; false: a made-up swing
    swingReach = 500,          --   cm: the enemy followed is the nearest this close
    swingWindow = 0.6,         --   seconds of its weapon kept; the fastest step in them is the killing swing
    swingMinSpeed = 300,       --   cm/s it must reach to count (slower: the made-up swing)
    swingSnap = 30,            --   cm: a plane passing her this close stays where the weapon put it (further: moved
                               --   onto the part of her nearest it, at the same angle)
    swingBones = 8,            --   most weapon bones followed per enemy
    attackerIgnore = { "Drone", "CH_P_", "AirborneSquad" }, -- class names (parts) never taken for her killer: her drone, playable characters, the passive angels
    legRagdoll = true,         -- a leg cut on her own death fall switches to the ragdoll first (she can't fall on it)
    deathFace = {              -- a dead face held on her face mesh's morph targets from `at` s into a death, faded in
      enabled = true,          --   over `fade` s, until she gets up (the game's own death face was gone 1 s in and
      at = 0.3,                --   her eyes stayed open). Shift+F7 shows it on her living face for 3 s
      fade = 0.5,
      morphs = {               --   { JALI morph, its ARKit twin, weight }: the first one her face mesh has is used
        { "upLid_down_L", "eyeBlinkLeft", 1.0 },          -- eyes shut
        { "upLid_down_R", "eyeBlinkRight", 1.0 },
        { "jaw_open", "jawOpen", 0.15 },                  -- mouth slack
        { "lipCorner_down_left", "mouthFrownLeft", 0.3 },
        { "lipCorner_down_right", "mouthFrownRight", 0.3 },
        { "brow_in", "browInnerUp", 0.25 },               -- a last wince
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
    splitSpine = true,         -- a split down her length shows the spine halved along each lid (GM_Brokenbone pieces)
    splitSpineWidth = 3.0,     --   cm wide in the plane
    splitSpineFlat = 1.2,      --   cm thick out of it
    splitBeside = 2,           -- cm beside her neck an F11 / F5 / odds split passes (leaning from her crotch up, between
                               --   her breasts), so the head stays whole on one half; 0 = straight up her spine through
                               --   the head. At 10 it ran through a breast
    splitMinShare = 0.12,      -- a split leaving either half less than this share of her body is a waist cut instead
    splitLidGrow = 0.4,        -- cm a split's flat lid reaches past the skin round its edge
    splitLidPush = 0.2,        -- cm it sits out of the half, over the flattened skin
    splitLidSkin = true,       -- the lid in one piece that bends with her spine (false: a rigid piece per spine bone,
                               --   which cracked into shards as she bent)
    splitLidFollow = 12,       -- seconds the bending lid follows her (then it stays as it lies)
    probes = false,            -- diagnostics after a split or limb cut: the stretch probe (skins every vertex on the
                               --   CPU at 0.5 and 2 s, a stutter of its own) and the helper drift
    slowMs = 15,               -- a split stage or sbslice command taking this long is logged (stutter hunt)
    splitAnim = 0,             -- a split on her death fall (tune.active.animated): both halves play on with the fall for
                               -- this many seconds, then come apart by physics at the speed it had. 0 = no fall: she
                               -- ragdolls at once, held still while it is cut, and comes apart
    bone = "auto",             -- "auto" = the roll above, or always one of: Bip001-Head, Bip001-Spine1,
                               -- Bip001-L/R-UpperArm, Bip001-L/R-Forearm, Bip001-L/R-Thigh, Bip001-L/R-Calf
    cutAt = "auto",            -- where along the limb, 0 = joint, 1 = next joint; "auto" = 0.4 (torso 0.5, the neck
                               -- 0.3 of the way to the head; a blade's cut at least 0.3 down the limb)
    hitMarks = {               -- a hit she lives through leaves a slash of blood on her skin (no cut): a decal
      enabled = true,          --   on the skin where it landed (the DLL finds it), along the swing, riding that skin's
                               --   bone. F10 puts one on a part at random. false = living hits leave nothing
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
      rest = 8,                --   s a recording rests before it can play again
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
    pieceGravity = 0.55,       -- share of gravity a cut-off arm or leg falls with, for its first pieceFloat s (1 = full:
    pieceFloat = 3,            --   it dropped like a stone)
    throwTicks = 3,           -- ticks after a cut the piece is kept at least as fast as its throw (the throw went in
                               --   the tick its bodies started simulating and was mostly lost)
    splitFly = 200,            -- cm/s both halves of a death split fly with, the way the blow went
    caps = true,               -- flesh caps over both openings
    capScale = 1.05,           -- cap size relative to the opening's outline (1 = ends exactly on the skin)
    boneStubs = true,          -- a snapped bone (the game's GM_Brokenbone) in each limb and neck stump
    stubBone = 0.3,            --   its thickness, as a share of the opening's width
    stubOut = 0.5,             --   how far it sticks out, times the opening's narrow radius
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
    debugCaps = false,         -- every cap and lid glows bright green (a test: are the split's shards lids or skin?)
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
  physfix = {                  -- physfix.lua: an outfit the data mod didn't patch (an outfit mod it didn't see)
    enabled = true,            -- false = leave such an outfit's physics as it ships
    linearDamping = 0.2,       -- the main bodies' damping, as the data mod sets it (vanilla 5.0: she falls slowly)
    angularDamping = 1.0,      --   (vanilla 10: she turns as if under water)
    hardLimits = true,         -- the main joints' limits stop dead instead of giving way
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
  active = {                   -- active.lua, real deaths and F7
    enabled = true,            -- false = the plain ragdoll the death show makes
    animated = true,           -- stand and light-hit deaths play her own fall (the death show's animation) and
                               -- hold its end pose; cuts happen on it, the cut piece falls by physics. A waist cut,
                               -- a split, heavy hits, explosions, airborne and ledge deaths stay ragdolls. false =
                               -- every death a ragdoll (the death shows' own key still fires, just not muted)
    animatedPool = false,      -- an animated death picks its fall at random from her death show's own and 8 made
                               -- from her knockdown falls (the knockdown itself is untouched); false = her own only
    massScale = 1.0,           -- times the built-in human masses (~60 kg); the outfits ship 100 kg chest bodies
    accessoryMaxKg = 0.8,      -- cap for every other body (cape, hair, jiggle, accessories), so they trail behind
    accessoryShare = 0.15,     -- all the accessories hanging off one body part weigh at most this share of it
                               -- (the cape's 8 bodies a side hang off the upper arm, the hair's 9 off the head:
                               -- heavier, they pulled both out of their joints)
    accessoryMinKg = 0.05,     -- ...but none lighter than this
    buzzLog = false,           -- log which bodies shake over a ragdoll's first 2 s (reads every body every tick)
    bisect = false,            -- buzz hunt: F7 / F11 ragdolls take turns at 1 as it is, 2 plain engine
                               --   ragdoll, 3 heavy accessories; each logs which bodies shake over its first 2 s
    momentum = 1.0,            -- share of her speed before death carried into the fall (0 = drops on the spot)
    momentumMax = 1500,        -- cm/s
    impact = 200,              -- cm/s extra push along the killing blow, spread over the upper body (deaths only;
                               -- from the attacker when the game gives no direction)
    impactUp = 0.15,           -- upward share of that push
    twist = 35,                -- deg/s random turn about the vertical as she goes down (0 = none)
    dropWeapon = true,         -- her sword falls out of her hand (it hung in the air where she died)
    weaponKg = 1.5,            --   its weight
    weaponToss = 150,          --   cm/s it is thrown off on top of her hand's speed
    weaponMaxCm = 120,         --   its box is never longer than this
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
      launchOver = 400,        --   launchOver cm/s (+ the fall since): a leg cut mid-fall shot her off at 16 m/s
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
      most = 3,                -- seconds: past this she settles once her bodies drift less than driftMost, however
      driftMost = 6,           --   fast they shiver
      splitMost = 1.5,         -- the same for a split's halves (they shivered on the floor for 3 s)
      wake = 60,               -- cm/s: something moved her this fast, she settles again
    },
  },
  enemies = {                  -- gore on generic humanoid enemies, and the enemy spawner (enemies.lua)
    enabled = true,            -- false: no gore on them (the spawner still works)
    nativeSlice = false,       -- the game's own monster slicer on them (off: it hides parts its own way, on top of ours)
    reach = 2500,              -- cm from Eve: enemies further off are left alone (their hits aren't followed)
    cutChance = 1.0,           -- a kill near her takes something off
    bladeChance = 0.85,        --   ...along her swing (her right hand's arc) when she swung, else a rolled kind
    swingMinSpeed = 250,       -- cm/s her hand must reach to count as a swing
    swingWindow = 0.5,         -- seconds of her hand's path kept
    hitWindow = 1.0,           -- seconds a hit on its mesh is where the killing blow landed
    odds = { limb = 0.55, head = 0.3, torso = 0.15 }, -- a rolled kill (torso: across the waist; never a split)
    killWait = 2.0,            -- seconds a kill's cut waits for another cut to finish opening
    maxCorpses = 6,            -- cut corpses at once; past it a kill is left whole (each holds caps, effects and its
                               -- kind's collapsed helpers, which bend every live enemy of that kind near the cut)
    corpseHits = {             -- her swings through a corpse cut it again
      enabled = true,
      reach = 35,              -- cm her hand passes from one of its parts
      max = 4,                 -- per corpse
      from = 0.4,              -- seconds after the kill (the killing swing itself)
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
  glassCannon = {              -- realistic glass cannon (glass.lua); Shift+F8 turns it on and off in game
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
