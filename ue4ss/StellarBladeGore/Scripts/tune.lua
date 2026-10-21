-- Sandbox tuning, re-read on F6 (no restart). Applies to F7 test ragdolls; the collision switches also
-- apply to real deaths.
return {
  impulse = 1200,              -- cm/s velocity change on the impulse bone (0 = just go limp)
  bone = "Bip001-Spine1",      -- where the push lands
  direction = "back",          -- "back" (away from camera view), "forward", "left", "right"
  up = 0.15,                   -- upward share of the push direction
  selfCollision = "auto",      -- "auto": on for physics assets the data mod fixed, off for vanilla ones
                               -- (vanilla overlaps Pelvis/Thigh at rest and flings her); true / false force it
  hairCollision = false,       -- true = SBHair keeps PhysicsOnly collision during the ragdoll
  massScale = 1.0,             -- SetAllMassScale on every body
  recoverAfter = 6,            -- seconds of ragdoll before the script gets her up (death screen covers it)
  gore = {
    enabled = true,            -- false = no cutting, no blood (sbslice.dll stays idle)
    sliceOnDeath = true,       -- a killing blow leaves a mark (see death)
    sliceChance = 1.0,         -- 0..1, per death
    death = {                  -- relative odds of what it does; F9 rolls the cuts only, F10 dents, F11 splits
      limb = 45,               --   the arm or thigh nearest the hit comes off
      head = 20,               --   beheaded (the face goes with the head, the neck gets a stump)
      torso = 15,              --   cut in half at the waist
      wound = 20,              --   a blunt dent where the blow landed
      split = 10,              --   cut in half top to bottom along the blade; only counts when the killing blow
                               --   came down from above (else the others are rolled)
    },
    bladeChance = 0.85,        -- a death whose killing hit the game reported cuts along that blade: the neck
                               -- (beheading), the body in two along the blade's plane, or the limb it crosses;
                               -- otherwise (and without a reported hit) the odds above are rolled
    sliceTilt = 50,            -- a limb cut along a blade leans with it at most this many degrees off square
    faceSplitCm = 10,          -- a blade further than this from her head leaves the face whole
    limbReach = 12,            -- a blade meeting an arm or leg this close to the hit, with the hit
    spineReach = 15,           --   further than this from the spine, takes that limb (else the plane decides)
    splitDown = 0.6,           -- how steeply a swing must come down to split (share of its direction pointing down)
    hitWindow = 0.6,           -- seconds before death the game's last hit on her still counts as the killing blow
    splitPush = 120,           -- cm/s the halves get away from each other
    bone = "auto",             -- "auto" = the roll above, or always one of: Bip001-Head, Bip001-Spine1,
                               -- Bip001-L/R-UpperArm, Bip001-L/R-Forearm, Bip001-L/R-Thigh, Bip001-L/R-Calf
    cutAt = "auto",            -- where along the limb, 0 = joint, 1 = next joint; "auto" = 0.15 (torso 0.5, head
                               -- 0.5 under the neck joint, below the face)
    woundScale = 1.0,          -- dent size; r = 6.5 cm on the torso, 5 thigh, 3.5 upper arm / calf
    bluntWidth = 1.4,          -- a blunt dent is r times this wide (radius)
    bluntDepth = 0.45,         --   and r times this deep: a wide shallow squash
    stabWidth = 2.5,           -- a stab's pit: this radius in cm
    stabDepth = 0.6,           --   r times this deep (at most 4 cm)
    -- a killing hit whose attack group or show name holds one of these is a stab or a blunt blow (dents where it
    -- landed), anything else a blade; "hit on Eve (style)" log lines show the names to fit these to
    stabWords = { "stab", "thrust", "pierce", "sting", "spear", "lance", "drill", "needle", "spike", "impale" },
    bluntWords = { "punch", "smash", "bash", "slam", "stomp", "kick", "hammer", "tackle", "crush", "charge",
      "headbutt", "fist", "blunt", "rush" },
    maxWounds = 6,             -- per life
    tilt = 0.25,               -- random tilt of the cut plane
    blowTilt = 35,             -- death cuts lean towards the killing blow's direction, at most this many degrees
                               -- off square (0 = always square to the limb)
    throw = 250,               -- cm/s the severed piece gets, away from the body (0 = it just drops)
    caps = true,               -- flesh caps over both openings
    capScale = 1.05,           -- cap size relative to the opening's outline (1 = ends exactly on the skin)
    blood = true,              -- hit/cut/bleed effects
    sliceFx = false,           -- the game's flesh-slice burst at the cut: it drops a static meat stub made for
                               -- monster stumps, which hangs in the air where she was cut
    bleedTime = 2.5,           -- seconds both openings keep bleeding (0 = until she recovers)
    hitSplat = true,           -- blood decal under every hit
    pool = true,               -- blood pool under the body after 2 s
  },
  active = {                   -- active.lua, real deaths and F7
    enabled = true,            -- false = the plain ragdoll the death show makes
    massScale = 1.0,           -- times the built-in human masses (~60 kg); the outfits ship 100 kg chest bodies
    accessoryMaxKg = 0.8,      -- cap for every other body (cape, hair, jiggle, accessories), so they trail behind
                               -- (much lighter and they jitter against the heavy main bodies)
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
      rest = 0.15,             -- share that stays until she settles: some stiffness, so she doesn't fold flat at
                               -- every joint like a sack (0 = fully limp)
    },
    settle = {                 -- lying still: tone off and every body asleep, so she stops jittering on the floor
      enabled = true,
      after = 1.5,             -- not before this many seconds of ragdoll
      speed = 15,              -- cm/s: main bodies all slower than this...
      time = 0.5,              --   ...for this long
      wake = 60,               -- cm/s: something moved her this fast, she settles again
    },
  },
}
