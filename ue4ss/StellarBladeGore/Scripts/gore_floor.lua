-- Floor tracing and bounded pool geometry checks.
return function(M, load_obj, get_try, log, vec, add, sub, scale, len, norm, dot, cross)
local trace_logged = false
-- the floor under p: trace down (visibility, her own actor ignored), else 5 cm under p, flat
local function floor_at(pawn, p)
  local try = get_try()
  local ks = load_obj("/Script/Engine.Default__KismetSystemLibrary")
  if ks then
    local hit = {}
    local ok = try(function()
      return ks:LineTraceSingle(pawn, add(p, vec(0, 0, 20)), add(p, vec(0, 0, -400)), 0, false, { pawn }, 0, hit, true,
        { R = 1, G = 0, B = 0, A = 1 }, { R = 0, G = 1, B = 0, A = 1 }, 0)
    end)
    local at = ok and try(function() local l = hit.ImpactPoint or hit.Location; return vec(l.X, l.Y, l.Z) end)
    local n = at and try(function() local l = hit.ImpactNormal or hit.Normal; return vec(l.X, l.Y, l.Z) end)
    if not trace_logged then
      trace_logged = true
      log(string.format("floor blood: trace %s%s", tostring(ok), at and string.format(", hit %.0f cm under", p.Z - at.Z) or ", no hit (using the opening's height)"))
    end
    if at then return at, norm(n or vec(0, 0, 1)) or vec(0, 0, 1) end
  end
  return add(p, vec(0, 0, -5)), vec(0, 0, 1)
end

-- where a pool may spread: a decal's box projects along the floor's normal and paints whatever is in it, so a pool
-- spread up to a wall smeared down it in long streaks (playtest). Two checks keep it on open, flat floor:
-- wall_room as it starts: level traces in 4 directions, 3 and 10 cm over the floor, out to its full size; a surface
-- steeper than 45 deg is a wall, and the pool stays 10 % short of the nearest. ring_ok before it grows into each
-- next ring (6 cm out): 4 traces down onto the ring, each must find floor facing up (within 25 deg of the pool's)
-- within 3 cm of the pool's plane, else it stops at the last ring that held (a post, a curb, a step, a gap, a thin
-- wall a level trace slipped past). (On M: gore.lua is at Lua's 200 locals)
M.POOL_DIRS = 4
function M.pool_frame(n)
  local up = n or vec(0, 0, 1)
  local a = norm(cross(up, math.abs(up.X) < 0.9 and vec(1, 0, 0) or vec(0, 1, 0))) or vec(1, 0, 0)
  return up, a, cross(up, a)
end
function M.pool_trace(pawn, from, to)
  local try = get_try()
  local ks = load_obj("/Script/Engine.Default__KismetSystemLibrary")
  if not ks then return nil end
  local hit = {}
  local ok = try(function()
    return ks:LineTraceSingle(pawn, from, to, 0, false, { pawn }, 0, hit, true,
      { R = 1, G = 0, B = 0, A = 1 }, { R = 0, G = 1, B = 0, A = 1 }, 0)
  end)
  if not ok then return false end
  local at = try(function() local l = hit.ImpactPoint or hit.Location; return vec(l.X, l.Y, l.Z) end)
  local hn = try(function() local l = hit.ImpactNormal or hit.Normal; return vec(l.X, l.Y, l.Z) end)
  return at ~= nil, at, hn and norm(hn)
end
function M.wall_room(pawn, at, n, rmax)
  local up, a, b = M.pool_frame(n)
  local room = rmax
  for _, h in ipairs({ 3, 10 }) do
    local from = add(at, scale(up, h))
    for i = 0, M.POOL_DIRS - 1 do
      local ang = i * 2 * math.pi / M.POOL_DIRS
      local d = add(scale(a, math.cos(ang)), scale(b, math.sin(ang)))
      local hit, p, hn = M.pool_trace(pawn, from, add(from, scale(d, rmax)))
      if hit and p and hn and math.abs(dot(hn, up)) < 0.7 then
        local w = len(sub(p, from))
        if w < room then room = w end
      end
    end
  end
  return math.max(room * 0.9, 4)
end
function M.ring_ok(pawn, at, n, ring)
  local up, a, b = M.pool_frame(n)
  for i = 0, M.POOL_DIRS - 1 do
    local ang = (i + 0.5) * 2 * math.pi / M.POOL_DIRS
    local c = add(at, add(scale(a, math.cos(ang) * ring), scale(b, math.sin(ang) * ring)))
    local hit, p, hn = M.pool_trace(pawn, add(c, scale(up, 15)), add(c, scale(up, -15)))
    if not (hit and p and hn) or dot(hn, up) < 0.9 or math.abs(dot(sub(p, at), up)) > 3 then return false end
  end
  return true
end

-- Incremental wall and floor checks share a bounded trace budget across all pools.
function M.pool_check_step(k, limit)
  local q, used = k.pool, 0
  if not q or not q.check then return 0 end
  local c = q.check
  local up, a, b = M.pool_frame(q.n)
  while used < limit and c.i < (c.kind == "wall" and M.POOL_DIRS * 2 or M.POOL_DIRS) do
    local i = c.i % M.POOL_DIRS
    local ang = (i + (c.kind == "ring" and 0.5 or 0)) * 2 * math.pi / M.POOL_DIRS
    local d = add(scale(a, math.cos(ang)), scale(b, math.sin(ang)))
    local hit, p, hn, from
    if c.kind == "wall" then
      from = add(q.at, scale(up, c.i < M.POOL_DIRS and 3 or 10))
      hit, p, hn = M.pool_trace(k.pawn, from, add(from, scale(d, k.rmax)))
      if hit and p and hn and math.abs(dot(hn, up)) < 0.7 then c.room = math.min(c.room, len(sub(p, from))) end
    else
      local point = add(q.at, scale(d, c.ring))
      hit, p, hn = M.pool_trace(k.pawn, add(point, scale(up, 15)), add(point, scale(up, -15)))
      if not (hit and p and hn) or dot(hn, up) < 0.9 or math.abs(dot(sub(p, q.at), up)) > 3 then c.failed = true end
    end
    c.i, used = c.i + 1, used + 1
    if c.failed then break end
  end
  if c.failed or c.i >= (c.kind == "wall" and M.POOL_DIRS * 2 or M.POOL_DIRS) then
    if c.kind == "wall" then q.rmax = math.max(c.room * 0.9, 4)
    elseif c.failed then q.stopped = true
    else q.ok = c.ring end
    q.check = nil
  end
  return used
end

return floor_at
end
