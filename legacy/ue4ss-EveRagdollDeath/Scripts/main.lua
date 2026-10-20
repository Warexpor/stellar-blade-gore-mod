-- EveRagdollDeath 0.9.3
-- Native detour of FSBShowStage PlayShow log. DLL lives next to main.lua (not dlls/main.dll).

local MOD, VER = "EveRagdollDeath", "0.9.3"
local busy, ragdolled = false, false
local cachedPawn = nil
local lastShowHit = ""
local eveNotifySamples = 0

local COLLISION_NO = 0
local COLLISION_QUERY_AND_PHYSICS = 3
local ECR_IGNORE, ECR_BLOCK = 0, 2
local ECC_WORLD_STATIC, ECC_PAWN, ECC_PHYSICS_BODY, ECC_VEHICLE, ECC_CAMERA = 0, 2, 5, 6, 7
local THROW_SCALE, THROW_MIN, THROW_MAX, THROW_UP = 2.6, 550, 2000, 400
local lastVel = { X = 0, Y = 0, Z = 0 }
local lastHitDir = { X = 0, Y = 1, Z = 0.15 }

local SHOW_PATHS = {
  "/Game/Art/Show/CH_P_EVE_01/Basic/Eve_Dead_Common.Eve_Dead_Common",
  "/Game/Art/Show/CH_P_EVE_01/Basic/Eve_Dead_Down.Eve_Dead_Down",
  "/Game/Art/Show/CH_P_EVE_01/Basic/Eve_Dead_DownFaceDown.Eve_Dead_DownFaceDown",
  "/Game/Art/Show/CH_P_EVE_01/Basic/Eve_Dead_DownFaceUp.Eve_Dead_DownFaceUp",
}

local SHOW_CLASSES = {
  "SBShowData", "SBShowAnimKey", "SBShowPlayShowKey",
  "SBShowManager", "SBShowComponent", "SBShowInstance",
}

local PAWN_PROPS = {
  "CurrentShow", "PlayingShow", "ActiveShow", "DeadShow",
  "ShowData", "ShowPlayer", "ShowComponent", "DeadType",
  "CharacterDeadType", "DefaultDeadShow", "StandDeadShow", "DownDeadShow",
}

local function log(msg)
  print(string.format("[%s %s] %s", MOD, VER, tostring(msg)))
end

local function step(label, fn)
  log("try " .. label)
  local ok, err = pcall(fn)
  if not ok then log("FAIL " .. label .. ": " .. tostring(err)) return false end
  log("ok  " .. label)
  return true
end

local function objName(obj)
  if not obj then return "<nil>" end
  local ok, n = pcall(function() return obj:GetFullName() end)
  return ok and tostring(n) or "<bad>"
end

local function isValidObj(obj)
  local ok, v = pcall(function() return obj and obj:IsValid() end)
  return ok and v == true
end

local function isEvePawn(pawn)
  if not isValidObj(pawn) then return false end
  local n = objName(pawn)
  return n:find("CH_P_EVE_01_Blueprint", 1, true)
    and not n:find("Lobby", 1, true)
    and not n:find("Env_", 1, true)
    and not n:find("AngelRemains", 1, true)
end

local function getPlayer()
  if isEvePawn(cachedPawn) then return cachedPawn end
  for _, pc in pairs(FindAllOf("PlayerController") or {}) do
    if isValidObj(pc) then
      local pawn = pc.AcknowledgedPawn or pc.Pawn or pc.Character
      if isEvePawn(pawn) then cachedPawn = pawn; return pawn end
    end
  end
  for _, p in pairs(FindAllOf("CH_P_EVE_01_Blueprint_C") or {}) do
    if isEvePawn(p) then cachedPawn = p; return p end
  end
  return nil
end

local function getMesh(pawn)
  if not isValidObj(pawn) then return nil end
  if isValidObj(pawn.Mesh) then return pawn.Mesh end
  local m = nil
  pcall(function() m = pawn.CharacterMesh0 end)
  if isValidObj(m) then return m end
  return nil
end

