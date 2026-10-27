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

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
