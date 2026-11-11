-- Bone-tree cache and native cut-list construction.
return function(M, try, valid, addr, enemy, get_ctx)
-- bones that may never be a sink (see nosink in sbslice.c): a sink gives up its weights everywhere and collapses, so
-- not the main skeleton (Bip001-*: the pelvis, a clavicle, the head had been picked), nor hair, capes, breasts (they
-- swing, and the seam swung with them), nor accessory bones (Ab_*: a neck chain 26 cm off the cut). Per mesh asset,
-- sent before every cut on a component
-- each mesh asset's bone names and parents by index, read once (M.watch reads hers a slice at a time while she plays):
-- the lists below come from it with no engine call. Read bone by bone at the cut, they held the first cut's frame
-- 15-34 ms more (twenty-ninth playtest). budget: at most that many bones now, nil if it isn't whole yet
M.trees = {}
function M.bone_tree(comp, budget)
  local sm = try(function() return comp.SkeletalMesh end)
  local key = valid(sm) and addr(sm)
  if not key then return nil end
  local t = M.trees[key]
  if not t then
    local n = try(function() return comp:GetNumBones() end) or 0
    if n <= 0 then return nil end
    t = { n = n, name = {}, pname = {}, index = {}, parent = {}, next = 0 }
    M.trees[key] = t
  end
  if t.done then return t end
  local stop = budget and math.min(t.n, t.next + budget) or t.n
  while t.next < stop do
    local i = t.next
    local nm = try(function() return comp:GetBoneName(i):ToString() end) or "None"
    t.name[i], t.index[nm] = nm, i
    t.pname[i] = try(function() return comp:GetParentBone(FName(nm)):ToString() end) or "None"
    t.next = i + 1
  end
  if t.next < t.n then return nil end
  for i = 0, t.n - 1 do t.parent[i] = t.index[t.pname[i]] or -1 end
  t.done = true
  return t
end
-- i is r's bone or under it (by name)
function M.under(t, i, r)
  local ri = t.index[r]
  if not ri then return false end
  local guard = 0
  while i and i >= 0 and guard < 512 do
    if i == ri then return true end
    i, guard = t.parent[i], guard + 1
  end
  return false
