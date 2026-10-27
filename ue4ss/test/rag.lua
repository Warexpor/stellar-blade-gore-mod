-- A made-up ragdoll for the fake Eve (eve.lua): her bodies as a chain of joints that turn, lying on her back once
-- she simulates. Each body keeps an angular velocity (deg/s, world); every frame its turn against its parent's body
-- turns everything below it about its joint (the pelvis's turns all of her), and turns die down with damping. No
-- gravity, floor or joint limits: enough for the scripts that steer her (struggle.lua, convulse.lua) to show whether
-- what they ask moves her the way they mean, and for active.lua's settling to see her speeds.
-- What the engine does to a body asleep is kept as the playtests saw it: turns set on it are read back, but it
-- doesn't move until woken
local R = {}

local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local function add(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
local function sub(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
local function scale(a, k) return vec(a.X * k, a.Y * k, a.Z * k) end
local function len(a) return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z) end
-- p turned about the axis w (rad, its length the angle) through o (Rodrigues)
local function turn(p, o, w)
  local th = len(w)
  if th < 1e-9 then return p end
  local k = scale(w, 1 / th)
  local v = sub(p, o)
  local c, s = math.cos(th), math.sin(th)
  local kv = vec(k.Y * v.Z - k.Z * v.Y, k.Z * v.X - k.X * v.Z, k.X * v.Y - k.Y * v.X)
  local kd = k.X * v.X + k.Y * v.Y + k.Z * v.Z
  return add(o, add(add(scale(v, c), scale(kv, s)), scale(k, kd * (1 - c))))
end
R.turn = turn

function R.install(F, E, opts)
  opts = opts or {}
  local s, mesh = E.s, E.mesh
  local damp = opts.damping or 1.0
  -- the bones with a body (everything but the root, the head's end and the fingers), parents first
  local BODY, ORDER = {}, {}
  for n in pairs(E.INDEX) do if n ~= "Bip001" and n ~= "Bip001-HeadNub" and not n:find("Finger", 1, true) then BODY[n] = true end end
  for i = 0, #E.BONE_OF do local n = E.BONE_OF[i]; if n then ORDER[#ORDER + 1] = n end end
  local function body_parent(n)
    local p = E.PARENT[n]
    while p and not BODY[p] do p = E.PARENT[p] end
    return p
  end
  local KIDS = {}
  for _, n in ipairs(ORDER) do
    local p = E.PARENT[n]
    if p then KIDS[p] = KIDS[p] or {}; table.insert(KIDS[p], n) end
  end
  local function below(n, out)
    out = out or {}
    for _, k in ipairs(KIDS[n] or {}) do out[#out + 1] = k; below(k, out) end
    return out
  end
  local BELOW = {}
  for _, n in ipairs(ORDER) do BELOW[n] = below(n) end
  R.BODY, R.ORDER, R.BELOW, R.body_parent = BODY, ORDER, BELOW, body_parent

  -- her pose lying on her back, head to +X, face up: standing (fwd x, left y, up z) -> (z, y, x); opts.faceDown:
  -- on her front, her left to -Y
  local P, W, V, prev, asleep = {}, {}, {}, {}, {}
  R.P, R.W, R.V, R.asleep = P, W, V, asleep
  local side = opts.faceDown and -1 or 1
  local function lay()
    for _, n in ipairs(ORDER) do
      local p = E.POS[n]
      P[n] = vec(1000 + p[3] - 95, 2000 + side * p[2], 12 + p[1])
      prev[n], W[n], V[n], asleep[n] = P[n], vec(0, 0, 0), vec(0, 0, 0), nil
    end
  end
  lay()
  R.lay = lay
  R.sets, R.zeroed, R.sleptSets, R.top = 0, 0, 0, {}
  local function live(n) return BODY[n] and (s.sim or s.simBelow[n]) end
  local function key(b) return b and b:ToString() or "None" end
  local real = { GetSocketLocation = mesh.GetSocketLocation }
  local function at(n)
    if s.sim then return P[n] or P["Bip001-Pelvis"] end
    return E.bone(n)
  end
  rawset(mesh, "GetSocketLocation", function(_, b) local p = at(key(b)); return vec(p.X, p.Y, p.Z) end)
  rawset(mesh, "GetBoneLocation", function(_, b) local p = at(key(b)); return vec(p.X, p.Y, p.Z) end)
  rawset(mesh, "GetCenterOfMass", function(_, b)
    local n = key(b)
    local k = (KIDS[n] or {})[1]
    local a, c = at(n), k and at(k)
    return c and scale(add(a, c), 0.5) or a
  end)
  rawset(mesh, "GetPhysicsAngularVelocityInDegrees", function(_, b) local w = W[key(b)] or vec(0, 0, 0); return vec(w.X, w.Y, w.Z) end)
  rawset(mesh, "GetPhysicsLinearVelocity", function(_, b) local v = V[key(b)] or vec(0, 0, 0); return vec(v.X, v.Y, v.Z) end)
  rawset(mesh, "SetPhysicsAngularVelocityInDegrees", function(_, w, plus, b)
    local n = key(b)
    if n == "None" then n = "Bip001-Pelvis" end
    if not live(n) then return end
    R.sets = R.sets + 1
    if asleep[n] then R.sleptSets = R.sleptSets + 1 end
    W[n] = plus and add(W[n], w) or vec(w.X, w.Y, w.Z)
    R.top[n] = math.max(R.top[n] or 0, len(W[n]))
  end)
  rawset(mesh, "SetAllPhysicsAngularVelocityInDegrees", function(_, w, plus)
    for n in pairs(BODY) do if live(n) then W[n] = plus and add(W[n], w) or vec(w.X, w.Y, w.Z) end end
    if not plus and len(w) == 0 then R.zeroed = R.zeroed + 1; F.event("her bodies' turns all zeroed") end
  end)
  -- (linear velocities: her joints keep her together, so what moves is the turns; a whole-body push goes nowhere.
  -- What is added to each body is summed in R.lin, for struggle.lua's drag along the floor)
  R.lin = {}
  rawset(mesh, "SetPhysicsLinearVelocity", function(_, v, plus, b)
    local n = key(b)
    if plus and live(n) then R.lin[n] = add(R.lin[n] or vec(0, 0, 0), v) end
  end)
  rawset(mesh, "SetAllPhysicsLinearVelocity", function() end)
  rawset(mesh, "WakeAllRigidBodies", function() for n in pairs(BODY) do asleep[n] = nil end end)
  rawset(mesh, "WakeRigidBody", function(_, b) asleep[key(b)] = nil end)
  rawset(mesh, "PutRigidBodyToSleep", function(_, b) local n = key(b); if BODY[n] then asleep[n] = true; W[n] = vec(0, 0, 0) end end)
  rawset(mesh, "PutAllRigidBodiesToSleep", function() for n in pairs(BODY) do asleep[n] = true; W[n] = vec(0, 0, 0) end end)
  rawset(mesh, "IsAnyRigidBodyAwake", function() for n in pairs(BODY) do if not asleep[n] then return true end end return false end)
  rawset(mesh, "GetBoneMass", function(_, b) return (opts.mass or {})[key(b)] or 2 end)
  -- her physics asset: a body per bone
  local setups = {}
  for _, n in ipairs(ORDER) do
    if BODY[n] then setups[#setups + 1] = F.obj("BodySetup_" .. n, "SkeletalBodySetup", { BoneName = F.fname(n), DefaultInstance = { LinearDamping = 0.2, AngularDamping = 1.0 } }) end
  end
  local pa = F.obj("CH_P_EVE_01_Physics", "PhysicsAsset", {
    SkeletalBodySetups = { ForEach = function(_, cb) for i, x in ipairs(setups) do cb(i, { get = function() return x end }) end end },
  })
  rawset(mesh, "GetPhysicsAsset", function() return pa end)
  rawset(mesh, "SkeletalMesh", F.obj("SK_CH_P_EVE_01", "SkeletalMesh", { PhysicsAsset = pa }))

  -- a frame: each body's turn against its parent's turns what is below it, parents first
  local wasSim = false
  function R.step(dt)
    if not s.sim then wasSim = false; return end
    if not wasSim then wasSim = true; lay() end
    for _, n in ipairs(ORDER) do prev[n] = P[n] end
    local k = math.exp(-damp * dt)
    for _, n in ipairs(ORDER) do
      if BODY[n] and not asleep[n] then
        local p = body_parent(n)
        local w = W[n]
        if p then w = sub(w, asleep[p] and vec(0, 0, 0) or W[p]) end
        local rad = scale(w, math.pi / 180 * dt)
        if len(rad) > 0 then
          for _, c in ipairs(BELOW[n]) do P[c] = turn(P[c], P[n], rad) end
        end
      end
    end
    for _, n in ipairs(ORDER) do
      V[n] = scale(sub(P[n], prev[n]), 1 / dt)
      if not asleep[n] then W[n] = scale(W[n], k) end
    end
  end
  return R
end

return R