local function getAnim(mesh)
  if not isValidObj(mesh) then return nil end
  local anim = nil
  pcall(function()
    if mesh.GetAnimInstance then anim = mesh:GetAnimInstance()
    else anim = mesh.AnimScriptInstance end
  end)
  if isValidObj(anim) then return anim end
  return nil
end

local function vecLen(v)
  return math.sqrt((v.X or 0) ^ 2 + (v.Y or 0) ^ 2 + (v.Z or 0) ^ 2)
end

local function sampleVelocity(pawn)
  if not isValidObj(pawn) then return end
  pcall(function()
    local move = pawn.CharacterMovement
    if isValidObj(move) and move.Velocity then
      local v = move.Velocity
      local cand = { X = v.X or 0, Y = v.Y or 0, Z = v.Z or 0 }
      if vecLen(cand) > 80 then lastVel = cand end
    end
  end)
end

local function applyDeathThrow(mesh, pawn)
  sampleVelocity(pawn)
  local dir = { X = lastHitDir.X, Y = lastHitDir.Y, Z = lastHitDir.Z }
  local dlen = vecLen(dir)
  local from = "hitDir"
  if dlen < 0.1 then dir = { X = lastVel.X, Y = lastVel.Y, Z = lastVel.Z }; dlen = vecLen(dir); from = "velocity" end
  if dlen < 40 then
    local f = nil
    pcall(function() if pawn.GetActorForwardVector then f = pawn:GetActorForwardVector() end end)
    if f then dir = { X = -(f.X or 0), Y = -(f.Y or 0), Z = 0.25 }; dlen = vecLen(dir); from = "backwards" end
  end
  if dlen < 0.001 then dir = { X = 0, Y = 1, Z = 0.2 }; dlen = 1; from = "default" end
  local nx, ny, nz = dir.X / dlen, dir.Y / dlen, dir.Z / dlen
  local speed = vecLen(lastVel)
  local throw = speed * THROW_SCALE
  if throw < THROW_MIN then throw = THROW_MIN end
  if throw > THROW_MAX then throw = THROW_MAX end
  local vx, vy, vz = nx * throw, ny * throw, math.max(nz * throw, 0) + THROW_UP
  log(string.format("throw %s -> (%.0f,%.0f,%.0f)", from, vx, vy, vz))
  step("throw vel", function()
    if mesh.SetAllPhysicsLinearVelocity then
      mesh:SetAllPhysicsLinearVelocity({ X = vx, Y = vy, Z = vz }, false)
    end
  end)
end

local function isHairBone(name)
  name = name:lower()
  for _, h in ipairs({ "hair", "pony", "ponytail", "tail", "ribbon", "bang", "ahoge" }) do
    if name:find(h, 1, true) then return true end
  end
  return false
end

local function physicsOffOnly(reason)
  log("physicsOff (" .. tostring(reason) .. ")")
  local mesh = getMesh(getPlayer())
  pcall(function()
    if not mesh then return end
    if mesh.SetAllBodiesSimulatePhysics then mesh:SetAllBodiesSimulatePhysics(false) end
    if mesh.SetAllBodiesPhysicsBlendWeight then mesh:SetAllBodiesPhysicsBlendWeight(0.0, false) end
    mesh.bBlendPhysics = false
    mesh.GlobalAnimRateScale = 1.0
    pcall(function() mesh.bPauseAnims = false end)
    mesh:SetCollisionEnabled(COLLISION_NO)
    if mesh.PutAllRigidBodiesToSleep then mesh:PutAllRigidBodiesToSleep() end
  end)
end

