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
    sliceOnDeath = true,       -- cut a limb off when she dies
    sliceChance = 1.0,         -- 0..1, per death
    bone = "auto",             -- "auto" = arm or thigh nearest the hit, or one of: Bip001-L/R-UpperArm,
                               -- Bip001-L/R-Forearm, Bip001-L/R-Thigh, Bip001-L/R-Calf, Bip001-Spine1
    allowTorso = false,        -- "auto" may also pick Bip001-Spine1 (cuts her in half)
    cutAt = "auto",            -- where along the limb, 0 = joint, 1 = next joint; "auto" = 0.15 (torso 0.5)
    tilt = 0.25,               -- random tilt of the cut plane
    throw = 250,               -- cm/s the severed piece gets, away from the body (0 = it just drops)
    caps = true,               -- flesh caps over both openings
    capScale = 1.05,           -- cap size relative to the opening's outline (1 = ends exactly on the skin)
    blood = true,              -- hit/cut/bleed effects
    sliceFx = false,           -- the game's flesh-slice burst at the cut: it drops a static meat stub made for
                               -- monster stumps, which hangs in the air where she was cut
    bleedTime = 2.5,           -- seconds both ends of the wound keep bleeding (0 = until she recovers)
    hitSplat = true,           -- blood decal under every hit
    pool = true,               -- blood pool under the body after 2 s
  },
}
