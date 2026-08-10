-- EveRagdollDeath 0.3.3-probe
-- Death ragdoll gets a throw from last velocity / hit direction (not just sink).

local MOD, VER = "EveRagdollDeath", "0.3.3-probe"
local busy = false
local ragdolled = false
local pendingDeath = false
local AUTO_RAGDOLL = true
local cachedPawn = nil
local lastKnock = 0.0
local suppressTicks = 0
local lastVel = { X = 0, Y = 0, Z = 0 }
local lastHitDir = { X = 0, Y = 1, Z = 0.15 }

-- throw tuning
local THROW_SCALE = 2.2      -- multiply captured speed
local THROW_MIN = 450        -- uu/s floor so weak hits still fling
local THROW_MAX = 1800
local THROW_UP = 350         -- extra upward kick
local PELVIS = "Bip001-Pelvis"

local COLLISION_NO = 0
local COLLISION_QUERY_ONLY = 1
local COLLISION_QUERY_AND_PHYSICS = 3
local ECR_IGNORE, ECR_BLOCK = 0, 2
local ECC_WORLD_STATIC = 0
local ECC_PAWN, ECC_PHYSICS_BODY, ECC_VEHICLE, ECC_CAMERA = 2, 5, 6, 7
local MOVE_WALKING = 1

local function log(msg)
  print(string.format("[%s %s] %s", MOD, VER, tostring(msg)))
end

local function step(label, fn)
  log("try " .. label)
  local ok, err = pcall(fn)
  if not ok then
    log("FAIL " .. label .. ": " .. tostring(err))
    return false
  end
  log("ok  " .. label)
  return true
end

local function objName(obj)
  if not obj then return "<nil>" end
  local ok, n = pcall(function() return obj:GetFullName() end)
  return ok and tostring(n) or "<bad>"
end

local function isEvePawn(pawn)
  if not (pawn and pawn:IsValid()) then return false end
  local n = objName(pawn)
  return n:find("EVE", 1, true) and not n:find("Lobby", 1, true)
end

local function getPlayer()
  if isEvePawn(cachedPawn) then return cachedPawn end
  local pcs = FindAllOf("PlayerController") or {}
  for _, pc in pairs(pcs) do
    if pc and pc:IsValid() then
      local pawn = pc.AcknowledgedPawn or pc.Pawn or pc.Character
      if isEvePawn(pawn) then
        cachedPawn = pawn
        return pawn
      end
    end
  end
  for _, p in pairs(FindAllOf("CH_P_EVE_01_Blueprint_C") or {}) do
    if isEvePawn(p) then
      cachedPawn = p
      return p
    end
  end
  return nil
end

local function getMesh(pawn)
  if not pawn then return nil end
  if pawn.Mesh and pawn.Mesh:IsValid() then return pawn.Mesh end
  local m = nil
  pcall(function() m = pawn.CharacterMesh0 end)
  if m and m:IsValid() then return m end
  return nil
end

local function getAnim(pawn)
  local mesh = getMesh(pawn)
  if not mesh then return nil end
  local anim = nil
  pcall(function()
    if mesh.GetAnimInstance then anim = mesh:GetAnimInstance()
    else anim = mesh.AnimScriptInstance end
  end)
  if anim and anim:IsValid() then return anim end
  return nil
end

local function getKnockAlpha(anim)
  if not anim then return nil end
  local v = nil
  pcall(function()
    if anim.GetPropertyValue then
      v = anim:GetPropertyValue("KnockDown_FullBodyIK_Alpha")
    end
    if v == nil then v = anim.KnockDown_FullBodyIK_Alpha end
  end)
  if type(v) == "number" then return v end
  return nil
end

local function looksRelevant(name)
  name = tostring(name):lower()
  return name:find("knock", 1, true)
    or name:find("dead", 1, true)
    or name:find("death", 1, true)
    or name:find("result", 1, true)
    or name:find("corpse", 1, true)
    or name:find("down", 1, true)
    or name:find("hit", 1, true)
    or name:find("die", 1, true)
