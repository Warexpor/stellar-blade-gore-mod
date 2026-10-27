-- struggle.lua's limb solve against her real hinges: elbows and knees fold one way only, positive about the lower
-- bone's own X (CH_P_EVE_01's bind pose: X of each forearm and calf below, in her component). The playtest's arms
-- never bent: the solve bent them the way each act's pole guessed, backwards for some, and the 3 deg the joint
-- allows that way held them straight
local print = print
local S = dofile("ue4ss/Mods/StellarBladeGore/Scripts/struggle.lua")

local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local function add(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
local function sub(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
local function scale(a, k) return vec(a.X * k, a.Y * k, a.Z * k) end
local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function cross(a, b) return vec(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
local function norm(a) local l = math.sqrt(dot(a, a)); return scale(a, 1 / l) end
local function perp(a, n) return sub(a, scale(n, dot(a, n))) end
local function turn(v, a, ang)
  local c, s = math.cos(ang), math.sin(ang)
  return add(add(scale(v, c), scale(cross(a, v), s)), scale(a, dot(a, v) * (1 - c)))
end
-- the signed fold of d from up about x, deg
local function folded(up, d, x)
  local u, v = norm(perp(up, x)), norm(perp(d, x))
  return math.deg(math.atan(dot(cross(u, v), x), dot(u, v)))
end

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
if type(S) ~= "table" or not (S.fold and S.solve) then print("FAIL: struggle.lua has no fold / solve"); print("FAIL"); return end

local HINGE = {
  { "left elbow", "arm", vec(-0.08, -0.87, 0.49), 28, 25 }, { "right elbow", "arm", vec(0.08, -0.87, -0.49), 28, 25 },
  { "left knee", "leg", vec(-0.08, 1.0, -0.06), 45, 42 }, { "right knee", "leg", vec(0.08, 1.0, 0.06), 45, 42 },
}
for _, h in ipairs(HINGE) do
  local name, kind, x, l1, l2 = h[1], h[2], norm(h[3]), h[4], h[5]
  local most = kind == "arm" and 145 or 140
  local up = norm(perp(vec(0.3, 0.2, -1), x))
  -- fold: what the hinge allows
  local f = folded(up, S.fold(up, turn(up, x, math.rad(90)), x, most), x)
  check(math.abs(f - 90) < 0.5, string.format("%s: a 90 deg fold the way it goes kept (%.1f)", name, f))
  f = folded(up, S.fold(up, turn(up, x, math.rad(-40)), x, most), x)
  check(math.abs(f) < 0.5, string.format("%s: 40 deg the wrong way comes out straight (%.1f)", name, f))
  f = folded(up, S.fold(up, turn(up, x, math.rad(-170)), x, most), x)
  check(math.abs(f - most) < 0.5, string.format("%s: 170 deg the wrong way, nearer the full fold, folds it fully (%.1f)", name, f))
  -- solve: a target that needs the joint bent 100 deg, the caller's pole on the wrong side and on the right one
  local a = vec(0, 0, 100)
  local m = add(a, scale(up, l1))
  local e = add(m, scale(up, l2))
  local t = add(m, scale(turn(up, x, math.rad(100)), l2))
  local side = norm(cross(norm(sub(t, a)), x))
  for _, p in ipairs({ { "the wrong way", scale(side, -1) }, { "the right way", side } }) do
    local d1, d2 = S.solve(a, m, e, t, x, p[2], kind)
    local bend = d1 and folded(d1, d2, x) or -999
    local got = d1 and add(add(a, scale(d1, l1)), scale(turn(norm(perp(d1, x)), x, math.rad(bend)), l2))
    local off = got and math.sqrt(dot(sub(got, t), sub(got, t))) or 999
    check(bend > 90 and bend < 110 and off < 2, string.format("%s, its pole %s: bent %.0f deg its own way, the end %.1f cm off the target",
      name, p[1], bend, off))
  end
  -- no hinge read: the pole's bend, as before
  local d1, d2 = S.solve(a, m, e, t, nil, side, kind)
  check(d1 ~= nil and d2 ~= nil, name .. ": no hinge read, still solved (on the pole)")
end
print(fails == 0 and "PASS" or "FAIL")
