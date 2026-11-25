-- Living-hit decal placement, healing, and cleanup.
-- The owner supplies live guards; these are initialized after the scripts load.
return function(M, d)
local native, cfg, log, load_obj = d.native, d.cfg, d.log, d.load_obj
local vec, sub, add, scale, len, norm, dot, cross = d.vec, d.sub, d.add, d.scale, d.len, d.norm, d.dot, d.cross
local bone_loc, command, triple, num, pick, niagara, FX = d.bone_loc, d.command, d.triple, d.num, d.pick, d.niagara, d.FX
local function try(...) local f = d.guards(); return f(...) end
local function valid(...) local _, f = d.guards(); return f(...) end
local function v3(...) local _, _, f = d.guards(); return f(...) end
local MARK_AT = d.MARK_AT
-- ---- a living hit's mark (tune.gore.hitMarks) ----
-- A hit she lives through leaves a slash of blood on her skin, no cut: a deferred decal (the cinematic floor blood's
-- streaky one, stretched along the swing) on the skin where the hit landed, riding the bone that moves that skin. The
-- DLL finds that skin ("m": a ray from the nearest part's bone axis out through the physics hit, the first skin it
-- leaves through, and its normal), so the mark sits on her and not on the capsule the hit was reported on. Its box
-- reaches only a share of the part's radius into her, so it never shows on the far side or on the arm beside her.
-- Marks heal (heal_marks): each remembers her HP bar before its hit and fades once healing brings it back past that;
-- all go when she recovers (cleanup)
M.mk = { list = {} }
M.decal_seen = {}   -- outfit mesh address -> true once its decal setup is logged (hit_mark)
M.MARK_AT = MARK_AT

M.MARK_DECALS = {
  "/Game/Art/FX/Enviroment/WasteLand/Cinematic/MV_Nest_RavenBattle_After_QTE_success/MI_FloorBloodDecal_5.MI_FloorBloodDecal_5",
}
-- its shape: the floor blood's own (BaseTex) is a lumpy puddle with a normal map, which squeezed to a slash on her
-- skin read as a dent. The mark gets its own instance with the game's sword scar instead (a long thin streak, 64 x 512,
-- along the decal's Y) and no normal relief
M.MARK_SLASH = { "/Game/Art/FX/Tex/Decal/T_A_SwordScars_01.T_A_SwordScars_01" }

