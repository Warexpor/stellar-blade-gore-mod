-- Install the shared Tachy opening geometry functions on the gore module.
return function(M, cfg, vec, add, scale, sub, dot, norm, cross)
-- Tachy's flesh as a torn surface: rings from the rim in to the centre, each point raised by her
-- texture's relief (t.relief, read where that point lands on the disc) and a swell where the flesh pushes out of the
-- skin, the normals worked out from the faces so the light shows it. The relief fades out at the rim, which stays on
-- her skin, and under the core. The back face is lid_mesh's flat one. Same return as lid_mesh
-- one frame for both openings of a cut (tachy_lid, M.core): the body side's x and y. Each opening had its own (its
-- first rim point, its fitted ellipse) and Tachy's core was turned, not mirrored, onto the other side: the stump and
-- the cut piece showed different cross-sections, the bone in one place on the arm and elsewhere on the shoulder. With
-- this the piece's side is the stump's mirror image, as the two faces of one cut are
-- back: her back on the cut's plane (back_on), the frame's x, else the opening's own x (the DLL's rim axis, which is
-- any way round per cut: the bone stood at a random place on each stump, left and right thighs unlike each other,
-- playtest). side: -1 for her right's limbs, whose frame is the left's mirror image (y the other way), so the cores of
-- her two thighs or arms mirror across her midline as she does
function M.pair(ob, ol, back, side)
  local z = ob and ob.z and norm(ob.z)
  local function on(v) return z and v and norm(sub(v, scale(z, dot(v, z)))) end
  local x = on(back) or on(ob and ob.x)
  if not x then return end
  local y = cross(z, x)
  if side and side < 0 then y = scale(y, -1) end
  ob.tx, ob.ty = x, y
  if ol then ol.tx, ol.ty = x, y end
end
-- the spine bone a cut's frame reads her back off (back_on): one that stays with the limb whatever was cut before.
-- Spine1 for all, and after a waist cut it rode her flying upper half: a thigh cut then got its back from that, the
-- right thigh's bone and tubes turned anyhow and no longer the left's mirror image (playtest screenshot). The legs
-- hang off Bip001-Spine, under the waist cut; the arms and spine off Spine1 and up, which go with them
function M.back_bone(bone)
  if not bone then return "Bip001-Spine1" end
  if bone:find("Thigh") or bone:find("Calf") or bone:find("Foot") then return "Bip001-Spine" end
  return bone:find("^Bip001%-[PSNH]") and not bone:find("%-[LR]%-") and bone or "Bip001-Spine1"
end
-- a cut bone's side for M.pair: -1 on her right, 1 on her left and down her middle
function M.side_of(bone)
  return bone and bone:find("%-R%-") and -1 or 1
end
-- an opening's frame for the tachy look: x along it, y across it (the shared one, M.pair), and whether that is
-- mirrored (the cut piece's side: y = -(z cross x))
function M.tachy_frame(o, z)
  local x0 = o.tx or o.x
  local x = x0 and norm(sub(x0, scale(z, dot(x0, z))))
  if not x then return nil end
  local y = cross(z, x)
  local mirrored = o.ty and dot(y, o.ty) < 0 or false
  if mirrored then y = scale(y, -1) end
  return x, y, mirrored
end
-- a cap with no core of Tachy's over it (a neck's or waist's, which get the snapped bone at the spine, and a split's)
-- takes this patch of her disc, {x, y, radius} in disc radii: plain flesh away from her core, whose gold socket and
-- tube holes are painted on the disc and showed through on a neck as a stray bump by the bone (playtest)
M.TACHY_PATCH = { -0.3, -0.3, 0.38 }
-- how high the flesh rises in the middle of an opening of mean radius r (tachyDome of a dome: 0 flat, as a blade
-- leaves it; the lid was a smooth dome and read as a cover, not a cut, playtest). Tachy's core stands on it
function M.tachy_dome(r)
  return math.min(math.max(r * 0.18, 0.4), 1.8) * (cfg().tachyDome or 0)
end
-- smooth value noise, -1..1, on a hashed lattice
function M.tachy_hash(i, j)
  local n = (i * 374761393 + j * 668265263) % 2147483647
  n = (n ~ (n >> 13)) * 1274126177 % 2147483647
  return (n % 2001) / 1000 - 1
end
function M.tachy_noise(x, y)
  local i, j = math.floor(x), math.floor(y)
  local fx, fy = x - i, y - j
  fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
  local h = M.tachy_hash
  local h00, h10, h01, h11 = h(i, j), h(i + 1, j), h(i, j + 1), h(i + 1, j + 1)
  local a = h00 + (h10 - h00) * fx
  local b = h01 + (h11 - h01) * fx
  return a + (b - a) * fy
