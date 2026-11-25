-- Post-death incontinence effect contributed by troubling. The stream and puddle use non-colliding meshes.
--
-- Once her hips have lain still (still s) and delay s have passed since she died:
--  * the stream (spray s, 2-3): from the skin between her legs (sbslice's ray out of her from between her hip joints,
--    down her body and a little forward; else a point that far), launched down her body and forward of her at up to
--    spraySpeed cm/s, rising to it, wavering, then weakening to a dribble. It falls under gravity to the floor; a few
--    droplets splash where it lands. Followed every tick from her hips as they lie (a thin glossy tube of its own)
--  * the puddle: from where the stream lands, it spreads as the stream runs and goes on spreading for grow s after it,
--    to size cm across (longer along her legs by stretch, or downhill on a slope), lumpy at its edge and growing
--    unevenly. It lies on the floor as traced round it (a ring of traces at the start): it follows the floor's
--    slope and bumps, and stops at a drop, a step or a wall. It lies lift cm over the floor, over the blood pools'
--    decals (those paint the floor itself; the puddle takes no decals), so it shows on top of her blood.
-- Both are meshes of their own, not decals (decals take their colour from the game's blood materials, red and
-- global). Their material is Tachy's character material (Base Color Tint, Desaturation, Brightness, Roughness Min/
-- Max, all known to take), her colour texture swapped for plain white where the parameter takes, tinted color.
-- Gone when she is up again or the level changes.
local M = {}
local ctx, try, valid
local log = function() end
function M.init(c)
  ctx, try, valid = c, c.try, c.valid
  log = function(s) c.log("fluid: " .. s) end
