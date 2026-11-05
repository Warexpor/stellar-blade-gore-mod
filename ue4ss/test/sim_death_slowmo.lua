-- Slow-motion death effect (death_slowmo.lua): off unless enabled, runs its window,
-- hands time back, and refuses bad speeds and durations
local print = require("fake").say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local now = 1000
local tune = { deathSlowmo = { enabled = false, speed = 0.3, duration = 2.5 } }
local logs = {}
local function log(s) logs[#logs + 1] = s end
local M = dofile("ue4ss/Mods/StellarBladeGore/Scripts/death_slowmo.lua")(
  function() return tune end, function() return now end, log)
check(M.running() == false, "idle at first")
check(M.start() == nil, "off unless enabled")
check(M.running() == false, "nothing running while off")
tune.deathSlowmo.enabled = true
check(M.start() == 0.3, "starts at the tuned speed")
check(M.running() == true, "running in its window")
check(M.done() == false, "not done at once")
now = now + 2.5
check(M.done() == true, "done after its duration")
local speeds = {}
check(M.stop("its time is up", function() speeds[#speeds + 1] = 1 end) == true, "stop hands time back")
check(speeds[1] == 1, "full speed restored")
check(M.running() == false, "idle after its window")
check(M.stop("again") == false, "second stop is a no-op")
-- bad tuning never slows the game
tune.deathSlowmo.speed = 1.5
check(M.start() == nil and M.running() == false, "a speed over 1x is refused")
tune.deathSlowmo.speed = 0.3
tune.deathSlowmo.duration = 60
check(M.start() == nil and M.running() == false, "an 8 s+ window is refused")
tune.deathSlowmo.duration = 2.5
-- Esc's fast forward takes over mid-window through the same stop
check(M.start() == 0.3, "starts again")
now = now + 1
check(M.stop("Esc fast forward", function() speeds[#speeds + 1] = 1 end) == true, "Esc hands time back first")
check(M.running() == false and speeds[2] == 1, "idle for the fast forward")
print(fails == 0 and "PASS" or "FAIL")
