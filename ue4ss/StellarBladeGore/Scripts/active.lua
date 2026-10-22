-- active.lua: make Eve's ragdoll fall like a body instead of a sack (tune.active).
--
-- On every ragdoll start:
--   * masses: the outfits' physics assets set bOverrideMass on the spine and jiggle bodies without a value, so
--     they weigh the engine default of 100 kg each (a 400 kg chest the push can't move), and cape / accessory
--     chains weigh up to 80 kg a link. Main bodies get a human mass distribution (~60 kg), every other body is
--     capped at a few hundred grams, so they follow her instead of steering her.
--   * momentum: the speed she had in the last few hundred ms before dying carries into the ragdoll (the death
--     show stops the capsule first, so without it she drops dead on the spot even at a sprint).
--   * impact: an extra push along the killing blow, spread over the upper body, plus a little twist so she turns as
--     she goes down. The direction is the game's own impulse when its death key gives one, else where the blow came
--     from (main.lua: the hit on her, or the nearest enemy).
--   * muscle tone: a PhysicalAnimationComponent drives every main joint towards the animated pose (local space, so
--     it shapes her but never holds her up), at full strength for tone.hold seconds, then fading over tone.fade to
--     tone.rest, which stays: a body without any folds flat at every joint like a sack. Legs get less, so the knees
--     go first and the torso folds over them. A severed limb's drive is dropped at once.
--   * her weapons drop: the sword hangs off a prop bone without a physics body, so in a ragdoll it stayed in the
--     air where she died. Each weapon showing is carried by an invisible box of its size that falls and tumbles,
--     starting with her hand's speed.
--   * settling: lying still, she kept jittering (head and limbs turning at 50-80 deg/s on the floor for seconds):
--     the tone's drives pulling towards the animated pose against the floor and the joint limits, and light jiggle
--     bodies fighting heavy ones. Speed alone rarely got low enough (a body shivering in place is fast but goes
--     nowhere), so she counts as lying still when her main bodies are slow or have drifted less than settle.drift
--     over the last settle.window; the tone lets go the moment she does, and after settle.time of it every body is
--     put to sleep. Past settle.most seconds a ragdoll that is only shivering settles anyway. Something hitting
--     her wakes her up and she settles again.
-- Everything is put back on recovery (masses, the component, the weapons on their sockets).

local M = {}
local ctx

local function cfg() return ctx.tune.active or {} end
local function log(s) ctx.log("active: " .. s) end
local try, valid = nil, nil

local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local function len(v) return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end

-- kg per main body, ~60 kg in all (Dempster-style segment shares for a light adult)
local MASS = {
  ["Bip001-Pelvis"] = 8.5, ["Bip001-Spine"] = 5.5, ["Bip001-Spine1"] = 5.5, ["Bip001-Spine2"] = 7.5,
  -- (the neck heavier than a segment table's 1.1: a 4.5 kg head on it shook in place on the floor)
  ["Bip001-Neck"] = 1.8, ["Bip001-Head"] = 4.5,
  ["Bip001-L-Clavicle"] = 1.4, ["Bip001-R-Clavicle"] = 1.4,
  ["Bip001-L-UpperArm"] = 1.7, ["Bip001-R-UpperArm"] = 1.7,
  ["Bip001-L-Forearm"] = 1.0, ["Bip001-R-Forearm"] = 1.0,
  ["Bip001-L-Hand"] = 0.4, ["Bip001-R-Hand"] = 0.4,
  ["Bip001-L-Thigh"] = 6.5, ["Bip001-R-Thigh"] = 6.5,
  ["Bip001-L-Calf"] = 2.8, ["Bip001-R-Calf"] = 2.8,
  ["Bip001-L-Foot"] = 0.8, ["Bip001-R-Foot"] = 0.8,
}
-- muscle tone per joint, as a share of tone.strength (the pelvis has no parent body to drive against). The head,
-- hands and feet have none: pulled towards an animated pose the floor was in the way of, they shook at 500-5000
-- deg/s while the rest of her lay still (thirteenth playtest). Nor the neck, clavicles and upper arms: with tone
-- they flipped their spin round on 40-60% of ticks in mid-air (the buzz log, eighteenth playtest), without it hardly
local TONE = {
  ["Bip001-Spine"] = 1.0, ["Bip001-Spine1"] = 1.0, ["Bip001-Spine2"] = 1.0,
  ["Bip001-L-Forearm"] = 0.5, ["Bip001-R-Forearm"] = 0.5,
  ["Bip001-L-Thigh"] = 0.45, ["Bip001-R-Thigh"] = 0.45,
  ["Bip001-L-Calf"] = 0.35, ["Bip001-R-Calf"] = 0.35,
}
-- the ends of her chains: they spin at most spin.ends, like every accessory body
local ENDS = { ["Bip001-Head"] = true, ["Bip001-L-Hand"] = true, ["Bip001-R-Hand"] = true, ["Bip001-L-Foot"] = true,
  ["Bip001-R-Foot"] = true }
-- the push along the blow, per bone, as a share of impact
local IMPACT = {
  ["Bip001-Spine2"] = 1.0, ["Bip001-Spine1"] = 0.8, ["Bip001-Head"] = 0.6, ["Bip001-L-Clavicle"] = 0.6,
  ["Bip001-R-Clavicle"] = 0.6, ["Bip001-Spine"] = 0.5, ["Bip001-Pelvis"] = 0.35,
}
local TWIST = { "Bip001-Pelvis", "Bip001-Spine", "Bip001-Spine1", "Bip001-Spine2" }

local speeds = {}       -- the capsule's last velocities while alive, newest last
local SPEED_SAMPLES = 10 -- ~330 ms at the 33 ms tick
local run = nil         -- the ragdoll in progress: { mesh, pac, t, masses = {bone = kg}, scales = {bone = scale} }
local dropped = {}      -- { comp, box, parent, socket, loc, rot }: weapons let go of
local extra = {}        -- other ragdolls to settle with hers (a split's copy)
local STILL = { "Bip001-Pelvis", "Bip001-Spine2", "Bip001-Head", "Bip001-L-Hand", "Bip001-R-Hand", "Bip001-L-Foot", "Bip001-R-Foot" }

function M.init(c)
  ctx = c
  try, valid = c.try, c.valid
end

-- every tick she is alive: remember how fast she moves
function M.track(pawn)
  local v = try(function() local x = pawn:GetVelocity(); return vec(x.X, x.Y, x.Z) end)
  if not v then return end
  speeds[#speeds + 1] = v
  if #speeds > SPEED_SAMPLES then table.remove(speeds, 1) end
end

local function bodies(mesh)
  local out = {}
  local pa = ctx.physics_of(mesh)
  if not valid(pa) then return out end
  try(function()
    pa.SkeletalBodySetups:ForEach(function(_, elem)
      local bs = elem:get()
      if valid(bs) then out[#out + 1] = bs.BoneName:ToString() end
    end)
  end)
  return out
end

local function mass(mesh, bone) return try(function() return mesh:GetBoneMass(FName(bone), true) end) end

-- the main body an accessory hangs from (its nearest ancestor in MASS), or nil
local function anchor_of(mesh, bone)
  local b = bone
  for _ = 1, 64 do
    local p = try(function() return mesh:GetParentBone(FName(b)):ToString() end)
    if not p or p == "None" then return nil end
    if MASS[p] then return p end
    b = p
  end
  return nil
end

-- keep: where the masses it changes are remembered for M.stop (nil for a split's copy, which is destroyed)
-- Accessories hanging off one main body share a budget of accessoryShare of its mass, each at most accessoryMaxKg:
-- the cape hangs off the upper arms (8 bodies a side) and the hair off the head (9), and at 0.8 kg a body they
-- weighed 6.4 kg on a 1.7 kg arm and 7.2 kg on a 4.5 kg head, and dragged both out of their joints
local function set_masses(mesh, g, keep)
  local before, after, acc, accBefore, n = 0, 0, 0, 0, 0
  local main = {}
  local cap, share, floor = g.accessoryMaxKg or 0.8, g.accessoryShare or 0.15, g.accessoryMinKg or 0.05
  local list, groups = {}, {}
  for _, bone in ipairs(bodies(mesh)) do
    local m = mass(mesh, bone)
    if m and m > 0 then
      list[#list + 1] = { bone = bone, m = m }
      if not MASS[bone] then
        local a = anchor_of(mesh, bone) or "?"
        groups[a] = (groups[a] or 0) + 1
        list[#list].anchor = a
      end
    end
  end
  for _, e in ipairs(list) do
    local bone, m = e.bone, e.m
    if MASS[bone] then
      main[#main + 1] = string.format("%s=%.0f", bone:gsub("Bip001%-", ""), m)
      if keep then keep.masses[bone] = m end
      local want = MASS[bone] * (g.massScale or 1.0)
      if try(function() mesh:SetMassOverrideInKg(FName(bone), want, true); return true end) then
        before, after = before + m, after + want
      end
    else
      accBefore = accBefore + m
      local want = cap
      local am = MASS[e.anchor]
      if am and share > 0 then want = math.max(math.min(cap, am * (g.massScale or 1.0) * share / groups[e.anchor]), floor) end
      if want > 0 and m > want then
        local s = try(function() return mesh:GetMassScale(FName(bone)) end) or 1.0
        if try(function() mesh:SetMassScale(FName(bone), s * want / m); return true end) then
          if keep then keep.scales[bone] = s end
          m = want
        end
      end
      acc, n = acc + m, n + 1
    end
  end
  local per = {}
  for a, c in pairs(groups) do per[#per + 1] = string.format("%s:%d", a:gsub("Bip001%-", ""), c) end
  table.sort(per)
  return string.format("masses %.0f -> %.0f kg (was %s), %d other bodies %.1f -> %.1f kg (on %s)", before, after,
    table.concat(main, " "), n, accBefore, acc, table.concat(per, " "))
end

-- every body's top angular speed (spin.main for the torso, arms and legs, spin.ends for the rest); put back to the
-- engine's default 3600 deg/s by M.stop
local SPIN_DEFAULT = 3600
-- split: a split's half, capped at spin.splitMain / spin.splitEnds instead
local function cap_spin(comp, g, max, split)
  local s = g.spin or {}
  if s.enabled == false then return "" end
  local n = 0
  local main, ends = s.main or 720, s.ends or 360
  if split then main, ends = s.splitMain or 360, s.splitEnds or 240 end
  for _, b in ipairs(bodies(comp)) do
    local w = max or ((MASS[b] and not ENDS[b]) and main or ends)
    if try(function() comp:SetPhysicsMaxAngularVelocityInDegrees(w, false, FName(b)); return true end) then n = n + 1 end
  end
  return string.format(", spin capped on %d bodies", n)
end

local function momentum(mesh, g)
  local k = g.momentum or 1.0
  if k <= 0 then return "" end
  local best, bs = nil, 0
  for _, v in ipairs(speeds) do
    local h = math.sqrt(v.X * v.X + v.Y * v.Y)
    if h + math.abs(v.Z) * 0.5 > bs then best, bs = v, h + math.abs(v.Z) * 0.5 end
  end
  if not best then return ", no momentum" end
  local v = vec(best.X * k, best.Y * k, best.Z * k)
  local l = len(v)
  local cap = g.momentumMax or 1500
  if l > cap then v = vec(v.X * cap / l, v.Y * cap / l, v.Z * cap / l); l = cap end
  if l < 20 then return ", standing still" end
  local ok = try(function() mesh:SetAllPhysicsLinearVelocity(v, true); return true end)
  return string.format(", momentum %.0f cm/s%s", l, ok and "" or " (failed)")
end

-- dir: the blow's direction (horizontal is enough), or nil
local function impact(mesh, g, dir, boost)
  local out = ""
  boost = boost or g.impact or 350
  if dir and boost > 0 then
    local h = math.sqrt(dir.X * dir.X + dir.Y * dir.Y)
    if h > 1e-3 then
      local up = g.impactUp or 0.15
      local d = vec(dir.X / h * (1 - up), dir.Y / h * (1 - up), up)
      local n = 0
      for bone, share in pairs(IMPACT) do
        if try(function() mesh:AddImpulse(vec(d.X * boost * share, d.Y * boost * share, d.Z * boost * share), FName(bone), true); return true end) then n = n + 1 end
      end
      out = string.format(", impact %.0f cm/s on %d bones", boost, n)
    end
  end
  local tw = g.twist or 90
  if tw > 0 then
    local w = vec(0, 0, (math.random() < 0.5 and -1 or 1) * tw * (0.6 + 0.4 * math.random()))
    for _, bone in ipairs(TWIST) do try(function() mesh:AddAngularImpulseInDegrees(w, FName(bone), true) end) end
    out = out .. string.format(", twist %.0f deg/s", w.Z)
  end
  return out
end

local function drive(pac, bone, k, t)
  local s = t.strength or 800
  local data = { bIsLocalSimulation = true, OrientationStrength = s * k, AngularVelocityStrength = s * k * (t.damping or 0.1),
    PositionStrength = 0, VelocityStrength = 0, MaxLinearForce = 0, MaxAngularForce = 0 }
  return try(function() pac:ApplyPhysicalAnimationSettings(FName(bone), data); return true end)
end

local function tone_start(pawn, mesh, g)
  local t = g.tone or {}
  if t.enabled == false then return ", no tone" end
  local cls = try(function() return StaticFindObject("/Script/Engine.PhysicalAnimationComponent") end)
  if not valid(cls) then return ", tone: no PhysicalAnimationComponent class" end
  local pac = try(function()
    return pawn:AddComponentByClass(cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }, false)
  end)
  if not valid(pac) then return ", tone: component not created" end
  run.pac = pac
  if not try(function() pac:SetSkeletalMeshComponent(mesh); return true end) then return ", tone: no mesh" end
  local n = 0
  for bone, k in pairs(TONE) do if drive(pac, bone, k, t) then n = n + 1 end end
  try(function() pac:SetStrengthMultiplyer(1.0) end)
  return string.format(", tone on %d joints (%.0f, hold %.2f s, fade %.2f s)", n, t.strength or 800, t.hold or 0.25, t.fade or 1.4)
end

local function tone_stop()
  local pac = run and run.pac
  if not valid(pac) then return end
  -- release the drives before the component goes (gore recreates the bodies on recovery)
  try(function() pac:SetStrengthMultiplyer(0) end)
  try(function() pac:SetSkeletalMeshComponent(nil) end)
  try(function() pac:K2_DestroyComponent(pac) end)
  run.pac = nil
end

local WEAPON_SLOTS = { [5] = true, [6] = true, [7] = true, [8] = true }
local function weapons(pawn)
  local out = {}
  try(function()
    pawn.MeshInfoList:ForEach(function(_, e)
      local info = e:get()
      local c = info.MeshComponent
      if WEAPON_SLOTS[info.MeshSlot] and valid(c) and try(function() return c:IsVisible() end) == true
        and valid(try(function() return c.SkeletalMesh end)) then out[#out + 1] = c end
    end)
  end)
  return out
end

local function weapons_back()
  local n = 0
  for _, d in ipairs(dropped) do
    local w = d.comp
    if valid(w) and valid(d.parent) then
      if try(function()
        w:K2_AttachToComponent(d.parent, d.socket or FName("None"), 2, 2, 2, false)
        if d.loc and d.rot then w:K2_SetRelativeLocationAndRotation(d.loc, d.rot, false, {}, true) end
        return true
      end) then n = n + 1 end
    end
    if valid(d.box) then try(function() d.box:K2_DestroyComponent(d.box) end) end
  end
  dropped = {}
  return n
end

-- each weapon rides an invisible box of its mesh's size, simulated, starting with her hand's speed plus a toss
local function drop_weapons(pawn, mesh, g)
  if g.dropWeapon == false then return "" end
  local cls = try(function() return StaticFindObject("/Script/Engine.BoxComponent") end)
  if not valid(cls) then return ", weapons: no BoxComponent class" end
  local hv = try(function() local v = mesh:GetPhysicsLinearVelocity(FName("Bip001-R-Hand")); return vec(v.X, v.Y, v.Z) end)
    or speeds[#speeds] or vec(0, 0, 0)
  local id = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }
  local names = {}
  for _, w in ipairs(weapons(pawn)) do
    -- the imported bounds (GetBounds adds the asset's bounds extension: 217 cm for her sword), capped at weaponMaxCm
    local function bnd(fn) return try(function() local x = fn(); return { o = vec(x.Origin.X, x.Origin.Y, x.Origin.Z),
      e = vec(x.BoxExtent.X, x.BoxExtent.Y, x.BoxExtent.Z) } end) end
    local b = bnd(function() return w.SkeletalMesh:GetImportedBounds() end) or bnd(function() return w.SkeletalMesh:GetBounds() end)
    if b then
      local half = (g.weaponMaxCm or 120) / 2
      b.e = vec(math.min(b.e.X, half), math.min(b.e.Y, half), math.min(b.e.Z, half))
    end
    local box = b and try(function() return pawn:AddComponentByClass(cls, true, id, false) end)
    if valid(box) then
      local d = { comp = w, box = box, parent = try(function() return w:GetAttachParent() end),
        socket = try(function() return w:GetAttachSocketName() end),
        loc = try(function() local v = w.RelativeLocation; return vec(v.X, v.Y, v.Z) end),
        rot = try(function() local r = w.RelativeRotation; return { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end) }
      dropped[#dropped + 1] = d
      local ok = try(function()
        local wl, f, r, u = w:K2_GetComponentLocation(), w:GetForwardVector(), w:GetRightVector(), w:GetUpVector()
        local o = b.o
        local at = vec(wl.X + f.X * o.X + r.X * o.Y + u.X * o.Z, wl.Y + f.Y * o.X + r.Y * o.Y + u.Y * o.Z,
          wl.Z + f.Z * o.X + r.Z * o.Y + u.Z * o.Z)
        box:K2_SetWorldLocationAndRotation(at, w:K2_GetComponentRotation(), false, {}, true)
        box:SetBoxExtent(vec(math.max(b.e.X, 1.5), math.max(b.e.Y, 1.5), math.max(b.e.Z, 1.5)), false)
        box:SetHiddenInGame(true, false)
        -- Pawn: not her capsule (or the player's); PhysicsBody: it lands on her as well as the floor
        box:SetCollisionProfileName(FName("PhysicsActor"), true)
        box:SetCollisionResponseToChannel(2, 0)
        box:SetCollisionEnabled(3)
        try(function() box.BodyInstance.bUseCCD = true end)
        box:SetSimulatePhysics(true)
        box:SetMassOverrideInKg(FName("None"), g.weaponKg or 1.5, true)
        w:K2_AttachToComponent(box, FName("None"), 1, 1, 1, false)
        local toss = g.weaponToss or 150
        local a = math.random() * math.pi * 2
        box:SetPhysicsLinearVelocity(vec(hv.X + math.cos(a) * toss, hv.Y + math.sin(a) * toss, hv.Z + toss * 0.6), false, FName("None"))
        box:SetPhysicsAngularVelocityInDegrees(vec((math.random() - 0.5) * 720, (math.random() - 0.5) * 720,
          (math.random() - 0.5) * 360), false, FName("None"))
        return true
      end)
      names[#names + 1] = string.format("%s %.0fx%.0fx%.0f%s", tostring(try(function() return w.SkeletalMesh:GetFName():ToString() end)),
        b.e.X * 2, b.e.Y * 2, b.e.Z * 2, ok and "" or " (failed)")
    end
  end
  if #names == 0 then return ", no weapon showing" end
  return ", dropped " .. table.concat(names, ", ")
end

-- stretch probe: every main joint's length (bone to the main bone above it) at the start, and how far it is off later
-- (logged at STRETCH_AT seconds, the worst three). A joint the solver can't hold shows as centimetres here
local STRETCH_AT = { 0.5, 1.0, 2.0, 3.0 }
local function addr(o) return try(function() return o:GetAddress() end) end
-- bones gore cut through (limbs, the split's spine break), on the mesh at severedOn: their joints come apart on
-- purpose, so the probe leaves out every joint whose chain up to its anchor crosses one. Kept across M.start (a
-- piece cut while she stands, then her death ragdoll) until another mesh starts
local severed, severedOn = {}, nil
local function crosses_cut(mesh, bone, up)
  for s in pairs(severed) do
    if s == bone then return true end
    local below = try(function() return mesh:BoneIsChildOf(FName(bone), FName(s)) end) == true
    local upBelow = s == up or try(function() return mesh:BoneIsChildOf(FName(up), FName(s)) end) == true
    if below and not upBelow then return true end
  end
  return false
end
local function joint_lengths(mesh)
  local out = {}
  for bone in pairs(MASS) do
    local up = anchor_of(mesh, bone)
    local a = up and try(function() local v = mesh:GetSocketLocation(FName(bone)); return vec(v.X, v.Y, v.Z) end)
    local b = a and try(function() local v = mesh:GetSocketLocation(FName(up)); return vec(v.X, v.Y, v.Z) end)
    if b then out[bone] = { up = up, l = len(vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z)) } end
  end
  return out
end
local function stretch_report(mesh, base)
  local now = joint_lengths(mesh)
  local list = {}
  for bone, j in pairs(base) do
    local n = now[bone]
    if n and not crosses_cut(mesh, bone, j.up) then list[#list + 1] = { bone = bone, d = n.l - j.l } end
  end
  table.sort(list, function(x, y) return math.abs(x.d) > math.abs(y.d) end)
  local parts = {}
  for i = 1, math.min(3, #list) do parts[#parts + 1] = string.format("%s %+.1f", list[i].bone:gsub("Bip001%-", ""), list[i].d) end
  return table.concat(parts, ", ")
end

-- how far each limb joint rolled about its bone since the start (the axis from the bone to the next one down): an
-- arm lay twisted as if it had spun round many times (eighteenth playtest), while its limits allow 5 deg at the
-- shoulder and none at the elbow. { parent, next bone down }
local ROLL = {
  ["Bip001-L-UpperArm"] = { "Bip001-L-Clavicle", "Bip001-L-Forearm" }, ["Bip001-R-UpperArm"] = { "Bip001-R-Clavicle", "Bip001-R-Forearm" },
  ["Bip001-L-Forearm"] = { "Bip001-L-UpperArm", "Bip001-L-Hand" }, ["Bip001-R-Forearm"] = { "Bip001-R-UpperArm", "Bip001-R-Hand" },
  ["Bip001-L-Hand"] = { "Bip001-L-Forearm", "Bip001-L-Finger2" }, ["Bip001-R-Hand"] = { "Bip001-R-Forearm", "Bip001-R-Finger2" },
  ["Bip001-L-Thigh"] = { "Bip001-Pelvis", "Bip001-L-Calf" }, ["Bip001-R-Thigh"] = { "Bip001-Pelvis", "Bip001-R-Calf" },
  ["Bip001-L-Calf"] = { "Bip001-L-Thigh", "Bip001-L-Foot" }, ["Bip001-R-Calf"] = { "Bip001-R-Thigh", "Bip001-R-Foot" },
  ["Bip001-L-Foot"] = { "Bip001-L-Calf", "Bip001-L-Toe0" }, ["Bip001-R-Foot"] = { "Bip001-R-Calf", "Bip001-R-Toe0" },
}
local function quat(mesh, b)
  return try(function() local r = mesh:GetSocketTransform(FName(b), 0).Rotation; return { r.X, r.Y, r.Z, r.W } end)
end
local function qmul(a, b)
  return { a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2], a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
    a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4], a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3] }
end
local function qconj(a) return { -a[1], -a[2], -a[3], a[4] } end
local function loc(mesh, b) return try(function() local l = mesh:GetSocketLocation(FName(b)); return vec(l.X, l.Y, l.Z) end) end
-- per joint: the child relative to its parent, and (at the start) the bone's own axis in the child's frame
local function joint_rolls(mesh, axes)
  local out = {}
  for c, pe in pairs(ROLL) do
    local qc, qp = quat(mesh, c), quat(mesh, pe[1])
    if qc and qp then
      local j = { rel = qmul(qconj(qp), qc) }
      if axes then
        local a, b = loc(mesh, c), loc(mesh, pe[2])
        local d = a and b and vec(b.X - a.X, b.Y - a.Y, b.Z - a.Z)
        local l = d and len(d)
        if l and l > 1e-3 then
          local v = qmul(qmul(qconj(qc), { d.X / l, d.Y / l, d.Z / l, 0 }), qc)
          j.axis = { v[1], v[2], v[3] }
        end
      end
      out[c] = j
    end
  end
  return out
end
local function roll_report(mesh, base)
  local now, list = joint_rolls(mesh), {}
  for b, j0 in pairs(base or {}) do
    local r = now[b]
    if r and j0.axis and not severed[b] then
      -- the turn since the start, in the child's own frame, and its twist about the bone's axis
      local d = qmul(qconj(j0.rel), r.rel)
      if d[4] < 0 then d = { -d[1], -d[2], -d[3], -d[4] } end
      local a = j0.axis
      list[#list + 1] = { b = b, roll = math.deg(2 * math.atan(d[1] * a[1] + d[2] * a[2] + d[3] * a[3], d[4])),
        all = math.deg(2 * math.acos(math.min(1, d[4]))) }
    end
  end
  table.sort(list, function(x, y) return math.abs(x.roll) > math.abs(y.roll) end)
  local parts = {}
  for i = 1, math.min(4, #list) do
    parts[#parts + 1] = string.format("%s %+.0f (turned %.0f)", list[i].b:gsub("Bip001%-", ""), list[i].roll, list[i].all)
  end
  return table.concat(parts, ", ")
end

-- the buzz hunt (tune.active.bisect, temporary): F7 / F11 ragdolls take turns at three setups, and the first two
-- seconds log which bodies shake (angular velocity flipping round between ticks). She buzzed in every joint in mid-air
-- (eighteenth playtest) with self-collision off, the tiny hard limits locked and tone off on the split
local VARIANTS = { "as it is", "plain engine ragdoll (no masses, spin caps, clamp or tone)", "heavy accessories (0.4 kg at least, up to 1 kg)" }
local bisect_n = 0
local function variant_cfg(g, v)
  if v ~= 3 then return g end
  return setmetatable({ accessoryShare = 1.0, accessoryMinKg = 0.4, accessoryMaxKg = 1.0 }, { __index = g })
end
local function buzz_tick(comps)
  run.buzz = run.buzz or {}
  for i, comp in ipairs(comps) do
    if valid(comp) then
      local key = addr(comp) or i
      local per = run.buzz[key]
      if not per then per = { i = i, names = bodies(comp), b = {} }; run.buzz[key] = per end
      for _, b in ipairs(per.names) do
        local w = try(function() local x = comp:GetPhysicsAngularVelocityInDegrees(FName(b)); return vec(x.X, x.Y, x.Z) end)
        if w then
          local e = per.b[b] or { n = 0, flips = 0, sum = 0 }
          per.b[b] = e
          local l = len(w)
          if e.w and l > 90 and len(e.w) > 90 and (w.X * e.w.X + w.Y * e.w.Y + w.Z * e.w.Z) < 0 then e.flips = e.flips + 1 end
          e.w, e.n, e.sum = w, e.n + 1, e.sum + l
        end
      end
    end
  end
end
local function buzz_report()
  local list = {}
  for _, per in pairs(run.buzz or {}) do
    for b, e in pairs(per.b) do
      if e.n > 0 then list[#list + 1] = { name = string.format("%d/%s", per.i, b:gsub("Bip001%-", "")), f = e.flips / e.n, m = e.sum / e.n } end
    end
  end
  table.sort(list, function(x, y) return x.f > y.f or (x.f == y.f and x.m > y.m) end)
  local parts, shaking = {}, 0
  for _, e in ipairs(list) do if e.f >= 0.2 then shaking = shaking + 1 end end
  for i = 1, math.min(10, #list) do parts[#parts + 1] = string.format("%s %.0f%% (%.0f deg/s)", list[i].name, list[i].f * 100, list[i].m) end
  return string.format("%d of %d bodies flipping on 20%%+ of ticks; top: %s", shaking, #list, table.concat(parts, ", "))
end

-- kind: "death" or "sandbox"; dir: the blow's direction for the impact (sandbox), or where it came from when the
-- game's death key gives no impulse (death)
function M.start(pawn, mesh, kind, dir)
  local g = cfg()
  if g.enabled == false then return end
  if run then M.stop(pawn) end
  if addr(mesh) ~= severedOn then severed, severedOn = {}, addr(mesh) end
  run = { mesh = mesh, t = 0, masses = {}, scales = {}, still = 0 }
  run.joints, run.probe = joint_lengths(mesh), 1
  run.rolls = joint_rolls(mesh, true)
  extra = {}
  if g.bisect and kind == "sandbox" then
    bisect_n = bisect_n + 1
    run.variant = (bisect_n - 1) % #VARIANTS + 1
    log(string.format("bisect: ragdoll %d is variant %d, %s", bisect_n, run.variant, VARIANTS[run.variant]))
    g = variant_cfg(g, run.variant)
  end
  local plain = run.variant == 2
  local parts = plain and {} or { set_masses(mesh, g, run), cap_spin(mesh, g) }
  if kind == "death" then
    parts[#parts + 1] = momentum(mesh, g)
    -- the death key pushes after ImpulseDelayTime (0.01 s), so its direction is read a couple of ticks later
    run.pawn, run.impactAt, run.hint = pawn, 0.06, dir
  else
    parts[#parts + 1] = impact(mesh, g, dir)
  end
  if not plain then parts[#parts + 1] = tone_start(pawn, mesh, g) end
  parts[#parts + 1] = drop_weapons(pawn, mesh, g)
  speeds = {}
  log(kind .. ": " .. table.concat(parts, ""))
end

-- a piece cut off her while she stands (gore, F9): no ragdoll runs, so give her bodies their human masses now; put
-- back by M.stop like a ragdoll's (a ragdoll that starts meanwhile takes over)
function M.piece(pawn, mesh)
  local g = cfg()
  if g.enabled == false or run then return nil end
  run = { mesh = mesh, t = 0, masses = {}, scales = {}, piece = true, still = 0 }
  local r = set_masses(mesh, g, run) .. cap_spin(mesh, g)
  log("piece: " .. r)
  return r
end

-- the blow's direction: the death key's impulse, else where main.lua says it came from, else from where she was hit
-- through her pelvis
local function blow(pawn, mesh, hint)
  local d = try(function() local v = pawn.RagdollInfo.ImpulseValue; return vec(v.X, v.Y, v.Z) end)
  if d and len(d) > 1e-3 then return d, "key" end
  if hint and len(hint) > 1e-3 then return hint, "attack" end
  local h = try(function() local v = pawn.RagdollInfo.HitLocation; return vec(v.X, v.Y, v.Z) end)
  local p = try(function() local v = mesh:GetSocketLocation(FName("Bip001-Pelvis")); return vec(v.X, v.Y, v.Z) end)
  if h and p and len(h) > 0 then
    d = vec(p.X - h.X, p.Y - h.Y, 0)
    if len(d) > 1 then return d, "hit" end
  end
  return nil, "none"
end

-- a split half's gone limbs, by component address: they fall free, invisible, and aren't the half's to wait for
local freed = {}
-- a body that still simulates and that the half still shows
local function live(comp, b)
  local f = freed[addr(comp)]
  if f and f[b] then return false end
  return try(function() return comp:IsSimulatingPhysics(FName(b)) end) ~= false
end

-- the fastest of a ragdoll's main bodies, cm/s, and which
local function speed(comp)
  local top, which = 0, nil
  for _, b in ipairs(STILL) do
    local v = live(comp, b) and try(function() local x = comp:GetPhysicsLinearVelocity(FName(b)); return vec(x.X, x.Y, x.Z) end)
    if v and len(v) > top then top, which = len(v), b end
  end
  return top, which
end

-- the fastest turning of a ragdoll's main bodies, deg/s, and which (shaking in place shows here, not in speed)
local function turning(comp)
  local top, which = 0, nil
  for _, b in ipairs(STILL) do
    local w = live(comp, b) and try(function() local x = comp:GetPhysicsAngularVelocityInDegrees(FName(b)); return vec(x.X, x.Y, x.Z) end)
    if w and len(w) > top then top, which = len(w), b end
  end
  return top, which
end

-- where the main bodies are, keyed "<component n>/<bone>"
local function where(comps)
  local out = {}
  for i, comp in ipairs(comps) do
    if valid(comp) then
      for _, b in ipairs(STILL) do
        local p = live(comp, b) and try(function() local x = comp:GetSocketLocation(FName(b)); return vec(x.X, x.Y, x.Z) end)
        if p then out[i .. "/" .. b] = p end
      end
    end
  end
  return out
end

local function sleep(comp)
  local n = 0
  for _, b in ipairs(bodies(comp)) do
    if try(function() comp:PutRigidBodyToSleep(FName(b)); return true end) then n = n + 1 end
  end
  return n
end

-- a split holds her still until it opens, then she falls in halves: her bodies stop (gravity off, velocities zeroed
-- every tick) and get back the velocities they had (the death key's push, her momentum, F7's impulse) on release.
-- The tone stays at full strength meanwhile, so she holds her pose. Released after HOLD_MAX s whatever happens
local HOLD_MAX = 1.0
local function velocities(comp)
  local out = {}
  for _, b in ipairs(bodies(comp)) do
    local v = try(function() local x = comp:GetPhysicsLinearVelocity(FName(b)); return vec(x.X, x.Y, x.Z) end)
    local w = try(function() local x = comp:GetPhysicsAngularVelocityInDegrees(FName(b)); return vec(x.X, x.Y, x.Z) end)
    if v and w then out[b] = { v = v, w = w } end
  end
  return out
end
local function gravity(comp, on)
  try(function() comp:SetEnableGravity(on) end)
  for _, b in ipairs(bodies(comp)) do try(function() comp:SetEnableBodyGravity(on, FName(b)) end) end
end
local function stop_all(comp)
  try(function() comp:SetAllPhysicsLinearVelocity(vec(0, 0, 0), false) end)
  try(function() comp:SetAllPhysicsAngularVelocityInDegrees(vec(0, 0, 0), false) end)
end

function M.hold(mesh)
  -- by address: UE4SS hands out a new wrapper per call, so two wrappers of her mesh never compare equal
  if not run or run.piece or run.held or addr(run.mesh) ~= addr(mesh) then return false end
  run.held = { t = 0, vel = velocities(mesh) }
  gravity(mesh, false)
  stop_all(mesh)
  log(string.format("held still for the split at %.2f s", run.t))
  return true
end

function M.release()
  if not (run and run.held) then return end
  local held, mesh = run.held, run.mesh
  run.held = nil
  if not valid(mesh) then return end
  gravity(mesh, true)
  -- the halves go on as she was going: each body its own velocity again, the split's copy the same per bone
  local n = 0
  for _, comp in ipairs({ mesh, table.unpack(extra) }) do
    if valid(comp) then
      for b, e in pairs(held.vel) do
        try(function() comp:SetPhysicsLinearVelocity(e.v, false, FName(b)) end)
        try(function() comp:SetPhysicsAngularVelocityInDegrees(e.w, false, FName(b)) end)
        n = n + 1
      end
      try(function() comp:WakeAllRigidBodies() end)
    end
  end
  log(string.format("released after %.2f s held (%d body velocities back)", held.t, n))
end

-- a split's copy: her masses (it came with the outfit's 100 kg chest bodies and 80 kg cape links), and it settles
-- with her. No tone: it plays no animation, so the drives would pull it towards the bind pose (arms out). Her half
-- lets go of its tone too: with it her half stood stiff on its one leg and toppled over slowly like a plank while
-- the copy, limp, dropped, and the drives pulling her joints towards her live animation kept her half shaking on
-- the floor (eighteenth playtest). Both halves spin slower (spin.splitMain / splitEnds) and settle sooner
-- (settle.splitMost)
function M.add_body(comp)
  if not valid(comp) then return end
  local g = variant_cfg(cfg(), run and run.variant)
  if not (run and run.variant == 2) then log("split copy: " .. set_masses(comp, g) .. cap_spin(comp, g, nil, true)) end
  if not run then return end
  extra[#extra + 1] = comp
  run.split = true
  local had = valid(run.pac)
  tone_stop()
  run.toneDone = true
  log(string.format("split: %s, her half%s", had and "tone off" or "no tone", run.variant == 2 and "" or cap_spin(run.mesh, g, nil, true)))
end

-- the tone's strength now (the fade, or what settling left of it)
local function tone_set(s)
  if valid(run.pac) then try(function() run.pac:SetStrengthMultiplyer(s) end) end
end

-- the engine's own cap (cap_spin) doesn't hold: her head turned at 1000-8000 deg/s shaking on the floor, her hands
-- at 2000 (eighteenth playtest). Every tick each main body turning faster than its cap is slowed down to it.
-- Flung bodies too: a leg cut that switched her fall to the ragdoll shot her right hand off at 15000 cm/s and her
-- head at 6000 with the pelvis under 800, the arm 3 m out of its socket for half a second (nineteenth playtest).
-- A main body faster than the torso by more than linearOver (and over linearFloor) is slowed to that.
local TORSO = { "Bip001-Pelvis", "Bip001-Spine", "Bip001-Spine1", "Bip001-Spine2" }
local function lin_vel(comp, b)
  return live(comp, b) and try(function() local x = comp:GetPhysicsLinearVelocity(FName(b)); return vec(x.X, x.Y, x.Z) end)
end
local function clamp_flung(comp, s)
  if s.linear == false then return end
  local ref = 0
  for _, b in ipairs(TORSO) do
    local v = lin_vel(comp, b)
    if v then ref = math.max(ref, len(v)) end
  end
  local cap = math.max(s.linearFloor or 1500, ref + (s.linearOver or 1200))
  for b in pairs(MASS) do
    local v = lin_vel(comp, b)
    local l = v and len(v)
    if l and l > cap then
      local k = cap / l
      try(function() comp:SetPhysicsLinearVelocity(vec(v.X * k, v.Y * k, v.Z * k), false, FName(b)) end)
      run.flung = (run.flung or 0) + 1
      if run.flung == 1 then
        log(string.format("flung: %s at %.0f cm/s (torso %.0f) slowed to %.0f at %.2f s", b, l, ref, cap, run.t or 0))
      end
    end
  end
end
local function clamp_spin()
  local s = cfg().spin or {}
  if s.enabled == false or s.clamp == false or run.asleep or run.held or run.variant == 2 then return end
  local comps = { run.mesh }
  for _, c in ipairs(extra) do comps[#comps + 1] = c end
  local main, ends = s.main or 720, s.ends or 360
  if run.split then main, ends = s.splitMain or 360, s.splitEnds or 240 end
  for _, comp in ipairs(comps) do
    if valid(comp) then
      clamp_flung(comp, s)
      for b in pairs(MASS) do
        local cap = ENDS[b] and ends or main
        local w = live(comp, b) and try(function() local x = comp:GetPhysicsAngularVelocityInDegrees(FName(b)); return vec(x.X, x.Y, x.Z) end)
        local l = w and len(w)
        if l and l > cap then
          local k = cap / l
          try(function() comp:SetPhysicsAngularVelocityInDegrees(vec(w.X * k, w.Y * k, w.Z * k), false, FName(b)) end)
          run.clamped = (run.clamped or 0) + 1
        end
      end
    end
  end
end

local function settle(dt)
  local st = cfg().settle or {}
  local comps = { run.mesh }
  for _, c in ipairs(extra) do comps[#comps + 1] = c end
  -- the main bodies' trail over the last window: how far each got (shivering in place goes nowhere)
  local win = st.window or 0.5
  run.trail = run.trail or {}
  local now = where(comps)
  table.insert(run.trail, { t = run.t, at = now })
  while #run.trail > 1 and run.trail[2].t <= run.t - win do table.remove(run.trail, 1) end
  if st.enabled == false or run.t < (st.after or 1.5) then return end
  local top, which, wc = 0, nil, nil
  for i, c in ipairs(comps) do
    if valid(c) then
      local s, b = speed(c)
      if s > top then top, which, wc = s, b, i end
    end
  end
  local drift, far = 0, nil
  local old = run.trail[1]
  if old and run.t - old.t >= win * 0.9 then
    for k, p in pairs(now) do
      local q = old.at[k]
      if q then
        local d = len(vec(p.X - q.X, p.Y - q.Y, p.Z - q.Z))
        if d > drift then drift, far = d, k end
      end
    end
  else
    drift = math.huge
  end
  if run.asleep then
    if top > (st.wake or 60) then
      run.asleep, run.still = false, 0
      log(string.format("woken (%.0f cm/s, %s)", top, tostring(which)))
    end
    return
  end
  local calm = top < (st.speed or 15) or drift < (st.drift or 2)
  -- a ragdoll that has been only shivering for long enough settles whatever its speed
  local most = run.split and (st.splitMost or 1.5) or (st.most or 6)
  if not calm and run.t >= most and drift < (st.driftMost or 6) then calm = true end
  if calm then
    if run.still == 0 then
      -- no tone pulling her against the floor while she comes to rest
      run.toneHeld = true
      tone_set(0)
    end
    run.still = run.still + dt
  else
    if run.still > 0 and run.toneHeld then
      run.toneHeld = false
      tone_set(run.toneNow or 1)
    end
    run.still = 0
  end
  -- every 2 s she isn't lying still: what keeps her going
  run.nextWhy = run.nextWhy or (st.after or 1.5)
  if run.still == 0 and run.t >= run.nextWhy then
    run.nextWhy = run.t + 2
    local wt, wb, wi = 0, nil, 0
    for i, c in ipairs(comps) do
      if valid(c) then local w, b = turning(c); if w > wt then wt, wb, wi = w, b, i end end
    end
    log(string.format("not settled at %.1f s: fastest %s %.0f cm/s (body %d), drift %.1f cm (%s) over %.1f s, turning %s %.0f deg/s (body %d)",
      run.t, tostring(which), top, wc or 0, drift == math.huge and -1 or drift, tostring(far), win, tostring(wb), wt, wi))
  end
  if run.still < (st.time or 0.5) then return end
  run.asleep = true
  tone_stop()
  local n = 0
  for _, c in ipairs(comps) do if valid(c) then n = n + sleep(c) end end
  log(string.format("settled after %.2f s (%.0f cm/s, drift %.1f cm): tone off, %d bodies asleep, %d spins slowed to the cap, %d flung bodies slowed", run.t, top,
    drift == math.huge and -1 or drift, n, run.clamped or 0, run.flung or 0))
  if run.rolls then log("rolled about the bone since the start (deg): " .. roll_report(run.mesh, run.rolls)) end
end

function M.tick(dt)
  if not run then return end
  if run.held then
    run.held.t = run.held.t + dt
    if not valid(run.mesh) or run.held.t >= HOLD_MAX then M.release(); return end
    stop_all(run.mesh)
    return
  end
  run.t = run.t + dt
  if run.probe and STRETCH_AT[run.probe] and run.t >= STRETCH_AT[run.probe] then
    log(string.format("stretch at %.1f s (cm off the start): %s", run.t, stretch_report(run.mesh, run.joints)))
    run.probe = run.probe + 1
  end
  -- a piece cut off a living Eve settles too: lying on the floor it shook and spun like her ragdoll did before the
  -- settle check (fifteenth playtest's waist cut); only its own bodies simulate, so only they are watched
  if cfg().buzzLog and run.t <= 2.0 and not run.piece then
    local comps = { run.mesh }
    for _, c in ipairs(extra) do comps[#comps + 1] = c end
    buzz_tick(comps)
  elseif run.buzz and not run.buzzed then
    run.buzzed = true
    log(string.format("buzz over the first 2 s%s: %s", run.variant and (" (variant " .. run.variant .. ")") or "", buzz_report()))
  end
  settle(dt)
  if not run then return end
  clamp_spin()
  if run.impactAt and run.t >= run.impactAt then
    run.impactAt = nil
    local d, from = blow(run.pawn, run.mesh, run.hint)
    log(string.format("blow from %s%s", from, impact(run.mesh, cfg(), d)))
  end
  if not run.pac or run.toneDone then return end
  local t = cfg().tone or {}
  local hold, fade, rest = t.hold or 0.35, t.fade or 2.5, math.max(t.rest or 0.1, 0)
  -- landing ends the tone: pulled towards a standing pose with the floor and her own body in the way, every joint
  -- jittered until each part found the ground and the fade ran out (eighteenth playtest)
  local vz = try(function() return run.mesh:GetPhysicsLinearVelocity(FName("Bip001-Pelvis")).Z end)
  if vz then
    run.fall = math.min(run.fall or 0, vz)
    if t.landOff ~= false and run.fall < -(t.fallSpeed or 150) and vz > -(t.landSpeed or 40) then
      tone_stop()
      run.toneDone = true
      log(string.format("tone off on landing at %.2f s (fell at %.0f cm/s)", run.t, -run.fall))
      return
    end
  end
  if run.t <= hold then return end
  local x = (run.t - hold) / math.max(fade, 0.01)
  if x >= 1 then
    if rest <= 0 then
      tone_stop()
      log(string.format("tone gone after %.2f s", run.t))
    else
      run.toneNow = rest
      if not run.toneHeld then tone_set(rest) end
      run.toneDone = true
      log(string.format("tone down to %.2f after %.2f s", rest, run.t))
    end
    return
  end
  -- smooth fade, down to the resting tone (settling holds it at 0 meanwhile)
  run.toneNow = rest + (1 - rest) * (1 - x * x * (3 - 2 * x))
  if not run.toneHeld then tone_set(run.toneNow) end
end

-- a joint gore broke (no tone change): left out of the stretch probe
function M.broken(mesh, bone)
  local a = addr(mesh)
  if a ~= severedOn then severed, severedOn = {}, a end
  if bone then severed[tostring(bone)] = true end
end

-- a split half let go of a body (a limb that went with the other half): the settle check leaves it out
function M.freed(comp, bone)
  local a = addr(comp)
  if not a then return end
  freed[a] = freed[a] or {}
  freed[a][tostring(bone)] = true
end

-- a limb came off: its root stops pulling towards the body (its own joints keep their fading tone)
function M.on_cut(mesh, bone)
  M.broken(mesh, bone)
  if not (run and valid(run.pac)) then return end
  drive(run.pac, bone, 0, cfg().tone or {})
end

function M.stop(pawn)
  if run and run.held and valid(run.mesh) then gravity(run.mesh, true) end
  if run then run.held = nil end
  local nw = #dropped > 0 and weapons_back() or nil
  if nw then log(string.format("%d weapons back on their sockets", nw)) end
  if not run then return end
  tone_stop()
  local mesh = run.mesh
  local n = 0
  if valid(mesh) then
    for bone, m in pairs(run.masses) do if try(function() mesh:SetMassOverrideInKg(FName(bone), m, true); return true end) then n = n + 1 end end
    for bone, s in pairs(run.scales) do if try(function() mesh:SetMassScale(FName(bone), s); return true end) then n = n + 1 end end
    cap_spin(mesh, cfg(), SPIN_DEFAULT)
  end
  run = nil
  freed = {}
  log(string.format("stopped, %d masses put back", n))
end

-- a new Eve (the level reloaded): drop what was held from the old one without touching it
function M.forget()
  run, speeds, dropped, extra = nil, {}, {}, {}
  severed, severedOn = {}, nil
  freed = {}
end

return M