end
local function cfg() return ((ctx.tune.gore or {}).deathFluid) or {} end
local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local function add(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
local function sub(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
local function scale(a, s) return vec(a.X * s, a.Y * s, a.Z * s) end
local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function cross(a, b) return vec(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
local function len(a) return math.sqrt(dot(a, a)) end
local function norm(a) local l = len(a); return l > 1e-4 and scale(a, 1 / l) or nil end
local function num(x, d, lo, hi)
  x = tonumber(x)
  if not x or x ~= x then x = d end
  return math.max(lo, math.min(hi, x))
end
local GRAVITY = vec(0, 0, -980)

local st = {}

local function obj(p)
  local g = ctx.gore
  if g and g.guarded_asset then return g.guarded_asset(p) end
  return try(function() return StaticFindObject(p) end)
end
local function bone(mesh, b)
  return try(function() local v = mesh:GetSocketLocation(FName(b)); return vec(v.X, v.Y, v.Z) end)
end
-- between her legs, and the way her legs run from there (nil when it can't tell)
function M.between(mesh)
  local lt, rt = bone(mesh, "Bip001-L-Thigh"), bone(mesh, "Bip001-R-Thigh")
  local pel = bone(mesh, "Bip001-Pelvis")
  if not (lt and rt) or len(sub(lt, rt)) > 45 then return pel, nil end
  local hip = scale(add(lt, rt), 0.5)
  local lk, rk = bone(mesh, "Bip001-L-Calf"), bone(mesh, "Bip001-R-Calf")
  if lk and rk and len(sub(lk, lt)) < 70 and len(sub(rk, rt)) < 70 then
    local knee = scale(add(lk, rk), 0.5)
    local way = sub(knee, hip)
    return add(hip, scale(way, num(cfg().along, 0.3, 0, 0.8))), way
  end
  return hip, nil
end

-- her hips as they lie: { hip (between her hip joints), up (toward her chest), right (her right), front (the way her
-- belly faces), legs (toward her knees, or nil) }, or nil
function M.hips(mesh)
  local lt, rt = bone(mesh, "Bip001-L-Thigh"), bone(mesh, "Bip001-R-Thigh")
  if not (lt and rt) or len(sub(lt, rt)) > 45 then return nil end
  local hip = scale(add(lt, rt), 0.5)
  -- (her lower back: it stays with her hips through a waist cut, where Spine1 flies off with her upper body)
  local up
  for _, b in ipairs({ "Bip001-Spine", "Bip001-Spine1" }) do
    local p = not up and bone(mesh, b)
    local d = p and len(sub(p, hip))
    if d and d >= 5 and d <= 35 then up = norm(sub(p, hip)) end
  end
  local right = norm(sub(rt, lt))
  if not (up and right) then return nil end
  right = norm(sub(right, scale(up, dot(right, up)))) or right
  local front = norm(cross(up, right))
  if not front then return nil end
  local lk, rk = bone(mesh, "Bip001-L-Calf"), bone(mesh, "Bip001-R-Calf")
  local legs = lk and rk and norm(sub(scale(add(lk, rk), 0.5), hip)) or nil
  return { hip = hip, up = up, right = right, front = front, legs = legs }
end
local function at_frame(f, k) return add(f.hip, add(add(scale(f.up, k[1]), scale(f.right, k[2])), scale(f.front, k[3]))) end
local function dir_frame(f, k) return norm(add(add(scale(f.up, k[1]), scale(f.right, k[2])), scale(f.front, k[3]))) end
local function in_frame(f, p) local v = sub(p, f.hip); return { dot(v, f.up), dot(v, f.right), dot(v, f.front) } end

-- the stream's source on her, in her hips' frame { up, right, front } (cm), found once: sbslice's ray from between her
-- hip joints, down her body and a little forward, the first skin it leaves through; else the point that far out
function M.find_source(mesh, f)
  local guess = { -7.5, 0, 3.5 }
  local g = ctx.gore
  local d = dir_frame(f, { -0.85, 0, 0.5 })
  local h = g and g.skin_ray and d and try(function() return g.skin_ray(mesh, f.hip, d, 25) end)
  if h and h.hit then
    local k = in_frame(f, h.hit)
    local r = len(sub(h.hit, f.hip))
    if r >= 3 and r <= 18 and k[1] < 0 then return k, "her skin", h.n end
  end
  return guess, "a guess (no skin found)", nil
end

-- the stream's speed share at t s into it (0-1): rising, holding, weakening to a dribble; 0 once it is over
function M.pressure(t, spray)
  if t < 0 or spray <= 0 then return 0 end
  if t < spray then
    local rise = math.min(0.18, spray * 0.6)
    if t < rise then return 0.35 + 0.65 * t / rise end
    if t < spray * 0.6 then return 1 end
    return 1 - 0.7 * (t - spray * 0.6) / (spray * 0.4)
  end
  if t < spray + 0.45 then return 0.3 - 0.2 * (t - spray) / 0.45 end
  return 0
end

-- s along a path from p0 at velocity v till it is lift cm over the floor's plane (f, n); capped
function M.land_time(p0, v, f, n, lift)
  local h0 = dot(sub(p0, f), n) - (lift or 0)
  if h0 <= 0 then return 0.02 end
  local a, b = dot(v, n), dot(GRAVITY, n)
  if b >= -1e-3 then return 0.8 end
  local disc = a * a - 2 * b * h0
  local s = (a + math.sqrt(math.max(disc, 0))) / -b
  return math.max(0.02, math.min(0.8, s))
end

-- ---- the meshes ----
local function sections(pmc, verts, tris, normals, uvs, colors, tangents, update)
  if update then
    if try(function() pmc:UpdateMeshSection_LinearColor(0, verts, normals, uvs, {}, {}, {}, colors, tangents); return true end)
      or try(function() pmc:UpdateMeshSection_LinearColor(0, verts, normals, uvs, colors, tangents); return true end) then
      return true
    end
  end
  return try(function() pmc:CreateMeshSection_LinearColor(0, verts, tris, normals, uvs, {}, {}, {}, colors, tangents, false); return true end)
    or try(function() pmc:CreateMeshSection_LinearColor(0, verts, tris, normals, uvs, colors, tangents, false); return true end)
end

-- the stream: a tube along the path (rings of SIDES), and DROPS splash droplets (octahedra), one mesh. Positions
-- relative to o. path: { p, r } points, drops: { p, s } (s 0: hidden)
M.SIDES, M.RINGS, M.DROPS = 6, 12, 8
function M.stream_mesh(path, drops, o)
  local verts, normals, uvs, colors, tangents, tris = {}, {}, {}, {}, {}, {}
  local S, R = M.SIDES, #path
  local function put(p, n, u, v, t)
    verts[#verts + 1] = sub(p, o)
    normals[#normals + 1] = n
    uvs[#uvs + 1] = { X = u, Y = v }
    colors[#colors + 1] = { R = 1, G = 1, B = 1, A = 1 }
    tangents[#tangents + 1] = { TangentX = t, bFlipTangentY = false }
  end
  for i = 1, R do
    local p = path[i].p
    local tan = norm(sub(path[math.min(R, i + 1)].p, path[math.max(1, i - 1)].p)) or vec(0, 0, -1)
    local ref = math.abs(tan.Z) < 0.9 and vec(0, 0, 1) or vec(1, 0, 0)
    local a = norm(cross(tan, ref)) or vec(1, 0, 0)
    local b = cross(tan, a)
    for j = 0, S - 1 do
      local ang = j * 2 * math.pi / S
      local n = add(scale(a, math.cos(ang)), scale(b, math.sin(ang)))
      put(add(p, scale(n, path[i].r)), n, j / S, (i - 1) / math.max(1, R - 1), tan)
    end
  end
  local function tri(x, y, z)
    tris[#tris + 1] = x; tris[#tris + 1] = y; tris[#tris + 1] = z
    tris[#tris + 1] = x; tris[#tris + 1] = z; tris[#tris + 1] = y
  end
  for i = 0, R - 2 do
    for j = 0, S - 1 do
      local j2 = (j + 1) % S
      local a, b, c, d = i * S + j, i * S + j2, (i + 1) * S + j, (i + 1) * S + j2
      tri(a, c, b); tri(b, c, d)
    end
  end
  local OCT = { vec(1, 0, 0), vec(-1, 0, 0), vec(0, 1, 0), vec(0, -1, 0), vec(0, 0, 1), vec(0, 0, -1) }
  local FACES = { { 0, 2, 4 }, { 2, 1, 4 }, { 1, 3, 4 }, { 3, 0, 4 }, { 2, 0, 5 }, { 1, 2, 5 }, { 3, 1, 5 }, { 0, 3, 5 } }
  for _, dr in ipairs(drops) do
    local base = #verts
    for _, n in ipairs(OCT) do put(add(dr.p, scale(n, dr.s)), n, 0.5, 0.5, vec(1, 0, 0)) end
    for _, fc in ipairs(FACES) do tri(base + fc[1], base + fc[2], base + fc[3]) end
  end
  return verts, tris, normals, uvs, colors, tangents
end

-- the puddle at radius r (cm, across its narrow way) round c on the floor's plane n: a low dome with a lumpy rim,
-- stretch times longer along `along`. hf(angle, k): the floor's height there off the plane (k = share of the full
-- radius out), lim(angle): the share of the full size it may reach that way; rmax its full radius. Positions
-- relative to o
M.PUDDLE_N = 28
function M.puddle_mesh(c, n, along, r, rmax, stretch, ph, hf, lim, lift, o)
  local up = norm(n) or vec(0, 0, 1)
  local e = along and norm(sub(along, scale(up, dot(along, up))))
  if not e then
    local ref = math.abs(up.X) < 0.9 and vec(1, 0, 0) or vec(0, 1, 0)
    e = norm(cross(up, ref))
  end
  local f = cross(up, e)
  ph = ph or { 0, 0, 0, 0 }
  lift = lift or 0.35
  local N = M.PUDDLE_N
  local verts, normals, uvs, colors, tangents, tris = {}, {}, {}, {}, {}, {}
  local function put(x, y, h, nn)
    verts[#verts + 1] = sub(add(c, add(add(scale(e, x), scale(f, y)), scale(up, h))), o or c)
    normals[#normals + 1] = nn
    uvs[#uvs + 1] = { X = 0.5 + x / (math.max(rmax, 1) * 4), Y = 0.5 + y / (math.max(rmax, 1) * 4) }
    colors[#colors + 1] = { R = 1, G = 1, B = 1, A = 1 }
    tangents[#tangents + 1] = { TangentX = e, bFlipTangentY = false }
  end
  local k0 = math.max(0, math.min(1, r / math.max(rmax, 1e-3)))
  put(0, 0, (hf and hf(0, 0) or 0) + lift * 1.4, up)
  local RINGS = { { 0.35, 1.3 }, { 0.7, 1.1 }, { 1, 0.55 } }
  for _, ring in ipairs(RINGS) do
    for i = 0, N - 1 do
      local a = i * 2 * math.pi / N
      -- (lumpy, and growing faster some ways than others as it spreads)
      local wob = 1 + 0.13 * math.sin(2 * a + ph[1]) + 0.08 * math.sin(3 * a + ph[2]) + 0.05 * math.sin(5 * a + ph[3])
      local grow = math.min(1, k0 * (1 + 0.18 * math.sin(3 * a + ph[4])))
      local k = math.min(grow, lim and lim(a) or 1) * ring[1]
      local rr = rmax * k * wob
      local x, y = rr * math.cos(a) * stretch, rr * math.sin(a)
      local out = norm(add(scale(e, math.cos(a)), scale(f, math.sin(a)))) or e
      local h = (hf and hf(a, k * wob) or 0) + lift * ring[2]
      put(x, y, h, norm(add(up, scale(out, ring[1] < 1 and 0.04 * ring[1] or 0.22))) or up)
    end
  end
  local function tri(x, y, z)
    tris[#tris + 1] = x; tris[#tris + 1] = y; tris[#tris + 1] = z
    tris[#tris + 1] = x; tris[#tris + 1] = z; tris[#tris + 1] = y
  end
  for i = 0, N - 1 do
    local j = (i + 1) % N
    tri(0, 1 + i, 1 + j)
    for ring = 0, #RINGS - 2 do
      local a0, b0 = 1 + ring * N, 1 + (ring + 1) * N
      tri(a0 + i, b0 + i, b0 + j)
      tri(a0 + i, b0 + j, a0 + j)
    end
  end
  return verts, tris, normals, uvs, colors, tangents
end

-- its colour by tune.gore.deathFluid.tint (the menu's Fluid Colour): dark yellow by default, amber, yellow, pale,
-- or custom (deathFluid.color, linear RGB)
M.TINTS = {
  dark = { 0.36, 0.25, 0.03 },
  amber = { 0.55, 0.30, 0.04 },
  yellow = { 0.80, 0.60, 0.10 },
  pale = { 0.85, 0.78, 0.36 },
}
function M.tint_color(c)
  local t = c.tint or "dark"
  if t == "custom" and type(c.color) == "table" then return c.color end
  return M.TINTS[t] or M.TINTS.dark
end

-- its material: Tachy's, white under the tint where the colour texture takes, glossy, no glow. What took is logged once
local function fluid_material(pmc)
  local c = cfg()
  local g = ctx.gore
  local mat = obj(c.material or (g and g.TACHY_MAT) or
    "/Game/Art/Character/NPC/CH_NPC_TachyNPC/Materials/MI_CH_NPC_TachyNPC_Destroyed.MI_CH_NPC_TachyNPC_Destroyed")
  if not mat then return false, "no material" end
  local mid = try(function() return pmc:CreateDynamicMaterialInstance(0, mat, FName("None")) end)
  if not valid(mid) then try(function() pmc:SetMaterial(0, mat) end); return false, "no instance of its own" end
  local white = obj("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture")
  local flat = obj("/Engine/EngineMaterials/FlatNormal.FlatNormal")
  local took = {}
  local function tex(names, t)
    if not t then return end
    for _, nm in ipairs(names) do
      local ok = try(function()
        mid:SetTextureParameterValue(FName(nm), t)
        local back = mid:K2_GetTextureParameterValue(FName(nm))
        return valid(back) and back:GetAddress() == t:GetAddress()
      end)
      if ok then took[#took + 1] = nm end
    end
  end
  tex({ "BaseColor", "Basecolor", "BaseColorTex", "Diffuse" }, white)
  tex({ "BaseNormalTex", "Baked NormalMap", "NormalTex", "Normal" }, flat)
  local col = M.tint_color(c)
  local gloss = num(c.gloss, 0.06, 0, 1)
  local whiteTook = false
  for _, nm in ipairs(took) do if nm:lower():find("color") or nm == "Diffuse" then whiteTook = true end end
  try(function()
    mid:SetVectorParameterValue(FName("Base Color Tint"), { R = col[1] or 0.8, G = col[2] or 0.6, B = col[3] or 0.1, A = 1 })
    -- (her texture kept: greyed under the tint, so it still reads yellow)
    mid:SetScalarParameterValue(FName("Desaturation"), whiteTook and 0 or 1)
    mid:SetScalarParameterValue(FName("Brightness"), num(c.brightness, 1, 0.1, 5))
    mid:SetScalarParameterValue(FName("Roughness Min"), math.min(gloss, 0.04))
    mid:SetScalarParameterValue(FName("Roughness Max"), gloss)
    mid:SetScalarParameterValue(FName("Metallic"), 0)
    mid:SetScalarParameterValue(FName("EmissivePower"), 0)
  end)
  if not st.matLogged then
    st.matLogged = true
    local tint = try(function() local v = mid:K2_GetVectorParameterValue(FName("Base Color Tint")); return string.format("%.2f, %.2f, %.2f", v.R, v.G, v.B) end)
    local rmax = try(function() return mid:K2_GetScalarParameterValue(FName("Roughness Max")) end)
    log(string.format("material %s: textures %s, tint reads %s, roughness max %s", try(function() return mat:GetFName():ToString() end) or "?",
      #took > 0 and table.concat(took, ", ") or "none took (her own, greyed)", tostring(tint), tostring(rmax)))
  end
  return true
end

local function spawn(pawn, at)
  local gs = obj("/Script/Engine.Default__GameplayStatics")
  local cls = obj("/Script/Engine.StaticMeshActor")
  local pcls = obj("/Script/ProceduralMeshComponent.ProceduralMeshComponent")
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
    try(function() root:SetMobility(2) end)
    try(function() root:SetCollisionEnabled(0) end)
  end
  local pmc = try(function()
    return a:AddComponentByClass(pcls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }, false)
  end)
  if not valid(pmc) then try(function() a:K2_DestroyActor() end); return nil end
  try(function() pmc:SetCollisionEnabled(0) end)
  try(function() pmc:SetCastShadow(false) end)
  -- (the blood pools' decals would paint it red: it shows over them)
  try(function() pmc:SetReceivesDecals(false) end)
  local owner, component = ctx.keep(a), ctx.keep(pmc)
  if not (owner and component and ctx.alive_ask({ owner, component }) and owner.alive and component.alive) then
    try(function() a:K2_DestroyActor() end)
    return nil
  end
  return owner, component
end

local function component_of(actor, component)
  if actor and component and ctx.held(actor) and ctx.held(component) then return component.obj end
end

local function destroy(actor)
  if actor and ctx.alive_ask({ actor }) and actor.alive and valid(actor.obj) then
    try(function() actor.obj:K2_DestroyActor() end)
  end
end

-- ---- the floor round the puddle ----
-- traced once round c on the plane n, out to the puddle's full size: the height off the plane at half and full
-- radius every DIRS directions, and how far it may spread each way (a drop, a step or a wall stops it)
M.DIRS = 20
function M.floor_map(pawn, c, n, e, f, rmax, stretch)
  local g = ctx.gore
  local map = { h = {}, lim = {} }
  for i = 0, M.DIRS - 1 do
    local a = i * 2 * math.pi / M.DIRS
    local hs, lim = { 0 }, 1
    for _, k in ipairs({ 0.5, 1 }) do
      local p = add(c, add(scale(e, math.cos(a) * rmax * k * stretch * 1.1), scale(f, math.sin(a) * rmax * k * 1.1)))
      local hit, q, hn = g.pool_trace(pawn, add(p, scale(n, 12)), add(p, scale(n, -20)))
      local h = hit and q and dot(sub(q, c), n)
      if not (h and hn and dot(hn, n) > 0.8 and math.abs(h) <= 4) then
        lim = math.min(lim, k == 0.5 and 0.3 or 0.6)
        h = hs[#hs]
      end
      hs[#hs + 1] = h
    end
    map.h[i + 1], map.lim[i + 1] = hs, lim
  end
  return map
end
local function map_at(map, list, a)
  local x = (a / (2 * math.pi)) * M.DIRS
  local i = math.floor(x)
  local w = x - i
  local i0, i1 = i % M.DIRS + 1, (i + 1) % M.DIRS + 1
  return list[i0], list[i1], w
end
-- (the height off the plane at angle a, k of the full radius out; how far it may go that way)
function M.map_height(map, a, k)
  if not map then return 0 end
  local h0, h1, w = map_at(map, map.h, a)
  -- (k is a share of the size the floor was traced at, 1.1 times the puddle's: past it, on along the last slope)
  k = k / 1.1
  local function along(hs)
    if k <= 0.5 then return hs[1] + (hs[2] - hs[1]) * (k / 0.5) end
    return hs[2] + (hs[3] - hs[2]) * math.min(1.6, (k - 0.5) / 0.5)
  end
  return along(h0) * (1 - w) + along(h1) * w
end
function M.map_limit(map, a)
  if not map then return 1 end
  local l0, l1, w = map_at(map, map.lim, a)
  return l0 * (1 - w) + l1 * w
end

-- ---- the run of it ----
-- the floor under her hips, the stream and its puddle set up. False to try again a moment later
function M.start(pawn, mesh, now)
  local c = cfg()
  local g = ctx.gore
  if not (g and g.pool_trace) then st.phase = "done"; log("no floor tracing (gore.lua)"); return false end
  st.noStream, st.way, st.fallback = nil, nil, nil
  local fr = M.hips(mesh)
  if not fr then
    -- (a leg gone or her hips torn apart: the puddle alone, under her hips)
    local p, way = M.between(mesh)
    if not p then return false end
    fr = nil
    st.noStream, st.way, st.fallback = true, way, p
  end
  local k, how = { -7.5, 0, 3.5 }, "a guess"
  if fr then k, how = M.find_source(mesh, fr) end
  local src = fr and at_frame(fr, k) or st.fallback
  local hit, f, n = g.pool_trace(pawn, add(src, vec(0, 0, 10)), add(src, vec(0, 0, -100)))
  if not (hit and f and n) or n.Z < 0.75 then
    if not st.toldFloor then st.toldFloor = true; log("no level floor under her yet: waiting") end
    return false
  end
  local h = dot(sub(src, f), n)
  if h > num(c.height, 45, 5, 200) then
    if not st.toldHigh then st.toldHigh = true; log(string.format("between her legs %.0f cm over the floor: waiting for her to come down", h)) end
    return false
  end
  st.srcK, st.floor, st.floorN, st.t1 = k, f, n, now
  st.spray = num(c.spray, 2.5, 0, 6)
  if st.noStream or c.stream == false or st.spray <= 0 then st.spray = 0 end
  -- the stream's own actor (none when it can't run)
  if st.spray > 0 then
    local a, pmc = spawn(pawn, src)
    if a then
      st.sa, st.spmc, st.so = a, pmc, src
      local okm, why = fluid_material(pmc.obj)
      if not okm then log("material: " .. tostring(why)) end
      st.drops = {}
      for i = 1, M.DROPS do st.drops[i] = { born = -1, life = 0, v = vec(0, 0, 0), at = src, s = 0 } end
    else
      st.spray = 0
    end
  end
  st.phase = "stream"
  log(string.format("from %s between her legs %.0f cm over the floor, %.1f s after her death: %s", how, h, now - st.t0,
    st.spray > 0 and string.format("spurting for %.1f s, then spreading", st.spray) or "seeping out (no stream)"))
  return true
end

-- where the puddle goes and how it is shaped: centre c on the floor (the stream's landing point)
function M.puddle_start(pawn, c, now)
  local cc = cfg()
  local g = ctx.gore
  local n = st.floorN
  -- (on the floor itself: the stream landed lift cm over the plane traced under her hips; the floor there, traced)
  local hit, q = g.pool_trace(pawn, add(c, scale(n, 10)), add(c, scale(n, -30)))
  if hit and q and math.abs(dot(sub(q, c), n)) < 8 then c = q else c = sub(c, scale(n, dot(sub(c, st.floor), n))) end
  local size = num(cc.size, 24, 6, 120)
  local rmax = size * 0.5
  -- along her legs, or downhill on a slope (it runs further that way)
  local stretch = num(cc.stretch, 1.35, 1, 3)
  local way = st.way
  local slope = math.sqrt(math.max(0, 1 - n.Z * n.Z))
  local downhill = norm(add(vec(0, 0, -1), scale(n, n.Z)))
  if slope > 0.05 and downhill then
    way = downhill
    stretch = stretch + math.min(1.2, slope * 6)
  elseif st.frame and st.frame.legs then
    way = st.frame.legs
  end
  if g.wall_room then rmax = math.min(rmax, g.wall_room(pawn, c, n, rmax * stretch) / stretch) end
  local up = n
  local e = way and norm(sub(way, scale(up, dot(way, up))))
  if not e then e = norm(cross(up, math.abs(up.X) < 0.9 and vec(1, 0, 0) or vec(0, 1, 0))) end
  local f = cross(up, e)
  local map = M.floor_map(pawn, c, n, e, f, rmax, stretch)
  local a, pmc = spawn(pawn, c)
  if not a then return false end
  local okm, why = fluid_material(pmc.obj)
  if not okm then log("material: " .. tostring(why)) end
  st.pa, st.ppmc, st.pc, st.pe, st.rmax, st.stretch, st.map = a, pmc, c, e, rmax, stretch, map
  st.ph = { math.random() * 6.283, math.random() * 6.283, math.random() * 6.283, math.random() * 6.283 }
  st.downhill = slope > 0.05 and downhill or nil
  st.pt0, st.pmade, st.pnext = now, false, 0
  local stops = 0
  for _, l in ipairs(map.lim) do if l < 1 then stops = stops + 1 end end
  log(string.format("puddle spreading from where it lands: to %.0f x %.0f cm%s%s", rmax * 2 * stretch, rmax * 2,
    slope > 0.05 and string.format(", downhill (slope %.0f deg)", math.deg(math.asin(math.min(1, slope)))) or "",
    stops > 0 and string.format(", held short %d of %d ways round (a drop, a step or a wall)", stops, M.DIRS) or ""))
  return true
end

-- the puddle's radius share at t s since it started (the stream's part, then the spread after it)
function M.puddle_share(t, spray, grow)
  local a = 0.45
  if spray > 0 and t < spray then return 0.06 + (a - 0.06) * (1 - math.exp(-2.2 * t / spray)) / (1 - math.exp(-2.2)) end
  local u = t - math.max(spray, 0)
  local from = spray > 0 and a or 0.08
  return from + (1 - from) * (1 - math.exp(-3 * u / math.max(grow, 0.5)))
end

local function puddle_update(now)
  local pmc = component_of(st.pa, st.ppmc)
  if not pmc then return false end
  local c = cfg()
  local grow = num(c.grow, 8, 1, 60)
  local t = now - st.pt0
  local k = M.puddle_share(t, st.spray or 0, grow)
  local centre = st.pc
  -- (on a slope its middle creeps downhill as it spreads)
  if st.downhill then centre = add(centre, scale(st.downhill, st.rmax * 0.3 * k)) end
  local map = st.map
  local verts, tris, normals, uvs, colors, tangents = M.puddle_mesh(centre, st.floorN, st.pe, st.rmax * k, st.rmax,
    st.stretch, st.ph, function(a, kk) return M.map_height(map, a, kk) end, function(a) return M.map_limit(map, a) end,
    num(c.lift, 0.35, 0.05, 3), st.pc)
  local ok = sections(pmc, verts, tris, normals, uvs, colors, tangents, st.pmade)
  if ok then st.pmade = true end
  return t < (st.spray or 0) + grow * 1.3
end

local function stream_update(pawn, mesh, now)
  local c = cfg()
  local t = now - st.t1
  local spray = st.spray
  local fr = M.hips(mesh)
  if fr then st.frame = fr end
  fr = st.frame
  if not fr then return false end
  local src = at_frame(fr, st.srcK)
  -- launched down her body and forward of her (her belly's way), wavering a little
  local w1, w2 = math.sin(t * 9.1 + 0.7) * 0.07, math.sin(t * 6.3 + 2.1) * 0.06
  local d = dir_frame(fr, { -0.7 + w1, w2, 0.72 })
  local p = M.pressure(t, spray)
  local speed = num(c.spraySpeed, 100, 20, 400) * p * (1 + 0.05 * math.sin(t * 43) + 0.04 * math.sin(t * 71 + 1))
  local v = scale(d, speed)
  local floorF, floorN = st.floor, st.floorN
  local lift = num(c.lift, 0.35, 0.05, 3)
  local land = M.land_time(src, v, floorF, floorN, lift)
  local function at(s) return add(add(src, scale(v, s)), scale(GRAVITY, 0.5 * s * s)) end
  local landing = at(land)
  -- the puddle starts where it first lands
  if st.pa == nil and t >= land then
    st.way = st.way or fr.legs
    if not M.puddle_start(pawn, landing, now) then st.pa = false end
  end
  local pmc = component_of(st.sa, st.spmc)
  if not pmc then return t < spray + 0.6 end
  -- the stream's head runs out at first, its tail falls away once it stops
  local s0 = math.max(0, t - (spray + 0.45))
  local s1 = math.min(land, t)
  local r0 = num(c.sprayRadius, 0.32, 0.05, 2) * (0.55 + 0.45 * math.sqrt(math.max(p, 0)))
  local path = {}
  local R = M.RINGS
  local visible = s1 > s0 + 1e-3
  for i = 1, R do
    local u = (i - 1) / (R - 1)
    local s = s0 + (s1 - s0) * u
    local r = visible and r0 * (1 - 0.35 * u) or 0
    -- (its head and its tail taper)
    if s1 < land and u > 0.8 then r = r * (1 - (u - 0.8) / 0.2 * 0.8) end
    if s0 > 0 and u < 0.15 then r = r * (0.3 + u / 0.15 * 0.7) end
    path[i] = { p = at(s), r = r }
  end
  -- droplets where it lands, while it reaches the floor
  local splashing = c.splash ~= false and visible and t >= land and s0 < land * 0.8 and p > 0
  for _, dr in ipairs(st.drops) do
    local age = now - dr.born
    if age > dr.life then
      if splashing then
        local ref = math.abs(floorN.Z) < 0.9 and vec(0, 0, 1) or vec(1, 0, 0)
        local ea = norm(cross(floorN, ref)) or vec(1, 0, 0)
        local eb = cross(floorN, ea)
        local ang = math.random() * 2 * math.pi
        local hor = add(scale(ea, math.cos(ang)), scale(eb, math.sin(ang)))
        local sp = (25 + math.random() * 55) * (0.4 + 0.6 * p)
        dr.v = add(scale(hor, sp * 0.8), scale(floorN, sp * (0.6 + math.random() * 0.5)))
        dr.at, dr.born, dr.life = landing, now, 0.12 + math.random() * 0.18
        dr.size = 0.12 + math.random() * 0.2
        age = 0
      else
        dr.size = 0
      end
    end
    if (dr.size or 0) > 0 then
      local q = add(add(dr.at, scale(dr.v, age)), scale(GRAVITY, 0.5 * age * age))
      if dot(sub(q, floorF), floorN) < 0 then dr.s, dr.p = 0, dr.at else dr.s, dr.p = dr.size, q end
    else
      dr.s, dr.p = 0, dr.at or landing
    end
  end
  local verts, tris, normals, uvs, colors, tangents = M.stream_mesh(path, st.drops, st.so)
  local ok = sections(pmc, verts, tris, normals, uvs, colors, tangents, st.smade)
  if ok then st.smade = true end
  if not visible and t > spray + 0.45 then
    destroy(st.sa)
    st.sa = nil
    return false
  end
  return true
end

-- every poll: dead, whether her death is on
function M.tick(pawn, mesh, dead)
  if not dead then
    if st.phase then M.clear("she is up") end
    return
  end
  local c = cfg()
  if c.enabled ~= true or (ctx.tune.gore or {}).enabled == false then
    if st.phase then M.clear("off") end
    return
  end
  if not (ctx.gore and ctx.gore.native_ready()) then return end
  local now = os.clock()
  if not st.phase then st.phase, st.t0, st.still, st.last, st.next = "wait", now, 0, nil, 0 end
  if not valid(mesh) then mesh = try(function() return pawn.Mesh end) end
  if st.phase == "wait" then
    if now < st.next then return end
    st.next = now + 0.2
    if now - st.t0 > num(c.giveUp, 25, 5, 120) then
      st.phase = "done"
      log(string.format("not settled near a floor %.0f s into her death: none this time", now - st.t0))
      return
    end
    if not valid(mesh) then return end
    local p = M.between(mesh)
    if not p then return end
    local moved = st.last and len(sub(p, st.last)) or 1e9
    st.last = p
    if moved / 0.2 < 12 then st.still = st.still + 0.2 else st.still = 0 end
    if st.still < num(c.still, 1, 0, 10) or now - st.t0 < num(c.delay, 2, 0, 60) then return end
    st.frame = M.hips(mesh)
    if not M.start(pawn, mesh, now) then st.next = now + 0.5 end
  elseif st.phase == "stream" then
    local going = false
    if st.spray > 0 and valid(mesh) then
      local ok, r = pcall(stream_update, pawn, mesh, now)
      if not ok then
        log("stream: " .. tostring(r))
        destroy(st.sa)
        st.sa, st.spray, r = nil, 0, false
      end
      going = r
    end
    -- (no stream: the puddle straight under her, seeping out)
    if st.pa == nil and st.spray <= 0 then
      st.way = st.way or (st.frame and st.frame.legs)
      if not M.puddle_start(pawn, st.floor, now) then st.pa = false end
    end
    -- (the puddle redrawn a dozen times a second while it spreads)
    local spreading = false
    if st.pa then
      spreading = true
      if now >= (st.pnext or 0) then
        st.pnext = now + 0.08
        local ok, r = pcall(puddle_update, now)
        if not ok then log("puddle: " .. tostring(r)); r = false end
        spreading = r
      end
    end
    if not going and not spreading and (st.pa ~= nil or st.spray <= 0) then st.phase = "done" end
  end
end

function M.clear(why)
  destroy(st.sa)
  destroy(st.pa)
  if st.sa or st.pa then log("cleared (" .. tostring(why) .. ")") end
  M.forget()
end
-- a new level: the old one's actors went with it, not touched
function M.forget()
  for k in pairs(st) do if k ~= "matLogged" then st[k] = nil end end
end
return M
