-- The pause detector (photo_freeze.time_stopped): a stopped game clock means photo mode or a real
-- pause, but slow motion also runs the clock behind real time on purpose. It must not read slow motion
-- as a pause (at x0.05 the freeze/unfreeze flap every frame and the mesh tick with it).
local F = require("fake")
local print = F.say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local logs = {}
local scale = 1
local screen = {}
local goreCtx = { time_scale = function() return scale end }
local ctx = {
  try = function(f) local ok, r = pcall(f); if ok then return r end end,
  valid = function(x) return x ~= nil and x ~= false end,
}
dofile("ue4ss/Mods/StellarBladeGore/Scripts/photo_freeze.lua")(screen, goreCtx,
  ctx.valid, ctx.try, function(s) logs[#logs + 1] = s end, nil, nil, nil, nil, nil, nil, nil, nil, nil)
local game = 100
local gs = { GetTimeSeconds = function() return game end }
local pawn = F.obj("Eve", "Pawn")
local function tick(dt, gdt)
  F.t = F.t + dt
  game = game + gdt
  return screen.time_stopped(pawn, gs)
end
-- full speed: a still clock is a pause, a running one isn't
tick(0.05, 0.05)
check(tick(0.05, 0) == true, "full speed, clock stopped: paused")
tick(0.05, 0.05)
check(tick(0.05, 0.05) == false, "full speed, clock running: not paused")
-- slow motion at x0.05: the clock creeping at the expected speed is not a pause...
scale = 0.05
tick(0.05, 0.0025)
check(tick(0.05, 0.0025) == false, "slowed x0.05, clock on pace: not paused")
-- ...but a truly stopped clock still is
tick(0.05, 0.0025)
check(tick(0.05, 0) == true, "slowed x0.05, clock stopped: paused")
print(fails == 0 and "PASS" or "FAIL")
