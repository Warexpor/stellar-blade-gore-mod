-- Swing selection in the actor's own frame: a dash carrying a still hand is no swing (it used to read as a
-- 13572 cm/s swing with a garbage plane: a downward calf cut from a midsection-upward blow, playtest), while a real
-- swing during the dash still reads at its own speed and direction.
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
local function dist(a, b) local d = sub(a, b); return math.sqrt(dot(d, d)) end
local function len(a) return math.sqrt(dot(a, a)) end
local function unit(a) local l = len(a); return l > 1e-6 and v(a.X / l, a.Y / l, a.Z / l) or nil end
local function cross(a, b) return v(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
local settings = function() return { gore = { swingMinSpeed = 300, swingWindow = 0.6 } } end
local of = dofile("ue4ss/Mods/StellarBladeGore/Scripts/swing_selection.lua")(
  settings, function() return true end, function(f) local ok, r = pcall(f); if ok then return r end end,
  function(x) return x end, {}, sub, dot, dist, len, unit, cross, function() end)
local actor = F.obj("Grub", "CH_M_NA_07_TypeB_C", { GetActorForwardVector = function() return v(1, 0, 0) end })
-- a hand held still at the body's side while it dashes 300 cm in 0.1 s (3000 cm/s world speed)
local t0 = os.clock()
local function dash_hist()
  local h = {}
  for i = 0, 3 do
    h[#h + 1] = { t = t0 - 0.3 + i * 0.1, p = { v(300 * i, 0, 100) }, origin = v(300 * i, 0, 0) }
  end
  return h
end
local dash = of({ hist = dash_hist(), bones = { "Bip001-R-Hand" }, who = "Grub", k = 1, actor = actor }, nil)
check(dash == nil, "a dashed still hand is no swing")
-- a curving dash (direction changing sample to sample): the old world-space arc read it as a swing
local function curve_hist()
  local h = {}
  for i = 0, 3 do
    local th = i * 0.4
    local o = v(200 * math.cos(th), 200 * math.sin(th), 0)
    h[#h + 1] = { t = t0 - 0.3 + i * 0.1, p = { v(o.X, o.Y + 50, o.Z + 100) }, origin = o }
  end
  return h
end
local curve = of({ hist = curve_hist(), bones = { "Bip001-R-Hand" }, who = "Grub", k = 1, actor = actor }, nil)
check(curve == nil, "a curving dash with a still hand is no swing")
-- the same dash with a real 500 cm/s upward swing of the hand against the body
local function swing_hist()
  local h = {}
  for i = 0, 3 do
    h[#h + 1] = { t = t0 - 0.3 + i * 0.1, p = { v(300 * i, 0, 100 + 50 * i) }, origin = v(300 * i, 0, 0) }
  end
  return h
end
local sw = of({ hist = swing_hist(), bones = { "Bip001-R-Hand" }, who = "Grub", k = 1, actor = actor }, nil)
check(sw ~= nil and math.abs(sw.speed - 500) < 5, "the swing reads at its own speed (" .. tostring(sw and sw.speed) .. ")")
check(sw ~= nil and sw.dir ~= nil and sw.dir.Z > 0.9, "the swing points up with the hand, not with the dash")
for _, e in ipairs(F.errors) do print("hook error: " .. e) end
check(#F.errors == 0, "no engine simulation errors")
print(fails == 0 and "PASS" or "FAIL")
