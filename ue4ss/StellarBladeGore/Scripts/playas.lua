-- playas.lua: Play As (tune.playAs, F3 → Sandbox → Play As): Eve wears another character, one menu row. Her own
-- components take the other's meshes, so her animations, physics, cuts, struggle and death face stay hers:
--   tachy: her NPC body (hair in it) and face (CH_NPC_TachyNPC_Body, _Face_Jali2: built on Eve's skeleton, the beach
--     scenes' Tachy), Eve's hair hidden
--   scarlet: the DLC boss's body (CH_M_NA_961, on Eve's skeleton, head and hair in it), Eve's face and hair hidden.
--     Without the DLC it isn't found and nothing changes
--   raven: the game has no Raven head on Eve's skeleton (hers is on a skeleton of its own): Raven's suit as Eve's
--     outfit (CH_P_EVE_11) and Raven's own hair (CH_M_NA_53_Hair) on a component of its own, posed by Eve's body
--     (master pose, bones by name), Eve's hair hidden
-- Each takes her own blade too (the game's EquipmentTable: Tachy_Sword, Raven_Blade, Scarlet_Sword) in place of
-- Eve's drawn sword (CH_W_Sword_01 in a weapon slot; the folded one the game shows when it is away is left, so it
-- still goes away as hers): on a skeleton of its own, it doesn't fold, and her sword's gore (its fall, a blade cut
-- through it) takes it as it took hers.
-- What the game puts back (a level, a respawn, the outfit menu, a scene) is set again within a second; "eve" gives
-- back what she wore. While it is on, an outfit change in the game's menu is overridden.
local M = {}
local ctx, try, valid
local function cfg() return ctx.tune.playAs or {} end
local function log(s) ctx.log("play as: " .. s) end

