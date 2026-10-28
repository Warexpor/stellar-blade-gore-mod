-- Lose Arm at Low HP's side (tune.gore.lowArm.side "hit", the default): a hit that leaves her under the mark takes
-- the arm on the side of her it landed on. The mesh's hit bone of one side decides; a hit on her middle bones goes by
-- where it landed off her spine; one on her spine or none seen, one at random
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
local SET = "ue4ss/Mods/StellarBladeGore/Scripts/settings.lua"
local f = assert(io.open(SET, "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.gore = s.gore or {}
s.gore.lowArm = s.gore.lowArm or {}
s.gore.lowArm.enabled = true
-- (her deaths cut a limb: case 9's death cut is redone on the new outfit, a waist cut or split is left as it is)
s.gore.death = { limb = 100, head = 0, torso = 0, split = 0, moreLimbs = 0 }
s.gore.bladeFollow = 0
return s
]])
f:close()
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"
local ok, err = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function mark() return #F.log_lines() + 1 end
local function dump(from, pat)
  for i, x in ipairs(F.log_lines()) do if i >= from and (not pat or x:find(pat)) then print("  | " .. x:sub(1, 240)) end end
end

local mesh = E.mesh
local n = 0
-- a hit on her mesh (the game's physical hit reaction: its force, where and on which bone), then her HP bar down
local function hit(bone, y, hp)
  n = n + 1
  if bone then
    local p = E.bone("Bip001-Spine1")
    rawset(mesh, "PhysicalHitForceVector", { X = -100 - n, Y = 0, Z = 0 })
    rawset(mesh, "PhysicalHitForceLocation", { X = p.X + 10, Y = p.Y + y, Z = p.Z })
    rawset(mesh, "PhysicalHitForceTargetBone", F.fname(bone))
    F.run(0.1, pawn)
  end
  E.s.hp = hp
  F.run(2, pawn)
end
-- her next life brings the arm back (the death's end undoes every cut)
local function back()
  E.s.hp = 0
  E.die(true)
  F.run(14, pawn)
  E.respawn()
  F.run(8, pawn)
end

-- 1: a hit on her left forearm: the left arm
local at = mark()
hit("Bip001-L-Forearm", 20, 0.2)
check(F.find("her left arm cut off", at) ~= nil, "1: a hit on her left forearm takes the left arm")
check(F.find("landed on Bip001%-L%-Forearm", at) ~= nil, "1: told by the hit bone")
-- (her body takes decals while she plays with the arm off: the floor blood's shield kept the Purification Scanner's
-- grid, a decal, off all of her but the face mesh, reported)
check(E.s.decalsOff and mesh.bReceivesDecals == true, "1: kept off decals as the cut bled, taking them again as she plays")
if fails > 0 then dump(at, "low HP") end
back()

-- 2: a hit on her chest 14 cm to her right (her right: -Y): the right arm
at = mark()
hit("Bip001-Spine2", -14, 0.2)
check(F.find("her right arm cut off", at) ~= nil, "2: a hit on her chest to her right takes the right arm")
check(F.find("landed 14 cm to her right", at) ~= nil, "2: told by where it landed")
if fails > 0 then dump(at, "low HP") end
back()

-- 3: no hit seen on her mesh (a ranged hit the reaction missed): one at random
at = mark()
hit(nil, 0, 0.2)
check(F.find("arm cut off", at) ~= nil, "3: no hit seen: an arm still comes off")
check(F.find("no side to the blow", at) ~= nil, "3: at random")
if fails > 0 then dump(at, "low HP") end
back()

-- 10: an arm off as the ponytail reset (her respawn's, 4 s on) comes: her mesh never goes query only (it stopped the
-- arm simulating: it went back onto her shoulder, playtest)
-- (her meshes found down her root's attach children, as the reset walks them)
local root = F.obj("Root10", "CapsuleComponent", { AttachChildren = { ForEach = function(_, fn) fn(1, { get = function() return mesh end }) end } })
rawset(pawn, "RootComponent", root)
local SMC = "/Script/Engine.SkeletalMeshComponent"
local smcPath, meshIsa = rawget(F.objects[SMC], "__path"), rawget(mesh, "__isa")
rawset(F.objects[SMC], "__path", SMC)
rawset(mesh, "__isa", { [SMC] = true })
E.respawn()
F.run(1, pawn)
at = mark()
E.collLog = {}
hit("Bip001-L-Forearm", 20, 0.2)
F.run(6, pawn)
check(F.find("her left arm cut off", at) ~= nil, "10: the arm off")
check(F.find("her ponytail reset %(NotifyBP_ReInitActor%): 1 mesh%(es%), 0 of them query only", at) ~= nil, "10: the ponytail reset ran after it, her mesh left out")
local q = false
for _, v in ipairs(E.collLog) do if v == 1 then q = true end end
check(not q and (E.coll or 3) == 3, "10: her mesh kept its collision with the arm off")
if fails > 0 then dump(at, "cloth") ; dump(at, "low HP") end
back()
rawset(pawn, "RootComponent", nil)
rawset(F.objects[SMC], "__path", smcPath)
rawset(mesh, "__isa", meshIsa)

-- No Sword Without It and the game's own swordless stance (Altess Levoire takes her sword the same way): its end never
-- lifts the game's (reported: the arm back or her death there gave her sword back)
local STANCE, LEVEL = "P_Eve_Idle", "E03_WasteLand_P"
local function ts(v) return { ToString = function() return v end } end
rawset(pawn, "GetCurrentStanceName", function() return ts(STANCE) end)
F.objects["/Script/Engine.Default__GameplayStatics"] = F.obj("Default__GameplayStatics", "GameplayStatics",
  { GetCurrentLevelName = function() return ts(LEVEL) end })

-- 4: the right arm off in the game's own block (Altess Levoire): left to the game, nothing lifted after
STANCE, LEVEL = "P_Eve_BlockSword", "AltesLab_P"
at = mark()
hit("Bip001-Spine2", -14, 0.2)
check(F.find("her right arm cut off", at) ~= nil, "4: the right arm")
check(F.find("no sword already %(the game's own block, AltesLab_P%): left to the game", at) ~= nil, "4: the game's block seen")
back()
check(F.find("the sword left to the game", at) ~= nil, "4: her death leaves the game's block on")
check(F.find("sword back", at) == nil, "4: no end fired")
if fails > 0 then dump(at, "low HP") end

-- 5: the right arm off outside, Altess Levoire gone into with it off: the end waits till she is out of it
STANCE, LEVEL = "P_Eve_Idle", "E03_WasteLand_P"
at = mark()
hit("Bip001-Spine2", -14, 0.2)
check(F.find("low HP arm: .*: no sword %(", at) ~= nil, "5: ours on")
STANCE, LEVEL = "P_Eve_BlockSword", "AltesLab_P"
F.run(1, pawn)
back()
check(F.find("in Altess Levoire with no sword", at) ~= nil, "5: the end waits in Altess Levoire")
check(F.find("sword back", at) == nil, "5: nothing lifted in it")
LEVEL = "E03_WasteLand_P"
F.run(2, pawn)
check(F.find("out of Altess Levoire %(E03_WasteLand_P%): sword back", at) ~= nil, "5: lifted as she leaves it")
if fails > 0 then dump(at, "low HP") end

-- 6: as 5, the game giving her sword back itself in Altess Levoire: nothing fired
STANCE, LEVEL = "P_Eve_Idle", "E03_WasteLand_P"
at = mark()
hit("Bip001-Spine2", -14, 0.2)
STANCE, LEVEL = "P_Eve_BlockSword", "AltesLab_P"
F.run(1, pawn)
back()
STANCE = "P_Eve_Idle"
F.run(2, pawn)
check(F.find("the game gave her sword back", at) ~= nil, "6: the game's own end seen")
check(F.find("sword back %(", at) == nil, "6: no end fired")
if fails > 0 then dump(at, "low HP") end

-- 6b: the right arm off in Altess Levoire before the game took her sword there (ours on), its block on since: the
-- end waits too (lifting ours lifted the game's, reported)
STANCE, LEVEL = "P_Eve_Idle", "AltesLab_P"
at = mark()
hit("Bip001-Spine2", -14, 0.2)
check(F.find("low HP arm: .*: no sword %(", at) ~= nil, "6b: ours on")
STANCE = "P_Eve_BlockSword"
F.run(1, pawn)
back()
check(F.find("in Altess Levoire with no sword", at) ~= nil, "6b: the end waits")
check(F.find("sword back %(", at) == nil, "6b: nothing lifted in it")
LEVEL = "E03_WasteLand_P"
F.run(2, pawn)
check(F.find("out of Altess Levoire %(E03_WasteLand_P%): sword back", at) ~= nil, "6b: lifted as she leaves it")
if fails > 0 then dump(at, "low HP") end

-- 7: the arm off, then a level gone into (Altess Levoire): the new level's HP bar reads full till the game sets it
-- after its cutscene; full to her low HP is no blow (reported: the arm came off again, sound and all)
STANCE, LEVEL = "P_Eve_Idle", "E03_WasteLand_P"
at = mark()
hit("Bip001-L-Forearm", 20, 0.2)
check(F.find("her left arm cut off", at) ~= nil, "7: the left arm")
local function count(pat)
  local n = 0
  for i, l in ipairs(F.log_lines()) do if i >= at and l:find(pat) then n = n + 1 end end
  return n
end
local cuts = count("arm cut off")
-- (the new level's Eve is whole: her cuts gone with the old one, as her next life brings them back here)
back()
E.hud.__dead = true
local newPct = 1.0
local bar2o = F.obj("ProgressBar_HP", "ProgressBar")
local bar2 = setmetatable({}, { __index = function(_, k) if k == "Percent" then return newPct end return bar2o[k] end })
local hud2 = F.obj("WB_MainHUD_PlayerInfo_C_1", "WB_MainHUD_PlayerInfo_C")
rawset(hud2, "ProgressBar_HP", bar2)
F.classes.WB_MainHUD_PlayerInfo_C = { hud2 }
F.run(70, pawn)
newPct = 0.2
F.run(3, pawn)
check(F.find("a new HP bar went from full to 0.200", at) ~= nil, "7: the new bar's setting seen")
check(count("arm cut off") == cuts, "7: no arm cut again")
if fails > 0 then dump(at, "HP") end

-- 8: the arm off, then an outfit put on her over it (Nexus 672, ESE: her shield broken, her suit gone to the inner
-- suit): the new asset is uncut and the arm was back on her (reported). Cut again on the new one, the arm still off
-- (the HP bar is case 7's new one now: newPct, not E.s.hp)
back()
newPct = 1.0
F.run(3, pawn)
rawset(mesh, "SkeletalMesh", F.obj("CH_P_EVE_09", "SkeletalMesh"))
at = mark()
-- (the hit within LOW_HIT_S of the bar's drop: older, the side is random)
F.run(2, pawn)
local p8 = E.bone("Bip001-Spine1")
rawset(mesh, "PhysicalHitForceVector", { X = -180, Y = 0, Z = 0 })
rawset(mesh, "PhysicalHitForceLocation", { X = p8.X + 10, Y = p8.Y + 20, Z = p8.Z })
rawset(mesh, "PhysicalHitForceTargetBone", F.fname("Bip001-L-Forearm"))
F.run(0.1, pawn)
newPct = 0.2
F.run(2, pawn)
check(F.find("her left arm cut off", at) ~= nil, "8: the left arm")
local at8 = mark()
rawset(mesh, "SkeletalMesh", F.obj("CH_P_EVE_InnerSuit", "SkeletalMesh"))
F.run(3, pawn)
check(F.find("outfit changed over her cuts %(Bip001%-L%-UpperArm%)", at8) ~= nil, "8: the new outfit seen under the cut")
check(F.find("cut Bip001%-L%-UpperArm %(outfit changed%)", at8) ~= nil, "8: the arm cut again on it")
check(F.find("the arm came back", at8) == nil and F.find("sword back", at8) == nil, "8: the arm still off for the game")
F.run(3, pawn)
check(count("outfit changed over her cuts") == 1, "8: cut again once")
if fails > 0 then dump(at, "cut") end

-- 9: ESE's Destroyed: the suit used up as she dies, the inner suit put on her dead body over the death's cut. Cut
-- again as a cut after her death: no undo (it would stop her ragdoll)
back()
rawset(mesh, "SkeletalMesh", F.obj("CH_P_EVE_09_V02", "SkeletalMesh"))
at = mark()
E.s.hp = 0
E.die(true)
F.run(4, pawn)
local deathCut = F.find("cut Bip001%-%S+ %(death%)", at)
check(deathCut ~= nil, "9: cut at her death")
local at9 = mark()
rawset(mesh, "SkeletalMesh", F.obj("CH_P_EVE_InnerSuit_2", "SkeletalMesh"))
F.run(3, pawn)
-- (a waist cut is left as it is: its split's copy holds the other half)
local waist = F.find("cut Bip001%-Spine1 %(death%)", at) ~= nil
if waist then
  check(F.find("over her waist cut", at9) ~= nil, "9: the waist cut left as it is")
  check(F.find("cut Bip001%-Spine1 %(after%)", at9) == nil, "9: no second split")
else
  check(F.find("cut again on the new one %(dead", at9) ~= nil, "9: the new outfit seen under the death's cut")
  check(F.find("cut Bip001%-%S+ %(after%)", at9) ~= nil, "9: cut again after her death")
end
check(F.find("undid cut", at9) == nil, "9: nothing undone")
if fails > 0 then dump(at, "cut") end
F.run(10, pawn)
E.respawn()
F.run(8, pawn)

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
