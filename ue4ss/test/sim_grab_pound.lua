-- A blunt pound in an enemy's grab while she lives smashes one limb, never the head or body.
local T = require("smash_world").boot('s.gore.smash = { enabled = true }\ns.gore.blood = false\ns.gore.torsoLegs = { enabled = false }')
T.ctx.tune.gore.smash.grabPounds = true
local F, E, G, pawn, v = T.F, T.E, T.G, T.pawn, T.v
local print, fails = F.say, 0
local function run(seconds)
  for _ = 1, math.floor(seconds * 60 + 0.5) do F.step(1/60); G.tick(pawn); G.pump() end
end
local function check(c, what) print((c and "ok   " or "FAIL ") .. what); if not c then fails = fails + 1 end end
-- Exercise the production watcher, including lethal-hit ordering and the hit's bone provenance.
local hm, sw = T.state.hm, T.state.sw
local meshHitIndex
for i = 1, math.huge do
  local name = debug.getupvalue(hm.grab_pound, i)
  if not name then break end
  if name == "meshHit" then meshHitIndex = i; break end
end
check(meshHitIndex ~= nil, "watcher has mesh-hit evidence")
local originalEnemies, originalBusy, originalSmash, originalBlunt = T.ctx.enemies, G.busy, G.smash, sw.blunt_of
local attempts, seenHit = 0, nil
local watches = 0
T.ctx.enemies = { grab_now = function() return { cls = "CH_M_NA_15_Blueprint_C" } end,
  grab_tick = function() watches = watches + 1 end }
local oldWoundAtHit, oldGlass = T.ctx.tune.gore.woundAtHit, T.ctx.glass
T.ctx.tune.gore.woundAtHit = false
hm.lethal_watch(pawn, E.mesh)
check(watches == 1, "grab tracking runs with the lethal-hit watcher disabled")
T.ctx.tune.gore.woundAtHit, T.ctx.glass = oldWoundAtHit, nil
hm.lethal_watch(pawn, E.mesh)
check(watches == 2, "grab tracking runs without the HP-bar watcher")
T.ctx.glass = oldGlass
G.busy = function() return false end
G.smash = function() attempts = attempts + 1; return true end
sw.blunt_of = function(h) seenHit = h; return true end
F.step(0.1)
debug.setupvalue(hm.grab_pound, meshHitIndex, { t = os.clock(), loc = v(0, 0, 0), bone = "Bip001-L-Hand" })
hm.lethal = { t = os.clock(), wasGrab = true }
hm.grab_pound(pawn, E.mesh)
check(attempts == 0, "lethal hit is not processed again as a living pound")
hm.lethal = nil
hm.grab_pound(pawn, E.mesh)
check(attempts == 1 and seenHit and seenHit.wbone == nil, "living hit processed without treating her hit bone as the attacker's weapon")
hm.grab_pound(pawn, E.mesh)
check(attempts == 1, "one mesh hit is processed only once")
T.ctx.enemies, G.busy, G.smash, sw.blunt_of = originalEnemies, originalBusy, originalSmash, originalBlunt
local LIMBS = { "Bip001-L-UpperArm", "Bip001-R-UpperArm", "Bip001-L-Forearm", "Bip001-R-Forearm",
  "Bip001-L-Thigh", "Bip001-R-Thigh", "Bip001-L-Calf", "Bip001-R-Calf" }
local function cut_limbs()
  local out = {}
  for _, b in ipairs(LIMBS) do if G.has_cut(E.mesh, b) then out[#out + 1] = b end end
  return out
end
math.randomseed(20261108)
-- a pound at the head still takes a limb: the head and body need her ragdoll
local head = E.bone("Bip001-HeadNub")
G.aim(v(0, 0, -1))
check(G.smash(pawn, E.mesh, { loc = head, grabPound = true }, "grab"), "grab pound at the head starts")
run(0.6)
check(not G.has_cut(E.mesh, "Bip001-Head"), "head survives a grab pound")
check(not G.has_cut(E.mesh, "Bip001-Spine1"), "torso survives a grab pound")
local first = cut_limbs()
check(#first >= 1 and #first <= 2, "one limb smashed (" .. table.concat(first, ", ") .. ")")
check(G.cuts_on(E.mesh) == 1, "first pound creates exactly one smash record")
-- a pound at the chest still takes a limb, and the next pound takes another one
local chest = E.bone("Bip001-Spine2")
G.aim(v(0, 0, -1))
check(G.smash(pawn, E.mesh, { loc = chest, grabPound = true }, "grab"), "second grab pound starts")
run(0.6)
check(not G.has_cut(E.mesh, "Bip001-Head"), "head still survives the second pound")
check(not G.has_cut(E.mesh, "Bip001-Spine1"), "torso still survives the second pound")
local second = cut_limbs()
check(#second > #first and #second <= #first + 2, "another limb smashed on the next pound (" .. table.concat(second, ", ") .. ")")
check(G.cuts_on(E.mesh) == 2, "second pound adds exactly one smash record")
-- Even with an impact footprint, a living pound cannot roll a full-body smash.
G.cleanup(pawn, E.mesh)
T.ctx.tune.gore.smash.fullBodyChance = 1
G.aim(v(0, 0, -1))
check(G.smash(pawn, E.mesh, { loc = chest, impactRadius = 200, grabPound = true }, "grab"), "large grab pound starts")
run(0.6)
check(not G.has_cut(E.mesh, "Bip001-Spine1") and not G.has_cut(E.mesh, "Bip001-Pelvis"),
  "large grab pound never rolls a full-body smash")
-- Nor can the lower-body remainder path turn a pound into a full smash after an earlier waist cut.
G.cleanup(pawn, E.mesh)
check(G.slice_bone(pawn, E.mesh, "Bip001-Spine1", nil, "test"), "earlier waist cut starts")
run(0.6)
local leg = E.bone("Bip001-L-Thigh")
G.aim(v(0, 0, -1))
check(G.smash(pawn, E.mesh, { loc = leg, grabPound = true }, "grab"), "grab pound after a waist cut starts")
run(0.6)
check(not G.has_cut(E.mesh, "Bip001-Pelvis"), "grab pound does not explode the lower-body remainder")
check(#F.errors == 0, "no errors (" .. table.concat(F.errors, "; ") .. ")")
print(fails == 0 and "PASS" or "FAIL")
