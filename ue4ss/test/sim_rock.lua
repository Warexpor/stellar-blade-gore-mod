-- Actual rock and generic projectile callbacks, then main.lua's death selection on a moving ragdoll.
local T = require("smash_world").boot('s.gore.smash = { enabled = true }\ns.gore.blood = false\ns.gore.torsoLegs = { enabled = false }')
local F, E, G, pawn, v = T.F, T.E, T.G, T.pawn, T.v
local sw, hm = T.state.sw, T.state.hm
local print, fails = F.say, 0
local function check(c, label)
  print((c and "ok   " or "FAIL ") .. label)
  if not c then fails = fails + 1 end
end
local function fresh()
  for i = 1, 100 do
    local name = debug.getupvalue(sw.rock_event, i)
    if not name then break end
    if name == "pawnSeen" then debug.setupvalue(sw.rock_event, i, os.clock()); return end
  end
  error("pawnSeen not found")
end
local rock = F.obj("Rock", "M_GorillaB_S18_ThrowStone_Projectile1_C")
local head, leg = E.bone("Bip001-Head"), E.bone("Bip001-L-Thigh")
local function impact(at, reverse)
  sw.projectileLast, sw.rockLast, sw.projectileVolley = nil, nil, {}
  fresh()
  if reverse then sw.projectile_blueprint_event(F.param(rock), F.param(at), F.param(1)) end
  sw.rock_event(F.param(rock), F.param(at), F.param(1))
  if not reverse then sw.projectile_blueprint_event(F.param(rock), F.param(at), F.param(1)) end
end
impact(leg)
local hit = T.state.death_hit(pawn, E.mesh)
check(hit and hit.rock and hit.projectile, "known rock correction precedes generic projectile fallback")
check(hit and G.smash_part(E.mesh, hit.loc, nil, hit.pose) == "Bip001-Spine1",
  "low rock origin maps to upper body instead of the thigh")
check(hit and hit.volley == 1, "one rock stays one projectile in volley accounting")

local socket, transform = E.mesh.GetSocketLocation, E.mesh.GetSocketTransform
for _, reverse in ipairs({ false, true }) do
  impact(head, reverse)
  F.step(0.1)
  E.mesh.GetSocketLocation = function(self, bone)
    local p = socket(self, bone); return v(p.X, p.Y - 40, p.Z - 20)
  end
  E.mesh.GetSocketTransform = function(self, bone)
    local p = transform(self, bone)
    p.Translation = v(p.Translation.X, p.Translation.Y - 40, p.Translation.Z - 20)
    return p
  end
  hit = T.state.death_hit(pawn, E.mesh)
  check(hit and hit.rock and hit.pose and G.smash_part(E.mesh, hit.loc, nil, hit.pose) == "Bip001-Head",
    "captured head impact survives ragdoll motion; reversed callbacks=" .. tostring(reverse))
  E.mesh.GetSocketLocation, E.mesh.GetSocketTransform = socket, transform
end

impact(leg)
local bar, smash, observed = T.ctx.glass.bar_pct, G.smash, nil
T.ctx.glass.bar_pct = function() return 0 end
G.smash = function(_, _, h) observed = h; return false, "later" end
hm.lethal, hm.armed = nil, true
hm.lethal_watch(pawn, E.mesh)
check(observed and observed.rock and hm.lethal and hm.lethal.projectile == observed,
  "lethal HP watch keeps corrected rock for the deferred death")
G.smash = function(_, _, h) observed = h; return true end
observed = nil
T.state.gore_cut(pawn, E.mesh, nil, nil)
check(observed and observed.rock and G.smash_part(E.mesh, observed.loc, nil, observed.pose) == "Bip001-Spine1",
  "deferred death uses corrected upper-body hit")
G.smash, T.ctx.glass.bar_pct, hm.lethal = smash, bar, nil

for _, full in ipairs({ false, true }) do
  rock.PhysicsShapeComponent = F.obj("RockSphere", "SphereComponent", { GetScaledSphereRadius = function() return 100 end })
  impact(leg)
  hit = T.state.death_hit(pawn, E.mesh)
  T.ctx.tune.gore.smash.fullBody, T.ctx.tune.gore.smash.fullBodyChance = full, 1
  E.s.sim = true
  check(G.smash(pawn, E.mesh, hit, "death"), "real rock smash starts; full-body=" .. tostring(full))
  for _ = 1, 100 do F.step(1/60); G.tick(pawn); G.pump() end
  check(E.hiddenBones["Bip001-Spine1"] and (E.hiddenBones["Bip001-Pelvis"] == true) == full,
    "rock respects full-body option and preserves lower body when off")
  G.cleanup(pawn, E.mesh)
end
rock.PhysicsShapeComponent = nil

impact(leg)
fresh()
local other = F.obj("OtherRocket", "Enemy_Rocket_Projectile1_C")
sw.projectile_blueprint_event(F.param(other), F.param(leg), F.param(1))
hit = T.state.death_hit(pawn, E.mesh)
check(hit and hit.projectile and not hit.rock, "another projectile object is not relabelled as the nearby rock")
sw.rockLast = nil
sw.rock_event(F.param(rock), F.param(head), F.param(2))
check(sw.rockLast == nil, "missed rock callback does not capture an impact")
impact(leg)
F.step(0.7)
fresh()
sw.projectile_blueprint_event(F.param(other), F.param(leg), F.param(1))
hit = T.state.death_hit(pawn, E.mesh)
check(hit and hit.projectile and not hit.rock, "expired rock evidence cannot redirect a later projectile")
for _, err in ipairs(F.errors) do print("FAIL hook: " .. err); fails = fails + 1 end
print(fails == 0 and "PASS" or "FAIL")
