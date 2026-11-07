-- A kind whose waist can't be cut (Marionette: its legs' skin follows the upper body, real-mesh ENEMY
-- waist harness FAILs). Kill flow (E.tick, rigged torso odds): a rolled torso becomes a limb, the blade attempt
-- carries the noTorso veto, the fallback tries limb then head, never the waist. Blade flow (G.blow, why="enemy"):
-- a waist plane with noTorso cuts no waist (a crossed limb instead, else nothing); without the flag the same plane
-- cuts the torso, and a limb plane with the flag still cuts the limb.
local F = require("fake")
local print = F.say
local fails = 0
local function check(c, what) print((c and "ok   " or "FAIL ") .. what); if not c then fails = fails + 1 end end
local function v(x, y, z) return { X = x, Y = y, Z = z } end
local try = function(f, ...) local o, r = pcall(f, ...); if o then return r end end
local valid = function(x) return x ~= nil and x ~= false end

-- ---- kill flow: rigged torso roll on a noTorso kind ----
local logs = {}
local tune = dofile("ue4ss/Mods/StellarBladeGore/Scripts/tune.lua")
tune.enemies.odds = { limb = 0, head = 0, torso = 100 }
local bp = {
  ["Bip001-Pelvis"] = v(500, 0, 100), ["Bip001-Spine"] = v(500, 0, 112), ["Bip001-Spine1"] = v(500, 0, 122),
  ["Bip001-Spine2"] = v(500, 0, 135), ["Bip001-Neck"] = v(500, 0, 148), ["Bip001-Head"] = v(500, 0, 160),
  ["Bip001-L-UpperArm"] = v(480, 0, 140), ["Bip001-L-Forearm"] = v(478, 0, 120), ["Bip001-L-Hand"] = v(478, 0, 105),
  ["Bip001-R-UpperArm"] = v(520, 0, 140), ["Bip001-R-Forearm"] = v(522, 0, 120), ["Bip001-R-Hand"] = v(522, 0, 105),
  ["Bip001-L-Thigh"] = v(490, 0, 90), ["Bip001-L-Calf"] = v(490, 0, 50), ["Bip001-L-Foot"] = v(490, 0, 10),
  ["Bip001-R-Thigh"] = v(510, 0, 90), ["Bip001-R-Calf"] = v(510, 0, 50), ["Bip001-R-Foot"] = v(510, 0, 10),
}
local mmesh = F.obj("MariMesh", "SkeletalMeshComponent", { SkeletalMesh = F.obj("CH_M_NA_26", "SkeletalMesh") })
mmesh.GetSocketLocation = function(_, b) return bp[tostring(b)] or v(500, 0, 100) end
mmesh.IsSimulatingPhysics = function() return true end
mmesh.IsVisible = function() return true end
mmesh.GetNumMaterials = function() return 0 end
local mobj = F.obj("CH_M_NA_26_Blueprint_C_1", "CH_M_NA_26_Blueprint_C",
  { Mesh = mmesh, bActorIsBeingDestroyed = false, bHidden = false })
