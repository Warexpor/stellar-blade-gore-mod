-- Customized Ragdoll (Nexus 3884) support (tune.customizedRagdoll, off by default): its death camera and its death
-- screen (up as the game puts it but see-through, its keys working) over the mod's own ragdoll and cuts.
-- That mod's death animations (its death_anim_p: Result_Stand_Dead, Eve_Stand_Dead2/3, the down and explosion deaths)
-- carry a notify at 0.008 s that spawns its A_RagdollManager on her, or calls Process on the one there. Process swaps
-- her physics asset for its own (SetPhysicsAsset, reinitialised) and ragdolls her with a physical animation blend:
-- that undoes the outfit's ragdoll fixes (physfix.lua) and fights the mod's ragdoll and cuts. Process does nothing on
-- a manager already Active, so the mod keeps one spawned on her, Active, while she lives (the notify is the death's
-- first frame, before the mod sees the death). Its camera modifier (CM_Ragdoll: 2 m behind her pelvis down the view,
-- stopped short of walls, the player turning it) reads only the manager's Active and Mesh, so it is added at her
-- death and removed as she gets up. The manager's own keys ([ ] \ and its revert on F / R) need Process's
-- EnableInput and stay off; the death screen's F / R are the game's own and work
local M = {}
local ctx, try, valid, log
local DIR = "/Game/Art/Character/PC/CH_P_EVE_01/Animation/Facial/"
local MGR, CAM = DIR .. "A_RagdollManager", DIR .. "CM_Ragdoll"
-- mgr: the manager kept on her (pawn: her address); cls / camCls: their classes; missing: the mod isn't installed (told once);
-- mod: the camera modifier while a death has it; off: the modifier disabled (photo mode)
local st = { mgr = nil, pawn = nil, cls = nil, camCls = nil, missing = false, nextKeep = 0, mod = nil, off = false }

function M.init(c)
  ctx = c
  try, valid, log = c.try, c.valid, c.log
end

function M.enabled() return ctx.tune.customizedRagdoll == true end
local function addr(o) return valid(o) and try(function() return o:GetAddress() end) or 0 end

-- a Blueprint's class: loaded already, else from its package (not around a respawn: main.lua's may_load)
local function class_of(path)
  local nm = path:match("([^/]+)$")
  local full = path .. "." .. nm .. "_C"
  local c = try(function() return StaticFindObject(full) end)
  if valid(c) then return c end
  if not (LoadAsset and ctx.may_load()) then return nil end
  try(function() LoadAsset(path .. "." .. nm) end)
  c = try(function() return StaticFindObject(full) end)
  return valid(c) and c or nil
end

local function classes()
  if st.missing then return false end
  st.cls = valid(st.cls) and st.cls or class_of(MGR)
  st.camCls = valid(st.camCls) and st.camCls or class_of(CAM)
  if valid(st.cls) and valid(st.camCls) then return true end
  if ctx.may_load() then
    st.missing = true
    log("Customized Ragdoll support is on, but its A_RagdollManager / CM_Ragdoll didn't load: the mod isn't installed "
      .. "(its death_anim_p and death_expression_p in Paks/~mods); the mod's own death camera is used")
  end
  return false
end

local function drop(why)
  if valid(st.mgr) then
    try(function() st.mgr:K2_DestroyActor() end)
    log("Customized Ragdoll: manager removed (" .. why .. ")")
  end
  st.mgr, st.pawn = nil, nil
end

-- while she lives (main.lua's alive watch), once a second: the manager on her, Active, so its notify does nothing.
-- Off: the one kept is removed (and missing is told again once it is turned back on)
function M.keep(pawn, mesh)
  local now = os.clock()
  if now < st.nextKeep then return end
  st.nextKeep = now + 1
  if not M.enabled() then
    st.missing = false
    if st.mgr then drop("support turned off") end
    return
  end
  if valid(st.mgr) and st.pawn == addr(pawn) then
    if try(function() return st.mgr.Active end) ~= true then try(function() st.mgr.Active = true end) end
    return
  end
  if st.mgr then drop("she was replaced") end
  if not (valid(pawn) and valid(mesh) and classes()) then return end
  -- one of its own on her already: its notify made it (a death before the mod's) and Processed her
  local found = try(function() return FindFirstOf("A_RagdollManager_C") end)
  if valid(found) and addr(try(function() return found:GetOwner() end)) == addr(pawn) then
    log("Customized Ragdoll: its own manager is on her already (its death came first); taken over as is")
  else
    found = nil
  end
  local gs = ctx.statics()
  local loc = try(function() local v = pawn:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
  if not (valid(gs) and loc) then return end
  local tm = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = loc, Scale3D = { X = 1, Y = 1, Z = 1 } }
  local mgr = valid(found) and found or try(function()
    local d = gs:BeginDeferredActorSpawnFromClass(pawn, st.cls, tm, 1, nil)
    return gs:FinishSpawningActor(d, tm)
  end)
  if not valid(mgr) then log("Customized Ragdoll: manager spawn failed"); return end
  if not found then try(function() mgr:K2_AttachToActor(pawn, FName("None"), 2, 2, 2, false) end) end
  -- BlendAmount 1: its tick (on with its blend saved on) has nothing to blend out, and no PhysicalAnim to blend it on
  try(function() mgr.Mesh = mesh; mgr.BlendAmount = 1.0; mgr.Active = true end)
  st.mgr, st.pawn = mgr, addr(pawn)
  log("Customized Ragdoll: manager kept on her (Active: its death notify does nothing, the mod ragdolls her)")
end

-- at her death (main.lua's camera_hold): its camera on, true if it took the view (else the mod's own camera)
function M.camera_on(pawn)
  if not M.enabled() then return false end
  st.nextKeep = 0
  M.keep(pawn, try(function() return pawn.Mesh end))
  if not valid(st.mgr) then return false end
  local pcm = try(function() return ctx.statics():GetPlayerCameraManager(pawn, 0) end)
  local mod = valid(pcm) and try(function() return pcm:AddNewCameraModifier(st.camCls) end)
  if not valid(mod) then log("Customized Ragdoll: its camera modifier wasn't added, the mod's own camera is used"); return false end
  st.mod, st.pcm, st.off = mod, pcm, false
  log("Customized Ragdoll: its death camera on")
  return true
end

-- every frame of a death: off while photo mode is open (it would pin photo mode's camera behind her pelvis)
function M.tick(photo)
  if not valid(st.mod) then return end
  local off = photo and true or false
  if off == st.off then return end
  st.off = off
  if off then try(function() st.mod:DisableModifier(true) end) else try(function() st.mod:EnableModifier() end) end
end

-- as she gets up (camera_release)
function M.camera_off()
  if not st.mod then return end
  if valid(st.mod) and valid(st.pcm) then try(function() st.pcm:RemoveCameraModifier(st.mod) end) end
  st.mod, st.pcm, st.off = nil, nil, false
  log("Customized Ragdoll: its death camera off")
end

return M
