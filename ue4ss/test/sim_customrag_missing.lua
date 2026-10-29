-- Customized Ragdoll support on with that mod not installed (playtest): the death screen kept as tune.deathScreen
-- says, not up at once see-through (it took the mouse, and the death camera only turned with a button held)
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.customizedRagdoll = true
return s
]])
f:close()
local ok, err = pcall(dofile, DIR .. "main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local at = #F.log_lines() + 1
E.die(true)
F.run(4, pawn)
check(F.find("didn't load: the mod isn't installed") ~= nil, "told the mod isn't installed")
check(F.find("see%-through %(Customized Ragdoll support%)", at) == nil, "the death screen not put up see-through")
local w = E.deadScreen.__w
check(w.vis == 1 or w.vis == 2, "the death screen kept hidden, as deathScreen says (" .. tostring(w.vis) .. ")")

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
