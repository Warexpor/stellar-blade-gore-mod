-- convulse.lua: her body's last movements after death (tune.convulse). With tune.convulse.body off (the default) her
-- body lies still and her face alone moves (face_event): winces with a moan, gasps, a swallow, one-sided tics, her
-- jaw trembling, her lip quivering, sobs, her eyes rolling up, sighs, her eyelids fluttering, over the death face
-- main.lua holds; each pose in a few takes, jittered. With it on, the body as below.
--
-- A body doesn't go still the moment it dies: its muscles go on firing on their own for a while. First the agonal
-- spasms, fading over tune.convulse.agonal (4) seconds: bursts of jerks of one limb at a time (an arm curling, a leg
-- kicking straight with the foot pointed), her back arching with the head thrown back, her head jerking, and gasps
-- (the chest heaving, the shoulders rising, the jaw dropping). Then a last gasp, and after it only small twitches of a
-- hand, a foot or a calf, further apart, until tune.convulse.duration (8 s: the death screen comes about 10 s in).
-- Her eyelids flutter and her face winces with the spasms (main.lua's death face, M.face). A cut-off arm or leg
-- twitches on its own too. Beheaded (an instant death) her body convulses but never gasps, and her face stays as it
-- is (her cry is cut off as the head comes away: gore.lua's vox.cut).
--
-- Each movement is a muscle: a bone turned against its parent about the joint, its speed rising and falling over a
-- tenth of a second or so (a gasp, half a second), the parent turned back by the child's share of their mass, so she
-- moves herself and isn't pushed about. The joint's axis is the bone's own X when the movement runs about it (Bip001
-- limbs bend about X: elbows forward, knees back, the spine and head back, the foot down; checked on her bind pose),
-- else square to the bone and the way it should go.
--   * ragdoll: the bodies are moved as they lie (active.lua wakes her quietly and lets her settle again after)
--   * an animated death (her fall's held end pose): a forearm, hand, calf or foot simulates for its twitch, held to
--     the pose by a drive (weak during the twitch, strong after it) with its gravity off, then blended back into the
--     animation. Her back and head stay as the fall left them; she gasps with her face only.
-- Nothing moves while the game or photo mode is paused.

local M = {}
local ctx, try, valid
local function cfg() return ctx.tune.convulse or {} end
local function log(s) ctx.log("convulse: " .. s) end

local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local function add(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
local function sub(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
local function scale(a, k) return vec(a.X * k, a.Y * k, a.Z * k) end
local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function cross(a, b) return vec(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
local function norm(a)
  local l = math.sqrt(dot(a, a))
  return l > 1e-4 and scale(a, 1 / l) or nil
end
local function rnd(a, b) return a + math.random() * (b - a) end

-- per bone: its parent body (what it turns against) and the bone it points at (none: away from the parent)
local J = {
  ["Bip001-Spine1"] = { "Bip001-Spine", "Bip001-Spine2" },
  ["Bip001-Spine2"] = { "Bip001-Spine1", "Bip001-Neck" },
  ["Bip001-Head"] = { "Bip001-Neck" },
}
for _, s in ipairs({ "L", "R" }) do
  local b = "Bip001-" .. s .. "-"
  J[b .. "Clavicle"] = { "Bip001-Spine2", b .. "UpperArm" }
  J[b .. "UpperArm"] = { b .. "Clavicle", b .. "Forearm" }
  J[b .. "Forearm"] = { b .. "UpperArm", b .. "Hand" }
  J[b .. "Hand"] = { b .. "Forearm" }
  J[b .. "Thigh"] = { "Bip001-Pelvis", b .. "Calf" }
  J[b .. "Calf"] = { b .. "Thigh", b .. "Foot" }
  J[b .. "Foot"] = { b .. "Calf", b .. "Toe0" }
end
-- an animated death: the bones that may simulate for a twitch (each with what simulates with it), and the cuts that
-- leave such a chain a piece of its own (it simulates already, and is never put back on the animation)
local CHAIN, CUTS = {}, {}
for _, s in ipairs({ "L", "R" }) do
  local b = "Bip001-" .. s .. "-"
  CHAIN[b .. "Forearm"] = { b .. "Forearm", b .. "Hand" }
  CHAIN[b .. "Hand"] = { b .. "Hand" }
  CHAIN[b .. "Calf"] = { b .. "Calf", b .. "Foot", b .. "Toe0" }
  CHAIN[b .. "Foot"] = { b .. "Foot", b .. "Toe0" }
  local arm, leg = { b .. "Clavicle", b .. "UpperArm", b .. "Forearm", b .. "Hand" }, { b .. "Thigh", b .. "Calf", b .. "Foot" }
  CUTS[b .. "Forearm"], CUTS[b .. "Hand"], CUTS[b .. "Calf"], CUTS[b .. "Foot"] = arm, arm, leg, leg
end
-- her head (the neck's struggle): it simulates on its own, a beheading takes it
CHAIN["Bip001-Head"], CUTS["Bip001-Head"] = { "Bip001-Head" }, { "Bip001-Head" }
-- a waist cut whose legs play the fall on (gore.lua's torsoLegs): the arms and head went with the upper body, flying
-- in the ragdoll, and a twitch's blend back onto the animation would have snapped them onto her legs' fall
for _, b in ipairs({ "Bip001-Spine", "Bip001-Spine1", "Bip001-Spine2", "Bip001-Neck" }) do
  for root, list in pairs(CUTS) do if not root:find("Calf") and not root:find("Foot") then list[#list + 1] = b end end
end
-- the chain a hand's or foot's is part of (it simulates with the forearm's or calf's)
local INNER = {}
for _, s in ipairs({ "L", "R" }) do
  local b = "Bip001-" .. s .. "-"
  INNER[b .. "Forearm"], INNER[b .. "Calf"] = b .. "Hand", b .. "Foot"
end

-- the movements, a muscle each: { bone, where its far end goes, share of the jerk } ("front", "back", "up", "out"
-- (away from her middle), "in", "plantar" (along the parent: the foot pointing), "rand"); s is the side
local function arch() return {
  { "Bip001-Spine1", "back", 0.8 }, { "Bip001-Spine2", "back", 0.9 }, { "Bip001-Head", "back", 1.1 },
  { "Bip001-L-Forearm", "front", 0.5 }, { "Bip001-R-Forearm", "front", 0.5 },
} end
-- her arms (tune.convulse.arms): their jerks looked like the ragdoll glitching (playtest), off by default
local function arm_bone(b) return b:find("Clavicle") or b:find("Arm") or b:find("Hand") end
local function arms_on() return ctx.tune.convulse == nil or ctx.tune.convulse.arms == true end
local function kick(s) local b = "Bip001-" .. s .. "-"; return {
  { b .. "Calf", "front", 1.0 }, { b .. "Foot", "plantar", 1.0 }, { b .. "Thigh", math.random() < 0.5 and "front" or "back", 0.5 },
} end
local function curl(s) local b = "Bip001-" .. s .. "-"; return {
  { b .. "Forearm", "front", 1.0 }, { b .. "Hand", "rand", 0.9 }, { b .. "UpperArm", "in", 0.4 },
} end
local HEAD_WAYS = { "front", "back", "out", "in" }
local function head() return { { "Bip001-Head", HEAD_WAYS[math.random(4)], 1.0 } } end
local function gasp() return {
  { "Bip001-Spine2", "back", 0.35 }, { "Bip001-L-Clavicle", "up", 0.6 }, { "Bip001-R-Clavicle", "up", 0.6 },
  { "Bip001-Head", "back", 0.45 },
} end
local function small(s)
  local b = "Bip001-" .. s .. "-"
  local k = arms_on() and math.random(5) or ({ 2, 4, 5 })[math.random(3)]
  if k == 1 then return { { b .. "Hand", "rand", 1.0 } }
  elseif k == 2 then return { { b .. "Foot", "plantar", 1.0 } }
  elseif k == 3 then return { { b .. "Forearm", "front", 0.7 } }
  elseif k == 4 then return { { b .. "Calf", "front", 0.6 } }
  end
  return { { "Bip001-Head", HEAD_WAYS[math.random(4)], 0.4 } }
end

local st = nil -- this death: { pawn, mesh, t, onset, next, pulses, chains, faces, events, ... }

function M.init(c)
  ctx = c
  try, valid = c.try, c.valid
end

local function rag() return ctx.rag end
local function headless(mesh) local r = rag(); return r and r.severed(mesh, "Bip001-Head") end
-- split down her length (a vertical slash): her face stays and she makes no sound, as when beheaded
local function split(mesh)
  local g = ctx.gore
  return g and g.cuts_on and select(2, g.cuts_on(mesh)) == true
end
local function still(mesh) return headless(mesh) or split(mesh) end
local function loc(comp, b) return try(function() local v = comp:GetSocketLocation(FName(b)); return vec(v.X, v.Y, v.Z) end) end
local function xaxis(comp, b)
  return try(function()
    local q = comp:GetSocketTransform(FName(b), 0).Rotation
    local x, y, z, w = q.X, q.Y, q.Z, q.W
    return vec(1 - 2 * (y * y + z * z), 2 * (x * y + w * z), 2 * (x * z - w * y))
  end)
end
local function simulating(comp, b) return try(function() return comp:IsSimulatingPhysics(FName(b)) end) == true end

-- her frame on a component: up her spine, her right, her front
local function frame(comp)
  local p, n = loc(comp, "Bip001-Pelvis"), loc(comp, "Bip001-Neck")
  local up = p and n and norm(sub(n, p))
  if not up then return nil end
  local r = vec(0, 0, 0)
  for _, s in ipairs({ "Thigh", "UpperArm" }) do
    local a, b = loc(comp, "Bip001-L-" .. s), loc(comp, "Bip001-R-" .. s)
    if a and b then r = add(r, sub(b, a)) end
  end
  r = norm(sub(r, scale(up, dot(r, up))))
  if not r then return nil end
  return { up = up, right = r, front = cross(r, up) }
end

-- the angular velocity direction that turns bone b's far end towards `to`, or nil. floor: an animated death's chain,
-- whose bodies don't collide with the floor: a far end sent down into it goes the other way (her head, strained back
-- lying face up or front lying face down, sank into the floor and snapped back up onto the animation, playtest)
local function axis_of(comp, f, b, to, floor)
  local j = J[b]
  if not j then return nil end
  local at, par = loc(comp, b), loc(comp, j[1])
  local tip = j[2] and loc(comp, j[2])
  local d = at and (tip and norm(sub(tip, at)) or (par and norm(sub(at, par))))
  if not d then return nil end
  local t
  if to == "plantar" then t = par and norm(sub(at, par))
  elseif to == "rand" or not f then t = norm(vec(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)))
  else
    local side = b:find("%-R%-") and 1 or b:find("%-L%-") and -1 or (math.random() < 0.5 and 1 or -1)
    t = ({ front = f.front, back = scale(f.front, -1), up = f.up, down = scale(f.up, -1), out = scale(f.right, side),
      ["in"] = scale(f.right, -side) })[to]
  end
  if floor and t and t.Z < -0.35 then t = scale(t, -1) end
  local a = t and norm(cross(d, t))
  if not a then return nil end
  -- about the joint's own hinge when the movement runs about it
  local x = xaxis(comp, b)
  if x and math.abs(dot(x, a)) > 0.5 then a = dot(x, a) > 0 and x or scale(x, -1) end
  return a
end

-- ---- an animated death's chains: simulating for their twitch, then back on the animation ----
local function pac()
  if valid(st.pac) then return st.pac end
  local cls = try(function() return StaticFindObject("/Script/Engine.PhysicalAnimationComponent") end)
  local p = valid(cls) and try(function()
    return st.pawn:AddComponentByClass(cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }, false)
  end)
  if not valid(p) then return nil end
  try(function() p:SetSkeletalMeshComponent(st.mesh) end)
  st.pac = p
  return p
end
local function hold(root, s)
  local p = pac()
  if not p then return end
  local a = cfg().anim or {}
  local k = s and (a.strong or 600) or (a.weak or 40)
  local data = { bIsLocalSimulation = true, OrientationStrength = k, AngularVelocityStrength = k * (a.damping or 0.15),
    PositionStrength = 0, VelocityStrength = 0, MaxLinearForce = 0, MaxAngularForce = 0 }
  try(function() p:ApplyPhysicalAnimationSettingsBelow(FName(root), data, true) end)
end
local function cut_off(root)
  for _, b in ipairs(CUTS[root] or {}) do if rag() and rag().severed(st.mesh, b) then return true end end
  return false
end
local function gravity(root, on)
  for _, b in ipairs(CHAIN[root]) do try(function() st.mesh:SetEnableBodyGravity(on, FName(b)) end) end
end
-- the chain under root simulating till `till` (os.clock()): true when it does
local function chain_open(root, till)
  local c = st.chains[root]
  if c then
    c.till, c.phase = math.max(c.till, till), "twitch"
    hold(root, false)
    try(function() st.mesh:SetAllBodiesBelowPhysicsBlendWeight(FName(root), 1.0, false, true) end)
    return true
  end
  if not CHAIN[root] or cut_off(root) then return false end
  -- a hand or foot twitching on its own goes on as part of the forearm's or calf's chain
  local inner = INNER[root] and st.chains[INNER[root]]
  if inner then st.chains[INNER[root]] = nil; till = math.max(till, inner.till)
  elseif simulating(st.mesh, root) then return false end
  if not try(function() st.mesh:SetAllBodiesBelowSimulatePhysics(FName(root), true, true); return true end) then return false end
  try(function() st.mesh:SetAllBodiesBelowPhysicsBlendWeight(FName(root), 1.0, false, true) end)
  gravity(root, false)
  hold(root, false)
  st.chains[root] = { till = till, phase = "twitch" }
  return true
end
local function chain_close(root, why)
  local c = st.chains[root]
  st.chains[root] = nil
  if not c or not valid(st.mesh) then return end
  gravity(root, true)
  -- (a drive left on would pull a piece cut off meanwhile, or her ragdoll, towards the pose)
  local p = st.pac
  if valid(p) then try(function() p:ApplyPhysicalAnimationSettingsBelow(FName(root), { bIsLocalSimulation = true, OrientationStrength = 0,
    AngularVelocityStrength = 0, PositionStrength = 0, VelocityStrength = 0, MaxLinearForce = 0, MaxAngularForce = 0 }, true) end) end
  if why == "ragdoll" or cut_off(root) then return end
  try(function() st.mesh:SetAllBodiesBelowSimulatePhysics(FName(root), false, true) end)
end
local function chains_tick(now)
  local a = cfg().anim or {}
  local back, blend = a.back or 0.3, a.blend or 0.15
  for root, c in pairs(st.chains) do
    if cut_off(root) then chain_close(root)
    elseif c.phase == "twitch" and now >= c.till then
      c.phase, c.t = "back", now
      hold(root, true)
    elseif c.phase == "back" and now >= c.t + back then
      c.phase, c.t = "blend", now
    elseif c.phase == "blend" then
      local w = 1 - (now - c.t) / blend
      if w <= 0 then chain_close(root)
      else try(function() st.mesh:SetAllBodiesBelowPhysicsBlendWeight(FName(root), w, false, true) end) end
    end
  end
end
local function chains_drop(why)
  for root in pairs(st.chains) do chain_close(root, why) end
  local p = st.pac
  st.pac = nil
  if valid(p) then
    try(function() p:SetSkeletalMeshComponent(nil) end)
    try(function() p:K2_DestroyComponent(p) end)
  end
end

-- ---- the movements ----
-- one muscle on comp: bone b's far end towards `to` at amp deg/s at the peak, over dur s, from `at` (os.clock())
-- (trem, hz: a shaking over it, deg/s either way that many times a second, about axis `ax` if given)
-- (swing: an arm's slow swing, which tune.convulse.arms' jerks being off doesn't stop)
local function pulse(comp, f, b, to, amp, dur, at, anim, trem, hz, ax, swing)
  local r = rag()
  if not (J[b] and valid(comp)) then return false end
  if not swing and not arms_on() and arm_bone(b) then return false end
  if r and r.severed(comp, b) then return false end -- a piece's root: nothing to turn it against
  if anim then
    -- (a hand or foot in a forearm's or calf's chain keeps that chain simulating till it is done)
    local open
    for root in pairs(st.chains) do
      for _, m in ipairs(CHAIN[root]) do if m == b then open = root end end
    end
    if open then chain_open(open, at + dur)
    elseif not simulating(comp, b) and not chain_open(b, at + dur) then return false end
  elseif r and not r.live(comp, b) then return false end
  local a = ax or axis_of(comp, f, b, to, anim)
  if not a then return false end
  local p = J[b][1]
  local mass = r and r.MASS or {}
  local k = (mass[b] and mass[p]) and math.min(0.6, mass[b] / mass[p]) or 0.3
  -- (no turning back of a parent that is animated, or that a cut took this bone from)
  if anim and not simulating(comp, p) then k = 0 end
  st.pulses[#st.pulses + 1] = { comp = comp, b = b, p = p, a = a, amp = amp, dur = dur, at = at, v = 0, k = k,
    trem = trem, hz = hz, ph = math.random() * 2 * math.pi }
  return a
end
local function pulses_tick(now)
  local keep = {}
  for _, p in ipairs(st.pulses) do
    if now >= p.at and valid(p.comp) then
      local x = math.min(1, (now - p.at) / p.dur)
      local v = p.amp * math.sin(math.pi * x)
      -- (the shaking strongest mid-strain, gone at both ends: no step in speed)
      if p.trem then v = v + p.trem * math.sin(math.pi * x) ^ 0.5 * math.sin(2 * math.pi * p.hz * (now - p.at) + p.ph) end
      local dv = v - p.v
      p.v = v
      if p.started == nil then
        p.started = true
        try(function() p.comp:WakeRigidBody(FName(p.b)) end)
      end
      -- a swing's upper arm: how far it really turned, logged at its end (a right arm's crawl showed no movement,
      -- playtest)
      if p.meter then
        local tip = J[p.b] and J[p.b][2]
        local at, to = loc(p.comp, p.b), tip and loc(p.comp, tip)
        local d = at and to and norm(sub(to, at))
        if d then
          p.d0 = p.d0 or d
          local deg = math.deg(math.acos(math.max(-1, math.min(1, dot(p.d0, d)))))
          if deg > (p.most or 0) then p.most = deg end
        end
        if x >= 1 then log(string.format("%s: turned at most %.0f deg (peak %.0f deg/s asked)", p.meter, p.most or -1, p.amp)) end
      end
      try(function() p.comp:AddAngularImpulseInDegrees(scale(p.a, dv), FName(p.b), true) end)
      if p.k > 0 then try(function() p.comp:AddAngularImpulseInDegrees(scale(p.a, -dv * p.k), FName(p.p), true) end) end
      if x < 1 then keep[#keep + 1] = p end
    elseif now < p.at then
      keep[#keep + 1] = p
    end
  end
  st.pulses = keep
end

-- her face along (main.lua's death face reads M.face): each pose a set of her face's morph targets (the JALI names of
-- CH_P_EVE_Face_Jali3) and how far each moves at the pose's full amount, added over the held death face. lids opens
-- her eyes (a flutter), jaw drops it, brow and mouth are a wince's halves. A pose given as a list is a set of takes,
-- one picked each time; every morph of it is jittered by tune.convulse.faceJitter (and a sided pair apart)
local POSES = {
  lids = { upLid_down_L = -1, upLid_down_R = -1 },
  jaw = { jaw_open = 1, nostrill_flare = 0.8 },
  brow = { brow_furrow = 1, brow_down = 0.6, innerBrow_up = 0.4, squint = 0.6 },
  mouth = { lip_stretch = 1, lipCorner_down = 0.6, nose_wrinkle = 0.6, upperLip_up = 0.4 },
  -- face only (tune.convulse.body off): her whole face screwing up, the mouth open on it
  wince = {
    { brow_furrow = 0.7, brow_down = 0.45, innerBrow_up = 0.35, squint = 0.8, squint_lower = 0.4, nose_wrinkle = 0.55,
      lip_stretch = 0.5, upperLip_up = 0.3, lipCorner_down = 0.3, jaw_open = 0.18, grimace_neck = 0.4 },
    -- teeth clenched and bared
    { brow_furrow = 0.8, brow_down = 0.6, squint = 0.9, squint_lower = 0.5, nose_wrinkle = 0.7, lip_stretch = 0.8,
      upperLip_up = 0.5, lowerLip_down = 0.45, jaw_Close = 0.3, grimace_neck = 0.7 },
    -- eyes screwed shut, the mouth pulled down
    { brow_furrow = 0.5, innerBrow_up = 0.6, brow_in = 0.5, upLid_down_L = 0.5, upLid_down_R = 0.5, squint = 1.0,
      squint_lower = 0.6, lipCorner_down = 0.7, sadSmile = 0.4, chin_up = 0.5, jaw_open = 0.1 },
    -- one side worse
    { brow_furrow = 0.6, brow_down_left = 0.6, squint_left = 0.9, outerSquint_left = 0.5, noseWrinkle_left = 0.7,
      upperLip_sneer_left = 0.5, lip_stretch_left = 0.6, lipCorner_down_right = 0.4, jaw_open = 0.15 },
  },
  moan = {
    { jaw_open = 0.3, lowerLip_down = 0.25, innerBrow_up = 0.45, outerBrow_up = 0.1, lipCorner_down = 0.25, squint = 0.25 },
    -- a whimper through closed lips
    { lips_together = 0.5, chin_up = 0.4, innerBrow_up = 0.55, brow_in = 0.3, lipCorner_down = 0.4, squint = 0.2 },
    -- a low groan, the jaw hanging
    { jaw_open = 0.4, lowerLip_down = 0.35, upperLip_up = 0.1, brow_down = 0.25, squint = 0.35, lowerLip_in = 0.15 },
  },
  gasp = {
    { jaw_open = 0.55, nostrill_flare = 0.8, upLid_down_L = -0.4, upLid_down_R = -0.4, innerBrow_up = 0.4,
      outerBrow_up = 0.25, upperLip_up = 0.2, lowerLip_down = 0.2 },
    -- caught short, through the teeth
    { jaw_open = 0.2, lip_stretch = 0.3, upperLip_up = 0.35, lowerLip_down = 0.35, nostrill_flare = 1.0,
      upLid_down_L = -0.3, upLid_down_R = -0.3, brow_furrow = 0.3 },
    -- the mouth rounding, the eyes rolling up
    { jaw_open = 0.45, lip_pucker = 0.25, lowerLip_funnel = 0.3, upperLip_funnel = 0.3, eye_up_L = 0.4, eye_up_R = 0.4,
      outerBrow_up = 0.3, nostrill_flare = 0.6 },
  },
  -- her neck straining (neck_event): its cords out, the jaw clenched, the face screwed up with the effort
  strain = {
    { grimace_neck = 0.9, jaw_Close = 0.4, lips_together = 0.35, squint = 0.45, brow_furrow = 0.55, brow_down = 0.3,
      nostrill_flare = 0.6, lip_stretch = 0.35 },
    -- teeth showing through it
    { grimace_neck = 1.0, lip_stretch = 0.6, upperLip_up = 0.35, lowerLip_down = 0.35, squint = 0.6, nose_wrinkle = 0.4,
      brow_furrow = 0.6, jaw_Close = 0.25 },
    -- one side of the neck
    { grimace_neck_left = 0.9, lip_stretch_left = 0.5, lipCorner_down_left = 0.4, squint_left = 0.5, brow_furrow = 0.4,
      jaw_Close = 0.3, nostrill_flare = 0.4 },
    { grimace_neck_right = 0.9, lip_stretch_right = 0.5, lipCorner_down_right = 0.4, squint_right = 0.5,
      brow_furrow = 0.4, jaw_Close = 0.3, nostrill_flare = 0.4 },
  },
  swallow = { hyoid_up = 0.8, lips_together = 0.6, jaw_Close = 0.3, squint = 0.15 },
  tremble = { jaw_open = 0.12, lowerLip_down = 0.1 },
  -- her lip and chin quivering
  quiver = { lowerLip_down = 0.25, chin_up_loLip = 0.3, lipCorner_down = 0.15 },
  -- a sob, catching: the brows up in the middle, the chin and mouth down
  sob = { innerBrow_up = 0.6, brow_in = 0.35, chin_up = 0.5, lipCorner_down = 0.6, sadSmile = 0.4, jaw_open = 0.12,
    nostrill_flare = 0.4 },
  -- her eyes rolling up under the lids, a moment
  roll = { eye_up_L = 0.7, eye_up_R = 0.7, upLid_down_L = 0.25, upLid_down_R = 0.25 },
  -- a long breath out: everything letting go a little, lips apart
  sigh = { jaw_open = 0.15, lowerLip_down = 0.15, upLid_down_L = 0.15, upLid_down_R = 0.15, puff = 0.2,
    brow_furrow = -0.3, squint = -0.3, lip_stretch = -0.3 },
}
-- a tic on one side: the mouth's corner pulled, an eye squeezed, the nose wrinkled, the cheek pulled down, the lip up
local function tic_pose(sd)
  local l, e = sd == "L" and "_left" or "_right", sd == "L" and "_L" or "_R"
  local k = math.random(6)
  if k == 1 then return { ["lipCorner_pull" .. l] = 0.6, ["outerSquint" .. l] = 0.3 }
  elseif k == 2 then return { ["squint" .. l] = 0.7, ["upLid_down" .. e] = 0.2, ["brow_down" .. l] = 0.3 }
  elseif k == 3 then return { ["noseWrinkle" .. l] = 0.6, ["upperLip_sneer" .. l] = 0.3 }
  elseif k == 4 then return { ["upperLip_up" .. l] = 0.5, ["dimple" .. l] = 0.4 }
  elseif k == 5 then return { ["outerBrow_up" .. l] = 0.5, ["upLid_up" .. e] = 0.3 }
  end
  return { ["lipCorner_down" .. l] = 0.5, ["grimace_neck" .. l] = 0.5 }
end
local function face(what, amount, at, dur)
  if cfg().face == false or still(st.mesh) then return end
  local pose = type(what) == "table" and what or POSES[what]
  if not pose then return end
  if pose[1] then pose = pose[math.random(#pose)] end
  local j, o, p = cfg().faceJitter or 0.3, cfg().faceOpen or 1, {}
  for m, w in pairs(pose) do
    -- (the morphs dropping her mouth: farther, by faceOpen)
    local down = m == "jaw_open" or m:find("^lowerLip_down") or m == "wholeMouth_down"
    p[m] = w * rnd(1 - j, 1 + j) * (down and o or 1)
  end
  st.faces[#st.faces + 1] = { pose = p, k = amount, at = at, dur = dur }
end
-- a pose's amount over its time, 0..1 at x of it: a long one (a moan, a gasp) comes in over its first quarter, holds,
-- and eases out; a half sine both ways read as a slow wide open and the same slow close (playtest), and the quarter
-- sine it came in on before (fastest at its start) read as her face snapping as she came to lie still (playtest): an
-- S-curve now, starting slow. Short ones (a tic, a flutter) stay a half sine
local function envelope(x, dur)
  if dur < 0.3 then return math.sin(math.pi * x) end
  if x < 0.25 then local u = x / 0.25; return u * u * (3 - 2 * u) end
  if x < 0.4 then return 1 end
  local u = (x - 0.4) / 0.6
  return 1 - u * u * (3 - 2 * u)
end
-- what the poses add now, by morph target name (nil: nothing)
function M.face()
  if not st or #st.faces == 0 then return nil end
  local now, out, keep = os.clock(), {}, {}
  for _, e in ipairs(st.faces) do
    if now < e.at + e.dur then
      keep[#keep + 1] = e
      if now >= e.at then
        local k = e.k * envelope((now - e.at) / e.dur, e.dur)
        for m, w in pairs(e.pose) do out[m] = (out[m] or 0) + w * k end
      end
    end
  end
  st.faces = keep
  -- (the first ones eased in over faceIn s from her convulsions' start: the death face's still mask went straight
  -- into a full wince as she came to lie still)
  local fin = cfg().faceIn or 0.8
  local x = st.onset and (st.t - st.onset) or 0
  if fin > 0 and x < fin then
    local u = math.max(0, x / fin)
    local k = u * u * (3 - 2 * u)
    for m, w in pairs(out) do out[m] = w * k end
  end
  return out
end

-- one event: a set of muscles at once (repeats: a burst of jerks, each weaker), with the face's part
local function event(kind, list, amp, dur, reps, anim)
  local r = rag()
  local v = not anim and r and r.view()
  local comps = v and v.comps or { st.mesh }
  local comp = comps[math.random(#comps)]
  local f = frame(comp)
  local now, n, gap = os.clock(), 0, rnd(0.16, 0.26)
  for i = 1, reps do
    local at = now + (i - 1) * gap
    local k = 0.85 ^ (i - 1)
    for _, m in ipairs(list) do
      if pulse(comp, f, m[1], m[2], amp * m[3] * k * rnd(0.85, 1.15), dur * rnd(0.85, 1.2), at, anim) then n = n + 1 end
    end
  end
  local span = (reps - 1) * gap + dur * 1.2
  if n > 0 and not anim and r then r.twitch(span + (cfg().settleAfter or 0.4)) end
  st.events = st.events + 1
  return n, span
end

local function side() return math.random() < 0.5 and "L" or "R" end

-- her voice along, quiet (tune.convulse.voice): a breath with a gasp, now and then a moan with a spasm. Never once
-- beheaded, never over her death cry, at least voice.gap s apart. Played on her head by gore.lua (voice_soft)
local function sound(kind, k, always)
  local v = cfg().voice
  if type(v) ~= "table" or v.enabled == false or still(st.mesh) then return "" end
  -- (the first spasm always moans: the first one came 1.5 s in, 4.7 s into her death, playtest)
  if kind == "moan" and st.moaned and not always and math.random() > (v.moanChance or 0.5) then return "" end
  local now = os.clock()
  if now - (st.voiced or -100) < (v.gap or 1.2) then return "" end
  local g = ctx.gore
  local names = kind == "breath" and v.breaths or v.moans
  local vol = (kind == "breath" and (v.breathVolume or 0.25) or (v.moanVolume or 0.15)) * (v.volume or 1) * (k or 1)
  local name = g and g.voice_soft and try(function() return g.voice_soft(st.pawn, st.mesh, names, vol) end)
  if not name then return "" end
  st.voiced = now
  if kind == "moan" then st.moaned = true end
  return string.format(", %s at %.2f", name, vol)
end

-- her body still, her face alone (tune.convulse.body off): winces with a moan, gasps, a swallow, tics on one side, her
-- jaw trembling, her eyelids fluttering; strong and close together at first, then fewer and smaller
-- how long they run: her face alone is shorter (tune.convulse.faceAgonal, faceDuration)
local function span()
  local c = cfg()
  if c.body == false then return c.faceAgonal or 2.5, c.faceDuration or 5 end
  return c.agonal or 4, c.duration or 8
end

-- (an open mouth goes with its sound: a gasp, a wince or sobs whose breath or moan can't play (another one too
-- recent, the voice off) is a silent movement instead; a gasp with no breath looked like a scream with no sound)
local swing_on
local function face_event(x)
  local c = cfg()
  local agonal, total = span()
  local s = c.strength or 1.0
  local I = math.exp(-x / math.max(c.fade or 2, 0.1))
  local now, what = os.clock(), nil
  if still(st.mesh) then
    -- (her arms may still swing: asked again a little later, said once)
    if swing_on() then
      st.next = x + rnd(0.4, 1.0)
      if st.stillSaid then return nil, 0 end
      st.stillSaid = true
    else st.next = total end
    return (headless(st.mesh) and "beheaded" or "split") .. ": her face stays", 0
  end
  if x < agonal then
    -- (the first one a wince, with its moan)
    local r = st.moaned == nil and (c.voice or {}).enabled ~= false and 0.4 or math.random()
    if st.moaned == nil then st.moaned = false end
    if c.gasps ~= false and x - st.gasped >= (c.gaspGap or 1.5) and r < 0.25 then
      local snd = sound("breath", 1, true)
      if snd ~= "" then
        st.gasped = x
        face("gasp", s * rnd(0.8, 1.1), now, rnd(0.6, 0.9))
        what = "gasp" .. snd
      end
    elseif r < 0.6 then
      local snd = sound("moan", 0.6 + 0.4 * I, true)
      if snd ~= "" then
        local dur = rnd(0.55, 0.9)
        face("wince", s * (0.6 + 0.4 * I) * rnd(0.85, 1.15), now, dur)
        face("moan", s * rnd(0.7, 1.0), now + 0.1, dur * 0.9)
        what = "wince" .. snd
      end
    elseif r < 0.68 and math.random() < 0.5 then
      local n, snd = math.random(2, 3), sound("breath", 0.6, true)
      if snd ~= "" then
        for i = 0, n - 1 do face("sob", s * (0.9 ^ i) * rnd(0.7, 1.0), now + i * rnd(0.3, 0.45), rnd(0.35, 0.5)) end
        what = string.format("%d sobs", n) .. snd
      end
    end
    if not what and r < 0.68 then r = 0.6 + math.random() * 0.4 end
    if what then
    elseif r < 0.68 then
      face("swallow", s, now, 0.5)
      what = "swallow"
    elseif r < 0.84 then
      local sd, reps = side(), math.random(1, 3)
      local pose = tic_pose(sd)
      for i = 0, reps - 1 do face(pose, s * (0.85 ^ i), now + i * rnd(0.16, 0.22), rnd(0.12, 0.18)) end
      what = string.format("%d %s tic%s", reps, sd == "L" and "left" or "right", reps > 1 and "s" or "")
    elseif r < 0.92 then
      local n = math.random(4, 7)
      local q = math.random() < 0.5 and "tremble" or "quiver"
      for i = 0, n - 1 do face(q, s * rnd(0.7, 1.2), now + i * 0.09, 0.09) end
      what = q == "tremble" and "jaw trembling" or "lip quivering"
    else
      face("roll", s * rnd(0.6, 1.0), now, rnd(0.5, 0.9))
      what = "eyes roll up"
    end
    if math.random() < 0.35 then
      local t0 = now + rnd(0, 0.2)
      for i = 0, math.random(1, 3) - 1 do face("lids", rnd(0.3, 0.6) * s, t0 + i * 0.16, 0.12) end
      what = what .. ", eyelids flutter"
    end
    st.next = x + rnd(0.4, 1.0) / (0.5 + I)
  else
    if not st.lastGasp then
      st.lastGasp = true
      local snd = c.gasps ~= false and sound("breath", 1.15, true) or ""
      if snd ~= "" then
        face("gasp", s * 1.1, now, 1.2)
        face("lids", 0.3 * s, now + 0.3, 0.5)
        st.next = x + rnd(0.8, 1.2)
        st.events = st.events + 1
        return "her last gasp" .. snd, 0
      end
    end
    local y = (x - agonal) / math.max(total - agonal, 1)
    local r = math.random()
    if r < 0.25 then
      face("lids", rnd(0.15, 0.3) * s * (1 - 0.6 * y), now, 0.12)
      what = "eyelid flicker"
    elseif r < 0.4 then
      face("sigh", s * rnd(0.6, 1.0), now, rnd(1.0, 1.6))
      what = "a sigh"
    elseif r < 0.5 then
      local n = math.random(3, 5)
      for i = 0, n - 1 do face("quiver", s * rnd(0.4, 0.7) * (1 - 0.5 * y), now + i * 0.1, 0.1) end
      what = "lip quivering"
    else
      local sd = side()
      face(tic_pose(sd), s * rnd(0.4, 0.7) * (1 - 0.6 * y), now, rnd(0.1, 0.15))
      what = (sd == "L" and "left" or "right") .. " tic"
    end
    st.next = x + rnd(0.5, 1.0) * (1 + y)
  end
  st.events = st.events + 1
  return what, 0
end

-- her neck struggling (tune.convulse.neck): her head strains one way (lifting off the floor, mostly, or turning aside,
-- now and then back), shaking with the effort (a tremor along the strain and half of it crossways), gives out and drops,
-- then jerks 2-4 times the same way, weakening; the strain's cords and clenched jaw on her face. Later ones weaker and
-- with fewer jerks. A ragdoll's head body is moved as it lies; an animated death's head simulates for it (CHAIN)
local NECK_WAYS = { "front", "front", "front", "out", "in", "out", "in", "back" }
local function neck_on()
  local nk = cfg().neck
  return type(nk) == "table" and nk.enabled ~= false
end
local function neck_event(late, anim)
  local c, nk = cfg(), cfg().neck
  local r = rag()
  local comp = st.mesh
  if not anim then
    local v = r and r.view()
    comp = nil
    for _, m in ipairs(v and v.comps or {}) do if not comp and r.live(m, "Bip001-Head") then comp = m end end
    if not comp then return nil end
  end
  local f = frame(comp)
  local s = (c.strength or 1.0) * (late and 0.6 or 1.0)
  -- (an animated death's head simulates alone off her animated neck: no ragdoll's neck range held it, and the full
  -- strain and jerks bent it ~70 deg after she landed, a snapped neck, playtest)
  if anim then s = s * (tonumber(nk.animScale) or 0.35) end
  local way = NECK_WAYS[math.random(#NECK_WAYS)]
  local tt, hh = nk.strainTime or { 0.7, 1.3 }, nk.hz or { 7, 11 }
  local dur, hz = rnd(tt[1], tt[2] or tt[1]), rnd(hh[1], hh[2] or hh[1])
  local trem = (nk.tremor or 55) * s * rnd(0.8, 1.2)
  local now = os.clock()
  if not pulse(comp, f, "Bip001-Head", way, (nk.strain or 110) * s * rnd(0.85, 1.15), dur, now, anim, trem, hz) then return nil end
  -- (the crossways shaking a little out of step with the other)
  pulse(comp, f, "Bip001-Head", (way == "front" or way == "back") and "out" or "front", 0, dur, now, anim, trem * 0.5, hz * rnd(0.8, 1.2))
  local reps = late and math.random(1, 2) or math.random(2, 4)
  local t, n = now + dur + rnd(0.08, 0.2), 0
  for i = 0, reps - 1 do
    if pulse(comp, f, "Bip001-Head", way, (nk.jerk or 170) * s * (0.8 ^ i) * rnd(0.85, 1.15), rnd(0.07, 0.1), t, anim) then
      n = n + 1
      face("strain", 0.5 * s * (0.8 ^ i), t, 0.15)
    end
    t = t + rnd(0.18, 0.3)
  end
  local span = t - now
  face("strain", s * rnd(0.8, 1.0), now, dur)
  if not anim and r then r.twitch(span + (c.settleAfter or 0.4)) end
  return string.format("neck strains %s for %.1f s, shaking at %.0f Hz, then %d jerk%s", way, dur, hz, n, n == 1 and "" or "s"), span
end

-- her arm swinging (tune.convulse.armSwing, also with body off): the whole arm lifting slowly from the shoulder and
-- falling back, the elbow following a beat later and the hand turning after it, each a smooth rise and fall of speed
-- over most of a second; now and then it swings back the other way before it drops. Not arms' jerks, which looked like
-- the ragdoll glitching (playtest); later ones weaker. An animated death's arm moves from the elbow only (its
-- forearm's chain simulates for it, the upper arm stays on the fall's pose)
local SWING_WAYS = { "up", "up", "front", "out", "in" }
local SWING_BACK = { up = "down", front = "back", out = "in", ["in"] = "out" }
function swing_on()
  local a = cfg().armSwing
  return type(a) == "table" and a.enabled ~= false
end
local function swing_event(late, anim)
  local c, a = cfg(), cfg().armSwing
  local r = rag()
  -- an arm still on her: no cut at its clavicle, upper arm, forearm or hand (a cut-off arm's bodies still simulate on
  -- her mesh: its swing moved the arm lying apart on the floor, and she showed none, playtest), on the comp given or
  -- on the half of a split it is on
  local function arm_comp(sd2)
    local bb = "Bip001-" .. sd2 .. "-"
    local function on(m)
      if not (r and r.live(m, bb .. "UpperArm") and r.live(m, bb .. "Forearm")) then return false end
      for _, x in ipairs({ "Clavicle", "UpperArm", "Forearm" }) do if r.severed(m, bb .. x) then return false end end
      return true
    end
    if anim then return (valid(st.mesh) and not (r and (r.severed(st.mesh, bb .. "UpperArm") or r.severed(st.mesh, bb .. "Forearm")
      or r.severed(st.mesh, bb .. "Clavicle")))) and st.mesh or nil end
    local v = r and r.view()
    for _, m in ipairs(v and v.comps or {}) do if on(m) then return m end end
  end
  local sd = side()
  local comp = arm_comp(sd)
  if not comp then sd = sd == "L" and "R" or "L"; comp = arm_comp(sd) end
  if not comp then return nil end
  local b = "Bip001-" .. sd .. "-"
  local f = frame(comp)
  local s = (c.strength or 1.0) * (late and (a.late or 0.6) or 1.0)
  local tt = a.time or { 0.7, 1.2 }
  local dur = rnd(tt[1], tt[2] or tt[1])
  local amp = (a.speed or 300) * s * rnd(0.85, 1.15)
  local now, n = os.clock(), 0
  -- now and then a crawl's stroke instead, as if dragging herself away: the arm reaching past her head with the elbow
  -- straightening, then pulling back down along her with the elbow bending and the hand clawing; the next one most
  -- likely the other arm
  if math.random() < (a.crawl or 0.35) then
    if st.crawled then sd = st.crawled == "L" and (math.random() < 0.75 and "R" or "L") or (math.random() < 0.75 and "L" or "R") end
    local pick = arm_comp(sd)
    if not pick then sd = sd == "L" and "R" or "L"; pick = arm_comp(sd) end
    if not pick then return nil end
    b = "Bip001-" .. sd .. "-"
    comp, f = pick, frame(pick)
    if pulse(comp, f, b .. "UpperArm", "up", amp, dur, now, anim, nil, nil, nil, true) then
      n = n + 1
      st.pulses[#st.pulses].meter = (sd == "L" and "left" or "right") .. " arm's reach"
    end
    if pulse(comp, f, b .. "Forearm", "back", amp * 0.6 * (anim and 1.4 or 1), dur * 0.8, now + dur * 0.15, anim, nil, nil, nil, true) then n = n + 1 end
    if n == 0 then return nil end
    local t, d2 = now + dur + rnd(0.05, 0.2), dur * rnd(0.9, 1.2)
    pulse(comp, f, b .. "UpperArm", "down", amp * rnd(0.7, 0.9), d2, t, anim, nil, nil, nil, true)
    pulse(comp, f, b .. "Forearm", "front", amp * 0.7 * (anim and 1.4 or 1), d2 * 0.9, t + d2 * 0.1, anim, nil, nil, nil, true)
    pulse(comp, f, b .. "Hand", "front", amp * (a.hand or 0.5), d2 * 0.6, t + d2 * 0.2, anim, nil, nil, nil, true)
    st.crawled = sd
    local span = t + d2 - now
    if not anim and r then r.twitch(span + (c.settleAfter or 0.4)) end
    return string.format("%s arm reaches out and drags back, over %.1f s", sd == "L" and "left" or "right", span), span
  end
  local way = SWING_WAYS[math.random(#SWING_WAYS)]
  if pulse(comp, f, b .. "UpperArm", way, amp, dur, now, anim, nil, nil, nil, true) then
    n = n + 1
    st.pulses[#st.pulses].meter = (sd == "L" and "left" or "right") .. " arm's swing " .. way
  end
  local bend = math.random() < 0.6 and "front" or "back"
  if pulse(comp, f, b .. "Forearm", bend, amp * rnd(0.5, 0.8) * (anim and 1.4 or 1), dur * rnd(0.8, 1.0),
    now + dur * rnd(0.1, 0.25), anim, nil, nil, nil, true) then n = n + 1 end
  if pulse(comp, f, b .. "Hand", "rand", amp * (a.hand or 0.5), dur * 0.7, now + dur * 0.3, anim, nil, nil, nil, true) then n = n + 1 end
  if n == 0 then return nil end
  local span, back = dur * 1.25, ""
  if math.random() < (a.back or 0.4) then
    local t = now + dur + rnd(0.1, 0.3)
    local d2 = dur * rnd(0.8, 1.0)
    if pulse(comp, f, b .. "UpperArm", SWING_BACK[way], amp * rnd(0.5, 0.7), d2, t, anim, nil, nil, nil, true)
      or pulse(comp, f, b .. "Forearm", bend == "front" and "back" or "front", amp * 0.5, d2, t, anim, nil, nil, nil, true) then
      span, back = t + d2 - now, ", and back"
    end
  end
  if not anim and r then r.twitch(span + (c.settleAfter or 0.4)) end
  return string.format("%s arm swings %s over %.1f s%s", sd == "L" and "left" or "right", way, dur, back), span
end

-- the next event, by how far into her convulsions she is: x seconds since they began
local function next_event(x, anim)
  -- (never the first either)
  if swing_on() and (st.moaned ~= nil or still(st.mesh)) and not (x >= span() and not st.lastGasp)
    and math.random() < (cfg().armSwing.chance or 0.35) * (x >= span() and 0.5 or 1) then
    local what, dur = swing_event(x >= span(), anim)
    if what then
      st.events = st.events + 1
      st.next = x + dur * 0.6 + rnd(0.3, 0.8) * (x >= span() and 1.5 or 1)
      return what, 1
    end
  end
  -- (never the first: that one is a wince or spasm with its moan)
  if neck_on() and st.moaned ~= nil and not still(st.mesh) and not (x >= span() and not st.lastGasp)
    and math.random() < (cfg().neck.chance or 0.3) * (x >= span() and 0.5 or 1) then
    local what, dur = neck_event(x >= span(), anim)
    if what then
      st.events = st.events + 1
      st.next = x + dur + rnd(0.3, 0.8) * (x >= span() and 1.5 or 1)
      return what, 1
    end
  end
  if cfg().body == false then return face_event(x) end
  local c = cfg()
  local agonal, total = c.agonal or 4, c.duration or 8
  local s = c.strength or 1.0
  local jerk = (c.jerk or 260) * s
  local I = math.exp(-x / math.max(c.fade or 2, 0.1))
  local noHead = still(st.mesh)
  local what, n, span
  if x < agonal then
    -- (her first movement a spasm, with its moan)
    local r = st.moaned == nil and not noHead and (cfg().voice or {}).enabled ~= false and 0.4 or math.random()
    if st.moaned == nil then st.moaned = false end
    if not noHead and c.gasps ~= false and x - st.gasped >= (c.gaspGap or 1.5) and r < 0.3 then
      st.gasped = x
      n, span = event("gasp", gasp(), jerk * 0.45, 0.5, 1, anim)
      face("jaw", 0.35 * s, os.clock(), 0.8)
      face("brow", 0.2 * s, os.clock(), 0.8)
      what = "gasp" .. sound("breath")
    elseif r < 0.55 then
      local sd = side()
      local reps = math.random(2, 2 + math.floor(3 * I + 0.5))
      local leg = not arms_on() or math.random() < 0.5
      n, span = event("burst", leg and kick(sd) or curl(sd), jerk * (0.5 + 0.5 * I), 0.14, reps, anim)
      face("brow", 0.3 * s * I, os.clock(), span)
      face("mouth", 0.25 * s * I, os.clock(), span)
      what = string.format("burst of %d %s %s", reps, sd == "L" and "left" or "right", leg and "kicks" or "arm curls")
        .. sound("moan", 0.6 + 0.4 * I)
    elseif r < 0.75 and not anim then
      n, span = event("arch", arch(), jerk * (0.4 + 0.6 * I), 0.22, math.random(1, 2), anim)
      face("brow", 0.35 * s * I, os.clock(), span)
      what = "back arched" .. sound("moan", 0.6 + 0.4 * I)
    elseif r < 0.85 and not noHead then
      n, span = event("head", head(), jerk * 0.6 * (0.5 + 0.5 * I), 0.12, 1, anim)
      what = "head jerk"
    else
      n, span = event("twitch", small(side()), jerk * 0.5, 0.1, 1, anim)
      what = "twitch"
    end
    if math.random() < 0.35 then
      local t0 = os.clock() + rnd(0, 0.2)
      for i = 0, math.random(1, 3) - 1 do face("lids", rnd(0.3, 0.6) * s, t0 + i * 0.16, 0.12) end
    end
    st.next = x + rnd(0.3, 0.9) / (0.5 + I)
  else
    if not st.lastGasp then
      st.lastGasp = true
      if not noHead and c.gasps ~= false then
        n, span = event("gasp", gasp(), jerk * 0.55, 0.7, 1, anim)
        face("jaw", 0.45 * s, os.clock(), 1.2)
        face("lids", 0.25 * s, os.clock() + 0.3, 0.5)
        st.next = x + rnd(1.0, 1.6)
        return "her last gasp" .. sound("breath", 1.15), n
      end
    end
    local y = (x - agonal) / math.max(total - agonal, 1)
    n, span = event("twitch", small(side()), jerk * rnd(0.25, 0.45) * (1 - 0.6 * y), rnd(0.07, 0.11), math.random() < 0.25 and 2 or 1, anim)
    what = "twitch"
    st.next = x + rnd(0.5, 1.2) * (1 + y)
  end
  return what, n
end

-- ---- the death ----
function M.start(pawn, mesh)
  M.stop()
  local c = cfg()
  if c.enabled == false then return end
  st = { pawn = pawn, mesh = mesh, t = 0, pulses = {}, chains = {}, faces = {}, events = 0, gasped = -100,
    last = os.clock(), trail = {} }
end

-- the death went ragdoll partway (main.lua's ragdoll_now, before her bodies all simulate): the chains let go
function M.to_ragdoll()
  if not st then return end
  chains_drop("ragdoll")
  st.pulses = {}
end

-- has she come to rest? A ragdoll once active.lua settled her; her animated fall once her pelvis stopped moving
-- (an animated fall waits for its pelvis and head both, up to animStartMax: started at startMax (2 s), the head of a
-- fall still playing 3-5 s in was taken by the neck's struggle and snapped mid animation, playtest)
local function at_rest(anim)
  local c = cfg()
  if st.t >= (anim and (c.animStartMax or 6) or (c.startMax or 2)) then return true end
  if not anim then
    local v = rag() and rag().view()
    return v ~= nil and v.settled == true
  end
  if st.t < 1.0 then return false end
  local p, hd = loc(st.mesh, "Bip001-Pelvis"), loc(st.mesh, "Bip001-Head")
  if not (p and hd) then return false end
  table.insert(st.trail, { t = st.t, p = p, h = hd })
  while #st.trail > 1 and st.trail[2].t <= st.t - 0.5 do table.remove(st.trail, 1) end
  local o = st.trail[1]
  local function moved(a, b) return math.sqrt(dot(sub(a, b), sub(a, b))) end
  return st.t - o.t >= 0.45 and moved(p, o.p) < 1.0 and moved(hd, o.h) < 1.0
end

function M.tick(paused)
  if not st then return end
  local now = os.clock()
  local dt = math.min(now - st.last, 0.1)
  st.last = now
  if not valid(st.gs) then st.gs = StaticFindObject("/Script/Engine.Default__GameplayStatics") end
  paused = paused or (valid(st.gs) and try(function() return st.gs:IsGamePaused(st.pawn) end))
  if paused or not valid(st.mesh) then
    -- the twitches wait (their start times move on with the pause)
    for _, p in ipairs(st.pulses) do p.at = p.at + dt end
    for _, e in ipairs(st.faces) do e.at = e.at + dt end
    for _, c in pairs(st.chains) do c.till = c.till + dt; if c.t then c.t = c.t + dt end end
    return
  end
  st.t = st.t + dt
  local anim = ctx.animated and ctx.animated()
  if not anim and next(st.chains) then chains_drop("ragdoll") end
  if not anim and not (rag() and rag().view()) then
    if not st.noRun then st.noRun = true; log("no ragdoll run (tune.active off?): none") end
    return
  end
  pulses_tick(now)
  if anim then chains_tick(now) end
  local c = cfg()
  if not st.onset then
    if not at_rest(anim) then return end
    st.onset = st.t + rnd(0.1, 0.3)
    st.next = 0
    log(string.format("from %.1f s, %s (%s)", st.onset, anim and "her animated fall's end pose" or "her ragdoll",
      headless(st.mesh) and "beheaded: no gasps" or split(st.mesh) and "split: no gasps, face or voice" or "gasps"))
    return
  end
  local x = st.t - st.onset
  if x < 0 then return end
  if x >= select(2, span()) then
    if not st.done then
      st.done = true
      log(string.format("over after %.0f s, %d movements", x, st.events))
    end
    return
  end
  if x >= st.next then
    local what, n = next_event(x, anim)
    if what and c.log ~= false then log(string.format("%.1f s: %s%s", x, what, c.body == false and "" or string.format(" (%d muscles)", n or 0))) end
  end
end

-- she got up, or the death ended: whatever is simulating for a twitch goes back on the animation
function M.stop()
  if not st then return end
  if valid(st.mesh) then chains_drop() end
  if st.onset and not st.done then log(string.format("stopped after %d movements", st.events)) end
  st = nil
end

-- a new Eve (the level reloaded): drop the old one's without touching it
function M.forget() st = nil end

return M
