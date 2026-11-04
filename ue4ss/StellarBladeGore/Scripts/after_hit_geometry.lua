-- Geometry of a weapon or hand crossing body segments after death.
return function(try, vof, SWING_AT, sub, dot, dist, seg_dist)
  local function after_radius(b)
    if b == "Bip001-Head" then return 12 end
    if b == "Bip001-Neck" then return 9 end
    if b == "Bip001-Spine" or b == "Bip001-Spine1" or b == "Bip001-Spine2" then return 16 end
    if b:find("UpperArm") or b:find("Forearm") then return 8 end
    if b:find("Hand") then return 10 end
    if b:find("Thigh") or b:find("Calf") then return 9 end
    if b:find("Foot") then return 8 end
    return 8
  end
  local function seg_seg(p1, q1, p2, q2)
    local d1 = sub(q1, p1)
    local d2 = sub(q2, p2)
    local r = sub(p1, p2)
    local a = dot(d1, d1)
    local e = dot(d2, d2)
    if a < 1e-8 and e < 1e-8 then return dist(p1, p2), p1, p2 end
    if a < 1e-8 then
      local t = math.max(0, math.min(1, dot(sub(p1, p2), d2) / math.max(e, 1e-4)))
      local cc = { X = p2.X + d2.X * t, Y = p2.Y + d2.Y * t, Z = p2.Z + d2.Z * t }
      return dist(p1, cc), p1, cc
    end
    if e < 1e-8 then
      local s = math.max(0, math.min(1, dot(sub(p2, p1), d1) / math.max(a, 1e-4)))
      local cc = { X = p1.X + d1.X * s, Y = p1.Y + d1.Y * s, Z = p1.Z + d1.Z * s }
      return dist(cc, p2), cc, p2
    end
    local f = dot(d2, r)
    local cc0 = dot(d1, r)
    local b = dot(d1, d2)
    local denom = a * e - b * b
    local s = denom > 1e-8 and math.max(0, math.min(1, (b * f - cc0 * e) / denom)) or 0
    local t = math.max(0, math.min(1, (b * s + f) / e))
    s = math.max(0, math.min(1, (b * t - cc0) / math.max(a, 1e-8)))
    local c1 = { X = p1.X + d1.X * s, Y = p1.Y + d1.Y * s, Z = p1.Z + d1.Z * s }
    local c2 = { X = p2.X + d2.X * t, Y = p2.Y + d2.Y * t, Z = p2.Z + d2.Z * t }
    return dist(c1, c2), c1, c2
  end
  return function(mesh, best, cfgReach)
    local at, d, bone, allow
  do
    -- Body segments in world space: full limb segments where SWING_AT names both ends, spheres elsewhere.
    -- A swing must cross one of these within its anatomical radius (+4 cm slack, capped by the configured
    -- reach), not merely pass near a joint point. Missing sockets are skipped: no geometry, no hit.
    local segs = {}
    local head = try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Head"))) end)
    if head then segs[#segs + 1] = { a = head, b = nil, bone = "Bip001-Head", r = after_radius("Bip001-Head") } end
    for _, e in ipairs(SWING_AT) do
      if e[3] then
        local a, b = try(function() return vof(mesh:GetSocketLocation(FName(e[1]))) end),
          try(function() return vof(mesh:GetSocketLocation(FName(e[3]))) end)
        if a and b then segs[#segs + 1] = { a = a, b = b, bone = e[1], r = after_radius(e[1]) } end
      else
        local a = try(function() return vof(mesh:GetSocketLocation(FName(e[1]))) end)
        if a then segs[#segs + 1] = { a = a, b = nil, bone = e[1], r = after_radius(e[1]) } end
      end
    end
    -- Blade sweep: the blade segment at sampled fractions of this step (every ~15 cm of travel, up to 8
    -- samples), so a fast swing cannot tunnel past a limb between endpoints. Hand/claw motion (no blade
    -- mesh) is a single moving point instead. Weapon bounds are used as-is; only the tolerance shrank.
    local blades = {}
    if best.steps then
      local A0, A1, B0, B1
      if best.steps[1] and best.steps[3] then
        A0, A1, B0, B1 = best.steps[1][1], best.steps[1][2], best.steps[3][1], best.steps[3][2]
      end
      if A0 and A1 and B0 and B1 then
        local travel = math.max(dist(A0, A1), dist(B0, B1))
        local cuts = math.max(1, math.min(8, math.ceil(travel / 15)))
        for j = 0, cuts do
          local f = j / cuts
          blades[#blades + 1] = {
            a = { X = A0.X + (A1.X - A0.X) * f, Y = A0.Y + (A1.Y - A0.Y) * f, Z = A0.Z + (A1.Z - A0.Z) * f },
            b = { X = B0.X + (B1.X - B0.X) * f, Y = B0.Y + (B1.Y - B0.Y) * f, Z = B0.Z + (B1.Z - B0.Z) * f },
          }
        end
      else
        for _, st in ipairs(best.steps) do blades[#blades + 1] = { a = st[1], b = st[1], q = st[2] } end
      end
    end
    for _, s in ipairs(segs) do
      local lim = math.min(s.r + 4, cfgReach)
      if best.steps and #blades > 0 then
        for _, bl in ipairs(blades) do
          local dd, c2
          if bl.q then
            dd = s.b and select(1, seg_seg(bl.a, bl.q, s.a, s.b)) or seg_dist(bl.a, bl.q, s.a)
            c2 = s.a
          elseif s.b then
            local closest
            dd, closest, c2 = seg_seg(bl.a, bl.b, s.a, s.b)
          else
            local da = seg_dist(bl.a, bl.b, s.a)
            dd, c2 = da, s.a
          end
          if dd and (not d or dd - lim < d - allow) then at, d, bone, allow = c2, dd, s.bone, lim end
        end
        for _, st in ipairs(best.steps) do
          local dd, c2
          if s.b then
            local closest
            dd, closest, c2 = seg_seg(st[1], st[2], s.a, s.b)
          else dd, c2 = seg_dist(st[1], st[2], s.a), s.a end
          if dd and (not d or dd - lim < d - allow) then at, d, bone, allow = c2, dd, s.bone, lim end
        end
      else
        local dd, c2
        if s.b then
          local closest
          dd, closest, c2 = seg_seg(best.p, best.q, s.a, s.b)
        else dd, c2 = seg_dist(best.p, best.q, s.a), s.a end
        if dd and (not d or dd - lim < d - allow) then at, d, bone, allow = c2, dd, s.bone, lim end
      end
    end
  end
    return at, d, bone, allow
  end
end
