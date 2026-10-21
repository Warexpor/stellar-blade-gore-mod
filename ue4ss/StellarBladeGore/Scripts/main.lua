-- Stellar Blade Gore Mod: Eve ragdolls, bleeds and loses limbs when she dies (stabiliser, active ragdoll, gore, logger).
--
-- Probe #1 showed the ragdoll is not launched by the impulse: the pelvis stays put while every bone keeps
-- 500-1400 cm/s and 1000-9000 deg/s for the whole 4 s, and re-energises after settling. That is
-- self-collision: the mesh runs the Ragdoll profile (object PhysicsBody, blocks PhysicsBody), so the
-- physics asset's bodies collide with each other, and with SBHair (PhysicsOnly, PhysicsBody, blocks
-- PhysicsBody, attached to Bip001-Head).
--
-- Fixes applied on every ragdoll:
--   * the ragdolling mesh ignores PhysicsBody (no body-vs-body or hair collision), restored on recovery
--   * SBHair stops colliding while she is ragdolled, restored on recovery
--   * on recovery (respawn) the mesh is re-attached to the capsule at its gameplay transform if the
--     game left it detached (probe #1: respawn had no player model), and SB's hidden parent-update block
--     on it is cleared through sbslice.dll, on recovery and again after the game's respawn
-- Gore (gore.lua + sbslice.dll): dismemberment through a skin weight split on her own mesh, blood on hits,
-- cuts and under the body; all removed again on recovery.
-- Active ragdoll (active.lua): human masses, momentum and the blow carried into the fall, fading muscle tone.
-- Sandbox: F7 ragdolls her with a shove onto her back (tune.lua), F8 recovers, F6 re-reads tune.lua,
-- F9 cuts a limb, the head or the torso (tune.gore), F10 a blunt wound or (next press) a stab, F11 ragdolls her and splits
-- her in half top to bottom, Shift+F5 ragdolls her and cuts along a made-up blade (as a killing blow does), F5 plays one
-- of her animated death shows (a test death, which always splits her: tune.gore.f5Split).
-- Hits: the game tells clients about every skill hit (SBNetworkPlayerController:ClientBroadcast_SkillHitResult,
-- with the swing's direction); the last one on Eve decides whether a killing blow came down from above. In single
-- player it never fires: the blow is made up from her mesh's hit or the nearest enemy (death_hit), whose class also
-- names the attack's style (ENEMY_STYLE).
-- On first load it also dumps the full reflection schema (DumpUSMAP) for asset editing.
-- Log: ue4ss/Mods/StellarBladeGore/stellarbladegore.log (also mirrored into UE4SS.log).

local MOD = "StellarBladeGore"
local LOG_PATH = "ue4ss/Mods/StellarBladeGore/stellarbladegore.log"
local POLL_MS = 33
local TRACE_EVERY = 3       -- log motion every 3rd poll (~10 Hz)
local TRACE_POLLS = 120     -- ~4 s

local CH = { WorldStatic = 0, WorldDynamic = 1, Pawn = 2, Visibility = 3, Camera = 4, PhysicsBody = 5 }
local IGNORE, BLOCK = 0, 2
local NO_COLLISION = 0
local BONES = { "Bip001-Pelvis", "Bip001-Head", "Bip001-R-Hand" }

local TUNE_PATH = "ue4ss/Mods/StellarBladeGore/Scripts/tune.lua"
local GORE_PATH = "ue4ss/Mods/StellarBladeGore/Scripts/gore.lua"
local ACTIVE_PATH = "ue4ss/Mods/StellarBladeGore/Scripts/active.lua"
local USMAP_DONE = "ue4ss/Mods/StellarBladeGore/usmap.done"

local fh = io.open(LOG_PATH, "a")
local function log(s)
  local line = string.format("[%s] %s", os.date("%H:%M:%S"), s)
  print("[" .. MOD .. "] " .. line .. "\n")
  if fh then fh:write(line, "\n"); fh:flush() end
end

local function try(fn, ...)
  local ok, v = pcall(fn, ...)
  if ok then return v end
  return nil
end

local function valid(o) return o ~= nil and try(function() return o:IsValid() end) == true end
local function name(o) return valid(o) and (try(function() return o:GetFName():ToString() end) or "?") or "<nil>" end
local function v3(v) return v and string.format("(%.0f %.0f %.0f)", v.X, v.Y, v.Z) or "(?)" end
local function len(v) return v and math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) or -1 end
local function dist(a, b) return (a and b) and len({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }) or -1 end
local function copy3(v, k) return v and { [k[1]] = v[k[1]], [k[2]] = v[k[2]], [k[3]] = v[k[3]] } or nil end
local XYZ, PYR = { "X", "Y", "Z" }, { "Pitch", "Yaw", "Roll" }

-- the Eve whose ReceiveTick runs the script (see adopt below)
local cachedPawn, pawnAddr, pawnSeen = nil, nil, 0
local tune = {}
local goreCtx = { tune = tune }
local function load_tune()
  local ok, t = pcall(dofile, TUNE_PATH)
  if ok and type(t) == "table" then
    tune = t
    goreCtx.tune = t
    local keys = {}
    local function flat(prefix, x)
      for k, v in pairs(x) do
        if type(v) == "table" then flat(prefix .. k .. ".", v) else keys[#keys + 1] = prefix .. k .. "=" .. tostring(v) end
      end
    end
    flat("", t)
    table.sort(keys)
    log("tune: " .. table.concat(keys, " "))
  else
    log("tune.lua failed: " .. tostring(t))
  end
end
load_tune()

local gore, rag = nil, nil
-- an animated death (see animated_death below): { pawn, mesh, push } while her own fall plays, nil otherwise
local animDeath = nil
local function ragdoll_now(why)
  local a = animDeath
  if not a then return end
  animDeath = nil
  try(function() a.mesh:SetSimulatePhysics(true) end)
  try(function() a.mesh:SetAllBodiesSimulatePhysics(true) end)
  try(function() a.mesh:WakeAllRigidBodies() end)
  log("animated death: ragdoll after all (" .. why .. ")")
  if rag then rag.start(a.pawn, a.mesh, "death", a.push) end
end
goreCtx.log, goreCtx.try, goreCtx.valid, goreCtx.v3 = log, try, valid, v3
-- a severed limb stops being driven by the muscle tone
goreCtx.on_cut = function(mesh, bone) if rag then rag.on_cut(mesh, bone) end end
-- a split's copy settles with her
goreCtx.on_copy = function(comp) if rag then rag.add_body(comp) end end
-- a split holds her still until it opens, then she falls in halves
goreCtx.on_broken = function(mesh, bone) if rag then rag.broken(mesh, bone) end end
goreCtx.on_hold = function(mesh) if rag then return rag.hold(mesh) end end
goreCtx.on_release = function() if rag then rag.release() end end
-- a waist cut or a split needs the ragdoll: an animated death switches to it before the cut
goreCtx.on_need_ragdoll = function(kind) ragdoll_now(kind) end
-- her death fall is playing (a split then plays on with it before the halves come apart)
goreCtx.animated = function() return animDeath ~= nil end
-- a piece cut off a standing Eve gets human masses
goreCtx.on_piece = function(pawn, mesh) if rag then return rag.piece(pawn, mesh) end end
do
  local ok, g = pcall(dofile, GORE_PATH)
  if ok and type(g) == "table" then
    gore = g
    gore.init(goreCtx)
  else
    log("gore.lua failed: " .. tostring(g))
  end
  local ok2, a = pcall(dofile, ACTIVE_PATH)
  if ok2 and type(a) == "table" then
    rag = a
    rag.init(goreCtx)
  else
    log("active.lua failed: " .. tostring(a))
  end
end

-- only ever called from her own tick (keys wait for it), so the pawn is alive; no IsValid on it, see adopt
local function find_eve() return cachedPawn end

-- gameplay-time state, refreshed while she is not ragdolled
local rel = { loc = nil, rot = nil }
-- ragdoll-time state
local active, polls, deaths = false, 0, 0
local saved = {}
local after = -1            -- polls since recovery; watch the mesh until ~10 s after the game respawns her
local AFTER_POLLS = 300     -- ~10 s
local respawned = false     -- NotifyBP_ReInitActor seen since the last recovery

-- the ragdoll key asks for a pose snapshot after PoseSnapshotDelayTime (1 s in every death show): the
-- corpse optimisation that freezes the mesh. Enemies are removed afterwards; Eve keeps a frozen mesh that
-- no move reaches after respawn. Turn it off for her and log the ragdoll state.
local function ragdoll_state(pawn)
  local ri = try(function() return pawn.RagdollInfo end)
  if not ri then return "RagdollInfo=?" end
  local f = {}
  for _, k in ipairs({ "EnableRagdollCount", "bRegisterPoseSnapshot", "PoseSnapshotDelayTime", "bPoseSnapshot",
                       "bStopSimulatePhysics", "CurrentActiveTime", "BlendWeight", "bAllBodies" }) do
    f[#f + 1] = k .. "=" .. tostring(try(function() return ri[k] end))
  end
  f[#f + 1] = "support=" .. tostring(try(function() return pawn.bSupportRagdollPoseSnapshot end))
  f[#f + 1] = "lockup=" .. tostring(try(function() return pawn.bLockupSimulatePhysics end))
  f[#f + 1] = "meshLockup=" .. tostring(try(function() return pawn.Mesh.bLockupSimulatePhysics end))
  return table.concat(f, " ")
end

-- the cause of the frozen mesh, from the exe: SB's engine adds bLockupSimulatePhysics + LockupTransform to
-- USkeletalMeshComponent. ASBCharacter::SetLockupSimulatePhysics(true) copies each of its meshes'
-- ComponentToWorld into LockupTransform and the mesh then stays pinned there, whatever moves it. A corpse
-- never gets unlocked; Eve respawns still locked. The setter only acts on a change, so flip it on first.
local function unlock(pawn, mesh)
  local was = string.format("lockup=%s meshLockup=%s", tostring(try(function() return pawn.bLockupSimulatePhysics end)),
    tostring(try(function() return mesh.bLockupSimulatePhysics end)))
  try(function() pawn.bLockupSimulatePhysics = true end)
  try(function() pawn:SetLockupSimulatePhysics(false) end)
  try(function() mesh.bLockupSimulatePhysics = false end)
  local hair = try(function() return pawn.SBHair end)
  if valid(hair) then try(function() hair.bLockupSimulatePhysics = false end) end
  return was
end

local function no_snapshot(pawn)
  try(function() pawn.bSupportRagdollPoseSnapshot = false end)
  try(function() pawn.RagdollInfo.bRegisterPoseSnapshot = false end)
  try(function() pawn.RagdollInfo.bPoseSnapshot = false end)
end

-- The data mod sets LinearDamping 0.2 on the main bodies (vanilla 5.0); that is how a patched physics asset is
-- told apart from a vanilla one at runtime.
local function patched_physics(pa)
  if not valid(pa) then return false end
  local found = false
  try(function()
    pa.SkeletalBodySetups:ForEach(function(_, elem)
      local bs = elem:get()
      if not found and valid(bs) and bs.BoneName:ToString() == "Bip001-Pelvis" then
        found = bs.DefaultInstance.LinearDamping < 1.0
      end
    end)
  end)
  return found
end

local function on_start(pawn, mesh)
  log("ragdoll state at start: " .. ragdoll_state(pawn))
  no_snapshot(pawn)
  deaths = deaths + 1
  active, polls = true, 0
  saved = { meshPB = try(function() return mesh:GetCollisionResponseToChannel(CH.PhysicsBody) end) }
  -- "auto": the data mod fixes the collision table of every outfit's physics asset (mod/ragdoll_spec.json,
  -- "outfits"), so those keep self-collision (limbs can't pass through each other); vanilla ones (outfit mods
  -- that ship their own physics asset) overlap at rest and fling
  local paObj = try(function() return mesh:GetPhysicsAsset() end) or try(function() return mesh.SkeletalMesh.PhysicsAsset end)
  local pa = name(paObj)
  local selfCol = tune.selfCollision
  if selfCol == "auto" or selfCol == nil then selfCol = patched_physics(paObj) end
  saved.selfCollision = selfCol
  if not selfCol then
    try(function() mesh:SetCollisionResponseToChannel(CH.PhysicsBody, IGNORE) end)
  end
  if tune.massScale and tune.massScale ~= 1.0 then
    try(function() mesh:SetAllMassScale(tune.massScale) end)
  end
  local hair = try(function() return pawn.SBHair end)
  if valid(hair) and not tune.hairCollision then
    saved.hair = hair
    saved.hairEnabled = try(function() return hair:GetCollisionEnabled() end)
    try(function() hair:SetCollisionEnabled(NO_COLLISION) end)
  end
  log(string.format("=== ragdoll #%d start | mesh=%s physics=%s selfCollision=%s hairCollision=%s massScale=%s | parent=%s",
    deaths, name(try(function() return mesh.SkeletalMesh end)), pa, tostring(selfCol), tostring(tune.hairCollision), tostring(tune.massScale),
    name(try(function() return mesh:GetAttachParent() end))))
end

-- SB's engine blocks the capsule from moving the mesh after a death ragdoll (a hidden counter, cleared through
-- sbslice.dll). Clear it, then nudge the relative offset: setting the same one is a no-op, so this forces the
-- mesh's world transform to be rebuilt from the capsule now instead of on the next capsule move.
local function reattach_transform(mesh)
  local r = gore and gore.unpin(mesh) or "no gore.lua"
  local l = try(function() local v = mesh.RelativeLocation; return { X = v.X, Y = v.Y, Z = v.Z } end)
  if l then
    try(function() mesh:K2_SetRelativeLocation({ X = l.X, Y = l.Y, Z = l.Z + 1 }, false, {}, true) end)
    try(function() mesh:K2_SetRelativeLocation(l, false, {}, true) end)
  end
  return r
end

-- put the mesh back into normal animated gameplay state
local function recover(pawn, mesh, why)
  local cap = try(function() return pawn.CapsuleComponent end)
  -- the muscle tone's drives hold the current bodies, which gore's cleanup recreates: release them first
  if rag then try(function() rag.stop(pawn) end) end
  if gore then try(function() gore.cleanup(pawn, mesh) end) end
  local steps = { "unlock(" .. unlock(pawn, mesh) .. ")" }
  local function step(label, fn) steps[#steps + 1] = label .. (try(function() fn(); return true end) and "" or "!") end
  step("sim", function() mesh:SetSimulatePhysics(false) end)
  step("allSim", function() mesh:SetAllBodiesSimulatePhysics(false) end)
  step("blend", function() mesh:SetAllBodiesPhysicsBlendWeight(0.0, false) end)
  step("reset", function() mesh:ResetAllBodiesSimulatePhysics() end)
  -- a real death leaves the mesh on absolute location/rotation, so after respawn its relative offset is
  -- used as a world position (log: mesh at (0 0 -97) while attached to the capsule)
  step("abs", function() mesh:SetAbsolute(false, false, false) end)
  if valid(cap) then
    -- after a real death GetAttachParent still says capsule but the capsule no longer carries the mesh,
    -- and attaching to the same parent is a no-op, so detach first
    step("detach", function() mesh:K2_DetachFromComponent(0, 0, 0, false) end)
    step("attach", function() mesh:K2_AttachToComponent(cap, FName("None"), 0, 0, 0, false) end)
  end
  if rel.loc and rel.rot then
    step("rel", function() mesh:K2_SetRelativeLocationAndRotation(rel.loc, rel.rot, false, {}, true) end)
  end
  steps[#steps + 1] = "unpin(" .. reattach_transform(mesh) .. ")"
  local function gap_now()
    return dist(try(function() return mesh:K2_GetComponentLocation() end), cap and try(function() return cap:K2_GetComponentLocation() end))
  end
  local gap = gap_now()
  local function place()
    local cl = cap:K2_GetComponentLocation()
    local cr = cap:K2_GetComponentRotation()
    local yaw = math.rad(cr.Yaw)
    local wl = { X = cl.X + rel.loc.X * math.cos(yaw) - rel.loc.Y * math.sin(yaw),
                 Y = cl.Y + rel.loc.X * math.sin(yaw) + rel.loc.Y * math.cos(yaw), Z = cl.Z + rel.loc.Z }
    local wr = { Pitch = rel.rot.Pitch, Yaw = cr.Yaw + rel.rot.Yaw, Roll = rel.rot.Roll }
    mesh:K2_SetWorldLocationAndRotation(wl, wr, false, {}, true)
    mesh:K2_AttachToComponent(cap, FName("None"), 1, 1, 0, false)
  end
  -- fallback if the mesh is still away from the capsule after the unlock
  local attempts = {
    { "world", function() end },
  }
  if valid(cap) and rel.loc and rel.rot and (gap < 0 or gap > 250) then
    for _, a in ipairs(attempts) do
      step(a[1], function() a[2](); place() end)
      gap = gap_now()
      steps[#steps] = steps[#steps] .. string.format("=%.0f", gap)
      if gap >= 0 and gap < 250 then break end
    end
  end
  local rl = try(function() return mesh.RelativeLocation end)
  -- UPrimitiveComponent::MoveComponentImpl refuses to move a pending-kill component: is the mesh destroyed?
  local pk = try(function() return mesh:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end)
  local bd = try(function() return mesh:HasAnyFlags(EObjectFlags.RF_BeginDestroyed) end)
  steps[#steps + 1] = string.format("pendingKill=%s beginDestroyed=%s", tostring(pk), tostring(bd))
  local diag = string.format("relLoc=%s pawn=%x mesh=%x reg=%s anySim=%s mob=%s absLoc=%s absRot=%s tum=%s",
    v3(rl), pawn:GetAddress(), mesh:GetAddress(), tostring(try(function() return mesh:IsRegistered() end)),
    tostring(try(function() return mesh:IsAnySimulatingPhysics() end)), tostring(try(function() return mesh.Mobility end)),
    tostring(try(function() return mesh.bAbsoluteLocation end)), tostring(try(function() return mesh.bAbsoluteRotation end)),
    tostring(try(function() return mesh.PhysicsTransformUpdateMode end)))
  steps[#steps + 1] = diag
  log(string.format("recover (%s): %s gap=%.0f", why, table.concat(steps, " "), gap))
end

-- attached to the capsule and actually following it (mesh sits ~97 cm under the capsule centre)
local function attached_to_capsule(pawn, mesh)
  local cap = try(function() return pawn.CapsuleComponent end)
  local parent = try(function() return mesh:GetAttachParent() end)
  if not (valid(cap) and valid(parent) and parent:GetAddress() == cap:GetAddress()) then return false end
  local gap = dist(try(function() return mesh:K2_GetComponentLocation() end), try(function() return cap:K2_GetComponentLocation() end))
  return gap >= 0 and gap < 250
end

local lastRecover = -100
local function watch(pawn, mesh)
  local cap = try(function() return pawn.CapsuleComponent end)
  local cloc = cap and try(function() return cap:K2_GetComponentLocation() end)
  local mloc = try(function() return mesh:K2_GetComponentLocation() end)
  local ploc = try(function() return mesh:GetSocketLocation(FName("Bip001-Pelvis")) end)
  log(string.format("a%03d parent=%s capsule%s mesh%s pelvis%s pelvisGap=%.0f visible=%s hidden=%s sim=%s meshLockup=%s",
    after, name(try(function() return mesh:GetAttachParent() end)), v3(cloc), v3(mloc), v3(ploc), dist(ploc, cloc),
    tostring(try(function() return mesh:IsVisible() end)), tostring(try(function() return pawn.bHidden end)),
    tostring(try(function() return mesh:IsSimulatingPhysics(FName("None")) end)),
    tostring(try(function() return mesh.bLockupSimulatePhysics end))))
end

local function on_end(pawn, mesh)
  log("ragdoll state at end: " .. ragdoll_state(pawn))
  log(string.format("mesh flags at ragdoll end: pendingKill=%s beginDestroyed=%s",
    tostring(try(function() return mesh:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end)),
    tostring(try(function() return mesh:HasAnyFlags(EObjectFlags.RF_BeginDestroyed) end))))
  active, animDeath = false, nil
  after, lastRecover, respawned = 0, -100, false
  try(function() mesh:SetCollisionResponseToChannel(CH.PhysicsBody, saved.meshPB or BLOCK) end)
  if valid(saved.hair) and saved.hairEnabled then try(function() saved.hair:SetCollisionEnabled(saved.hairEnabled) end) end
  local cap = try(function() return pawn.CapsuleComponent end)
  local parent = try(function() return mesh:GetAttachParent() end)
  local mloc = try(function() return mesh:K2_GetComponentLocation() end)
  local cloc = cap and try(function() return cap:K2_GetComponentLocation() end)
  local visible = try(function() return mesh:IsVisible() end)
  log(string.format("=== ragdoll #%d end after %d polls | parent=%s mesh%s capsule%s gap=%.0f visible=%s profile=%s",
    deaths, polls, name(parent), v3(mloc), v3(cloc), dist(mloc, cloc), tostring(visible),
    tostring(try(function() return mesh:GetCollisionProfileName():ToString() end))))
  if tune.massScale and tune.massScale ~= 1.0 then try(function() mesh:SetAllMassScale(1.0) end) end
  if saved.collision then
    -- sandbox ragdoll: put back the exact gameplay collision setup
    local c = saved.collision
    try(function() mesh:SetCollisionObjectType(c.obj) end)
    for ch, r in pairs(c.resp) do try(function() mesh:SetCollisionResponseToChannel(ch, r) end) end
    try(function() mesh:SetCollisionEnabled(c.enabled) end)
  end
  recover(pawn, mesh, "ragdoll ended")
end

-- F7's push, per bone, as a share of tune.impulse (upper body) or of tune.legKick (negative: the legs, the other way)
local F7_PUSH = {
  ["Bip001-Spine2"] = 1.0, ["Bip001-Spine1"] = 0.9, ["Bip001-Neck"] = 0.9, ["Bip001-Head"] = 0.9,
  ["Bip001-L-Clavicle"] = 0.8, ["Bip001-R-Clavicle"] = 0.8, ["Bip001-L-UpperArm"] = 0.6, ["Bip001-R-UpperArm"] = 0.6,
  ["Bip001-Spine"] = 0.6, ["Bip001-Pelvis"] = 0.3,
  ["Bip001-L-Calf"] = -0.6, ["Bip001-R-Calf"] = -0.6, ["Bip001-L-Foot"] = -1.0, ["Bip001-R-Foot"] = -1.0,
}
-- F7's push waits until her bodies simulate: pushed the tick physics was switched on, most of it was lost (her pelvis
-- read 0 cm/s right after, the head 100 instead of 900). { pawn, mesh, n } ticks to wait
local f7_push, f7_after = nil, nil
local F7_WAIT = 2

local function body_speed(mesh, b)
  local v = try(function() local x = mesh:GetPhysicsLinearVelocity(FName(b)); return { X = x.X, Y = x.Y, Z = x.Z } end)
  return v and math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) or -1
end

-- the shove: the whole body moves along it (push, every body the same velocity change, so the centre of mass goes),
-- the upper body more (impulse) and the legs the other way (legKick), so with "back" she topples onto her back
local function f7_shove(pawn, mesh)
  local f = (tune.relativeTo or "eve") == "camera" and try(function()
    local yaw = math.rad(pawn:GetControlRotation().Yaw)
    return { X = math.cos(yaw), Y = math.sin(yaw) }
  end) or try(function() local v = pawn:GetActorForwardVector(); return { X = v.X, Y = v.Y } end)
  f = f or { X = 1, Y = 0 }
  local fl = math.max(math.sqrt(f.X * f.X + f.Y * f.Y), 1e-3)
  local fx, fy = f.X / fl, f.Y / fl
  local dirs = { forward = { fx, fy }, back = { -fx, -fy }, left = { fy, -fx }, right = { -fy, fx } }
  local d = dirs[tune.direction] or dirs.back
  local up, kick, push = tune.up or 0, tune.legKick or 0, tune.push or 0
  local h = math.sqrt(math.max(0, 1 - up * up))
  local before = body_speed(mesh, "Bip001-Pelvis")
  local all = false
  if push > 0 then
    all = try(function()
      mesh:AddImpulseToAllBodiesBelow({ X = d[1] * h * push, Y = d[2] * h * push, Z = up * push }, FName("Bip001"), true, true)
      return true
    end) == true
  end
  local n = 0
  for bone, share in pairs(F7_PUSH) do
    local v = share > 0 and (tune.impulse or 0) * share or kick * share
    local imp = { X = d[1] * h * v, Y = d[2] * h * v, Z = share > 0 and up * v or 0 }
    if try(function() mesh:AddImpulse(imp, FName(bone), true); return true end) then n = n + 1 end
  end
  try(function() mesh:WakeAllRigidBodies() end)
  log(string.format("F7: pushed %s (from %s's facing): whole body %.0f cm/s%s, upper body %.0f, legs the other way %.0f, on %d bones; pelvis at %.0f cm/s",
    tune.direction or "back", (tune.relativeTo or "eve") == "camera" and "the camera" or "her", push, all and "" or " (FAILED)",
    tune.impulse or 0, kick, n, before))
end

-- F7 sandbox ragdoll: what the death show does (Ragdoll profile + simulate + impulse), on demand
local function sandbox_ragdoll()
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not valid(mesh) then log("F7: no Eve"); return end
  if active then log("F7: already ragdolled"); return end
  local c = { resp = {} }
  c.obj = try(function() return mesh:GetCollisionObjectType() end)
  c.enabled = try(function() return mesh:GetCollisionEnabled() end)
  for ch = 0, 31 do c.resp[ch] = try(function() return mesh:GetCollisionResponseToChannel(ch) end) end
  try(function() mesh:SetCollisionProfileName(FName("Ragdoll"), true) end)
  on_start(pawn, mesh)
  saved.collision = c
  try(function() mesh:SetAllBodiesBelowSimulatePhysics(FName("Bip001"), true, true) end)
  if rag then rag.start(pawn, mesh, "sandbox") end
  -- the push goes in a couple of ticks later, once her bodies simulate (tick)
  if (tune.impulse or 0) > 0 or (tune.push or 0) > 0 then f7_push = { pawn = pawn, mesh = mesh, n = F7_WAIT } end
end

local function sandbox_recover()
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not valid(mesh) then return end
  try(function() mesh:SetAllBodiesSimulatePhysics(false) end)
  try(function() mesh:SetSimulatePhysics(false) end)
  -- a cut on a living Eve (F9) never starts a full ragdoll, so undo it here too
  if gore and not active then gore.cleanup(pawn, mesh) end
  if rag and not active then rag.stop(pawn) end
  log("F8: recover requested")
end

-- what a killing blow does, by tune.gore.death's odds: "limb", "head", "torso", "wound" or "split" (a blunt dent,
-- when no reported hit named a stab or blunt attack); wounds false = only cuts (F9);
-- split only when allowed (a blow that came down from above)
local KINDS = { "limb", "head", "torso", "wound", "split" }
-- blunt: a fist or a slam tears off a limb or the head at most, it never cuts her in two
local function pick_kind(wounds, split, blunt)
  local odds = (tune.gore or {}).death or { limb = 45, head = 20, torso = 15, wound = 20, split = 10 }
  local function w(k)
    if k == "wound" and not wounds then return 0 end
    if k == "split" and (not split or blunt) then return 0 end
    if k == "torso" and blunt then return 0 end
    return math.max(tonumber(odds[k]) or 0, 0)
  end
  local total = 0
  for _, k in ipairs(KINDS) do total = total + w(k) end
  if total <= 0 then return "limb" end
  local r = math.random() * total
  for _, k in ipairs(KINDS) do
    if r < w(k) then return k end
    r = r - w(k)
  end
  return "limb"
end

-- the game's skill hits, newest last: { t, loc, normal, dir, fwd, attack, bone, group }
local hits = {}
local HIT_KEEP = 8
local function vecof(p)
  local v = try(function() return p:get() end)
  if v == nil then return nil end
  local x, y, z = try(function() return v.X end), try(function() return v.Y end), try(function() return v.Z end)
  if type(x) ~= "number" then return nil end
  return { X = x, Y = y, Z = z }
end
local function strof(p)
  local v = try(function() return p:get() end)
  if v == nil then return "?" end
  return try(function() return v:ToString() end) or tostring(v)
end
-- ClientBroadcast_SkillHitResult(inTurn, inSkillGuid, inSkillResultID, inCasterGUID, inTargetGUID, inSkillHitResult,
-- inAttackGroupName, inHitResult, inHitLocation, inHitNormal, inHitBoneName, inHitDirection, inHitFoward,
-- inHitStopTime, inCriticalHit, inAttackDirection, inShowKeyTag) as the SDK dump declares it. The script used to read
-- its parameters from the third on as location, normal, bone, ..., so no hit ever had a location near her.
-- Every call is counted, and the first HIT_PROBE that aren't on her are logged: a death with "last hit none" then
-- says whether the hook fires at all or its hits were filtered out.
local HIT_RESULT = { [0] = "none", "hit", "miss", "parry", "superparry", "guard", "guardblock" }
local ATTACK_DIR = { [0] = "none", "left-to-right", "right-to-left", "front" }
local hitCalls, hitsOnEve = 0, 0
local attack_style -- below
local HIT_PROBE = 12
local function on_skill_hit(_, _turn, skill, _result_id, caster, target, result, group, _hit, loc, nrm, bone, dir, fwd,
                            _stop, _crit, attack_dir, show)
  hitCalls = hitCalls + 1
  local function num(p) local v = try(function() return p:get() end); return type(v) == "number" and v or nil end
  local h = { t = os.clock(), loc = vecof(loc), normal = vecof(nrm), dir = vecof(dir), fwd = vecof(fwd),
    result = num(result), attack_dir = num(attack_dir), skill = num(skill), caster = num(caster), target = num(target),
    bone = strof(bone), group = strof(group), show = strof(show) }
  -- only hits on Eve are kept (within reach of her pelvis); every one of them is logged for calibration
  -- not while her tick is silent: the level may be reloading, and the old pawn's memory gone
  local pawn = os.clock() - pawnSeen < 0.5 and cachedPawn or nil
  local mesh = pawn and try(function() return pawn.Mesh end)
  local pel = valid(mesh) and try(function() return mesh:GetSocketLocation(FName("Bip001-Pelvis")) end)
  local near = pel and h.loc and dist(pel, h.loc) < 150
  local function vs(v) return v and string.format("(%.2f %.2f %.2f)", v.X, v.Y, v.Z) or "?" end
  local what = string.format("%s, %s, skill %s, caster %s -> target %s, group %s, show %s",
    HIT_RESULT[h.result or -1] or tostring(h.result), ATTACK_DIR[h.attack_dir or -1] or tostring(h.attack_dir),
    tostring(h.skill), tostring(h.caster), tostring(h.target), h.group, h.show)
  if not near then
    if hitCalls <= HIT_PROBE then
      log(string.format("hit #%d (not on Eve): at %s, %.0f from her pelvis, bone %s, %s", hitCalls, v3(h.loc),
        dist(pel, h.loc), h.bone, what))
    end
    return
  end
  hitsOnEve = hitsOnEve + 1
  hits[#hits + 1] = h
  if #hits > HIT_KEEP then table.remove(hits, 1) end
  log(string.format("hit on Eve (%s): at %s bone %s dir %s fwd %s normal %s, %s", attack_style(h), v3(h.loc), h.bone,
    vs(h.dir), vs(h.fwd), v3(h.normal), what))
end
-- blade, stab or blunt, by the attack's group and show names (the game has no weapon type): any of
-- tune.gore.stabWords or bluntWords in them (case-insensitive), else a blade. Each hit on her logs its style and both
-- names, so the lists can be fitted to what the enemies' attacks are called
local STAB = { "stab", "thrust", "pierce", "sting", "spear", "lance", "drill", "needle", "spike", "impale" }
local BLUNT = { "punch", "smash", "bash", "slam", "stomp", "kick", "hammer", "tackle", "crush", "charge",
  "headbutt", "fist", "blunt", "rush" }
-- The game never reports the attack in single player, so the attacker decides: each enemy by what most of its
-- attacks are (sorted from its skill shows' names: the Gorilla's FistRush / BodySlam / SmashCombo are blunt, the
-- Sawshark's saw and the Tachy's slashes blades, the gunners' shots stabs). tune.gore.attackerStyles adds or
-- overrides entries; the key is the part of the enemy's class name after CH_M_ (CH_M_NA_05_Blueprint_C -> "NA_05")
local ENEMY_STYLE = {
  NA_01 = "stab", NA_02 = "blade", NA_03 = "blade", NA_05 = "blunt", NA_07 = "blunt", NA_08 = "blunt",
  NA_09 = "stab", NA_11 = "blunt", NA_12 = "blunt", NA_13 = "blade", NA_14 = "blade", NA_15 = "blunt",
  NA_16 = "blunt", NA_17 = "blade", NA_18 = "stab", NA_19 = "stab", NA_20 = "blunt", NA_21 = "blade",
  NA_22 = "blade", NA_23 = "blade", NA_24 = "stab", NA_25 = "blunt", NA_26 = "blade", NA_27 = "stab",
  NA_28 = "blunt", NA_29 = "blade", NA_30 = "blunt", NA_31 = "blade", NA_32 = "blunt", NA_34 = "blunt",
  NA_35 = "blunt", NA_36 = "blunt", NA_37 = "blunt", NA_39 = "blade", NA_40 = "blade", NA_41 = "blunt",
  NA_42 = "blade", NA_43 = "blunt", NA_44 = "blade", NA_45 = "blade", NA_46 = "blunt", NA_47 = "blade",
  NA_48 = "stab", NA_49 = "blade", NA_51 = "blunt", NA_52 = "blunt", NA_53 = "blade", NA_54 = "blade",
  NA_55 = "blade", NA_56 = "blade", NA_57 = "stab", NA_58 = "blade", NA_901 = "blade", NA_961 = "blade",
}
local function enemy_style(cls)
  if not cls then return nil end
  local key = cls:match("^CH_[MN]_([%a]+_%d+)")
  if not key then return nil end
  local over = (tune.gore or {}).attackerStyles or {}
  return over[key] or ENEMY_STYLE[key]
end
attack_style = function(h)
  if not h then return "blade" end
  local g = tune.gore or {}
  local name = ((h.group or "") .. " " .. (h.show or "")):lower()
  local function any(words)
    for _, w in ipairs(words) do if name:find(tostring(w):lower(), 1, true) then return true end end
    return false
  end
  if any(g.stabWords or STAB) then return "stab" end
  if any(g.bluntWords or BLUNT) then return "blunt" end
  return enemy_style(h.attacker) or g.unknownStyle or "blade"
end
local function last_hit(within)
  local h = hits[#hits]
  if h and os.clock() - h.t <= within then return h end
  return nil
end

-- The skill-hit message above never comes in single player (0 calls in a whole session), so hits are also read off
-- her mesh: the game's physical hit reaction leaves the force, where it landed and on which bone
-- (PhysicalHitForce*), and the hit shake its position and direction (VertexShakeInfo). A change is a new hit.
local meshHit, meshKey = nil, nil
local function vof(v) return v and { X = v.X, Y = v.Y, Z = v.Z } or nil end
local function poll_mesh_hit(mesh)
  local f = try(function() return vof(mesh.PhysicalHitForceVector) end)
  local at = try(function() return vof(mesh.PhysicalHitForceLocation) end)
  local sp = try(function() return vof(mesh.VertexShakeInfo.ShakeHitPosition) end)
  local sd = try(function() return vof(mesh.VertexShakeInfo.ShakeHitDirection) end)
  local key = string.format("%s %s %s %s", v3(f), v3(at), v3(sp), v3(sd))
  if meshKey == nil then meshKey = key; return end
  if key == meshKey then return end
  meshKey = key
  local bone = try(function() return mesh.PhysicalHitForceTargetBone:ToString() end)
  local pel = try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Pelvis"))) end)
  -- whichever position lies on her (either may be component space or stale)
  local loc = (at and dist(at, pel) < 150 and at) or (sp and dist(sp, pel) < 150 and sp) or nil
  local dir = (f and len(f) > 1e-3 and f) or (sd and len(sd) > 1e-3 and sd) or nil
  meshHit = { t = os.clock(), loc = loc, push = dir, bone = bone, src = "mesh" }
  log(string.format("mesh hit: force %s at %s bone %s power %s, shake at %s dir %s -> on her %s", v3(f), v3(at),
    tostring(bone), tostring(try(function() return mesh.PhysicalHitForcePower end)), v3(sp), v3(sd), tostring(loc ~= nil)))
end

-- the nearest other character within tune.gore.attackerReach of her: who most likely killed her
local function attacker(pawn, mesh)
  local me = pawnAddr
  local at = try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Spine1"))) end)
  if not at then return nil end
  local reach = (tune.gore or {}).attackerReach or 800
  local best, bd = nil, nil
  for _, cls in ipairs({ "SBCharacter", "Character" }) do
    local all = try(function() return FindAllOf(cls) end) or {}
    for _, a in ipairs(all) do
      local ad = try(function() return a:GetAddress() end)
      if ad and ad ~= me and try(function() return a.bActorIsBeingDestroyed end) == false
        and try(function() return a.bHidden end) ~= true then
        local l = try(function() return vof(a:K2_GetActorLocation()) end)
        local d = dist(l, at)
        if l and d >= 0 and d < reach and (not bd or d < bd) then best, bd = { actor = a, loc = l, d = d }, d end
      end
    end
    if best then break end
  end
  if not best then return nil end
  best.name = name(best.actor)
  local fl = try(function() return vof(best.actor:GetActorForwardVector()) end)
  local push = { X = at.X - best.loc.X, Y = at.Y - best.loc.Y, Z = 0 }
  if len(push) < 1 and fl then push = { X = fl.X, Y = fl.Y, Z = 0 } end
  best.push = push
  return best
end

-- where a made-up blade lands, with odds: mostly the chest, stomach, neck and arms (an even pick of 12 bones, a third of
-- them legs, put nearly every made-up blow through a leg); a limb is struck 40 % of the way down it, not at its joint
local SWING_AT = {
  { "Bip001-Spine1", 3 }, { "Bip001-Spine2", 3 }, { "Bip001-Neck", 1.5 }, { "Bip001-Spine", 1 },
  { "Bip001-L-UpperArm", 1.5, "Bip001-L-Forearm" }, { "Bip001-R-UpperArm", 1.5, "Bip001-R-Forearm" },
  { "Bip001-L-Forearm", 0.75, "Bip001-L-Hand" }, { "Bip001-R-Forearm", 0.75, "Bip001-R-Hand" },
  { "Bip001-L-Thigh", 0.6, "Bip001-L-Calf" }, { "Bip001-R-Thigh", 0.6, "Bip001-R-Calf" },
  { "Bip001-L-Calf", 0.3, "Bip001-L-Foot" }, { "Bip001-R-Calf", 0.3, "Bip001-R-Foot" },
}
local function swing_at(mesh)
  local sum = 0
  for _, e in ipairs(SWING_AT) do sum = sum + e[2] end
  local r = math.random() * sum
  local e = SWING_AT[#SWING_AT]
  for _, x in ipairs(SWING_AT) do
    r = r - x[2]
    if r <= 0 then e = x; break end
  end
  local loc = try(function()
    local a = mesh:GetSocketLocation(FName(e[1]))
    if not e[3] then return { X = a.X, Y = a.Y, Z = a.Z } end
    local b = mesh:GetSocketLocation(FName(e[3]))
    return { X = a.X + 0.4 * (b.X - a.X), Y = a.Y + 0.4 * (b.Y - a.Y), Z = a.Z + 0.4 * (b.Z - a.Z) }
  end)
  return e[1], loc
end
-- the killing blow: the game's skill hit when it came (swing and forward), else a blade made up around where it came
-- from (her mesh's last hit, else the nearest enemy): pushed from there, swung level, slanted or down across it,
-- through where the mesh says she was hit or a part of her (swing_at)
local function death_hit(pawn, mesh)
  local g = tune.gore or {}
  local h = last_hit(g.hitWindow or 0.6)
  if h and h.dir and h.fwd then
    h.push = h.push or h.fwd
    return h
  end
  local m = meshHit and os.clock() - meshHit.t <= (g.meshHitWindow or 1.0) and meshHit or nil
  local a = attacker(pawn, mesh)
  local push = (m and m.push) or (a and a.push)
  if not push then return h end
  local fl = len({ X = push.X, Y = push.Y, Z = 0 })
  if fl < 1e-3 then return h end
  local fwd = { X = push.X / fl, Y = push.Y / fl, Z = 0 }
  local side = math.random() < 0.5 and -1 or 1
  local ang = math.rad(({ 0, 20, 45, 45, 70, 90 })[math.random(6)])
  local dir = { X = -fwd.Y * side * math.cos(ang), Y = fwd.X * side * math.cos(ang), Z = -math.sin(ang) }
  local loc = m and m.loc
  local bone = m and m.bone
  if not loc then bone, loc = swing_at(mesh) end
  if not loc then return h end
  local from = (m and m.push and "her mesh's hit") or "the nearest enemy"
  log(string.format("death: blow from %s%s, %d deg down, at %s (%s)", from,
    a and string.format(" (nearest enemy %s, %.0f cm off: %s)", a.name, a.d, enemy_style(a.name) or "style unknown") or "",
    math.floor(math.deg(ang) + 0.5), v3(loc), m and "where the mesh was hit" or ("made up: " .. tostring(bone))))
  return { t = os.clock(), loc = loc, dir = dir, fwd = fwd, push = push, attack_dir = 0, src = from,
    group = h and h.group, show = h and h.show, bone = bone, attacker = a and a.name }
end

-- a blow from above: the split plane holds the swing and the attacker's forward (its normal is their cross
-- product), else nil
local function split_normal(h)
  local g = tune.gore or {}
  if not (h and h.dir) then return nil end
  local d = h.dir
  local l = len(d)
  if l < 1e-3 or d.Z / l > -(g.splitDown or 0.6) then return nil end
  local f = h.fwd
  if f then
    local c = { X = d.Y * f.Z - d.Z * f.Y, Y = d.Z * f.X - d.X * f.Z, Z = d.X * f.Y - d.Y * f.X }
    if len(c) > 0.2 * l * len(f) then return c end
  end
  -- no usable forward: the plane holds the swing and the line from the hit into her
  return { X = d.Y, Y = -d.X, Z = 0 }
end

-- F9: cut something off where she stands (tune.gore.bone, or a roll of tune.gore.death's cut odds if "auto")
local function sandbox_slice()
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not (gore and valid(mesh)) then log("F9: no Eve or no gore.lua"); return end
  gore.slice(pawn, mesh, nil, "F9", pick_kind(false))
end

-- F11: ragdoll her (F7) and split her top to bottom, along the camera's view (as if the blade came down in front of it)
local function sandbox_split()
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not (gore and valid(mesh)) then log("F11: no Eve or no gore.lua"); return end
  if not active then sandbox_ragdoll() end
  local rot = try(function() return pawn:GetControlRotation() end)
  local yaw = math.rad(rot and rot.Yaw or 0)
  gore.split(pawn, mesh, nil, { X = -math.sin(yaw), Y = math.cos(yaw), Z = 0 }, "F11")
end

-- Shift+F5: ragdoll her and cut along a made-up blade, as a killing blow would (gore.blow): a swing level, slanted or
-- straight down through a random part of her, the attacker standing where the camera looks from
local function sandbox_blade()
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not (gore and valid(mesh)) then log("Shift+F5: no Eve or no gore.lua"); return end
  if not active then sandbox_ragdoll() end
  local rot = try(function() return pawn:GetControlRotation() end)
  local yaw = math.rad(rot and rot.Yaw or 0)
  local fwd = { X = math.cos(yaw), Y = math.sin(yaw), Z = 0 }
  local side = math.random() < 0.5 and -1 or 1
  local a = math.rad(({ 0, 30, 60, 90 })[math.random(4)])
  local dir = { X = -math.sin(yaw) * side * math.cos(a), Y = math.cos(yaw) * side * math.cos(a), Z = -math.sin(a) }
  local bone, loc = swing_at(mesh)
  if not loc then log("Shift+F5: no " .. bone); return end
  log(string.format("Shift+F5: blade through %s, %d deg down", bone, math.floor(math.deg(a) + 0.5)))
  gore.blow(pawn, mesh, { t = os.clock(), loc = loc, dir = dir, fwd = fwd, attack_dir = 0, bone = bone }, "F5")
end

-- more falls for an animated death: the data mod's death shows made from her knockdown falls (Ragdoll/EveDeath_*,
-- no ragdoll key; the knockdown shows themselves are untouched). One is picked at random with her own death show
-- (tune.active.animatedPool) and played over it
local DEATH_FALLS = { "Knock_Down_Start", "Knock_Down_Start1", "Knock_Down_Forward", "Knock_Down_Backward",
  "KnockDown_S_Fw", "KnockDown_S_Bw", "KnockDown_Tumble_Fw", "KnockDown_Tumble_Bw" }
local forceFall = nil -- F5: the fall to play next ("own" = her death show's own)
local DEATH_HOST = "/Game/Art/Show/CH_P_EVE_01/Basic/P_Eve_Dead.P_Eve_Dead" -- imports every EveDeath_* (ragdoll_spec.json)
-- a show (path under Art/Show, e.g. "CH_P_EVE_01/Basic/P_Eve_Dead") on her. PlaySingleShow is only on the game's
-- show interface, which Lua can't call (it silently did nothing); SBBlueprintLibrary's PlaySBShowToPlayerCharacter
-- takes the show asset itself, and the cheat manager's SBPlayShow (when the game made one) its path
local function play_show(pawn, rel, why)
  local nm = rel:match("([^/]+)$")
  local path = "/Game/Art/Show/" .. rel .. "." .. nm
  local show = try(function() return StaticFindObject(path) end)
  if not valid(show) and LoadAsset then show = try(function() return LoadAsset(path) end) end
  if not valid(show) then show = try(function() return StaticFindObject(path) end) end
  if not valid(show) and LoadAsset then
    -- the mod's own shows aren't in the asset registry, so LoadAsset can't find them; P_Eve_Dead (which is)
    -- imports the death falls, and loading it brings them in
    try(function() LoadAsset(DEATH_HOST) end)
    show = try(function() return StaticFindObject(path) end)
  end
  if valid(show) then
    local lib = try(function() return StaticFindObject("/Script/SB.Default__SBBlueprintLibrary") end)
    if valid(lib) then
      local ok, err = pcall(function() lib:PlaySBShowToPlayerCharacter(show) end)
      log(string.format("%s: show %s via SBBlueprintLibrary: %s", why, rel, ok and "played" or tostring(err)))
      if ok then return true end
    else
      log(why .. ": no SBBlueprintLibrary")
    end
  else
    -- what the host holds: its preload keys gone (collected) or never there (the pak)
    local host = try(function() return StaticFindObject(DEATH_HOST) end)
    local key = try(function() return StaticFindObject(DEATH_HOST .. ":SBShowPlayShowKey_1") end)
    local sd = valid(key) and try(function() return key.ShowData end)
    log(string.format("%s: show %s didn't load (host %s, preload key %s -> %s)", why, path, tostring(valid(host)),
      tostring(valid(key)), valid(sd) and sd:GetFullName() or "nothing"))
  end
  local cm = try(function() return FindFirstOf("SBCheatManager") end)
  if valid(cm) then
    local ok, err = pcall(function() cm:SBPlayShow(path) end)
    log(string.format("%s: show %s via the cheat manager: %s", why, rel, ok and "played" or tostring(err)))
    if ok then return true end
  end
  return false
end

-- F5: one of her animated death shows on the spot, in turn (P_Eve_Dead, Dead2, Dead3). Its ragdoll key is the
-- data mod's death signal, so everything after runs as on a real death: the fall plays, the death's cut is rolled
-- (or cut along the last hit), blood, recovery after recoverAfter. She isn't dead, so the game's death screen and
-- respawn don't come
local DEATH_SHOWS = { "P_Eve_Dead", "P_Eve_Dead2", "P_Eve_Dead3" }
local f5_fall = 0
local f5_at = nil -- when F5 played its death: that death splits her top to bottom (tune.gore.f5Split)
local function sandbox_death()
  local pawn = find_eve()
  if not pawn then log("F5: no Eve"); return end
  if active then log("F5: she is already down (F8 gets her up)"); return end
  -- her three death shows first, then each knockdown fall over the first
  f5_fall = f5_fall % (#DEATH_SHOWS + #DEATH_FALLS) + 1
  local show
  if f5_fall <= #DEATH_SHOWS then show, forceFall = DEATH_SHOWS[f5_fall], "own"
  else show, forceFall = DEATH_SHOWS[1], DEATH_FALLS[f5_fall - #DEATH_SHOWS] end
  log(string.format("F5: test death %d of %d: %s, fall %s", f5_fall, #DEATH_SHOWS + #DEATH_FALLS, show, forceFall))
  if play_show(pawn, "CH_P_EVE_01/Basic/" .. show, "F5") then f5_at = os.clock() else forceFall = nil end
end

-- F10: a wound, blunt (tune.gore.bluntWound) and stab in turn
local f10_stab = false
local function sandbox_wound()
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not (gore and valid(mesh)) then log("F10: no Eve or no gore.lua"); return end
  f10_stab = not f10_stab
  gore.wound(pawn, mesh, nil, nil, "F10", f10_stab and "stab" or "blunt")
end

-- real death: blood where she was hit, then maybe take a limb; h: the killing blow (death_hit), or nil
local function gore_death(pawn, mesh, h)
  local g = tune.gore or {}
  if not gore or g.enabled == false then return end
  local hit = try(function() local h = pawn.RagdollInfo.HitLocation; return { X = h.X, Y = h.Y, Z = h.Z } end)
  if hit and hit.X == 0 and hit.Y == 0 and hit.Z == 0 then hit = nil end
  gore.on_hit(pawn, mesh, hit or try(function() return mesh:GetSocketLocation(FName("Bip001-Spine2")) end))
  -- F5's test death: always the split top to bottom, down the middle (her left and right), on her fall
  local f5 = f5_at and os.clock() - f5_at < 5
  f5_at = nil
  if f5 and g.f5Split ~= false then
    log("death: F5's test death, split top to bottom")
    gore.split(pawn, mesh, nil, nil, "death")
    return
  end
  if g.sliceOnDeath ~= false and math.random() <= (g.sliceChance or 1.0) then
    local style = attack_style(h)
    -- a stab or blunt killing blow presses in where it landed, against its direction (else against her push)
    if h and style ~= "blade" then
      local out = h.dir and { X = -h.dir.X, Y = -h.dir.Y, Z = -h.dir.Z }
      if out and out.X == 0 and out.Y == 0 and out.Z == 0 then out = nil end
      out = out or try(function() local v = pawn.RagdollInfo.ImpulseValue; return { X = -v.X, Y = -v.Y, Z = -v.Z } end)
      log(string.format("death: last hit %.2f s ago (hook called %d times, %d on Eve), a %s (group %s, show %s)",
        os.clock() - h.t, hitCalls, hitsOnEve, style, h.group, h.show))
      if gore.wound(pawn, mesh, h.loc or hit, out, "death", style) then return end
    end
    -- a killing blow the game told us about cuts along the blade (gore.blow), else the roll below
    if h and style == "blade" and math.random() <= (g.bladeChance or 0.85) then
      log(string.format("death: last hit %.2f s ago (hook called %d times, %d on Eve), cutting along the blade",
        os.clock() - h.t, hitCalls, hitsOnEve))
      if gore.blow(pawn, mesh, h, "death") then return end
    end
    local normal = split_normal(h)
    -- a blade's death always takes something off: a wound only for stabs and blunt blows (whose own one failed)
    local kind = pick_kind(style ~= "blade", normal ~= nil, style == "blunt")
    log(string.format("death: last hit %s (hook called %d times, %d on Eve), from above %s, rolled %s",
      h and string.format("%.2f s ago", os.clock() - h.t) or "none", hitCalls, hitsOnEve, tostring(normal ~= nil), kind))
    if kind == "split" then
      gore.split(pawn, mesh, hit or (h and h.loc), normal, "death")
    elseif kind == "wound" then
      -- out of the body, against the push the killing blow gave her
      local out = try(function() local v = pawn.RagdollInfo.ImpulseValue; return { X = -v.X, Y = -v.Y, Z = -v.Z } end)
      if out and out.X == 0 and out.Y == 0 and out.Z == 0 then out = nil end
      if not out and h and h.push then out = { X = -h.push.X, Y = -h.push.Y, Z = -h.push.Z } end
      gore.wound(pawn, mesh, hit or (h and h.loc), out, "death", "blunt")
    else
      gore.slice(pawn, mesh, hit, "death", kind)
    end
  end
end

-- key actions wait for the next game-thread tick (see game_tick below)
local pending = {}
local function on_key(label, fn)
  return function()
    pending[#pending + 1] = function()
      local ok, err = pcall(fn)
      if not ok then log(label .. " error: " .. tostring(err)) end
    end
  end
end
RegisterKeyBind(Key.F7, on_key("F7", sandbox_ragdoll))
RegisterKeyBind(Key.F8, on_key("F8", sandbox_recover))
RegisterKeyBind(Key.F6, on_key("F6", load_tune))
RegisterKeyBind(Key.F9, on_key("F9", sandbox_slice))
RegisterKeyBind(Key.F10, on_key("F10", sandbox_wound))
RegisterKeyBind(Key.F11, on_key("F11", sandbox_split))
RegisterKeyBind(Key.F5, on_key("F5", sandbox_death))
RegisterKeyBind(Key.F5, { ModifierKey.SHIFT }, on_key("Shift+F5", sandbox_blade))

-- who touches the mesh around death/respawn: Blueprint-level destroys and Eve's (re)init events
local hooked = false
local function hook_once()
  if hooked then return end
  hooked = true
  local function h(path, label)
    local ok, err = pcall(RegisterHook, path, function(ctx)
      local o = try(function() return ctx:get() end)
      log(string.format("HOOK %s on %s", label, name(o)))
      if label == "NotifyBP_ReInitActor" and after >= 0 then respawned, after, lastRecover = true, 0, -100 end
    end)
    log(string.format("hook %s: %s", label, ok and "ok" or tostring(err)))
  end
  -- no native hooks on K2_DestroyComponent/K2_DestroyActor: reading the dying object there crashed the game
  local bp = "/Game/Art/Character/PC/CH_P_EVE_01/Blueprints/CH_P_EVE_01_Blueprint.CH_P_EVE_01_Blueprint_C:"
  for _, f in ipairs({ "NotifyBP_ReInitActor", "NotifyBP_InitActor", "NotifyBP_SetMesh", "ApplyMeshInfo" }) do
    h(bp .. f, f)
  end
  local hit_fn = "/Script/SB.SBNetworkPlayerController:ClientBroadcast_SkillHitResult"
  local ok, err = pcall(RegisterHook, hit_fn, function(...)
    local ok2, e = pcall(on_skill_hit, ...)
    if not ok2 then log("hit hook error: " .. tostring(e)) end
  end)
  log("hook ClientBroadcast_SkillHitResult: " .. (ok and "ok" or tostring(err)))
end

local usmapTried = false
local function maybe_dump_usmap()
  if usmapTried then return end
  usmapTried = true
  local f = io.open(USMAP_DONE, "r")
  if f then f:close(); return end
  log("dumping reflection schema (DumpUSMAP), the game may hitch for a few seconds")
  local ok, err = pcall(DumpUSMAP)
  log("DumpUSMAP: " .. (ok and "ok" or tostring(err)))
  if ok then
    local w = io.open(USMAP_DONE, "w")
    if w then w:write(os.date()); w:close() end
  end
end

local function trace(pawn, mesh)
  local parts = {}
  for _, b in ipairs(BONES) do
    local bn = FName(b)
    local lv = try(function() return mesh:GetPhysicsLinearVelocity(bn) end)
    local av = try(function() return mesh:GetPhysicsAngularVelocityInDegrees(bn) end)
    local tag = b:gsub("Bip001%-", "")
    if b == "Bip001-Pelvis" then
      tag = tag .. v3(try(function() return mesh:GetSocketLocation(bn) end))
    end
    parts[#parts + 1] = string.format("%s v=%.0f w=%.0f", tag, len(lv), len(av))
  end
  log(string.format("p%03d %s", polls, table.concat(parts, " ")))
end

-- Animated deaths: the data mod's ragdoll key in her animated death shows (P_Eve_Dead, Dead2, Dead3, _Nikke,
-- Eve_Dead_Down) carries ImpulseLimitVelocity 701, and the death table points the stand and light-hit deaths at
-- them. That key is only the signal that she died: the show's own fall plays on, physics goes back off, and cuts
-- happen on the animated body like F9's on a standing Eve (the piece simulates, she doesn't). The end pose holds,
-- so nothing jiggles on the floor. Heavy hits, explosions, airborne and ledge deaths keep the raw ragdoll, and so do
-- a waist cut and a split (on_need_ragdoll). Knockdown shows have no key at all, so a knockdown never counts.
local ANIM_MARK = 701
local function animated_marker(pawn)
  local v = try(function() return pawn.RagdollInfo.ImpulseLimitVelocity end)
  return v and math.abs(v - ANIM_MARK) < 0.5, v
end
local anim_fall
local function animated_death(pawn, mesh, push)
  local a = tune.active or {}
  if a.enabled == false or a.animated == false then return false end
  local marked, v = animated_marker(pawn)
  if not marked then
    log(string.format("death: ragdoll show (ImpulseLimitVelocity %s)", tostring(v)))
    return false
  end
  try(function() mesh:SetAllBodiesSimulatePhysics(false) end)
  try(function() mesh:SetSimulatePhysics(false) end)
  return anim_fall(pawn, mesh, push)
end

-- her fall plays on as the death (the show's own, or one of DEATH_FALLS over it)
anim_fall = function(pawn, mesh, push)
  local a = tune.active or {}
  animDeath = { pawn = pawn, mesh = mesh, push = push }
  log(string.format("death: animated fall, physics off (pelvis simulating %s)",
    tostring(try(function() return mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end))))
  local fall = forceFall
  forceFall = nil
  if not fall and a.animatedPool ~= false then
    local k = math.random(#DEATH_FALLS + 1)
    fall = k <= #DEATH_FALLS and DEATH_FALLS[k] or "own"
  end
  if fall and fall ~= "own" then
    animDeath.fall = fall
    if not play_show(pawn, "CH_P_EVE_01/Ragdoll/EveDeath_" .. fall, "animated death") then animDeath.fall = "own (" .. fall .. " didn't play)" end
  else
    animDeath.fall = "own"
  end
  log("animated death: fall " .. animDeath.fall)
  return true
end

local function tick()
  local pawn = find_eve()
  if not pawn then return end
  -- a pawn from a level that is still streaming in (or being torn down): leave it alone
  if try(function() return pawn.bActorIsBeingDestroyed end) ~= false
    or (try(function() return pawn:GetGameTimeSinceCreation() end) or 0) < 2 then return end
  maybe_dump_usmap()
  hook_once()
  local mesh = try(function() return pawn.Mesh end)
  if not valid(mesh) then return end
  local function simulating() return try(function() return mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end) == true end
  local sim = simulating()

  if gore then
    gore.tick(pawn)
    -- gore can switch an animated death to the ragdoll (a split after its splitAnim): read it again, or this tick
    -- saw a death with no fall and no ragdoll and ended it (she was put back whole mid death)
    if not sim and animDeath == nil and active then sim = simulating() end
  end
  if f7_push then
    f7_push.n = f7_push.n - 1
    if f7_push.n <= 0 then
      local p = f7_push
      f7_push = nil
      if valid(p.mesh) and active then
        f7_shove(p.pawn, p.mesh)
        -- the push shows in the bodies' speed only after the next physics step
        f7_after = { mesh = p.mesh, n = 1 }
      end
    end
  elseif f7_after then
    f7_after.n = f7_after.n - 1
    if f7_after.n <= 0 then
      if valid(f7_after.mesh) then log(string.format("F7: pelvis %.0f cm/s after the push", body_speed(f7_after.mesh, "Bip001-Pelvis"))) end
      f7_after = nil
    end
  end
  if rag and not sim then rag.track(pawn) end
  if not sim then poll_mesh_hit(mesh) end
  if f5_at and not sim and not active and os.clock() - f5_at >= ((tune.gore or {}).f5Delay or 0.5) then
    -- the show's ragdoll key does nothing while she is alive (F5 played the fall, then nothing): the death starts
    -- here, on her animated fall, as if the key had fired
    log("F5: the show's ragdoll key didn't fire (she isn't dead), the test death starts here")
    after = -1
    saved = {}
    on_start(pawn, mesh)
    anim_fall(pawn, mesh, nil)
    gore_death(pawn, mesh, nil)
    f5_at = nil
  elseif sim and not active then
    after = -1
    saved = {}
    on_start(pawn, mesh)
    local h = death_hit(pawn, mesh)
    if not animated_death(pawn, mesh, h and h.push) and rag then rag.start(pawn, mesh, "death", h and h.push) end
    gore_death(pawn, mesh, h)
  elseif not sim and active and animDeath then
    -- her own fall: the death continues without physics
    if polls == 15 then
      log(string.format("animated death at 0.5 s: pelvis%s, simulating %s", v3(try(function() return mesh:GetSocketLocation(FName("Bip001-Pelvis")) end)),
        tostring(try(function() return mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end))))
    end
    -- is she lying at the end? her head's height over the mesh's origin (her feet, the floor)
    if polls == 90 or polls == 150 then
      local h = try(function() return mesh:GetSocketLocation(FName("Bip001-Head")).Z - mesh:K2_GetComponentLocation().Z end)
      log(string.format("animated death (%s) at %.0f s: head %s cm over the floor%s", tostring(animDeath.fall), polls / 30,
        h and string.format("%.0f", h) or "?", h and h > 60 and " - NOT LYING, drop this fall" or ""))
    end
  elseif not sim and active then
    on_end(pawn, mesh)
  elseif not sim and after >= 0 then
    -- respawn window: the game may detach / move things again after our first recovery
    local chatty = respawned or after < AFTER_POLLS
    if respawned and after == 5 then log("after respawn: unpin(" .. reattach_transform(mesh) .. ")") end
    if chatty and after % 10 == 0 then watch(pawn, mesh) end
    if chatty and after % 60 == 0 then log("ragdoll state after: " .. ragdoll_state(pawn)) end
    if not attached_to_capsule(pawn, mesh) and after - lastRecover >= 30 then
      lastRecover = after
      recover(pawn, mesh, "off the capsule at a" .. after)
    end
    after = after + 1
    -- the respawn waits on the player's revive input, so only count down once it happened
    if respawned and after > AFTER_POLLS then after = -1 end
  elseif not sim then
    local l = try(function() return mesh.RelativeLocation end)
    local r = try(function() return mesh.RelativeRotation end)
    if l and r then rel.loc, rel.rot = copy3(l, XYZ), copy3(r, PYR) end
  end

  if active and polls * POLL_MS / 1000 >= (tune.recoverAfter or 10) then
    -- get her up ourselves while the death screen covers it; the sandbox (F8) recovery always worked,
    -- the one after the game's respawn never did
    log(string.format("recovering after %.1f s of ragdoll, before the game respawns her", polls * POLL_MS / 1000))
    try(function() mesh:SetAllBodiesSimulatePhysics(false) end)
    try(function() mesh:SetSimulatePhysics(false) end)
    on_end(pawn, mesh)
  end

  if active then
    no_snapshot(pawn)
    if rag then rag.tick(POLL_MS / 1000) end
    if polls == 45 then log("ragdoll state at 1.5 s: " .. ragdoll_state(pawn)) end
    if polls == 60 and gore and not saved.collision then gore.on_settled(pawn, mesh) end
    if polls % TRACE_EVERY == 0 and polls < TRACE_POLLS then trace(pawn, mesh) end
    polls = polls + 1
  end
end

-- Threading: this game has no UEngine::Tick for UE4SS to hook, so ExecuteInGameThread runs its callbacks
-- from the next ProcessEvent on any thread, Blueprint worker threads included. A recovery run there
-- deadlocked the game (PhysX waited on the game thread, which waited on UE4SS's Lua lock). So the real
-- work runs from Eve's own ReceiveTick (actor ticks are game thread); the async loop only finds her and
-- installs that hook.
-- A death reloads the level: a new Eve ticks, the old one is freed. UE4SS's IsValid reads the object, so asking
-- it about the old pawn crashed the game on the new one's first tick. The script now follows the actor whose tick
-- it runs on: a different one is taken once ours has been silent for a second (never two at once), and everything
-- held from the old one is dropped without touching it.
local function forget_world()
  active, polls, after, respawned, lastRecover = false, 0, -1, false, -100
  saved, hits, pending, animDeath = {}, {}, {}, nil
  rel = { loc = nil, rot = nil }
  meshHit, meshKey = nil, nil
  if gore then gore.forget() end
  if rag then rag.forget() end
end
local function adopt(ctx)
  local self = ctx and try(function() return ctx:get() end)
  local a = self and try(function() return self:GetAddress() end)
  if not a then return false end
  local now = os.clock()
  if a == pawnAddr then pawnSeen = now; return true end
  if pawnAddr and now - pawnSeen < 1.0 then return false end
  if pawnAddr then log(string.format("new Eve %x (was %x, the level reloaded): dropped everything held from the old one", a, pawnAddr)) end
  if pawnAddr then forget_world() end
  pawnAddr, pawnSeen, cachedPawn = a, now, self
  return true
end

local nextTick = 0
local lastTickErr, tickErrRepeats = nil, 0
local function game_tick(ctx)
  if not adopt(ctx) then return end
  local now = os.clock()
  for _, fn in ipairs(pending) do fn() end
  pending = {}
  if now < nextTick then return end
  nextTick = now + POLL_MS / 1000
  local ok, err = xpcall(tick, debug and debug.traceback or tostring)
  if not ok then
    -- the same error on every tick filled the log (900 lines in 30 s): once with its traceback, then a count
    err = tostring(err)
    if err == lastTickErr then
      tickErrRepeats = tickErrRepeats + 1
      if tickErrRepeats % 300 == 0 then log(string.format("tick error repeated %d times", tickErrRepeats)) end
    else
      lastTickErr, tickErrRepeats = err, 0
      log("tick error: " .. err)
    end
  end
end

local TICK_FN = "/Game/Art/Character/PC/CH_P_EVE_01/Blueprints/CH_P_EVE_01_Blueprint.CH_P_EVE_01_Blueprint_C:ReceiveTick"
local hookedFn = nil
LoopAsync(250, function()
  -- only object lookups from this thread, no engine calls; (re)hook when the Blueprint (re)loads
  if not valid(FindFirstOf("CH_P_EVE_01_Blueprint_C")) then return false end
  local fn = try(function() return StaticFindObject(TICK_FN) end)
  local addr = valid(fn) and fn:GetAddress() or nil
  if addr and addr ~= hookedFn then
    local ok, err = pcall(RegisterHook, TICK_FN, function(ctx) game_tick(ctx) end)
    if ok then hookedFn = addr end
    log(string.format("tick hook on %x: %s", addr, ok and "ok" or tostring(err)))
  end
  return false
end)

log("loaded (stabiliser + logger)")
