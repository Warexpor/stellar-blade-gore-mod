-- Her sword thrown with the death (active.throw_along): along the killing blow, else as now.
local F = require("fake")
local M = dofile("ue4ss/Mods/StellarBladeGore/Scripts/active.lua")
local print = F.say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function v(x, y, z) return { X = x, Y = y, Z = z } end
local function close(a, b) return math.abs(a.X - b.X) < 0.01 and math.abs(a.Y - b.Y) < 0.01 and math.abs(a.Z - b.Z) < 0.01 end

local t = M.throw_along(v(3, 4, 0.5), 400)
check(t and close(t, v(240, 320, 0)), "thrown along the blow, horizontal, at full speed")
check(M.throw_along(v(3, 4, 0), 0) == nil, "knob at 0: dropped as now")
check(M.throw_along(nil, 400) == nil, "no blow direction: dropped as now")
check(M.throw_along(v(0, 0, -500), 400) == nil, "a straight-down blow: dropped as now")
local t2 = M.throw_along(v(-100, 0, 900), 200)
check(t2 and close(t2, v(-200, 0, 0)), "straight-line throws keep their sign")
check(#F.errors == 0, "no errors (" .. table.concat(F.errors, "; ") .. ")")
print(fails == 0 and "PASS" or "FAIL")