mobj.K2_GetActorLocation = function() return v(300, 0, 100) end
mobj.K2_GetComponentsByClass = function() return {} end
local chars = { { obj = mobj, addr = mobj:GetAddress(), cls = "CH_M_NA_26_Blueprint_C", k = "k1" } }
local pawn = F.obj("Eve", "CH_P_EVE_01_Blueprint_C", {})
pawn.K2_GetActorLocation = function() return v(0, 0, 100) end
local herMesh = F.obj("EveMesh", "SkeletalMeshComponent")
herMesh.GetSocketLocation = function() return v(10, 0, 150) end
local calls = {}
local ctx = { tune = tune, try = try, valid = valid, log = function(s) logs[#logs + 1] = s end,
  live_chars = function() return chars end, keep = function(o) return { obj = o } end, held = function() return true end,
  newobj = { watch = function() end },
  gore = { busy = function() return false end,
    enemy_cut = function(owner, obj, mesh, h, kind, face)
      calls[#calls + 1] = { kind = kind, noTorso = h and h.noTorso == true, plane = h and (h.n or h.dir) ~= nil }
      return nil
    end,
    enemy_hit = function() end, enemy_cuts = function() return 0, false end } }
local E = dofile("ue4ss/Mods/StellarBladeGore/Scripts/enemies.lua")
E.init(ctx)
local rnd = math.random
math.random = function(a) if a then return 1 else return 0.99 end end
E.tick(pawn, herMesh)
E.tick(pawn, herMesh)
math.random = rnd
local kinds, torso = {}, false
for _, c in ipairs(calls) do kinds[#kinds + 1] = c.kind; if c.kind == "torso" then torso = true end end
check(#calls == 2 and kinds[1] == "limb" and kinds[2] == "head" and not torso,
  "rigged torso roll on a noTorso kind: limb then head tried, never the waist (" .. table.concat(kinds, ",") .. ")")
check(calls[1] and calls[1].noTorso and calls[1].plane, "the blade attempt carries the noTorso veto")
local gone = false
for _, l in ipairs(logs) do if l:find("nothing came off") then gone = true end end
check(gone, "nothing came off, logged")

-- ---- blade flow ----
local T = require("smash_world").boot('s.gore.bladeJitter = 0\ns.gore.multiCut = { enabled = false }')
local F2, E2, G2, pawn2, v2 = T.F, T.E, T.G, T.pawn, T.v
local function parts2() return G2.cut_parts(E2.mesh) end
E2.s.sim = true
local waist = E2.bone("Bip001-Spine1")
check(G2.blow(pawn2, E2.mesh, { loc = waist, n = v2(0, 0, 1) }, "enemy"), "waist plane on an enemy: accepted")
for _ = 1, 60 do F2.step(1/60); G2.tick(pawn2); G2.pump() end
check(#parts2() == 1 and parts2()[1] == "Bip001-Spine1", "without the flag: the waist cut lands")
G2.cleanup(pawn2, E2.mesh)
check(G2.cuts_on(E2.mesh) == 0, "recovery clears the control cut")
local okVeto = G2.blow(pawn2, E2.mesh, { loc = waist, n = v2(0, 0, 1), noTorso = true }, "enemy")
for _ = 1, 60 do F2.step(1/60); G2.tick(pawn2); G2.pump() end
local torso2 = false
for _, p in ipairs(parts2()) do if p == "Bip001-Spine1" then torso2 = true end end
check(not torso2, "waist plane with noTorso: no waist cut" .. (okVeto and " (a crossed limb instead)" or " (nothing)"))
check(F2.find("noTorso"), "the veto is logged")
G2.cleanup(pawn2, E2.mesh)
check(G2.cuts_on(E2.mesh) == 0, "recovery clears after the veto")
local arm = E2.bone("Bip001-L-UpperArm")
check(G2.blow(pawn2, E2.mesh, { loc = arm, n = v2(0, 1, 0), bone = "Bip001-L-UpperArm", noTorso = true }, "enemy"), "limb plane with noTorso: accepted")
for _ = 1, 60 do F2.step(1/60); G2.tick(pawn2); G2.pump() end
local limbs, torso3 = 0, false
for _, p in ipairs(parts2()) do if p == "Bip001-Spine1" then torso3 = true elseif p:find("UpperArm") or p:find("Forearm") then limbs = limbs + 1 end end
check(limbs >= 1 and not torso3, "limb plane with noTorso: a limb cut lands, still no waist")
G2.cleanup(pawn2, E2.mesh)
check(G2.cuts_on(E2.mesh) == 0, "recovery clears after the limb cut")
check(#F2.errors == 0 and not F2.find("tick error"), "no errors")
print(fails == 0 and "PASS" or "FAIL")
