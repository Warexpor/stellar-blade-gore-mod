-- An arm cut on a cape outfit (gore.lua kept_chains): CH_P_EVE_09's cape (Ab_CapeL01, 7 links, 70 cm, hung off the
-- upper arm's twist bone Ab-L-UpperArm-Tw1) has to be kept off the arm, to be cut off as a piece of its own, in any pose
-- of her arm: hanging down her side (the cape along the arm, past its end) and held out level or raised (the cape
-- hanging across the arm, within its length: it was taken for a strap and stretched from her shoulder to the arm on
-- the floor, playtest screenshot). A leg strap's chain (CH_P_EVE_14's Ab_LLA01, 14 cm round the thigh) is still one
local F = require("fake")
local M = dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore.lua")
local print = F.say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function v(x, y, z) return { X = x, Y = y, Z = z } end
local function add(a, b) return v(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
local function sc(a, k) return v(a.X * k, a.Y * k, a.Z * k) end
-- a mesh: bones { name, parent, world location }, the physics bodies' bone names
local function mesh(bones, bodies)
  local by, list = {}, {}
  for i, b in ipairs(bones) do by[b[1]] = b; list[i - 1] = b[1] end
  local m = { __n = #bones }
  local sm = { GetAddress = function() return 0x5000 + #bones end }
  m.SkeletalMesh = sm
  function m:GetAddress() return 0x9000 + #bones end
  function m:GetNumBones() return #bones end
  function m:GetBoneName(i) return FName(list[i] or "None") end
  function m:GetBoneIndex(n) local b = by[n:ToString()]; for i = 0, #bones - 1 do if list[i] == (b and b[1]) then return i end end; return -1 end
  function m:GetParentBone(n) local b = by[n:ToString()]; return FName(b and b[2] or "None") end
  function m:GetSocketLocation(n) local b = by[n:ToString()]; return b and b[3] or v(0, 0, 0) end
  function m:BoneIsChildOf(x, y)
    local b = by[x:ToString()]
    while b and b[2] do if b[2] == y:ToString() then return true end; b = by[b[2]] end
    return false
  end
  local setups = {}
  for _, n in ipairs(bodies) do setups[#setups + 1] = { BoneName = FName(n) } end
  m.__pa = { SkeletalBodySetups = { ForEach = function(_, f) for i, s in ipairs(setups) do f(i, { get = function() return s end }) end end } }
  return m
end
M.init({ log = function() end, try = function(f) local ok, r = pcall(f); if ok then return r end end,
  valid = function(x) return x ~= nil end, v3 = function() return "" end, physics_of = function(m) return m.__pa end })
-- her left arm from the shoulder (0, 0, 140) along dir, 24 cm, the cape off its twist bone half way, hanging down
-- (gravity: -Z) 7 links of 10 cm
local function arm(dir, at)
  local sh = v(15, 0, 140)
  local fa = add(sh, sc(dir, 24))
  local tw = add(sh, sc(dir, 12))
  local bones = {
    { "Bip001-Spine2", nil, v(0, 0, 130) }, { "Bip001-L-Clavicle", "Bip001-Spine2", v(5, 0, 140) },
    { "Bip001-L-UpperArm", "Bip001-L-Clavicle", sh }, { "Ab-L-UpperArm-Tw1", "Bip001-L-UpperArm", tw },
    { "Bip001-L-Forearm", "Bip001-L-UpperArm", fa }, { "Bip001-L-Hand", "Bip001-L-Forearm", add(fa, sc(dir, 22)) },
  }
  local bodies = { "Bip001-Spine2", "Bip001-L-UpperArm", "Bip001-L-Forearm" }
  -- (its joint 5 cm off the arm, square to it: rigid on the twist bone, whatever the pose)
  local px, py = -dir.Y, dir.X
  local pl = math.sqrt(px * px + py * py)
  local top = add(tw, pl > 0.1 and v(px / pl * 5, py / pl * 5, 0) or v(0, -5, 0))
  local prev = "Ab-L-UpperArm-Tw1"
  for k = 1, 7 do
    local n = string.format("Ab_CapeL%02d", k)
    bones[#bones + 1] = { n, prev, add(top, v(0, 0, -(k - 1) * 10)) }
    bodies[#bodies + 1] = n
    prev = n
  end
  local m = mesh(bones, bodies)
  local p = add(sh, sc(dir, 24 * at))
  return M.kept_chains(m, "Bip001-L-UpperArm", sh, fa, p, dir)
end
for _, c in ipairs({ { "hanging down", v(0.2, 0, -1) }, { "held out level", v(1, 0, 0) }, { "raised", v(0.5, 0, 0.85) },
  { "held forward", v(0, -1, 0) } }) do
  local l = math.sqrt(c[2].X ^ 2 + c[2].Y ^ 2 + c[2].Z ^ 2)
  local d = sc(c[2], 1 / l)
  for _, at in ipairs({ 0.25, 0.4, 0.7 }) do
    local tops, stay = arm(d, at)
    check(#tops == 1 and tops[1] == "Ab_CapeL01" and not stay.Ab_CapeL01,
      string.format("arm %s, cut %.0f%% down it: the cape kept off the arm to be cut off (%s)", c[1], at * 100,
        #tops > 0 and (tops[1] .. (stay[tops[1]] and ", taken for a strap" or "")) or "not kept"))
  end
end
-- a leg strap: CH_P_EVE_14's Ab_LLA01 off the thigh, 3 links round it 20-34% down, a 45 cm thigh hanging down
do
  local hip, knee = v(10, 0, 95), v(10, 0, 50)
  local bones = { { "Bip001-Pelvis", nil, v(0, 0, 100) }, { "Bip001-L-Thigh", "Bip001-Pelvis", hip },
    { "Bip001-L-Calf", "Bip001-L-Thigh", knee } }
  local bodies = { "Bip001-Pelvis", "Bip001-L-Thigh", "Bip001-L-Calf" }
  local prev = "Bip001-L-Thigh"
  for k = 1, 3 do
    local n = string.format("Ab_LLA%02d", k)
    bones[#bones + 1] = { n, prev, v(10 + 6 * math.cos(k), 6 * math.sin(k), 86 - 3 * k) }
    bodies[#bodies + 1] = n
    prev = n
  end
  local m = mesh(bones, bodies)
  local tops, stay = M.kept_chains(m, "Bip001-L-Thigh", hip, knee, v(10, 0, 70), v(0, 0, -1))
  check(#tops == 1 and stay.Ab_LLA01, "a leg strap over the plane is still a strap, staying on her")
  tops, stay = M.kept_chains(m, "Bip001-L-Thigh", hip, knee, v(10, 0, 90), v(0, 0, -1))
  check(#tops == 0, "a leg strap past the plane still goes with the leg")
end
print(fails == 0 and "PASS" or "FAIL")
