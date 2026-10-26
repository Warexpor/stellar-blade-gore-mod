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
local function vlog(s) if ctx.tune.verboseLog then log(s) end end -- (the settle watch's lines: tune.verboseLog only)
local try, valid = nil, nil

local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local function len(v) return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
local function addr(o) return try(function() return o:GetAddress() end) end

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
local run = nil         -- the ragdoll in progress: { mesh, pac, t, masses = {bone = kg} }
local dropped = {}      -- { comp, box, parent, socket, loc, rot }: weapons let go of
local gripped = {}      -- address -> { comp, parent, socket, loc, rot }: weapons still in her hand in a ragdoll death
local extra = {}        -- other ragdolls to settle with hers (a split's copy)
-- her hands opening once a weapon left them (tune.active.grip.open): hand bone -> { t, comps = { {comp, bone index} } }
local eased = {}
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

-- by physics asset address: its bodies' bones, and each accessory's anchor (anchor_of), read once. Read again for
-- every death, cut piece and split copy (a name per body and a parent per bone up the chain), the copy's masses took
-- 36 ms of the split's opening frame (playtest)
local layouts = {}
local function layout(mesh)
  local pa = ctx.physics_of(mesh)
  if not valid(pa) then return nil end
  local a = try(function() return pa:GetAddress() end)
  local l = a and layouts[a]
  if l and valid(l.pa) then return l end
  l = { pa = pa, bones = {}, anchor = {} }
  try(function()
    pa.SkeletalBodySetups:ForEach(function(_, elem)
      local bs = elem:get()
      if valid(bs) then l.bones[#l.bones + 1] = bs.BoneName:ToString() end
    end)
  end)
  if a then layouts[a] = l end
  return l
end
local function bodies(mesh)
  local l = layout(mesh)
  return l and l.bones or {}
end

local function mass(mesh, bone) return try(function() return mesh:GetBoneMass(FName(bone), true) end) end

-- the main body an accessory hangs from (its nearest ancestor in MASS), or nil
local function anchor_walk(mesh, bone)
  local b = bone
  for _ = 1, 64 do
    local p = try(function() return mesh:GetParentBone(FName(b)):ToString() end)
    if not p or p == "None" then return nil end
    if MASS[p] then return p end
    b = p
  end
  return nil
end
local function anchor_of(mesh, bone)
  local l = layout(mesh)
  if not l then return anchor_walk(mesh, bone) end
  local a = l.anchor[bone]
  if a == nil then a = anchor_walk(mesh, bone) or false; l.anchor[bone] = a end
  return a or nil
end

-- keep: where the masses it changes are remembered for M.stop (nil for a split's copy, which is destroyed)
-- Accessories hanging off one main body share a budget of accessoryShare of its mass, each at most accessoryMaxKg:
-- the cape hangs off the upper arms (8 bodies a side) and the hair off the head (9), and at 0.8 kg a body they
-- weighed 6.4 kg on a 1.7 kg arm and 7.2 kg on a 4.5 kg head, and dragged both out of their joints.
-- Every body gets an override, accessories too: the engine ignores the mass scale of a body authored with a mass
-- override (bOverrideMass), and every outfit but CH_P_EVE_10 has some. CH_P_EVE_30's breasts stayed 100 kg each
-- welded to a 10 kg chest and CH_P_EVE_29's skirt 1400 kg on 2 kg thighs, while the log said 3.7 kg: the ragdoll
-- shook from the first tick, took the push slowly and never lay still (playtest). The log reads the masses back.
-- (read back with tune.gore.probes only: 35 more engine calls in the frame of a death or a cut)
local function real_mass(mesh, bone)
  if not (ctx.tune.gore or {}).probes then return 0 end
  return try(function() return mesh:GetBoneMass(FName(bone), false) end) or 0
end
local function set_masses(mesh, g, keep, only)
  local before, after, acc, accBefore, n = 0, 0, 0, 0, 0
  local readMain, readAcc = 0, 0
  local main = {}
  local cap, share, floor = g.accessoryMaxKg or 0.8, g.accessoryShare or 0.15, g.accessoryMinKg or 0.05
  local list, groups = {}, {}
  for _, bone in ipairs(only or bodies(mesh)) do
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
      readMain = readMain + real_mass(mesh, bone)
    else
      accBefore = accBefore + m
      local want = cap
      local am = MASS[e.anchor]
      if am and share > 0 then want = math.max(math.min(cap, am * (g.massScale or 1.0) * share / groups[e.anchor]), floor) end
      if want > 0 and m > want then
        if keep then keep.masses[bone] = m end
        if try(function() mesh:SetMassOverrideInKg(FName(bone), want, true); return true end) then m = want end
      end
      acc, n = acc + m, n + 1
      readAcc = readAcc + real_mass(mesh, bone)
    end
  end
  local per = {}
  for a, c in pairs(groups) do per[#per + 1] = string.format("%s:%d", a:gsub("Bip001%-", ""), c) end
  table.sort(per)
  local dev = (ctx.tune.gore or {}).probes
  return string.format("masses %.0f -> %.0f kg (%swas %s), %d other bodies %.1f -> %.1f kg (%son %s)",
    before, after, dev and string.format("reads %.0f, ", readMain) or "", table.concat(main, " "), n, accBefore, acc,
    dev and string.format("reads %.1f, ", readAcc) or "", table.concat(per, " "))
end

-- every body's top angular speed (spin.main for the torso, arms and legs, spin.ends for the rest); put back to the
-- engine's default 3600 deg/s by M.stop
local SPIN_DEFAULT = 3600
-- split: a split's half, capped at spin.splitMain / spin.splitEnds instead
local function cap_spin(comp, g, max, split, only)
  local s = g.spin or {}
  if s.enabled == false then return "" end
  local n = 0
  local main, ends = s.main or 720, s.ends or 360
  if split then main, ends = s.splitMain or 360, s.splitEnds or 240 end
  for _, b in ipairs(only or bodies(comp)) do
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
  run.mom = l
  local ok = try(function() mesh:SetAllPhysicsLinearVelocity(v, true); return true end)
  return string.format(", momentum %.0f cm/s%s", l, ok and "" or " (failed)")
end

-- bones gore cut through (limbs, the split's spine break), on the mesh at severedOn: their joints come apart on
-- purpose, so the probe leaves out every joint whose chain up to its anchor crosses one. Kept across M.start (a
-- piece cut while she stands, then her death ragdoll) until another mesh starts
local severed, severedOn = {}, nil
-- the bodies a cut took off fly on their own
local function on_her(comp, b)
  for r in pairs(severed) do
    if r == b or try(function() return comp:BoneIsChildOf(FName(b), FName(r)) end) then return false end
  end
  return true
end
-- the bodies a run moves, masses and puts to sleep: a piece cut off a living Eve, only the piece's. The rest of her
-- is the game's, simulating too where it is hair or jiggle: CH_P_EVE_30's ponytail (Ab-TL-HairB01-09), re-massed
-- with the piece and put to sleep as it settled, hung where it was as she moved on and in photo mode's poses, till
-- her death (playtest)
local function own(comp)
  if not (run and run.piece and addr(comp) == addr(run.mesh)) then return bodies(comp) end
  local out = {}
  for _, b in ipairs(bodies(comp)) do if not on_her(comp, b) then out[#out + 1] = b end end
  return out
end

-- dir: the blow's direction (horizontal is enough), or nil. whole: also launch her whole body along it (deaths):
-- the upper body's push alone only toppled her, her feet stayed put on the floor and she sank on the spot
-- (thirty-sixth playtest: the pelvis went 20 cm sideways in a 2.6 m fall). Never a split's halves: they fly with
-- splitFly already, and on top of the split's own release it shot her half through the floor (thirty-seventh)
local function impact(mesh, g, dir, boost, whole)
  local out = ""
  local k = math.max(tonumber(g.push) or 1, 0)
  boost = (boost or g.impact or 350) * k
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
      local l = (whole and not run.split) and (g.launch or 0) * k or 0
      if l > 0 then
        local lu = g.launchUp or 0.3
        local ld = vec(dir.X / h * (1 - lu) * l, dir.Y / h * (1 - lu) * l, lu * l)
        local m = 0
        for b in pairs(MASS) do
          if on_her(mesh, b) and try(function() mesh:AddImpulse(ld, FName(b), true); return true end) then m = m + 1 end
        end
        run.launchV = l
        -- one push was lost at once: her pelvis read ~110 cm/s a tick later with nothing sideways left, her feet
        -- still on the floor (thirty-seventh playtest). Like a cut piece's throw, for launchTicks more ticks every
        -- body still on her is kept at least that fast along it
        run.launchHold = { d = vec(ld.X / l, ld.Y / l, ld.Z / l), v = l, n = g.launchTicks or 4 }
        out = out .. string.format(", whole body launched %.0f cm/s (%.0f up) on %d bones", l, lu * l, m)
      end
    end
  end
  local tw = g.twist or 90
  if tw > 0 then
    local w = vec(0, 0, (math.random() < 0.5 and -1 or 1) * tw * (0.6 + 0.4 * math.random()))
    -- (added to the angular velocity: AddAngularImpulseInDegrees as a velocity change did nothing in game)
    for _, bone in ipairs(TWIST) do try(function() mesh:SetPhysicsAngularVelocityInDegrees(w, true, FName(bone)) end) end
    out = out .. string.format(", twist %.0f deg/s", w.Z)
  end
  return out
end

-- how stiff her ragdoll is (tune.active.stiffness, settings.lua's active.stiffness): times the tone's strength and its
-- resting share. 0: limp from the start, 1: as tuned, 2-3: she keeps her shape, stiff as she falls and lies
local function stiff() return math.max(tonumber(cfg().stiffness) or 1, 0) end
local function drive(pac, bone, k, t)
  local s = (t.strength or 800) * stiff()
  local data = { bIsLocalSimulation = true, OrientationStrength = s * k, AngularVelocityStrength = s * k * (t.damping or 0.1),
    PositionStrength = 0, VelocityStrength = 0, MaxLinearForce = 0, MaxAngularForce = 0 }
  return try(function() pac:ApplyPhysicalAnimationSettings(FName(bone), data); return true end)
end

local function tone_start(pawn, mesh, g)
  local t = g.tone or {}
  if t.enabled == false or stiff() <= 0 then return ", no tone" end
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
  return string.format(", tone on %d joints (%.0f, hold %.2f s, fade %.2f s, stiffness %.2f)", n, (t.strength or 800) * stiff(),
    t.hold or 0.25, t.fade or 1.4, stiff())
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

-- each weapon rides an invisible box of its mesh's size, simulated, starting with her hand's speed plus a toss.
-- only: drop just the weapons it says yes to (a cut arm's); one already dropped stays on its box
-- extra: components to drop besides her own weapons (a split sword's second half); bound(w): the box for w (its
-- component-space origin and extent: a half's), else its mesh's bounds; push: cm/s more along it (the halves apart)
-- (its vertices' box from sbslice, "W": the asset's imported bounds are twice her sword's width and far longer than
-- its 140 cm, so the break "across its middle" fell by the hilt, the blade stayed whole and its boxes overlapped, which
-- threw the tip off fast, playtest; the imported bounds only when sbslice can't read the mesh). By mesh asset
local real_bounds = {}
local function true_bounds(w)
  local sm = try(function() return w.SkeletalMesh end)
  local ma = sm and addr(sm)
  if not ma then return nil end
  if real_bounds[ma] ~= nil then return real_bounds[ma] or nil end
  real_bounds[ma] = false -- (asked once: a mesh sbslice can't read keeps its imported bounds)
  local o, e
  if ctx.gore and ctx.gore.command then
    local r = ctx.gore.command(string.format("W%x,0", addr(w) or 0))
    local v = {}
    for x in (r:match("^ok W (.+)$") or ""):gmatch("[^,]+") do v[#v + 1] = tonumber(x) end
    if #v == 6 then
      o = vec((v[1] + v[4]) / 2, (v[2] + v[5]) / 2, (v[3] + v[6]) / 2)
      e = vec((v[4] - v[1]) / 2, (v[5] - v[2]) / 2, (v[6] - v[3]) / 2)
      real_bounds[ma] = { o = o, e = e }
      log(string.format("weapon %s: %.0f x %.0f x %.0f cm", tostring(try(function() return sm:GetFName():ToString() end)),
        e.X * 2, e.Y * 2, e.Z * 2))
    else
      log("weapon bounds: " .. tostring(r))
    end
  end
  return real_bounds[ma]
end
-- her hand opens once what it held is gone: the ragdoll's fingers have no bodies and kept the animation's fist
-- (playtest). sbslice eases each bone under the hand toward its bind pose, the open hand ("F", every tick: grip_ease)
-- It writes the mesh asset's bind matrices, which every component on that asset shares (a split's copy, a cut-off
-- arm): one component per asset, the one whose hand is nearest the weapon (at: where it left the hand). Eased on
-- both halves of a split, the copy's frozen hand overwrote hers each tick and her fist stayed shut (playtest)
local function ease_start(pawn, mesh, hand, at)
  local o = (cfg().grip or {}).open or 0.8
  if not hand or eased[hand] or o <= 0 or not (ctx.gore and ctx.gore.fire) then return end
  local comps, seen = {}, {}
  local cand = { mesh }
  for _, c in ipairs(extra) do cand[#cand + 1] = c end
  try(function()
    local cls = StaticFindObject("/Script/Engine.SkeletalMeshComponent")
    for _, c in ipairs(pawn:K2_GetComponentsByClass(cls)) do cand[#cand + 1] = c end
  end)
  -- never a weapon's asset: a sword with a hand bone of its own had it eased too, and its handle half stretched a
  -- face to her hand, flashing, once the break dropped it (playtest)
  local arms = {}
  local function arm(w) local sm = valid(w) and try(function() return w.SkeletalMesh:GetAddress() end); if sm then arms[sm] = true end end
  for _, w in ipairs(weapons(pawn)) do arm(w) end
  for _, d in ipairs(dropped) do arm(d.comp) end
  local by = {} -- asset address -> its pick
  for _, c in ipairs(cand) do
    local a = addr(c)
    local sa = a and try(function() return c.SkeletalMesh:GetAddress() end)
    if sa and arms[sa] then a = nil end
    local i = a and not seen[a] and try(function() return c:GetBoneIndex(FName(hand)) end)
    if a then seen[a] = true end
    local sm = i and i >= 0 and try(function() return c.SkeletalMesh:GetAddress() end)
    if sm then
      local h = at and try(function() local v = c:GetSocketLocation(FName(hand)); return vec(v.X, v.Y, v.Z) end)
      local d = h and len(vec(at.X - h.X, at.Y - h.Y, at.Z - h.Z)) or math.huge
      if not by[sm] then by[sm] = { c = c, a = a, i = i, d = d }; comps[#comps + 1] = by[sm]
      elseif d < by[sm].d then by[sm].c, by[sm].a, by[sm].i, by[sm].d = c, a, i, d end
    end
  end
  if #comps > 0 then eased[hand] = { t = 0, comps = comps } end
end
-- the hand nearest a weapon of hers, within 30 cm (the one holding it)
local function holding_hand(mesh, w)
  local at = try(function() local v = w:K2_GetComponentLocation(); return vec(v.X, v.Y, v.Z) end)
  local hand, best
  for _, sd in ipairs({ "R", "L" }) do
    local b = "Bip001-" .. sd .. "-Hand"
    local h = at and try(function() local v = mesh:GetSocketLocation(FName(b)); return vec(v.X, v.Y, v.Z) end)
    local d = h and len(vec(at.X - h.X, at.Y - h.Y, at.Z - h.Z))
    if d and d < 30 and (not best or d < best) then hand, best = b, d end
  end
  return hand
end
-- every tick: the eased hands opened a little more, toward grip.open over grip.openTime s (smoothed)
local function grip_ease(dt)
  if not next(eased) then return end
  local gp = cfg().grip or {}
  local o, T = math.min(math.max(gp.open or 0.8, 0), 1), math.max(gp.openTime or 0.6, 0.01)
  local f = {}
  for _, e in pairs(eased) do
    e.t = e.t + dt
    local x = math.min(e.t / T, 1)
    local a = math.floor(o * x * x * (3 - 2 * x) * 1000 + 0.5)
    for _, c in ipairs(e.comps) do
      if valid(c.c) and addr(c.c) == c.a then f[#f + 1] = string.format("%x,%x,%x", c.a, c.i, a) end
    end
  end
  -- (eight hands a command: sbslice reads 24 fields)
  for i = 1, #f, 8 do ctx.gore.fire("F" .. table.concat(f, ",", i, math.min(i + 7, #f))) end
end
local function ease_stop()
  if next(eased) and ctx.gore and ctx.gore.fire then ctx.gore.fire("F") end
  eased = {}
end
local function drop_weapons(pawn, mesh, g, only, soft, extra, bound, push)
  if g.dropWeapon == false then return "" end
  local cls = try(function() return StaticFindObject("/Script/Engine.BoxComponent") end)
  if not valid(cls) then return ", weapons: no BoxComponent class" end
  local hv = try(function() local v = mesh:GetPhysicsLinearVelocity(FName(soft and soft.hand or "Bip001-R-Hand")); return vec(v.X, v.Y, v.Z) end)
    or speeds[#speeds] or vec(0, 0, 0)
  local id = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }
  local names = {}
  -- by address: UE4SS hands out a new wrapper each call, so a cut re-dropped the sword already on its box, and
  -- on recovery it went back onto that box, destroyed, left lying on the floor (thirty-seventh playtest)
  local held = {}
  for _, d in ipairs(dropped) do
    local a = try(function() return d.comp:GetAddress() end)
    if a then held[a] = true end
  end
  local list, cand = {}, weapons(pawn)
  for _, w in ipairs(extra or {}) do cand[#cand + 1] = w end
  for _, w in ipairs(cand) do
    local a = try(function() return w:GetAddress() end)
    if not (a and held[a]) and (not only or only(w)) then list[#list + 1] = w end
  end
  if only and #list == 0 then return "" end
  for _, w in ipairs(list) do
    -- the imported bounds (GetBounds adds the asset's bounds extension: 217 cm for her sword), capped at weaponMaxCm
    local function bnd(fn) return try(function() local x = fn(); return { o = vec(x.Origin.X, x.Origin.Y, x.Origin.Z),
      e = vec(x.BoxExtent.X, x.BoxExtent.Y, x.BoxExtent.Z) } end) end
    local b = bound and bound(w)
    local tb = not b and true_bounds(w)
    b = b or (tb and { o = vec(tb.o.X, tb.o.Y, tb.o.Z), e = vec(tb.e.X, tb.e.Y, tb.e.Z) })
      or bnd(function() return w.SkeletalMesh:GetImportedBounds() end) or bnd(function() return w.SkeletalMesh:GetBounds() end)
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
      -- (one her grip held: back onto its prop bone on recovery, not her hand)
      local ga = addr(w)
      local o = ga and gripped[ga]
      local hold = (o and o.hand) or (soft and soft.hand) or holding_hand(mesh, w)
      if o then d.parent, d.socket, d.loc, d.rot, gripped[ga] = o.parent, o.socket, o.loc, o.rot, nil end
      dropped[#dropped + 1] = d
      local ok = try(function()
        local wl, f, r, u = w:K2_GetComponentLocation(), w:GetForwardVector(), w:GetRightVector(), w:GetUpVector()
        local o = b.o
        local at = vec(wl.X + f.X * o.X + r.X * o.Y + u.X * o.Z, wl.Y + f.Y * o.X + r.Y * o.Y + u.Y * o.Z,
          wl.Z + f.Z * o.X + r.Z * o.Y + u.Z * o.Z)
        box:K2_SetWorldLocationAndRotation(at, w:K2_GetComponentRotation(), false, {}, true)
        -- its thinnest side flattened to 1.5 cm: the bounds' 6 cm (the guard's) stood a dropped sword on its edge,
        -- a box that thick resting as well on it as flat (playtest)
        local ex = { math.max(b.e.X, 1.5), math.max(b.e.Y, 1.5), math.max(b.e.Z, 1.5) }
        local thin = 1
        for i = 2, 3 do if ex[i] < ex[thin] then thin = i end end
        ex[thin] = 0.75
        box:SetBoxExtent(vec(ex[1], ex[2], ex[3]), false)
        box:SetHiddenInGame(true, false)
        -- Pawn: not her capsule (or the player's); PhysicsBody: it lands on her as well as the floor
        box:SetCollisionProfileName(FName("PhysicsActor"), true)
        box:SetCollisionResponseToChannel(2, 0)
        box:SetCollisionEnabled(3)
        try(function() box.BodyInstance.bUseCCD = true end)
        box:SetSimulatePhysics(true)
        box:SetMassOverrideInKg(FName("None"), g.weaponKg or 1.5, true)
        w:K2_AttachToComponent(box, FName("None"), 1, 1, 1, false)
        -- (soft: slipping out of her loosening grip, with her hand's own speed: barely tossed or turned)
        local toss = soft and soft.toss or g.weaponToss or 150
        local spin = soft and soft.spin or 1
        local a = math.random() * math.pi * 2
        local pv = push and push(w) or vec(0, 0, 0)
        box:SetPhysicsLinearVelocity(vec(hv.X + math.cos(a) * toss + pv.X, hv.Y + math.sin(a) * toss + pv.Y,
          hv.Z + toss * 0.6 + pv.Z), false, FName("None"))
        box:SetPhysicsAngularVelocityInDegrees(vec((math.random() - 0.5) * 720 * spin, (math.random() - 0.5) * 720 * spin,
          (math.random() - 0.5) * 360 * spin), false, FName("None"))
        return true
      end)
      if ok then ease_start(pawn, mesh, hold, try(function() local v = w:K2_GetComponentLocation(); return vec(v.X, v.Y, v.Z) end)) end
      names[#names + 1] = string.format("%s %.0fx%.0fx%.0f%s", tostring(try(function() return w.SkeletalMesh:GetFName():ToString() end)),
        b.e.X * 2, b.e.Y * 2, b.e.Z * 2, ok and "" or " (failed)")
    end
  end
  if #names == 0 then return ", no weapon showing" end
  return ", dropped " .. table.concat(names, ", ")
end

-- her grip in a ragdoll death (tune.active.grip): a weapon in her hand (Bip001-Prop1/2 hang off Bip001, the
-- animation puts them in the hand; a ragdoll leaves them in the air, so it was thrown off at once) is put on her hand
-- bone where it is and rides with it, then slips out as her grip eases (grip.hold s), with her hand's speed
local function grip_start(mesh, g)
  local gp = g.grip or {}
  if g.dropWeapon == false or gp.enabled == false then return "" end
  local pawn = try(function() return mesh:GetOwner() end)
  if not valid(pawn) then return "" end
  local names = {}
  for _, w in ipairs(weapons(pawn)) do
    local at = try(function() local v = w:K2_GetComponentLocation(); return vec(v.X, v.Y, v.Z) end)
    local hand, best
    for _, sd in ipairs({ "R", "L" }) do
      local b = "Bip001-" .. sd .. "-Hand"
      local h = try(function() local v = mesh:GetSocketLocation(FName(b)); return vec(v.X, v.Y, v.Z) end)
      local d = h and at and len(vec(at.X - h.X, at.Y - h.Y, at.Z - h.Z))
      if d and d < 30 and (not best or d < best) and not severed[b] then hand, best = b, d end
    end
    local a = addr(w)
    -- (one let go of already, a sword broken on her guard: the ragdoll that came after took its tip half off the floor
    -- into her hand, playtest)
    local gone = false
    for _, d in ipairs(dropped) do if addr(d.comp) == a then gone = true end end
    if hand and a and not gripped[a] and not gone then
      local o = { comp = w, hand = hand, parent = try(function() return w:GetAttachParent() end),
        socket = try(function() return w:GetAttachSocketName() end),
        loc = try(function() local v = w.RelativeLocation; return vec(v.X, v.Y, v.Z) end),
        rot = try(function() local r = w.RelativeRotation; return { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end) }
      -- (KeepWorld: where the animation had it, in her fingers)
      if try(function() w:K2_AttachToComponent(mesh, FName(hand), 1, 1, 1, false); return true end) then
        gripped[a] = o
        names[#names + 1] = string.format("%s in %s", tostring(try(function() return w.SkeletalMesh:GetFName():ToString() end)),
          hand:gsub("Bip001%-", ""))
      end
    end
  end
  if #names == 0 then return "" end
  local lo, hi = gp.holdMin or 0.35, gp.holdMax or 0.9
  run.gripAt = lo + math.random() * math.max(hi - lo, 0)
  return string.format(", grip on %s (eases at %.2f s)", table.concat(names, ", "), run.gripAt)
end
-- her grip eases: what it held slips out (gone already: a cut arm let go of it, on_cut)
local function grip_release(pawn, mesh, g)
  run.gripAt = nil
  local gp = g.grip or {}
  local out = {}
  for a, o in pairs(gripped) do
    if valid(o.comp) and valid(pawn) then
      local r = drop_weapons(pawn, mesh, g, function(w) return addr(w) == a end,
        { toss = gp.toss or 30, spin = gp.spin or 0.2, hand = o.hand })
      if r ~= "" then out[#out + 1] = r:gsub("^, dropped ", "") end
    end
    gripped[a] = nil
  end
  return table.concat(out, ", ")
end
-- the grip never eased (she got up, or the death ended first): back on the prop bones
local function grip_back()
  local n = 0
  for _, o in pairs(gripped) do
    if valid(o.comp) and valid(o.parent) and try(function()
      o.comp:K2_AttachToComponent(o.parent, o.socket or FName("None"), 2, 2, 2, false)
      if o.loc and o.rot then o.comp:K2_SetRelativeLocationAndRotation(o.loc, o.rot, false, {}, true) end
      return true
    end) then n = n + 1 end
  end
  gripped = {}
  return n
end

-- her sword cut by the killing blade (tune.active.weaponCut, gore.blow at death): where the blade's plane crosses a
-- weapon of hers within reach cm of the hit, a second component of its mesh on its pose takes the far half
-- (sbslice's "e": each keeps one side through its own skin weights, the cut face is the crossed part pressed flat)
-- and each half falls on a box of its own, pushed apart. Put back whole when she gets up
-- blocked: she had her guard up at the blow (main.lua: the guard key, a guard montage or stance): the sword breaks whatever the plane did, where
-- the blade's plane crosses it, else across its middle nearest the hit, tilted as the blade came (judged by the
-- plane alone, a blow she blocked mostly missed the sword or crossed it far off: "the blade misses it", playtest)
local splits = {} -- { w, b }: the sword and its other half
-- a component's mesh bounds: its long axis's two ends in the world, and the bounds (component space)
local function weapon_axis(w)
  local tb = true_bounds(w)
  local o, e = tb and tb.o, tb and tb.e
  if not o then
    local x = try(function() return w.SkeletalMesh:GetImportedBounds() end)
    if not x then return nil end
    o, e = vec(x.Origin.X, x.Origin.Y, x.Origin.Z), vec(x.BoxExtent.X, x.BoxExtent.Y, x.BoxExtent.Z)
  end
  local k = e.X >= e.Y and e.X >= e.Z and "X" or e.Y >= e.Z and "Y" or "Z"
  local function at(sg)
    local p = vec(o.X, o.Y, o.Z)
    p[k] = p[k] + sg * e[k]
    return try(function()
      local wl, f, r, u = w:K2_GetComponentLocation(), w:GetForwardVector(), w:GetRightVector(), w:GetUpVector()
      return vec(wl.X + f.X * p.X + r.X * p.Y + u.X * p.Z, wl.Y + f.Y * p.X + r.Y * p.Y + u.Y * p.Z, wl.Z + f.Z * p.X + r.Z * p.Y + u.Z * p.Z)
    end)
  end
  local a, b = at(-1), at(1)
  return a and b and { a = a, b = b, o = o, e = e, k = k }
end
function M.weapon_cut(mesh, at, n, blocked)
  local g = cfg()
  local wc = g.weaponCut or {}
  if wc.enabled == false or g.dropWeapon == false then return nil end
  local gore = ctx.gore
  local pawn = try(function() return mesh:GetOwner() end)
  if not (gore and gore.command and valid(pawn) and at and n) then return nil end
  local cls = try(function() return StaticFindObject("/Script/Engine.SkeletalMeshComponent") end)
  if not valid(cls) then return nil end
  local out = {}
  local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
  local function sub(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
  for _, w in ipairs(weapons(pawn)) do
    local ax = weapon_axis(w)
    local pa, pn = at, n -- the plane this sword is cut on
    local ha, hb, t, x, reach, forced
    local function cross_at()
      ha = ax and dot(sub(ax.a, pa), pn)
      hb = ax and dot(sub(ax.b, pa), pn)
      t = ha and hb and (ha < 0) ~= (hb < 0) and ha / (ha - hb)
      x = t and vec(ax.a.X + (ax.b.X - ax.a.X) * t, ax.a.Y + (ax.b.Y - ax.a.Y) * t, ax.a.Z + (ax.b.Z - ax.a.Z) * t)
      reach = x and len(sub(x, at))
    end
    cross_at()
    local ends = wc.ends or 0.08
    local d = ax and sub(ax.b, ax.a)
    local l = d and len(d) or 0
    local u = l > 1 and vec(d.X / l, d.Y / l, d.Z / l)
    -- a plane lying along the sword (within ~37 deg of its length) slices it lengthwise: one half a sliver off the
    -- grip, the other the whole sword still (playtest: "the blade part AND the full untouched sword")
    local along = u and math.abs(dot(n, u)) < (wc.across or 0.6)
    -- (a blocked blow always breaks it on the bare blade: its own crossing landed at 0.22, in the frame over the grip;
    -- and so does any blow crossing it off the blade: at 0.40-0.45 the blade came off whole, tip and all, where the
    -- frame ends, and lay beside the hilt as a whole sword, playtest)
    local br = wc.breakAt or { 0.55, 0.68 }
    local off = t and (t < br[1] or t > (br[2] or br[1]))
    if u and (blocked or ((along or off) and reach and reach <= (wc.reach or 80))) then
      do
        -- (on the bare blade: at 0.3 it broke through the open frame over the grip, and both halves looked like a
        -- sword with a hilt, playtest)
        local tt = math.max(br[1], math.min(br[2] or br[1], dot(sub(at, ax.a), u) / l))
        -- mostly along the sword (a clean break across it), leaning the way the blade's plane lies
        local k = dot(n, u)
        local p = vec(n.X - u.X * k, n.Y - u.Y * k, n.Z - u.Z * k)
        local m = vec(u.X + p.X * 0.5, u.Y + p.Y * 0.5, u.Z + p.Z * 0.5)
        local ml = len(m)
        pa = vec(ax.a.X + d.X * tt, ax.a.Y + d.Y * tt, ax.a.Z + d.Z * tt)
        pn = vec(m.X / ml, m.Y / ml, m.Z / ml)
        cross_at()
        forced = true
      end
    end
    local nm = tostring(try(function() return w.SkeletalMesh:GetFName():ToString() end))
    local split_already = false
    for _, sp in ipairs(splits) do if sp.w == w or sp.b == w then split_already = true end end
    if split_already then
      out[#out + 1] = nm .. ": in two already"
    elseif not reach then
      out[#out + 1] = nm .. ": the blade misses it"
    elseif reach > (wc.reach or 80) and not forced then -- (a blocked blow breaks it however far off the guessed hit was)
      out[#out + 1] = string.format("%s: crossed %.0f cm from the hit (over %d)", nm, reach, wc.reach or 80)
    elseif t < ends or t > 1 - ends then
      out[#out + 1] = string.format("%s: crossed at its very end (%.2f)", nm, t)
    else
      local id = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }
      local b = try(function() return pawn:AddComponentByClass(cls, true, id, false) end)
      if valid(b) then
        try(function() b:SetCollisionEnabled(0) end)
        try(function() b:SetSkeletalMesh(w.SkeletalMesh, true) end)
        local nmat = try(function() return w:GetNumMaterials() end) or 0
        for i = 0, nmat - 1 do
          local mt = try(function() return w:GetMaterial(i) end)
          if mt then try(function() b:SetMaterial(i, mt) end) end
        end
        local tm = try(function() return w:K2_GetComponentToWorld() end)
        if tm then try(function() b:K2_SetWorldTransform(tm, false, {}, true) end) end
        try(function() b:SetMasterPoseComponent(w, true) end)
        gore.lod0(w, true)
        gore.lod0(b, true)
        -- its pose frozen as it is cut (the copy follows it): the sword's gears, panels and blade segments go on
        -- animating, and the flat cut faces and the collapsed ends are made in this pose, so both halves showed most
        -- of the sword with its ends bent off to where the moved bones went (playtest)
        try(function() w.bNoSkeletonUpdate = true end)
        local r = gore.command(string.format("e%x,%x,0", w:GetAddress(), b:GetAddress()), pa, pn)
        if r:sub(1, 2) ~= "ok" then
          try(function() w.bNoSkeletonUpdate = false end)
          gore.lod0(w, false)
          try(function() b:K2_DestroyComponent(b) end)
          out[#out + 1] = nm .. ": " .. r
        else
          gore.command("k")
          local aw, ab = addr(w), addr(b)
          splits[#splits + 1] = { w = w, b = b }
          -- each half's box: its stretch of the long axis, from the crossing to its end (w keeps the front)
          local front = ha >= 0 and -1 or 1 -- the end (-1 a, 1 b) in front of the plane
          local k = ax.k
          local cx = ax.o[k] + (2 * t - 1) * ax.e[k]
          -- (each box stops gap cm short of the break: two boxes meeting there, or overlapping, threw a half off fast)
          local gap = wc.gap or 1.5
          -- across the sword, each box as wide and thick as its own half (sbslice's abox / bbox): on the whole sword's
          -- section, guard and all, the tip lay 2-3 cm over the floor (playtest)
          local function own(tag)
            local v = {}
            for x in (r:match(" " .. tag .. "=([%d%.,%-]+)") or ""):gmatch("[^,]+") do v[#v + 1] = tonumber(x) end
            if #v ~= 6 then return nil end
            return { o = vec((v[1] + v[4]) / 2, (v[2] + v[5]) / 2, (v[3] + v[6]) / 2), e = vec((v[4] - v[1]) / 2, (v[5] - v[2]) / 2, (v[6] - v[3]) / 2) }
          end
          local function half(sg, box)
            local lo, hi = cx + sg * gap, ax.o[k] + sg * ax.e[k]
            local o, e = vec(ax.o.X, ax.o.Y, ax.o.Z), vec(ax.e.X, ax.e.Y, ax.e.Z)
            if box then
              for _, j in ipairs({ "X", "Y", "Z" }) do
                if j ~= k then o[j], e[j] = box.o[j], math.max(box.e[j], 0.5) end
              end
            end
            o[k], e[k] = (lo + hi) / 2, math.max(math.abs(hi - lo) / 2, 1.5)
            local cap = (g.weaponMaxCm or 120) / 2
            return { o = o, e = vec(math.min(e.X, cap), math.min(e.Y, cap), math.min(e.Z, cap)) }
          end
          local hw, hbx = half(front, own("abox")), half(-front, own("bbox"))
          local apart = wc.apart or 120
          local gp = g.grip or {}
          local soft = { toss = gp.toss or 30, spin = wc.spin or 0.5, hand = gripped[aw or 0] and gripped[aw].hand or nil }
          local d = drop_weapons(pawn, mesh, g, function(c) local a2 = addr(c); return a2 == aw or a2 == ab end, soft, { b },
            function(c) return addr(c) == ab and hbx or hw end,
            function(c) local sg = addr(c) == ab and -1 or 1; return vec(pn.X * apart * sg, pn.Y * apart * sg, pn.Z * apart * sg) end)
          -- (the half on no prop bone has nothing to go back onto)
          for _, dd in ipairs(dropped) do if addr(dd.comp) == ab then dd.parent = nil end end
          out[#out + 1] = string.format("%s split at %.2f along it, %.0f cm from the hit%s: %s%s", nm, t, reach,
            forced and (blocked and " (she blocked: broken across its blade)" or along and " (plane along it: broken across its blade)"
              or " (crossed it off its blade: broken across its blade)") or "", r, d)
        end
      end
    end
  end
  if #out > 0 then log("weapon cut: " .. table.concat(out, "; ")) end
end
-- a sword of hers already in two (this death)
function M.sword_split() return #splits > 0 end
-- she got up: each split sword whole again, its other half gone (the asset's sinks with the weights)
local function splits_back()
  local gore = ctx.gore
  local n = 0
  for _, sp in ipairs(splits) do
    if gore and gore.command then
      if valid(sp.w) then gore.command(string.format("x%x,0", sp.w:GetAddress())) end
      if valid(sp.b) then gore.command(string.format("x%x,0", sp.b:GetAddress())) end
    end
    if valid(sp.w) and gore then gore.lod0(sp.w, false); try(function() sp.w.bNoSkeletonUpdate = false end) end
    if valid(sp.b) then try(function() sp.b:K2_DestroyComponent(sp.b) end) end
    n = n + 1
  end
  splits = {}
  return n
end

-- stretch probe: every main joint's length (bone to the main bone above it) at the start, and how far it is off later
-- (logged at STRETCH_AT seconds, the worst three). A joint the solver can't hold shows as centimetres here
local STRETCH_AT = { 0.5, 1.0, 2.0, 3.0 }
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
-- and the cape's links (accessory bodies named *Cape*), each to the link above it: the cape on CH_P_EVE_09 hangs off
-- the upper arms' twist bones as two 7-link chains and stretched in deaths (playtest); this shows whether its joints
-- come apart or the chain only swings
local function cape_lengths(mesh)
  local out = {}
  for _, bone in ipairs(bodies(mesh)) do
    if not MASS[bone] and bone:find("Cape") then
      local up = try(function() return mesh:GetParentBone(FName(bone)):ToString() end)
      -- (link to link: the top one hangs off the shoulder in a ragdoll, away from its arm bone by design)
      local a = up and up:find("Cape") and try(function() local v = mesh:GetSocketLocation(FName(bone)); return vec(v.X, v.Y, v.Z) end)
      local b = a and try(function() local v = mesh:GetSocketLocation(FName(up)); return vec(v.X, v.Y, v.Z) end)
      if b then out[bone] = { up = up, l = len(vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z)) } end
    end
  end
  return next(out) and out or nil
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
-- A cape hung off the upper arms (CH_P_EVE_09: Ab_CapeL/R01-07 jointed to the arm's twist bone, 10 degrees a link)
-- whipped about with the arm in a ragdoll and tore at its top, which is skinned to her torso too (playtest). Each
-- such chain (an accessory body jointed to an upper arm, 3 or more bodies down from it) lets go of the arm and hangs
-- off the arm's parent body (the clavicle) by a joint of our own: a cone of capeSwing degrees about the way the chain
-- runs now, capeTwist about itself. Its links weigh capeKg each. The asset's joint comes back when her physics is
-- remade on recovery (gore's cleanup); ours are destroyed in M.stop
local ARMS = { ["Bip001-L-UpperArm"] = true, ["Bip001-R-UpperArm"] = true }
local function hang_capes(pawn, mesh, g)
  if g.capeHang == false then return "" end
  local list = bodies(mesh)
  local has, up = {}, {}
  for _, b in ipairs(list) do has[b] = true end
  -- each body's parent body
  for _, b in ipairs(list) do
    local p = b
    for _ = 1, 64 do
      p = try(function() return mesh:GetParentBone(FName(p)):ToString() end)
      if not p or p == "None" or has[p] then break end
    end
    if p and has[p] then up[b] = p end
  end
  -- the arm a chain hangs off: its parent body, or the arm's twist body between (CH_P_EVE_09's capes hang off
  -- Ab-*-UpperArm-Tw1, which has a body of its own: the twist body itself was hung off the shoulder, playtest). A twist
  -- body is never a cape's root
  local function twist(b) return b and (b:find("%-Tw%d") or b:find("[Tt]wist")) ~= nil end
  local function arm_of(b)
    if twist(b) then return nil end
    local p = up[b]
    if ARMS[p] then return p end
    if twist(p) and ARMS[up[p]] then return up[p] end
    return nil
  end
  local cls
  local done = {}
  -- (a cape gore took off with its arm or cut off it is a piece of its own, or hung off the shoulder already: hung
  -- again off the clavicle from where it lay, 140 cm away, it whipped about her on a rigid 1.4 m lever, playtest)
  local function cut(b) return addr(mesh) == severedOn and severed[b] == true end
  local skipped = {}
  for _, root in ipairs(list) do
    local arm = not MASS[root] and arm_of(root)
    if arm and (cut(arm) or cut(root)) then skipped[#skipped + 1] = root; arm = nil end
    if arm then
      -- the chain under it, and its next link for the way it runs
      local chain, n, nxt = { [root] = true }, 1, nil
      for _ = 1, 16 do
        local grew = false
        for _, b in ipairs(list) do
          if not chain[b] and up[b] and chain[up[b]] then
            chain[b], n, grew = true, n + 1, true
            if up[b] == root and not nxt then nxt = b end
          end
        end
        if not grew then break end
      end
      local anchor = n >= 3 and anchor_of(mesh, arm)
      local at = anchor and try(function() local v = mesh:GetSocketLocation(FName(root)); return vec(v.X, v.Y, v.Z) end)
      local to = at and nxt and try(function() local v = mesh:GetSocketLocation(FName(nxt)); return vec(v.X, v.Y, v.Z) end)
      cls = cls or (at and try(function() return StaticFindObject("/Script/Engine.PhysicsConstraintComponent") end))
      local pc = to and valid(cls) and try(function()
        return pawn:AddComponentByClass(cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }, false)
      end)
      if valid(pc) then
        run.hung[#run.hung + 1] = pc
        -- the joint's frame is the component's when it is made: X (the twist axis) along the chain
        local d = vec(to.X - at.X, to.Y - at.Y, to.Z - at.Z)
        local rot = { Pitch = math.deg(math.atan(d.Z, math.sqrt(d.X * d.X + d.Y * d.Y))), Yaw = math.deg(math.atan(d.Y, d.X)), Roll = 0 }
        try(function() pc:K2_SetWorldLocationAndRotation(at, rot, false, {}, true) end)
        try(function() pc:SetAngularSwing1Limit(1, g.capeSwing or 45) end)
        try(function() pc:SetAngularSwing2Limit(1, g.capeSwing or 45) end)
        try(function() pc:SetAngularTwistLimit(1, g.capeTwist or 20) end)
        try(function() mesh:BreakConstraint(vec(0, 0, 0), at, FName(root)) end)
        if try(function() pc:SetConstrainedComponents(mesh, FName(anchor), mesh, FName(root)); return true end) then
          for b in pairs(chain) do
            run.masses[b] = run.masses[b] or mass(mesh, b)
            try(function() mesh:SetMassOverrideInKg(FName(b), g.capeKg or 0.12, true) end)
          end
          done[#done + 1] = string.format("%s (%d links) on %s", root, n, anchor:gsub("Bip001%-", ""))
        end
      end
    end
  end
  return (#done > 0 and (", cape hung off the shoulder: " .. table.concat(done, ", ")) or "")
    .. (#skipped > 0 and (", cape left as the cut left it: " .. table.concat(skipped, ", ")) or "")
end

function M.start(pawn, mesh, kind, dir)
  local g = cfg()
  if g.enabled == false then return end
  -- a restart in the same death (an animated fall turning ragdoll for a split) keeps her broken and dropped weapons:
  -- the full stop mended the sword the blow had just broken and put it back in her hand (playtest)
  if run then M.stop(pawn, true) end
  if addr(mesh) ~= severedOn then severed, severedOn = {}, addr(mesh) end
  run = { mesh = mesh, t = 0, masses = {}, still = 0, hung = {} }
  run.joints, run.capes, run.probe = joint_lengths(mesh), cape_lengths(mesh), 1
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
  if not plain then parts[#parts + 1] = hang_capes(pawn, mesh, g) end
  if kind == "death" then
    parts[#parts + 1] = momentum(mesh, g)
    -- the death key pushes after ImpulseDelayTime (0.01 s), so its direction is read a couple of ticks later
    run.pawn, run.impactAt, run.hint = pawn, 0.06, dir
  else
    parts[#parts + 1] = impact(mesh, g, dir)
  end
  -- (not on a quiet one, from an animated fall's end pose: her animation goes on to a standing pose under it, and
  -- the tone would pull her towards that)
  if not plain and kind ~= "quiet" then parts[#parts + 1] = tone_start(pawn, mesh, g) end
  if kind == "death" and not plain then
    parts[#parts + 1] = grip_start(mesh, g)
    parts[#parts + 1] = drop_weapons(pawn, mesh, g, function(w) return not gripped[addr(w) or 0] end)
  else
    parts[#parts + 1] = drop_weapons(pawn, mesh, g)
  end
  speeds = {}
  log(kind .. ": " .. table.concat(parts, ""))
end

-- a piece cut off her while she stands (gore, F9): no ragdoll runs, so give her bodies their human masses now; put
-- back by M.stop like a ragdoll's (a ragdoll that starts meanwhile takes over)
function M.piece(pawn, mesh, bone)
  local g = cfg()
  if g.enabled == false or run then return nil end
  -- (the piece's bone known before its joint breaks: own() picks its bodies by it)
  if bone then M.broken(mesh, bone) end
  run = { mesh = mesh, t = 0, masses = {}, piece = true, still = 0 }
  local only = own(mesh)
  local r = set_masses(mesh, g, run, only) .. cap_spin(mesh, g, nil, nil, only)
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

-- convulse.lua or struggle.lua still to move her (their M.due)
local function moving()
  local cv, sg = ctx.convulse, ctx.struggle
  return (cv and cv.due and cv.due()) or (sg and sg.due and sg.due()) or false
end
local function sleep(comp)
  local n = 0
  for _, b in ipairs(own(comp)) do
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
  if run and run.piece then
    for _, b in ipairs(own(comp)) do
      try(function() comp:SetPhysicsLinearVelocity(vec(0, 0, 0), false, FName(b)) end)
      try(function() comp:SetPhysicsAngularVelocityInDegrees(vec(0, 0, 0), false, FName(b)) end)
    end
    return
  end
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
  -- its cape hung off the shoulder as hers is: on the asset's joint to the upper arm it whipped about and stretched
  -- (playtest, CH_P_EVE_09). The joints go with the others in M.stop
  local masses = not (run and run.variant == 2) and (set_masses(comp, g) .. cap_spin(comp, g, nil, true))
  local hung = ""
  if masses and run and run.hung then
    local pawn = try(function() return comp:GetOwner() end)
    if valid(pawn) then hung = hang_capes(pawn, comp, g) end
  end
  if masses then log("split copy: " .. masses .. hung) end
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
  -- the start: nothing she has moves faster than her momentum and the blow (and the fall since) allow. A ragdoll
  -- that started mid-fall (a leg cut) shot her torso off at 1600 cm/s with 57 of momentum, thirty-fourth playtest
  if run.t < (s.launchTime or 0.5) then
    local g = cfg()
    local lim = (run.mom or 0) + (g.impact or 200) * math.max(tonumber(g.push) or 1, 1) + (run.launchV or 0) + (s.launchOver or 400) + 981 * run.t
    for b in pairs(MASS) do
      local v = lin_vel(comp, b)
      local l = v and len(v)
      if l and l > lim then
        local k = lim / l
        try(function() comp:SetPhysicsLinearVelocity(vec(v.X * k, v.Y * k, v.Z * k), false, FName(b)) end)
        run.launched = (run.launched or 0) + 1
        if run.launched == 1 then log(string.format("launched: %s at %.0f cm/s slowed to %.0f at %.2f s", b, l, lim, run.t)) end
      end
    end
    return
  end
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

-- how far p is over whatever is under it (a visibility trace down to 10 m, her own actor ignored): nil with nothing
-- there (a floor that doesn't block the trace too: taken as unknown, left alone)
function M.over_floor(pawn, p)
  local ks = try(function() return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end)
  if not (valid(ks) and p) then return nil end
  local hit = {}
  local ok = try(function()
    return ks:LineTraceSingle(pawn, vec(p.X, p.Y, p.Z + 5), vec(p.X, p.Y, p.Z - 1000), 0, false, { pawn }, 0, hit, true,
      { R = 1, G = 0, B = 0, A = 1 }, { R = 0, G = 1, B = 0, A = 1 }, 0)
  end)
  local z = ok and try(function() return (hit.ImpactPoint or hit.Location).Z end)
  return z and p.Z - z or nil
end
-- the bones looked at for hanging in the air: the pelvis, and on her body the root of each piece cut off it. A waist
-- cut's upper half hung in the air while its pelvis lay on the stairs with her legs (Nexus report)
local function aloft_bones(c)
  -- (her pelvis only simulating: a living Eve's stands, and was "77 cm over the floor, woken to fall" by a piece's run)
  local out = live(c, "Bip001-Pelvis") and { "Bip001-Pelvis" } or {}
  if addr(c) == severedOn then
    for b in pairs(severed) do if live(c, b) then out[#out + 1] = b end end
  end
  return out
end
-- the highest of those over the floor (cm) and which; nil with no floor found under any
local function aloft(c)
  local pawn = run.pawn or try(function() return run.mesh:GetOwner() end)
  local top, which = nil, nil
  for _, b in ipairs(aloft_bones(c)) do
    local l = try(function() local x = c:GetSocketLocation(FName(b)); return vec(x.X, x.Y, x.Z) end)
    local over = l and M.over_floor(pawn, l)
    if over and (not top or over > top) then top, which = over, b end
  end
  return top, which
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
  -- a twitch moving her (convulse.lua): she isn't lying still while it runs, however slow
  if run.twitchTill and run.t < run.twitchTill then run.still = 0; return end
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
    -- (kept awake for her last movements: asleep once they are over)
    if run.awake and not moving() then
      run.awake = nil
      local n = 0
      for _, c in ipairs(comps) do if valid(c) then n = n + sleep(c) end end
      log(string.format("her last movements are over: %d bodies asleep at %.1f s", n, run.t))
    end
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
    vlog(string.format("not settled at %.1f s: fastest %s %.0f cm/s (body %d), drift %.1f cm (%s) over %.1f s, turning %s %.0f deg/s (body %d)",
      run.t, tostring(which), top, wc or 0, drift == math.huge and -1 or drift, tostring(far), win, tostring(wb), wt, wi))
  end
  if run.still < (st.time or 0.5) then return end
  -- not up in the air: still there (slowed at the top of a fall, held by something that let go) she was put to sleep
  -- and hung there (0.4.0 report: killed in mid-air, hung in the air). Woken and left to fall, checked again later
  local over, ob
  for _, c in ipairs(comps) do
    if valid(c) then
      local o, b = aloft(c)
      if o and (not over or o > over) then over, ob = o, b end
    end
  end
  if over and over > (st.air or 60) then
    run.still = 0
    for _, c in ipairs(comps) do
      if valid(c) and run.piece then for _, b in ipairs(own(c)) do try(function() c:WakeRigidBody(FName(b)) end) end
      elseif valid(c) then try(function() c:WakeAllRigidBodies() end) end
    end
    if not run.airSaid then
      run.airSaid = true
      log(string.format("not settled at %.1f s: %s is %.0f cm over the floor, woken to fall", run.t, tostring(ob), over))
    end
    return
  end
  run.asleep = true
  tone_stop()
  local n = 0
  -- her convulsions or struggle still to come: stopped but left awake. A body put to sleep took the turns they gave
  -- it (read back at once) and never moved (playtest: an arm's centre of mass 0.1 cm over a 164 deg/s swing)
  run.awake = moving() or nil
  for _, c in ipairs(comps) do
    if valid(c) then
      if run.awake then
        stop_all(c)
        n = n + #bodies(c)
      else
        n = n + sleep(c)
      end
    end
  end
  -- settling again after a twitch: once is enough in the log
  if run.settled then return end
  run.settled = true
  log(string.format("settled after %.2f s (%.0f cm/s, drift %.1f cm): tone off, %d bodies %s, %d spins slowed to the cap, %d flung bodies slowed, %d launched", run.t, top,
    drift == math.huge and -1 or drift, n, run.awake and "stopped, kept awake for her last movements" or "asleep", run.clamped or 0, run.flung or 0, run.launched or 0))
  if run.rolls then log("rolled about the bone since the start (deg): " .. roll_report(run.mesh, run.rolls)) end
end

-- hanging in the air: settle's own check runs only once she is calm, and a split killed in mid-air left her half up
-- there, swinging, for 16 s till it did (0.4.1 playtest). Each half's pelvis is looked at every HANG_EVERY s: up over
-- settle.air and dropped under HANG_DROP cm in the last HANG_SPAN s, what holds it is logged once (bodies not
-- simulating, gravity) and it is let go: gravity on, every body simulating, woken
local HANG_EVERY, HANG_SPAN, HANG_DROP = 0.25, 1.0, 20
local function hang_watch()
  if run.piece or run.asleep or run.t < 0.5 then return end
  if run.t < (run.hangNext or 0) then return end
  run.hangNext = run.t + HANG_EVERY
  local st = cfg().settle or {}
  run.hang = run.hang or {}
  local comps = { run.mesh }
  for _, c in ipairs(extra) do comps[#comps + 1] = c end
  local pawn = run.pawn or try(function() return run.mesh:GetOwner() end)
  for i, c in ipairs(comps) do
    for _, bone in ipairs(valid(c) and aloft_bones(c) or {}) do
      local key = i .. bone
      local l = try(function() local x = c:GetSocketLocation(FName(bone)); return vec(x.X, x.Y, x.Z) end)
      local h = run.hang[key] or { zs = {} }
      run.hang[key] = h
      if l then
        local z = l.Z
        table.insert(h.zs, { t = run.t, z = z })
        while #h.zs > 1 and h.zs[2].t <= run.t - HANG_SPAN do table.remove(h.zs, 1) end
        local old = h.zs[1]
        if run.t - old.t >= HANG_SPAN * 0.9 and old.z - z < HANG_DROP then
          local over = M.over_floor(pawn, l)
          if over and over > (st.air or 60) then
            if not h.said then
              h.said = true
              local still, n = {}, 0
              for _, b in ipairs(bodies(c)) do
                n = n + 1
                if try(function() return c:IsSimulatingPhysics(FName(b)) end) ~= true then still[#still + 1] = b end
              end
              local v = lin_vel(c, bone)
              log(string.format("%s hangs at %.1f s: %s %.0f cm over the floor, dropped %.0f cm in %.1f s, %.0f cm/s; gravity %s, %d of %d bodies not simulating%s; let go",
                i == 1 and "her body" or "the split's copy", run.t, bone, over, old.z - z, run.t - old.t, v and len(v) or -1,
                tostring(try(function() return c:IsGravityEnabled() end)), #still, n,
                #still > 0 and (" (" .. table.concat(still, ",", 1, math.min(#still, 12)) .. ")") or ""))
            end
            gravity(c, true)
            try(function() c:SetSimulatePhysics(true) end)
            try(function() c:SetAllBodiesBelowSimulatePhysics(FName("Bip001"), true, true) end)
            try(function() c:WakeAllRigidBodies() end)
            h.zs = {}
          end
        end
      end
    end
  end
end

-- her fall: a death in the air fell at a steady 2 m/s for over a second, as if under water (thirty-fifth playtest).
-- From when her pelvis starts dropping until it lands, the bodies still on her are kept at least as fast downward as
-- a free fall from then would be (up to fall.max)
local function fall_assist(dt)
  local f = cfg().fall or {}
  -- (not while the launch is held: its lift would read as landing)
  if f.enabled == false or run.piece or run.split or run.asleep or run.landed or run.launchHold or not valid(run.mesh) then return end
  local comp = run.mesh
  local v = lin_vel(comp, "Bip001-Pelvis")
  if not v then return end
  local g = 981 * (f.gravity or 1.0)
  if not run.fallT then
    if v.Z > -(f.start or 100) then return end
    run.fallT = run.t + v.Z / g -- when a free fall would have been this fast
  end
  if v.Z > -(f.land or 60) then
    run.landed = true
    log(string.format("fall: landed at %.2f s after %.2f s falling, %d ticks sped up (at most %.0f cm/s)", run.t,
      run.t - run.fallT, run.fallSped or 0, run.fallTop or 0))
    return
  end
  local want = -math.min(g * (run.t - run.fallT), f.max or 1500)
  local dz = want - v.Z
  if dz >= 0 then return end
  for b in pairs(MASS) do
    local bv = on_her(comp, b) and lin_vel(comp, b)
    if bv then try(function() comp:SetPhysicsLinearVelocity(vec(bv.X, bv.Y, bv.Z + dz), false, FName(b)) end) end
  end
  run.fallSped = (run.fallSped or 0) + 1
  run.fallTop = math.max(run.fallTop or 0, -want)
end

function M.tick(dt)
  -- (an animated death's hand too: its animation kept the fist as well)
  if not (run and run.held) then grip_ease(dt) end
  if not run then return end
  if run.held then
    run.held.t = run.held.t + dt
    if not valid(run.mesh) or run.held.t >= HOLD_MAX then M.release(); return end
    stop_all(run.mesh)
    return
  end
  run.t = run.t + dt
  if run.gripAt and run.t >= run.gripAt then
    local r = grip_release(run.pawn or try(function() return run.mesh:GetOwner() end), run.mesh, cfg())
    log(string.format("her grip eased at %.2f s%s", run.t, r ~= "" and (": " .. r .. " slipped out") or ", nothing left in it"))
  end
  if run.probe and STRETCH_AT[run.probe] and run.t >= STRETCH_AT[run.probe] then
    vlog(string.format("stretch at %.1f s (cm off the start): %s%s", run.t, stretch_report(run.mesh, run.joints),
      run.capes and ("; cape " .. stretch_report(run.mesh, run.capes)) or ""))
    run.probe = run.probe + 1
  end
  -- a piece cut off a living Eve settles too: lying on the floor it shook and spun like her ragdoll did before the
  -- settle check (fifteenth playtest's waist cut); only its own bodies are watched and put to sleep (own: her hair
  -- and jiggle simulate too)
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
  hang_watch()
  fall_assist(dt)
  clamp_spin()
  if run.impactAt and run.t >= run.impactAt then
    run.impactAt = nil
    local d, from = blow(run.pawn, run.mesh, run.hint)
    log(string.format("blow from %s%s", from, impact(run.mesh, cfg(), d, nil, true)))
  elseif run.launchHold then
    local h = run.launchHold
    h.n = h.n - 1
    local sped = 0
    for b in pairs(MASS) do
      local cur = on_her(run.mesh, b) and lin_vel(run.mesh, b)
      local along = cur and (cur.X * h.d.X + cur.Y * h.d.Y + cur.Z * h.d.Z)
      if along and along < h.v then
        local k = h.v - along
        if try(function() run.mesh:SetPhysicsLinearVelocity(vec(cur.X + h.d.X * k, cur.Y + h.d.Y * k, cur.Z + h.d.Z * k), false, FName(b)); return true end) then sped = sped + 1 end
      end
    end
    if h.n <= 0 then
      run.launchHold = nil
      local pv = lin_vel(run.mesh, "Bip001-Pelvis")
      log(string.format("launch held: pelvis %.0f cm/s along it (%d bodies sped up on the last tick)",
        pv and (pv.X * h.d.X + pv.Y * h.d.Y + pv.Z * h.d.Z) or -1, sped))
    end
  end
  if not run.pac or run.toneDone then return end
  local t = cfg().tone or {}
  local hold, fade, rest = t.hold or 0.35, t.fade or 2.5, math.min(math.max((t.rest or 0.1) * stiff(), 0), 1)
  -- landing ends the tone: pulled towards a standing pose with the floor and her own body in the way, every joint
  -- jittered until each part found the ground and the fade ran out (eighteenth playtest)
  local vz = try(function() return run.mesh:GetPhysicsLinearVelocity(FName("Bip001-Pelvis")).Z end)
  if vz then
    run.fall = math.min(run.fall or 0, vz)
    if t.landOff ~= false and run.fall < -(t.fallSpeed or 150) and vz > -(t.landSpeed or 40) then
      -- (stiffer than tuned: down to her resting tone instead, else she went limp the moment she landed)
      if stiff() > 1 and rest > 0 then
        run.toneNow, run.toneDone = rest, true
        if not run.toneHeld then tone_set(rest) end
        log(string.format("tone down to %.2f on landing at %.2f s (fell at %.0f cm/s)", rest, run.t, -run.fall))
        return
      end
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

-- every cut on her undone (gore's cleanup remade her physics): nothing of her is cut off any more
function M.mended(mesh)
  if addr(mesh) == severedOn then severed = {} end
end

-- a split half let go of a body (a limb that went with the other half): the settle check leaves it out
function M.freed(comp, bone)
  local a = addr(comp)
  if not a then return end
  freed[a] = freed[a] or {}
  freed[a][tostring(bone)] = true
end

-- a limb came off: its root stops pulling towards the body (its own joints keep their fading tone). A cut arm lets
-- go of the weapons it held: in a death show's fall the animation kept her sword in the air, in an invisible hand
function M.on_cut(mesh, bone)
  M.broken(mesh, bone)
  local b = tostring(bone)
  local side = b:match("^Bip001%-(%a)%-")
  if side and (b:find("Clavicle") or b:find("UpperArm") or b:find("Forearm") or b:find("Hand")) then
    local pawn = try(function() return mesh:GetOwner() end)
    -- held in the cut arm's hand: weapons hang off Bip001-Prop1/2 (children of Bip001, the animation puts them in
    -- the hand), so it goes by where the grip is
    local hand = try(function() local v = mesh:GetSocketLocation(FName("Bip001-" .. side .. "-Hand")); return vec(v.X, v.Y, v.Z) end)
    local function in_hand(w)
      local at = try(function() local v = w:K2_GetComponentLocation(); return vec(v.X, v.Y, v.Z) end)
      if not (hand and at) then return false end
      local dx, dy, dz = at.X - hand.X, at.Y - hand.Y, at.Z - hand.Z
      return dx * dx + dy * dy + dz * dz < 30 * 30
    end
    local r = valid(pawn) and drop_weapons(pawn, mesh, cfg(), in_hand) or ""
    if r ~= "" then log("cut " .. b .. r) end
  end
  -- a cut on her settled body (a hit after her death): woken and let settle again, or the piece took its throw asleep
  -- or stopped and barely moved (playtest: an arm off 1 s before she settled, "no push")
  if run and valid(run.mesh) and (run.asleep or run.settled) then
    try(function() run.mesh:WakeAllRigidBodies() end)
    run.asleep, run.settled, run.awake, run.still = false, nil, nil, 0
    log("woken for a cut (" .. b .. ")")
  end
  if not (run and valid(run.pac)) then return end
  drive(run.pac, bone, 0, cfg().tone or {})
end

-- restart: the ragdoll starts again in the same death, her weapons stay as the blow left them
function M.stop(pawn, restart)
  M.photo_hold(false, true)
  if run and run.held and valid(run.mesh) then gravity(run.mesh, true) end
  if run then run.held = nil end
  if not restart then
    ease_stop()
    local ns = #splits > 0 and splits_back() or 0
    if ns > 0 then log(string.format("%d split weapons whole again", ns)) end
    local ng = next(gripped) and grip_back() or 0
    if ng > 0 then log(string.format("%d weapons back from her grip onto their sockets", ng)) end
    local nw = #dropped > 0 and weapons_back() or nil
    if nw then log(string.format("%d weapons back on their sockets", nw)) end
    -- a split's copy: gore destroys it as she gets up. Kept here, the next death's hand easing (an animated fall's
    -- sword cut, before any start cleared it) read the freed copy: crash in UE4SS (playtest, the death after a split)
    extra = {}
  end
  if not run then return end
  tone_stop()
  local mesh = run.mesh
  for _, pc in ipairs(run.hung or {}) do
    if valid(pc) then try(function() pc:BreakConstraint() end); try(function() pc:K2_DestroyComponent(pc) end) end
  end
  local n = 0
  if valid(mesh) then
    for bone, m in pairs(run.masses) do if try(function() mesh:SetMassOverrideInKg(FName(bone), m, true); return true end) then n = n + 1 end end
    cap_spin(mesh, cfg(), SPIN_DEFAULT)
  end
  run = nil
  freed = {}
  vlog(string.format("stopped, %d masses put back", n))
end

-- convulse.lua's view of the ragdoll: the components to move (hers and a split's copy), how long it has run and
-- whether she has lain still yet; nil for a piece cut off her alive or a split holding her
function M.view()
  if not run or run.piece or run.held then return nil end
  local comps = { run.mesh }
  for _, c in ipairs(extra) do comps[#comps + 1] = c end
  return { mesh = run.mesh, comps = comps, t = run.t, settled = run.settled }
end
M.MASS = MASS
-- the bones of her bodies (main.lua: her hair's simulated ones, set up again with the cloth)
M.bodies = bodies
-- a bone a cut took off (the root of the piece): nothing left to turn it against
function M.severed(mesh, bone) return addr(mesh) == severedOn and severed[bone] == true end
-- a body that simulates and that the half still shows
function M.live(comp, bone) return live(comp, bone) end
-- a twitch (convulse.lua) moves her for s seconds: she isn't settled meanwhile, and wakes without a "woken" line
function M.twitch(s)
  if not run then return end
  run.twitchTill = math.max(run.twitchTill or 0, run.t + s)
  if run.asleep then run.asleep, run.still = false, 0 end
end

-- photo mode over a death she lies still in: her bodies, and a split's copy's, put back to sleep every tick it is on
-- and a second after. A split's halves, asleep, moved her head 2 cm as it opened and 6 more as it closed (playtest)
function M.hold_still()
  if not run or not run.asleep then return 0 end
  local n = 0
  local comps = { run.mesh }
  for _, c in ipairs(extra) do comps[#comps + 1] = c end
  for _, c in ipairs(comps) do
    if valid(c) then
      if run.piece or not try(function() c:PutAllRigidBodiesToSleep(); return true end) then sleep(c) end
      n = n + 1
    end
  end
  return n
end

-- photo mode opening on a death (P): her tick stops while it is on, so hold_still never ran there, and the one
-- physics step photo mode let through as it opened lifted her upper body 4 cm (playtest: her head 4 cm off once it
-- was on, 15 ms of the game's time gone). Photo mode makes its own pawn as it opens, and her bodies blocked pawns. So
-- before it opens: every body stopped and put to sleep (settled or not: a twitch had woken her), and her meshes
-- ignore pawns till it closes (on false: the responses put back)
-- A death still falling (P in mid-air) was left asleep up there once it closed, nothing to wake her: she hung in
-- the air and moved a little at each P (Nexus report, on stairs). One not lying still yet gets its bodies' velocities
-- back and is woken as it closes, as a split's hold lets go (stopping: left as it is)
M.photoHeld = nil
local photoWake = nil
function M.photo_hold(on, stopping)
  if not on then
    local h, w = M.photoHeld, photoWake
    M.photoHeld, photoWake = nil, nil
    for _, e in ipairs(h or {}) do
      if valid(e.c) then try(function() e.c:SetCollisionResponseToChannel(2, e.r) end) end
    end
    if w and run and not stopping then
      local n = 0
      for _, e in ipairs(w) do
        if valid(e.c) then
          for b, v in pairs(e.vel) do
            try(function() e.c:SetPhysicsLinearVelocity(v.v, false, FName(b)) end)
            try(function() e.c:SetPhysicsAngularVelocityInDegrees(v.w, false, FName(b)) end)
            n = n + 1
          end
          try(function() e.c:WakeAllRigidBodies() end)
        end
      end
      run.asleep, run.still = false, 0
      log(string.format("photo mode closed on her before she lay still: woken, %d body velocities back", n))
    end
    return h and #h or 0
  end
  if not run or M.photoHeld then return 0 end
  local comps = { run.mesh }
  for _, c in ipairs(extra) do comps[#comps + 1] = c end
  M.photoHeld = {}
  photoWake = not run.asleep and {} or nil
  for _, c in ipairs(comps) do
    if valid(c) then
      if photoWake then photoWake[#photoWake + 1] = { c = c, vel = velocities(c) } end
      stop_all(c)
      if run.piece or not try(function() c:PutAllRigidBodiesToSleep(); return true end) then sleep(c) end
      local r = try(function() return c:GetCollisionResponseToChannel(2) end)
      if r and r ~= 0 then
        try(function() c:SetCollisionResponseToChannel(2, 0) end)
        M.photoHeld[#M.photoHeld + 1] = { c = c, r = r }
      end
    end
  end
  run.asleep = true
  return #comps
end

-- a new Eve (the level reloaded): drop what was held from the old one without touching it
function M.forget()
  M.photoHeld = nil
  layouts = {}
  run, speeds, dropped, extra, gripped, splits = nil, {}, {}, {}, {}, {}
  severed, severedOn = {}, nil
  freed = {}
end

return M
