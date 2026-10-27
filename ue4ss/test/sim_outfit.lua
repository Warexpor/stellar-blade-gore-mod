-- Outfits whose physics asset is missing main bodies, in the game as the playtest would check them (physfix.lua through
-- main.lua, test/sim_lemi.lua has physfix alone). Her bodies are made from the asset she reads at each re-make, and a
-- bone with no body in it doesn't simulate: a death on Lemi21's Latex Nun (no pelvis) ended its ragdoll on its first
-- poll and the cut was undone (Nexus report). Three runs:
--   1. no outfit system: the vanilla outfit, and one missing its thighs put on mid-game (given the complete asset at
--      once), each an F6 death that ragdolls and keeps its cuts
--   2. Lemi21 on as the level loads: the Latex Nun checked while loading is held off; given the complete asset once
--      it may; a death then ragdolls, a real one too
--   2b. a death 2 s after a reload, the complete asset preloaded (kept loaded by gore.lua) while nothing may load
--   3. Lemi21 switched to mid-game, then dropping the given asset every 2.5 s for 30 s as she runs: her bodies not
--      re-made meanwhile (she twitched), the asset put back on her at her death and the death ragdolls
local F = require("fake")
local E = require("eve")
local R = require("rag")
math.randomseed(5)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.deathMoves = false
return s
]])
f:close()
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function mark() return #F.log_lines() + 1 end
local function dump(from, pat)
  for i, x in ipairs(F.log_lines()) do
    local hit = not pat
    for _, p in ipairs(pat or {}) do hit = hit or x:find(p, 1, true) ~= nil end
    if i >= from and hit then print("  | " .. x:sub(1, 260)) end
  end
end

-- physics assets: a body per bone named (damping 0.2: the data mod's, read as patched; 5: vanilla's)
local function asset(name, bones, damping)
  local setups = {}
  for _, n in ipairs(bones) do
    setups[#setups + 1] = F.obj("BodySetup_" .. n, "SkeletalBodySetup", { BoneName = F.fname(n),
      DefaultInstance = { LinearDamping = damping, AngularDamping = 1.0 } })
  end
  local pa = F.obj(name, "PhysicsAsset", {
    SkeletalBodySetups = { ForEach = function(_, cb) for i, x in ipairs(setups) do cb(i, { get = function() return x end }) end end },
    ConstraintSetup = { ForEach = function() end },
  })
  pa.has = {}
  for _, n in ipairs(bones) do pa.has[n] = true end
  return pa
end
local ALL = { "Pelvis", "Spine", "Spine1", "Spine2", "Neck", "Head", "L-Clavicle", "R-Clavicle", "L-UpperArm", "R-UpperArm",
  "L-Forearm", "R-Forearm", "L-Hand", "R-Hand", "L-Thigh", "R-Thigh", "L-Calf", "R-Calf", "L-Foot", "R-Foot" }
