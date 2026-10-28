-- A limb cut off her alive goes onto a copy of her mesh once it lies still (main.lua hm.piece_watch, gore.hide_pieces
-- with bake): grabbing a ladder drew her mesh on her animation for a frame or two, and the cut-off arm was back on her
-- shoulder for those frames (Nexus report, 0.5.0). Its bones hidden on her, the copy shown; back on her mesh for her
-- death and for an undo (F8), with its bones shown again; a copy that fails leaves it on her mesh, tried once
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
local SET = "ue4ss/Mods/StellarBladeGore/Scripts/settings.lua"
local f = assert(io.open(SET, "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
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
local ARM = "Bip001-R-UpperArm"
local function cut()
  E.s.hp = 0.3
  F.run(0.5, pawn)
  F.press("F8", "ALT")
end

-- 1: her right arm cut off, lying still: onto a copy 1 s on, not before
local at = mark()
cut()
F.run(0.5, pawn)
check(F.find("her right arm cut off", at) ~= nil, "1: Alt+F8: her right arm cut off")
check(F.find("piece settled: 1 piece", at) == nil, "1: not on a copy while it may still move")
F.run(2.5, pawn)
check(F.find("piece settled: 1 piece%(s%) onto a copy", at) ~= nil, "1: onto a copy once it lay still")
check(E.hiddenBones[ARM] == true, "1: its bones hidden on her mesh")
local copy = E.added[#E.added]
check(copy ~= nil and not copy.hidden and not copy.__dead, "1: the copy shown")
check(copy ~= nil and copy.postAtMesh == true, "1: no post-process AnimBP made on the copy (off before its mesh went on)")
local n0 = #E.added
F.run(3, pawn)
check(#E.added == n0, "1: made once")

-- 2: her death: back on her mesh, its bones shown
at = mark()
E.s.hp = 0
E.die(true)
F.run(1, pawn)
check(F.find("back on her mesh.*her death", at) ~= nil, "2: back on her mesh at her death")
check(E.hiddenBones[ARM] == nil, "2: its bones shown on her again")
check(copy and copy.__dead, "2: the copy destroyed")
-- (sbslice told it is gone before it went, her sinks kept: "y" made it a co-owner of them)
local xs = copy and string.format("x%x,0,1", copy:GetAddress())
local told = false
for _, c in ipairs(F.cmds) do told = told or c.s == xs end
check(told, "2: the copy let go in sbslice (" .. tostring(xs) .. ")")
-- a death screen button pressed long before recoverAfter: she is got up at once, before the game's respawn (its
-- respawn set her meshes with her cut weights still on: the engine's FRenderResource crash, playtest)
F.run(2, pawn)
at = mark()
check(F.fire("/Game/Art/UI/Widget/HUD/WB_MainHUD_Dead.WB_MainHUD_Dead_C:FinishPressAnimation") > 0, "2: the death screen's press hooked")
F.run(0.2, pawn)
check(F.find("recovering after [%d.]+ s .*a death screen button", at) ~= nil, "2: a press 3 s in gets her up at once")
F.run(10, pawn)
E.respawn()
F.run(8, pawn)

-- 3: F8 (the cut undone) with the piece on its copy: back on her first, its bones shown
at = mark()
cut()
F.run(3, pawn)
check(F.find("piece settled: 1 piece%(s%) onto a copy", at) ~= nil, "3: onto a copy")
F.press("F8")
F.run(1, pawn)
check(E.hiddenBones[ARM] == nil, "3: F8: its bones shown on her again")
check(E.added[#E.added].__dead == true, "3: F8: the copy destroyed")
F.run(3, pawn)

-- 4: the copy's pose fails: the piece stays on her mesh, not hidden, and it isn't tried again
at = mark()
F.sbslice.P = function() return "err no pose" end
cut()
F.run(4, pawn)
check(F.find("no copy of her mesh for it, left on her mesh", at) ~= nil, "4: a failed copy leaves it on her mesh")
check(E.hiddenBones[ARM] == nil, "4: its bones not hidden")
local tries = 0
for i, x in ipairs(F.log_lines()) do if i >= at and x:find("left on her mesh") then tries = tries + 1 end end
check(tries == 1, string.format("4: tried once (%d)", tries))

if fails > 0 then dump(1, "piece") end
print(fails == 0 and "PASS" or "FAIL")
