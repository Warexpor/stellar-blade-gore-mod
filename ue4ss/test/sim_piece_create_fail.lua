-- A refused skeletal component must leave the limb on her mesh and not retry every second.
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
local f = assert(io.open("ue4ss/Mods/StellarBladeGore/Scripts/settings.lua", "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.gore.lowArm.enabled = true
s.gore.lowArm.settledCopy = true
return s
]])
f:close()
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"
local ok, err = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua")
if not ok then print("FAIL: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)
local attempts = 0
rawset(pawn, "AddComponentByClass", function() attempts = attempts + 1; return nil end)
local at = #F.log_lines() + 1
E.s.hp = 0.3
F.run(0.5, pawn)
F.press("F8", "ALT")
F.run(5, pawn)
local failed = F.find("no copy of her mesh for it, left on her mesh", at) ~= nil
local visible = E.hiddenBones["Bip001-R-UpperArm"] == nil
print((failed and "ok   " or "FAIL ") .. "copy failure recorded")
print((visible and "ok   " or "FAIL ") .. "limb remains visible on her mesh")
print((attempts == 1 and "ok   " or "FAIL ") .. "component creation attempted once: " .. attempts)
local once = attempts == 1
F.press("F8")
F.run(3, pawn)
E.s.hp = 0.3
F.press("F8", "ALT")
F.run(5, pawn)
local retried = attempts == 2
print((retried and "ok   " or "FAIL ") .. "a new cut may retry after the old one is undone: " .. attempts)
print(failed and visible and once and retried and "PASS" or "FAIL")
