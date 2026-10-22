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
-- F9 cuts a limb, the head or the torso (tune.gore), F10 puts a living hit's mark on her (tune.gore.hitMarks: a hit she
-- lives through leaves a slash of blood on her skin, healing fades it), F11 ragdolls her and splits
-- her in half top to bottom, Ctrl+Shift+F5 ragdolls her and cuts along a made-up blade (as a killing blow does), Ctrl+F5 plays one
-- of her animated death shows (a test death, which always splits her: tune.gore.f5Split).
-- Enemies (enemies.lua): F5 spawns the picked humanoid enemy in front of her, Shift+F5 picks the next, Shift+F6 shows
-- or hides the spawner window (sbslice.dll), Ctrl+F6 ragdolls the followed one nearest her (the passive Airborne
-- Squad die no other way); her killing blows and hits on their corpses cut them like her.
-- Glass cannon (glass.lua, off by default, Shift+F8): the shield guards her HP, once it is down any hit kills her, cut
-- where it landed; her blows do several times the damage.
-- Settings: settings.lua (the player's switches) over tune.lua. The test keys, the spawner and the glass cannon only
-- work with its dev on.
-- Hits: the game tells clients about every skill hit (SBNetworkPlayerController:ClientBroadcast_SkillHitResult,
-- with the swing's direction); the last one on Eve decides whether a killing blow came down from above. In single
-- player it never fires: the blow is made up from her mesh's hit or the nearest enemy (death_hit). Every killing
-- blow cuts, whatever hit her (a fist cuts like a blade).
-- On first load it also dumps the full reflection schema (DumpUSMAP) for asset editing.
-- Log: ue4ss/Mods/StellarBladeGore/stellarbladegore.log (also mirrored into UE4SS.log).

local MOD = "StellarBladeGore"
local VERSION = "0.2.1"
local LOG_PATH = "ue4ss/Mods/StellarBladeGore/stellarbladegore.log"
local POLL_MS = 33
local TRACE_EVERY = 3       -- log motion every 3rd poll (~10 Hz)
local TRACE_POLLS = 120     -- ~4 s

local CH = { WorldStatic = 0, WorldDynamic = 1, Pawn = 2, Visibility = 3, Camera = 4, PhysicsBody = 5 }
local IGNORE, BLOCK = 0, 2
local NO_COLLISION = 0
local BONES = { "Bip001-Pelvis", "Bip001-Head", "Bip001-R-Hand" }

local TUNE_PATH = "ue4ss/Mods/StellarBladeGore/Scripts/tune.lua"
local SETTINGS_PATH = "ue4ss/Mods/StellarBladeGore/Scripts/settings.lua"
-- what ships: copied to settings.lua on the first start, so a zip extracted over an update never overwrites the
-- player's own
local SETTINGS_DEFAULT = "ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua"
local GORE_PATH = "ue4ss/Mods/StellarBladeGore/Scripts/gore.lua"
local ACTIVE_PATH = "ue4ss/Mods/StellarBladeGore/Scripts/active.lua"
local PHYSFIX_PATH = "ue4ss/Mods/StellarBladeGore/Scripts/physfix.lua"
local ENEMIES_PATH = "ue4ss/Mods/StellarBladeGore/Scripts/enemies.lua"
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
-- settings.lua (the player's few switches) laid over tune.lua (every knob), key by key
local function overlay(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then overlay(dst[k], v) else dst[k] = v end
  end
end
local function first_settings()
  local f = io.open(SETTINGS_PATH, "r")
  if f then f:close(); return end
  local d = io.open(SETTINGS_DEFAULT, "r")
  if not d then return end
  local text = d:read("*a"); d:close()
  local o = io.open(SETTINGS_PATH, "w")
  if o then o:write(text); o:close(); log("settings.lua made from settings.default.lua")
  else log("settings.lua couldn't be written: settings.default.lua is used as it is") end
end

local function load_tune()
  first_settings()
  local ok, t = pcall(dofile, TUNE_PATH)
  if ok and type(t) == "table" then
    local sok, s = pcall(dofile, SETTINGS_PATH)
    if not sok and tostring(s):find("No such file", 1, true) then sok, s = pcall(dofile, SETTINGS_DEFAULT) end
    if sok and type(s) == "table" then overlay(t, s)
    elseif not tostring(s):find("No such file", 1, true) then log("settings.lua failed: " .. tostring(s)) end
    t.dev = t.dev == true
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
    if goreCtx.enemies then goreCtx.enemies.reload() end
  else
    log("tune.lua failed: " .. tostring(t))
  end
end
log(string.format("Stellar Blade Gore Mod %s", VERSION))
load_tune()

local gore, rag, physfix = nil, nil, nil
-- an animated death (see animated_death below): { pawn, mesh, push } while her own fall plays, nil otherwise
local animDeath = nil
-- one of the data mod's falls is playing: it holds its last frame for 120 s (the game's dead pose snapped in when it
-- ended 0.9 s after the fall), so recovery stops it, or a test death (F5) left her lying there
local heldShow = false
local function ragdoll_now(why)
  local a = animDeath
  if not a then return end
  animDeath = nil
  try(function() a.mesh:SetSimulatePhysics(true) end)
  try(function() a.mesh:SetAllBodiesSimulatePhysics(true) end)
  try(function() a.mesh:SetAllBodiesBelowSimulatePhysics(FName("Bip001"), true, true) end)
  try(function() a.mesh:WakeAllRigidBodies() end)
  log(string.format("animated death: ragdoll after all (%s), pelvis simulating %s", why,
    tostring(try(function() return a.mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end))))
  if rag then rag.start(a.pawn, a.mesh, "death", a.push) end
end
goreCtx.log, goreCtx.try, goreCtx.valid, goreCtx.v3 = log, try, valid, v3
-- her mesh's physics asset, the one physfix gave an outfit without one included
goreCtx.physics_of = function(m)
  if physfix then return physfix.asset(m) end
  local pa = try(function() return m:GetPhysicsAsset() end)
  if valid(pa) then return pa end
  pa = try(function() return m.SkeletalMesh.PhysicsAsset end)
  return valid(pa) and pa or nil
end
-- a severed limb stops being driven by the muscle tone
goreCtx.on_cut = function(mesh, bone) if rag then rag.on_cut(mesh, bone) end end
-- a split's copy settles with her
goreCtx.on_copy = function(comp) if rag then rag.add_body(comp) end end
-- a split holds her still until it opens, then she falls in halves
goreCtx.on_broken = function(mesh, bone) if rag then rag.broken(mesh, bone) end end
-- a split half's gone limbs fall free: the settle check doesn't wait for them
goreCtx.on_free = function(comp, bone) if rag then rag.freed(comp, bone) end end
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
  local ok3, p = pcall(dofile, PHYSFIX_PATH)
  if ok3 and type(p) == "table" then
    physfix = p
    physfix.init(goreCtx)
  else
    log("physfix.lua failed: " .. tostring(p))
  end
  -- gore on generic humanoid enemies and the enemy spawner (goreCtx.enemies; main.lua has no locals to spare)
  goreCtx.gore = gore
  local ok4, en = pcall(dofile, ENEMIES_PATH)
  if ok4 and type(en) == "table" then
    goreCtx.enemies = en
    en.init(goreCtx)
  else
    log("enemies.lua failed: " .. tostring(en))
  end
  -- the glass cannon mode (goreCtx.glass, tune.glassCannon)
  local ok5, gl = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/glass.lua")
  if ok5 and type(gl) == "table" then
    goreCtx.glass = gl
    gl.init(goreCtx)
  else
    log("glass.lua failed: " .. tostring(gl))
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

local DIE1_PATH = "/Game/Art/Character/PC/CH_P_EVE_01/Animation/Facial/EVE_Facial_ActionVoice_DIE1.EVE_Facial_ActionVoice_DIE1"
-- DIE1 is curves only (JALI morph names): her body's anim instance carries them, and the master-posed face takes its
-- morph targets from there. Both are read for a few of the death face's curves.
local FACE_CURVES = { "jaw_open", "upLid_down_L", "brow_down", "lipCorner_down" }
local function face_curves(mesh, face)
  local ai = try(function() return mesh:GetAnimInstance() end)
  local out = {}
  for _, c in ipairs(FACE_CURVES) do
    local b = valid(ai) and try(function() return ai:GetCurveValue(FName(c)) end)
    local m = valid(face) and try(function() return face:GetMorphTarget(FName(c)) end)
    out[#out + 1] = string.format("%s %s/%s", c, b and string.format("%.2f", b) or "?", m and string.format("%.2f", m) or "?")
  end
  return "curves body/face: " .. table.concat(out, ", ")
end

-- what her face plays after she died: the death voice (die1, from Eve_Dead_Common) plays the death face, and in
-- the eighteenth playtest no death showed one
local function face_probe(pawn, mesh, at)
  local face = gore and gore.face_of and gore.face_of(pawn, mesh)
  if not valid(face) then log(string.format("face at %.1f s: no face component", at)); return end
  local ai = try(function() return face:GetAnimInstance() end)
  local mont = valid(ai) and try(function() return ai:GetCurrentActiveMontage() end)
  local master = try(function() return face.MasterPoseComponent:Get() end)
  log(string.format("face at %.1f s: %s visible=%s tick=%s anim=%s mode=%s montage=%s master=%s lod=%s", at, name(face),
    tostring(try(function() return face:IsVisible() end)), tostring(try(function() return face:IsComponentTickEnabled() end)),
    valid(ai) and (try(function() return ai:GetClass():GetFName():ToString() end) or "?") or "none",
    tostring(try(function() return face:GetAnimationMode() end)),
    valid(mont) and (try(function() return mont:GetFName():ToString() end) or "?") or "none",
    valid(master) and name(master) or "none", tostring(try(function() return face.ForcedLodModel end))))
  -- the face is posed by her body (master pose), so the facial animation plays in her body's anim blueprint, whose
  -- facial variables are read here (FacialOn / FacialPlayPosition / FacialPlayRate, JALI lip sync), off the anim
  -- instance and the pawn; and whether the death face's animation is loaded at all
  local bai = try(function() return mesh:GetAnimInstance() end)
  local parts = {}
  for _, src in ipairs({ { "anim", bai }, { "pawn", pawn } }) do
    local o = src[2]
    if valid(o) then
      for _, k in ipairs({ "FacialOn", "FacialPlayPosition", "FacialPlayRate", "UseJALI", "UseNewJaliFace", "bActiveJali",
        "StanceFacialAnimIndex", "FacialAnimTypeIndex", "bPlayFacialAnim" }) do
        local v = try(function() return o[k] end)
        if v ~= nil and type(v) ~= "userdata" then parts[#parts + 1] = string.format("%s.%s=%s", src[1], k, tostring(v)) end
      end
    end
  end
  local die1 = try(function() return StaticFindObject(DIE1_PATH) end)
  log(string.format("face at %.1f s: body anim %s, %s, DIE1 loaded %s, %s", at,
    valid(bai) and (try(function() return bai:GetClass():GetFName():ToString() end) or "?") or "none",
    #parts > 0 and table.concat(parts, " ") or "no facial variables read", tostring(valid(die1)), face_curves(mesh, face)))
end

-- ---- the death face ----
-- DIE1 (Proper Death Expression) does start as she dies: her eyelids were closing 0.2 s in (upLid_down_L 0.95 on her
-- body's curves), and by 1 s every curve was back at 0 and she stared with her eyes open (twentieth playtest; the
-- sequencer calls tried before had nothing to be called on). So the mod holds a dead face itself: morph targets set on
-- her face mesh (SetMorphTarget; a master-posed face adds its own over the curves it takes from her body), faded in
-- from tune.gore.deathFace.at over fade seconds and held until she gets up. Each entry of deathFace.morphs names a
-- JALI morph, its ARKit twin and a weight: the first name her face mesh has is used (both would close the eyes twice).
-- Shift+F7 shows it on her living face for 3 s.
local dface = { known = {}, on = nil } -- known: mesh asset addr -> { set of its morph names, count }; on: the face held
function dface.names(face)
  local sm = try(function() return face.SkeletalMesh end)
  local a = valid(sm) and try(function() return sm:GetAddress() end)
  if not a then return {}, 0 end
  if dface.known[a] then return dface.known[a].set, dface.known[a].n end
  local set, n = {}, 0
  try(function()
    sm.MorphTargets:ForEach(function(_, e)
      local m = e:get()
      local nm = valid(m) and try(function() return m:GetFName():ToString() end)
      if nm then set[nm], n = true, n + 1 end
    end)
  end)
  dface.known[a] = { set = set, n = n }
  return set, n
end
function dface.start(pawn, mesh, why, hold)
  local df = (tune.gore or {}).deathFace or {}
  local face = gore and gore.face_of and gore.face_of(pawn, mesh)
  if not valid(face) then face = mesh end
  local set, n = dface.names(face)
  local list, shown = {}, {}
  for _, e in ipairs(df.morphs or {}) do
    local w = e[#e]
    for i = 1, #e - 1 do
      if set[e[i]] then
        list[#list + 1] = { FName(e[i]), w }
        shown[#shown + 1] = string.format("%s %.2f", e[i], w)
        break
      end
    end
  end
  if #list == 0 then
    local some = {}
    for k in pairs(set) do if #some < 40 then some[#some + 1] = k end end
    log(string.format("face (%s): none of deathFace.morphs on %s (%d morph targets: %s)", why, name(face), n,
      table.concat(some, " ")))
    return
  end
  dface.stop()
  dface.on = { face = face, list = list, t0 = os.clock(), fade = math.max(df.fade or 0.5, 0.01), till = hold and os.clock() + hold }
  log(string.format("face (%s): holding %d of her %d morph targets on %s: %s", why, #list, n, name(face), table.concat(shown, ", ")))
end
-- every tick: the weights again (the game resets the morph targets it drives, and the fade)
function dface.tick()
  local f = dface.on
  if not f then return end
  if not valid(f.face) or (f.till and os.clock() >= f.till) then dface.stop(); return end
  local k = math.min(1, (os.clock() - f.t0) / f.fade)
  for _, e in ipairs(f.list) do try(function() f.face:SetMorphTarget(e[1], e[2] * k, false) end) end
end
function dface.stop()
  local f = dface.on
  dface.on = nil
  if not (f and valid(f.face)) then return end
  for _, e in ipairs(f.list) do try(function() f.face:SetMorphTarget(e[1], 0, true) end) end
end
local faceCheck = nil
-- hits after death (hits_after, below): n so far this death, armed once the weapon slowed after the last, t0 the death
local ah = { n = 0, armed = false, t0 = 0 }
local function sandbox_face()
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not valid(mesh) then log("Shift+F7: no Eve"); return end
  log("Shift+F7: " .. face_curves(mesh, gore and gore.face_of and gore.face_of(pawn, mesh)))
  dface.start(pawn, mesh, "Shift+F7", 3)
  faceCheck = { at = os.clock() + 0.8, mesh = mesh, pawn = pawn }
end

-- SB's ragdoll drags the capsule (and the camera on it) after a bone, RagdollInfo.CapsuleComponentFollowingSocket, a
-- step every tick: the camera stuttered after her (playtest 38). The data mod clears it in every death show's ragdoll
-- key, but an animated death that goes ragdoll partway, or a test ragdoll, never runs one, and the default is
-- Bip001-Pelvis. Cleared on every ragdoll tick (tune.capsuleStill). Playtest 41: an animated death gone ragdoll still
-- had the capsule 50-65 cm a tick after her body with the socket None and her movement already MOVE_None (the game
-- moves the pawn itself; putting it back every tick made the camera strobe), so the view is held instead (below).
-- The log says how the capsule moves (at most 5 ticks) and how far it went
local hold = nil
local function hold_capsule(pawn, sim)
  if tune.capsuleStill == false then return end
  local ri = try(function() return pawn.RagdollInfo end)
  local cur = ri and try(function() return ri.CapsuleComponentFollowingSocket:ToString() end)
  if cur and cur ~= "None" then
    try(function() ri.CapsuleComponentFollowingSocket = FName("None") end)
    log("capsule: the ragdoll had it follow " .. cur .. ", now it stays where she died")
  end
  if not hold then hold = { far = 0, logged = 0 } end
  local c = try(function() local v = pawn:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
  if not sim or not c then return end
  if not hold.at then hold.at, hold.last = c, c end
  hold.far = math.max(hold.far, dist(hold.at, c))
  local step = dist(hold.last, c)
  hold.last = c
  if step > 2 and hold.logged < 5 then
    hold.logged = hold.logged + 1
    log(string.format("capsule: moved %.0f cm this tick (%.0f off where she went limp)", step, dist(hold.at, c)))
  end
end
local function capsule_report()
  local h = hold
  hold = nil
  if h and h.at then log(string.format("capsule: drifted at most %.0f cm during the ragdoll", h.far)) end
end

-- Playtest 41: the camera followed her body after an animated death went ragdoll (a split, a beheading, a leg): the
-- game moves her pawn after the ragdoll and the view rides the pawn. Nothing needs following: at a death a still
-- camera is put where the view is and made the view target, back to her at recovery (tune.cameraStill). The log says
-- where the view is against her capsule and head for 3 s
local camHeld = nil -- { pc, cam, pawn, mesh, d, pitch, yaw, t, pivot, home, from, turned, free, placed }
local function fwd(r)
  local p, y = math.rad(r.Pitch), math.rad(r.Yaw)
  return { X = math.cos(p) * math.cos(y), Y = math.cos(p) * math.sin(y), Z = math.sin(p) }
end
local camWatch = nil -- { t0, n }
local PELVIS = FName("Bip001-Pelvis")
local function camera_pelvis(h)
  return valid(h.mesh) and try(function() local v = h.mesh:GetSocketLocation(PELVIS); return { X = v.X, Y = v.Y } end)
end
local function camera_hold(pawn)
  camWatch = { t0 = os.clock(), n = 0 }
  if tune.cameraStill == false or tune.cameraFollow == true or camHeld then return end
  local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
  local cls = StaticFindObject("/Script/Engine.CameraActor")
  local pc = valid(gs) and try(function() return gs:GetPlayerController(pawn, 0) end)
  local pcm = valid(gs) and try(function() return gs:GetPlayerCameraManager(pawn, 0) end)
  if not (valid(cls) and valid(pc) and valid(pcm)) then log("camera: no controller or camera manager, the view follows her"); return end
  local loc = try(function() local v = pcm:GetCameraLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
  local rot = try(function() local r = pcm:GetCameraRotation(); return { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end)
  local fov = try(function() return pcm:GetFOVAngle() end)
  if not (loc and rot) then log("camera: can't read the view, it follows her"); return end
  local tm = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = loc, Scale3D = { X = 1, Y = 1, Z = 1 } }
  local cam = try(function()
    local d = gs:BeginDeferredActorSpawnFromClass(pawn, cls, tm, 1, nil)
    return gs:FinishSpawningActor(d, tm)
  end)
  if not valid(cam) then log("camera: spawn failed, the view follows her"); return end
  try(function() cam:K2_SetActorLocationAndRotation(loc, rot, false, {}, true) end)
  local cc = try(function() return cam.CameraComponent end)
  if valid(cc) then
    try(function() cc.bConstrainAspectRatio = false end)
    if fov then try(function() cc:SetFieldOfView(fov) end) end
  end
  try(function() pc:SetViewTargetWithBlend(cam, 0, 0, 0, false) end)
  -- it turns about the point it looked at, where she died (her capsule's distance down the view), all the way round
  -- either way, with the mouse and the right stick read straight off the controller's input (playtest 41: while she
  -- is dead the game turns the controller's rotation only sideways, and putting it back each frame didn't take)
  local cap = try(function() local v = pawn:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
  local d = cap and math.max(dist(loc, cap), 150) or 400
  local f = fwd(rot)
  local mesh = try(function() return pawn.Mesh end)
  camHeld = { pc = pc, cam = cam, pawn = pawn, mesh = mesh, d = d, pitch = rot.Pitch, yaw = rot.Yaw, t = os.clock(),
    pivot = { X = loc.X + f.X * d, Y = loc.Y + f.Y * d, Z = loc.Z + f.Z * d } }
  camHeld.from = camera_pelvis(camHeld)
  camHeld.home = { X = camHeld.pivot.X, Y = camHeld.pivot.Y, Z = camHeld.pivot.Z }
  log(string.format("camera: view held at %s (fov %s) till she gets up, target %s", v3(loc), tostring(fov),
    name(try(function() return pcm.ViewTarget.Target end))))
end
local function wrap(a) a = (a + 180) % 360 - 180; return a end
local ks = nil
-- every frame (game_tick): the held view turned about its point by the mouse (tune.cameraMouse degrees a unit of mouse
-- input) and the right stick (tune.cameraStick degrees a second at full tilt), the point flown about by WASD, Q/E and
-- the left stick and triggers (tune.cameraMove cm a second, Shift tune.cameraFast times that, no further than
-- tune.cameraRange from where it started), kept out of walls (traces on the Camera channel, her and the camera
-- ignored: the point stops 10 cm short of what it would fly into, the view 10 cm short of what is between them)
local function K(n) return { KeyName = FName(n) } end
local KEYS = { mx = K("MouseX"), my = K("MouseY"), sx = K("Gamepad_RightX"), sy = K("Gamepad_RightY"),
  lx = K("Gamepad_LeftX"), ly = K("Gamepad_LeftY"), lt = K("Gamepad_LeftTriggerAxis"), rt = K("Gamepad_RightTriggerAxis"),
  w = K("W"), a = K("A"), s = K("S"), d = K("D"), q = K("Q"), e = K("E"), shift = K("LeftShift") }
local function axis(pc, k) return try(function() return pc:GetInputAnalogKeyState(k) end) or 0 end
local function down(pc, k) return try(function() return pc:IsInputKeyDown(k) end) and 1 or 0 end
local function dead(v) return math.abs(v) < 0.15 and 0 or v end
-- where a Camera-channel trace from a to b first hits, or nil
local function camera_trace(h, a, b)
  if not valid(ks) then ks = try(function() return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end) end
  if not valid(ks) then return nil end
  local hit = {}
  local blocked = try(function()
    return ks:LineTraceSingle(h.cam, a, b, 1, false, { h.pawn, h.cam }, 0, hit, true,
      { R = 1, G = 0, B = 0, A = 1 }, { R = 0, G = 1, B = 0, A = 1 }, 0)
  end)
  return blocked and try(function() local l = hit.Location; return { X = l.X, Y = l.Y, Z = l.Z } end) or nil
end
-- a point 10 cm short of where the way from a towards b (dir, len) is blocked, or b
local function camera_short(h, a, dir, len)
  local b = { X = a.X + dir.X * len, Y = a.Y + dir.Y * len, Z = a.Z + dir.Z * len }
  local at = camera_trace(h, a, b)
  if not at then return b end
  local l = math.max(dist(a, at) - 10, 0)
  return { X = a.X + dir.X * l, Y = a.Y + dir.Y * l, Z = a.Z + dir.Z * l }
end
local function camera_orbit()
  local h = camHeld
  if not (h and valid(h.cam) and valid(h.pc)) then return end
  local now = os.clock()
  local dt = math.min(now - h.t, 0.1)
  h.t = now
  local pc = h.pc
  local mx, my, sx, sy = axis(pc, KEYS.mx), axis(pc, KEYS.my), dead(axis(pc, KEYS.sx)), dead(axis(pc, KEYS.sy))
  local km, kst = tune.cameraMouse or 3, tune.cameraStick or 150
  local dy = mx * km + sx * kst * dt
  local dp = my * km + sy * kst * dt
  if not h.turned and (dy ~= 0 or dp ~= 0) then
    h.turned = true
    log(string.format("camera: turning with the player (mouse %.2f %.2f, stick %.2f %.2f)", mx, my, sx, sy))
  end
  h.yaw, h.pitch = wrap(h.yaw + dy), wrap(h.pitch + dp)
  -- past straight up or down the view goes on over the top, upside down
  local rot = { Pitch = h.pitch, Yaw = h.yaw, Roll = 0 }
  local f = fwd(rot)
  -- flying: forward along the view, sideways on the level (flipped upside down), up and down in the world
  local mf = down(pc, KEYS.w) - down(pc, KEYS.s) + dead(axis(pc, KEYS.ly))
  local mr = down(pc, KEYS.d) - down(pc, KEYS.a) + dead(axis(pc, KEYS.lx))
  local mu = down(pc, KEYS.e) - down(pc, KEYS.q) + dead(axis(pc, KEYS.rt)) - dead(axis(pc, KEYS.lt))
  local moved = false
  -- not till every key that flies it has been let go once: she died running, W still down, and it flew off at once
  if not h.armed then h.armed = mf == 0 and mr == 0 and mu == 0 end
  if h.armed and (mf ~= 0 or mr ~= 0 or mu ~= 0) then
    local y, flip = math.rad(h.yaw), math.cos(math.rad(h.pitch)) < 0 and -1 or 1
    local v = { X = f.X * mf - math.sin(y) * flip * mr, Y = f.Y * mf + math.cos(y) * flip * mr, Z = f.Z * mf + mu }
    local l = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
    local step = math.min(l, 1) * (tune.cameraMove or 400) * (down(pc, KEYS.shift) == 1 and (tune.cameraFast or 3) or 1) * dt
    if l > 0 and step > 0 then
      local dir = { X = v.X / l, Y = v.Y / l, Z = v.Z / l }
      local to = camera_short(h, h.pivot, dir, step)
      local range = tune.cameraRange or 1500
      local o = { X = to.X - h.home.X, Y = to.Y - h.home.Y, Z = to.Z - h.home.Z }
      local r = math.sqrt(o.X * o.X + o.Y * o.Y + o.Z * o.Z)
      if r > range then to = { X = h.home.X + o.X * range / r, Y = h.home.Y + o.Y * range / r, Z = h.home.Z + o.Z * range / r } end
      if not h.free then h.free = true; log("camera: flying free (it stops sliding after her)") end
      h.pivot, moved = to, true
    end
  end
  -- till then it slides after her pelvis on the level (tune.cameraTrack): the point it turns about moves by as much as
  -- her pelvis has since she died, eased in, height kept
  local rate = tune.cameraTrack or 2.5
  local p = not h.free and rate > 0 and h.from and camera_pelvis(h)
  if p then
    local k = 1 - math.exp(-rate * dt)
    local ox, oy = (p.X - h.from.X) * k, (p.Y - h.from.Y) * k
    if ox * ox + oy * oy > 0.0001 then
      h.from.X, h.from.Y = h.from.X + ox, h.from.Y + oy
      h.pivot.X, h.pivot.Y = h.pivot.X + ox, h.pivot.Y + oy
      h.home.X, h.home.Y = h.home.X + ox, h.home.Y + oy
      moved = true
    end
  end
  if dy == 0 and dp == 0 and h.placed and not moved then return end
  h.placed = true
  local loc = camera_short(h, h.pivot, { X = -f.X, Y = -f.Y, Z = -f.Z }, h.d)
  try(function() h.cam:K2_SetActorLocationAndRotation(loc, rot, false, {}, true) end)
end
local function camera_release(pawn)
  local h = camHeld
  camHeld, camWatch = nil, nil
  if not h then return end
  if valid(h.pc) and valid(pawn) then try(function() h.pc:SetViewTargetWithBlend(pawn, 0, 0, 0, false) end) end
  if valid(h.cam) then try(function() h.cam:K2_DestroyActor() end) end
  log("camera: view back on her")
end
local function camera_watch(pawn, mesh)
  local w = camWatch
  if not w or w.n >= 6 then return end
  local t = os.clock() - w.t0
  if t < w.n * 0.5 then return end
  w.n = w.n + 1
  local cam = try(function()
    local v = StaticFindObject("/Script/Engine.Default__GameplayStatics"):GetPlayerCameraManager(pawn, 0):GetCameraLocation()
    return { X = v.X, Y = v.Y, Z = v.Z }
  end)
  local c = try(function() local v = pawn:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
  local h = try(function() local v = mesh:GetSocketLocation(FName("Bip001-Head")); return { X = v.X, Y = v.Y, Z = v.Z } end)
  log(string.format("camera at %.1f s: view%s, %.0f cm from her capsule%s, %.0f from her head%s",
    t, v3(cam), dist(cam, c), v3(c), dist(cam, h), v3(h)))
end

-- Esc on a death (tune.deathSkip): the game runs tune.deathSkipSpeed times as fast till its death screen
-- (WB_MainHUD_Dead) shows, instead of the wait. The mod's own clock for getting her up (recoverAfter) counts the
-- game's time meanwhile (ahead: game seconds over real ones), so she still gets up under the screen
local skip, ahead = nil, 0 -- skip: { t0, k, pawn }
local function time_speed(pawn, k)
  local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
  return valid(gs) and valid(pawn) and try(function() gs:SetGlobalTimeDilation(pawn, k); return true end) == true
end
local function death_screen()
  local w = try(function() return FindFirstOf("WB_MainHUD_Dead_C") end)
  if not valid(w) then return false end
  local vis = try(function() return w:GetVisibility() end) or 0 -- 1 collapsed, 2 hidden
  return try(function() return w:IsInViewport() end) == true and vis ~= 1 and vis ~= 2
end
local function skip_stop(why)
  local sk = skip
  skip = nil
  if not sk then return end
  time_speed(valid(sk.pawn) and sk.pawn or find_eve(), 1)
  log(string.format("death: fast forward off after %.1f s (%s)", os.clock() - sk.t0, why))
end
local function skip_start(pawn)
  -- a real death only: the test ragdolls (F7, saved.collision) have no death screen
  if tune.deathSkip == false or skip or not active or saved.collision or not valid(pawn) then return end
  if death_screen() then log("death: Esc, the death screen is up already"); return end
  local k = tune.deathSkipSpeed or 6
  if not time_speed(pawn, k) then log("death: Esc, the game's speed can't be set"); return end
  skip = { t0 = os.clock(), k = k, pawn = pawn }
  log(string.format("death: Esc, fast forward x%.0f to the death screen", k))
end
-- every tick of the ragdoll: the game's time it ran ahead, and the fast forward off once the screen shows (or the
-- game's time is past getting her up, with no screen seen: a test death)
local function skip_tick()
  if not skip then return end
  ahead = ahead + (skip.k - 1) * POLL_MS / 1000
  if death_screen() then skip_stop("the death screen is up")
  elseif polls * POLL_MS / 1000 + ahead >= (tune.recoverAfter or 10) then skip_stop("no death screen seen") end
end

local function on_start(pawn, mesh)
  log("ragdoll state at start: " .. ragdoll_state(pawn))
  -- her voice for any death: a cry as she dies, nothing after (gore.lua, tune.gore.voice)
  if gore then try(function() gore.voice_death(pawn, mesh) end) end
  ah.n, ah.armed, ah.t0 = 0, false, os.clock()
  no_snapshot(pawn)
  hold = nil
  hold_capsule(pawn)
  camera_hold(pawn)
  deaths = deaths + 1
  active, polls, ahead = true, 0, 0
  saved = { meshPB = try(function() return mesh:GetCollisionResponseToChannel(CH.PhysicsBody) end) }
  -- "auto": the data mod fixes the collision table of every outfit's physics asset (mod/ragdoll_spec.json,
  -- "outfits"), so those keep self-collision (limbs can't pass through each other); vanilla ones (outfit mods
  -- that ship their own physics asset) overlap at rest and fling
  -- an outfit the data mod didn't patch: its loose bodies are locked to the body above them, and a mesh with no
  -- physics asset gets one (physfix.lua)
  if physfix then try(function() physfix.start(pawn, mesh) end) end
  local paObj = goreCtx.physics_of(mesh)
  local pa = name(paObj)
  local selfCol = tune.selfCollision
  if selfCol == "auto" or selfCol == nil then
    selfCol = patched_physics(paObj) and not (physfix and physfix.runtime_fixed(paObj))
  end
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
  if physfix then try(function() physfix.stop() end) end
  local steps = { "unlock(" .. unlock(pawn, mesh) .. ")" }
  if heldShow then
    heldShow = false
    local ok, err = pcall(function() pawn:StopAllShow() end)
    steps[#steps + 1] = ok and "fallStopped" or ("fallNotStopped(" .. tostring(err) .. ")")
  end
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

-- the camera rides her capsule, which stays where she died while her ragdoll slides and tumbles away: the capsule
-- drifts after her pelvis instead, loosely (nothing within cameraSlack cm, then cameraRate of the rest a tick), held
-- cameraLift cm over it. It ignores her bodies meanwhile, or moving it would shove them
local followed = nil -- { cap, resp }: the capsule's PhysicsBody response before the death
local function camera_follow(pawn, mesh)
  if tune.cameraFollow == false then return end
  local cap = try(function() return pawn.CapsuleComponent end)
  local p = try(function() local v = mesh:GetSocketLocation(FName("Bip001-Pelvis")); return { X = v.X, Y = v.Y, Z = v.Z } end)
  local c = try(function() local v = pawn:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
  if not (valid(cap) and p and c) then return end
  if not followed then
    followed = { cap = cap, resp = try(function() return cap:GetCollisionResponseToChannel(CH.PhysicsBody) end) }
    try(function() cap:SetCollisionResponseToChannel(CH.PhysicsBody, IGNORE) end)
  end
  local t = { X = p.X, Y = p.Y, Z = p.Z + (tune.cameraLift or 95) }
  local d = { X = t.X - c.X, Y = t.Y - c.Y, Z = t.Z - c.Z }
  local l = math.sqrt(d.X * d.X + d.Y * d.Y + d.Z * d.Z)
  local slack = tune.cameraSlack or 40
  if l <= slack then return end
  local k = (1 - slack / l) * (tune.cameraRate or 0.06)
  try(function() pawn:K2_SetActorLocation({ X = c.X + d.X * k, Y = c.Y + d.Y * k, Z = c.Z + d.Z * k }, false, {}, true) end)
end
local function camera_unfollow()
  local f = followed
  followed = nil
  if f and valid(f.cap) and f.resp then try(function() f.cap:SetCollisionResponseToChannel(CH.PhysicsBody, f.resp) end) end
end

local function on_end(pawn, mesh)
  log("ragdoll state at end: " .. ragdoll_state(pawn))
  log(string.format("mesh flags at ragdoll end: pendingKill=%s beginDestroyed=%s",
    tostring(try(function() return mesh:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end)),
    tostring(try(function() return mesh:HasAnyFlags(EObjectFlags.RF_BeginDestroyed) end))))
  active, animDeath = false, nil
  after, lastRecover, respawned = 0, -100, false
  camera_unfollow()
  capsule_report()
  camera_release(pawn)
  skip_stop("she got up")
  dface.stop()
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
  if goreCtx.glass then goreCtx.glass.revived(pawn) end
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
-- a living Eve's gameplay collision has no physics: the Ragdoll profile, and the old setup to put back (on_end)
local function ragdoll_collision(mesh)
  local c = { resp = {} }
  c.obj = try(function() return mesh:GetCollisionObjectType() end)
  c.enabled = try(function() return mesh:GetCollisionEnabled() end)
  for ch = 0, 31 do c.resp[ch] = try(function() return mesh:GetCollisionResponseToChannel(ch) end) end
  try(function() mesh:SetCollisionProfileName(FName("Ragdoll"), true) end)
  return c
end

local function sandbox_ragdoll()
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not valid(mesh) then log("F7: no Eve"); return end
  if active then log("F7: already ragdolled"); return end
  local c = ragdoll_collision(mesh)
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

-- what a killing blow does, by tune.gore.death's odds: "limb", "head", "torso" or "split" (split only when allowed:
-- a blow that came down from above)
local KINDS = { "limb", "head", "torso", "split" }
local function pick_kind(split)
  local odds = (tune.gore or {}).death or { limb = 50, head = 25, torso = 15, split = 10 }
  local function w(k)
    if k == "split" and not split then return 0 end
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
  log(string.format("hit on Eve: at %s bone %s dir %s fwd %s normal %s, %s", v3(h.loc), h.bone,
    vs(h.dir), vs(h.fwd), v3(h.normal), what))
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
-- a living hit's mark (tune.gore.hitMarks, gore.hit_mark): q, the hits waiting to be marked; pct, her HP bar's last
-- reading (read every 0.25 s while she is alive), the "before" of the next hit
local hm = { q = {}, pct = nil, nextBar = 0 }
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
  -- marked a moment later, if she still lives (a killing blow's hit is the death cut's)
  local mk = (tune.gore or {}).hitMarks or {}
  if loc and not active and mk.enabled ~= false then
    hm.q[#hm.q + 1] = { due = os.clock() + (mk.delay or 0.25), loc = loc, push = dir, pre = hm.pct }
    if #hm.q > 4 then table.remove(hm.q, 1) end
  end
  log(string.format("mesh hit: force %s at %s bone %s power %s, shake at %s dir %s -> on her %s", v3(f), v3(at),
    tostring(bone), tostring(try(function() return mesh.PhysicalHitForcePower end)), v3(sp), v3(sd), tostring(loc ~= nil)))
end

-- every character in the level, kept as they spawn (FindAllOf walks every object: 35 ms, a stutter when it ran four
-- times a second for the swing, eighteenth playtest); seeded once per level. An entry whose object went, or whose
-- address now holds something else, is dropped.
local chars, charsSeeded = {}, false
local function add_char(o)
  local ad = try(function() return o:GetAddress() end)
  local cls = ad and try(function() return o:GetClass():GetFName():ToString() end)
  if cls then chars[ad] = { obj = o, cls = cls } end
end
do
  local ok, err = pcall(NotifyOnNewObject, "/Script/SB.SBCharacter", function(o) add_char(o) end)
  if not ok then log("characters: NotifyOnNewObject failed: " .. tostring(err)) end
end
local function live_chars()
  if not charsSeeded then
    charsSeeded = true
    for _, a in ipairs(try(function() return FindAllOf("SBCharacter") end) or {}) do add_char(a) end
  end
  local out = {}
  for ad, e in pairs(chars) do
    if valid(e.obj) and try(function() return e.obj:GetClass():GetFName():ToString() end) == e.cls then
      out[#out + 1] = { obj = e.obj, addr = ad, cls = e.cls }
    else
      chars[ad] = nil
    end
  end
  return out
end
goreCtx.live_chars = live_chars
-- not an enemy: her drone and the other playable characters (tune.gore.attackerIgnore, parts of class names)
local function ignored(cls)
  for _, p in ipairs((tune.gore or {}).attackerIgnore or { "Drone", "CH_P_", "AirborneSquad" }) do
    if cls:find(p, 1, true) then return true end
  end
  return false
end

-- the nearest other character within tune.gore.attackerReach of her: who most likely killed her
local function attacker(pawn, mesh, within)
  local me = pawnAddr
  local at = try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Spine1"))) end)
  if not at then return nil end
  local reach = within or (tune.gore or {}).attackerReach or 800
  local best, bd = nil, nil
  for _, e in ipairs(live_chars()) do
    local a = e.obj
    if e.addr ~= me and not ignored(e.cls) and try(function() return a.bActorIsBeingDestroyed end) == false
      and try(function() return a.bHidden end) ~= true then
      local l = try(function() return vof(a:K2_GetActorLocation()) end)
      local d = dist(l, at)
      if l and d >= 0 and d < reach and (not bd or d < bd) then best, bd = { actor = a, loc = l, d = d, cls = e.cls }, d end
    end
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
-- ---- the killing swing, off the enemy's weapon ----
-- In single player no hit says how the blow went, so the nearest enemy within tune.gore.swingReach is followed while
-- she lives: its weapon bones (by name, else its hands) are sampled every tick for the last swingWindow seconds. At
-- death the fastest stretch of the fastest bone is the swing, and the plane it sweeps (the arc through three samples,
-- else the swing and the enemy's forward) is the blade's.
local SWING_NAMES = { "weapon", "blade", "sword", "knife", "claw", "axe", "spear", "lance", "scythe", "wp", "hand" }
local swing = { addr = nil, actor = nil, mesh = nil, bones = nil, who = nil, hist = {}, refresh = 0 }
local swingBones = {} -- enemy class -> its weapon bones, found once
local function cross(a, b) return { X = a.Y * b.Z - a.Z * b.Y, Y = a.Z * b.X - a.X * b.Z, Z = a.X * b.Y - a.Y * b.X } end
local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function sub(a, b) return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z } end
local function unit(v) local l = len(v); return l > 1e-6 and { X = v.X / l, Y = v.Y / l, Z = v.Z / l } or nil end
local function swing_bones(m, cls)
  if swingBones[cls] then return swingBones[cls] end
  local n = try(function() return m:GetNumBones() end) or 0
  local names, ranked = {}, {}
  for i = 0, n - 1 do
    local nm = try(function() return m:GetBoneName(i):ToString() end)
    if nm then
      names[#names + 1] = nm
      local low = nm:lower()
      for r, p in ipairs(SWING_NAMES) do
        if low:find(p, 1, true) and not low:find("finger") and not low:find("twist") then
          ranked[#ranked + 1] = { nm, r }
          break
        end
      end
    end
  end
  table.sort(ranked, function(a, b) return a[2] < b[2] end)
  local out, most = {}, (tune.gore or {}).swingBones or 8
  for _, e in ipairs(ranked) do if #out < most then out[#out + 1] = e[1] end end
  swingBones[cls] = out
  log(string.format("swing: %s has %d bones, following %s%s", cls, n, #out > 0 and table.concat(out, ", ") or "none",
    #out == 0 and (": " .. table.concat(names, " ", 1, math.min(#names, 80))) or ""))
  return out
end
local function swing_drop() swing.addr, swing.actor, swing.mesh, swing.bones, swing.who, swing.hist = nil, nil, nil, nil, nil, {} end
local function track_swing(pawn, mesh)
  local g = tune.gore or {}
  if g.weaponSwing == false then return end
  local t0, now = os.clock(), os.clock()
  if now >= swing.refresh then
    swing.refresh = now + (g.swingRefresh or 0.25)
    local a = attacker(pawn, mesh, g.swingReach or 500)
    local ad = a and try(function() return a.actor:GetAddress() end)
    if not ad then
      swing_drop()
    elseif ad ~= swing.addr then
      swing_drop()
      local m = try(function() return a.actor.Mesh end)
      local cls = valid(m) and a.cls
      if cls then
        swing.addr, swing.actor, swing.mesh, swing.who = ad, a.actor, m, a.name
        swing.bones = swing_bones(m, cls)
      end
    end
  end
  if not (swing.mesh and swing.bones and #swing.bones > 0) then return end
  if try(function() return swing.actor.bActorIsBeingDestroyed end) ~= false then swing_drop(); return end
  local s = { t = now, p = {} }
  for i, b in ipairs(swing.bones) do s.p[i] = try(function() return vof(swing.mesh:GetSocketLocation(FName(b))) end) end
  local h = swing.hist
  h[#h + 1] = s
  local keep = g.swingWindow or 0.6
  while #h > 0 and now - h[1].t > keep do table.remove(h, 1) end
  local ms = (os.clock() - t0) * 1000
  if ms >= (g.slowMs or 15) then log(string.format("swing: following %s took %.0f ms", tostring(swing.who), ms)) end
end
-- the swing that killed her, if the weapon moved fast enough: { dir, n, at (the weapon there), speed, bone, fwd }
local function weapon_swing()
  local g = tune.gore or {}
  local h = swing.hist
  -- an old trail (the enemy gone, or a death that started without it) is no swing
  if #h < 3 or not swing.bones or os.clock() - h[#h].t > (g.swingWindow or 0.6) then return nil end
  local best
  for i = 2, #h do
    local dt = h[i].t - h[i - 1].t
    if dt > 1e-3 then
      for b = 1, #swing.bones do
        local p, q = h[i - 1].p[b], h[i].p[b]
        if p and q then
          local v = dist(p, q) / dt
          if not best or v > best.speed then best = { speed = v, i = i, b = b } end
        end
      end
    end
  end
  if not best or best.speed < (g.swingMinSpeed or 300) then
    if best then log(string.format("swing: %s's fastest bone %s only %.0f cm/s", tostring(swing.who), swing.bones[best.b], best.speed)) end
    return nil
  end
  local b, i = best.b, best.i
  local p0, p1 = h[i - 1].p[b], h[i].p[b]
  local dir = unit(sub(p1, p0))
  local fwd = try(function() return vof(swing.actor:GetActorForwardVector()) end)
  -- the arc: the samples either side of the fastest step, when the weapon turned enough between them
  local n, how
  local pa = h[i - 2] and h[i - 2].p[b]
  local pc = h[i + 1] and h[i + 1].p[b]
  local u, w = pa and sub(p0, pa), pc and sub(pc, p1)
  for _, pair in ipairs({ { u, sub(p1, p0) }, { sub(p1, p0), w }, { u, w } }) do
    if not n and pair[1] and pair[2] then
      local c = cross(pair[1], pair[2])
      if len(c) > 0.2 * len(pair[1]) * len(pair[2]) then n, how = unit(c), "weapon arc" end
    end
  end
  if not n and dir and fwd then
    local c = cross(dir, fwd)
    if len(c) > 0.3 then n, how = unit(c), "weapon swing x forward" end
  end
  if not (n and dir) then return nil end
  return { dir = dir, n = n, how = how, at = p1, speed = best.speed, bone = swing.bones[b], fwd = fwd,
    ago = os.clock() - h[i].t }
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
  local ws = weapon_swing()
  if ws then
    -- where the swept plane crosses her: the mesh's hit, else the part of her nearest it and the weapon
    local loc, bone, off = m and m.loc, m and m.bone, nil
    if not loc then
      local bd
      for _, e in ipairs(SWING_AT) do
        local l = try(function()
          local x = mesh:GetSocketLocation(FName(e[1]))
          if not e[3] then return vof(x) end
          local y = mesh:GetSocketLocation(FName(e[3]))
          return { X = x.X + 0.4 * (y.X - x.X), Y = x.Y + 0.4 * (y.Y - x.Y), Z = x.Z + 0.4 * (y.Z - x.Z) }
        end)
        if l then
          local d = math.abs(dot(sub(l, ws.at), ws.n))
          -- near the plane first, then near the weapon, a little toward the parts a blow most likely lands on
          local sc = d + 0.3 * dist(l, ws.at) - e[2]
          if not bd or sc < bd then bd, loc, bone, off = sc, l, e[1], d end
        end
      end
      -- on the plane when it passes that close; else the plane is moved onto her, keeping its angle
      if loc and off <= (g.swingSnap or 30) then
        local k = dot(sub(loc, ws.at), ws.n)
        loc = { X = loc.X - k * ws.n.X, Y = loc.Y - k * ws.n.Y, Z = loc.Z - k * ws.n.Z }
      end
    end
    if loc then
      log(string.format("death: swing of %s's %s at %.0f cm/s %.2f s before, %s %s, %.0f deg down, at %s (%s%s)",
        tostring(swing.who), ws.bone, ws.speed, ws.ago, ws.how, v3({ X = ws.n.X * 100, Y = ws.n.Y * 100, Z = ws.n.Z * 100 }),
        math.deg(math.asin(math.max(-1, math.min(1, -ws.dir.Z)))), v3(loc), m and "where the mesh was hit" or tostring(bone),
        off and string.format(", plane %.0f cm off it%s", off, off > (g.swingSnap or 30) and ", moved onto her" or "") or ""))
      return { t = os.clock(), loc = loc, dir = ws.dir, fwd = ws.fwd or ws.dir, n = ws.n, how = ws.how,
        push = push or ws.dir, attack_dir = 0, src = "weapon", group = h and h.group, show = h and h.show, bone = bone,
        attacker = swing.who }
    end
  end
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
    a and string.format(" (nearest enemy %s, %.0f cm off)", a.name, a.d) or "",
    math.floor(math.deg(ang) + 0.5), v3(loc), m and "where the mesh was hit" or ("made up: " .. tostring(bone))))
  return { t = os.clock(), loc = loc, dir = dir, fwd = fwd, push = push, attack_dir = 0, src = from,
    group = h and h.group, show = h and h.show, bone = bone, attacker = a and a.name }
end

-- ---- hits after death ----
-- An enemy's weapon still swinging through her once she is dead cuts her again (tune.gore.afterHits): every tick of
-- the death the step its fastest weapon bone just made is checked against her parts (SWING_AT, and the head); a step
-- faster than swingMinSpeed passing within reach cm of one is a blow there, cut along the plane the weapon swept as a
-- killing blow is (gore.blow: a limb, the head, or her body in two while she is still whole), else a hit mark. One per
-- swing (the weapon has to slow down again first), at most max a death, none in the first from seconds (the killing
-- swing itself)
local function seg_dist(p, q, x)
  local pq = sub(q, p)
  local t = math.max(0, math.min(1, dot(sub(x, p), pq) / math.max(dot(pq, pq), 1e-4)))
  return dist(x, { X = p.X + t * pq.X, Y = p.Y + t * pq.Y, Z = p.Z + t * pq.Z })
end
local function hits_after(pawn, mesh)
  local g = tune.gore or {}
  local c = g.afterHits or {}
  local hist = swing.hist
  if not (gore and swing.bones) or #hist < 2 or os.clock() - hist[#hist].t > 0.2 then return end
  local a, b = hist[#hist - 1], hist[#hist]
  local dt = b.t - a.t
  if dt < 1e-3 then return end
  local best
  for i = 1, #swing.bones do
    local p, q = a.p[i], b.p[i]
    if p and q then
      local v = dist(p, q) / dt
      if not best or v > best.v then best = { v = v, i = i, p = p, q = q } end
    end
  end
  if not best or best.v < (g.swingMinSpeed or 300) then ah.armed = true; return end
  if not ah.armed or ah.n >= (c.max or 6) or os.clock() - ah.t0 < (c.from or 0.6) or gore.busy() then return end
  local at, d, bone
  local parts = { { "Bip001-Head", 0 } }
  for _, e in ipairs(SWING_AT) do parts[#parts + 1] = e end
  for _, e in ipairs(parts) do
    local l = try(function()
      local x = mesh:GetSocketLocation(FName(e[1]))
      if not e[3] then return vof(x) end
      local y = mesh:GetSocketLocation(FName(e[3]))
      return { X = x.X + 0.4 * (y.X - x.X), Y = x.Y + 0.4 * (y.Y - x.Y), Z = x.Z + 0.4 * (y.Z - x.Z) }
    end)
    local dd = l and seg_dist(best.p, best.q, l)
    if dd and (not d or dd < d) then at, d, bone = l, dd, e[1] end
  end
  if not at or d > (c.reach or 35) then return end
  ah.armed, ah.n = false, ah.n + 1
  -- the plane: the arc through the last three samples, else the step and the enemy's forward
  local dir = unit(sub(best.q, best.p))
  local fwd = try(function() return vof(swing.actor:GetActorForwardVector()) end)
  local n, how
  local pa = hist[#hist - 2] and hist[#hist - 2].p[best.i]
  if pa then
    local u, w = sub(best.p, pa), sub(best.q, best.p)
    local cc = cross(u, w)
    if len(cc) > 0.2 * len(u) * len(w) then n, how = unit(cc), "weapon arc" end
  end
  if not n and dir and fwd then
    local cc = cross(dir, fwd)
    if len(cc) > 0.3 then n, how = unit(cc), "weapon swing x forward" end
  end
  -- onto the plane, through the part it passed
  if n then
    local k = dot(sub(at, best.q), n)
    at = { X = at.X - k * n.X, Y = at.Y - k * n.Y, Z = at.Z - k * n.Z }
  end
  local ncut, split = gore.cuts_on(mesh)
  log(string.format("after death (%.1f s in): %s's %s at %.0f cm/s passed %.0f cm from her %s, hit %d of %d%s",
    os.clock() - ah.t0, tostring(swing.who), swing.bones[best.i], best.v, d, bone, ah.n, c.max or 6,
    split and ", she is split: blood only" or ""))
  gore.on_hit(pawn, mesh, at)
  if split then return end
  gore.aim(dir)
  -- a split needs her whole: once something is off her, a blow through her body is a hit mark instead
  local h = { t = os.clock(), loc = at, dir = dir, fwd = fwd or dir, n = n, how = how, push = dir, attack_dir = 0,
    bone = bone, noSplit = ncut > 0, attacker = swing.who }
  if math.random() <= (c.cutChance or 0.75) and gore.blow(pawn, mesh, h, "after") then return end
  gore.hit_mark(pawn, mesh, at, dir, nil)
end

-- while she is alive: her HP bar for the marks' healing, and the hit waiting for its mark once its delay is up. The
-- slash runs along the attacker's fastest bone's motion (a weapon) if it moved in the last 0.3 s, else the hit's push
local function hit_marks(pawn, mesh)
  local g = tune.gore or {}
  if not gore or g.enabled == false or (g.hitMarks or {}).enabled == false then hm.q = {}; return end
  local now = os.clock()
  if now >= hm.nextBar and goreCtx.glass then
    hm.nextBar = now + 0.25
    -- the HUD is looked for (35 ms) only once a mark is waiting to heal; else only a widget already found is read
    local pct = goreCtx.glass.bar_pct(gore.marks() == 0)
    if pct then hm.pct = pct end
    if gore.marks() > 0 then gore.heal_marks(pct) end
  end
  local q = hm.q[1]
  if not q or now < q.due then return end
  table.remove(hm.q, 1)
  -- held over a death or a load: its place is long gone
  if now - q.due > 1 then return end
  -- a hit that took nothing off her bar (a guard, a parry) leaves no mark (tune.gore.hitMarks.needDamage)
  local pct = goreCtx.glass and goreCtx.glass.bar_pct(true)
  if q.pre and pct and pct > q.pre - 0.001 and (g.hitMarks or {}).needDamage ~= false then
    log(string.format("hit mark skipped: her HP bar didn't drop (%.3f before, %.3f now)", q.pre, pct))
    return
  end
  local dir
  local hist = swing.hist
  if swing.bones and #hist >= 2 and now - hist[#hist].t < 0.3 then
    local a, b = hist[#hist - 1], hist[#hist]
    local bv
    for i = 1, #swing.bones do
      local p, r = a.p[i], b.p[i]
      if p and r and (not bv or dist(p, r) > bv) then bv, dir = dist(p, r), sub(r, p) end
    end
  end
  if dir and len(dir) < 1 then dir = nil end
  gore.hit_mark(pawn, mesh, q.loc, dir or q.push, q.pre)
end

-- what glass.lua reads off the swing tracker and her mesh
goreCtx.swing, goreCtx.SWING_AT, goreCtx.seg_dist, goreCtx.dist, goreCtx.sub, goreCtx.unit = swing, SWING_AT, seg_dist, dist, sub, unit
goreCtx.cross, goreCtx.len, goreCtx.ignored = cross, len, ignored
goreCtx.mesh_hit = function() return meshHit end

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

-- Ctrl+Shift+F5: ragdoll her and cut along a made-up blade, as a killing blow would (gore.blow): a swing level, slanted or
-- straight down through a random part of her, the attacker standing where the camera looks from
local function sandbox_blade()
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not (gore and valid(mesh)) then log("Ctrl+Shift+F5: no Eve or no gore.lua"); return end
  if not active then sandbox_ragdoll() end
  local rot = try(function() return pawn:GetControlRotation() end)
  local yaw = math.rad(rot and rot.Yaw or 0)
  local fwd = { X = math.cos(yaw), Y = math.sin(yaw), Z = 0 }
  local side = math.random() < 0.5 and -1 or 1
  local a = math.rad(({ 0, 30, 60, 90 })[math.random(4)])
  local dir = { X = -math.sin(yaw) * side * math.cos(a), Y = math.cos(yaw) * side * math.cos(a), Z = -math.sin(a) }
  local bone, loc = swing_at(mesh)
  if not loc then log("Ctrl+Shift+F5: no " .. bone); return end
  log(string.format("Ctrl+Shift+F5: blade through %s, %d deg down", bone, math.floor(math.deg(a) + 0.5)))
  gore.aim(dir)
  gore.blow(pawn, mesh, { t = os.clock(), loc = loc, dir = dir, fwd = fwd, attack_dir = 0, bone = bone }, "F5")
end

-- more falls for an animated death: the data mod's death shows made from her knockdown falls (Ragdoll/EveDeath_*,
-- no ragdoll key; the knockdown shows themselves are untouched). One is picked at random with her own death show
-- (tune.active.animatedPool) and played over it
local DEATH_FALLS = { "Knock_Down_Start", "Knock_Down_Start1", "Knock_Down_Forward", "Knock_Down_Backward",
  "KnockDown_S_Fw", "KnockDown_S_Bw", "KnockDown_Tumble_Fw", "KnockDown_Tumble_Bw" }
local forceFall = nil -- Ctrl+F5: the fall to play next ("own" = her death show's own)
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

-- Ctrl+F5: one of her animated death shows on the spot, in turn (P_Eve_Dead, Dead2, Dead3). Its ragdoll key is the
-- data mod's death signal, so everything after runs as on a real death: the fall plays, the death's cut is rolled
-- (or cut along the last hit), blood, recovery after recoverAfter. She isn't dead, so the game's death screen and
-- respawn don't come
local DEATH_SHOWS = { "P_Eve_Dead", "P_Eve_Dead2", "P_Eve_Dead3" }
local f5_fall = 0
local f5_at = nil -- when F5 played its death: that death splits her top to bottom (tune.gore.f5Split)
local function sandbox_death()
  local pawn = find_eve()
  if not pawn then log("Ctrl+F5: no Eve"); return end
  if active then log("Ctrl+F5: she is already down (F8 gets her up)"); return end
  -- her three death shows first, then each knockdown fall over the first
  f5_fall = f5_fall % (#DEATH_SHOWS + #DEATH_FALLS) + 1
  local show
  if f5_fall <= #DEATH_SHOWS then show, forceFall = DEATH_SHOWS[f5_fall], "own"
  else show, forceFall = DEATH_SHOWS[1], DEATH_FALLS[f5_fall - #DEATH_SHOWS] end
  if (tune.gore or {}).f5Split ~= false then
    -- a split has no fall before it: the death starts on the next tick, straight into the ragdoll and the cut
    log("Ctrl+F5: test death, split at once")
    forceFall = "own"
    f5_at = os.clock() - ((tune.gore or {}).f5Delay or 0.5)
    return
  end
  log(string.format("Ctrl+F5: test death %d of %d: %s, fall %s", f5_fall, #DEATH_SHOWS + #DEATH_FALLS, show, forceFall))
  if play_show(pawn, "CH_P_EVE_01/Basic/" .. show, "F5") then f5_at = os.clock() else forceFall = nil end
end

local function gore_cut(pawn, mesh, h, hit)
  local g = tune.gore or {}
  -- what comes off flies the way the blow went: from the attacker through her, else the swing, else her push
  local fly = h and (h.push or h.dir)
  if fly and fly.X == 0 and fly.Y == 0 and fly.Z == 0 then fly = nil end
  fly = fly or try(function() local v = pawn.RagdollInfo.ImpulseValue; return { X = v.X, Y = v.Y, Z = v.Z } end)
  gore.aim(fly)
  -- F5's test death: always the split top to bottom, down the middle (her left and right), on her fall
  local f5 = f5_at and os.clock() - f5_at < 5
  f5_at = nil
  if f5 and g.f5Split ~= false then
    log("death: F5's test death, split top to bottom")
    gore.split(pawn, mesh, nil, nil, "death")
    return
  end
  -- the glass cannon mode: the head or body hit that killed her, or what the finishing blow landed on
  local gk = goreCtx.glass and goreCtx.glass.death_cut(pawn, mesh)
  if gk then
    local at = gk.part and gk.part.at
    log(string.format("death (glass cannon): %s, landed on %s (%s)", gk.kind, gk.part and gk.part.bone or "?", gk.part and gk.part.src or "?"))
    if gk.part and gk.part.h and gk.part.h.dir then gore.aim(gk.part.h.dir) end
    -- a weapon's swing that landed: cut along it, as any killing blade (one swing through her raised arm goes on into
    -- her body); else by the part it landed on
    local gh = gk.part and gk.part.h
    if gh and gh.loc and (gh.n or (gh.dir and gh.fwd)) and gore.blow(pawn, mesh, gh, "death") then return end
    if gk.kind == "head" then
      if gore.slice(pawn, mesh, at, "death", "head") then return end
    elseif gk.kind == "torso" then
      local normal = split_normal(gk.part and gk.part.h)
      if normal and g.deathSplit ~= false then gore.split(pawn, mesh, at, normal, "death"); return end
      if gore.slice(pawn, mesh, at, "death", "torso") then return end
    elseif gk.bone then
      if gore.slice_bone(pawn, mesh, gk.bone, at, "death") then return end
    end
  end
  if g.sliceOnDeath ~= false and math.random() <= (g.sliceChance or 1.0) then
    -- a killing blow the game told us about cuts along the blade (gore.blow), else the roll below
    if h and math.random() <= (g.bladeChance or 0.85) then
      log(string.format("death: last hit %.2f s ago (hook called %d times, %d on Eve), cutting along the blade",
        os.clock() - h.t, hitCalls, hitsOnEve))
      if gore.blow(pawn, mesh, h, "death") then return end
    end
    local normal = split_normal(h)
    -- a death always takes something off
    local kind = pick_kind(normal ~= nil)
    log(string.format("death: last hit %s (hook called %d times, %d on Eve), from above %s, rolled %s",
      h and string.format("%.2f s ago", os.clock() - h.t) or "none", hitCalls, hitsOnEve, tostring(normal ~= nil), kind))
    if kind == "split" then
      gore.split(pawn, mesh, hit or (h and h.loc), normal, "death")
    else
      gore.slice(pawn, mesh, hit, "death", kind)
    end
  end
end

-- real death: take something off, and blood where she was hit; h: the killing blow (death_hit), or nil. A split
-- brings its own blood once she has come apart (the hit's blood first read as blood, then a split)
local function gore_death(pawn, mesh, h)
  local g = tune.gore or {}
  if not gore or g.enabled == false then return end
  local hit = try(function() local h = pawn.RagdollInfo.HitLocation; return { X = h.X, Y = h.Y, Z = h.Z } end)
  if hit and hit.X == 0 and hit.Y == 0 and hit.Z == 0 then hit = nil end
  gore_cut(pawn, mesh, h, hit)
  if not gore.splitting() then
    gore.on_hit(pawn, mesh, hit or try(function() return mesh:GetSocketLocation(FName("Bip001-Spine2")) end))
  end
end

-- key actions wait for the next game-thread tick (see game_tick below); dev: a test key, dead unless tune.dev
local pending = {}
local function on_key(label, fn, dev)
  return function()
    if dev and not tune.dev then return end
    pending[#pending + 1] = function()
      local ok, err = pcall(fn)
      if not ok then log(label .. " error: " .. tostring(err)) end
    end
  end
end
RegisterKeyBind(Key.F7, on_key("F7", sandbox_ragdoll, true))
RegisterKeyBind(Key.F7, { ModifierKey.SHIFT }, on_key("Shift+F7", sandbox_face, true))
RegisterKeyBind(Key.F8, on_key("F8", sandbox_recover, true))
RegisterKeyBind(Key.F6, on_key("F6", load_tune))
-- Esc on her death: fast forward to the death screen (tune.deathSkip; parked for now, untested)
-- RegisterKeyBind(Key.ESCAPE, on_key("Esc", function() if active then skip_start(find_eve()) end end))
RegisterKeyBind(Key.F9, on_key("F9", sandbox_slice, true))
-- F10: a living hit's mark on a part at random, on its side facing the camera (tune.gore.hitMarks)
RegisterKeyBind(Key.F10, on_key("F10", function()
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not (gore and valid(mesh)) then log("F10: no Eve or no gore.lua"); return end
  local w = gore.MARK_AT[math.random(#gore.MARK_AT)]
  local a = try(function() return vof(mesh:GetSocketLocation(FName(w.bone))) end)
  local b = try(function() return vof(mesh:GetSocketLocation(FName(w.to))) end)
  local cam = try(function()
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    return vof(gs:GetPlayerCameraManager(pawn, 0):GetCameraLocation())
  end)
  if not (a and b and cam) then log("F10: no bone or camera"); return end
  local mid = { X = (a.X + b.X) / 2, Y = (a.Y + b.Y) / 2, Z = (a.Z + b.Z) / 2 }
  local to = unit(sub(cam, mid))
  local at = to and { X = mid.X + to.X * w.r * 2, Y = mid.Y + to.Y * w.r * 2, Z = mid.Z + to.Z * w.r * 2 } or mid
  local dir = { X = math.random() - 0.5, Y = math.random() - 0.5, Z = math.random() - 0.5 }
  log("F10: hit mark on " .. w.bone)
  gore.hit_mark(pawn, mesh, at, dir, hm.pct)
end, true))
RegisterKeyBind(Key.F11, on_key("F11", sandbox_split, true))
RegisterKeyBind(Key.F5, { ModifierKey.CONTROL }, on_key("Ctrl+F5", sandbox_death, true))
RegisterKeyBind(Key.F5, { ModifierKey.CONTROL, ModifierKey.SHIFT }, on_key("Ctrl+Shift+F5", sandbox_blade, true))
-- the enemy spawner (enemies.lua): F5 spawns the kind picked in front of her, Shift+F5 picks the next, Shift+F6 opens
-- the spawner window, Ctrl+F6 kills the one nearest her
RegisterKeyBind(Key.F5, on_key("F5", function()
  if goreCtx.enemies and find_eve() then goreCtx.enemies.spawn_pick(find_eve()) end
end, true))
RegisterKeyBind(Key.F5, { ModifierKey.SHIFT }, on_key("Shift+F5", function() if goreCtx.enemies then goreCtx.enemies.next_pick() end end, true))
RegisterKeyBind(Key.F6, { ModifierKey.SHIFT }, on_key("Shift+F6", function() if goreCtx.enemies then goreCtx.enemies.toggle_window() end end, true))
RegisterKeyBind(Key.F6, { ModifierKey.CONTROL }, on_key("Ctrl+F6", function()
  if goreCtx.enemies and find_eve() then goreCtx.enemies.kill_nearest(find_eve()) end
end, true))
-- the glass cannon mode on and off (glass.lua, tune.glassCannon)
RegisterKeyBind(Key.F8, { ModifierKey.SHIFT }, on_key("Shift+F8", function() if goreCtx.glass then goreCtx.glass.toggle() end end, true))

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
  if usmapTried or not tune.dev then return end
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
  -- in the air: her fall animation played on mid-air and she sank at 1.2 m/s for 3 s (thirty-fifth playtest)
  if try(function() return pawn.CharacterMovement:IsFalling() end) then
    log("death: animated show in the air, the ragdoll instead")
    return false
  end
  try(function() mesh:SetAllBodiesSimulatePhysics(false) end)
  try(function() mesh:SetSimulatePhysics(false) end)
  return anim_fall(pawn, mesh, push)
end

-- her fall plays on as the death (the show's own, or one of DEATH_FALLS over it)
anim_fall = function(pawn, mesh, push)
  local a = tune.active or {}
  animDeath = { pawn = pawn, mesh = mesh, push = push, z0 = try(function() return mesh:K2_GetComponentLocation().Z end) }
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
    if play_show(pawn, "CH_P_EVE_01/Ragdoll/EveDeath_" .. fall, "animated death") then heldShow = true
    else animDeath.fall = "own (" .. fall .. " didn't play)" end
  else
    animDeath.fall = "own"
  end
  log("animated death: fall " .. animDeath.fall)
  return true
end

-- the glass cannon mode's death when the game doesn't take HP 0 as one: as Ctrl+F5's, straight into the fall and
-- the cut (gore_cut asks glass which)
goreCtx.death = function(pawn, mesh)
  if active then return end
  after = -1
  local c = ragdoll_collision(mesh)
  saved = {}
  on_start(pawn, mesh)
  saved.collision = c
  anim_fall(pawn, mesh, nil)
  gore_death(pawn, mesh, nil)
end

-- a slow tick's time by part (tp.mark), logged by game_tick: the death's own start held a frame 82 ms besides the
-- cut's stages (twenty-fifth playtest)
local tp = { t = 0 }
function tp.mark(what)
  local t = os.clock()
  local ms = (t - tp.t) * 1000
  if ms >= 1 then tp[#tp + 1] = string.format("%s %.0f", what, ms) end
  tp.t = t
end
local function tick()
  for i = #tp, 1, -1 do tp[i] = nil end
  tp.t = os.clock()
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

  tp.mark("find")
  if goreCtx.enemies then goreCtx.enemies.tick(pawn, mesh) end
  tp.mark("enemies")
  if gore then
    gore.tick(pawn, tp.mark)
    tp.mark("gore")
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
  if active and sim then camera_follow(pawn, mesh) end
  if active then hold_capsule(pawn, sim); camera_watch(pawn, mesh) end
  -- the outfit she has on, whenever she is animated (the respawn window included: an outfit put on right after a
  -- reset went unchecked, fifteenth playtest)
  if physfix and not sim and not active then physfix.check(pawn, mesh, false) end
  if rag and not sim then rag.track(pawn) end
  if not sim then poll_mesh_hit(mesh) end
  tp.mark("outfit, hits")
  if not sim and not active then
    track_swing(pawn, mesh)
    tp.mark("swing")
    if gore then gore.watch(mesh) end
    tp.mark("bone watch")
    if goreCtx.glass then goreCtx.glass.tick(pawn, mesh) end
    tp.mark("glass")
    hit_marks(pawn, mesh)
    tp.mark("hit marks")
  elseif active and ((tune.gore or {}).afterHits or {}).enabled ~= false and (tune.gore or {}).enabled ~= false then
    track_swing(pawn, mesh)
    hits_after(pawn, mesh)
    tp.mark("hits after")
  end
  dface.tick()
  tp.mark("face")
  if faceCheck and os.clock() >= faceCheck.at then
    local f = faceCheck
    faceCheck = nil
    if valid(f.mesh) then log("Shift+F7 0.8 s later: " .. face_curves(f.mesh, gore and gore.face_of and gore.face_of(f.pawn, f.mesh))) end
  end
  if f5_at and not sim and not active and os.clock() - f5_at >= ((tune.gore or {}).f5Delay or 0.5) then
    -- the show's ragdoll key does nothing while she is alive (F5 played the fall, then nothing): the death starts
    -- here, on her animated fall, as if the key had fired
    log("Ctrl+F5: the test death starts here (a show's ragdoll key does nothing while she is alive)")
    after = -1
    -- the split goes straight to the ragdoll, with no death show to set her collision up for it: she stayed
    -- kinematic and the death ended on the next tick (twelfth playtest)
    local c = (tune.gore or {}).f5Split ~= false and ragdoll_collision(mesh) or nil
    saved = {}
    on_start(pawn, mesh)
    saved.collision = c
    anim_fall(pawn, mesh, nil)
    gore_death(pawn, mesh, nil)
    f5_at = nil
  elseif sim and not active then
    after = -1
    saved = {}
    on_start(pawn, mesh)
    tp.mark("death start")
    local h = death_hit(pawn, mesh)
    tp.mark("death hit")
    if not animated_death(pawn, mesh, h and h.push) and rag then rag.start(pawn, mesh, "death", h and h.push) end
    tp.mark("fall")
    gore_death(pawn, mesh, h)
    tp.mark("death cut")
  elseif not sim and active and animDeath and polls <= 45 and (try(function() return pawn.CharacterMovement:IsFalling() end)
    or (animDeath.z0 or -1e9) - (try(function() return mesh:K2_GetComponentLocation().Z end) or -1e9) > 25) then
    -- her fall plays on in the air (the game didn't say falling when she died, or she went off a ledge in it): her
    -- feet sank 25 cm under where she died, or her movement says falling
    ragdoll_now("in the air")
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
    tp.mark("death end")
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

  if active then skip_tick() end
  if active and polls * POLL_MS / 1000 + ahead >= (tune.recoverAfter or 10) then
    -- get her up ourselves while the death screen covers it; the sandbox (F8) recovery always worked,
    -- the one after the game's respawn never did
    log(string.format("recovering after %.1f s of ragdoll (%.1f of the game's), before the game respawns her",
      polls * POLL_MS / 1000, polls * POLL_MS / 1000 + ahead))
    try(function() mesh:SetAllBodiesSimulatePhysics(false) end)
    try(function() mesh:SetSimulatePhysics(false) end)
    on_end(pawn, mesh)
  end

  -- a piece cut off her while she is alive (F9) settles on its own clock
  tp.mark("recover")
  if not active and rag then rag.tick(POLL_MS / 1000) end
  if active then
    no_snapshot(pawn)
    if rag then rag.tick(POLL_MS / 1000) end
    if polls == 45 then log("ragdoll state at 1.5 s: " .. ragdoll_state(pawn)) end
    local df = (tune.gore or {}).deathFace or {}
    if df.enabled ~= false and polls == math.max(1, math.floor((df.at or 0.3) * 1000 / POLL_MS)) then
      try(function() dface.start(pawn, mesh, "death") end)
    end
    if polls == 6 or polls == 30 or polls == 90 then try(function() face_probe(pawn, mesh, polls / 30) end) end
    if polls == 60 and gore and not saved.collision then gore.on_settled(pawn, mesh) end
    if polls % TRACE_EVERY == 0 and polls < TRACE_POLLS then trace(pawn, mesh) end
    polls = polls + 1
  end
  tp.mark("ragdoll")
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
  hm.q, hm.pct = {}, nil
  swing_drop(); swingBones = {}
  chars, charsSeeded = {}, false
  followed = nil
  -- (the still camera went with the old level; the new controller looks through its own pawn)
  camHeld, camWatch, hold = nil, nil, nil
  skip, ahead = nil, 0
  -- the old face may be gone: dropped without touching it
  dface.on, dface.known, faceCheck = nil, {}, nil
  if gore then gore.forget() end
  if goreCtx.enemies then goreCtx.enemies.forget() end
  if goreCtx.glass then goreCtx.glass.forget() end
  if rag then rag.forget() end
  if physfix then physfix.forget() end
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
-- a frame that took long (a stutter): told with what the mod did just before, so a stutter at a cut shows whether
-- the mod's own work or the engine's (render state, physics) held it; longer gaps are menus and loading
local HITCH_MS, HITCH_MAX_MS = 70, 1500
local lastFrame, lastTick = nil, nil
local lastTickErr, tickErrRepeats = nil, 0
local function game_tick(ctx)
  if not adopt(ctx) then return end
  local now = os.clock()
  local gap = lastFrame and (now - lastFrame) * 1000
  lastFrame = now
  if gap and gap >= HITCH_MS and gap < HITCH_MAX_MS then
    local st = gore and gore.last_stage
    log(string.format("frame hitch: %.0f ms%s%s", gap,
      lastTick and now - lastTick.t < 0.5 and string.format(", the mod's last tick %.0f ms", lastTick.ms) or "",
      st and now - st.t < 0.5 and ", after " .. st.what or ""))
  end
  for _, fn in ipairs(pending) do fn() end
  pending = {}
  if camHeld then camera_orbit() end
  if now < nextTick then return end
  nextTick = now + POLL_MS / 1000
  local ok, err = xpcall(tick, debug and debug.traceback or tostring)
  lastTick = { t = os.clock(), ms = (os.clock() - now) * 1000 }
  if lastTick.ms >= ((tune.gore or {}).slowMs or 15) then log(string.format("slow tick: %.0f ms: %s", lastTick.ms, table.concat(tp, ", "))) end
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
