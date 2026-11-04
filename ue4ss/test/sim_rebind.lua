local F = require("fake")
local K = dofile("ue4ss/Mods/StellarBladeGore/Scripts/keys.lua")
local tune = { keys = {} }
K.init({ tune = tune, log = function() end })
K.register()
local calls = 0
K.on("menu", function() calls = calls + 1 end)
assert(F.press("F3", "")); K.flush(); assert(calls == 1)
tune.keys.menu = "Ctrl+Shift+Alt+F5"
assert(F.press("F3", "")); K.flush(); assert(calls == 1)
assert(F.press("F5", ""))
assert(F.press("F5", "CONTROL+SHIFT+ALT"))
K.flush(); assert(calls == 2)
F.say("PASS")
