local T = require("smash_world").boot('s.gore.smash = { enabled = true }\ns.gore.blood = false\ns.gore.torsoLegs = { enabled = false }')
local F, E, G, pawn, v = T.F, T.E, T.G, T.pawn, T.v
local print, fails = F.say, 0
local function check(condition, what)
  print((condition and "ok   " or "FAIL ") .. what)
  if not condition then fails = fails + 1 end
end
local sw, hm = T.state.sw, T.state.hm
local spine = E.bone("Bip001-Spine2")
pawn.RagdollInfo = { ImpulseLimitVelocity = 700, ImpulseValue = v(30, 40, 50) }
check(sw.explosion_hit(pawn, E.mesh) == nil, "ordinary heavy death is not an explosion")
pawn.RagdollInfo.ImpulseLimitVelocity = 701
check(sw.explosion_hit(pawn, E.mesh) == nil and pawn.RagdollInfo.ImpulseLimitVelocity == 701,
  "animated-death marker is not consumed as an explosion")
pawn.RagdollInfo.ImpulseLimitVelocity = 702
local blast = sw.explosion_hit(pawn, E.mesh)
check(blast and blast.blast and not blast.projectile, "explosion death show identifies blast without projectile or hit broadcasts")
check(pawn.RagdollInfo.ImpulseLimitVelocity == 700, "explosion marker restores the original physical velocity limit")
check(blast and blast.loc.X == spine.X and blast.loc.Y == spine.Y and blast.loc.Z == spine.Z,
  "explosion smash aims at Eve's torso, not a distant detonation")
check(blast and blast.push.X == 30 and blast.push.Y == 40 and blast.push.Z == 50,
  "explosion preserves the game's impulse")
check(blast and sw.blunt_of(blast), "explosion evidence wins over nearby blade names")
check(sw.explosion_hit(pawn, E.mesh) == nil, "consumed marker cannot create another explosion")
local function fresh()
  for index = 1, 100 do
    local name = debug.getupvalue(sw.projectile_blueprint_event, index)
    if not name then break end
    if name == "pawnSeen" then debug.setupvalue(sw.projectile_blueprint_event, index, os.clock()); return end
  end
  error("missing pawnSeen")
end
for _, class in ipairs({ "P_Eve_Gun_ShootExplosiveSlug1_Projectile1_C", "Enemy_Rocket_Projectile1_C", "M_StatueC_Shot_Projectile1_C" }) do
  sw.projectileLast = nil
  fresh()
  sw.projectile_blueprint_event(F.param(F.obj("Projectile", class)), F.param(v(spine.X + 120, spine.Y, spine.Z)), F.param(1))
  check(sw.projectile_hit() == nil, class .. ": nearby detonation alone never invents a hit on Eve")
end
sw.projectileLast = nil
fresh()
sw.projectile_blueprint_event(F.param(F.obj("Friendly", "P_Eve_Gun_ShootExplosiveSlug1_Projectile1_C")), F.param(spine), F.param(1))
check(sw.projectile_hit() == nil, "Eve's own projectile cannot fabricate a self-hit even at contact distance")
local socketLocation = E.mesh.GetSocketLocation
E.mesh.GetSocketLocation = function(self, bone)
  if tostring(bone) == "Bip001-Spine2" then error("missing chest socket") end
  return socketLocation(self, bone)
end
pawn.RagdollInfo.ImpulseLimitVelocity = 702
local fallback = sw.explosion_hit(pawn, E.mesh)
check(fallback and fallback.blast and pawn.RagdollInfo.ImpulseLimitVelocity == 700,
  "missing chest socket retains explosion evidence through a pelvis fallback")
E.mesh.GetSocketLocation = socketLocation
local savedSmash, seen = G.smash, nil
G.smash = function(_, _, hit) seen = hit; return true end
hm.lethal = { t = F.t, cut = true, judged = true, roll = "blade", projectile = { projectile = true, loc = spine } }
hm.lethal.held = { loc = spine, dir = v(0, 1, 0), src = "earlier grab blade" }
hm.landAny, hm.fellAt = { t = F.t, drop = 1600 }, F.t
G.held = { function() error("stale blade follow-up executed") end }
G.held_sword = { mesh = E.mesh }
T.state.gore_cut(pawn, E.mesh, blast, nil)
check(seen == blast, "confirmed explosion replaces earlier blade, projectile and inferred landing judgements")
check(#G.held == 0 and G.held_sword == nil, "explosion cancels speculative blade follow-ups")
check(hm.lethal.held == nil, "explosion discards an earlier grab's deferred killing blow")
G.smash, hm.lethal, hm.landAny = savedSmash, nil, nil
E.s.sim = true
check(G.smash(pawn, E.mesh, blast, "death"), "confirmed explosion starts real smash stages")
for _ = 1, 60 do F.step(1/60); G.tick(pawn); G.pump() end
check(E.hiddenBones["Bip001-Spine1"] == true, "confirmed explosion removes upper torso instead of rolling a cut")
G.cleanup(pawn, E.mesh)
for _, err in ipairs(F.errors) do print("FAIL hook: " .. err); fails = fails + 1 end
print(fails == 0 and "PASS" or "FAIL")