local function bones(skip)
  local out = {}
  for _, b in ipairs(ALL) do if not (skip or {})[b] then out[#out + 1] = "Bip001-" .. b end end
  return out
end
local COMPLETE = "/Game/Art/Character/PC/CH_P_EVE_InnerSuit/CH_P_EVE_InnerSuit_Physics.CH_P_EVE_InnerSuit_Physics"
local innerSuit = asset("CH_P_EVE_InnerSuit_Physics", bones(), 0.2)
local vanillaPA = asset("CH_P_EVE_01_Physics", bones(), 0.2)
local noThighs = asset("CH_P_EVE_21_Physics", bones({ ["L-Thigh"] = true, ["R-Thigh"] = true }), 0.2)
local ltxNun = asset("LtxNun_Physics", bones({ Pelvis = true, Spine1 = true, ["L-Clavicle"] = true, ["R-Clavicle"] = true,
  ["L-Forearm"] = true, ["R-Forearm"] = true, ["L-Hand"] = true, ["R-Hand"] = true, ["L-Foot"] = true, ["R-Foot"] = true }), 5.0)
local function skm(name, pa) return F.obj(name, "SkeletalMesh", { PhysicsAsset = pa, LODInfo = { { bAllowCPUAccess = true } } }) end
local VANILLA = skm("SK_CH_P_EVE_01", vanillaPA)
local EVE21 = skm("SK_CH_P_EVE_21", noThighs)
local NUN = skm("MESH_LatexNun_Gold", ltxNun)

-- the complete asset: in memory only once loaded (a fresh game: not yet)
local loaded = false
StaticFindObject = function(p) if p == COMPLETE then return loaded and innerSuit or nil end return F.objects[p] end
LoadAsset = function(p) if p == COMPLETE then loaded = true; return innerSuit end return F.objects[p] end

-- her mesh component's physics: the override (SetPhysicsAsset) else the mesh asset's; her bodies made from what she
-- reads at each re-make, and only a bone with a body simulates. An outfit system's drop: the component reads none
local M = {}
local function dress(pawn)
  R.install(F, E)
  F.world = R.step
  local mesh = E.mesh
  M.mesh, M.override, M.dropped, M.remakes = mesh, nil, false, 0
  local isSim = mesh.IsSimulatingPhysics
  rawset(mesh, "GetPhysicsAsset", function()
    if M.dropped then return nil end
    return M.override or mesh.SkeletalMesh.PhysicsAsset
  end)
  rawset(mesh, "SetPhysicsAsset", function(self, pa)
    M.override, M.dropped = pa, false
    M.bodies, M.remakes = self:GetPhysicsAsset(), M.remakes + 1
  end)
  rawset(mesh, "IsSimulatingPhysics", function(self, b)
    local n = b and b:ToString() or "Bip001-Pelvis"
    if n ~= "None" and not (M.bodies and M.bodies.has[n]) then return false end
    return isSim(self, b)
  end)
  return pawn
end
-- an outfit put on her: the game's apply drops the override and re-makes her bodies from the new mesh's asset
local function wear(sk)
  rawset(M.mesh, "SkeletalMesh", sk)
  M.override, M.dropped = nil, false
  M.bodies = sk.PhysicsAsset
end

local pawn = dress(E.make(F))
wear(VANILLA)
local ok, err = pcall(dofile, DIR .. "main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)

-- an F6 death (its tests in turn: a cut each but the last): ragdolled 3 s on, the cut kept, on the asset named; F8 up again
local function f6_death(tag, physics)
  local at = mark()
  check(F.press("F6", ""), tag .. ": F6 bound")
  F.run(3, pawn)
  local l = F.find("=== ragdoll #%d+ start", at)
  check(l and l:find("physics=" .. physics, 1, true) ~= nil, tag .. ": ragdoll on " .. physics .. " (" .. tostring(l and l:match("physics=%S+")) .. ")")
  check(not F.find("=== ragdoll #%d+ end", at), tag .. ": the ragdoll still runs 3 s in")
  check(M.mesh:IsSimulatingPhysics(F.fname("Bip001-Pelvis")) == true, tag .. ": her pelvis simulates")
  check(F.find("gore: cut Bip001%-%S+ %(death%)", at) ~= nil and not F.find("undone", at), tag .. ": the cut made and kept")
  if fails > 0 then dump(at, { "ragdoll #", "physfix", "cut", "undone" }) end
  F.press("F8", "")
  F.run(4, pawn)
end

-- the complete asset loaded and kept while she plays (gore's preloads), with no outfit needing it yet
F.run(90, pawn)
check(loaded, "the complete asset preloaded while she plays")

-- 1. no outfit system
loaded = false
f6_death("vanilla", "CH_P_EVE_01_Physics")
local at = mark()
wear(EVE21)
F.run(1, pawn)
local l = F.find("outfit SK_CH_P_EVE_21, physics", at)
check(l and l:find("its own CH_P_EVE_21_Physics has no body on L%-Thigh,R%-Thigh: gave it") ~= nil, "a thighless outfit put on: given the complete asset at once")
f6_death("thighless", "CH_P_EVE_InnerSuit_Physics")
wear(VANILLA)
F.run(2, pawn)

-- 2. Lemi21 on as the level loads: a new Eve in the Latex Nun, the complete asset not in memory (the preloads not
-- that far yet)
loaded = false
local old = pawn
pawn = dress(E.make(F))
wear(NUN)
old.__dead = true
at = mark()
F.run(3, pawn)
check(F.find("new Eve .* the level reloaded", at) ~= nil, "level reload: the new Eve adopted")
check(not F.find("outfit MESH_LatexNun_Gold", at), "within 3 s (loading held off): no verdict on the Latex Nun yet")
F.run(4, pawn)
l = F.find("outfit MESH_LatexNun_Gold, physics", at)
check(l and l:find("its own LtxNun_Physics has no body on .*: gave it") ~= nil, "once it may load: given the complete asset (" .. tostring(l and l:sub(1, 160)) .. ")")
check(not F.find("didn't load", at), "never settled with 'didn't load'")
if fails > 0 then dump(at, { "physfix", "new Eve" }) end
F.run(5, pawn)
f6_death("Latex Nun from the load", "CH_P_EVE_InnerSuit_Physics")
-- a real death on it
at = mark()
E.die(true)
F.run(3, pawn)
l = F.find("=== ragdoll #%d+ start", at)
check(l and l:find("physics=CH_P_EVE_InnerSuit_Physics", 1, true) ~= nil, "a real death: ragdoll on the complete asset")
check(not F.find("=== ragdoll #%d+ end", at) and M.mesh:IsSimulatingPhysics(F.fname("Bip001-Pelvis")) == true, "a real death: still ragdolled 3 s in")
F.run(12, pawn)
E.respawn()
F.run(20, pawn)

-- 2b. a reload in the Latex Nun with the asset in memory (preloaded): a death 2 s in, while nothing may load
old = pawn
pawn = dress(E.make(F))
wear(skm("MESH_LatexNun_Gold", ltxNun))
old.__dead = true
F.run(2, pawn)
f6_death("Latex Nun, death 2 s after a reload", "CH_P_EVE_InnerSuit_Physics")

-- 3. Lemi21 switched to mid-game (its = menu) in a new game (the mesh asset as it loads: its own physics asset)
loaded = false
NUN = skm("MESH_LatexNun_Gold", ltxNun)
old = pawn
pawn = dress(E.make(F))
wear(VANILLA)
old.__dead = true
F.run(8, pawn)
at = mark()
wear(NUN)
F.run(1, pawn)
l = F.find("outfit MESH_LatexNun_Gold", at)
check(l and l:find("gave it") ~= nil, "switched to mid-game: given the complete asset")
local before = M.remakes
local t0 = F.t
local drops = 0
F.world = function(dt)
  R.step(dt)
  if F.t - t0 >= 2.5 * (drops + 1) then drops = drops + 1; M.dropped = true end
end
F.run(30, pawn)
F.world = R.step
check(drops >= 10, "the asset dropped " .. drops .. " times in 30 s")
check(M.remakes == before, "her bodies not re-made meanwhile (" .. (M.remakes - before) .. " re-makes)")
check(not F.find("lost the physics asset", at), "no 'lost the physics asset' lines")
-- her death with it dropped
local at2 = mark()
M.dropped = true
f6_death("Latex Nun dropped at her death", "CH_P_EVE_InnerSuit_Physics")
check(F.find("her physics asset was none at her death: gave her CH_P_EVE_InnerSuit_Physics", at2) ~= nil, "put back on her at her death, logged")

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
