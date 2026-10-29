-- A level reload while her arm grows back at a camp rest (Nexus report, 0.5.2: the game crashed resting at a camp
-- with the left arm off). The regrow's matrices are written into her mesh asset, which the new Eve wears: they must be
-- put back as the old Eve is dropped (sbslice "Z"), and the arm, coming back, must not be carried into the new level
-- and cut again there over them
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.gore.lowArm.enabled = true
return s
]])
f:close()
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"
local ASSET = F.obj("SK_CH_P_EVE_01", "SkeletalMesh")
rawset(E.mesh, "SkeletalMesh", ASSET)
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

local at = mark()
E.s.hp = 0.3
F.run(0.5, pawn)
F.press("F8", "ALT")
F.run(3, pawn)
check(F.find("her right arm cut off", at) ~= nil, "Alt+F8: her right arm cut off")

-- the camp rest: she sits, the chair's sequence plays, 5 s on the arm starts dissolving back in
local seq = F.obj("Interaction_Camp_Chair", "LevelSequence", {
  GetFullName = function() return "LevelSequence /Game/Sequence/Interaction_Camp_Chair.Interaction_Camp_Chair" end,
})
local player = F.obj("SequencePlayer", "LevelSequencePlayer", {
  IsPlaying = function() return true end,
  GetSequence = function() return seq end,
})
F.classes.LevelSequenceActor = { F.obj("Interaction_Camp_Chair_Actor", "LevelSequenceActor", { SequencePlayer = player }) }
local rest = mark()
E.s.mode = 0
F.run(6, pawn)
check(F.find("dissolving back in over", rest) ~= nil, "the arm dissolving back in")

-- mid dissolve, the level reloads (the rest's zone reset): the old Eve freed, a new one wearing the same asset
local c0 = #F.cmds
local old = pawn
pawn = E.make(F)
rawset(E.mesh, "SkeletalMesh", ASSET)
old.__dead, old.__freed = true, true
F.classes.LevelSequenceActor = {}
E.s.mode = 1
local r0 = mark()
F.run(9, pawn)
E.s.hp = 0.3
F.run(3, pawn)
check(F.find("new Eve .* the level reloaded", r0) ~= nil, "the new Eve adopted")
local z = false
for i = c0 + 1, #F.cmds do if F.cmds[i].s == "Z" then z = true end end
check(z, "the regrow's matrices put back on her mesh asset (sbslice Z)")
check(F.find("level change with .* cut off her alive", r0) == nil, "the arm coming back isn't carried into the new level")
check(F.find("%(carried%)", r0) == nil, "nothing cut again on the new Eve")
for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
