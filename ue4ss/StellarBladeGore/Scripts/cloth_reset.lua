-- Spawn and outfit-change cloth reset, collision restoration and guarded hair simulation.
return function(screen, goreCtx, hm, get_active, get_rag, get_gore, sandbox_recover, try, valid, log)
-- her ponytail as she comes into the world: it starts through her hair tie, or on top of her sword on her back, and
-- jiggles there till photo mode is opened and closed (playtests). It is cloth (SBPonytail, no animation of its own: the
-- hair's KawaiiPhysics only moves her front and side strands) and collides with her bodies. physfix.lua re-makes her
-- bodies as she spawns (SetPhysicsAsset), and the cloth settles on the wrong side of her hair tie, kept there by
-- those collisions: the cloth and anim dynamics resets, the game's own cloth set up again
-- (NeedPonytailClothConfigUpdate) and passes of them at 0.3-5.5 s each ran the cloth again from where the collisions
-- let it, and it came back off the tie (0.4.1 playtests). Photo mode puts it right because it switches every character
-- mesh's collision to query only while it is on (0x1423a33e0): the cloth falls back through the tie with nothing
-- in its way, and stays there once the collision is back. So the reset does what photo mode does: CLOTH_AFTER s after
-- the last of a new Eve, a respawn, an outfit change or her bodies re-made (each starts the wait again), her meshes'
-- collision goes to query only (hits still find her) and the cloth is reset once, and the collision is given back
-- 1.5 s later, the cloth left to settle through the tie meanwhile, as photo mode leaves it. The game's set up again
-- (NeedPonytailClothConfigUpdate) and a second reset half a second later made her hair snap three times as she
-- spawned (playtest): neither is asked any more. Given back at once should she die or photo mode open meanwhile. The
-- log lists each mesh with its animation (`cloth: meshes ...`). Hair simulated on her own mesh (CH_P_EVE_30's
-- ponytail, Ab-TL-HairB01-09) stops while it is query only and went right onto her pose, then snapped back wrong as
-- the collision came back and it simulated on from where it had been (playtest, F8 put it right): it is kinematic for
-- 0.15 s as the collision comes back, onto her pose, and simulated from there
screen.CLOTH_AFTER = { 4, 5.5 }
function screen.cloth_soon(why)
  screen.cloth_restore()
  screen.cloth = { at = os.clock(), i = 1, why = why }
end
-- her bodies re-made with a fixed physics asset (physfix.lua): her ponytail's cloth set up again after it
goreCtx.on_remade = function() screen.cloth_soon("her bodies re-made") end
-- (the class walk per reset stage: StaticFindObject hashes the engine's object list, so hold the native
-- class across stages on screen itself: a chunk-level local would breach Lua's 200-locals limit here.
-- Native classes persist for the process lifetime, like load_obj's /Script/ cache.)
function screen.cloth_meshes(pawn)
  local out, seen = {}, {}
  if not valid(screen.clothSMC) then screen.clothSMC = StaticFindObject("/Script/Engine.SkeletalMeshComponent") end
  local cls = screen.clothSMC
  local function walk(c, depth)
    if not valid(c) or depth > 8 then return end
    local a = c:GetAddress()
    if seen[a] then return end
    seen[a] = true
    if try(function() return c:IsA(cls) end) then out[#out + 1] = c end
    local kids = {}
    try(function() c.AttachChildren:ForEach(function(_, e) kids[#kids + 1] = e:get() end) end)
    for _, k in ipairs(kids) do walk(k, depth + 1) end
  end
  walk(try(function() return pawn.RootComponent end), 0)
  return out
end
-- the collision taken off her meshes, given back (each kept, asked alive first: a level change frees them)
function screen.cloth_restore(noSimReset)
  local list = screen.clothColl
  screen.clothColl = nil
  if not list or #list == 0 then return 0 end
  local n = 0
  if goreCtx.alive_ask(list) then
    for _, k in ipairs(list) do
      if k.alive and valid(k.obj) and try(function() k.obj:SetCollisionEnabled(k.was); return true end) then
        n = n + 1
        -- (its simulated hair kinematic for a moment: back onto the animation's pose, simulated again from there)
        if k.sim and not noSimReset then
          for _, b in ipairs(k.sim) do try(function() k.obj:SetAllBodiesBelowSimulatePhysics(FName(b), false, true) end) end
          screen.clothSim = { k = k, at = os.clock() }
        end
      end
    end
  end
  return n
end
-- a ragdoll starting inside the 1.5 s her meshes are query only (an outfit's bodies re-made just before: F7 a
-- second after a change): their collision given back first, before the ragdoll reads and sets it. Given back after
-- (cloth_tick, the next tick) it put her hair's collision on again over the ragdoll's off, her head's bodies
-- shoved by her own hair flew her 9 m up (playtest), and the query-only state was what the ragdoll's end put back
function screen.cloth_give_back()
  if not screen.clothColl then return end
  local n = screen.cloth_restore()
  screen.cloth = nil
  log(string.format("cloth: her meshes' collision given back before her ragdoll (%d)", n))
end
-- the bodies on her mesh that simulate while she lives, not under a simulating Bip001 bone (a piece cut off her):
-- her hair's (CH_P_EVE_30's ponytail, Ab-TL-HairB01-09)
-- A bone's first Bip001 ancestor never changes under a mesh asset, but the walk up to it cost a parent-bone engine
-- read per level per reset (tens of reads on a respawn's tick). Resolve each bone's ancestor once per asset and only
-- re-ask whether the bones simulate: the bone list comes from the physics layout's own cache, so a rebuilt layout
-- (a new table) invalidates the entry with it.
screen.simReach = screen.simReach or {}
function screen.sim_bodies(mesh)
  local rag = get_rag()
  local out = {}
  if not (rag and rag.bodies) then return out end
  local function sim(b) return try(function() return mesh:IsSimulatingPhysics(FName(b)) end) == true end
  local bones = rag.bodies(mesh)
  local addr = try(function() return mesh:GetAddress() end) or 0
  local entry = screen.simReach[addr]
  if not entry or entry.list ~= bones then
    entry = { list = bones, bip = {} }
    screen.simReach[addr] = entry
    for _, b in ipairs(bones) do
      if b:sub(1, 6) ~= "Bip001" then
        local p, found = b, false
        for _ = 1, 32 do
          p = try(function() return mesh:GetParentBone(FName(p)):ToString() end)
          if not p or p == "None" then break end
          if p:sub(1, 6) == "Bip001" then found = p; break end
        end
        entry.bip[b] = found
      end
    end
  end
  for _, b in ipairs(bones) do
    if b:sub(1, 6) ~= "Bip001" and sim(b) then
      local found = entry.bip[b]
      if found == false or (found and not sim(found)) then out[#out + 1] = b end
    end
  end
  return out
end
-- her hair simulated again, a moment after the collision came back
function screen.cloth_sim_tick()
  local s = screen.clothSim
  if not s or os.clock() - s.at < 0.15 then return end
  screen.clothSim = nil
  local n = 0
  if goreCtx.alive_ask({ s.k }) and s.k.alive and valid(s.k.obj) then
    for _, b in ipairs(s.k.sim) do
      if try(function() s.k.obj:SetAllBodiesBelowSimulatePhysics(FName(b), true, true); return true end) then n = n + 1 end
    end
  end
  log(string.format("cloth: her hair's %d simulated bodies simulate again from her pose (%d)", #s.k.sim, n))
end
-- F8 by itself AUTO_F8_S s after the spawn's cloth reset is done: her ponytail still sat wrong on some spawns, and
-- F8 put it right every time (playtest). Only while she is up, whole and out of photo mode; else it waits
screen.AUTO_F8_S = 2
-- A cinematic camera is cheap to recognize every poll. When a reset is actually due, also check
-- active level sequences, including cutscenes that have not switched to their camera yet.
function screen.cloth_scene(pawn, sequences)
  screen.view(pawn)
  if (screen.vtClass or ""):lower():find("cinecamera", 1, true) then
    screen.clothSceneReason = "camera " .. screen.vtClass
    return true
  end
  if not sequences then return false end
  local blockers = {}
  for _, actor in ipairs(try(function() return FindAllOf("LevelSequenceActor") end) or {}) do
    local player = valid(actor) and try(function() return actor.SequencePlayer end)
    if valid(player) and try(function() return player:IsPlaying() end) == true then
      local name = try(function() return actor:GetFullName() end) or "unknown"
      -- Ambient environment loops (Xion, WLA hill drone, B07 bridge lights, SE05 cranes/robots) animate during
      -- ordinary gameplay and must not block the spawn ponytail reset; only real cutscenes block it. The reset was
      -- skipped through whole sessions by a looping light, leaving the ponytail wrong into cutscenes.
      if not name:find("EnvObj_", 1, true) and not name:match(":PersistentLevel%.EnvObj_SE05_[%w_]+$") then
        blockers[#blockers + 1] = name
      end
    end
  end
  if #blockers > 0 then
    screen.clothSceneReason = "sequence " .. table.concat(blockers, "; ")
    return true
  end
  return false
end
function screen.auto_f8(pawn)
  local gore = get_gore()
  if not screen.autoF8 or os.clock() < screen.autoF8 then return end
  if get_active() or screen.photoOn or screen.cloth or hm.regrow or hm.ghost then return end
  if screen.cloth_scene(pawn, true) then
    log("cloth: skipped automatic recovery during cinematic (" .. (screen.clothSceneReason or "unknown") .. ")")
    screen.autoF8 = nil
    return
  end
  local mesh = try(function() return pawn.Mesh end)
  if not valid(mesh) or (gore and #(gore.cut_parts(mesh) or {}) > 0) then return end
  screen.autoF8, screen.autoF8Ran = nil, os.clock()
  sandbox_recover("auto F8: her ponytail set right after she came into the world")
end
-- a part cut off her alive (tune.gore.lowArm, F9) simulates on her own mesh: query only stops it, and the arm went
-- back onto her shoulder, posed by her animation, till the collision came back (playtest: the reset an outfit's
-- bodies re-made set going came 2 s after the cut). Her mesh is left as it is while one is off her, and given back at
-- once should a part come off during the reset
function screen.piece_off(pawn)
  local gore = get_gore()
  local body = try(function() return pawn.Mesh end)
  return valid(body) and gore and #(gore.cut_parts(body) or {}) > 0 and body or nil
end
function screen.cloth_tick(pawn)
  local c = screen.cloth
  local due = c and not get_active() and not screen.photoOn and os.clock() - c.at >= (screen.CLOTH_AFTER[c.i] or 0)
  if (c or screen.autoF8 or screen.clothColl or screen.clothSim) and screen.cloth_scene(pawn, due) then
    local had = screen.cloth or screen.autoF8 or screen.clothColl or screen.clothSim
    screen.cloth, screen.autoF8 = nil, nil
    local n = screen.cloth_restore(true)
    if screen.clothSim then screen.clothSim.at = -math.huge; screen.cloth_sim_tick() end
    if had then log(string.format("cloth: skipped hair reset during cinematic (%s); restored %d mesh collisions", screen.clothSceneReason or "unknown", n)) end
    return
  end
  screen.cloth_sim_tick()
  screen.auto_f8(pawn)
  c = screen.cloth
  local piece = screen.piece_off(pawn)
  local bodyOff = piece and screen.clothColl and (function()
    for _, k in ipairs(screen.clothColl) do if valid(k.obj) and k.obj:GetAddress() == piece:GetAddress() then return true end end
  end)()
  if screen.clothColl and (get_active() or screen.photoOn or not c or bodyOff) then
    local n = screen.cloth_restore()
    log(string.format("cloth: her meshes' collision given back early (%d)%s", n, piece and ": a part is off her" or ""))
  end
  if not c or get_active() or screen.photoOn then return end
  local wait = screen.CLOTH_AFTER[c.i]
  if not wait then screen.cloth = nil; return end
  if os.clock() - c.at < wait then return end
  c.i = c.i + 1
  if c.i == 3 then
    local n = screen.cloth_restore()
    log(string.format("cloth: her meshes' collision given back (%d)", n))
    screen.cloth = nil
    -- (not after the one an auto F8 itself set going: its cleanup may re-make her bodies)
    if os.clock() - (screen.autoF8Ran or -100) > screen.AUTO_F8_S + 10 then screen.autoF8 = os.clock() + screen.AUTO_F8_S end
    return
  end
  local meshes = screen.cloth_meshes(pawn)
  -- ECollisionEnabled: QueryOnly 1 (photo mode's), QueryAndPhysics 3
  local off = 0
  if c.i == 2 then
    screen.clothColl = {}
    local body = try(function() return pawn.Mesh end)
    for _, m in ipairs(meshes) do
      local was = try(function() return m:GetCollisionEnabled() end)
      local k = was and was ~= 0 and was ~= 1 and not (piece and m:GetAddress() == piece:GetAddress()) and goreCtx.keep(m)
      -- (her hair's simulated bodies, read before: query only stops them)
      local sim = k and valid(body) and m:GetAddress() == body:GetAddress() and screen.sim_bodies(m) or {}
      if k and try(function() m:SetCollisionEnabled(1); return true end) then
        k.was = was
        if #sim > 0 then k.sim = sim end
        screen.clothColl[#screen.clothColl + 1] = k
        off = off + 1
      end
    end
    -- their indexes read now, while they surely live
    if #screen.clothColl > 0 then goreCtx.alive_ask(screen.clothColl) end
  end
  local ok, err = pcall(function() pawn:ForceAllClothNextUpdateTeleportAndReset() end)
  local info = {}
  local function nm(o) return valid(o) and (try(function() return o:GetFName():ToString() end) or "?") or "-" end
  local function cl(o) return valid(o) and (try(function() return o:GetClass():GetFName():ToString() end) or "?") or "-" end
  for _, m in ipairs(meshes) do
    -- ETeleportType::ResetPhysics
    pcall(function() m:ResetAnimInstanceDynamics(2) end)
    pcall(function() m:ForceClothNextUpdateTeleportAndReset() end)
    if c.i == 2 then
      info[#info + 1] = string.format("%s (%s, anim %s, post %s)", nm(m), nm(try(function() return m.SkeletalMesh end)),
        cl(try(function() return m.AnimScriptInstance end)), cl(try(function() return m.PostProcessAnimInstance end)))
    end
  end
  if c.i == 2 then
    local nsim = 0
    for _, k in ipairs(screen.clothColl or {}) do nsim = nsim + (k.sim and #k.sim or 0) end
    log(string.format("cloth: her ponytail reset (%s): %d mesh(es), %d of them query only for 1.5 s (as photo mode), %d simulated hair bodies on her mesh%s",
      c.why, #meshes, off, nsim, ok and "" or ("; her cloth reset failed: " .. tostring(err))))
    log("cloth: meshes " .. table.concat(info, "; "))
  end
end

end
