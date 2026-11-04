-- Pure procedural cap geometry; vector operations are supplied by the gore module.
return function(vec, add, scale, sub, dot, norm, cross)
-- the lid as a procedural mesh: the outline (pushed out a little past the skin), a ring halfway in and the centre
-- raised into a low dome, both faces. Vertices relative to the actor at the outline's centroid.
return function(o, k)
  local n = #o.p
  local c = vec(0, 0, 0)
  for _, q in ipairs(o.p) do c = add(c, q) end
  c = scale(c, 1 / n)
  local z = o.z
  local r = 0
  for _, q in ipairs(o.p) do local d = sub(q, c); r = r + math.sqrt(dot(d, d) - dot(d, z) ^ 2) end
  r = r / n
  -- the lid bulges out a little
  local dome = math.min(math.max(r * 0.18, 0.4), 1.8)
  local u = norm(sub(o.p[1], add(c, scale(z, dot(sub(o.p[1], c), z))))) or o.x
  local w = cross(z, u)
  local verts, normals, uvs, tris, tangents, colors = {}, {}, {}, {}, {}, {}
  -- tangents along the texture's U and white vertex colours: without them the material's normal map lit the flesh
  -- from a made-up direction (a glossy, broken look)
  local function vert(pos, nrm)
    verts[#verts + 1] = pos
    normals[#normals + 1] = nrm
    uvs[#uvs + 1] = { X = dot(pos, u) / 12 + 0.5, Y = dot(pos, w) / 12 + 0.5 }
    tangents[#tangents + 1] = { TangentX = u, bFlipTangentY = dot(nrm, z) < 0 }
    colors[#colors + 1] = { R = 1, G = 1, B = 1, A = 1 }
    return #verts - 1
  end
  local positions = {}
  for _, q in ipairs(o.p) do
    local d = sub(q, c)
    local h = dot(d, z)
    local flat = sub(d, scale(z, h))
    positions[#positions + 1] = add(scale(flat, k), scale(z, h + 0.2))
    positions[#positions + 1] = add(scale(flat, k * 0.55), scale(z, h * 0.5 + dome * 0.7))
  end
  for side = 1, 2 do
    local nz = side == 1 and z or scale(z, -1)
    local base = #verts
    vert(scale(z, dome), nz) -- centre
    for _, pos in ipairs(positions) do vert(vec(pos.X, pos.Y, pos.Z), nz) end
    -- the outline runs counter-clockwise seen from +z; UE's front faces are clockwise, so the +z face lists
    -- each triangle backwards and the -z face forwards
    for i = 0, n - 1 do
      local j = (i + 1) % n
      local ri, ii, rj, ij = base + 1 + 2 * i, base + 2 + 2 * i, base + 1 + 2 * j, base + 2 + 2 * j
      if side == 1 then
        for _, v in ipairs({ ij, rj, ri, ii, ij, ri, base, ij, ii }) do tris[#tris + 1] = v end
      else
        for _, v in ipairs({ ri, rj, ij, ri, ij, ii, ii, ij, base }) do tris[#tris + 1] = v end
      end
    end
  end
  return c, verts, tris, normals, uvs, tangents, colors
end

end
