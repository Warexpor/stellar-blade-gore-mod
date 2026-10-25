-- physfix.lua: the ragdoll fixes of every outfit's physics asset, made in game (tune.physfix).
--
-- The release ships no outfits pak: every outfit she puts on, vanilla or any mod's, on Linux or Windows, gets the
-- fixes the build's outfits container makes (assetkit/outfits.py, built only for dev and as the reference these are
-- tested to: test/run.sh phys). An asset that pak did patch is left alone. This tells the log which, and fixes:
--   * damping: vanilla bodies fall at ~2 m/s (linear 5.0) and turn as if under water (angular 10). The main
--     bodies get the data mod's values in the physics asset's defaults, and the mesh re-creates its bodies from it
--     while she is animated (they are kinematic then, so nothing shows).
--   * joint limits: the main joints' soft limits give way under a push; they're made hard, and a motion limited to a
--     few degrees is locked (at its limit all the time, it buzzed).
--   * loose bodies: twist and helper bones that carry a cape or skirt chain, with a body but no joint to anything
--     (in a ragdoll they fly off and drag the arm's or thigh's skin with them), get a locked joint to the nearest
--     body above them, the data mod's, added to the asset with sbslice.dll ("j"); without it, a locked constraint
--     component while she is ragdolled.
--   * joint ranges: the main joints' twist re-centred on her bind pose, read from the mesh by sbslice.dll ("b"), and
--     the hips' sideways swing, as the data mod's (outfits.py joint_limits, the same numbers: test/run.sh phys)
--   * collision: none of her bodies collide with each other, only the world, by the asset's collision table, which
--     sbslice.dll fills ("t"); without the DLL the torso's jiggle bodies are left colliding with nothing instead
--   * no physics asset at all: an outfit mod's mesh exported without one (Eve with no Clothes on) has no bodies,
--     so she can't ragdoll. It gets the asset next to it by the game's naming (<mesh>_Physics, which the data mod
--     ships patched), else tune.physfix.fallback (Eve's base body's).
-- Self-collision is already off for an unpatched asset (main.lua, tune.selfCollision "auto") and masses come from
-- active.lua either way. CPU access needs nothing from here: sbslice.dll makes the engine keep every skeletal mesh's
-- LOD0 CPU copy (its NeedCPUData patch), so any outfit can be cut; without the DLL a mesh lacking it can't be.

local M = {}
local ctx
local try, valid

local function cfg() return ctx.tune.physfix or {} end
local function log(s) ctx.log("physfix: " .. s) end
local function name(o) return valid(o) and (try(function() return o:GetFName():ToString() end) or "?") or "<nil>" end

local MAIN = {
  ["Bip001-Pelvis"] = true, ["Bip001-Spine"] = true, ["Bip001-Spine1"] = true, ["Bip001-Spine2"] = true,
  ["Bip001-Neck"] = true, ["Bip001-Head"] = true, ["Bip001-L-Clavicle"] = true, ["Bip001-R-Clavicle"] = true,
  ["Bip001-L-UpperArm"] = true, ["Bip001-R-UpperArm"] = true, ["Bip001-L-Forearm"] = true, ["Bip001-R-Forearm"] = true,
  ["Bip001-L-Hand"] = true, ["Bip001-R-Hand"] = true, ["Bip001-L-Thigh"] = true, ["Bip001-R-Thigh"] = true,
  ["Bip001-L-Calf"] = true, ["Bip001-R-Calf"] = true, ["Bip001-L-Foot"] = true, ["Bip001-R-Foot"] = true,
}
local ACM_LIMITED, ACM_LOCKED = 1, 2
local LCM_LOCKED = 2

local seenMesh = nil   -- address of the SkeletalMesh last checked
local fixed = {}       -- physics asset address -> true once its defaults are changed (the asset stays loaded)
local state = nil      -- { patched, cpu, pa } for the current mesh
local locks = {}       -- constraint components made for this ragdoll
local waiting = false  -- logged that an outfit waits for sbslice.dll
local filledTable = {} -- physics asset address -> true once sbslice.dll filled its collision table

function M.init(c)
  ctx = c
  try, valid = c.try, c.valid
end

local function bodies_of(pa)
  local out = {}
  try(function()
    pa.SkeletalBodySetups:ForEach(function(_, e)
      local bs = e:get()
      if valid(bs) then out[#out + 1] = bs end
    end)
  end)
  return out
end

local function constraints_of(pa)
  local out = {}
  try(function()
    pa.ConstraintSetup:ForEach(function(_, e)
      local t = e:get()
      if valid(t) then out[#out + 1] = t end
    end)
  end)
  return out
end

-- the data mod sets LinearDamping 0.2 on the main bodies (vanilla 5.0), as main.lua tells them apart
local function patched(pa)
  for _, bs in ipairs(bodies_of(pa)) do
    if try(function() return bs.BoneName:ToString() end) == "Bip001-Pelvis" then
      return (try(function() return bs.DefaultInstance.LinearDamping end) or 5) < 1.0
    end
  end
  return false
end

-- LOD0's bAllowCPUAccess, nil if it can't be read
local function cpu_access(sk)
  return try(function() return sk.LODInfo[1].bAllowCPUAccess end)
end

local function load(path)
  local o = try(function() return StaticFindObject(path) end)
  -- not from the pak around a respawn (main.lua's may_load)
  if not valid(o) and LoadAsset and ctx.may_load() then o = try(function() return LoadAsset(path) end) end
  return valid(o) and o or nil
end

-- the physics asset a mesh without one should have: "/Game/.../X.X" -> "/Game/.../X_Physics.X_Physics"
local function borrow_physics(sk)
  local full = try(function() return sk:GetFullName() end) or ""
  local pkg, obj = full:match("(/Game/[^%.%s]+)%.([%w_]+)$")
  local tried = {}
  -- a variant's trailing digit (CH_P_EVE_InnerSuit1) is still the same outfit
  for _, base in ipairs({ pkg, pkg and pkg:gsub("%d+$", "") }) do
    if base then
      local dir, leaf = base:match("^(.*)/([^/]+)$")
      local path = string.format("%s/%s_Physics.%s_Physics", dir, leaf, leaf)
      if not tried[path] then
        tried[path] = true
        local o = load(path)
        if o then return o, path end
      end
    end
  end
  local fb = cfg().fallback or "/Game/Art/Character/PC/CH_P_EVE_01/CH_P_EVE_01_Physics.CH_P_EVE_01_Physics"
  return load(fb), fb
end

-- ---- joint ranges from the bind pose: assetkit/outfits.py's joint_limits, step for step (test/run.sh phys holds the
-- two to the same numbers on every vanilla outfit) ----
local function vsub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
local function unit(a) local l = math.sqrt(dot(a, a)); return { a[1] / l, a[2] / l, a[3] / l } end
local function qrot(q, v) -- q {x, y, z, w}
  local u, w = { q[1], q[2], q[3] }, q[4]
  local c0 = cross(u, v)
  local m = cross(u, { c0[1] + v[1] * w, c0[2] + v[2] * w, c0[3] + v[3] * w })
  return { v[1] + 2 * m[1], v[2] + 2 * m[2], v[3] + 2 * m[3] }
end
local function qmul(a, b)
  return { a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2], a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
    a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4], a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3] }