end
-- the torn surface: rings from the rim in, and points round each (the outline's, more put between them up to
-- TACHY_AROUND: at the outline's 15-40 the relief was too coarse to read as torn)
M.TACHY_RINGS = { 1, 0.94, 0.88, 0.82, 0.75, 0.68, 0.61, 0.54, 0.47, 0.4, 0.33, 0.26, 0.19, 0.12, 0.06 }
M.TACHY_AROUND = 72
function M.tachy_lid(o, k, t)
  local g = cfg()
  local n = #o.p
  local c = vec(0, 0, 0)
  for _, q in ipairs(o.p) do c = add(c, q) end
  c = scale(c, 1 / n)
  local z = o.z
  local r = 0
  for _, q in ipairs(o.p) do local d = sub(q, c); r = r + math.sqrt(math.max(dot(d, d) - dot(d, z) ^ 2, 0)) end
  r = r / n
  local dome = M.tachy_dome(r)
  -- (deep: a harsh cut's torn flesh; at r * 0.22 the relief's typical 0.27 of it was 2-3 mm on a neck and read as flat,
  -- playtest)
  -- (at r * 0.45 up to 3 cm, with the noise on top, it was too lumpy, playtest)
  -- (still too lumpy at r * 0.3 up to 1.5 cm, and its creases sank under the cut, where the limb's own closed skin hid the
  -- flesh: the stump looked uncovered, playtest. Creases go at most a fifth of it down)
  local amp = math.min(math.max(r * 0.12, 0.3), 0.8) * (g.tachyRelief or 1)
  local u, w = M.tachy_frame(o, z)
  if not u then
    u = norm(sub(o.p[1], add(c, scale(z, dot(sub(o.p[1], c), z))))) or o.x
    w = cross(z, u)
  end
  local disc, rel = t.disc, t.relief
  -- (a plain patch of the disc under a core too: the whole disc's painted gold socket showed beside the core's own,
  -- playtest)
  local pa = M.TACHY_PATCH
  local gs = rel and rel.size or 0
  -- the relief at a point of the disc's square (-1..1 each way), bilinear
  local function relief(x, y)
    if gs == 0 then return 0 end
    local fx, fy = (x + 1) * 0.5 * gs - 0.5, (y + 1) * 0.5 * gs - 0.5
    local x0, y0 = math.max(0, math.min(gs - 2, math.floor(fx))), math.max(0, math.min(gs - 2, math.floor(fy)))
    local ax, ay = math.max(0, math.min(1, fx - x0)), math.max(0, math.min(1, fy - y0))
    local row = y0 * gs + x0 + 1
    local h = (((rel[row] or 0) / 99) * (1 - ax) + ((rel[row + 1] or 0) / 99) * ax) * (1 - ay)
      + (((rel[row + gs] or 0) / 99) * (1 - ax) + ((rel[row + gs + 1] or 0) / 99) * ax) * ay
    -- torn finer than the texture's 48 cells: smooth noise on the disc (the same on both faces of a cut: they mirror)
    return math.max(-1, math.min(1, h + 0.25 * M.tachy_noise(x * 9, y * 9) + 0.15 * M.tachy_noise(x * 21 + 7, y * 21 + 3)))
  end
  local verts, normals, uvs, tris, tangents, colors = {}, {}, {}, {}, {}, {}
  local function vert(pos, nrm, uv)
    verts[#verts + 1] = pos
    normals[#normals + 1] = nrm
    uvs[#uvs + 1] = uv
    tangents[#tangents + 1] = { TangentX = u, bFlipTangentY = dot(cross(nrm, u), w) < 0 }
    colors[#colors + 1] = { R = 1, G = 1, B = 1, A = 1 }
    return #verts - 1
  end
  -- the front: ring i, point j; ρ the share of the way out to the rim
  local R = M.TACHY_RINGS
  local pts = {}
  local per = math.max(1, math.ceil(M.TACHY_AROUND / n))
  for j, q in ipairs(o.p) do
    local q2 = o.p[j % n + 1]
    for s2 = 0, per - 1 do pts[#pts + 1] = add(q, scale(sub(q2, q), s2 / per)) end
  end
  local nf = #pts
  -- These are properties of the outline, unchanged across all fifteen rings.
  local outline = {}
  for j, q in ipairs(pts) do
    local d = sub(q, c)
    local h = dot(d, z)
    local flat = sub(d, scale(z, h))
    local ang = math.atan(dot(flat, w), dot(flat, u))
    outline[j] = { flat = flat, h = h, cos = math.cos(ang), sin = math.sin(ang) }
  end
  local grid = {}
  for i, rho in ipairs(R) do
    grid[i] = {}
    for j, point in ipairs(outline) do
      local flat, h = point.flat, point.h
      local cx, cy = pa[1] + point.cos * rho * pa[3], pa[2] + point.sin * rho * pa[3]
      -- (out at the rim: the skin's own height; in from it the dome, a swell just inside the skin, the relief, which
      -- fades in over the outer tenth, and under a core)
      local fade = math.min(1, (1 - rho) / 0.1) * (o.core and math.min(1, rho / 0.3) or 1)
      if o.boneAt then
        local b = sub(add(c, scale(flat, k * rho)), o.boneAt)
        local bd = math.sqrt(math.max(dot(b, b) - dot(b, z) ^ 2, 0))
        fade = fade * math.max(0, math.min(1, (bd - 1.2) / 1.5))
      end
      local lift = 0.2 + h * rho + dome * (1 - rho * rho) * 0.85 + dome * 0.35 * math.sin(math.min(1, (1 - rho) / 0.3) * math.pi)
        + amp * fade * math.max(relief(cx, cy), -0.2)
      grid[i][j] = vert(add(scale(flat, k * rho), scale(z, lift)), z,
        { X = disc[1] + disc[3] * cx, Y = disc[2] + disc[3] * cy })
    end
  end
  local centre = vert(scale(z, dome * 0.85 + 0.2), z, { X = disc[1] + disc[3] * pa[1], Y = disc[2] + disc[3] * pa[2] })
  local front = {}
  -- counter-clockwise from +z, as lid_mesh's (each written backwards for UE's clockwise front faces)
  local function tri(a, b, cc) front[#front + 1] = { a, b, cc } end
  for i = 1, #R - 1 do
    for j = 1, nf do
      local jn = j % nf + 1
      local a, b, cc, d = grid[i][j], grid[i][jn], grid[i + 1][jn], grid[i + 1][j]
      tri(a, b, cc); tri(a, cc, d)
    end
  end
  for j = 1, nf do tri(grid[#R][j], grid[#R][j % nf + 1], centre) end
  -- normals from the faces (each face's, by its area, onto its corners)
  local acc = {}
  for _, f in ipairs(front) do
    local p1, p2, p3 = verts[f[1] + 1], verts[f[2] + 1], verts[f[3] + 1]
    local fn = cross(sub(p2, p1), sub(p3, p1))
    if dot(fn, z) < 0 then fn = scale(fn, -1) end
    for _, v in ipairs(f) do acc[v] = acc[v] and add(acc[v], fn) or fn end
    tris[#tris + 1] = f[3]; tris[#tris + 1] = f[2]; tris[#tris + 1] = f[1]
  end
  for v, a in pairs(acc) do normals[v + 1] = norm(a) or z end
  -- the back: lid_mesh's flat face, the other way
  local nz = scale(z, -1)
  local base = #verts
  vert(scale(z, dome), nz, { X = disc[1], Y = disc[2] })
  for _, q in ipairs(o.p) do
    local d = sub(q, c)
    local h = dot(d, z)
    local flat = sub(d, scale(z, h))
    vert(add(scale(flat, k), scale(z, h + 0.2)), nz, { X = disc[1], Y = disc[2] })
  end
  for j = 0, n - 1 do
    local jn = (j + 1) % n
    tris[#tris + 1] = base + 1 + j; tris[#tris + 1] = base + 1 + jn; tris[#tris + 1] = base
  end
  return c, verts, tris, normals, uvs, tangents, colors
end


-- her metal bone alone, out of the core (its shaft and its end, two pieces; the two tubes and the flat disc by them
-- are left out), centred on 0, 0: a neck's or waist's stump shows only the bone, at her spine. {tris, centre, shaft}
-- (shaft: the shaft's radius in disc radii, from its vertices above the flare)
function M.tachy_bone(t)
  if t.bone then return t.bone end
  local v, nv = t.verts, #t.verts // 11
  local par = {}
  for i = 0, nv - 1 do par[i] = i end
  local function f(a) while par[a] ~= a do par[a] = par[par[a]]; a = par[a] end return a end
  for i = 1, #t.tris, 3 do
    local a, b, c = t.tris[i], t.tris[i + 1], t.tris[i + 2]
    par[f(a)] = f(b); par[f(b)] = f(c)
  end
  local comps = {}
  for i = 0, nv - 1 do
    local r = f(i)
    local c = comps[r] or { n = 0, x = 0, y = 0 }
    comps[r] = c
    c.n, c.x, c.y = c.n + 1, c.x + v[i * 11 + 1], c.y + v[i * 11 + 2]
  end
  local big
  for r, c in pairs(comps) do if not big or c.n > comps[big].n then big = r end end
  local bx, by = comps[big].x / comps[big].n, comps[big].y / comps[big].n
  local reach = 0
  for i = 0, nv - 1 do
    if f(i) == big then reach = math.max(reach, math.sqrt((v[i * 11 + 1] - bx) ^ 2 + (v[i * 11 + 2] - by) ^ 2)) end
  end
  local keep = {}
  for r, c in pairs(comps) do
    if math.sqrt((c.x / c.n - bx) ^ 2 + (c.y / c.n - by) ^ 2) < reach * 0.5 then keep[r] = true end
  end
  local tris = {}
  for i = 1, #t.tris, 3 do
    if keep[f(t.tris[i])] then for k = 0, 2 do tris[#tris + 1] = t.tris[i + k] end end
  end
  local shaft, top = 0, -1
  for i = 0, nv - 1 do if keep[f(i)] then top = math.max(top, v[i * 11 + 3]) end end
  for i = 0, nv - 1 do
    if keep[f(i)] and v[i * 11 + 3] > top * 0.4 then
      shaft = math.max(shaft, math.sqrt((v[i * 11 + 1] - bx) ^ 2 + (v[i * 11 + 2] - by) ^ 2))
    end
  end
  local set = {}
  for i = 0, nv - 1 do if keep[f(i)] then set[i] = true end end
  -- its lean: the shaft's middles over its lowest and highest quarters, per unit of height
  local z0, z1 = math.huge, -math.huge
  for i = 0, nv - 1 do if f(i) == big then z0, z1 = math.min(z0, v[i * 11 + 3]), math.max(z1, v[i * 11 + 3]) end end
  local lo, hi = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
  for i = 0, nv - 1 do
    local h = v[i * 11 + 3]
    local q = f(i) == big and (h < z0 + (z1 - z0) * 0.25 and lo or h > z1 - (z1 - z0) * 0.25 and hi) or nil
    if q then q[1], q[2], q[3], q[4] = q[1] + v[i * 11 + 1], q[2] + v[i * 11 + 2], q[3] + h, q[4] + 1 end
  end
  local lx, ly = 0, 0
  if lo[4] > 0 and hi[4] > 0 then
    local dz = hi[3] / hi[4] - lo[3] / lo[4]
    if dz > 1e-3 then lx, ly = (hi[1] / hi[4] - lo[1] / lo[4]) / dz, (hi[2] / hi[4] - lo[2] / lo[4]) / dz end
  end
  -- her gold socket: the flat pieces lying low on her disc (two rings, 0.05 high at most; a tube's end lies flat too,
  -- but up at its top)
  local gold, span = {}, {}
  for i = 0, nv - 1 do
    local r, h = f(i), v[i * 11 + 3]
    local sp = span[r] or { math.huge, -math.huge }
    span[r] = sp
    sp[1], sp[2] = math.min(sp[1], h), math.max(sp[2], h)
  end
  for i = 0, nv - 1 do local sp = span[f(i)]; if sp[2] < 0.08 and sp[2] - sp[1] < 0.1 then gold[i] = true end end
  t.bone = { tris = tris, cx = bx, cy = by, shaft = shaft > 0 and shaft or reach, verts = set, lx = lx, ly = ly, gold = gold }
  return t.bone
end
-- her bone in silver (boneSilver): on her texture it is painted ivory, not metal (its metal mask 0.01-0.04), and read
-- as pale dirt (playtest); her metal is on the strip along the bottom (v 0.82-0.93, a mask of 0.95) and in the tube
-- ends' tiles down the left. Its end goes onto a tube end's tile, its shaft onto the strip, each scaled, not turned
-- (her tangents stay right)
function M.bone_uv(t, i, u, w)
  if cfg().boneSilver == false or not M.tachy_bone(t).verts[i] then return { X = u, Y = w } end
  if u < 0.3 and w < 0.35 then return { X = 0.02 + (u - 0.01) / 0.28 * 0.15, Y = 0.40 + (w - 0.01) / 0.33 * 0.16 } end
  return { X = 0.05 + (u - 0.74) / 0.25 * 0.65, Y = 0.82 + (w - 0.12) / 0.87 * 0.11 }
end

end
