-- Manual slow motion (manual_slowmo.lua): off unless enabled, toggles on and off at the death slow
-- motion's speed, always runs down to full speed going off
local print = require("fake").say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local tune = { deathSlowmo = { enabled = true, speed = 0.15, duration = 5 }, manualSlowmo = { enabled = false } }
local logs = {}
local function log(s) logs[#logs + 1] = s end
local M = dofile("ue4ss/Mods/StellarBladeGore/Scripts/manual_slowmo.lua")(
  function() return tune end, log)
check(M.running() == false, "idle at first")
check(M.toggle() == nil, "off unless enabled")
check(M.running() == false, "toggling while off changes nothing")
tune.manualSlowmo.enabled = true
check(M.toggle() == 0.15, "on at the death slow motion's speed")
check(M.running() == true, "running while toggled on")
check(M.speed() == 0.15, "speed reported while on")
check(M.toggle() == 1, "off again to full speed")
check(M.running() == false, "idle after toggling off")
check(M.speed() == nil, "no speed reported while off")
-- on again, then a bad speed: off still takes, on refuses
check(M.toggle() == 0.15, "on again")
tune.deathSlowmo.speed = 2
check(M.toggle() == 1, "off even with a broken speed")
check(M.toggle() == nil and M.running() == false, "on refused with a broken speed")
tune.deathSlowmo.speed = 0.15
check(M.toggle() == 0.15, "on again once the speed is usable")
M.reset()
check(M.running() == false, "reset for a level reload")
print(fails == 0 and "PASS" or "FAIL")
