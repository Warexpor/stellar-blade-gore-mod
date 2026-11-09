-- Out-of-map flight guards: a mid-cut socket glitch once read 93-210 m/s and the halves left the map.
-- Covers the animated-split velocity cap at the source, the absolute whole-body speed cap in the ragdoll tick,
-- and the map leash (sideways and up) that stops both halves and says so.
local T = require("smash_world").boot('s.gore.blood=false\ns.active.buzzLog=false\ns.active.settle={enabled=false}')
local F, E, ctx = T.F, T.E, T.ctx
local R = require("rag")
R.install(F, E)
local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local function len(v) return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
local fails = 0
local function check(c, s) F.say((c and "ok   " or "FAIL ") .. s); if not c then fails = fails + 1 end end
local rag = ctx.rag
rag.start(T.pawn, E.mesh, "quiet")
E.s.sim = true -- her bodies simulate (E.die would set this on a real death)
local function tick() rag.tick(1 / 30, function() end) end
for _ = 1, 20 do tick() end -- past the launch window, so only the absolute cap can bite
-- A uniform 200 m/s on the whole body defeats the torso-relative cap: the absolute one still holds.
R.V["Bip001-Pelvis"] = vec(20000, 0, 0)
R.V["Bip001-Spine1"] = vec(20000, 0, 0)
R.V["Bip001-R-Hand"] = vec(20000, 0, 0)
local vmax = ((ctx.tune.active or {}).spin or {}).linearMax or 6000
tick()
local held = true
for _, b in ipairs({ "Bip001-Pelvis", "Bip001-Spine1", "Bip001-R-Hand" }) do
  local l = len(E.mesh:GetPhysicsLinearVelocity(F.fname(b)))
  held = held and l <= vmax + 50 and l > 0
end
check(held, string.format("uniform 200 m/s flight is capped at the absolute ceiling (%d cm/s)", vmax))
check(F.find("absolute:") ~= nil, "the absolute cap logs its first bite")
-- Both caps apply in the same tick. The sky trim must use the already-capped velocity,
-- not restore the original horizontal speed after the absolute trim.
R.V["Bip001-Pelvis"] = vec(20000, 0, 10000)
R.V["Bip001-Spine1"] = vec(20000, 0, 10000)
R.V["Bip001-R-Hand"] = vec(20000, 0, 10000)
tick()
local mixed = E.mesh:GetPhysicsLinearVelocity(F.fname("Bip001-R-Hand"))
check(len(mixed) <= vmax + 1 and mixed.Z <= ctx.tune.active.spin.riseMax + 1,
  "combined absolute and rise trims preserve both limits")
ctx.tune.active.spin.linear = false
R.V["Bip001-R-Hand"] = vec(0, 0, 2000)
tick()
check(E.mesh:GetPhysicsLinearVelocity(F.fname("Bip001-R-Hand")).Z == 2000,
  "disabling linear speed trims also disables the rise trim")
ctx.tune.active.spin.linear = true
R.V["Bip001-R-Hand"] = vec(10, 0, 600)
tick()
check(E.mesh:GetPhysicsLinearVelocity(F.fname("Bip001-R-Hand")).Z <= ctx.tune.active.spin.riseMax + 1,
  "the rise limit also trims a non-projectile 600 cm/s upward limb")
ctx.tune.active.spin.riseMax = nil
R.V["Bip001-R-Hand"] = vec(10, 0, 600)
tick()
check(E.mesh:GetPhysicsLinearVelocity(F.fname("Bip001-R-Hand")).Z <= 501,
  "the missing rise setting falls back to the 500 cm/s default")
ctx.tune.active.spin.riseMax = 500
-- The source: one animated frame's per-bone speeds, capped at splitVelMax, never applied raw.
local function find(fn, wanted, seen)
  seen = seen or {}; if type(fn) ~= "function" or seen[fn] then return end; seen[fn] = true
  for i = 1, math.huge do
    local name, v = debug.getupvalue(fn, i); if not name then break end
    if name == wanted then return v end
    if name ~= "_ENV" and type(v) == "function" then
      local r = find(v, wanted, seen); if r then return r end
    end
  end
