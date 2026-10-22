-- physfix.lua's runtime fix on a vanilla outfit's physics asset, made up from its JSON (parity.py): the asset as
-- UE4SS hands it over (UObjects with fields, FNames with ToString), sbslice.dll's "b" and "t" answered from the data.
-- Prints what the fix left: B bodies, C main joints, T the table asked for, J the joints it added ("j"), L the bodies
-- still loose after it.
--   lua parity.lua <Scripts dir> <data.lua>...  (its physfix.lua with its tune.lua's physfix settings)
local physfix_path, tune = arg[1] .. "/physfix.lua", dofile(arg[1] .. "/tune.lua")
FName = function(s) return { ToString = function() return s end } end
local function fname(s) return { ToString = function() return s end } end
local function vec(v) return { X = v[1], Y = v[2], Z = v[3] } end

for i = 2, #arg do
  local d = dofile(arg[i])
  local M = dofile(physfix_path)
  local index, asked = {}, nil
  local cons, made, added = {}, {}, {}
  for n, b in pairs(d.bones) do index[n] = b.i end
  local gore = {
    native_state = function() return "ready" end,
    command = function(s)
      if s:sub(1, 1) == "b" then
        local out = {}
        for h in s:gmatch(",(%x+)") do
          local bi = tonumber(h, 16)
          for n, b in pairs(d.bones) do
            if b.i == bi then
              out[#out + 1] = string.format("%d %.17g %.17g %.17g %.17g %.17g %.17g %.17g", bi, b.q[1], b.q[2], b.q[3], b.q[4], b.t[1], b.t[2], b.t[3])
            end
          end
        end
        return "ok " .. table.concat(out, "|")
      elseif s:sub(1, 1) == "j" then
        local f = {}
        for h in s:sub(2):gmatch("%x+") do f[#f + 1] = tonumber(h, 16) end
        if f[2] ~= #cons or f[3] ~= cons[1].addr then return "err no joint array" end
        for k = 4, #f do cons[#cons + 1] = made[f[k]]; added[#added + 1] = made[f[k]] end
        return "ok joints +40 " .. f[2] .. " -> " .. #cons
      elseif s:sub(1, 1) == "t" then
        asked = tonumber(s:match(",(%x+)$"), 16)
        return "ok table +1a8 0 -> 0"
      end
      return "err"
    end,
  }
  local ctx = { tune = tune, gore = gore, log = function() end,
    try = function(fn, ...) local ok, v = pcall(fn, ...); if ok then return v end return nil end,
    valid = function(o) return o ~= nil end }
  M.init(ctx)
  local bodies = {}
  for _, b in ipairs(d.bodies) do
    bodies[#bodies + 1] = { BoneName = fname(b.bone), DefaultInstance = { LinearDamping = b.lin, AngularDamping = b.ang } }
  end
  for _, c in ipairs(d.cons) do
    cons[#cons + 1] = { DefaultInstance = { ConstraintBone1 = fname(c.child), ConstraintBone2 = fname(c.parent),
      PriAxis1 = vec(c.pri1), SecAxis1 = vec(c.sec1), PriAxis2 = vec(c.pri2), SecAxis2 = vec(c.sec2),
      ProfileInstance = { ConeLimit = c.cone, TwistLimit = c.twist } } }
    cons[#cons].addr = 0x10000 + #cons * 0x100
    cons[#cons].GetAddress = function(self) return self.addr end
  end
  StaticFindObject = function(path) return path:match("PhysicsConstraintTemplate$") and {} or nil end
  StaticConstructObject = function(_, outer)
    -- a new template at the class defaults (FConstraintInstance, FConstraintProfileProperties)
    local t = { DefaultInstance = { JointName = "None", ConstraintBone1 = "None", ConstraintBone2 = "None",
      Pos1 = vec({ 0, 0, 0 }), PriAxis1 = vec({ 1, 0, 0 }), SecAxis1 = vec({ 0, 1, 0 }),
      Pos2 = vec({ 0, 0, 0 }), PriAxis2 = vec({ 1, 0, 0 }), SecAxis2 = vec({ 0, 1, 0 }),
      ProfileInstance = { LinearLimit = { XMotion = 2, YMotion = 2, ZMotion = 2 }, bDisableCollision = false,
        ConeLimit = { Swing1Motion = 0, Swing2Motion = 0, Swing1LimitDegrees = 45, Swing2LimitDegrees = 45, bSoftConstraint = true },
        TwistLimit = { TwistMotion = 0, TwistLimitDegrees = 45, bSoftConstraint = true } } } }
    t.addr = 0x80000 + #added * 0x100 + (function() local n = 0; for _ in pairs(made) do n = n + 1 end; return n end)() * 0x100
    t.GetAddress = function(self) return self.addr end
    made[t.addr] = t
    return t
  end
  local function each(list) return { ForEach = function(_, fn) for k, v in ipairs(list) do fn(k, { get = function() return v end }) end end } end
  local pa = { SkeletalBodySetups = each(bodies), ConstraintSetup = each(cons), GetAddress = function() return 0x1000 end }
  local sk = { GetAddress = function() return 0x2000 end }
  local mesh = {
    GetBoneIndex = function(_, n) return index[n:ToString()] or -1 end,
    GetParentBone = function(_, n) local b = d.bones[n:ToString()]; return fname(b and b.parent or "None") end,
  }
  local what = M.fix_asset(pa, mesh, sk)
  print("F " .. d.name .. " " .. what)
  for _, b in ipairs(bodies) do
    print(string.format("B %s %.6f %.6f", b.BoneName:ToString(), b.DefaultInstance.LinearDamping, b.DefaultInstance.AngularDamping))
  end
  for _, c in ipairs(cons) do
    local di = c.DefaultInstance
    local cone, tw = di.ProfileInstance.ConeLimit, di.ProfileInstance.TwistLimit
    print(string.format("C %s %d %d %.6f %.6f %s %d %.6f %s %.7f %.7f %.7f %.7f %.7f %.7f", di.ConstraintBone1:ToString(), cone.Swing1Motion,
      cone.Swing2Motion, cone.Swing1LimitDegrees, cone.Swing2LimitDegrees, tostring(cone.bSoftConstraint), tw.TwistMotion,
      tw.TwistLimitDegrees, tostring(tw.bSoftConstraint), di.SecAxis2.X, di.SecAxis2.Y, di.SecAxis2.Z, di.PriAxis2.X, di.PriAxis2.Y, di.PriAxis2.Z))
  end
  print("T " .. tostring(asked))
  for _, c in ipairs(added) do
    local di, p = c.DefaultInstance, c.DefaultInstance.ProfileInstance
    local function v3(v) return string.format("%.7f %.7f %.7f", v.X, v.Y, v.Z) end
    print(string.format("J %s %s %s %s %s %s %d%d%d%d%d%d %s", di.ConstraintBone1:ToString(), di.ConstraintBone2:ToString(),
      di.JointName:ToString(), v3(di.Pos2), v3(di.PriAxis2), v3(di.SecAxis2), p.LinearLimit.XMotion, p.LinearLimit.YMotion,
      p.LinearLimit.ZMotion, p.ConeLimit.Swing1Motion, p.ConeLimit.Swing2Motion, p.TwistLimit.TwistMotion, tostring(p.bDisableCollision)))
  end
  for _, l in ipairs(M.loose_bodies(pa, mesh)) do print("L " .. l[1] .. " " .. l[2]) end
  print("E")
end