end

local function dumpKnockContext(anim, pawn)
  log("=== knock context ===")
  log("KnockDown_FullBodyIK_Alpha=" .. tostring(getKnockAlpha(anim)))
  pcall(function()
    local cls = anim:GetClass()
    if not (cls and cls.ForEachProperty) then return end
    cls:ForEachProperty(function(prop)
      local pname = nil
      pcall(function() pname = prop:GetFName():ToString() end)
      pname = tostring(pname or "")
      if not looksRelevant(pname) then return end
      local v = nil
      pcall(function()
        if anim.GetPropertyValue then v = anim:GetPropertyValue(pname)
        else v = anim[pname] end
      end)
      local t = type(v)
      if t == "boolean" or t == "number" or t == "string" then
        log(string.format("  anim.%s=%s:%s", pname, t, tostring(v)))
      end
    end)
  end)
end

local function isHairBone(name)
  name = name:lower()
  for _, h in ipairs({ "hair", "pony", "ponytail", "tail", "ribbon", "bang", "ahoge" }) do
    if name:find(h, 1, true) then return true end
  end
  return false
end

local function isSoftJiggleBone(name)
  name = name:lower()
  for _, s in ipairs({
    "breast", "boob", "bust", "mune", "oppai", "pec",
    "hip", "butt", "ass", "booty", "pelvis_soft",
  }) do
    if name:find(s, 1, true) then return true end
  end
  return false
end

local function boneNameOf(node)
  local n = nil
  pcall(function()
    if node.SpringBone and node.SpringBone.BoneName then
      local bn = node.SpringBone.BoneName
      n = bn.ToString and bn:ToString() or tostring(bn)
    elseif node.BoundBone and node.BoundBone.BoneName then
      local bn = node.BoundBone.BoneName
      n = bn.ToString and bn:ToString() or tostring(bn)
    elseif node.BoneName then
      local bn = node.BoneName
      n = bn.ToString and bn:ToString() or tostring(bn)
    end
  end)
  return n and tostring(n) or ""
end