local function doFull(reason)
  if busy or ragdolled then return end
  busy = true
  pcall(function()
    local pawn = getPlayer()
    local mesh = getMesh(pawn)
    if not mesh then log("no mesh"); return end
    log("RAGDOLL BEGIN " .. tostring(reason))
    sampleVelocity(pawn)
    step("freeze anim", function() mesh.GlobalAnimRateScale = 0.0; mesh.bPauseAnims = true end)
    local move = pawn.CharacterMovement
    if isValidObj(move) then step("StopMovement", function() move:StopMovementImmediately() end) end
    step("mesh coll", function() mesh:SetCollisionEnabled(COLLISION_QUERY_AND_PHYSICS) end)
    step("obj type", function() if mesh.SetCollisionObjectType then mesh:SetCollisionObjectType(ECC_PHYSICS_BODY) end end)
    step("responses", function()
      mesh:SetCollisionResponseToAllChannels(ECR_IGNORE)
      mesh:SetCollisionResponseToChannel(ECC_WORLD_STATIC, ECR_BLOCK)
      mesh:SetCollisionResponseToChannel(ECC_PAWN, ECR_IGNORE)
      mesh:SetCollisionResponseToChannel(ECC_PHYSICS_BODY, ECR_IGNORE)
      mesh:SetCollisionResponseToChannel(ECC_VEHICLE, ECR_IGNORE)
      mesh:SetCollisionResponseToChannel(ECC_CAMERA, ECR_IGNORE)
    end)
    step("sim", function()
      mesh.bBlendPhysics = true
      mesh:SetAllBodiesSimulatePhysics(true)
      if mesh.SetAllBodiesPhysicsBlendWeight then mesh:SetAllBodiesPhysicsBlendWeight(1.0, false) end
    end)
    pcall(function()
      if not (mesh.GetNumBones and mesh.SetBodySimulatePhysics) then return end
      for i = 0, mesh:GetNumBones() - 1 do
        local bn = mesh:GetBoneName(i)
        local name = bn.ToString and bn:ToString() or tostring(bn)
        if isHairBone(name) then pcall(function() mesh:SetBodySimulatePhysics(name, false, true) end) end
      end
    end)
    applyDeathThrow(mesh, pawn)
    ragdolled = true
    log("RAGDOLL END")
  end)
  busy = false
end

local function isDeathName(n)
  n = tostring(n)
  return n:find("Eve_Dead", 1, true)
    or n:find("Dead_Common", 1, true)
    or n:find("DeadShow", 1, true)
    or n:find("Result_Dead", 1, true)
    or n:find("Stand_Dead", 1, true)
    or n:find("P_Eve_Dead", 1, true)
end

function EveRagdollDeath_OnNativePlayShow(name)
  name = tostring(name or "")
  log("NATIVE_PLAY " .. name)
  if isDeathName(name) then
    doFull("native " .. name)
  end
end

local function unwrap(x)
  if x == nil then return nil end
  local ok, v = pcall(function()
    if type(x) == "userdata" and x.Get then return x:Get() end
    return x
  end)
  if ok and v ~= nil then return v end
  return x
end

local function dumpFns(label, obj)
  if not isValidObj(obj) then log("  " .. label .. " <invalid>"); return end
  log("  " .. label .. " " .. objName(obj))
  local cls = nil
  pcall(function() cls = obj:GetClass() end)
  log("  " .. label .. " class=" .. objName(cls))
  local function eachFn(tag, target)
    if not isValidObj(target) then log("  " .. tag .. " skip"); return end
    local n = 0
    local ok, err = pcall(function()
      target:ForEachFunction(function(fn)
        n = n + 1
        local name = ""
        pcall(function()
          if fn.GetFullName then name = fn:GetFullName()
          elseif fn.GetName then name = fn:GetName()
          else name = tostring(fn) end
        end)
        name = tostring(name)
        local interesting = name:find("Play", 1, true) or name:find("Show", 1, true)
          or name:find("Dead", 1, true) or name:find("Start", 1, true)
          or name:find("Stop", 1, true) or name:find("Exec", 1, true)
        if interesting or (not tag:find(".class", 1, true) and n <= 60) then
          log("  fn " .. tag .. " " .. name)
        end
      end)
    end)
    if not ok then log("  " .. tag .. " ForEachFunction FAIL " .. tostring(err)) end
    log("  " .. tag .. " fnCount=" .. tostring(n))
  end
  local function eachProp(tag, target)
    if not isValidObj(target) then return end
    local n = 0
    local ok, err = pcall(function()
      target:ForEachProperty(function(prop)
        n = n + 1
        if n > 40 then return end
        local name = ""
        pcall(function()
          if prop.GetFullName then name = prop:GetFullName()
          elseif prop.GetName then name = prop:GetName()
          else name = tostring(prop) end
        end)
        log("  prop " .. tag .. " " .. tostring(name))
      end)
    end)
    if not ok then log("  " .. tag .. " ForEachProperty FAIL " .. tostring(err)) end
    log("  " .. tag .. " propCount=" .. tostring(n))
  end
  eachFn(label .. ".obj", obj)
  eachFn(label .. ".class", cls)
  eachProp(label .. ".obj", obj)
  eachProp(label .. ".class", cls)
