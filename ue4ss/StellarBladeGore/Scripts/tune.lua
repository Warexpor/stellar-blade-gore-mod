-- Sandbox tuning, re-read on F6 (no restart). Applies to F7 test ragdolls; the collision switches also
-- apply to real deaths.
return {
  push = 450,                  -- F7: cm/s the whole body is shoved (its centre of mass moves; 0 = none)
  impulse = 900,               --   cm/s the upper body gets on top (spread over chest, neck, head, arms; 0 = none)
  legKick = 550,               --   cm/s her feet (calves less) are swept the other way, so she goes over and lands on
                               --   her back with "back"
  direction = "back",          -- "back", "forward", "left", "right" of...
  relativeTo = "eve",          --   ..."eve" (her own facing) or "camera" (the camera's view)
  up = 0.1,                    -- upward share of the shove
  selfCollision = "auto",      -- "auto": on for physics assets the data mod fixed, off for vanilla ones
                               -- (vanilla overlaps Pelvis/Thigh at rest and flings her); true / false force it
  hairCollision = false,       -- true = SBHair keeps PhysicsOnly collision during the ragdoll
  massScale = 1.0,             -- SetAllMassScale on every body
  recoverAfter = 10,           -- seconds of ragdoll before the script gets her up (the death screen, 8 s in, covers it)
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
                               -- F9 rolls the cuts only, F10 dents, F11 splits
      limb = 50,               --   the arm or thigh nearest the hit comes off
      head = 25,               --   beheaded (the face goes with the head, the neck gets a stump)
      torso = 15,              --   cut in half at the waist
      split = 10,              --   cut in half top to bottom along the blade; only counts when the killing blow
                               --   came down from above (else the others are rolled)
    },
    bladeChance = 0.85,        -- a death whose killing hit the game reported cuts along that blade: the neck
                               -- (beheading), the body in two along the blade's plane, or the limb it crosses;
                               -- otherwise (and without a reported hit) the odds above are rolled
    bladeSplit = 0.2,          --   share of those blades through her body that split her in two (else the odds above
                               --   are rolled): a blade made up for a death the game reported no hit for always
                               --   crossed the spine, so every real death was a split
    sliceTilt = 50,            -- a limb cut along a blade leans with it at most this many degrees off square
    limbReach = 12,            -- a blade meeting an arm or leg this close to the hit, with the hit
    spineReach = 15,           --   further than this from the spine, takes that limb (else the plane decides)
    splitDown = 0.6,           -- how steeply a swing must come down to split (share of its direction pointing down)
    hitWindow = 0.6,           -- seconds before death the game's last hit on her still counts as the killing blow
    splitPush = 300,           -- cm/s the halves get away from each other
    splitTip = 250,            -- cm/s more on each half's upper body (Spine2 up), so a cut down her length falls open
    splitBleedDelay = 0.3,     -- seconds after a split opens before it bleeds (the halves come apart first)
    splitSpine = true,         -- a split down her length shows the spine halved along each lid (GM_Brokenbone pieces)
    splitSpineWidth = 3.0,     --   cm wide in the plane
    splitSpineFlat = 1.2,      --   cm thick out of it
    splitMinShare = 0.12,      -- a split leaving either half less than this share of her body is a waist cut instead
    splitLidGrow = 0.4,        -- cm a split's flat lid reaches past the skin round its edge
    splitLidPush = 0.2,        -- cm it sits out of the half, over the flattened skin
    splitAnim = 0,             -- a split on her death fall (tune.active.animated): both halves play on with the fall for
                               -- this many seconds, then come apart by physics at the speed it had. 0 = no fall: she
                               -- ragdolls at once, held still while it is cut, and comes apart
    bone = "auto",             -- "auto" = the roll above, or always one of: Bip001-Head, Bip001-Spine1,
                               -- Bip001-L/R-UpperArm, Bip001-L/R-Forearm, Bip001-L/R-Thigh, Bip001-L/R-Calf
    cutAt = "auto",            -- where along the limb, 0 = joint, 1 = next joint; "auto" = 0.4 (torso 0.5, the neck
                               -- 0.3 of the way to the head; a blade's cut at least 0.3 down the limb)
    woundScale = 1.0,          -- wound size; r = 6.5 cm on the torso, 5 thigh, 3.5 upper arm / calf
    bluntWound = "rupture",    -- a blunt blow: "rupture" bursts the skin (a crater under a ragged lid of torn flesh,
                               -- bleeding like a stab), "dent" presses it in smoothly (the older look)
    ruptureWidth = 0.9,        --   a rupture's radius, times r (torso 5.9 cm, upper arm 3.2)
    ruptureDepth = 0.5,        --   its crater's depth, times r
    bluntWidth = 1.8,          -- a dent is r times this wide (radius)
    bluntDepth = 0.7,          --   and r times this deep: a wide squash (upper arm 6.3 cm wide, 2.5 deep; torso
                               --   11.7 and 4.6)
    woundFlesh = true,         -- torn flesh (the cut-flesh material) at the bottom of a dent or stab
    woundFleshShare = 0.55,    --   a dent's patch, as a share of the dent's radius
    woundBleed = 0.6,          -- a dent bleeds for this share of bleedTime (a stab or a rupture for all of it), and
                               -- drips and pools like a cut (a small pool, 22 cm)
    stabWidth = 2.5,           -- a stab's pit: this radius in cm
    stabDepth = 0.6,           --   r times this deep (at most 4 cm)
    sounds = true,             -- the game's own gore sounds on cuts, splits and wounds
    soundVolume = 1.0,
    maxWounds = 6,             -- per life
    tilt = 0.25,               -- random tilt of the cut plane
    blowTilt = 35,             -- death cuts lean towards the killing blow's direction, at most this many degrees
                               -- off square (0 = always square to the limb)
    throw = 250,               -- cm/s the severed piece gets, away from the body (0 = it just drops)
    deathThrow = 650,          -- cm/s a piece cut off by a killing blow flies with, the way the blow went
    splitFly = 350,            -- cm/s the cut off half of a death split flies with, the way the blow went
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
    capMaterial = "/Game/Art/FX/MA/Enviroment/MI_A_Meat_01_1.MI_A_Meat_01_1", -- the flesh on caps, lids and wounds
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
  active = {                   -- active.lua, real deaths and F7
    enabled = true,            -- false = the plain ragdoll the death show makes
    animated = true,           -- stand and light-hit deaths play her own fall (the death show's animation) and
                               -- hold its end pose; cuts happen on it, the cut piece falls by physics. A waist cut,
                               -- a split, heavy hits, explosions, airborne and ledge deaths stay ragdolls. false =
                               -- every death a ragdoll (the death shows' own key still fires, just not muted)
    animatedPool = true,       -- an animated death picks its fall at random from her death show's own and 8 made
                               -- from her knockdown falls (the knockdown itself is untouched); false = her own only
    massScale = 1.0,           -- times the built-in human masses (~60 kg); the outfits ship 100 kg chest bodies
    accessoryMaxKg = 0.8,      -- cap for every other body (cape, hair, jiggle, accessories), so they trail behind
    accessoryShare = 0.15,     -- all the accessories hanging off one body part weigh at most this share of it
                               -- (the cape's 8 bodies a side hang off the upper arm, the hair's 9 off the head:
                               -- heavier, they pulled both out of their joints)
    momentum = 1.0,            -- share of her speed before death carried into the fall (0 = drops on the spot)
    momentumMax = 1500,        -- cm/s
    impact = 450,              -- cm/s extra push along the killing blow, spread over the upper body (deaths only;
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
    },
    spin = {                   -- deg/s a body may turn at most: lying still, her head and hands shook at 500-5000
      enabled = true,          -- deg/s (thirteenth playtest), and anything cut off with them
      main = 720,              --   torso, arms and legs
      ends = 360,              --   head, hands, feet and every accessory body (hair, cape, jiggle)
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
      wake = 60,               -- cm/s: something moved her this fast, she settles again
    },
  },
}
