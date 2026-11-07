-- Select the weapon sweep that best explains a hit. Settings and object guards remain live.
return function(settings, held, try, vof, SWING_AT, sub, dot, dist, len, unit, cross, log, get_scale)
local function scale() local s = get_scale and get_scale() or 1; return (s and s > 0) and s or 1 end
return function(swing, mesh)
  local g = settings().gore or {}
  local h = swing.hist
  -- an old trail (the enemy gone, or a death that started without it) is no swing
  if #h < 3 or os.clock() - h[#h].t > (g.swingWindow or 0.6) or not held(swing.k) then return nil end
  local fwd = try(function() return vof(swing.actor:GetActorForwardVector()) end)
  -- a weapon mesh's blade: the step (fast enough) whose sweep went through her, the plane through the blade line along
  -- its motion. The fastest step alone was the pull-back after a blocked blow: its plane passed 52 cm beside her, was
  -- moved onto her calf and took a leg, the arms raised in front and the body untouched (playtest). Each step's blade
  -- is swept over spots of its motion (every ~15 cm) against her parts (SWING_AT, where they were with that sample: s.pose);
  -- the nearest wins, a fast one a little ahead (up to swingSpeedPull cm), one moving away from that part well behind
  -- the nearest point of segment a-b to p, and how far
  local function seg_near(p, a, b)
    local ab = sub(b, a)
    local t = math.max(0, math.min(1, dot(sub(p, a), ab) / math.max(dot(ab, ab), 1e-4)))
    local x = { X = a.X + ab.X * t, Y = a.Y + ab.Y * t, Z = a.Z + ab.Z * t }
    return x, dist(p, x)
  end
  local parts_now, parts_by_step = nil, {}
  local function parts(s)
    local P = s.pose
    if not P and not parts_now then
      parts_now = {}
      local function sample(b)
        if not parts_now[b] then parts_now[b] = try(function() return vof(mesh:GetSocketLocation(FName(b))) end) end
      end
      for _, x in ipairs(SWING_AT) do
        sample(x[1])
        if x[3] then sample(x[3]) end
      end
    end
    local function at(b) local p = P and P[b]; return p and p.t or (parts_now and parts_now[b]) end
    local out = {}
    for _, x in ipairs(SWING_AT) do
      local a = at(x[1])
      local b = x[3] and at(x[3])
      if a then out[#out + 1] = { b and { X = a.X + 0.4 * (b.X - a.X), Y = a.Y + 0.4 * (b.Y - a.Y), Z = a.Z + 0.4 * (b.Z - a.Z) } or a, x[1] } end
    end
    return out
  end
  local bw, second, fastest, steps, closest = nil, nil, nil, 0, nil
  local perw = {} -- each weapon's best step (a second blade of the swing: a cross slash with two)
  local minv, pull, full, now, gts = g.swingMinSpeed or 300, g.swingSpeedPull or 30, g.swingSpeedFull or 9000, os.clock(), scale()
  for i = 2, #h do
    local dt = (h[i].t - h[i - 1].t) * gts
    if dt > 1e-3 and h[i].w and h[i - 1].w then
      for k, e in pairs(h[i].w) do
        local o = h[i - 1].w[k]
        if o then
          local v = math.max(dist(o.a, e.a), dist(o.b, e.b)) / dt
          if not fastest or v > fastest then fastest = v end
          if v >= minv and mesh then
            steps = steps + 1
            local near, nd, np, part
            -- (spots every ~15 cm of the blade's motion: three spots of a 190 cm step at 11000 cm/s left 59 cm between
            -- the blade and her calf it went through, playtest)
            local cuts = math.max(2, math.min(12, math.ceil(v * dt / 15)))
            local targets = parts_by_step[i]
            if not targets then targets = parts(h[i]); parts_by_step[i] = targets end
            for _, pt in ipairs(targets) do
              for j = 0, cuts do
                local f = j / cuts
                local ax, ay, az = o.a.X + (e.a.X - o.a.X) * f, o.a.Y + (e.a.Y - o.a.Y) * f, o.a.Z + (e.a.Z - o.a.Z) * f
                local bx, by, bz = o.b.X + (e.b.X - o.b.X) * f, o.b.Y + (e.b.Y - o.b.Y) * f, o.b.Z + (e.b.Z - o.b.Z) * f
                local dx, dy, dz = bx - ax, by - ay, bz - az
                local p = pt[1]
                local t = math.max(0, math.min(1, ((p.X - ax) * dx + (p.Y - ay) * dy + (p.Z - az) * dz)
                  / math.max(dx * dx + dy * dy + dz * dz, 1e-4)))
                local x, y, z = ax + dx * t, ay + dy * t, az + dz * t
                local px, py, pz = p.X - x, p.Y - y, p.Z - z
                local d = math.sqrt(px * px + py * py + pz * pz)
                if not nd or d < nd then near, nd, np, part = { X = x, Y = y, Z = z }, d, p, pt[2] end
              end
            end
            if nd then
              -- (from where the blade started the step: one that went through the part had it ahead)
              local s0 = seg_near(np, o.a, o.b)
              local away = dot(sub((seg_near(np, e.a, e.b)), s0), sub(np, s0)) < 0
              -- (an older step costs more: a slow 2662 cm/s brush past her calf 0.27 s before the death beat the
              -- 9825 cm/s slash across her body after it and took one leg, playtest)
              local sc = nd - pull * math.min(1, v / full) + (away and (g.swingAwayCost or 60) or 0)
                + (g.swingAgeCost or 60) * (now - h[i].t) * gts
              if not closest or nd < closest then closest = nd end
              local c = { speed = v, i = i, k = k, sc = sc, d = nd, at = near, part = part, away = away }
              if not perw[k] or sc < perw[k].sc then perw[k] = c end
              if not bw or sc < bw.sc then
                if bw and bw.part ~= part then second = bw end
                bw = c
              elseif bw.part ~= part and (not second or sc < second.sc) then second = c end
            end
          elseif v >= minv and (not bw or v > bw.speed) then
            bw = { speed = v, i = i, k = k }
          end
        end
      end
    end
  end
  -- a blade that never came near her (its nearest step swept swingMiss cm off every part of her) didn't make the
  -- blow: its plane, put through her, took a standing Eve's shin with a 433 cm weapon 59 cm off her (playtest). The
  -- death goes on with a made-up blow (the weapon's bones would only miss her wider)
  if closest and closest > (g.swingMiss or 45) then
    log(string.format("swing: %d fast steps of %s's blade, the nearest %.0f cm from her: it missed her, not its plane",
      steps, tostring(swing.who), closest))
    return nil
  end
  if bw and bw.speed >= minv then
    local e, o = h[bw.i].w[bw.k], h[bw.i - 1].w[bw.k]
    local m1 = bw.at or { X = (e.a.X + e.b.X) / 2, Y = (e.a.Y + e.b.Y) / 2, Z = (e.a.Z + e.b.Z) / 2 }
    if bw.d then
      log(string.format("swing: step %.2f s before of %d fast ones, its blade %.0f cm from her %s%s at %.0f cm/s (fastest %.0f)",
        os.clock() - h[bw.i].t, steps, bw.d, tostring(bw.part), bw.away and ", moving away from it" or "", bw.speed, fastest or 0)
        .. (second and string.format("; next best %.2f s before, %.0f cm from her %s at %.0f cm/s", os.clock() - h[second.i].t,
          second.d, tostring(second.part), second.speed) or ""))
    end
    -- a step's plane: the faster end's motion (a blade turning about its grip: the tip's), the midpoint's when it
    -- barely moved, across the blade (a thrust runs along the blade: no plane from it)
    local function plane(x)
      local e, o = h[x.i].w[x.k], h[x.i - 1].w[x.k]
      local ta, tb = sub(e.a, o.a), sub(e.b, o.b)
      local dir = unit(len(tb) >= len(ta) and tb or ta)
      local blade = unit(sub(e.b, e.a))
      local c = dir and blade and cross(blade, dir)
      if c and len(c) > 0.3 then return dir, unit(c) end
    end
    local dir, n = plane(bw)
    if n then
      local w = swing.weapons[bw.k]
      -- the other weapon's best step, when it swept another part of her within swingMiss (a cross slash with two
      -- blades took one arm, the second blade's never came off, playtest question): cut along its own plane too
      -- (of the same blow: as fast as half the first blade and within 0.15 s of it, on another limb. A slow 2900 cm/s
      -- drift of the idle blade past her calf 0.28 s before passed for one, under a slash through the same leg)
      local function limb(p) local sd = p and p:match("^Bip001%-(%a)%-"); return sd and (sd .. ((p:find("Arm") or p:find("Hand")) and "arm" or "leg")) or p end
      local two
      for k, x in pairs(perw) do
        if k ~= bw.k and x.d and x.d <= (g.swingMiss or 45) and x.part and limb(x.part) ~= limb(bw.part)
          and x.speed >= math.max(minv, 0.5 * bw.speed) and math.abs(h[x.i].t - h[bw.i].t) * gts <= 0.15
          and (not two or x.sc < two.sc) then two = x end
      end
      local second
      if two then
        local d2, n2 = plane(two)
        local w2 = swing.weapons[two.k]
        if n2 then
          second = { dir = d2, n = n2, at = two.at, part = two.part, part_d = two.d, speed = two.speed,
            ago = os.clock() - h[two.i].t, bone = w2 and (w2.name .. " on " .. w2.socket) or "weapon" }
          log(string.format("swing: its second blade (%s) %.2f s before, %.0f cm from her %s at %.0f cm/s",
            second.bone, second.ago, two.d, tostring(two.part), two.speed))
        end
      end
      return { dir = dir, n = n, how = "blade " .. (w and w.name or "weapon"), at = m1, speed = bw.speed,
        bone = w and (w.name .. " on " .. w.socket) or "weapon", fwd = fwd, ago = os.clock() - h[bw.i].t, pose = h[bw.i].pose,
        part = bw.part, part_d = bw.d, second = second,
        impactRadius = w and w.impactRadius, impactSizeSource = w and "weapon cross-section" }
    end
  end
  if not swing.bones or #swing.bones == 0 then return nil end
  -- in the actor's own frame: a dash carries the whole body, and world-space hand speed read a dash as a
  -- 13572 cm/s swing with a garbage plane (a downward cut from a midsection-upward blow, playtest). A real swing
  -- still reads (the arm moves against the body); a pure dash reads ~0 and is no swing, as it should be
  local function rel(j, b)
    local p = h[j].p[b]
    local o = h[j].origin
    if p and o then return { X = p.X - o.X, Y = p.Y - o.Y, Z = p.Z - o.Z } end
    return p
  end
  local best
  for i = 2, #h do
    local dt = (h[i].t - h[i - 1].t) * gts
    if dt > 1e-3 then
      for b = 1, #swing.bones do
        local p, q = rel(i - 1, b), rel(i, b)
        if p and q then
          local v = dist(p, q) / dt
          if not best or v > best.speed then best = { speed = v, i = i, b = b } end
        end
      end
    end
  end
  if not best or best.speed < (g.swingMinSpeed or 300) then
    if best then log(string.format("swing: %s's fastest bone %s only %.0f cm/s", tostring(swing.who), swing.bones[best.b], best.speed)) end
    return nil
  end
  local b, i = best.b, best.i
  local p0, p1 = rel(i - 1, b), rel(i, b)
  local dir = unit(sub(p1, p0))
  -- the arc: the samples either side of the fastest step, when the weapon turned enough between them
  local n, how
  local pa = h[i - 2] and rel(i - 2, b)
  local pc = h[i + 1] and rel(i + 1, b)
  local u, w = pa and sub(p0, pa), pc and sub(pc, p1)
  for _, pair in ipairs({ { u, sub(p1, p0) }, { sub(p1, p0), w }, { u, w } }) do
    if not n and pair[1] and pair[2] then
      local c = cross(pair[1], pair[2])
      if len(c) > 0.2 * len(pair[1]) * len(pair[2]) then n, how = unit(c), "weapon arc" end
    end
  end
  if not n and dir and fwd then
    local c = cross(dir, fwd)
    if len(c) > 0.3 then n, how = unit(c), "weapon swing x forward" end
  end
  if not (n and dir) then return nil end
  return { dir = dir, n = n, how = how, at = h[i].p[b], speed = best.speed, bone = swing.bones[b], fwd = fwd,
    ago = os.clock() - h[i].t, pose = h[i].pose }
end

end
