-- Swing selection under slow motion (swing_selection.lua): trail speeds divide by real time, so at
-- quarter speed the same motion reads four times as fast, and age penalties count game time.
local F = require("fake")
local print = F.say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function v(x, y, z) return { X = x, Y = y, Z = z } end
local function sub(a, b) return v(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function len(a) return math.sqrt(dot(a, a)) end
local function dist(a, b) return len(sub(a, b)) end
local function cross(a, b) return v(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
local function unit(a) local n = len(a); return n > 0 and v(a.X / n, a.Y / n, a.Z / n) or nil end
local function try(f) local ok, r = pcall(f); if ok then return r end end
local SWING_AT = { { "Bip001-Head" } }
local mesh = F.obj("EveMesh", "SkeletalMeshComponent")
mesh.GetSocketLocation = function(_, b) return v(50, 50, 0) end
local actor = F.obj("Enemy", "CH_M_NA_43_Blueprint_C")
actor.GetActorForwardVector = function() return v(1, 0, 0) end
local function hist()
  local t0 = F.t
  return {
    { t = t0 - 0.4, w = { [1] = { a = v(0, -100, 0), b = v(100, -100, 0) } } },
    { t = t0 - 0.2, w = { [1] = { a = v(0, 0, 0), b = v(100, 0, 0) } } },
    { t = t0, w = { [1] = { a = v(0, 100, 0), b = v(100, 100, 0) } } },
  }
end
local function swing() return { hist = hist(), actor = actor, who = "enemy", weapons = { [1] = { name = "hand", socket = "Bip001-R-Hand" } } } end
local tune = { gore = { swingMinSpeed = 300, swingMiss = 1000 } }
local function run(scale)
  local sel = dofile("ue4ss/Mods/StellarBladeGore/Scripts/swing_selection.lua")(
    function() return tune end, function() return true end, try, function(vv) return vv end, SWING_AT,
    sub, dot, dist, len, unit, cross, function() end,
    function() return scale end)
  return sel(swing(), mesh)
end
local full = run(1)
check(full and math.abs(full.speed - 500) < 0.01, "full speed: the step reads 500 cm/s")
local slow = run(0.25)
check(slow and math.abs(slow.speed - 2000) < 0.01, "quarter speed: the same motion reads 2000 cm/s")
check(full and slow and slow.how == full.how, "the same plane is found either way")
print(fails == 0 and "PASS" or "FAIL")
