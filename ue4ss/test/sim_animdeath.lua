-- Test: Animated Death (Alt+F6): the game's own death shows played on her, so a death animation mod's (death_anim_P)
-- replaced animations show in the mod's animated death. Each press the next show, the death starting with it, taken
-- as animated even with active.animated off, her own fall, no cut, and she lies till F8
local F = require("fake")
local E = require("eve")
local R = require("rag")
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.active = s.active or {}
s.active.animated = false
return s
]])
f:close()
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"
R.install(F, E)
F.world = R.step
-- (the game's death shows, in memory as they are once she has played)
for _, n in ipairs({ "P_Eve_Dead", "P_Eve_Dead2", "P_Eve_Dead3", "Eve_Dead_Down" }) do
  F.objects["/Game/Art/Show/CH_P_EVE_01/Basic/" .. n .. "." .. n] = F.obj(n, "SBShowData")
end
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
local function dump(from)
  for i, x in ipairs(F.log_lines()) do if i >= from then print("  | " .. x:sub(1, 200)) end end
end

-- 1: the show plays and her death starts with it: animated (active.animated off or not), her own fall, no cut, and
-- she lies 20 s on; F8 ends it (an animated death has no physics for F8 to turn off: it did nothing, playtest)
local at, shows = mark(), #E.shows
check(F.press("F6", "ALT"), "Alt+F6 bound")
F.run(0.5, pawn)
check(F.find("Test: Animated Death 1 of 4: her standing death %(P_Eve_Dead%)", at) ~= nil, "1: the first press: P_Eve_Dead")
check(#E.shows > shows and E.shows[#E.shows] == "P_Eve_Dead", "1: P_Eve_Dead played on her (" .. tostring(E.shows[#E.shows]) .. ")")
check(F.find("Test: Animated Death: her standing death %(P_Eve_Dead%): her death starts with it, no cut", at) ~= nil, "1: the death started with the show")
check(F.find("death: animated fall, physics off", at) ~= nil, "1: an animated death, active.animated off or not")
check(F.find("animated death: fall own", at) ~= nil, "1: her own fall: the show's animation, none of the knockdown falls")
F.run(20, pawn)
check(not F.find("gore: cut ", at) and not F.find("gore: split", at), "1: no cut")
check(not F.find("recovering after", at) and not F.find("recover %(", at), "1: she lies there 20 s on")
local r = mark()
F.press("F8", "")
F.run(1, pawn)
check(F.find("recover %(ragdoll ended%)", r) ~= nil, "1: F8 got her up")
if fails > 0 then dump(at) end
F.run(3, pawn)

-- 2: the next press, a death again (she was up)
at = mark()
F.press("F6", "ALT")
F.run(0.5, pawn)
check(F.find("Test: Animated Death 2 of 4: a hit's death %(P_Eve_Dead2%)", at) ~= nil, "2: the next press: P_Eve_Dead2")
check(F.find("her death starts with it", at) ~= nil and not F.find("already down", at), "2: its death started too")
F.press("F8", "")
F.run(1, pawn)
check(F.find("recover %(ragdoll ended%)", at) ~= nil, "2: F8 got her up")
if fails > 0 then dump(at) end

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