end
local NOSINK_PREFIX = { "Bip001", "SC_", "Ab_" }
local NOSINK_PART = { "Hair", "Cape", "Breast", "Prop" }
local nosink_cache = {}
local function nosink_list(comp)
  local sm = try(function() return comp.SkeletalMesh end)
  local key = valid(sm) and addr(sm)
  -- An enemy without a separate face may use Ab_ helpers as sinks. The same
  -- mesh asset can also be used by the player or a faced character.
  if key then key = tostring(key) .. ((enemy.cur and not enemy.faced[enemy.cur]) and "/unfaced" or "/faced") end
  if key and nosink_cache[key] then return nosink_cache[key] end
  local t = M.bone_tree(comp)
  local n = t and t.n or 0
  local list = {}
  for i = 0, n - 1 do
    local nm = t.name[i]
    local bad = nm == "Root" or nm == "None"
    -- an enemy's Ab_ bones are its own deform helpers (the skulls' head has no other: without them its head had
    -- nothing to close on and vanished); a lurker's tentacles stay sinks too (its head closes on them)
    for _, pre in ipairs(NOSINK_PREFIX) do if nm:sub(1, #pre) == pre and not (enemy.cur and not enemy.faced[enemy.cur] and pre == "Ab_") then bad = true end end
    for _, part in ipairs(NOSINK_PART) do if nm:find(part, 1, true) then bad = true end end
    if bad then list[#list + 1] = string.format("%x", i) end
  end
  local s = table.concat(list, ",")
  if key and n > 0 then nosink_cache[key] = s end
  return s
end
-- a cut through the spine also keeps its sinks off the arms and legs: they swing on their own, and the bind pose's
-- arms hang down at the waist, where a waist cut's strap seam collapsed onto a triceps helper (seventeenth playtest).
-- A limb or head cut keeps them off every other limb (own: the cut bone's limb root, its own subtree stays allowed):
-- a thigh cut in a fall put the hip's seam on Ab-L-Elbow, the hand resting by the hip, and the seam rode the arm
-- off as she flailed, a sheet from the hip to the elbow (twenty-seventh playtest)
local LIMB_ROOTS = { "Bip001-L-Clavicle", "Bip001-R-Clavicle", "Bip001-L-Thigh", "Bip001-R-Thigh" }
-- the limb root bone i is on: under one of LIMB_ROOTS, or under a helper of the same name (CH_M_NA_40's arm helpers
-- hang off Ab-L-Clavicle, beside Bip001-L-Clavicle: a waist cut's seam took Ab-L-UpperArm-biceps and swung with the
-- arm), else nil
function M.limb_of(t, i)
  local guard = 0
  while i and i >= 0 and guard < 512 do
    local nm = t.name[i] or ""
    local side, part = nm:match("[-_]([LR])%-(Clavicle)$")
    if not side then side, part = nm:match("[-_]([LR])%-(Thigh)$") end
    if side then return "Bip001-" .. side .. "-" .. part end
    i, guard = t.parent[i], guard + 1
  end
end
local limbs_cache = {}
local function limbs_list(comp, own)
  local sm = try(function() return comp.SkeletalMesh end)
  local key = valid(sm) and (addr(sm) .. "/" .. tostring(own))
  if key and limbs_cache[key] then return limbs_cache[key] end
  local t = M.bone_tree(comp)
  local n = t and t.n or 0
  local list = {}
  for i = 0, n - 1 do
    local r = M.limb_of(t, i)
    if r and r ~= own then list[#list + 1] = string.format("%x", i) end
  end
  local s = table.concat(list, ",")
  if key and n > 0 then limbs_cache[key] = s end
  return s
end
-- the limb root a bone is on (M.limb_of), else nil
local function limb_root(comp, bone)
  local t = M.bone_tree(comp)
  if t and t.index[bone] then return M.limb_of(t, t.index[bone]) end
  for _, r in ipairs(LIMB_ROOTS) do if bone == r then return r end end
end
-- bones that may never carry a stub (after ffff in the same command): the rig's Dm- drivers, which the animation points
-- at limbs (Dm-Spine-bland, blending Spine and Spine1, carried a waist cut's stub after the flying upper body). An
-- enemy's every bone: its mesh asset is shared with the live enemies of its kind, whose skin on a carrier would move
-- with the cut one's matrix. Nor a bone with a physics body of its own: it swings on its own constraint in a ragdoll
-- (a calf's stub went on Ab-L-Hip, the hip's jiggle body, and would have bounced with it)
local nocarry_cache = {}
local function physics_key(comp)
  local sm = try(function() return comp.SkeletalMesh end)
  local pa = get_ctx().physics_of and try(function() return get_ctx().physics_of(comp) end)
  local sk = valid(sm) and addr(sm)
  local pk = valid(pa) and addr(pa)
  return sk and pk and (tostring(sk) .. "/" .. tostring(pk)) or nil, pa
end
-- her bones with a physics body (by index; sent after fffe in "n": a cut's sinks ride the body its stump rides, and a
-- limb's seam closes in the opening's middle). An enemy's too: without them its seams closed on helpers 40-50 cm off
-- the cut, sheets of skin out of every opening (playtest: stretched faces on enemies)
local function bodies_of(comp)
  local base, pa = physics_key(comp)
  local key = base and (base .. "b")
  if key and nocarry_cache[key] then return nocarry_cache[key] end
  local out = {}
  if valid(pa) then
    try(function() pa.SkeletalBodySetups:ForEach(function(_, e)
      local bs = e:get()
      local t = M.bone_tree(comp)
      local i = valid(bs) and try(function() return t and t.index[bs.BoneName:ToString()] or comp:GetBoneIndex(bs.BoneName) end)
      if i and i >= 0 then out[i] = true end
    end) end)
  end
  if key and next(out) then nocarry_cache[key] = out end
  return out
end
local function nocarry_list(comp)
  local base = physics_key(comp)
  local key = base and (base .. (enemy.cur and "e" or "h"))
  if key and nocarry_cache[key] then return nocarry_cache[key] end
  local t = not enemy.cur and M.bone_tree(comp)
  local n = try(function() return comp:GetNumBones() end) or 0
  local body = bodies_of(comp)
  local list = {}
  for i = 0, n - 1 do
    local nm = enemy.cur and "" or (t and t.name[i]) or "None"
    if enemy.cur or nm:sub(1, 3) == "Dm-" or nm:sub(1, 3) == "Dm_" or body[i] then list[#list + 1] = string.format("%x", i) end
  end
  local s = table.concat(list, ",")
  if key and n > 0 then nocarry_cache[key] = s end
  return s
end

-- a cut through the spine also sends the rig's Dm- drivers and every helper under one (before the main skeleton), after
-- fffd: the animation points them across the cut, so they are a sink only when a section has nothing else.
-- CH_P_EVE_30's Ab-L-AX2, under Dm-L-AX2 on the pelvis, took a waist cut's lower seam and went with the flying upper
-- body: that half's opening stretched 3.5 m after it (playtest)
function M.driven_list(comp)
  local sm = try(function() return comp.SkeletalMesh end)
  local key = valid(sm) and (addr(sm) .. "d")
  if key and nocarry_cache[key] then return nocarry_cache[key] end
  local t = M.bone_tree(comp)
  local n = t and t.n or 0
  local list = {}
  for i = 0, n - 1 do
    local j, guard = i, 0
    while j and j >= 0 and guard < 512 and t.name[j]:sub(1, 6) ~= "Bip001" do
      local pre = t.name[j]:sub(1, 3)
      if pre == "Dm-" or pre == "Dm_" then list[#list + 1] = string.format("%x", i); break end
      j, guard = t.parent[j], guard + 1
    end
  end
  local s = table.concat(list, ",")
  if key and n > 0 then nocarry_cache[key] = s end
  return s
end

-- the drivers of a side (L, R) a split half lets go of: the animation moves them after those limbs, which fall free and
-- invisible, so its kept skin that hung partly on them stretched out after them, cones out of the half (playtest).
-- The half's skin lets go of them as of the limbs (sbslice fffc). Which limb a driver follows is read off the name of
-- the topmost Dm- bone over it (M.DRIVER_LIMB); a breast's or a cloth's follow her chest
M.DRIVER_LIMB = { arm = { "Trape", "Shoulder", "Side", "Pectro", "Arm", "Deltoid", "Tricep", "Elbow", "Forearm", "Brochi", "Clavicle" },
  leg = { "Thigh", "Hip", "Knee", "Venter", "Calf", "Ankle", "AX2" } }
function M.driver_limb(name)
  if name:find("Breast", 1, true) or name:find("Cloth", 1, true) then return nil end
  local side = name:match("[%-_]([LR])[%-_]")
  if not side then return nil end
  for kind, words in pairs(M.DRIVER_LIMB) do
    for _, w in ipairs(words) do if name:find(w, 1, true) then return side .. kind end end
  end
end
function M.side_drivers(comp, gone)
  local want, tag = {}, {}
  for _, b in ipairs(gone or {}) do
    local sd, part = b:match("^Bip001%-([LR])%-(%a+)")
    if sd then
      local k = sd .. ((part == "Thigh" or part == "Calf") and "leg" or "arm")
      if not want[k] then want[k] = true; tag[#tag + 1] = k end
    end
  end
  if #tag == 0 then return "" end
  table.sort(tag)
  local sm = try(function() return comp.SkeletalMesh end)
  local key = valid(sm) and (addr(sm) .. "s" .. table.concat(tag))
  if key and nocarry_cache[key] then return nocarry_cache[key] end
  local t = M.bone_tree(comp)
  local n = t and t.n or 0
  local list = {}
  for i = 0, n - 1 do
    local j, guard, top = i, 0, nil
    while j and j >= 0 and guard < 512 and t.name[j]:sub(1, 6) ~= "Bip001" do
      local nm = t.name[j]
      if nm:sub(1, 3) == "Dm-" or nm:sub(1, 3) == "Dm_" then top = nm end
      j, guard = t.parent[j], guard + 1
    end
    local k = top and M.driver_limb(top)
    if k and want[k] then list[#list + 1] = string.format("%x", i) end
  end
  local r = table.concat(list, ",")
  if key and n > 0 then nocarry_cache[key] = r end
  return r
end


return {
  roots = LIMB_ROOTS, nosink = nosink_list, limbs = limbs_list, root = limb_root,
  bodies = bodies_of, nocarry = nocarry_list,
  clear = function() nosink_cache, nocarry_cache, limbs_cache, M.trees = {}, {}, {}, {} end,
}
end
