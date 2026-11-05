-- Smash target selection and impact coverage geometry.
return function(M, PARTS, cfg, get_guards, get_cuts, addr, already_cut, pick, bone_loc, vec, add, sub, scale, len, dot)
-- the part a blunt blow at `at` smashes: the arm, leg, head or upper body whose bone runs nearest it, not one already
-- off. With no blow (smash.always) the kind is rolled on the death odds (tune.gore.death: limb, head,
-- torso; a split's share left out), the limb at random: a pick among the parts alone never took the head in 50 F6
-- deaths, and never her body (playtest)
M.SMASH_SEG = { ["Bip001-Spine1"] = { "Bip001-Pelvis", "Bip001-Neck" } }
-- Approximate flesh around the bone lines, in cm. Mesh shake positions can lie outside the skin, especially for
-- large impacts; comparing only the skeleton's centre lines made a nearby forearm beat the face or chest.
M.SMASH_RADIUS = { head = 14, torso = 14, arm = 4, leg = 6 }
-- Keep clear hits on the struck part. Only nearly tied, surface-level candidates may vary.
function M.smash_choose(candidates, impactRadius)
  local best
  for _, c in ipairs(candidates) do
    if impactRadius and impactRadius > 0 then c.area = M.smashed.overlap(impactRadius, c.radius, c.d) end
    if not best or (c.area and c.area > best.area)
      or ((not c.area or c.area == best.area) and (c.surface < best.surface or (c.surface == best.surface and c.d < best.d))) then best = c end
  end
  if not best then return nil end
  if impactRadius and impactRadius > 0 then return best end
  local alternatives = {}
  if best.d >= best.radius - 3 then
    for _, c in ipairs(candidates) do
      if c ~= best and c.surface <= best.surface + 2 and c.d <= best.d + 2 then
        alternatives[#alternatives + 1] = c
      end
    end
  end
  if #alternatives > 0 and math.random() < 0.25 then return alternatives[math.random(#alternatives)] end
  return best
end
function M.smash_part(mesh, at, onlyKind, pose, impactRadius)
  local try, valid = get_guards()
  local cands = {}
  for bone, p in pairs(PARTS) do
    local index = valid(mesh) and try(function() return mesh:GetBoneIndex(FName(bone)) end)
    if type(index) == "number" and index >= 0 and not already_cut(mesh, bone)
      and (not onlyKind or p.kind == onlyKind or (onlyKind == "nonTorso" and p.kind ~= "torso")) then cands[#cands + 1] = { bone = bone, p = p } end
  end
  table.sort(cands, function(x, y) return x.bone < y.bone end)
  -- Optional weights choose a kind first; location still chooses the nearest part within that kind.
  local s = cfg().smash or {}
  if not onlyKind and s.overrideTargets == true then
    local available, weights, sum = {}, s.targetWeights or {}, 0
    for _, c in ipairs(cands) do available[c.p.kind] = true end
    local options = {}
    for _, kind in ipairs({"limb", "head", "torso"}) do
      local w = available[kind] and M.smashed.number(weights[kind], 1, 0, 100) or 0
      options[#options + 1] = {kind=kind, weight=w}; sum = sum + w
    end
    if sum > 0 then
      local r, selected = math.random() * sum, nil
      for _, item in ipairs(options) do
        r = r - item.weight
        if item.weight > 0 and r <= 0 then selected = item.kind; break end
      end
      if selected then return M.smash_part(mesh, at, selected, pose, impactRadius) end
    end
  end
  if not at and onlyKind then
    local c = pick(cands)
    return c and c.bone, nil, c and c.p.kind
  end
  if not at then
    local w = cfg().death or {}
    local odds = { limb = tonumber(w.limb) or 42, head = tonumber(w.head) or 25, torso = tonumber(w.torso) or 15 }
    local by = {}
    for _, c in ipairs(cands) do by[c.p.kind] = by[c.p.kind] or {}; table.insert(by[c.p.kind], c.bone) end
    local sum = 0
    for k, x in pairs(odds) do if not by[k] then odds[k] = 0 else sum = sum + math.max(x, 0) end end
    if sum <= 0 then return nil end
    local r = math.random() * sum
    for _, k in ipairs({ "limb", "head", "torso" }) do
      r = r - math.max(odds[k], 0)
      if odds[k] > 0 and r <= 0 and by[k] then return pick(by[k]), nil, k end
    end
    return nil
  end
  local candidates, distances = {}, nil
  distances = {}
  local function bl(b, joint)
    local x = pose and pose[b]
    if x and x.t then return x.t end
    if joint then return M.joint(mesh, b) end
    return bone_loc(mesh, b)
  end
  for _, c in ipairs(cands) do
    local bone, p = c.bone, c.p
    local seg = M.SMASH_SEG[bone]
    local a, b = bl(seg and seg[1] or p.from or bone, false), bl(seg and seg[2] or p.to, true)
    -- (the head's own bone is the skull's base: its segment runs on up past it, to the top of her head)
    if a and b and p.kind == "head" then b = vec(b.X + (b.X - a.X) * 3, b.Y + (b.Y - a.Y) * 3, b.Z + (b.Z - a.Z) * 3) end
    if a and b then
      a, b = vec(a.X, a.Y, a.Z), vec(b.X, b.Y, b.Z)
      local ab = sub(b, a)
      local t = math.max(0, math.min(1, dot(sub(at, a), ab) / math.max(dot(ab, ab), 1e-4)))
      local d = len(sub(at, add(a, scale(ab, t))))
      local radius = M.SMASH_RADIUS[p.kind == "limb" and (bone:find("Arm") or bone:find("Forearm")) and "arm"
        or p.kind == "limb" and "leg" or p.kind] or 0
      local surface = math.max(0, d - radius)
      distances[#distances + 1] = string.format("%s %.0f/%.0f", bone, d, surface)
      candidates[#candidates + 1] = { bone = bone, d = d, surface = surface, radius = radius }
    end
  end
  local best = M.smash_choose(candidates, impactRadius)
  return best and best.bone, best and best.d, best and PARTS[best.bone].kind, table.concat(distances, ", ")
end
-- Circular contact patches against approximate flesh cross-sections. This is a bounded geometric
-- estimate, not a mesh/physics query; all work runs once at smash selection, never every frame.
function M.smashed.overlap(a, b, d)
  if a <= 0 or b <= 0 or d >= a + b then return 0 end
  if d <= math.abs(a - b) then return math.pi * math.min(a, b)^2 end
  local x = math.max(-1, math.min(1, (d*d + a*a - b*b) / (2*d*a)))
  local y = math.max(-1, math.min(1, (d*d + b*b - a*a) / (2*d*b)))
  return math.max(0, a*a*math.acos(x) + b*b*math.acos(y)
    - 0.5*math.sqrt(math.max(0, (-d+a+b)*(d+a-b)*(d-a+b)*(d+a+b))))
end
function M.smashed.coverage(mesh, h)
  local radius = M.smashed.number(h and h.impactRadius, 0, 0, 500)
  if radius <= 0 or not (h and h.loc) then return 0, radius end
  local function at(b)
    local p = h.pose and h.pose[b]
    return p and p.t or bone_loc(mesh, b)
  end
  local head, chest, pelvis = at("Bip001-Head"), at("Bip001-Spine2"), at("Bip001-Pelvis")
  local lt, lc, rt, rc = at("Bip001-L-Thigh"), at("Bip001-L-Calf"), at("Bip001-R-Thigh"), at("Bip001-R-Calf")
  if not (head and chest and pelvis and lt and lc and rt and rc) then return 0, radius end
  local zones = { {head, 14}, {chest, 18}, {pelvis, 16},
    {scale(add(lt, lc), 0.5), 10}, {scale(add(rt, rc), 0.5), 10} }
  local covered, total, core = 0, 0, 1
  for i, zone in ipairs(zones) do
    local area = math.pi * zone[2]^2
    local hit = M.smashed.overlap(radius, zone[2], len(sub(h.loc, zone[1])))
    covered, total = covered + hit, total + area
    if i == 2 or i == 3 then core = math.min(core, hit / area) end
  end
  -- Both upper and lower trunk must be covered; a small head/hand/foot hit cannot roll full-body.
  return math.max(0, math.min(1, covered / total * core)), radius
end
-- Advanced tune.lua values must never leave an endless spawn queue or invalid shapes in the physics scene.
function M.smashed.number(value, default, lo, hi)
  local n = tonumber(value)
  if not n or n ~= n or n == math.huge or n == -math.huge then n = default end
  return math.max(lo, math.min(hi, n))
end
function M.smashed.profile(mesh, bone)
  local try = get_guards()
  local s, p = cfg().smash or {}, M.SMASH_PARTS[bone]
  if not p then return { count = 0, size = 1, blood = 0 } end
  local weight = 0
  local ma = addr(mesh)
  for b, part in pairs(M.SMASH_PARTS) do
    if b == bone or try(function() return mesh:BoneIsChildOf(FName(b), FName(bone)) end) == true then
      local index = try(function() return mesh:GetBoneIndex(FName(b)) end)
      local gone = false
      for _, c in ipairs(get_cuts()) do
        -- A severed arm's forearm is outside the torso too, even when it was cut rather than smashed.
        if c.addr == ma and (c.bone == b or try(function() return mesh:BoneIsChildOf(FName(b), FName(c.bone)) end) == true) then
          gone = true; break
        end
      end
      if type(index) == "number" and index >= 0 and not gone then weight = weight + part[3] end
    end
  end
  local share = math.max(0, math.min(1, weight / p[2]))
  return { count = math.floor(M.smashed.number(s[p[1]], p[5] or p[2], 0, 64) * share),
    size = p[4], blood = weight }
end
-- Query the completed smash, separately from cuts: an ordinary waist cut keeps its struggle and voice.
function M.smashed.has(mesh, bone)
  local a = addr(mesh)
  if not a then return false end
  for _, c in ipairs(get_cuts()) do
    if c.addr == a and c.bone == bone and c.smashed then return true end
  end
  return false
end
end
