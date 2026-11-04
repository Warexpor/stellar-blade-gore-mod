-- Smash test world: real Lua, fake engine calls, plus sphere flight against a floor and a wall.
-- This is a contract/ballistics model, not PhysX: it can catch unsafe collision masks and lifecycle mistakes,
-- but cannot reproduce the game's solver, asset geometry or audio renderer.
local S = {}
function S.boot(settings)
  local F, E = require("fake"), require("eve")
  local pawn = E.make(F)
  local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
  local f = assert(io.open(DIR .. "settings.lua", "w"))
  f:write('local s = dofile("' .. DIR .. 'settings.default.lua")\ns.dev = true\n' .. (settings or "") .. '\ns.gore.smash.torsoHitChance = 1\nreturn s\n')
  f:close()
  F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
  F.sbslice.k, F.sbslice.f = "ok collapsed 2", "ok photo shield 1"
  local function v(x, y, z) return { X = x, Y = y, Z = z } end
  local function copy(p) return v(p.X, p.Y, p.Z) end
  local actors, spheres, violations = {}, {}, {}
  local world = { actors = actors, spheres = spheres, violations = violations }
  for _, n in ipairs({ "StaticMeshActor", "BoxComponent", "StaticMeshComponent" }) do
    F.objects["/Script/Engine." .. n] = F.obj(n, "Class")
  end
  local function component(actor, cls)
    if world.failClass == cls then return nil end
    local c = F.obj(cls .. "_" .. #actors, cls, { BodyInstance = {}, at = copy(actor.at), resp = {}, objType = 1 })
    actor.comps[#actor.comps + 1] = c
    c.SetMobility = function(self, n) self.mobility = n end
    c.SetCollisionEnabled = function(self, n) self.collision = n end
    c.SetCollisionProfileName = function(self) self.objType = world.profileType or 5 end
    c.SetCollisionObjectType = function(self, n) self.objType = n end
    c.SetCollisionResponseToAllChannels = function(self, n) for i = 0, 31 do self.resp[i] = n end end
    c.SetCollisionResponseToChannel = function(self, ch, n) self.resp[ch] = n end
    c.SetGenerateOverlapEvents = function(self, on) self.overlaps = on end
    c.K2_SetWorldLocationAndRotation = function(self, at) self.at = copy(at); self.spawnAt = copy(at) end
    c.K2_GetComponentLocation = function(self) return copy(self.at) end
    c.SetBoxExtent = function(self, e) self.extent = copy(e); self.radius = e.X end
    c.SetHiddenInGame = function(self, on) self.hidden = on end
    c.SetStaticMesh = function(self, sm) self.sm = sm end
    c.GetNumMaterials = function() return 2 end
    c.SetMaterial = function(self, i, m) self.mats = self.mats or {}; self.mats[i] = m end
    c.GetMaterial = function(self, i) return self.mats and self.mats[i] end
    c.CreateDynamicMaterialInstance = function(self, i, mat)
      local mid = F.obj("ChunkMID", "MaterialInstanceDynamic", { Parent = mat, scalars = {}, vectors = {}, textures = {} })
      mid.SetScalarParameterValue = function(m, key, value) m.scalars[tostring(key)] = value end
      mid.SetVectorParameterValue = function(m, key, value) m.vectors[tostring(key)] = value end
      mid.SetTextureParameterValue = function(m, key, value) m.textures[tostring(key)] = value end
      mid.K2_GetScalarParameterValue = function(m, key) return m.scalars[tostring(key)] end
      mid.K2_GetVectorParameterValue = function(m, key) return m.vectors[tostring(key)] end
      mid.K2_GetTextureParameterValue = function(m, key) return m.textures[tostring(key)] end
      self:SetMaterial(i, mid)
      return mid
    end
    c.K2_AttachToComponent = function(self, parent) self.parent = parent end
    c.SetRelativeScale3D = function(self, k) self.scale = copy(k) end
    c.K2_SetRelativeLocation = function(self, p) self.offset = copy(p) end
    c.SetMassOverrideInKg = function(self, _, n) self.kg = n end
    c.SetAngularDamping = function(self, n) self.angularDamping = n end
    c.SetPhysicsLinearVelocity = function(self, p) self.vel = copy(p) end
    c.SetPhysicsAngularVelocityInDegrees = function(self, p) self.ang = copy(p) end
    c.SetSimulatePhysics = function(self, on)
      if world.throwPhysics then error("injected physics failure") end
      self.sim = on
      if on and (self.collision ~= 3 or self.resp[2] ~= 0 or self.resp[5] ~= 0 or self.resp[0] ~= 2) then
        violations[#violations + 1] = "unsafe collision mask when physics started"
      end
    end
    if cls == "BoxComponent" then spheres[#spheres + 1] = c end
    return c
  end
  local gs = F.obj("Default__GameplayStatics", "GameplayStatics")
  gs.BeginDeferredActorSpawnFromClass = function(_, _, cls, tm)
    if world.failSpawn then return nil end
    local a = F.obj("ChunkActor_" .. (#actors + 1), "StaticMeshActor", { at = copy(tm.Translation), comps = {} })
    actors[#actors + 1] = a
    a.StaticMeshComponent = component(a, "StaticMeshComponent")
    a.AddComponentByClass = function(self, c) return component(self, c.__name) end
    a.K2_DestroyActor = function(self)
      self.__dead = true
      for _, c in ipairs(self.comps) do c.__dead = true end
    end
    a.SetActorHiddenInGame = function(self, on) self.hidden = on end
    a.K2_GetRootComponent = function(self) return self.StaticMeshComponent end
    a.K2_SetActorLocation = function(self, pos) self.at = copy(pos); self.StaticMeshComponent.at = copy(pos) end
    a.K2_SetActorRotation = function(self, rot) self.rot = rot end
    a.SetActorScale3D = function(self, size) self.scale = copy(size) end
    a.K2_AttachToComponent = function(self, parent, bone) self.parent, self.bone = parent, bone end
    return a
  end
  gs.FinishSpawningActor = function(_, a) if world.failFinish then return nil end return a end
  F.objects["/Script/Engine.Default__GameplayStatics"] = gs
  F.objects["/Engine/BasicShapes/Sphere.Sphere"] = F.obj("FlowSphere", "StaticMesh")
  for i = 1, 4 do
    local n = "SM_meat_0" .. i
    F.objects["/Game/Art/FX/SM/" .. n .. "." .. n] = F.obj(n, "StaticMesh", {
      GetBounds = function() return { Origin = v(3, -2, 1), BoxExtent = v(10, 5, 4) } end,
    })
  end
  F.objects["/Game/Art/FX/MA/Enviroment/MI_A_Meat_01_1.MI_A_Meat_01_1"] = F.obj("Meat", "MaterialInstanceConstant")
  local face = F.obj("Face", "SkeletalMeshComponent", { SkeletalMesh = F.obj("CH_P_EVE_Face", "SkeletalMesh") })
  face.GetBoneIndex, face.GetSocketLocation, face.GetSocketTransform = E.mesh.GetBoneIndex, E.mesh.GetSocketLocation, E.mesh.GetSocketTransform
  face.GetNumBones, face.GetBoneName, face.GetParentBone = E.mesh.GetNumBones, E.mesh.GetBoneName, E.mesh.GetParentBone
  face.hiddenBones = {}
  face.HideBoneByName = function(self, b) self.hiddenBones[tostring(b)] = true end
  face.UnHideBoneByName = function(self, b) self.hiddenBones[tostring(b)] = nil end
  face.GetNumMaterials = function() return 1 end
  pawn.MeshInfoList = { ForEach = function(_, cb) cb(1, { get = function() return { MeshSlot = 1, MeshComponent = face } end }) end }
  E.mesh.BoneIsChildOf = function(_, b, parent)
    local n = E.PARENT[tostring(b)]
    while n do if n == tostring(parent) then return true end; n = E.PARENT[n] end
    return false
  end
  -- Capture existing modules through their normal loader; production scripts are never rewritten for a test.
  local original = dofile
  local G, ctx
  dofile = function(path)
    local result = original(path)
    if path == DIR .. "gore.lua" then
      G = result
      local init = G.init
      G.init = function(c) ctx = c; return init(c) end
    end
    return result
  end
  local ok, err = pcall(dofile, DIR .. "main.lua")
  dofile = original
  assert(ok, err)
  F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
  F.run(16, pawn)
  -- Find private closure state without adding test exports to the mod.
  local state, seen = {}, {}
  local function scan(fn)
    if type(fn) ~= "function" or seen[fn] then return end
    seen[fn] = true
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == "sw" or name == "swing" or name == "hm" or name == "death_hit" or name == "gore_cut" or name == "hits_after" then state[name] = value end
      if name ~= "_ENV" then scan(value) end
    end
  end
  for _, callbacks in pairs(F.hooks) do for _, fn in ipairs(callbacks) do scan(fn) end end
  for _, b in ipairs(F.binds) do scan(b.cb) end
  world.step = function(dt)
    for _, c in ipairs(spheres) do
      if not c.__dead and c.sim and c.vel then
        c.vel.Z = c.vel.Z - 980 * dt
        local p = c.at
        p.X, p.Y, p.Z = p.X + c.vel.X * dt, p.Y + c.vel.Y * dt, p.Z + c.vel.Z * dt
        if c.resp[0] == 2 and p.Z < c.radius then
          p.Z = c.radius
          c.vel.Z = math.abs(c.vel.Z) > 30 and math.abs(c.vel.Z) * 0.15 or 0
          c.vel.X, c.vel.Y = c.vel.X * 0.8, c.vel.Y * 0.8
        end
        -- CCD-like sweep against a world-dynamic wall at x=1100.
        if c.resp[1] == 2 and p.X > 1100 - c.radius then p.X = 1100 - c.radius; c.vel.X = -math.abs(c.vel.X) * 0.15 end
      end
    end
  end
  F.world = world.step
  return { F = F, E = E, G = G, ctx = ctx, state = state, pawn = pawn, face = face, world = world, v = v, dir = DIR }
end
return S
