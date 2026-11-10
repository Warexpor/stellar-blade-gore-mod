-- Low-HP arms skip the suspected settled-copy crash path by default.
local F, E = require("fake"), require("eve")
local pawn = E.make(F)
local f = assert(io.open("ue4ss/Mods/StellarBladeGore/Scripts/settings.lua", "w"))
f:write('local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")\ns.dev = true\ns.gore.lowArm.enabled = true\nreturn s\n'); f:close()
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"
assert(pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua"))
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil)); F.run(16, pawn)
local at = #F.log_lines() + 1
E.s.hp = 0.3; F.run(0.5, pawn); F.press("F8", "ALT"); F.run(5, pawn)
local ok = F.find("her right arm cut off", at) ~= nil
  and F.find("piece settled: 1 piece%(s%) onto a copy", at) == nil
  and E.hiddenBones["Bip001-R-UpperArm"] == nil
F.say((ok and "ok   " or "FAIL ") .. "low-HP arm is cut but no settled copy is made by default")
F.say(ok and "PASS" or "FAIL")
