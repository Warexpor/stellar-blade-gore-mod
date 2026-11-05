-- Select split-spine breaks while keeping each half's limbs attached.
return function(M, SPINE_CHAIN, SPINE_TOL, bone_loc, sub, dot, get_try)
local function try(...) local f=get_try(); return f(...) end
local function spine_break(mesh, at, n)
  local hs = {}
  for i, b in ipairs(SPINE_CHAIN) do
    local l = bone_loc(mesh, b)
    if not l then return nil end
    hs[i] = dot(sub(l, at), n)
  end
  if hs[1] >= -SPINE_TOL then return nil end
  for i = 2, #SPINE_CHAIN do
    local above = true
    for j = i, #SPINE_CHAIN do if hs[j] < -SPINE_TOL then above = false end end
    if above then return SPINE_CHAIN[i] end
  end
  return nil
end

-- each half's break keeps the limbs that half keeps on one piece. Her half breaks only when every limb she keeps
-- hangs off the break (with the head): a lengthwise slice keeps an arm and a leg each side, and her half broke at
-- Spine2, tearing her thigh from her shoulder across 1.6 m of skin (playtest 44). The copy's break is the spine bone
-- hers is at, or the next one up while any limb the copy keeps hangs off it (the Biped thighs' parent is Bip001-Spine,
-- not the pelvis): a waist split just over the pelvis broke both halves there, and the copy let its legs go with the
-- spine (playtest 40)
function M.hangs_off(mesh, l, b) return try(function() return mesh:BoneIsChildOf(FName(l), FName(b)) end) == true end
function M.her_break(mesh, spine, kept)
  if not spine then return nil end
  for _, l in ipairs(kept or {}) do if not M.hangs_off(mesh, l, spine) then return nil end end
  return spine
end
function M.copy_break(mesh, spine, kept)
  if not spine then return nil end
  local si
  for i, b in ipairs(SPINE_CHAIN) do if b == spine then si = i end end
  while si do
    local free = true
    for _, l in ipairs(kept or {}) do if M.hangs_off(mesh, l, SPINE_CHAIN[si]) then free = false; break end end
    if free then return SPINE_CHAIN[si] end
    si = SPINE_CHAIN[si + 1] and si + 1 or nil
  end
  return nil
end

return spine_break
end