local P = "/Game/Art/Character/"
M.LOOKS = {
  tachy = { label = "Tachy", body = P .. "NPC/CH_NPC_TachyNPC/CH_NPC_TachyNPC_Body.CH_NPC_TachyNPC_Body",
    face = P .. "NPC/CH_NPC_TachyNPC/CH_NPC_TachyNPC_Face_Jali2.CH_NPC_TachyNPC_Face_Jali2", hide = { hair = true },
    weapon = P .. "Weapon/Sword/CH_W_Sword_02/CH_W_Sword_02.CH_W_Sword_02" },
  scarlet = { label = "Scarlet", body = "/Game/DLC_2/Art/Character/Monster/CH_M_NA_961/CH_M_NA_961.CH_M_NA_961",
    hide = { face = true, hair = true }, dlc = true,
    weapon = "/Game/DLC_2/Art/Character/Monster/CH_M_NA_961/CH_M_NA_961_Weapon_01.CH_M_NA_961_Weapon_01" },
  raven = { label = "Raven", body = P .. "PC/CH_P_EVE_11/CH_P_EVE_11.CH_P_EVE_11",
    extra = P .. "Monster/CH_M_NA_53/CH_M_NA_53_Hair.CH_M_NA_53_Hair", hide = { hair = true },
    weapon = P .. "Monster/CH_M_NA_53/CH_M_NA_53_Weapon.CH_M_NA_53_Weapon" },
}
-- her mesh slots (MeshInfoList's MeshSlot): the face, and the hair ones (Hair1, Ponytail, PonytailShort)
M.FACE, M.HAIR = 1, { [2] = true, [3] = true, [4] = true }
-- her weapon slots (Weapon1-4), and her drawn sword's mesh in them
M.WEAPON, M.SWORD = { [5] = true, [6] = true, [7] = true, [8] = true }, "CH_W_Sword_01"

local st = { pawn = nil, who = "eve", was = nil, next = 0, failed = {} }

function M.init(c)
  ctx, try, valid = c, c.try, c.valid
end

local function addr(o) return valid(o) and try(function() return o:GetAddress() end) or nil end
local function asset(path)
  local a = try(function() return StaticFindObject(path) end)
  if not valid(a) and LoadAsset and (not ctx.may_load or ctx.may_load()) then a = try(function() return LoadAsset(path) end) end
  return valid(a) and a or nil
end
local function slots(pawn)
  local out = {}
  try(function() pawn.MeshInfoList:ForEach(function(_, e)
    local info = e:get()
    local c = info.MeshComponent
    if valid(c) then out[#out + 1] = { slot = info.MeshSlot, comp = c } end
  end) end)
  return out
end

-- what she wore before (put back by "eve"): her body's and face's meshes, the components it hid
local function remember(pawn, mesh)
  if st.was and st.was.pawn == addr(pawn) then return end
  local face
  for _, s in ipairs(slots(pawn)) do if s.slot == M.FACE then face = s.comp end end
  st.was = { pawn = addr(pawn), body = try(function() return mesh.SkeletalMesh end),
    face = face, faceMesh = face and try(function() return face.SkeletalMesh end), hidden = {}, weapons = {} }
end

local function hide(c)
  if not valid(c) then return end
  if try(function() return c:IsVisible() end) ~= true then return end
  try(function() c:SetVisibility(false, false) end)
  st.was.hidden[#st.was.hidden + 1] = c
end

local function drop_extra()
  local x = st.extra
  st.extra = nil
  if valid(x) then try(function() x:K2_DestroyComponent(x) end) end
end

-- the look on her (again: anything the game put back). Returns a line for the log, or nil when all was in place
local function apply(pawn, mesh, look)
  local out = {}
  local body = asset(look.body)
  if not body then
    if not st.failed[look.body] then
      st.failed[look.body] = true
      log(string.format("%s: %s not found%s; she stays as she is", look.label, look.body, look.dlc and " (needs its DLC)" or ""))
    end
    return nil
  end
  remember(pawn, mesh)
  if addr(try(function() return mesh.SkeletalMesh end)) ~= addr(body) then
    try(function() mesh:SetSkeletalMesh(body, true) end)
    out[#out + 1] = "body " .. look.body:match("([^/.]+)$")
  end
  for _, s in ipairs(slots(pawn)) do
    if s.slot == M.FACE then
      if look.hide.face then hide(s.comp)
      elseif look.face then
        local f = asset(look.face)
        if f and addr(try(function() return s.comp.SkeletalMesh end)) ~= addr(f) then
          try(function() s.comp:SetSkeletalMesh(f, true) end)
          out[#out + 1] = "face " .. look.face:match("([^/.]+)$")
        end
      end
    elseif M.HAIR[s.slot] and look.hide.hair then
      hide(s.comp)
    elseif M.WEAPON[s.slot] and look.weapon then
      local cur = try(function() return s.comp.SkeletalMesh end)
      local nm = valid(cur) and try(function() return cur:GetFName():ToString() end)
      local w = nm == M.SWORD and asset(look.weapon)
      if w then
        st.was.weapons[#st.was.weapons + 1] = { comp = s.comp, mesh = cur, ours = w }
        try(function() s.comp:SetSkeletalMesh(w, true) end)
        out[#out + 1] = "blade " .. look.weapon:match("([^/.]+)$")
      end
    end
  end
  -- a mesh of another skeleton on her pose (bones by name)
  if look.extra and not valid(st.extra) then
    local x = asset(look.extra)
    local cls = try(function() return StaticFindObject("/Script/Engine.SkeletalMeshComponent") end)
    local c = x and valid(cls) and try(function()
      return pawn:AddComponentByClass(cls, true, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
        Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
    end)
    if valid(c) then
      try(function() c:SetCollisionEnabled(0) end)
      try(function() c:SetSkeletalMesh(x, true) end)
      try(function() c:K2_AttachToComponent(mesh, FName("None"), 2, 2, 2, true) end)
      try(function() c:SetMasterPoseComponent(mesh, true) end)
      st.extra = c
      out[#out + 1] = "with " .. look.extra:match("([^/.]+)$")
    end
  end
  return #out > 0 and table.concat(out, ", ") or nil
end

-- back as she was
local function restore(why)
  drop_extra()
  local w = st.was
  st.was = nil
  if not w then return end
  local pawn = st.pawn
  if not (valid(pawn) and addr(pawn) == w.pawn) then return end -- (a new Eve wears her own)
  local mesh = try(function() return pawn.Mesh end)
  if valid(mesh) and valid(w.body) then try(function() mesh:SetSkeletalMesh(w.body, true) end) end
  if valid(w.face) and valid(w.faceMesh) then try(function() w.face:SetSkeletalMesh(w.faceMesh, true) end) end
  for _, c in ipairs(w.hidden) do if valid(c) then try(function() c:SetVisibility(true, false) end) end end
  -- (her sword back where ours still is: one the game swapped meanwhile stays the game's)
  for _, x in ipairs(w.weapons) do
    if valid(x.comp) and valid(x.mesh) and addr(try(function() return x.comp.SkeletalMesh end)) == addr(x.ours) then
      try(function() x.comp:SetSkeletalMesh(x.mesh, true) end)
    end
  end
  log("back to Eve (" .. why .. ")")
end

-- every tick of hers (main.lua): at most once a second, and never while she is dead (her body is the ragdoll's)
function M.tick(pawn, mesh, dead)
  local now = os.clock()
  if now < st.next then return end
  st.next = now + 1
  if addr(pawn) ~= addr(st.pawn) then
    -- a new Eve: what was hidden went with the old one
    st.pawn, st.was, st.extra = pawn, nil, nil
  end
  local who = cfg().who or "eve"
  local look = M.LOOKS[who]
  if who ~= st.who then
    if st.who ~= "eve" then restore("Play As: " .. who) end
    st.who = who
    if look then log("now " .. look.label) end
  end
  if not look or dead then return end
  -- (not while a cut on her alive is out, Lose Arm at Low HP's arm: her body's weights are the DLL's then)
  if ctx.gore and ctx.gore.cuts_on and (try(function() return ctx.gore.cuts_on(mesh) end) or 0) > 0 then return end
  local line = apply(pawn, mesh, look)
  if line then log(look.label .. ": " .. line) end
end
-- the F3 row changed: at once
function M.apply_now() st.next = 0 end
-- the level reloaded: nothing of the old Eve touched
function M.forget() st.pawn, st.was, st.extra = nil, nil, nil end

M._state = function() return st end
return M