local function muteHardJiggle(mesh)
  local anim = nil
  pcall(function()
    if mesh.GetAnimInstance then anim = mesh:GetAnimInstance()
    else anim = mesh.AnimScriptInstance end
  end)
  if not (anim and anim:IsValid()) then return end
  local muted, kept = 0, 0
  for i = 1, 32 do
    local names = {
      "AnimGraphNode_SpringBone_" .. i,
      "AnimGraphNode_AnimDynamics_" .. i,
    }
    if i == 1 then
      names[#names + 1] = "AnimGraphNode_SpringBone"
      names[#names + 1] = "AnimGraphNode_AnimDynamics"
    end
    for _, n in ipairs(names) do
      local node = nil
      pcall(function() node = anim[n] end)
      if node then
        local bn = boneNameOf(node)
        if bn ~= "" and isSoftJiggleBone(bn) then
          kept = kept + 1
        else
          pcall(function()
            if node.MaxDisplacement ~= nil then node.MaxDisplacement = 0.0 end
            if node.bTranslateX ~= nil then node.bTranslateX = false end
            if node.bTranslateY ~= nil then node.bTranslateY = false end
            if node.bTranslateZ ~= nil then node.bTranslateZ = false end
            if node.SpringStiffness ~= nil then node.SpringStiffness = 0.0 end
            if node.Alpha ~= nil then node.Alpha = 0.0 end
          end)
          muted = muted + 1
        end
      end
    end
  end
  log(string.format("springs muted=%d kept_soft=%d", muted, kept))
end

local function freezeHairBodies(mesh)
  local n = 0
  step("freeze hair", function()
    if not (mesh.GetNumBones and mesh.GetBoneName and mesh.SetBodySimulatePhysics) then
      error("no bone API")
    end
    for i = 0, mesh:GetNumBones() - 1 do
      local bn = mesh:GetBoneName(i)
      local name = bn.ToString and bn:ToString() or tostring(bn)
      if isHairBone(name) then
        pcall(function() mesh:SetBodySimulatePhysics(name, false, true) end)
        n = n + 1
      end
    end
  end)
  log("hair pinned=" .. tostring(n))
end

local function zeroVel(mesh)
  step("lin0", function()
    if mesh.SetAllPhysicsLinearVelocity then
      mesh:SetAllPhysicsLinearVelocity({ X = 0, Y = 0, Z = 0 }, false)
    end
  end)
  step("ang0", function()
    if mesh.SetAllPhysicsAngularVelocityInDegrees then
      mesh:SetAllPhysicsAngularVelocityInDegrees({ X = 0, Y = 0, Z = 0 }, false)
    end
  end)
end

local function vecLen(v)
  return math.sqrt((v.X or 0) ^ 2 + (v.Y or 0) ^ 2 + (v.Z or 0) ^ 2)
end

local function sampleVelocity(pawn)
  if not (pawn and pawn:IsValid()) then return end
  pcall(function()
    local move = pawn.CharacterMovement
    if move and move:IsValid() and move.Velocity then
      local v = move.Velocity
      local cand = { X = v.X or 0, Y = v.Y or 0, Z = v.Z or 0 }
      if vecLen(cand) > 80 then
        lastVel = cand
      end
    end
  end)
  -- SB / common hit-dir property names
  for _, name in ipairs({
    "LastHitDirection", "HitDirection", "DamageDirection",
    "KnockBackDirection", "KnockbackDirection", "LaunchVelocity",
    "LastDamageImpulse", "HitImpulse",
  }) do
    local ok, v = pcall(function()
      if pawn.GetPropertyValue then return pawn:GetPropertyValue(name) end
      return pawn[name]
    end)
    if ok and v then
      local x = v.X or v.x
      local y = v.Y or v.y
      local z = v.Z or v.z
      if type(x) == "number" and type(y) == "number" then
        local cand = { X = x, Y = y, Z = type(z) == "number" and z or 0 }
        if vecLen(cand) > 0.05 then
          lastHitDir = cand
        end
      end
    end
  end
end

local function applyDeathThrow(mesh, pawn, reason)
  sampleVelocity(pawn) -- one last read before movement is killed

  local dir = { X = lastHitDir.X, Y = lastHitDir.Y, Z = lastHitDir.Z }
  local dlen = vecLen(dir)
  local from = "hitDir"

  if dlen < 0.1 then
    dir = { X = lastVel.X, Y = lastVel.Y, Z = lastVel.Z }
    dlen = vecLen(dir)
    from = "velocity"
  end

  if dlen < 40 then
    -- fallback: fling opposite actor forward (away from facing)
    local f = nil
    pcall(function()
      if pawn.GetActorForwardVector then f = pawn:GetActorForwardVector() end
    end)
    if f then
      dir = { X = -(f.X or 0), Y = -(f.Y or 0), Z = 0.25 }
      dlen = vecLen(dir)
      from = "backwards"
    end
  end

  if dlen < 0.001 then
    dir = { X = 0, Y = 1, Z = 0.2 }
    dlen = vecLen(dir)
    from = "default"
  end

  local nx, ny, nz = dir.X / dlen, dir.Y / dlen, dir.Z / dlen
  local speed = vecLen(lastVel)
  local throw = speed * THROW_SCALE
  if throw < THROW_MIN then throw = THROW_MIN end
  if throw > THROW_MAX then throw = THROW_MAX end

  local vx = nx * throw
  local vy = ny * throw
  local vz = math.max(nz * throw, 0) + THROW_UP

  log(string.format(
    "throw from=%s speed=%.0f -> vel=(%.0f,%.0f,%.0f) reason=%s",
    from, speed, vx, vy, vz, tostring(reason)
  ))

  step("throw linear vel", function()
    if mesh.SetAllPhysicsLinearVelocity then
      mesh:SetAllPhysicsLinearVelocity({ X = vx, Y = vy, Z = vz }, false)
    end
  end)

  step("throw pelvis impulse", function()
    if mesh.AddImpulse then
      mesh:AddImpulse({ X = vx * 80, Y = vy * 80, Z = vz * 80 }, PELVIS, false)
    end
  end)

  -- angular spin so limbs whip instead of rigid slide
  step("throw angular", function()
    if mesh.SetAllPhysicsAngularVelocityInDegrees then
      mesh:SetAllPhysicsAngularVelocityInDegrees({
        X = (ny - nz) * 120,
        Y = (nz - nx) * 120,
        Z = (nx - ny) * 80,
      }, false)
    end
  end)
end

-- Undo everything doFull did so respawn is playable.
local function undoRagdoll(reason)
  log("UNDO ragdoll (" .. tostring(reason) .. ")")
  local pawn = getPlayer()
  local mesh = getMesh(pawn)
  pcall(function()
    if mesh and mesh:IsValid() then
      if mesh.SetAllBodiesSimulatePhysics then mesh:SetAllBodiesSimulatePhysics(false) end
      if mesh.SetAllBodiesPhysicsBlendWeight then
        mesh:SetAllBodiesPhysicsBlendWeight(0.0, false)
      end
      mesh.bBlendPhysics = false
      mesh.GlobalAnimRateScale = 1.0
      -- character mesh: no physics collision; capsule owns world collision
      mesh:SetCollisionEnabled(COLLISION_NO)
      if mesh.PutAllRigidBodiesToSleep then mesh:PutAllRigidBodiesToSleep() end
    end
  end)
  pcall(function()
    if not (pawn and pawn:IsValid()) then return end
    local anim = getAnim(pawn)
    if anim then
      pcall(function() anim.KnockDown_FullBodyIK_Alpha = 0.0 end)
    end
    local cap = pawn.CapsuleComponent
    if cap and cap:IsValid() then
      cap:SetCollisionEnabled(COLLISION_QUERY_AND_PHYSICS)
      if cap.SetCollisionResponseToAllChannels then
        -- restore sensible defaults
        cap:SetCollisionResponseToAllChannels(ECR_BLOCK)
        cap:SetCollisionResponseToChannel(ECC_CAMERA, ECR_IGNORE)
        cap:SetCollisionResponseToChannel(ECC_PHYSICS_BODY, ECR_IGNORE)
      end
      if cap.SetCollisionObjectType then
        cap:SetCollisionObjectType(ECC_PAWN)
      end
    end
    local move = pawn.CharacterMovement
    if move and move:IsValid() then
      if move.SetMovementMode then move:SetMovementMode(MOVE_WALKING) end
      if move.SetDefaultMovementMode then pcall(function() move:SetDefaultMovementMode() end) end
      pcall(function() move.Velocity = { X = 0, Y = 0, Z = 0 } end)
    end
  end)
  ragdolled = false
  busy = false
  pendingDeath = false
  lastKnock = 0.0
end

local function killKnockAnim(pawn, mesh)
  pcall(function()
    if mesh and mesh:IsValid() then mesh.GlobalAnimRateScale = 0.0 end
  end)
  pcall(function()
    local anim = getAnim(pawn)
    if anim then anim.KnockDown_FullBodyIK_Alpha = 0.0 end
  end)
end

local function doFull(reason)
  if busy or ragdolled then return end
  busy = true
  pcall(function()
    local pawn = getPlayer()
    local mesh = getMesh(pawn)
    if not mesh then
      log("no mesh (" .. tostring(reason) .. ")")
      return
    end
    log("RAGDOLL BEGIN reason=" .. tostring(reason))
    sampleVelocity(pawn)

    local anim = getAnim(pawn)
    dumpKnockContext(anim, pawn)
    killKnockAnim(pawn, mesh)

    local move = pawn.CharacterMovement
    if move and move:IsValid() then
      sampleVelocity(pawn)
      step("StopMovement", function() move:StopMovementImmediately() end)
      step("DisableMovement", function() move:DisableMovement() end)
    end

    local cap = pawn.CapsuleComponent
    if cap and cap:IsValid() then
      step("capsule off", function()
        cap:SetCollisionEnabled(COLLISION_NO)
        if cap.SetCollisionResponseToAllChannels then
          cap:SetCollisionResponseToAllChannels(ECR_IGNORE)
        end
      end)
    end

    muteHardJiggle(mesh)
    -- keep anim rate 0 so knockdown sequence cannot advance; soft springs still evaluate at 0Hz
    -- (blend physics owns pose). Soft jiggle will be weak until we find a better split.
    step("keep anim frozen", function() mesh.GlobalAnimRateScale = 0.0 end)
    killKnockAnim(pawn, mesh)

    step("mesh QueryAndPhysics", function()
      mesh:SetCollisionEnabled(COLLISION_QUERY_AND_PHYSICS)
    end)
    step("object type PhysicsBody", function()
      if mesh.SetCollisionObjectType then mesh:SetCollisionObjectType(ECC_PHYSICS_BODY) end
    end)
    step("responses floor-only", function()
      mesh:SetCollisionResponseToAllChannels(ECR_IGNORE)
      mesh:SetCollisionResponseToChannel(ECC_WORLD_STATIC, ECR_BLOCK)
      mesh:SetCollisionResponseToChannel(ECC_PAWN, ECR_IGNORE)
      mesh:SetCollisionResponseToChannel(ECC_PHYSICS_BODY, ECR_IGNORE)
      mesh:SetCollisionResponseToChannel(ECC_VEHICLE, ECR_IGNORE)
      mesh:SetCollisionResponseToChannel(ECC_CAMERA, ECR_IGNORE)
    end)
    step("bBlendPhysics", function() mesh.bBlendPhysics = true end)
    step("SetAllBodiesSimulatePhysics(true)", function()
      mesh:SetAllBodiesSimulatePhysics(true)
    end)
    step("blend weight 1", function()
      if mesh.SetAllBodiesPhysicsBlendWeight then
        mesh:SetAllBodiesPhysicsBlendWeight(1.0, false)
      end
    end)
    freezeHairBodies(mesh)
    step("damp", function()
      if mesh.SetLinearDamping then mesh:SetLinearDamping(3.0) end
      if mesh.SetAngularDamping then mesh:SetAngularDamping(4.0) end
    end)
    applyDeathThrow(mesh, pawn, reason)
    step("WakeAllRigidBodies", function()
      if mesh.WakeAllRigidBodies then mesh:WakeAllRigidBodies() end
    end)

    ragdolled = true
    pendingDeath = false
    if type(ExecuteWithDelay) == "function" then
      ExecuteWithDelay(30, function()
        pcall(function()
          if mesh and mesh:IsValid() then
            freezeHairBodies(mesh)
            killKnockAnim(pawn, mesh)
            -- do NOT zeroVel here — that killed the throw in older builds
          end
        end)
        log("post-settle")
      end)
    end
    log("RAGDOLL END")
  end)
  busy = false
end

local function onKnockRise(alpha)
  if not AUTO_RAGDOLL then return end
  if ragdolled or busy or pendingDeath then return end
  if suppressTicks > 0 then return end
  pendingDeath = true
  log(string.format("knock rise %.3f -> ragdoll", alpha))
  -- kill anim THIS tick before retries
  local pawn = getPlayer()
  killKnockAnim(pawn, getMesh(pawn))
  local tries = 0
  local function try()
    tries = tries + 1
    if ragdolled then return end
    killKnockAnim(getPlayer(), getMesh(getPlayer()))
    doFull(string.format("KnockDown_FullBodyIK_Alpha=%.3f", alpha))
    if not ragdolled and tries < 25 and type(ExecuteWithDelay) == "function" then
      ExecuteWithDelay(16, try)
    else
      pendingDeath = false
    end
  end
  if type(ExecuteWithDelay) == "function" then
    ExecuteWithDelay(0, try)
  else
    try()
  end
end

local function pollKnock()
  if suppressTicks > 0 then
    suppressTicks = suppressTicks - 1
  end
  local pawn = getPlayer()
  if pawn then
    cachedPawn = pawn
    if not ragdolled then sampleVelocity(pawn) end
  end
  local anim = getAnim(pawn)
  local k = getKnockAlpha(anim)
  if k == nil then return end

  -- any rise off zero — earlier than waiting for 0.5
  if k > 0.02 and lastKnock <= 0.02 then
    onKnockRise(k)
  end

  -- respawn / recover: knock cleared while we were ragdolled
  if ragdolled and k < 0.05 and lastKnock >= 0.05 then
    undoRagdoll("knock-cleared")
    suppressTicks = 40
  end
  if (not ragdolled) and k < 0.05 and lastKnock >= 0.05 then
    suppressTicks = 20
    log("knock fell — suppress")
  end
  lastKnock = k
end

local function watchTick()
  ExecuteWithDelay(16, function()
    pcall(pollKnock)
    watchTick()
  end)
end

local function onRestart()
  local was = ragdolled or pendingDeath
  log("ClientRestart — wasRagdoll=" .. tostring(was))
  busy = false
  pendingDeath = false
  cachedPawn = nil
  lastKnock = 0.0
  suppressTicks = 50
  local function finish(tag)
    cachedPawn = nil
    getPlayer()
    if was or ragdolled then
      undoRagdoll(tag)
    else
      -- still clear flags; light restore if mesh stuck simulating
      local mesh = getMesh(getPlayer())
      local sim = false
      pcall(function()
        if mesh and mesh.IsAnySimulatingPhysics then sim = mesh:IsAnySimulatingPhysics() end
      end)
      if sim then undoRagdoll(tag .. "-sim") end
      ragdolled = false
    end
    suppressTicks = 50
    lastKnock = 0.0
  end
  if type(ExecuteWithDelay) == "function" then
    ExecuteWithDelay(100, function() finish("ClientRestart") end)
    ExecuteWithDelay(600, function() finish("ClientRestart-late") end)
  else
    finish("ClientRestart")
  end
end

pcall(function()
  RegisterHook("/Script/Engine.PlayerController:ClientRestart", onRestart)
  log("hooked ClientRestart")
end)

RegisterKeyBind(0x77, function()
  log("F8")
  ragdolled = false
  pendingDeath = false
  doFull("F8")
end)

RegisterKeyBind(0x78, function()
  log("F9")
  local pawn = getPlayer()
  local anim = getAnim(pawn)
  log("pawn=" .. objName(pawn))
  log("knock=" .. tostring(getKnockAlpha(anim)))
  log("AUTO=" .. tostring(AUTO_RAGDOLL) .. " ragdolled=" .. tostring(ragdolled))
  dumpKnockContext(anim, pawn)
end)

RegisterKeyBind(0x79, function()
  AUTO_RAGDOLL = not AUTO_RAGDOLL
  log("AUTO_RAGDOLL=" .. tostring(AUTO_RAGDOLL))
end)

RegisterKeyBind(0x76, function() -- F7 manual un-ragdoll
  log("F7 undo")
  undoRagdoll("F7")
end)

log("loaded — knock ragdoll + death throw · F7 undo · F8 force · F9 dump")
if type(ExecuteWithDelay) == "function" then
  watchTick()
end