-- the skin under a hit (sbslice "m"): at, where the game says she was hit (world); dir, the blow's motion or nil;
-- reach, how far off her parts' bone axes the hit may lie (40 cm). A table { hit, n (unit), bone (index), part (a
-- MARK_AT row), mat (the material slot of the skin's section), u, v (its UV, channel 0) }, or nil and why. mat and
-- u / v are nil when the DLL couldn't tell (no CPU copy of the UVs)
function M.skin_query(mesh, at, dir, reach_cm)
  if native.state ~= "ready" then return nil, "sbslice not ready" end
  if not (at and valid(mesh)) then return nil, "no hit" end
  -- the part: the bone segment nearest the hit
  local best, bd, bc
  for _, w in ipairs(M.MARK_AT) do
    local a, b = bone_loc(mesh, w.bone), bone_loc(mesh, w.to)
    if a and b then
      a, b = vec(a.X, a.Y, a.Z), vec(b.X, b.Y, b.Z)
      local ab = sub(b, a)
      local t = math.max(0, math.min(1, dot(sub(at, a), ab) / math.max(dot(ab, ab), 1e-4)))
      local p = add(a, scale(ab, t))
      local d = len(sub(at, p))
      if not bd or d < bd then best, bd, bc = w, d, p end
    end
  end
  if not best or bd > (reach_cm or 40) then
    return nil, string.format("no part of her within %d cm of %s", reach_cm or 40, v3(at))
  end
  local out = norm(sub(at, bc)) or (dir and norm(scale(dir, -1))) or vec(1, 0, 0)
  local reach = math.min(math.max(bd + 8, 12), 30)
  local r = command(string.format("m%x,0,%x", mesh:GetAddress(), math.floor(reach + 0.5)), bc, out)
  local hit, n = triple(r, "hit", 1), triple(r, "n", 0.01)
  if r:sub(1, 2) ~= "ok" or not (hit and n) then return nil, r end
  local u, v = r:match(" uv=(%-?[%d.]+),(%-?[%d.]+)")
  return { hit = hit, n = norm(n) or out, bone = num(r, "bone"), part = best, mat = num(r, "mat"),
    u = tonumber(u), v = tonumber(v), out = num(r, "out") }
end

-- The procedural scar follows the skin around the impact. Adapted from troubling's contribution.
function M.skin_ray(mesh, origin, dir, reach_cm)
  if native.state ~= "ready" or not (valid(mesh) and origin and dir) then return nil end
  local r = command(string.format("m%x,0,%x", mesh:GetAddress(), math.max(1, math.floor(reach_cm + 0.5))), origin, dir)
  local hit, n = triple(r, "hit", 1), triple(r, "n", 0.01)
  if r:sub(1, 2) ~= "ok" or not (hit and n) then return nil end
  return { hit = hit, n = norm(n) or dir, bone = num(r, "bone") }
end

-- ---- the slash itself, a wound laid on her (hitMarks.wound, the default) ----
-- A decal on her (the sword scar's streak, Blood and Dirt's blood on her outfit) never showed on what she wears in
-- play (reported twice), and Eve's outfits are her body mesh. The slash is now a thin wound of the stumps' meat, a
-- lens along the blade's path laid a hair over her outermost surface: the DLL's ray finds her skin out from the bone,
-- then steps on out through what she wears over it (up to two layers, 6 cm each, facing the same way), at the slash's
-- middle and both ends; the points between follow the curve those three give (a limb's round, a chest's flat). It
-- rides the bone under it, heals as the marks do (shrinks away) and goes when she is up again
local function slash_actor(pawn, at)
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  local cls = load_obj("/Script/Engine.StaticMeshActor")
  local pcls = load_obj("/Script/ProceduralMeshComponent.ProceduralMeshComponent")
  if not (valid(gs) and valid(cls) and valid(pcls)) then return nil end
  local tm = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = at, Scale3D = vec(1, 1, 1) }
  local a = try(function()
    local x = gs:BeginDeferredActorSpawnFromClass(pawn, cls, tm, 1, nil)
    if not valid(x) then return nil end
    return gs:FinishSpawningActor(x, tm)
  end)
  if not valid(a) then return nil end
  local root = try(function() return a.StaticMeshComponent end)
  if valid(root) then
    -- (a spawned StaticMeshActor is static: it can't follow a bone until it is movable)
    try(function() root:SetMobility(2) end)
    try(function() root:SetCollisionEnabled(0) end)
  end
  local pmc = try(function()
    return a:AddComponentByClass(pcls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }, false)
  end)
  if not valid(pmc) then try(function() a:K2_DestroyActor() end); return nil end
  try(function() pmc:SetCollisionEnabled(0) end)
  try(function() pmc:SetCastShadow(false) end)
  try(function() pmc:SetReceivesDecals(false) end)
  return a, pmc
end
-- the stumps' meat (capMaterial), its glow held down as theirs (capBloodColor), or hitMarks.color
local function slash_material(pmc)
  local c = cfg().hitMarks or {}
  local mat = load_obj(c.material or M.cap_mat(true))
  if not mat then return false end
  local col = c.color or cfg().capBloodColor
  local mid = try(function() return pmc:CreateDynamicMaterialInstance(0, mat, FName("None")) end)
  if valid(mid) then
    if type(col) == "table" then
      try(function() mid:SetVectorParameterValue(FName("BloodColor"), { R = col[1] or 0, G = col[2] or 0, B = col[3] or 0, A = 1 }) end)
    end
  else
    try(function() pmc:SetMaterial(0, mat) end)
  end
  return true
