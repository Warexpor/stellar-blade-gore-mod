-- Parse sbslice response fields and opening geometry. No engine objects or state are retained.
local function vec(x, y, z) return { X = x, Y = y, Z = z } end

local function num(r, key) return tonumber(r:match(" " .. key .. "=(%-?[%d.]+)")) end
local function triple(r, key, k)
  local x, y, z = r:match(" " .. key .. "=(%-?[%d.]+),(%-?[%d.]+),(%-?[%d.]+)")
  if not x then return nil end
  return vec(tonumber(x) * k, tonumber(y) * k, tonumber(z) * k)
end
-- one opening from the DLL's answer: centre, major axis, normal, half extents (major, minor, depth)
local function opening(r, tag)
  local o = { c = triple(r, tag .. "c", 1), x = triple(r, tag .. "x", 0.001), z = triple(r, tag .. "z", 0.001),
    e = triple(r, tag .. "e", 1) }
  if not (o.c and o.x and o.z and o.e) then return nil end
  -- the outline: rim points in order, counter-clockwise seen from the side the normal points to
  local list = r:match(" " .. tag .. "p=([%d%.,;%-]+)")
  if list then
    o.p = {}
    for x, y, z in list:gmatch("(%-?[%d.]+),(%-?[%d.]+),(%-?[%d.]+)") do o.p[#o.p + 1] = vec(tonumber(x), tonumber(y), tonumber(z)) end
    if #o.p < 3 then o.p = nil end
  end
  return o
end


-- the widest of a cut's cap/lid extents (cm), else nil: a cap or lid dozens of cm across is a
-- drawn-out spike, not an opening (an after-cut on a leg whose lower part was already off elsewhere)
local function widest(r, other)
  local m
  local function include(e)
    if e then m = math.max(m or 0, math.abs(e.X), math.abs(e.Y), math.abs(e.Z)) end
  end
  include(triple(r, "be", 1)); include(triple(r, "le", 1))
  if other then include(triple(other, "be", 1)); include(triple(other, "le", 1)) end
  return m
end


return { num = num, triple = triple, opening = opening, widest = widest }
