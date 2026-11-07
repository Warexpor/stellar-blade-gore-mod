-- Slow-motion death effect (death_slowmo.lua): off unless enabled, runs its window,
-- hands time back, and refuses bad speeds and durations
local print = require("fake").say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local now = 1000
local tune = { deathSlowmo = { enabled = false, speed = 0.15, duration = 5 } }
local logs = {}
local function log(s) logs[#logs + 1] = s end
local M = dofile("ue4ss/Mods/StellarBladeGore/Scripts/death_slowmo.lua")(
  function() return tune end, function() return now end, log)
check(M.running() == false, "idle at first")
check(M.start() == nil, "off unless enabled")
check(M.running() == false, "nothing running while off")
tune.deathSlowmo.enabled = true
check(M.start() == 0.15, "starts at the tuned speed")
check(M.running() == true, "running in its window")
check(M.done() == false, "not done at once")
now = now + 5
check(M.done() == true, "done after its duration")
local speeds = {}
check(M.stop("its time is up", function() speeds[#speeds + 1] = 1 end) == true, "stop hands time back")
check(speeds[1] == 1, "full speed restored")
check(M.running() == false, "idle after its window")
check(M.stop("again") == false, "second stop is a no-op")
-- speeds outside (0, 1) and non-positive durations are refused; length has no cap
tune.deathSlowmo.speed = 1.5
check(M.start() == nil and M.running() == false, "a speed over 1x is refused")
tune.deathSlowmo.speed = 0
check(M.start() == nil and M.running() == false, "a zero speed is refused")
tune.deathSlowmo.speed = 0.01
tune.deathSlowmo.duration = 0
check(M.start() == nil and M.running() == false, "a zero duration is refused")
tune.deathSlowmo.duration = 120
check(M.start() == 0.01, "a long window and near-freeze speed are allowed")
now = now + 120
check(M.done() == true, "done after a long window")
M.stop("cleanup")
-- Esc's fast forward takes over mid-window through the same stop
now = 2000
check(M.start() == 0.01, "starts again")
now = now + 1
check(M.stop("Esc fast forward", function() speeds[#speeds + 1] = 1 end) == true, "Esc hands time back first")
check(M.running() == false and speeds[2] == 1, "idle for the fast forward")
-- the ease back: flat through the window, gliding to full after, done at the end of the glide
tune.deathSlowmo.speed, tune.deathSlowmo.duration, tune.deathSlowmo.easeOut = 0.15, 4, 1.2
now = 3000
check(M.start() == 0.15, "starts again for the ease")
now = now + 2
check(M.speed() == 0.15 and M.easing() == false and M.done() == false, "flat through its window")
now = now + 2.6
local mid = M.speed()
check(M.easing() == true and M.done() == false and mid > 0.15 and mid < 1, "gliding back after its window")
now = now + 0.4
local late = M.speed()
check(late > mid and late < 1, "still climbing toward full speed")
now = now + 0.3
check(M.done() == true and M.easing() == false, "done at the end of the glide")
M.stop("cleanup")
print(fails == 0 and "PASS" or "FAIL")