end

local function isInteresting(name)
  name = tostring(name)
  local keys = {
    "Dead", "Die", "Dying", "Show", "PlayShow", "Play", "Kill", "Life",
    "Health", "Ragdoll", "Corpse", "Knock", "Despawn", "DeadShow",
  }
  for _, k in ipairs(keys) do
    if name:find(k, 1, true) then return true end
  end
  return false
end

local function dumpClassFns(label, obj)
  if not isValidObj(obj) then log("  " .. label .. " <invalid>"); return end
  log("  " .. label .. " " .. objName(obj))
  local cls = obj
  local okc, c = pcall(function()
    if obj.IsA and obj:IsA("/Script/CoreUObject.Class") then return obj end
    return obj:GetClass()
  end)
  if okc and isValidObj(c) then cls = c end
  log("  " .. label .. " asClass=" .. objName(cls))
  local n, hit = 0, 0
  local ok, err = pcall(function()
    cls:ForEachFunction(function(fn)
      n = n + 1
      local name = ""
      pcall(function()
        if fn.GetFullName then name = fn:GetFullName()
        elseif fn.GetName then name = fn:GetName()
        else name = tostring(fn) end
      end)
      log("  fn " .. tostring(name))
      if isInteresting(name) then hit = hit + 1 end
    end)
  end)
  if not ok then log("  " .. label .. " ForEachFunction FAIL " .. tostring(err)) end
  log(string.format("  %s fnCount=%s interesting=%s", label, tostring(n), tostring(hit)))
  n, hit = 0, 0
  ok, err = pcall(function()
    cls:ForEachProperty(function(prop)
      n = n + 1
      local name = ""
      pcall(function()
        if prop.GetFullName then name = prop:GetFullName()
        elseif prop.GetName then name = prop:GetName()
        else name = tostring(prop) end
      end)
      if isInteresting(name) then
        hit = hit + 1
        log("  prop " .. tostring(name))
      end
    end)
  end)
  if not ok then log("  " .. label .. " ForEachProperty FAIL " .. tostring(err)) end
  log(string.format("  %s propCount=%s interesting=%s", label, tostring(n), tostring(hit)))
  local super = nil
  pcall(function()
    if cls.GetSuperClass then super = cls:GetSuperClass()
    else super = cls.SuperStruct end
  end)
  if isValidObj(super) then log("  " .. label .. " super=" .. objName(super)) end
end

local SHOW_DUMP_PATHS = {
  "/Script/SB.SBShowData",
  "/Script/SB.SBShowKey",
  "/Script/SB.SBShowPlayShowKey",
  "/Script/SB.SBShowRagdollKey",
  "/Script/SB.SBShowNotifyEventKey",
  "/Script/SB.SBShowAnimKey",
  "/Script/SB.SBShowPlayableActor",
  "/Script/SB.SBBTTask_SbPlayShow",
  "/Script/SB.SBShowActorInterface",
}

local function dumpCharacter(tag)
  log("dump " .. tag)
  for _, path in ipairs(SHOW_DUMP_PATHS) do
    local obj = nil
    pcall(function() obj = StaticFindObject(path) end)
    dumpClassFns(path, obj)
  end
end

