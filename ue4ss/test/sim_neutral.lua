-- neutral: the neutral pose's drive targets (physfix.neutral_targets, tune.active.neutral) reach the pose asked for:
-- each made target, turned into a quaternion as UE's FRotator does, moves a limb's far end front / out by as much
local M = dofile("ue4ss/Mods/StellarBladeGore/Scripts/physfix.lua")
-- UE FRotator::Quaternion
local function quat(r)
  local p, y, ro = math.rad(r.Pitch) / 2, math.rad(r.Yaw) / 2, math.rad(r.Roll) / 2
  local sp, cp, sy, cy, sr, cr = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(ro), math.cos(ro)
  return { cr * sp * sy - sr * cp * cy, -cr * sp * cy - sr * cp * sy, cr * cp * sy - sr * sp * cy, cr * cp * cy + sr * sp * sy }
end
local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
local function qrot(q, v)
  local u, w = { q[1], q[2], q[3] }, q[4]
  local c0 = cross(u, v); local m = cross(u, { c0[1] + v[1] * w, c0[2] + v[2] * w, c0[3] + v[3] * w })
  return { v[1] + 2 * m[1], v[2] + 2 * m[2], v[3] + 2 * m[3] }
end
local fails = 0
local function near(a, b, what, tol) if math.abs(a - b) > (tol or 0.5) then fails = fails + 1; print("FAIL " .. what, a, b) end end
-- round trip of the rotator
for _, q0 in ipairs({ { 0.1, 0.2, 0.3, 0.927 }, { -0.4, 0.1, 0.2, 0.888 }, { 0.3, -0.5, 0.1, 0.806 } }) do
  local n = math.sqrt(q0[1]^2 + q0[2]^2 + q0[3]^2 + q0[4]^2); for i = 1, 4 do q0[i] = q0[i] / n end
  local q = quat(M.rotator(q0)); local s = (q[4] * q0[4] < 0) and -1 or 1
  for i = 1, 4 do near(q[i] * s * 100, q0[i] * 100, "rotator round trip") end
end
-- a body: front +X, she stands at the origin; every bone at identity rotation
local I = { 0, 0, 0, 1 }
local bind = {
  ["Bip001-L-Toe0"] = { q = I, t = { 10, 0, 0 } }, ["Bip001-L-Foot"] = { q = I, t = { 0, 0, 10 } },
  ["Bip001-Pelvis"] = { q = I, t = { 0, 0, 100 } }, P = { q = I, t = { 0, 20, 150 } },
  C = { q = I, t = { 0, 20, 140 } }, E = { q = I, t = { 0, 20, 110 } },
}
-- the joint's frame in world after the drive reaches its target: where E's direction (down) goes
local function check(pri, sec, tilt, pose, wantFront, wantOut, what)
  -- frames given straight (bone rotations are identity), frame 2 possibly turned about Z by tilt (as fix_joints)
  local pri2, sec2 = pri, sec
  if tilt ~= 0 then
    local z = cross(pri, sec); local t = math.rad(tilt)
    pri2 = { pri[1] * math.cos(t) + sec[1] * math.sin(t), pri[2] * math.cos(t) + sec[2] * math.sin(t), pri[3] * math.cos(t) + sec[3] * math.sin(t) }
    sec2 = { sec[1] * math.cos(t) - pri[1] * math.sin(t), sec[2] * math.cos(t) - pri[2] * math.sin(t), sec[3] * math.cos(t) - pri[3] * math.sin(t) }
  end
  local cons = { { child = "C", parent = "P", pri1 = pri, sec1 = sec, pri2 = pri2, sec2 = sec2 } }
  local out, notes = M.neutral_targets(cons, bind, { C = pose }, { C = "E" })
  if not out.C then fails = fails + 1; print("FAIL " .. what .. ": no target", table.concat(notes, "; ")); return end
  local q = quat(out.C)
  -- frame 1 in world = frame 2 (world) * q; the child's rotation = that * frame1-in-bone^-1. Frames as matrices:
  -- the end's direction in frame-1 coordinates is fixed, so take it in frame 1 at bind, then map through frame 2 * q
  local f1 = { pri, sec, cross(pri, sec) }
  local f2 = { pri2, sec2, cross(pri2, sec2) }
  local d = { 0, 0, -1 }
  local loc = { d[1] * f1[1][1] + d[2] * f1[1][2] + d[3] * f1[1][3], d[1] * f1[2][1] + d[2] * f1[2][2] + d[3] * f1[2][3],
    d[1] * f1[3][1] + d[2] * f1[3][2] + d[3] * f1[3][3] }
  local inF2 = qrot(q, loc)
  local w = { 0, 0, 0 }
  for i = 1, 3 do for k = 1, 3 do w[k] = w[k] + inF2[i] * f2[i][k] end end
  local front = math.deg(math.atan(w[1], -w[3]))
  local out_ = math.deg(math.atan(w[2], -w[3])) -- +Y is away from her midline (C is at y = 20)
  near(front, wantFront, what .. " front", pose.out and pose.front ~= 0 and 1.5 or nil) -- (front read off a limb turned out too); near(out_, wantOut, what .. " out")
  print(string.format("%s: target P%.1f Y%.1f R%.1f -> front %.1f out %.1f", what, out.C.Pitch, out.C.Yaw, out.C.Roll, front, out_))
end
-- a hinge about her side axis (Y), both ways round
check({ 0, 1, 0 }, { 1, 0, 0 }, 0, { front = 40 }, 40, 0, "hinge +Y")
check({ 0, -1, 0 }, { 1, 0, 0 }, 0, { front = 40 }, 40, 0, "hinge -Y")
check({ 0, 1, 0 }, { 0, 0, 1 }, 0, { front = -50 }, -50, 0, "hinge +Y back")
-- a shoulder: hinge about Y, Swing1 about frame 2's Z, which must point along her front (+X): pri Y, sec Z -> Z = Y x Z = X
check({ 0, 1, 0 }, { 0, 0, 1 }, 0, { front = 0, out = 20 }, 0, 20, "out only")
check({ 0, 1, 0 }, { 0, 0, 1 }, 0, { front = 30, out = 15 }, 30, 15, "front and out")
check({ 0, -1, 0 }, { 0, 0, -1 }, 0, { front = 30, out = 15 }, 30, 15, "front and out, flipped frames")
check({ 0, 1, 0 }, { 0, 0, 1 }, 12, { front = 30, out = 15 }, 30, 15, "front and out, frame 2 tilted")
print(fails == 0 and "PASS" or "FAIL")
