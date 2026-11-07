-- Smash dispatch, visual effects and their recovery share the gore lifecycle's live queues.
return function(M, d)
local PARTS, FX, enemy = d.PARTS, d.FX, d.enemy
local cfg, addr, already_cut, log, hair_of = d.cfg, d.addr, d.already_cut, d.log, d.hair_of
local niagara, vec, bone_loc, norm, add, sub, scale, len = d.niagara, d.vec, d.bone_loc, d.norm, d.add, d.sub, d.scale, d.len
local load_obj, set_cap_material, mark, pick, track = d.load_obj, d.set_cap_material, d.mark, d.pick, d.track
local function try(...) local f = d.guards(); return f(...) end
local function valid(...) local _, f = d.guards(); return f(...) end
local function v3(...) return d.v3()(...) end
-- h: the killing blow (main.lua's death_hit: loc, push/dir). True when the smash started; false, "later" for her body
-- at the lethal hit (it needs her ragdoll: smashed at the death instead)
function M.smash(pawn, mesh, h, why)
  local s = cfg().smash or {}
  -- Full-body likelihood follows measured footprint coverage, including the hit's position.
  local volley = h and h.projectile and (h.volley or 0) >= 2
  local impactRadius = M.smashed.number(h and h.impactRadius, 0, 0, 500)
  local canFull = s.fullBody ~= false and impactRadius > 0 and M.cuts_on(mesh) == 0
    and valid(mesh) and (try(function() return mesh:GetBoneIndex(FName("Bip001-Spine1")) end) or -1) >= 0
    and not already_cut(mesh, "Bip001-Spine1")
  local coverage = canFull and M.smashed.coverage(mesh, h) or 0
  canFull = canFull and coverage > 0
  local base = M.smashed.number(s.fullBodyChance, 0.5, 0, 1)
  -- a simultaneous volley hits harder: each extra impact past the first adds 0.1, up to +0.3 (an explicit 0 stays never)
  if volley and base > 0 then base = math.min(1, base + math.min(0.3, 0.1 * ((h.volley or 2) - 1))) end
  local chance = base * coverage^2
  if h and h.smashFullRoll == nil then h.smashFullRoll = canFull and (chance >= 1 or (chance > 0 and math.random() < chance)) or false end
  local full = canFull and (h and h.smashFullRoll or (not h and (chance >= 1 or (chance > 0 and math.random() < chance))))
  local pose = h and h.pose
  local bone, d, kind, distances = M.smash_part(mesh, h and h.loc, full and "torso" or nil, pose, impactRadius)
  -- Reported impact points often cluster at the chest. The optional balance can redirect torso picks;
  -- otherwise use the nearest surviving head or limb. Persist the roll across deferred deaths.
  if not full and s.overrideTargets ~= true and kind == "torso" and h and h.loc then
    if h.smashTorsoRoll == nil then h.smashTorsoRoll = math.random() < M.smashed.number(s.torsoHitChance, 1, 0, 1) end
    if not h.smashTorsoRoll then
      local other, otherD, otherKind = M.smash_part(mesh, h.loc, "nonTorso", pose, impactRadius)
      if other then bone, d, kind = other, otherD, otherKind end
    end
  end
  if distances and distances ~= "" then log("smash candidates: bone distance / estimated surface distance (cm): " .. distances
    .. (pose and h.pose_ago and string.format(" (on her pose %.2f s before)", h.pose_ago) or "")) end
  if not bone then log("smash (" .. why .. "): nothing left to smash"); return false end
  if why == "after" and d and d > 55 + impactRadius then log(string.format("smash (after): nearest surviving part is %.0f cm away", d)); return false end
  if kind == "torso" and h and h.early then
    log("smash (" .. why .. "): her body, at her death")
    return false, "later"
  end
  full = full and kind == "torso"
  -- Remainder: the upper body already smashed, a blunt hit to a leg explodes what is left (pelvis and legs).
  -- No footprint needed: melee after-death hits carry none, and only the lower body remains.
  local remainder = not full and bone and kind == "limb" and (bone:find("Thigh") or bone:find("Calf"))
    and already_cut(mesh, "Bip001-Spine1") and s.fullBody ~= false
  if remainder then
    full = true
    log("smash: lower-body remainder: exploding what is left (" .. bone .. ")")
  end
  if volley then log(string.format("smash: %d distinct projectile reports; footprint still decides", h.volley)) end
  log(string.format("smash: impact radius %.1f cm (%s), body coverage %.0f%%, full-body chance %.1f%%: %s",
    impactRadius, h and h.impactSizeSource or "unknown", coverage * 100, canFull and chance * 100 or 0, full and "full body" or "local"))
  log(string.format("smash (%s): %s, %s", why, bone, d and string.format("%.0f cm from the blow", d) or "rolled (no blow seen)"))
  M.smash_once = true
  M.full_smash_once = full
  local ok, result = pcall(M.slice_bone, pawn, mesh, bone, h and h.loc, why)
  M.smash_once = nil
  M.full_smash_once = nil
  if not ok then error(result, 0) end
  return result
end
-- the piece hidden: its bones on her mesh and every part of her that has them (outfit pieces, a head's face), and
-- what rides them on a socket (a head's hair, earrings): PBO_None (0), only how they show (PBO_Term on her mesh
-- stopped her ragdoll, playtest 13)
function M.smashed.hide(q)
  local comps, seen = { q.mesh, q.c and q.c.face }, {}
  try(function() q.pawn.MeshInfoList:ForEach(function(_, e) comps[#comps + 1] = e:get().MeshComponent end) end)
  -- (her upper body takes the head along)
  local head = PARTS[q.bone] and (PARTS[q.bone].kind == "head" or PARTS[q.bone].kind == "torso")
  local nb, nv = 0, 0
  local started = os.clock()
  local function hide(c)
    local a = valid(c) and addr(c)
    if not a or seen[a] then return end
    seen[a] = true
    local index = try(function() return c:GetBoneIndex(FName(q.bone)) end)
    if type(index) == "number" and index >= 0
      and try(function() c:HideBoneByName(FName(q.bone), 0); return true end) then
      M.smashed.bones[#M.smashed.bones + 1] = { c = c, b = q.bone }
      nb = nb + 1
    end
  end
  for _, c in ipairs(comps) do hide(c) end
  local hiddenAt = os.clock()
  local function invisible(c)
    local a = valid(c) and addr(c)
    if a and not seen["v" .. a] and try(function() return c:IsVisible() end) == true
      and try(function() c:SetVisibility(false, false); return true end) then
      seen["v" .. a] = true
      M.smashed.shown[#M.smashed.shown + 1] = c
      nv = nv + 1
    end
  end
  if head then
    for _, c in ipairs(hair_of(q.pawn)) do invisible(c) end
    for _, nm in ipairs({ "SBHair", "SBPonytail", "SBPonytailShort" }) do invisible(try(function() return q.pawn[nm] end)) end
  end
  -- what rides the piece's bones on her mesh or face (not our caps and stubs: the piece's stay hidden, see stage_open)
  for _, m in ipairs({ q.mesh, q.c and q.c.face }) do
    if valid(m) then
      local kids, sockets = {}, {}
      try(function() m.AttachChildren:ForEach(function(_, e) kids[#kids + 1] = e:get() end) end)
      for _, k in ipairs(kids) do
        local s = valid(k) and try(function() return k:GetAttachSocketName():ToString() end)
        if s and s ~= "None" then
          local match = sockets[s]
          if match == nil then
            local bone = try(function() return m:GetSocketBoneName(FName(s)):ToString() end) or s
            match = bone == q.bone or try(function() return m:BoneIsChildOf(FName(bone), FName(q.bone)) end) == true
            sockets[s] = match
          end
          if match then invisible(k) end
        end
      end
    end
  end
  local ms = (os.clock() - started) * 1000
  if ms >= 10 then log(string.format("smash hide detail: %.0f ms: bones %.0f, attachments %.0f (%d meshes)", ms, (hiddenAt-started)*1000, (os.clock()-hiddenAt)*1000, #comps)) end
  return nb, nv
end
function M.smashed.back()
  local n = 0
  for _, e in ipairs(M.smashed.bones) do
    if valid(e.c) then try(function() e.c:UnHideBoneByName(FName(e.b)) end); n = n + 1 end
  end
  for _, c in ipairs(M.smashed.shown) do
    if valid(c) then try(function() c:SetVisibility(true, false) end); n = n + 1 end
  end
  M.smashed.bones, M.smashed.shown = {}, {}
  return n
end
-- One scaled burst per part: its spatial size follows remaining flesh, including prior missing children.
function M.smashed.blood(pawn, at, profile)
  local s = cfg().smash or {}
  if cfg().noBursts == true then return end
  local amount = (profile.blood or 0) * M.smashed.number(s.burstScale, 1, 0, 2)
  if amount <= 0 then return end
  local size = math.min(0.825, 0.825 * math.sqrt(amount / 36))
  local burst = niagara(s.burstFx or M.SMASH_BLOOD, pawn, nil, at, false, nil, vec(size, size, size), true)
  if not valid(burst) then log("smash: blood burst unavailable; using hit blood"); return end
  d.later()[#d.later() + 1] = { n = 2, fn = function()
    if valid(burst) then try(function() burst:Deactivate() end) end
  end }
  d.later()[#d.later() + 1] = { n = 180, fn = function()
    if valid(burst) then try(function() burst:K2_DestroyComponent(burst) end) end
  end }
end
-- F3 can enable Smash after the level's preload list was built. Add its assets ahead of the audio section,
-- under the same one-load-per-look budget, instead of first loading all four meat meshes in the death's frame.
function M.smashed.preload(w)
  local s = cfg().smash or {}
  if s.enabled ~= true and d.ctx().tune.dev ~= true then return end
  w.smashPaths = w.smashPaths or {}
  local paths = {}
  for _, p in ipairs(s.meshes or M.SMASH_MESHES) do paths[#paths + 1] = p end
  if cfg().blood ~= false then
    if s.splash == true then paths[#paths + 1] = s.fx or M.SMASH_FX end
    if s.burst ~= false then paths[#paths + 1] = s.burstFx or M.SMASH_BLOOD; paths[#paths + 1] = M.SMASH_GRINDER end
    paths[#paths + 1] = FX.hit
  end
  if s.material ~= false then paths[#paths + 1] = s.material or M.cap_mat() end
  for _, path in ipairs(paths) do
    if type(path) == "string" and not w.smashPaths[path] then
      w.smashPaths[path] = true
      table.insert(w.preload, w.sounds, path)
      w.next = math.min(w.next, w.sounds)
      w.sounds, w.told = w.sounds + 1, false
    end
  end
end
-- one chunk at `at`, flying at v (cm/s): an actor (in caps, destroyed with the cut) whose box simulates and
-- carries the meat mesh, scaled to cm across
function M.smashed.chunk(pawn, mesh, at, v, cm, sm, seamMaterial)
  local s = cfg().smash or {}
  cm = M.smashed.number(cm, 8, 1, 100)
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  local acls = load_obj("/Script/Engine.StaticMeshActor")
  local scls, mcls = load_obj("/Script/Engine.BoxComponent"), load_obj("/Script/Engine.StaticMeshComponent")
  if not (gs and acls and scls and mcls and sm) then return nil end
  local tm = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = at, Scale3D = vec(1, 1, 1) }
  local deferred = try(function() return gs:BeginDeferredActorSpawnFromClass(pawn, acls, tm, 1, nil) end)
  if not valid(deferred) then return nil end
  local a = try(function() return gs:FinishSpawningActor(deferred, tm) end)
  if not valid(a) then try(function() deferred:K2_DestroyActor() end); return nil end
  local root = try(function() return a.StaticMeshComponent end)
  if valid(root) then try(function() root:SetMobility(2) end); try(function() root:SetCollisionEnabled(0) end) end
  local id = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }
  local sp = try(function() return a:AddComponentByClass(scls, true, id, false) end)
  local m = try(function() return a:AddComponentByClass(mcls, true, id, false) end)
  if not (valid(sp) and valid(m)) then try(function() a:K2_DestroyActor() end); return nil end
  local b = try(function() local x = sm:GetBounds(); return { o = vec(x.Origin.X, x.Origin.Y, x.Origin.Z), e = vec(x.BoxExtent.X, x.BoxExtent.Y, x.BoxExtent.Z) } end)
  local big = b and math.max(b.e.X, b.e.Y, b.e.Z) or 0
  local k = big > 0.01 and cm / (2 * big) or 1
  local ok = try(function()
    sp:SetMobility(2)
    sp:K2_SetWorldLocationAndRotation(at, { Pitch = math.random() * 360, Yaw = math.random() * 360, Roll = math.random() * 360 }, false, {}, true)
    -- Match the mesh on each axis: the old fixed box extended beyond thin meshes and held them above the floor.
    local extent = b and vec(b.e.X * k * 0.85, b.e.Y * k * 0.85, b.e.Z * k * 0.85)
      or vec(cm * 0.30, cm * 0.24, cm * 0.17)
    sp:SetBoxExtent(vec(math.max(extent.X, 0.5), math.max(extent.Y, 0.5), math.max(extent.Z, 0.5)), false)
    sp:SetHiddenInGame(true, false)
    -- the level alone (WorldStatic, WorldDynamic): landing on her as well, the upper body's seven came out inside
    -- her hidden chest's bodies, still simulating, and the game froze 0.1 s on (the first upper body smash, F6)
    sp:SetCollisionProfileName(FName("PhysicsActor"), true)
    sp:SetCollisionObjectType(5) -- ECC_PhysicsBody even if another mod changed the profile
    sp:SetCollisionResponseToAllChannels(0)
    sp:SetCollisionResponseToChannel(0, 2)
    sp:SetCollisionResponseToChannel(1, 2)
    sp:SetCollisionEnabled(3)
    sp:SetGenerateOverlapEvents(false)
    try(function() sp.BodyInstance.bUseCCD = true end)
    m:SetMobility(2)
    m:SetStaticMesh(sm)
    m:SetCollisionEnabled(0)
    -- Share the surviving seam's actual instance: that includes its BloodColor, matte/Tachy settings and live
    -- tint changes. Without a cap, build the same material as a seam. A bare MI_A_Meat_01_1 glows orange.
    if s.material ~= false then
      local mat = type(s.material) == "string" and load_obj(s.material) or seamMaterial
      if not valid(mat) then
        set_cap_material(m, load_obj(M.cap_mat()))
        mat = try(function() return m:GetMaterial(0) end)
      end
      local nm = try(function() return m:GetNumMaterials() end) or 1
      if valid(mat) then for i = 0, math.max(nm, 1) - 1 do m:SetMaterial(i, mat) end end
    end
    m:K2_AttachToComponent(sp, FName("None"), 1, 1, 1, false)
    m:SetRelativeScale3D(vec(k, k, k))
    if b then m:K2_SetRelativeLocation(scale(b.o, -k), false, {}, true) end
    try(function() m:SetReceivesDecals(false) end)
    sp:SetSimulatePhysics(true)
    sp:SetMassOverrideInKg(FName("None"), M.smashed.number(s.kg, 0.3, 0.01, 10), true)
    try(function() sp:SetAngularDamping(M.smashed.number(s.angularDamping, 3, 0, 100)) end)
    sp:SetPhysicsLinearVelocity(v, false, FName("None"))
    sp:SetPhysicsAngularVelocityInDegrees(vec((math.random() - 0.5) * 1440, (math.random() - 0.5) * 1440, (math.random() - 0.5) * 720), false, FName("None"))
    return true
  end)
  if not ok then try(function() a:K2_DestroyActor() end); return nil end
  d.caps()[#d.caps() + 1] = a
  return sp
end
-- the piece of cut q goes: hidden, and the meat flies where it was, a couple of chunks a tick
function M.smashed.out(q)
  local s = cfg().smash or {}
  -- where it was: the middle of the part (the head's up past its bone), else the cut
  local p = PARTS[q.bone] or {}
  local seg = M.SMASH_SEG[q.bone]
  local a, b = bone_loc(q.mesh, seg and "Bip001-Spine1" or p.from or q.bone), bone_loc(q.mesh, seg and seg[2] or p.to or q.bone)
  local at = q.c.at
  if a and b then
    local k = p.kind == "head" and 2.2 or 0.5
    at = vec(a.X + (b.X - a.X) * k, a.Y + (b.Y - a.Y) * k, a.Z + (b.Z - a.Z) * k)
  end
  -- Capture the intact pose before hiding bones; spreading a full-body burst over it avoids a single visible nozzle.
  local sources = {}
  if q.fullSmash then
    for _, bone in ipairs({ "Bip001-Head", "Bip001-Spine2", "Bip001-Spine1", "Bip001-Pelvis",
      "Bip001-L-UpperArm", "Bip001-R-UpperArm", "Bip001-L-Forearm", "Bip001-R-Forearm",
      "Bip001-L-Thigh", "Bip001-R-Thigh", "Bip001-L-Calf", "Bip001-R-Calf" }) do
      local point = bone_loc(q.mesh, bone)
      if point then sources[#sources + 1] = vec(point.X, point.Y, point.Z) end
    end
  end
  -- Release held weapons while their hand and component are still visible and have their original transforms.
  if not enemy.cur and d.ctx().rag and d.ctx().rag.smash_drop then try(function() d.ctx().rag.smash_drop(q.pawn, q.mesh, q.bone) end) end
  -- HideBoneByName scales the subtree to zero: read its centre first, before its joints collapse together.
  local nb, nv = M.smashed.hide(q)
  if q.fullSmash then
    local legs = { pawn = q.pawn, mesh = q.mesh, c = q.c, bone = "Bip001-Pelvis" }
    local pidx = try(function() return q.mesh:GetBoneIndex(FName("Bip001-Pelvis")) end)
    local moreBones, moreVisible = M.smashed.hide(legs)
    nb, nv = nb + moreBones, nv + moreVisible
    -- the remainder's lower body stayed visible and hittable while the entry claimed all gone (playtest):
    -- whether the pelvis hide ran at all decides between a hide bug and an entry bug
    if moreBones == 0 then log(string.format("smash: full-body pelvis hide hid nothing (pelvis index %s)", tostring(pidx))) end
  end
  mark("smash hide")
  if not at then log("smash: nowhere to put the meat"); return end
  local profile = q.smashProfile or { count = 0, size = 1, blood = 0 }
  local n = profile.count
  local lo, hi = M.smashed.number(s.sizeMin, 7, 1, 100), M.smashed.number(s.sizeMax, 14, 1, 100)
  lo, hi = math.min(lo, hi), math.max(lo, hi)
  lo, hi = math.min(100, lo * profile.size), math.min(100, hi * profile.size)
  local speed = M.smashed.number(s.speed, 350, 0, 3000)
  local fly = q.fly and norm(q.fly)
  local meshes, meshPaths, meshNext = {}, s.meshes or M.SMASH_MESHES, 1
  local made, left = 0, n
  local chunks = {}
  local seam = q.seam
  if not valid(seam) then
    local cap = q.caps and q.caps[1]
    seam = valid(cap) and try(function() return cap:K2_GetRootComponent() end)
  end
  local material = valid(seam) and try(function() return seam:GetMaterial(0) end) or nil
  local drips = math.floor(M.smashed.number(s.drips, 3, 0, n))
  local pawn, mesh = q.pawn, q.mesh
  -- The torso's chunks are emitted over multiple ticks. Follow the surviving pelvis rather than
  -- continuing to emit at the suspended world position after the body has fallen away.
  local anchor = q.bone == "Bip001-Spine1" and bone_loc(mesh, "Bip001-Pelvis") or nil
  if anchor then anchor = vec(anchor.X, anchor.Y, anchor.Z) end
  mark("smash setup")
  local function batch()
    if not valid(pawn) then return end
    -- Start with the first available mesh; add more varieties as they load, one lookup per tick.
    -- Waiting for all of them left a visible gap between the smash and its first meat pieces.
    if meshNext <= #meshPaths then
      local o = load_obj(meshPaths[meshNext])
      if o then meshes[#meshes + 1] = o end
      meshNext = meshNext + 1
    end
    if #meshes == 0 then
      if meshNext <= #meshPaths then d.later()[#d.later() + 1] = { n = 1, fn = batch, label = "smash mesh load" }
      else log("smash: no meat meshes loaded for " .. q.bone) end
      return
    end
    local batchStart = os.clock()
    -- Cold chunk spawns can each be expensive; limit work before timing is known,
    -- while retaining every chunk and the existing slow-spawn time budget.
    for _ = 1, math.min((q.fullSmash or q.bone == "Bip001-Spine1") and 2 or 1, left) do
      left = left - 1
      -- out every way, more along the blow; almost flat so they scatter and arc instead of
      -- fountaining up, and spread wide so fresh chunks don't wake up overlapped and pop
      local r = norm(vec(math.random() - 0.5, math.random() - 0.5, (math.random() - 0.5) * 0.6)) or vec(0, 0, 1)
      local dir = fly and norm(add(scale(fly, 0.8), r)) or r
      local v = scale(dir, speed * (0.5 + math.random()))
      if q.bone == "Bip001-Spine1" then
        -- A steep hit could aim the whole 44-piece torso burst into the air. Keep the horizontal
        -- scatter and cap upward speed, so the pieces fall instead of forming a fountain.
        local horizontal = norm(vec(dir.X, dir.Y, 0)) or norm(vec(r.X, r.Y, 0)) or vec(1, 0, 0)
        local magnitude = speed * (0.5 + math.random())
        v = vec(horizontal.X * magnitude, horizontal.Y * magnitude, math.max(-magnitude * 0.20, math.min(v.Z, magnitude * 0.05)))
      end
      local spread = math.min(8 + n, 32)
      local off = vec((math.random() - 0.5) * spread, (math.random() - 0.5) * spread, (math.random() - 0.5) * spread)
      local origin = q.fullSmash and #sources > 0 and sources[(n - left - 1) % #sources + 1] or at
      if anchor then
        local now = valid(mesh) and bone_loc(mesh, "Bip001-Pelvis")
        if now then
          local d = sub(now, anchor)
          -- Do not follow a teleported/reused mesh or move the source upward with a bouncing pelvis.
          if len(d) < 300 then origin = add(origin, vec(d.X, d.Y, math.min(d.Z, 0))) end
        end
      end
      local cm = lo + math.random() * (hi - lo)
      local sp = M.smashed.chunk(pawn, mesh, add(origin, off), v, cm, pick(meshes), material)
      if sp then
        made = made + 1
        chunks[#chunks + 1] = sp
        -- Track every chunk of a full-body smash so each leaves a pool: the first-few cap left most
        -- meat with no blood under it (playtest). Creation, checks and growth stay on the shared spread
        -- budgets; local smashes keep the first-few cap.
        -- Size the pool past the meat sitting on it: a fixed small pool hid under its own chunk (playtest).
        if cfg().blood ~= false and made <= (q.fullSmash and n or math.max(1, drips)) then
          track(pawn, function()
            if not valid(sp) then return nil end
            return try(function() local l = sp:K2_GetComponentLocation(); return vec(l.X, l.Y, l.Z) end)
          end, "smash chunk", mesh, math.min(40, math.max(M.smashed.number(s.chunkPoolRadius, 11, 4, 20), cm * 1.5)),
            q.fullSmash or made > drips)
        end
      end
      -- A cold chunk spawn can be much slower than a warm one. Keep all the
      -- pieces, but leave the remaining work for later frames after a slow spawn.
      if os.clock() - batchStart >= 0.006 then break end
    end
    if left > 0 then d.later()[#d.later() + 1] = { n = 1, fn = batch, label = "smash chunks" }
    else
      log(string.format("smash: %d of %d meat chunks out at %s (%s)", made, n, v3(at), q.bone))
      -- (where they are 2 s on: they vanished at once, playtest)
      d.later()[#d.later() + 1] = { n = 60, fn = function()
        local out = {}
        for _, sp in ipairs(chunks) do
          out[#out + 1] = valid(sp) and v3(try(function() return sp:K2_GetComponentLocation() end)) or "gone"
        end
        log("smash: chunks 2 s on: " .. table.concat(out, " ") .. " (" .. q.bone .. ")")
      end }
    end
  end
  -- The opening already has seam, visibility and physics work. Spread chunk setup and the two effects
  -- across later ticks rather than starting them all in that frame.
  d.later()[#d.later() + 1] = { n = 2, fn = batch, label = "smash mesh load" }
  if cfg().blood ~= false then
    if s.burst ~= false then
      d.later()[#d.later() + 1] = { n = 1, label = "smash blood burst", fn = function()
        if valid(pawn) and cfg().blood ~= false then M.smashed.blood(pawn, at, profile) end
      end }
      if q.fullSmash then
        d.later()[#d.later() + 1] = { n = 3, label = "smash hit blood", fn = function()
          if not valid(pawn) or cfg().blood == false then return end
          local cloud = niagara(M.SMASH_GRINDER, pawn, nil, at, false, nil, nil, true)
          if not valid(cloud) then log("smash: grinder blood cloud unavailable"); return end
          -- The grinder is a cinematic loop: stop new particles promptly, then remove any lingering ones.
          d.later()[#d.later() + 1] = { n = 6, fn = function()
            if not valid(cloud) then return end
            local ok, err = pcall(function() cloud:Deactivate() end)
            if not ok then log("smash: grinder cloud would not stop: " .. tostring(err)) end
          end }
          d.later()[#d.later() + 1] = { n = 90, fn = function()
            if not valid(cloud) then return end
            -- (DeactivateImmediate is not on this build's component: it errored every full-body death, playtest)
            local ok2, err2 = pcall(function() cloud:K2_DestroyComponent(cloud) end)
            if not ok2 then log("smash: grinder cloud would not go: " .. tostring(err2)) end
          end }
        end }
      end
    end
    mark("smash burst queued")
    d.later()[#d.later() + 1] = { n = 4, label = "smash hit blood", fn = function()
      if not valid(pawn) or cfg().blood == false then return end
      if s.splash == true then niagara(s.fx or M.SMASH_FX, pawn, nil, at, false, nil, nil, true) end
      local hitScale = math.min(0.825, 0.825 * math.sqrt(math.max(0, profile.blood or 0) / 36))
      if hitScale > 0 then niagara(FX.hit, pawn, nil, at, false, nil, vec(hitScale, hitScale, hitScale), true) end
    end }
  end
  if cfg().blood ~= false and not q.fullSmash then
    d.later()[#d.later() + 1] = { n = 5, label = "smash splat", fn = function() if valid(pawn) and cfg().blood ~= false then M.splat(pawn, at) end end }
  end
  log(string.format("smash: %s gone (%d bones hidden, %d parts riding it hidden)", q.bone, nb, nv))
end
end