end
-- the points of the slash: K along it, each { p (on her outermost surface), n }. q: skin_query's answer, along: unit,
-- in her surface, half_l: cm. The rays used, and how many layers out her outfit's surface was
function M.slash_points(mesh, q, along, half_l, K)
  local part = q.part
  local A, B = bone_loc(mesh, part.bone), bone_loc(mesh, part.to)
  if not (A and B) then return nil, 0, 0 end
  A, B = vec(A.X, A.Y, A.Z), vec(B.X, B.Y, B.Z)
  local ab = sub(B, A)
  local L2 = math.max(dot(ab, ab), 1e-4)
  local ax = norm(ab)
  local function axis_at(p)
    local t = math.max(0, math.min(1, dot(sub(p, A), ab) / L2))
    return add(A, scale(ab, t))
  end
  local function radial(p, o)
    local v = sub(p, o)
    if ax then v = sub(v, scale(ax, dot(v, ax))) end
    return norm(v)
  end
  local rays = 0
  local function ray(o, d, reach) rays = rays + 1; return M.skin_ray(mesh, o, d, reach) end
  local function outward(h, d, most)
    local n = 0
    for _ = 1, most do
      local nx = ray(add(h.hit, scale(d, 0.4)), d, 6)
      if not (nx and dot(nx.n, d) > 0.3) then break end
      h, n = nx, n + 1
    end
    return h, n
  end
  -- the middle: skin_query's skin, then out through her outfit
  local ac = axis_at(q.hit)
  local dc = radial(q.hit, ac) or q.n
  local mid, layers = outward({ hit = q.hit, n = q.n }, dc, math.max(0, math.min(2, math.floor(tonumber((cfg().hitMarks or {}).woundLayers) or 0))))
  local rc = len(sub(mid.hit, ac))
  local reach = math.min(math.max(rc + 10, 15), 40)
  -- both ends: from the bone out, as far out as the middle went
  local ends = {}
  for _, t in ipairs({ -1, 1 }) do
    local s = add(mid.hit, scale(along, t * half_l))
    local ap = axis_at(s)
    local dr = radial(s, ap) or dc
    local h = ray(ap, dr, reach)
    if h and layers > 0 then h = outward(h, dr, layers) end
    -- (nothing there, or something far off her curve, another part of her: her middle's distance from the bone)
    local guess = add(ap, scale(dr, rc))
    if not h or len(sub(h.hit, guess)) > 6 then h = { hit = guess, n = dr } end
    ends[t] = { ap = ap, dr = dr, r = len(sub(h.hit, ap)), h = h }
  end
  -- every point: its distance from the bone off a parabola through the ends' and the middle's, along its own spoke
  local r0, rm, rp = rc, ends[-1].r, ends[1].r
  local b, c2 = (rp - rm) * 0.5, (rp + rm) * 0.5 - rc
  local out = {}
  K = math.max(3, math.min(11, math.floor(K or 7)))
  if K % 2 == 0 then K = K + 1 end
  for i = 1, K do
    local t = -1 + 2 * (i - 1) / (K - 1)
    if i == 1 then out[i] = { p = ends[-1].h.hit, n = ends[-1].h.n }
    elseif i == K then out[i] = { p = ends[1].h.hit, n = ends[1].h.n }
    elseif math.abs(t) < 1e-6 then out[i] = { p = mid.hit, n = mid.n }
    else
      local s = add(mid.hit, scale(along, t * half_l))
      local ap = axis_at(s)
      local dr = radial(s, ap) or dc
      local r = r0 + b * t + c2 * t * t
      out[i] = { p = add(ap, scale(dr, r)), n = dr }
    end
  end
  return out, rays, layers
end
-- the wound's mesh from those points: a lens, half_w at its widest, its floor a little under its lips, lifted lift cm
-- off her. Both windings (the meat isn't two-sided; seen from her outside, one of them faces the eye). Positions
-- relative to o
function M.slash_mesh(pts, half_w, lift, o)
  local K = #pts
  local verts, normals, uvs, colors, tangents, tris = {}, {}, {}, {}, {}, {}
  for i = 1, K do
    local t = -1 + 2 * (i - 1) / (K - 1)
    local tan = norm(sub(pts[math.min(K, i + 1)].p, pts[math.max(1, i - 1)].p)) or vec(1, 0, 0)
    local n = pts[i].n
    local side = norm(cross(n, tan)) or norm(cross(vec(0, 0, 1), tan)) or vec(0, 1, 0)
    local w = half_w * math.max(0.06, math.sqrt(math.max(0, 1 - t * t)))
    local lip = add(pts[i].p, scale(n, lift))
    local floor = add(pts[i].p, scale(n, lift * 0.35))
    local u = (t + 1) * 0.5
    for j, p in ipairs({ add(lip, scale(side, -w)), floor, add(lip, scale(side, w)) }) do
      verts[#verts + 1] = sub(p, o)
      normals[#normals + 1] = n
      uvs[#uvs + 1] = { X = u, Y = (j - 1) * 0.5 }
      colors[#colors + 1] = { R = 1, G = 1, B = 1, A = 1 }
      tangents[#tangents + 1] = { TangentX = tan, bFlipTangentY = false }
    end
  end
  for i = 0, K - 2 do
    local a, b = i * 3, (i + 1) * 3
    for _, s in ipairs({ 0, 1 }) do
      local p0, p1, p2, p3 = a + s, b + s, a + s + 1, b + s + 1
      for _, tri in ipairs({ { p0, p1, p2 }, { p1, p3, p2 }, { p0, p2, p1 }, { p1, p2, p3 } }) do
        tris[#tris + 1] = tri[1]; tris[#tris + 1] = tri[2]; tris[#tris + 1] = tri[3]
      end
    end
  end
  return verts, tris, normals, uvs, colors, tangents
end
-- the wound on her: an actor of its own riding bone ride, or nil and why
local function slash_wound(pawn, mesh, q, along, half_l, half_w, ride)
  local c = cfg().hitMarks or {}
  local t0 = os.clock()
  local pts, rays, layers = M.slash_points(mesh, q, along, half_l, c.samples or 7)
  if not pts then return nil, "no bone segment" end
  local o = pts[math.floor(#pts / 2) + 1].p
  local verts, tris, normals, uvs, colors, tangents = M.slash_mesh(pts, half_w, c.lift or 0.18, o)
  local a, pmc = slash_actor(pawn, o)
  if not a then return nil, "no actor" end
  local made = try(function() pmc:CreateMeshSection_LinearColor(0, verts, tris, normals, uvs, {}, {}, {}, colors, tangents, false); return true end)
    or try(function() pmc:CreateMeshSection_LinearColor(0, verts, tris, normals, uvs, colors, tangents, false); return true end)
  if not made then try(function() a:K2_DestroyActor() end); return nil, "no mesh section" end
  if not slash_material(pmc) then try(function() a:K2_DestroyActor() end); return nil, "no scar material" end
  -- KeepWorldPosition (1) for location, rotation and scale: it rides the bone where it was laid
  local attached = try(function() return a:K2_AttachToComponent(mesh, FName(ride), 1, 1, 1, false) ~= false end)
  if not attached then try(function() a:K2_DestroyActor() end); return nil, "cannot attach to bone" end
  return a, string.format("%d points, %d ray%s, %d layer%s out (what she wears), %.1f ms", #pts, rays, rays == 1 and "" or "s",
    layers, layers == 1 and "" or "s", (os.clock() - t0) * 1000)
end

local function mark_object(m)
  if m.held then return d.held(m.held) and m.held.obj or nil end
  return valid(m.d) and m.d or nil
end

local function drop_mark(m)
  local object = mark_object(m)
  if not object then return end
  if m.held then try(function() object:K2_DestroyActor() end)
  else try(function() object:K2_DestroyComponent(object) end) end
end

local function record_mark(m, cap)
  local list = M.mk.list
  list[#list + 1] = m
  while #list > math.max(1, cap or 12) do drop_mark(table.remove(list, 1)) end
end

-- at: where the game says she was hit (world), dir: the blade's motion there (the slash runs along it), or nil;
-- pre: her HP bar before the hit (0-1), or nil. True when a mark went on
function M.hit_mark(pawn, mesh, at, dir, pre)
  local g = cfg()
  local c = g.hitMarks or {}
  if g.enabled == false or c.enabled == false or not (at and valid(mesh)) then return false end
  if native.state ~= "ready" then return false end
  local q, why = M.skin_query(mesh, at, dir, c.reach or 40)
  if not q then log("hit mark skipped: " .. why); return false end
  local best, hit, n = q.part, q.hit, q.n
  local bi = q.bone
  local ride = bi and bi >= 0 and try(function() return mesh:GetBoneName(bi):ToString() end) or best.bone
  if ride == "None" then ride = best.bone end
  -- along the skin: the swing's motion, flattened onto it, else any way round
  local along = dir and norm(sub(dir, scale(n, dot(dir, n))))
  if not along then
    local side = math.abs(n.Z) < 0.9 and vec(0, 0, 1) or vec(1, 0, 0)
    local x, y = norm(cross(n, side)), nil
    y = cross(n, x)
    local a = math.random() * 2 * math.pi
    along = norm(add(scale(x, math.cos(a)), scale(y, math.sin(a)))) or x
  end
  -- its size: a slash of length x width, kept within the part's curve (a slash round a forearm would leave the box)
  local k = (c.scale or 1.0) * (0.75 + math.random() * 0.5)
  local half_l = math.min((c.length or 14) * 0.5 * k, best.r * 1.3)
  local half_w = (c.width or 4) * 0.5 * k
  if c.scarMesh and d.hold then
    local actor, reason = slash_wound(pawn, mesh, q, along, half_l,
      math.min(half_w, math.max(0.1, (c.scarWidth or 0.35) * k)), ride)
    if actor then
      local held = d.hold(actor)
      if held then
        record_mark({ held = held, pre = pre, low = pre }, c.max)
        if g.blood ~= false and c.blood ~= false then niagara(FX.hit, pawn, nil, hit, false) end
        log("scar on " .. ride .. " (" .. reason .. ")")
        return true
      end
      try(function() actor:K2_DestroyActor() end)
      reason = "actor lifetime unavailable"
    end
    log("scar using decal: " .. tostring(reason))
  end
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  local km = load_obj("/Script/Engine.Default__KismetMathLibrary")
  local mat = load_obj(pick(c.decals or M.MARK_DECALS))
  if not (gs and km and mat) then log("hit mark skipped: no decal material"); return false end
  local depth = math.max(1.5, best.r * (c.depth or 0.5))
  -- the decal projects along its X: into her skin; its Y runs along the slash
  local rot = try(function() local q = km:MakeRotFromXY(scale(n, -1), along); return { Pitch = q.Pitch, Yaw = q.Yaw, Roll = q.Roll } end)
  if not rot then log("hit mark skipped: no rotation"); return false end
  -- marks spawned on CH_P_EVE_30 (SBPR) and never showed: once per outfit mesh, decals are switched on if they were
  -- off, and the log says how its materials take decals (deferred decals skip translucent materials, and DBuffer
  -- decals skip a material whose MaterialDecalResponse is None, 0)
  local sk = try(function() return mesh.SkeletalMesh end)
  local ska = valid(sk) and try(function() return sk:GetAddress() end)
  -- This flag belongs to the component, not the skeletal asset. A replacement
  -- mesh can use an already-logged asset while still having decals disabled.
  local rd = try(function() return mesh.bReceivesDecals end)
  if rd == false then try(function() mesh:SetReceivesDecals(true) end) end
  if ska and not M.decal_seen[ska] then
    M.decal_seen[ska] = true
    local ms = {}
    for i = 0, (try(function() return mesh:GetNumMaterials() end) or 0) - 1 do
      local m = try(function() return mesh:GetMaterial(i) end)
      local base = valid(m) and try(function() return m:GetBaseMaterial() end)
      if valid(base) then
        ms[#ms + 1] = string.format("%s blend %s response %s", try(function() return base:GetFName():ToString() end) or "?",
          tostring(try(function() return base.BlendMode end)), tostring(try(function() return base.MaterialDecalResponse end)))
      end
    end
    local dm = try(function() return mat:GetBaseMaterial() end)
    log(string.format("hit marks on %s: receives decals %s%s; the mark's material blend %s; %s",
      try(function() return sk:GetFName():ToString() end) or "?", tostring(rd),
      rd == false and " (switched on)" or "", tostring(valid(dm) and try(function() return dm.DecalBlendMode end)),
      table.concat(ms, ", ")))
  end
  -- EAttachLocation::KeepWorldPosition = 1: it rides the bone at the skin's point and turn
  local d = try(function() return gs:SpawnDecalAttached(mat, vec(depth, half_l, half_w), mesh, FName(ride), hit, rot, 1, 0) end)
  if not valid(d) then log("hit mark skipped: the decal didn't spawn"); return false end
  local tex = c.slash ~= false and load_obj(pick(c.slash or M.MARK_SLASH))
  if tex then
    local mid = try(function() return d:CreateDynamicMaterialInstance() end)
    if not (valid(mid) and try(function()
      mid:SetTextureParameterValue(FName("BaseTex"), tex)
      mid:SetScalarParameterValue(FName("NormalStrength"), 0)
      return true
    end)) then log("hit mark: no instance of its own, the puddle's shape stays") end
  end
  record_mark({ d = d, pre = pre, low = pre }, c.max)
  if g.blood ~= false and c.blood ~= false then niagara(FX.hit, pawn, nil, hit, false) end
  log(string.format("hit mark on %s (rides %s): %.0f x %.1f cm at %s, %.1f cm out of the bone, %s off the reported hit, HP bar before %s",
    best.bone, ride, half_l * 2, half_w * 2, v3(hit), q.out or -1, string.format("%.1f cm", len(sub(hit, at))),
    pre and string.format("%.3f", pre) or "?"))
  return true
end

-- her HP bar now (0-1): marks whose hit healing has undone fade out over healFade s, then go. A mark counts as healed
-- once the bar has risen from its lowest since the hit and reached the reading it had before it (a hit that took
-- nothing waits for her recovery; one with no reading before it, for a full bar)
function M.heal_marks(pct)
  local c = cfg().hitMarks or {}
  local keep, now = {}, os.clock()
  for _, m in ipairs(M.mk.list) do
    local object = mark_object(m)
    if not object then
      -- gone with her mesh
    elseif m.gone then
      if now >= m.gone then
        drop_mark(m)
      else
        if m.held then
          local factor = math.max(0.02, (m.gone - now) / m.fade)
          try(function() object:SetActorScale3D(vec(factor, factor, factor)) end)
        end
        keep[#keep + 1] = m
      end
    else
      if pct then
        m.low = math.min(m.low or pct, pct)
        if pct > m.low + 0.01 and pct >= (m.pre or 0.98) - 0.005 then
          local f = math.max(0.1, c.healFade or 2.5)
          if m.held then m.fade = f + 0.2
          else try(function() object:SetFadeOut(0, f, false) end) end
          m.gone = now + f + 0.2
          log(string.format("hit mark healed: HP bar %.3f (was %s before the hit, %.3f at its lowest)", pct,
            m.pre and string.format("%.3f", m.pre) or "?", m.low))
        end
      end
      keep[#keep + 1] = m
    end
  end
  M.mk.list = keep
end

-- every mark off her at once (her recovery, a respawn)
function M.clear_marks()
  local n = #M.mk.list
  for _, m in ipairs(M.mk.list) do drop_mark(m) end
  M.mk.list = {}
  if n > 0 then log(string.format("removed %d hit marks", n)) end
end
function M.marks() return #M.mk.list end


end
