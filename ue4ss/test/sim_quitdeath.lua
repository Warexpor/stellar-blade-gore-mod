-- Quit to the title from the death screen (Nexus report, two crashes: the game closed a second after the lobby came
-- up, both times after a ragdoll death with cuts). Her right arm comes off alive (Lose Arm at Low HP, Alt+F8), her
-- death cuts her across the waist, a ragdoll: the struggle, the convulse, floor blood, the revive screen. Then the
-- level goes: every object of the old one freed (her pawn, meshes, caps, decals, effects, copies, the death screen),
-- a new Eve in the lobby. Nothing of the mod may ask a freed object anything (UE4SS's IsValid reads it: a crash)
local F = require("fake")
local E = require("eve")
local R = require("rag")
math.randomseed(7)
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.deathMoves = true
s.gore.lowArm.enabled = true
s.gore.death = { limb = 0, head = 0, torso = 100, split = 0, moreLimbs = 0 }
return s
]])
f:close()
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"
R.install(F, E)
F.world = R.step
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

local cases = { { name = "on the revive screen", s = 14 }, { name = "early in the death", s = 1.5 },
  { name = "mid struggle", s = 5 }, { name = "after the revive screen's intro", s = 19 }, { name = "at the cut", s = 0.2 } }
local CASE = cases[tonumber(rawget(_G, "QUIT_CASE") or 1)]
local d0 = mark()
E.s.hp = 0
E.die(true)
F.run(CASE.s, pawn)
check(F.find("Spine1.* off %(death%)", d0) ~= nil or F.find("cut Bip001%-Spine1", d0) ~= nil, "her death cut her across the waist")

-- the level goes: everything of the old one freed, a new Eve in the lobby (the old one never ticks again)
local e0 = #F.errors
F.world = nil
local n = F.free_world()
print(string.format("  (quit to the title %s: %d objects freed)", CASE.name, n))
pawn = E.make(F)
local q0 = mark()
F.run(12, pawn)
check(F.find("new Eve .* the level reloaded", q0) ~= nil, "the new Eve adopted")
local freed = {}
for i = e0 + 1, #F.errors do freed[#freed + 1] = F.errors[i] end
for i, e in ipairs(freed) do if i <= 12 then print("  error: " .. e) end end
check(#freed == 0, string.format("nothing asked of the old level's freed objects (%d)", #freed))
local te = F.find("tick error", q0)
if te then print("tick error in the log: " .. te) end
check(not te, "no tick errors after the quit")
print(fails == 0 and "PASS" or "FAIL")