end
local split_vel = assert(find(T.G.pump_once, "split_vel"), "animated-split velocity helper reachable")
local cap = (ctx.tune.gore or {}).splitVelMax or 2000
local v, n = split_vel({ a = vec(0, 0, 0) }, { a = vec(3000, 0, 0) }, 1, cap)
check(n == 1 and math.abs(len(v.a) - cap) < 1e-6, "a 30 m/s sampling jump is capped at splitVelMax")
local v2, n2 = split_vel({ a = vec(0, 0, 0) }, { a = vec(50, 0, 0) }, 0.05, cap)
check(n2 == 0 and math.abs(len(v2.a) - 1000) < 1e-6, "an ordinary 10 m/s animated speed passes through")
local v3, n3 = split_vel(nil, { a = vec(50, 0, 0) }, 0.05, cap)
check(n3 == 0 and next(v3) == nil, "no first sample means no velocities")
-- The leash: 60 m sideways from where she went limp stops every body and says so.
local px = R.P["Bip001-Pelvis"]
R.P["Bip001-Pelvis"] = vec(px.X + 6000, px.Y, px.Z)
tick()
check(len(E.mesh:GetPhysicsLinearVelocity(F.fname("Bip001-Pelvis"))) < 50, "past the leash the pelvis is stopped")
check(F.find("out of the map: her pelvis") ~= nil, "the leash logs where it held her")
-- Straight up is held too (a split's copy took off upward, playtest); falling down stays free.
rag.stop(T.pawn)
R.lay()
R.V["Bip001-Pelvis"] = vec(0, 0, 0)
R.V["Bip001-Spine1"] = vec(0, 0, 0)
R.V["Bip001-R-Hand"] = vec(0, 0, 0)
rag.start(T.pawn, E.mesh, "quiet")
E.s.sim = true
for _ = 1, 20 do tick() end
local py = R.P["Bip001-Pelvis"]
R.P["Bip001-Pelvis"] = vec(py.X, py.Y, py.Z + 6000)
tick()
check(len(E.mesh:GetPhysicsLinearVelocity(F.fname("Bip001-Pelvis"))) < 50, "past the leash above she is stopped")
check(F.find("out of the map: her pelvis (%d+) cm above") ~= nil, "the leash logs a climb")
-- A split copy made before her ragdoll starts is parked, then tracked with her from the first tick.
do
  rag.stop(T.pawn)
  local copy = F.obj("SplitCopy", "SkeletalMeshComponent")
  T.ctx.rag.add_body(copy)
  rag.start(T.pawn, E.mesh, "quiet")
  E.s.sim = true
  for _ = 1, 3 do tick() end
  check(F.find("split: late copy tracked with her half") ~= nil, "a pre-ragdoll copy joins her")
  rag.stop(T.pawn)
end
-- An enormous engine impulse is capped at the source, before its delayed push tunnels a floor.
do
  rag.stop(T.pawn)
  R.lay()
  T.pawn.RagdollInfo = { ImpulseValue = { X = 5000, Y = 0, Z = 0 } }
  rag.start(T.pawn, E.mesh, "quiet")
  E.s.sim = true
  local iv = T.pawn.RagdollInfo.ImpulseValue
  local l = math.sqrt(iv.X * iv.X + iv.Y * iv.Y + iv.Z * iv.Z)
  check(l <= 701, string.format("a 50 m/s engine impulse is capped at the source (%.0f cm/s)", l))
  check(F.find("engine impulse .* capped to") ~= nil, "the source cap logs its bite")
  rag.stop(T.pawn)
  T.pawn.RagdollInfo = nil
end
-- Tunnelled through: no floor below near but one just above. She is lifted back above it.
-- (Before the no-floor test: the Kismet object is cached on first use, so the distinguishing mock must come first.)
do
  rag.stop(T.pawn)
  R.lay()
  for _, n in pairs(R.BODY) do R.V[n] = vec(0, 0, 0); R.W[n] = vec(0, 0, 0) end
  F.objects["/Script/Engine.Default__KismetSystemLibrary"] = F.obj("KSL2", "KismetSystemLibrary", {
    LineTraceSingle = function(_, _, from, to, _, _, _, _, hit)
      if to.Z > from.Z then hit.ImpactPoint = { X = from.X, Y = from.Y, Z = from.Z + 50 }; return true end
      return false
    end,
  })
  rawset(E.mesh, "K2_SetWorldLocationAndRotation", function() return true end)
  rawset(E.mesh, "K2_GetComponentRotation", function() return { Pitch = 0, Yaw = 0, Roll = 0 } end)
  T.ctx.tune.active.settle.enabled = false
  rag.start(T.pawn, E.mesh, "quiet")
  E.s.sim = true
  for _ = 1, 45 do tick() end
  check(F.find("through the floor") ~= nil, "a sunk pelvis is lifted back above the floor it fell through")
  rag.stop(T.pawn)
end
-- No floor under her at all is unknown, not grounded: she must not settle hung in mid-air.
do
  rag.stop(T.pawn)
  R.lay()
  for _, n in pairs(R.BODY) do R.V[n] = vec(0, 0, 0) end
  F.objects["/Script/Engine.Default__KismetSystemLibrary"] = F.obj("KSL", "KismetSystemLibrary", {
    LineTraceSingle = function() return false end,
  })
  T.ctx.tune.active.settle.enabled = true
  rag.start(T.pawn, E.mesh, "quiet")
  E.s.sim = true
  for _ = 1, 90 do tick() end
  check(F.find("no floor under her") ~= nil, "unknown floor keeps her awake instead of settling mid-air")
  rag.stop(T.pawn)
end
for _, e in ipairs(F.errors) do F.say("hook error: " .. e) end
check(#F.errors == 0, "no engine simulation errors")
F.say(fails == 0 and "PASS" or "FAIL")