local function onShowHook(hookPath, ...)
  local parts = { hookPath }
  local args = { ... }
  for i = 1, #args do
    parts[#parts + 1] = objName(unwrap(args[i]))
  end
  local blob = table.concat(parts, " || ")
  if isDeathName(blob) then
    if blob ~= lastShowHit then
      lastShowHit = blob
      log("DEATH_SHOW " .. blob)
    end
  elseif eveNotifySamples < 40 then
    eveNotifySamples = eveNotifySamples + 1
    log("show_sample " .. blob)
  end
end

local function tryHook(path)
  local ok, err = pcall(function()
    RegisterHook(path, function(...)
      pcall(onShowHook, path, ...)
    end)
  end)
  if ok then log("hook ok " .. path) else log("hook FAIL " .. path) end
end

local function tryNewObj(cls)
  local ok, err = pcall(function()
    NotifyOnNewObject(cls, function(obj)
      pcall(function()
        local n = objName(obj)
        if isDeathName(n) then log("SHOW_NEW " .. cls .. " " .. n)
        elseif eveNotifySamples < 8 then
          eveNotifySamples = eveNotifySamples + 1
          log("newobj_sample " .. cls .. " " .. n)
        end
      end)
    end)
  end)
  if ok then log("newobj ok " .. cls) else log("newobj FAIL " .. cls) end
end

pcall(function()
  RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    log("ClientRestart wasRagdoll=" .. tostring(ragdolled))
    if ragdolled then physicsOffOnly("ClientRestart") end
    ragdolled = false
    busy = false
    cachedPawn = nil
    lastShowHit = ""
    eveNotifySamples = 0
  end)
end)

tryHook("/Script/SB.SBShowActorInterface:PlaySingleShow")
tryHook("/Script/SB.SBShowActorInterface:ActorPlayCustomAnimSequence")
tryHook("/Script/SB.SBShowActorInterface:ActorPlayCustomAnimName")
tryHook("/Script/SB.SBShowActorInterface:ActorPlayCustomAnimSequenceMeshSlot")
tryHook("/Script/SB.SBShowActorInterface:ActorPlayCustomAnimNameMeshSlot")
tryHook("/Script/SB.SBCharacter:NotifyShowEvent")

RegisterKeyBind(0x77, function()
  log("F8"); ragdolled = false; doFull("F8")
end)
RegisterKeyBind(0x76, function()
  log("F7"); physicsOffOnly("F7"); ragdolled = false
end)
RegisterKeyBind(0x78, function()
  log("F9 dump")
  dumpCharacter("F9")
end)

log("loaded " .. VER .. " — native PlayShow detour + death ragdoll")

local function scriptDir()
  local src = debug.getinfo(1, "S").source or ""
  src = src:gsub("^@", "")
  return (src:match("^(.*)[/\\][^/\\]+$") or ".")
end

local function loadNative()
  log("loadlib type=" .. tostring(package and type(package.loadlib)))
  local dir = scriptDir()
  local candidates = {
    dir .. "\\playshow.dll",
    dir .. "/playshow.dll",
    "ue4ss/Mods/EveRagdollDeath/Scripts/playshow.dll",
    "Mods/EveRagdollDeath/Scripts/playshow.dll",
  }
  local init, used = nil, nil
  for _, p in ipairs(candidates) do
    if type(package) == "table" and type(package.loadlib) == "function" then
      local fn, err = package.loadlib(p, "InitPlayShowHook")
      log("try " .. p .. " -> " .. tostring(fn) .. " " .. tostring(err))
      if type(fn) == "function" then
        init, used = fn, p
        break
      end
    end
  end
  if type(init) ~= "function" then
    log("native dll not loaded")
    return
  end
  log("native loaded " .. used)
  init()
  local status_path = dir .. "\\hook_status.txt"
  local last_path = dir .. "\\last_show.txt"
  local sf = io.open(status_path, "r")
  if sf then
    local s = sf:read("*a") or ""
    sf:close()
    log("native status=" .. s)
  else
    log("native status file missing")
  end
  local last_seen = ""
  local function tick()
    local f = io.open(last_path, "r")
    if f then
      local name = f:read("*a") or ""
      f:close()
      if name ~= "" and name ~= last_seen then
        last_seen = name
        pcall(EveRagdollDeath_OnNativePlayShow, name)
      end
    end
    if type(ExecuteWithDelay) == "function" then
      ExecuteWithDelay(100, tick)
    end
  end
  if type(ExecuteWithDelay) == "function" then
    ExecuteWithDelay(800, tick)
  end
end
pcall(loadNative)
