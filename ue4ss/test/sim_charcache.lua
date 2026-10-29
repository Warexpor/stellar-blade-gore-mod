-- The characters' places shared by the watches (main.lua goreCtx.char_at): her watches, the enemies' part and the poll
-- each read every character of the level again, on frames of their own (0.5.2 Nexus report of the frame rate down).
-- One far off (100 m) is read about once a second, not every time a watch asks; one near her whenever one asks; and
-- the far one, warped in next to her, is followed by the swing within that second. She stands at (1000, 2000)
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"

local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local BONES = { "Bip001", "Bip001-Pelvis", "Bip001-Spine1", "Bip001-R-Hand", "Weapon_R" }
local function enemy(name, at)
  local e = { at = at, reads = 0 }
  e.mesh = F.obj(name .. "_Mesh", "SkeletalMeshComponent", {
    SkeletalMesh = F.obj("SK_" .. name, "SkeletalMesh"),
    GetNumBones = function() return #BONES end,
    GetBoneName = function(_, i) return F.fname(BONES[i + 1] or "None") end,
    GetSocketLocation = function() return vec(e.at.X - 40, e.at.Y, e.at.Z + 30) end,
  })
  e.obj = F.obj(name, "CH_M_NA_14_Blueprint_C", {
    Mesh = e.mesh, bActorIsBeingDestroyed = false, bHidden = false,
    K2_GetActorLocation = function() e.reads = e.reads + 1; return vec(e.at.X, e.at.Y, e.at.Z) end,
    GetVelocity = function() return vec(0, 0, 0) end,
  })
  return e
end
local far = enemy("CH_M_NA_14_Blueprint_C_far", vec(11000, 2000, 90))
local near = enemy("CH_M_NA_14_Blueprint_C_near", vec(2500, 2000, 90))
F.classes.SBCharacter = { pawn, far.obj, near.obj }

local ok, err = pcall(dofile, DIR .. "main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function mark() return #F.log_lines() + 1 end

-- 3 s at 60 fps: 90 polls
far.reads, near.reads = 0, 0
F.run(3, pawn)
check(far.reads >= 2 and far.reads <= 5, "the one 100 m off read about once a second (" .. far.reads .. " reads in 3 s)")
check(near.reads >= 6 * far.reads and near.reads <= 100, "the one 15 m off read whenever a watch asks, at most once a poll (" .. near.reads .. " reads in 3 s, 90 polls)")

-- warped in next to her: followed by the swing within a second
local at = mark()
far.at = vec(1150, 2000, 90)
local t0 = F.t
local seen
for _ = 1, 90 do
  F.step(1 / 60, pawn)
  if not seen and F.find("swing: CH_M_NA_14_Blueprint_C holds", at) then seen = F.t - t0 end
end
check(seen ~= nil and seen <= 1.3, "the far one warped in: followed within a second (" .. tostring(seen and string.format("%.2f s", seen)) .. ")")

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