end
local function frame(q, pri, sec) local x, y = qrot(q, pri), qrot(q, sec); return { x, y, cross(x, y) } end
local function round2(x) return tonumber(string.format("%.2f", x)) end
local atan2 = math.atan2 or math.atan

-- cons: { child, parent, pri1, sec1, pri2, sec2 } per joint (axes {x, y, z}); bind: bone -> { q = {x, y, z, w},
-- t = {x, y, z} } in component space; ranges: tune.physfix.ranges. -> child -> { twist, turn }, notes. The twist is
-- the joint's bend (PhAT framed them as hinges about X), limited the same both ways round the asset's zero: twist is
-- half the range, turn how far frame 2 turns about X to centre it on the bind pose. Her front: her left foot to toe
function M.joint_ranges(cons, bind, ranges)
  local out, notes = {}, {}
  local toe, foot = bind["Bip001-L-Toe0"], bind["Bip001-L-Foot"]
  if not (toe and foot) then return out, { "no Bip001-L-Toe0 (no front)" } end
  local f = vsub(toe.t, foot.t)
  local fwd = unit({ f[1], f[2], 0 })
  for _, c in ipairs(cons) do
    local r, bc, ba = ranges[c.child], bind[c.child], bind[c.parent]
    if r and bc and ba then
      local be = bind[r.e]
      if not be then
        notes[#notes + 1] = c.child .. ": no " .. r.e
      else
        local f1, f2 = frame(bc.q, c.pri1, c.sec1), frame(ba.q, c.pri2, c.sec2)
        local rel = {}
        for i = 1, 3 do rel[i] = {}; for j = 1, 3 do rel[i][j] = dot(f2[i], f1[j]) end end
        local w = math.sqrt(math.max(0, 1 + rel[1][1] + rel[2][2] + rel[3][3])) / 2
        local x = w > 1e-6 and (rel[3][2] - rel[2][3]) / (4 * w) or 1.0
        local atBind = math.deg(2 * atan2(x, w))
        local ahead = dot(cross(f1[1], unit(vsub(be.t, bc.t))), fwd)
        if math.abs(ahead) < 0.5 then
          notes[#notes + 1] = string.format("%s: its twist doesn't bend it front to back (%+.2f)", c.child, ahead)
        else
          local lo, hi
          if ahead > 0 then lo, hi = -r.back, r.front else lo, hi = -r.front, r.back end
          lo, hi = lo + atBind, hi + atBind
          local o = { twist = round2((hi - lo) / 2), turn = round2((hi + lo) / 2) }
          out[c.child] = o
          local note = string.format("%s %+.0f at bind, twist %s turned %+g", c.child, atBind, o.twist, o.turn)
          -- the sideways swing (Swing1, about frame 2's Z) when the range says how far in and out: frame 2, turned
          -- for the twist, is turned about its Z to centre the cone there (the engine's +-45 round the A pose let an
          -- arm fold 15 deg into her chest, playtest 43)
          local pel = bind["Bip001-Pelvis"]
          if r.inward and r.outward and pel then
            local sec2 = M.turned(c.pri2, c.sec2, o.turn)
            local g2 = frame(ba.q, c.pri2, sec2)
            local rl = {}
            for i = 1, 3 do rl[i] = {}; for j = 1, 3 do rl[i][j] = dot(g2[i], f1[j]) end end
            local qw = math.sqrt(math.max(0, 1 + rl[1][1] + rl[2][2] + rl[3][3])) / 2
            local q = { (rl[3][2] - rl[2][3]) / (4 * qw), (rl[1][3] - rl[3][1]) / (4 * qw), (rl[2][1] - rl[1][2]) / (4 * qw), qw }
            local n = math.sqrt(q[1] * q[1] + q[4] * q[4])
            local sw = qmul(q, { -q[1] / n, 0, 0, q[4] / n }) -- the swing: q without its twist
            local s0 = math.deg(2 * atan2(sw[3], sw[4]))
            local lat = cross(fwd, { 0, 0, 1 })
            if dot(vsub(bc.t, pel.t), lat) < 0 then lat = { -lat[1], -lat[2], -lat[3] } end
            local side = dot(g2[3], fwd)
            if math.abs(side) < 0.5 then
              note = note .. string.format("; its Swing1 doesn't swing it sideways (%+.2f)", side)
            else
              local sign = dot(cross(g2[3], unit(vsub(be.t, bc.t))), lat) > 0 and 1 or -1
              o.swing1 = round2((r.inward + r.outward) / 2)
              o.tilt = round2(s0 + sign * (r.outward - r.inward) / 2)
              note = note .. string.format(", swing1 %s tilted %+g (%+.1f at bind)", o.swing1, o.tilt, s0)
            end
          end
          notes[#notes + 1] = note
        end
      end
    end
  end
  return out, notes
end

-- frame 2's secondary axis turned by deg about its primary one (the twist then reads deg less: the range moves by it)
function M.turned(pri, sec, deg)
  local c, t = cross(pri, sec), math.rad(deg)
  return { sec[1] * math.cos(t) + c[1] * math.sin(t), sec[2] * math.cos(t) + c[2] * math.sin(t), sec[3] * math.cos(t) + c[3] * math.sin(t) }
end

local function vec_of(s) return { s.X, s.Y, s.Z } end

-- the main joints of an asset, for joint_ranges
local function main_joints(pa)
  local out = {}
  for _, t in ipairs(constraints_of(pa)) do
    local j = try(function()
      local d = t.DefaultInstance
      return { child = d.ConstraintBone1:ToString(), parent = d.ConstraintBone2:ToString(), pri1 = vec_of(d.PriAxis1),
        sec1 = vec_of(d.SecAxis1), pri2 = vec_of(d.PriAxis2), sec2 = vec_of(d.SecAxis2), t = t }
    end)
    if j and MAIN[j.child] then out[#out + 1] = j end
  end
  return out
end

-- the main joints as the data mod leaves them: hard limits, a motion limited under lockBelow degrees locked, the cone
-- overrides (swing) and the twist ranges (lims, from joint_ranges). The joints' own defaults, so bodies made after it
-- have them. -> how many joints, how many got a range
function M.fix_joints(joints, lims, g)
  local hard, below, swing = g.hardLimits ~= false, g.lockBelow or 6, g.swing or {}
  local n, nr = 0, 0
  for _, j in ipairs(joints) do
    if try(function()
      local d = j.t.DefaultInstance
      local p = d.ProfileInstance
      local cone, tw = p.ConeLimit, p.TwistLimit
      if hard then cone.bSoftConstraint = false; tw.bSoftConstraint = false end
      local function lock(lim, m, deg)
        if hard and lim[m] == ACM_LIMITED and (lim[deg] == 0 or lim[deg] < below) then lim[m] = ACM_LOCKED end
      end
      lock(cone, "Swing1Motion", "Swing1LimitDegrees")
      lock(cone, "Swing2Motion", "Swing2LimitDegrees")
      if not lims[j.child] then lock(tw, "TwistMotion", "TwistLimitDegrees") end
      for k, v in pairs(swing[j.child] or {}) do cone[k] = v end
      local l = lims[j.child]
      if l then
        tw.TwistLimitDegrees = l.twist
        local s = M.turned(j.pri2, j.sec2, l.turn)
        d.SecAxis2.X, d.SecAxis2.Y, d.SecAxis2.Z = s[1], s[2], s[3]
        if l.swing1 then
          -- the sideways swing: the cone's half angle, frame 2 turned by tilt about its Z (pri x sec)
          cone.Swing1LimitDegrees, cone.Swing1Motion = l.swing1, ACM_LIMITED
          local t, a = math.rad(l.tilt), j.pri2
          local pa = { a[1] * math.cos(t) + s[1] * math.sin(t), a[2] * math.cos(t) + s[2] * math.sin(t), a[3] * math.cos(t) + s[3] * math.sin(t) }
          local sb = { s[1] * math.cos(t) - a[1] * math.sin(t), s[2] * math.cos(t) - a[2] * math.sin(t), s[3] * math.cos(t) - a[3] * math.sin(t) }
          d.PriAxis2.X, d.PriAxis2.Y, d.PriAxis2.Z = pa[1], pa[2], pa[3]
          d.SecAxis2.X, d.SecAxis2.Y, d.SecAxis2.Z = sb[1], sb[2], sb[3]
        end
        nr = nr + 1
      end
      return true
    end) then n = n + 1 end
  end
  return n, nr
end

-- the bind pose of the bones named (a set), from sbslice.dll: bone -> { q, t }, or nil and why
local function bind_pose(mesh, sk, names)
  local list, byIdx = {}, {}
  for b in pairs(names) do
    local i = try(function() return mesh:GetBoneIndex(FName(b)) end)
    if i and i >= 0 then list[#list + 1] = string.format("%x", i); byIdx[i] = b end
  end
  local r = ctx.gore.command(string.format("b%x,%s", sk:GetAddress(), table.concat(list, ",")))
  if r:sub(1, 3) ~= "ok " then return nil, r end
  local out = {}
  for item in r:sub(4):gmatch("[^|]+") do
    local f = {}
    for x in item:gmatch("%S+") do f[#f + 1] = x end
    local b = byIdx[tonumber(f[1])]
    if b and #f == 8 then
      out[b] = { q = { tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5]) }, t = { tonumber(f[6]), tonumber(f[7]), tonumber(f[8]) } }
    end
  end
  return out
end


-- a locked joint for each loose body (M.loose_bodies) to the body above it, as the data mod adds them (outfits.py
-- orphan_joints, patch_shows.py add_joints): a new PhysicsConstraintTemplate, frame 1 the child bone, frame 2 the
-- child at its bind pose in the parent's space, every motion locked, no collision between the two, appended to the
-- asset's ConstraintSetup by sbslice.dll ("j"). Real joints, made with her bodies whenever the mesh makes them: a
-- constraint component added at the ragdoll's start didn't hold CH_P_EVE_29's thigh twists, which carry her upper
-- thighs' skin, and the skin hung off the thigh (playtest 39). -> how many, or nil and why
function M.add_joints(pa, loose, bind)
  local cls = try(function() return StaticFindObject("/Script/Engine.PhysicsConstraintTemplate") end)
  if not valid(cls) then return nil, "no PhysicsConstraintTemplate class" end
  local have = constraints_of(pa)
  local first = have[1] and try(function() return have[1]:GetAddress() end)
  if not first then return nil, "the asset has no joint to find the array by" end
  local made, names = {}, {}
  for _, l in ipairs(loose) do
    local b, up = l[1], l[2]
    local c, a = bind[b], bind[up]
    if c and a then
      local ia = { -a.q[1], -a.q[2], -a.q[3], a.q[4] }
      local q = qmul(ia, c.q)
      local pos, pri, sec = qrot(ia, vsub(c.t, a.t)), qrot(q, { 1, 0, 0 }), qrot(q, { 0, 1, 0 })
      local t = try(function() return StaticConstructObject(cls, pa) end)
      if not valid(t) then t = try(function() return StaticConstructObject(cls, pa, FName("None"), 0) end) end
      if valid(t) and try(function()
        local d = t.DefaultInstance
        d.JointName, d.ConstraintBone1, d.ConstraintBone2 = FName(b), FName(b), FName(up)
        d.Pos2.X, d.Pos2.Y, d.Pos2.Z = pos[1], pos[2], pos[3]
        d.PriAxis2.X, d.PriAxis2.Y, d.PriAxis2.Z = pri[1], pri[2], pri[3]
        d.SecAxis2.X, d.SecAxis2.Y, d.SecAxis2.Z = sec[1], sec[2], sec[3]
        local p = d.ProfileInstance
        p.LinearLimit.XMotion, p.LinearLimit.YMotion, p.LinearLimit.ZMotion = LCM_LOCKED, LCM_LOCKED, LCM_LOCKED
        p.ConeLimit.Swing1Motion, p.ConeLimit.Swing2Motion, p.TwistLimit.TwistMotion = ACM_LOCKED, ACM_LOCKED, ACM_LOCKED
        p.bDisableCollision = true
        return true
      end) then
        made[#made + 1] = string.format("%x", t:GetAddress())
        names[#names + 1] = b .. ">" .. up
      end
    end
  end
  if #made == 0 then return nil, "no joint made" end
  local r = ctx.gore.command(string.format("j%x,%x,%x,%s", pa:GetAddress(), #have, first, table.concat(made, ",")))
  if r:sub(1, 3) ~= "ok " then return nil, r end
  return #made, table.concat(names, ", ")
end

-- sbslice.dll: "ready", "failed" (or no gore: as failed), else still starting
local function dll()
  local g = ctx.gore
  return g and g.native_state and g.native_state() or "failed"
end

-- the torso's jiggle bodies (breasts, belly and hip correctives): a leaf body whose nearest body above is one of these
local TORSO = { ["Bip001-Pelvis"] = true, ["Bip001-Spine"] = true, ["Bip001-Spine1"] = true, ["Bip001-Spine2"] = true,
  ["Bip001-Neck"] = true }

-- the data mod keeps every accessory body from touching her (patch_shows.py, accessory_collision); from here the
-- collision table can't be reached, so the torso's jiggle bodies get the body's own "collides with nothing"
-- (UBodySetup.CollisionReponse, the engine's spelling): they sit inside her chest and shoved her arms and torso
-- every frame, and she buzzed on the floor (CH_P_EVE_30's breasts; CH_P_EVE_10 has none and lay still). Only
-- leaves: a cape or skirt chain keeps the floor under it
local function quiet_jiggle(pa, mesh)
  local list, has, above = bodies_of(pa), {}, {}
  for _, bs in ipairs(list) do has[try(function() return bs.BoneName:ToString() end) or ""] = true end
  local inner = {}
  for b in pairs(has) do
    if b ~= "" and not MAIN[b] then
      local up = try(function() return mesh:GetParentBone(FName(b)):ToString() end)
      while up and up ~= "None" and not has[up] do up = try(function() return mesh:GetParentBone(FName(up)):ToString() end) end
      if up and up ~= "None" then above[b] = up; inner[up] = true end
    end
  end
  local done = {}
  for _, bs in ipairs(list) do
    local b = try(function() return bs.BoneName:ToString() end) or ""
    if above[b] and TORSO[above[b]] and not inner[b] and try(function() bs.CollisionReponse = 1; return true end) then
      done[#done + 1] = b
    end
  end
  table.sort(done)
  return #done > 0 and string.format("%d jiggle bodies collide with nothing (%s)", #done, table.concat(done, " "))
    or "no jiggle bodies in the torso"
end

-- Every outfit, patched or not: an outfit's breasts, neck pieces, arm twists and armour plates are authored kinematic
-- (PhysType_Kinematic) on joints of 0.1-1 deg with soft stiffness, to ride their bone while she lives. The ragdoll
-- simulates every body, and those light bodies fought their stiff joints: she buzzed and spun on every outfit but
-- CH_P_EVE_10, whose only extra bodies are its simulated hair and the hips. Their joints are locked solid now, so they
-- ride their bone as one with it. (Keeping them kinematic instead pinned her: an immovable body jointed to the chest
-- and thighs held her half of a split standing while the copy fell, playtest.)
local welded = {}      -- physics asset address -> true once its kinematic accessories' joints are locked
local steadied = {}    -- physics asset address -> true once its solver and end damping are set

-- every asset: more solver iterations on every body (the engine's 8 position / 1 velocity let joints come apart and
-- snap back: a ragdoll that started mid-fall shot her off at 10-23 m/s, and her hands and head spun at the cap for
-- seconds, thirty-fourth playtest), and the head, hands and feet turn-damped (light ends on a loose joint flick about)
local ENDS = { ["Bip001-Head"] = "head", ["Bip001-L-Hand"] = "hands", ["Bip001-R-Hand"] = "hands",
  ["Bip001-L-Foot"] = "feet", ["Bip001-R-Foot"] = "feet" }
local function steady(pa)
  local g = cfg()
  local pos, vel = g.positionIterations or 16, g.velocityIterations or 4
  local damp = g.endsAngularDamping or { head = 2.0, hands = 3.0, feet = 3.0 }
  local n, e = 0, 0
  for _, bs in ipairs(bodies_of(pa)) do
    if try(function()
      local d = bs.DefaultInstance
      if d.PositionSolverIterationCount < pos then d.PositionSolverIterationCount = pos end
      if d.VelocitySolverIterationCount < vel then d.VelocitySolverIterationCount = vel end
      return true
    end) then n = n + 1 end
    local k = ENDS[try(function() return bs.BoneName:ToString() end) or ""]
    if k and damp[k] and try(function()
      if bs.DefaultInstance.AngularDamping < damp[k] then bs.DefaultInstance.AngularDamping = damp[k] end
      return true
    end) then e = e + 1 end
  end
  return string.format("solver %d/%d on %d bodies, %d ends turn-damped", pos, vel, n, e)
end
-- Only a joint to the body right above it in her skeleton: the hips (Ab-L/R-Hip) hang under the thighs but are jointed
-- to Bip001-Spine, and locked that welded each thigh to her spine (a cut leg stayed on, her legs couldn't swing, every
-- outfit, playtest). Such cross joints keep the author's soft limits.
local function weld_kinematic(pa, mesh)
  local kin, has = {}, {}
  for _, bs in ipairs(bodies_of(pa)) do
    local b = try(function() return bs.BoneName:ToString() end) or ""
    local t = try(function() return bs.PhysicsType end)
    has[b] = true
    if b ~= "" and not MAIN[b] and (t == 1 or tostring(t):find("Kinematic") ~= nil) then kin[b] = true end
  end
  -- nil when the way up crosses a limb bone without a body (EVE_21 has no thigh bodies: Ab-L-Thigh-Tw0 under
  -- Bip001-L-Thigh is jointed to Bip001-Spine, and locked it held her leg to the spine)
  local function above(b)
    local up = try(function() return mesh:GetParentBone(FName(b)):ToString() end)
    while up and up ~= "None" and not has[up] do
      if MAIN[up] then return nil end
      up = try(function() return mesh:GetParentBone(FName(up)):ToString() end)
    end
    return up
  end
  local done = {}
  for _, t in ipairs(constraints_of(pa)) do
    local child = try(function() return t.DefaultInstance.ConstraintBone1:ToString() end)
    local parent = try(function() return t.DefaultInstance.ConstraintBone2:ToString() end)
    if child and kin[child] and parent and above(child) == parent and try(function()
      local p = t.DefaultInstance.ProfileInstance
      p.ConeLimit.Swing1Motion = ACM_LOCKED
      p.ConeLimit.Swing2Motion = ACM_LOCKED
      p.TwistLimit.TwistMotion = ACM_LOCKED
      p.LinearLimit.XMotion = LCM_LOCKED
      p.LinearLimit.YMotion = LCM_LOCKED
      p.LinearLimit.ZMotion = LCM_LOCKED
      return true
    end) then done[#done + 1] = child end
  end
  table.sort(done)
  return done
end

local function fix_defaults(pa, mesh, sk)
  local g = cfg()
  local lin, ang = g.linearDamping or 0.2, g.angularDamping or 1.0
  local nb = 0
  for _, bs in ipairs(bodies_of(pa)) do
    if MAIN[try(function() return bs.BoneName:ToString() end) or ""] then
      if try(function() bs.DefaultInstance.LinearDamping = lin; bs.DefaultInstance.AngularDamping = ang; return true end) then
        nb = nb + 1
      end
    end
  end
  local back = try(function()
    for _, bs in ipairs(bodies_of(pa)) do
      if bs.BoneName:ToString() == "Bip001-Pelvis" then return bs.DefaultInstance.LinearDamping end
    end
  end)
  -- the joints: ranges and the loose bodies' joints from the bind pose (read before fix_joints turns any frame)
  local joints, lims, why = main_joints(pa), {}, ""
  local loose = g.lockLoose ~= false and M.loose_bodies(pa, mesh) or {}
  local bind
  if (g.ranges or #loose > 0) and dll() == "ready" then
    local names = { ["Bip001-L-Toe0"] = true, ["Bip001-L-Foot"] = true, ["Bip001-Pelvis"] = true }
    for _, j in ipairs(joints) do
      local r = (g.ranges or {})[j.child]
      if r then names[j.child], names[j.parent], names[r.e] = true, true, true end
    end
    for _, l in ipairs(loose) do names[l[1]], names[l[2]] = true, true end
    local err
    bind, err = bind_pose(mesh, sk, names)
    if bind and g.ranges then
      local notes
      lims, notes = M.joint_ranges(joints, bind, g.ranges)
      for _, n in ipairs(notes) do if not n:find(" at bind,", 1, true) then why = why .. "; " .. n end end
    elseif not bind then
      why = "; no bind pose: " .. tostring(err)
    end
  elseif g.ranges or #loose > 0 then
    why = "; no sbslice.dll, so no ranges and no joints for loose bodies"
  end
  local nj, nr = M.fix_joints(joints, lims, g)
  if bind and #loose > 0 then
    local n, what = M.add_joints(pa, loose, bind)
    why = why .. (n and ("; loose bodies jointed: " .. what) or ("; loose bodies NOT jointed (" .. tostring(what) .. "): locked at the ragdoll's start instead"))
  end
  -- collision: none between her bodies (the DLL's table), else the jiggle bodies with nothing
  local coll = ""
  local filled = false
  if g.collisionTable ~= false and dll() == "ready" then
    local r = ctx.gore.command(string.format("t%x,%x", pa:GetAddress(), #bodies_of(pa)))
    filled = r:sub(1, 3) == "ok "
    filledTable[pa:GetAddress()] = filled or nil
    coll = filled and (", her bodies collide with nothing of hers (" .. r .. ")") or (", collision table NOT filled: " .. r)
  end
  if not filled and g.quietJiggle ~= false then coll = coll .. ", " .. quiet_jiggle(pa, mesh) end
  return string.format("damping %.1f/%.1f on %d main bodies (pelvis reads back %s), %d main joints fixed, %d ranged from the bind pose%s%s",
    lin, ang, nb, back and string.format("%.2f", back) or "?", nj, nr, why, coll)
end

M.fix_asset = fix_defaults -- (test/run.sh phys runs it on the vanilla outfits)

-- her mesh's physics asset: the component's, else the mesh's, else the one given to this mesh here. A null
-- UObject comes back from UE4SS as an invalid wrapper, which is truthy, so `a() or b()` never reached b().
function M.asset(mesh)
  local pa = try(function() return mesh:GetPhysicsAsset() end)
  if valid(pa) then return pa end
  pa = try(function() return mesh.SkeletalMesh.PhysicsAsset end)
  if valid(pa) then return pa end
  local addr = try(function() return mesh.SkeletalMesh:GetAddress() end)
  if state and state.borrowed and addr and addr == seenMesh and valid(state.pa) then return state.pa end
  return nil
end

-- every gameplay tick: a new outfit mesh is checked once, and an unpatched physics asset fixed (bodies re-made
-- from it while they are kinematic). live: she is ragdolled already, so the bodies are left as they are
function M.check(pawn, mesh, live)
  if cfg().enabled == false then return end
  local sk = try(function() return mesh.SkeletalMesh end)
  local addr = valid(sk) and try(function() return sk:GetAddress() end)
  if not addr then return end
  if addr == seenMesh then
    -- a borrowed asset is the component's own override, which the mesh's own (none) can replace again: gore's undo
    -- and recovery re-make the bodies from the mesh's asset (nineteenth playtest: InnerSuit read no physics asset at
    -- death, so the active ragdoll found no bodies to weigh)
    -- at most once in 2 s and 10 times an outfit: another mod that keeps setting its own asset (an outfit or body
    -- mod) had her bodies re-made every tick, 1-2 fps (reported)
    local now = try(function() return mesh:GetPhysicsAsset() end)
    if not live and state and state.borrowed and valid(state.pa) and (state.lost or 0) < 10
      and os.clock() - (state.lostAt or -1e9) >= 2
      and not (valid(now) and try(function() return now:GetAddress() == state.pa:GetAddress() end)) then
      local ok = try(function() mesh:SetPhysicsAsset(state.pa, true); return true end)
      state.lost, state.lostAt = (state.lost or 0) + 1, os.clock()
      if state.lost <= 3 or state.lost == 10 or not ok then
        log(string.format("outfit %s lost the physics asset it was given: %s%s", name(sk), ok and "given again" or "NOT given again",
          state.lost == 10 and " (another mod keeps its own: left to it)" or ""))
      end
    end
    return
  end
  -- a mesh checked before in this level: its state back, nothing re-made (a mod swapping her meshes back and forth
  -- ran the whole check, bodies re-made, on every swap)
  local back = M.seen[addr]
  if back and back.name == name(sk) then
    seenMesh, state = addr, back.state
    return
  end
  seenMesh = addr
  local pa = M.asset(mesh)
  local cpu = cpu_access(sk)
  local borrowed = ""
  if not valid(pa) and cfg().borrow ~= false then
    local o, path = borrow_physics(sk)
    -- on the mesh asset too: the game drops the component's override on every outfit apply and gore's undo, and a
    -- death started with none (InnerSuit, physics <nil>, after a dozen "given again" in a second)
    if o then try(function() sk.PhysicsAsset = o end) end
    if o and try(function() mesh:SetPhysicsAsset(o, true); return true end) then
      pa = o
      borrowed = string.format(" (the mesh has none: gave it %s)", path)
    else
      borrowed = string.format(" (the mesh has none, and %s didn't load: she can't ragdoll)", path)
    end
  end
  -- an asset missing main bodies (CH_P_EVE_21 has no thighs: its calves are jointed to the spine) can't ragdoll or
  -- lose a limb right: a body-less thigh's skin stays on the hip while the calf flies, and the clothes on it
  -- stretched between them (playtest 30). Such an outfit gets a complete asset instead (its skirt bodies go: the
  -- skirt rides its bones)
  if valid(pa) and cfg().complete ~= false then
    local has, miss = {}, {}
    for _, bs in ipairs(bodies_of(pa)) do has[try(function() return bs.BoneName:ToString() end) or ""] = true end
    for b in pairs(MAIN) do if not has[b] then miss[#miss + 1] = b:gsub("^Bip001%-", "") end end
    if #miss > 0 then
      table.sort(miss)
      local path = cfg().completeWith or "/Game/Art/Character/PC/CH_P_EVE_InnerSuit/CH_P_EVE_InnerSuit_Physics.CH_P_EVE_InnerSuit_Physics"
      local o = load(path)
      local own = name(pa)
      if o and o ~= pa then
        try(function() sk.PhysicsAsset = o end)
        if try(function() mesh:SetPhysicsAsset(o, true); return true end) then
          pa = o
          borrowed = string.format(" (its own %s has no body on %s: gave it %s)", own, table.concat(miss, ","), path)
        end
      else
        borrowed = string.format(" (no body on %s, and %s didn't load)", table.concat(miss, ","), path)
      end
    end
  end
  local paddr = valid(pa) and try(function() return pa:GetAddress() end)
  local weld = ""
  if paddr and not steadied[paddr] and cfg().steady ~= false then
    steadied[paddr] = true
    weld = "; " .. steady(pa)
    if not live then
      local ok = try(function() mesh:SetPhysicsAsset(pa, true); return true end)
      weld = weld .. (ok and ", bodies re-made" or ", bodies NOT re-made")
    end
  end
  if paddr and not welded[paddr] and cfg().weldKinematic ~= false then
    welded[paddr] = true
    local w = weld_kinematic(pa, mesh)
    if #w > 0 then
      weld = string.format("; %d kinematic accessory joints locked (%s)", #w, table.concat(w, " "))
      if not live then
        local ok = try(function() mesh:SetPhysicsAsset(pa, true); return true end)
        weld = weld .. (ok and ", bodies re-made" or ", bodies NOT re-made")
      end
    end
  end
  -- an asset fixed here reads as patched from then on: it isn't
  state = { patched = valid(pa) and not fixed[paddr or 0] and patched(pa), cpu = cpu, pa = pa, borrowed = borrowed:find("gave it") ~= nil }
  M.seen[addr] = { name = name(sk), state = state }
  -- (the asset's flag; sbslice.dll keeps every skeletal mesh's LOD0 CPU copy whatever it says)
  local forced = ctx and ctx.cpu_forced
  local what = string.format("outfit %s, physics %s%s: %s, LOD0 CPU access %s%s", name(sk), name(pa), borrowed,
    state.patched and "patched" or "NOT patched", forced and "kept by sbslice.dll" or cpu == nil and "unknown" or tostring(cpu), weld)
  if state.patched and (cpu ~= false or forced) then log(what); return end
  local note = forced and " (an outfit the build didn't see: its physics fixed from here)"
    or " (an outfit mod the build didn't see, or one that loads after this mod: rerun ./build.sh --install)"
  -- the flag isn't the whole story: InnerSuit read false and still cut (nineteenth playtest)
  if cpu == false and not forced then note = note .. "; cuts may not read this mesh (a failed cut logs 'no CPU copy')" end
  if not valid(pa) or state.patched then log(what .. note); return end
  if paddr and not fixed[paddr] then
    -- the ranges and the collision table need sbslice.dll: it answers within a few seconds of the game starting
    local d = dll()
    if d ~= "ready" and d ~= "failed" then
      if not waiting then log("outfit " .. name(sk) .. ": waiting for sbslice.dll to fix its physics"); waiting = true end
      seenMesh, M.seen[addr] = nil, nil
      return
    end
    fixed[paddr] = true
    what = what .. "; " .. fix_defaults(pa, mesh, sk)
    -- (the ends' turn damping again: fix_defaults set every main body's to angularDamping)
    if steadied[paddr] then steady(pa) end
  elseif weld == "" then
    -- fixed already: the game made this outfit's bodies from the fixed asset. Re-made on every outfit change, a mod
    -- swapping her meshes back and forth re-made them each time (reported: 1-2 fps)
    log(what .. note .. ", fixed before")
    return
  end
  if not live then
    local ok = try(function() mesh:SetPhysicsAsset(pa, true); return true end)
    what = what .. (ok and ", bodies re-made" or ", bodies NOT re-made")
  end
  log(what .. note)
end

-- main.lua's selfCollision "auto" goes by the damping too: an asset fixed here without sbslice.dll's collision table
-- still has vanilla's collision pairs
function M.runtime_fixed(pa)
  local a = valid(pa) and try(function() return pa:GetAddress() end)
  return a and fixed[a] == true and not filledTable[a] or false
end

-- the bodies no joint holds, outside the main skeleton (twist and helper bones carrying a cape or skirt chain), each
-- with the nearest bone above it that has a body: { { body, above }, ... } (outfits.py's orphan_joints picks the same)
function M.loose_bodies(pa, mesh)
  local has, held, out = {}, {}, {}
  for _, bs in ipairs(bodies_of(pa)) do has[try(function() return bs.BoneName:ToString() end) or ""] = true end
  for _, t in ipairs(constraints_of(pa)) do
    held[try(function() return t.DefaultInstance.ConstraintBone1:ToString() end) or ""] = true
  end
  for b in pairs(has) do
    if b ~= "" and not MAIN[b] and not held[b] then
      local up = try(function() return mesh:GetParentBone(FName(b)):ToString() end)
      while up and up ~= "None" and not has[up] do up = try(function() return mesh:GetParentBone(FName(up)):ToString() end) end
      if up and up ~= "None" then out[#out + 1] = { b, up } end
    end
  end
  table.sort(out, function(x, y) return x[1] < y[1] end)
  return out
end

-- ragdoll start: lock the loose bodies of an unpatched asset to the body above them
function M.start(pawn, mesh)
  M.check(pawn, mesh, true)
  if cfg().enabled == false or cfg().lockLoose == false or not state or state.patched or not valid(state.pa) then return "" end
  local cls = try(function() return StaticFindObject("/Script/Engine.PhysicsConstraintComponent") end)
  if not valid(cls) then return "no PhysicsConstraintComponent class" end
  local done = {}
  for _, l in ipairs(M.loose_bodies(state.pa, mesh)) do
    local b, up = l[1], l[2]
    local at = try(function() return mesh:GetSocketLocation(FName(b)) end)
    local pc = at and try(function()
      return pawn:AddComponentByClass(cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
        Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
    end)
    if valid(pc) then
      locks[#locks + 1] = pc
      try(function() pc:K2_SetWorldLocation(at, false, {}, true) end)
      try(function() pc:SetLinearXLimit(LCM_LOCKED, 0) end)
      try(function() pc:SetLinearYLimit(LCM_LOCKED, 0) end)
      try(function() pc:SetLinearZLimit(LCM_LOCKED, 0) end)
      try(function() pc:SetAngularSwing1Limit(ACM_LOCKED, 0) end)
      try(function() pc:SetAngularSwing2Limit(ACM_LOCKED, 0) end)
      try(function() pc:SetAngularTwistLimit(ACM_LOCKED, 0) end)
      if try(function() pc:SetConstrainedComponents(mesh, FName(up), mesh, FName(b)); return true end) then
        done[#done + 1] = b .. ">" .. up
      end
    end
  end
  local s = #done > 0 and ("loose bodies locked: " .. table.concat(done, ", ")) or "no loose bodies"
  log(s)
  return s
end

-- her arms against her body and each other, and her legs against each other: the collision table (sbslice.dll's "t") leaves these pairs out, so
-- they collide while every other pair of hers doesn't. A pair whose bodies are within armGap cm of each other as she
-- goes limp is left out: bodies that start overlapping fling apart. The gap is between the bodies' own shapes (their
-- capsules where she is then): measured between the bones with a 22 cm margin, the upper arms never collided with her
-- chest and the forearms mostly didn't, and her arms went through her body as before (playtest 43). Returns the pairs
-- (bone names) and what to log; none without the DLL's table. Each death writes the table again, for her pose then
local ARM_BONES = { "Bip001-L-UpperArm", "Bip001-L-Forearm", "Bip001-L-Hand", "Bip001-R-UpperArm", "Bip001-R-Forearm", "Bip001-R-Hand" }
local CHEST_BONES = { "Bip001-Pelvis", "Bip001-Spine", "Bip001-Spine1", "Bip001-Spine2" }
-- a bone's segment when its body's shapes can't be read: to the next bone down the chain (a hand: 8 cm on along the
-- forearm), as thick as her bodies are on the vanilla outfits
local SEG_TO = { ["Bip001-L-UpperArm"] = "Bip001-L-Forearm", ["Bip001-L-Forearm"] = "Bip001-L-Hand",
  ["Bip001-R-UpperArm"] = "Bip001-R-Forearm", ["Bip001-R-Forearm"] = "Bip001-R-Hand",
  ["Bip001-Pelvis"] = "Bip001-Spine", ["Bip001-Spine"] = "Bip001-Spine1",
  ["Bip001-Spine1"] = "Bip001-Spine2", ["Bip001-Spine2"] = "Bip001-Neck",
  ["Bip001-L-Thigh"] = "Bip001-L-Calf", ["Bip001-L-Calf"] = "Bip001-L-Foot", ["Bip001-L-Foot"] = "Bip001-L-Toe0",
  ["Bip001-R-Thigh"] = "Bip001-R-Calf", ["Bip001-R-Calf"] = "Bip001-R-Foot", ["Bip001-R-Foot"] = "Bip001-R-Toe0" }
local SEG_R = { UpperArm = 3, Forearm = 2.5, Hand = 2.5, Pelvis = 11, Spine = 7, Spine1 = 8, Spine2 = 8, Thigh = 7,
  Calf = 5.5, Foot = 4.5 }
local function seg_dist(p, q, r, s)
  local best
  for i = 0, 8 do
    local t = i / 8
    local a = { p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t, p[3] + (q[3] - p[3]) * t }
    for j = 0, 8 do
      local u = j / 8
      local b = { r[1] + (s[1] - r[1]) * u, r[2] + (s[2] - r[2]) * u, r[3] + (s[3] - r[3]) * u }
      local d = vsub(a, b)
      d = math.sqrt(dot(d, d))
      if not best or d < best then best = d end
    end
  end
  return best
end
-- FRotator::Quaternion
local function rotator_quat(r)
  local h = math.pi / 360
  local sp, cp = math.sin(r.Pitch * h), math.cos(r.Pitch * h)
  local sy, cy = math.sin(r.Yaw * h), math.cos(r.Yaw * h)
  local sr, cr = math.sin(r.Roll * h), math.cos(r.Roll * h)
  return { cr * sp * sy - sr * cp * cy, -cr * sp * cy - sr * cp * sy, cr * cp * sy - sr * sp * cy, cr * cp * cy + sr * sp * sy }
end
-- a body's shapes where its bone is now, as capsules { a, b, r } (a sphere: a == b; a box: its long axis)
local function body_capsules(mesh, bs, b)
  local x = try(function()
    local t = mesh:GetSocketTransform(FName(b), 0) -- RTS_World
    local q, p = t.Rotation, t.Translation
    return { q = { q.X, q.Y, q.Z, q.W }, t = { p.X, p.Y, p.Z }, s = t.Scale3D.X }
  end)
  if not x then return nil end
  local out = {}
  local function place(c, rot, half, r)
    local at = qrot(x.q, { c.X * x.s, c.Y * x.s, c.Z * x.s })
    at = { at[1] + x.t[1], at[2] + x.t[2], at[3] + x.t[3] }
    local ax = qrot(qmul(x.q, rot), half)
    out[#out + 1] = { vsub(at, ax), { at[1] + ax[1], at[2] + ax[2], at[3] + ax[3] }, r * x.s }
  end
  try(function()
    local g = bs.AggGeom
    g.SphylElems:ForEach(function(_, e)
      local el = e:get()
      place(el.Center, rotator_quat(el.Rotation), { 0, 0, el.Length / 2 * x.s }, el.Radius)
    end)
    g.SphereElems:ForEach(function(_, e)
      local el = e:get()
      place(el.Center, { 0, 0, 0, 1 }, { 0, 0, 0 }, el.Radius)
    end)
    g.BoxElems:ForEach(function(_, e)
      local el = e:get()
      local ext = { el.X / 2, el.Y / 2, el.Z / 2 }
      local k = (ext[1] >= ext[2] and ext[1] >= ext[3]) and 1 or (ext[2] >= ext[3] and 2 or 3)
      local sorted = { ext[1], ext[2], ext[3] }
      table.sort(sorted)
      local half = { 0, 0, 0 }
      half[k] = (ext[k] - sorted[2]) * x.s
      place(el.Center, rotator_quat(el.Rotation), half, sorted[2])
    end)
  end)
  return #out > 0 and out or nil
end
-- the collision table with every pair of hers apart but these (bone names): sbslice.dll's answer
function M.arm_table(pa, pairs)
  local idx, n = {}, 0
  for i, bs in ipairs(bodies_of(pa)) do idx[try(function() return bs.BoneName:ToString() end) or ""] = i - 1; n = i end
  local nums = {}
  for _, p in ipairs(pairs) do
    local i, j = idx[p[1]], idx[p[2]]
    if i and j then nums[#nums + 1] = string.format("%x,%x", math.min(i, j), math.max(i, j)) end
  end
  return ctx.gore.command(string.format("t%x,%x", pa:GetAddress(), n) .. (#nums > 0 and ("," .. table.concat(nums, ",")) or ""))
end
-- the pairs of cand (bone names) whose bodies are at least gap cm apart where she is now, and those nearer (to log)
local function measure(mesh, pa, cand, gap)
  local bodies = bodies_of(pa)
  local idx = {}
  for i, bs in ipairs(bodies) do idx[try(function() return bs.BoneName:ToString() end) or ""] = i - 1 end
  local function loc(b) local l = try(function() return mesh:GetSocketLocation(FName(b)) end); return l and { l.X, l.Y, l.Z } end
  local guessed = 0
  local caps = {}
  local function shapes(b)
    if caps[b] ~= nil then return caps[b] or nil end
    local c = idx[b] and body_capsules(mesh, bodies[idx[b] + 1], b)
    if not c then
      -- the bone's segment, as thick as SEG_R says
      local a = loc(b)
      local e = a and SEG_TO[b] and loc(SEG_TO[b])
      if a and not e then
        local fa = loc((b:gsub("Hand", "Forearm")))
        local d = fa and vsub(a, fa)
        local l = d and math.sqrt(dot(d, d))
        e = l and l > 1 and { a[1] + d[1] / l * 8, a[2] + d[2] / l * 8, a[3] + d[3] / l * 8 } or a
      end
      if a then c = { { a, e, SEG_R[b:gsub("Bip001%-", ""):gsub("^[LR]%-", "")] or 3 } }; guessed = guessed + 1 end
    end
    caps[b] = c or false
    return c
  end
  local pairs, near = {}, {}
  for _, c in ipairs(cand) do
    local i, j = idx[c[1]], idx[c[2]]
    local s1, s2 = i and shapes(c[1]), j and shapes(c[2])
    if s1 and s2 then
      local d
      for _, x in ipairs(s1) do
        for _, y in ipairs(s2) do
          local v = seg_dist(x[1], x[2], y[1], y[2]) - x[3] - y[3]
          if not d or v < d then d = v end
        end
      end
      if d >= gap then
        pairs[#pairs + 1] = c
      else
        near[#near + 1] = string.format("%s/%s %.0f", (c[1]:gsub("Bip001%-", "")), (c[2]:gsub("Bip001%-", "")), d)
      end
    end
  end
  return pairs, near, guessed
end
local function short(p) return (p[1]:gsub("Bip001%-", "")) .. "/" .. (p[2]:gsub("Bip001%-", "")) end
local function told(pairs, near, guessed, r)
  local names = {}
  for _, p in ipairs(pairs) do names[#names + 1] = short(p) end
  return string.format("%d pairs collide%s; %d touching, left out%s%s, %s", #pairs,
    #names > 0 and (": " .. table.concat(names, " ")) or "", #near, #near > 0 and (" (" .. table.concat(near, ", ") .. " cm)") or "",
    guessed > 0 and string.format("; %d bodies' shapes unread, guessed from the bones", guessed) or "", r)
end

function M.arm_collision(mesh, pa)
  local g = cfg()
  if g.enabled == false or g.collisionTable == false or not valid(pa) or dll() ~= "ready" then return {}, "no table" end
  local cand = {}
  if g.armCollision ~= false then
    for _, a in ipairs(ARM_BONES) do
      for _, c in ipairs(CHEST_BONES) do cand[#cand + 1] = { a, c } end
    end
    for _, a in ipairs({ "Bip001-L-UpperArm", "Bip001-L-Forearm", "Bip001-L-Hand" }) do
      for _, b in ipairs({ "Bip001-R-UpperArm", "Bip001-R-Forearm", "Bip001-R-Hand" }) do cand[#cand + 1] = { a, b } end
    end
    -- her forearms and hands against her thighs, and her legs against each other (the hips swing 15 deg in: the
    -- legs stop on each other instead of crossing)
    for _, a in ipairs({ "Bip001-L-Forearm", "Bip001-L-Hand", "Bip001-R-Forearm", "Bip001-R-Hand" }) do
      for _, b in ipairs({ "Bip001-L-Thigh", "Bip001-R-Thigh" }) do cand[#cand + 1] = { a, b } end
    end
    for _, a in ipairs({ "Bip001-L-Thigh", "Bip001-L-Calf", "Bip001-L-Foot" }) do
      for _, b in ipairs({ "Bip001-R-Thigh", "Bip001-R-Calf", "Bip001-R-Foot" }) do cand[#cand + 1] = { a, b } end
    end
  end
  local pairs, near, guessed = measure(mesh, pa, cand, g.armGap or 2)
  local r = M.arm_table(pa, pairs)
  if r:sub(1, 3) ~= "ok " then return {}, "table NOT written: " .. r end
  return pairs, told(pairs, near, guessed, r)
end

-- a cut-off piece (the main bodies at and below roots, bone names) against the rest of her main bodies: those pairs
-- collide too, on top of base (the pairs colliding so far), but the ones touching where she is cut (the piece's root
-- against the body it came off). Before, a cut arm or leg fell through her as if she weren't there. -> every pair
-- colliding now (nil if the table wasn't written) and what to log
function M.piece_collision(mesh, pa, roots, base)
  local g = cfg()
  if g.enabled == false or g.collisionTable == false or g.pieceCollision == false or not valid(pa) or dll() ~= "ready" then
    return nil, "no table"
  end
  local inside = {}
  local names = {}
  for _, bs in ipairs(bodies_of(pa)) do
    local b = try(function() return bs.BoneName:ToString() end)
    if b and MAIN[b] then
      names[#names + 1] = b
      for _, r in ipairs(roots) do
        if b == r or try(function() return mesh:BoneIsChildOf(FName(b), FName(r)) end) == true then inside[b] = true end
      end
    end
  end
  local have = {}
  for _, p in ipairs(base) do have[p[1] .. "|" .. p[2]] = true; have[p[2] .. "|" .. p[1]] = true end
  local cand = {}
  for _, a in ipairs(names) do
    if inside[a] then
      for _, b in ipairs(names) do
        if not inside[b] and not have[a .. "|" .. b] then cand[#cand + 1] = { a, b } end
      end
    end
  end
  local pairs, near, guessed = measure(mesh, pa, cand, g.armGap or 2)
  local all = {}
  for _, p in ipairs(base) do all[#all + 1] = p end
  for _, p in ipairs(pairs) do all[#all + 1] = p end
  local r = M.arm_table(pa, all)
  if r:sub(1, 3) ~= "ok " then return nil, "table NOT written: " .. r end
  return all, told(pairs, near, guessed, r)
end

M.seen = {} -- SkeletalMesh address -> { name, state }: meshes checked in this level

-- recovery: the locks go (the mesh's bodies are re-made by the game anyway)
function M.stop()
  for _, pc in ipairs(locks) do
    if valid(pc) then
      try(function() pc:BreakConstraint() end)
      try(function() pc:K2_DestroyComponent(pc) end)
    end
  end
  locks = {}
  -- the respawn may hand her the same mesh with bodies made from scratch: check again
  seenMesh = nil
end

-- a reloaded level: everything held is gone (the assets' changed defaults stay with them)
function M.forget()
  locks, seenMesh, state, M.seen = {}, nil, nil, {}
end

return M
