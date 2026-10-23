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
-- Sandbox: F7 ragdolls her with a shove onto her back (tune.lua), F8 recovers (F7, F9 and F11 stay until F8), F6 re-reads tune.lua,
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
local VERSION = "0.3.0"
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
-- an object held past this tick: its address and path, taken while it is alive. Garbage collection frees an object's
-- memory, and IsValid on a freed one reads it and crashes UE4SS (no pcall catches that: a death crashed so once the
-- game freed a killed enemy, 0.3.0). held() asks the game's object name table, which drops an object as it is freed,
-- and touches the object only while its path still leads to that address
function goreCtx.keep(o)
  local a = o and try(function() return o:GetAddress() end)
  local full = a and try(function() return o:GetFullName() end)
  local path = full and full:match("^%S+ (.+)$")
  return path and { obj = o, addr = a, path = path } or nil
end
function goreCtx.held(k)
  if not k then return false end
  local o = try(function() return StaticFindObject(k.path) end)
  return o ~= nil and try(function() return o:GetAddress() end) == k.addr and valid(k.obj)
end
-- may an asset be loaded from the pak now (LoadAsset)? Not from her getting up in a death till the new level's Eve has
-- ticked a while: a load on the game thread then waited on the respawn's own loading, whose new objects wait on the
-- Lua lock that thread holds (NotifyOnNewObject: widgets, characters), an endless loading screen (Nexus report).
-- What isn't loaded yet is found or loaded on a later call
goreCtx.quietUntil = 0
goreCtx.may_load = function() return os.clock() >= goreCtx.quietUntil end
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
  if goreCtx.convulse then try(function() goreCtx.convulse.to_ragdoll() end) end
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
-- a cut-off piece collides with the rest of her (physfix.piece_collision: its pairs join the collision table's), the
-- mesh blocking its own bodies' channel, switched off and on so the engine filters her body pairs again
goreCtx.piece_collision = function(mesh, roots)
  if not physfix then return end
  local all, w = physfix.piece_collision(mesh, goreCtx.physics_of(mesh), roots, goreCtx.arm_pairs or {})
  if all and #all > 0 then
    goreCtx.arm_pairs = all
    try(function() mesh:SetCollisionResponseToChannel(CH.PhysicsBody, IGNORE) end)
    try(function() mesh:SetCollisionResponseToChannel(CH.PhysicsBody, BLOCK) end)
  end
  log("cut piece " .. table.concat(roots, ",") .. ": " .. tostring(w))
end
goreCtx.arm_table = function(m, p) return physfix and physfix.arm_table(goreCtx.physics_of(m), p) or "no physfix" end
-- she is up: none of her pairs collide any more. The table lives on her physics asset, so a cut on her standing (F9
-- after F8) took the last ragdoll's pairs, measured in another pose: her hands against her thighs, where they hang
-- now, and the cut flung them off at 2000 cm/s (playtest)
goreCtx.reset_pairs = function(mesh)
  if not goreCtx.arm_pairs then return end
  goreCtx.arm_pairs = nil
  log("collision pairs reset: " .. tostring(goreCtx.arm_table(mesh, {})))
end
-- a split's copy settles with her
goreCtx.on_copy = function(comp) if rag then rag.add_body(comp) end end
-- a split holds her still until it opens, then she falls in halves
goreCtx.on_broken = function(mesh, bone) if rag then rag.broken(mesh, bone) end end
goreCtx.on_mended = function(mesh) if rag then rag.mended(mesh) end end
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
    goreCtx.rag = a
  else
    log("active.lua failed: " .. tostring(a))
  end
  -- her last movements after death (goreCtx.convulse, tune.convulse)
  local ok6, cv = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/convulse.lua")
  if ok6 and type(cv) == "table" then
    goreCtx.convulse = cv
    cv.init(goreCtx)
  else
    log("convulse.lua failed: " .. tostring(cv))
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
-- A mood (tune.gore.deathFace.moods) is picked per death and every weight and time jittered, with her eyes' last
-- opening, their drift and her jaw's hang picked too, so no two deaths wear the same face. Shift+F7 shows the moods
-- in turn on her living face, 6 s each.
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
  -- the mood: by weight, never the one before while there's another (Shift+F7: the next in turn)
  local moods, mood = df.moods or {}, nil
  if #moods > 0 then
    if hold then
      dface.turn = (dface.turn or 0) % #moods + 1
      mood = moods[dface.turn]
    else
      local sum = 0
      for i, m in ipairs(moods) do if i ~= dface.last or #moods == 1 then sum = sum + (m.weight or 1) end end
      local r = math.random() * sum
      for i, m in ipairs(moods) do
        if i ~= dface.last or #moods == 1 then
          r = r - (m.weight or 1)
          if r <= 0 or not mood then mood, dface.pick = m, i end
          if r <= 0 then break end
        end
      end
      dface.last = dface.pick
    end
  end
  -- this death's own: how far her eyes end up shut, where they drift, which way the jaw hangs
  local function rnd(a, b) return a + math.random() * (b - a) end
  local ls = df.lidsShut or { 1, 1 }
  local shut = rnd(ls[1] or 1, ls[2] or ls[1] or 1)
  local extra = {}
  local g = df.gaze or 0
  if g > 0 then
    local dirs = { { "eye_up_L", "eye_up_R" }, { "eye_down_L", "eye_down_R" }, { "eye_left_L", "eye_left_R" },
      { "eye_right_L", "eye_right_R" } }
    local d, a = dirs[math.random(#dirs)], rnd(0.3, 1) * g
    local over = rnd(2, 5)
    extra[#extra + 1] = { d[1], a, from = 0, over = over }
    extra[#extra + 1] = { d[2], a, from = 0, over = over }
  end
  -- a mood made for one side (mirror) is turned to the other half the time: _L/_R, _left/_right, Left/Right swapped
  local flip = mood and mood.mirror and math.random() < 0.5
  local function side_of(nm)
    if not flip then return nm end
    for _, sw in ipairs({ { "_L$", "_R" }, { "_R$", "_L" }, { "_left$", "_right" }, { "_right$", "_left" },
      { "Left$", "Right" }, { "Right$", "Left" } }) do
      if nm:find(sw[1]) then return (nm:gsub(sw[1], sw[2])) end
    end
    return nm
  end
  if (df.jawSide or 0) > 0 and not (mood and mood.mirror) then
    extra[#extra + 1] = { math.random() < 0.5 and "jaw_left" or "jaw_right", rnd(0, df.jawSide), from = 0, over = rnd(4, 8) }
  end
  local j = df.jitter or 0
  local function jit(x) return x and x * rnd(1 - j, 1 + j) end
  -- base, then the mood's, then this death's (a morph named again: the later entry)
  local list, shown, at = {}, {}, {}
  local function add(src, sided)
    for _, e in ipairs(src or {}) do
      local w = e[#e]
      for i = 1, #e - 1 do
        local nm = sided and side_of(e[i]) or e[i]
        if set[nm] then
          -- (from: its weight as the face comes on, easing to w over `over` s: her eyes half open closing, the
          -- grimace slackening)
          w = jit(w)
          if nm:find("^upLid_down") or nm == "eyeBlinkLeft" or nm == "eyeBlinkRight" then w = w * shut end
          local x = { FName(nm), math.min(1, w), nil, from = e.from and math.min(1, jit(e.from)), over = jit(e.over), name = nm }
          if at[nm] then list[at[nm]] = x else list[#list + 1], at[nm] = x, #list + 1 end
          break
        end
      end
    end
  end
  add(df.morphs); add(mood and mood.morphs, true); add(extra)
  for _, e in ipairs(list) do
    shown[#shown + 1] = e.from and string.format("%s %.2f>%.2f", e.name, e.from, e[2]) or string.format("%s %.2f", e.name, e[2])
  end
  if #list == 0 then
    local some = {}
    for k in pairs(set) do if #some < 40 then some[#some + 1] = k end end
    log(string.format("face (%s): none of deathFace.morphs on %s (%d morph targets: %s)", why, name(face), n,
      table.concat(some, " ")))
    return
  end
  dface.stop()
  local has = {}
  for _, e in ipairs(list) do has[e.name] = true end
  dface.on = { face = face, list = list, set = set, has = has, extra = {}, t0 = os.clock(), fade = math.max(df.fade or 0.5, 0.01),
    till = hold and os.clock() + hold }
  log(string.format("face (%s): %s, holding %d of her %d morph targets on %s: %s", why,
    mood and (mood.name .. (flip and " (mirrored)" or "")) or "no mood",
    #list, n, name(face), table.concat(shown, ", ")))
end
-- every tick: the weights again (the game resets the morph targets it drives, and the fade)
function dface.tick()
  local f = dface.on
  if not f then return end
  if not valid(f.face) or (f.till and os.clock() >= f.till) then dface.stop(); return end
  local t = os.clock() - f.t0
  local k = math.min(1, t / f.fade)
  -- the convulsions' face over it (convulse.lua's poses, by morph target name): winces, gasps, tics, flutters
  local c = goreCtx.convulse and goreCtx.convulse.face() or {}
  for _, e in ipairs(f.list) do
    local w = e[2]
    if e.from and (e.over or 0) > 0 then
      local u = math.min(1, t / e.over)
      w = e.from + (w - e.from) * u * u * (3 - 2 * u)
    end
    w = math.max(0, math.min(1, w * k + (c[e.name] or 0)))
    try(function() f.face:SetMorphTarget(e[1], w, false) end)
  end
  -- the ones the death face doesn't hold: set while a pose moves them, back to 0 after
  for m, x in pairs(f.extra) do
    if not c[m] then try(function() f.face:SetMorphTarget(x, 0, false) end); f.extra[m] = nil end
  end
  for m, d in pairs(c) do
    if not f.has[m] and f.set[m] then
      f.extra[m] = f.extra[m] or FName(m)
      local x = f.extra[m]
      try(function() f.face:SetMorphTarget(x, math.max(0, math.min(1, d)), false) end)
    end
  end
end
function dface.stop()
  local f = dface.on
  dface.on = nil
  if not (f and valid(f.face)) then return end
  for _, e in ipairs(f.list) do try(function() f.face:SetMorphTarget(e[1], 0, true) end) end
  for _, x in pairs(f.extra or {}) do try(function() f.face:SetMorphTarget(x, 0, true) end) end
end
local faceCheck = nil
-- hits after death (hits_after, below): n so far this death, armed once the weapon slowed after the last, t0 the death
local ah = { n = 0, armed = false, t0 = 0 }
local function sandbox_face()
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not valid(mesh) then log("Shift+F7: no Eve"); return end
  log("Shift+F7: " .. face_curves(mesh, gore and gore.face_of and gore.face_of(pawn, mesh)))
  dface.start(pawn, mesh, "Shift+F7", 6)
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

-- photo mode in a held death (tune.deathPhoto): the game turns it down while she is dead, so sbslice.dll sets the
-- game's SBPhotoMode_Bypass_ActivationConditionChecks while the death is held, and clears it when it is let go or ends
-- (screen: the death screen's state, below; made here for the camera's sake)
local screen = { n = 0, photo = false }
-- revived where she lay, her movement left off is put back to walking within WINDOW polls (~20 s) after she got up,
-- once it has been off POLLS (~1.5 s) with her capsule still; at = { since = after, at = capsule }: off since then, there
screen.stuck = { WINDOW = 600, POLLS = 45, at = nil }
-- Ultra Violence (screen.uv: on) keeps its blood on her through a respawn: it clears only at a load, a camp rest or
-- in water, and the game's respawn is none of these (reported: its splatters stayed on her after the death). So as
-- we get her up for a respawn her movement mode reads swimming (MOVE_Swimming, written as a property, no mode change
-- events) for UV_POLLS, her movement's tick off so it isn't put back, long enough for its 0.5 s check to see water
-- and clear her ("swim clear" in UE4SS.log); then walking again. uvClean = { pawn, n }
screen.UV_POLLS = 36
function screen.uv_tick()
  local u = screen.uvClean
  if not u then return end
  local cm = valid(u.pawn) and try(function() return u.pawn.CharacterMovement end)
  if not valid(cm) then screen.uvClean = nil; return end
  if u.n == 0 then try(function() cm:SetComponentTickEnabled(false) end) end
  u.n = u.n + 1
  -- (the game's respawn came meanwhile: its movement is left to it)
  if u.n > screen.UV_POLLS or respawned then
    screen.uvClean = nil
    if not respawned then try(function() cm:SetMovementMode(1, 0) end) end
    try(function() cm:SetComponentTickEnabled(true) end)
    log(string.format("Ultra Violence's blood: she read as swimming for %.1f s, then %s", (u.n - 1) * POLL_MS / 1000,
      respawned and "the game's respawn" or "walking"))
    return
  end
  try(function() cm.MovementMode = 4 end)
end
function screen.allow_photo(on, why)
  if on == screen.photo or not gore or (on and tune.deathPhoto == false) then return end
  local r = gore.photo(on)
  if r:match("^ok") then screen.photo = on end
  log(string.format("photo mode %s (%s): %s", on and "allowed in the held death" or "back to the game's checks", why, r))
end

-- Playtest 41: the camera followed her body after an animated death went ragdoll (a split, a beheading, a leg): the
-- game moves her pawn after the ragdoll and the view rides the pawn. Nothing needs following: at a death a still
-- camera is put where the view is and made the view target, back to her at recovery (tune.cameraStill). The log says
-- where the view is against her capsule and head for 3 s
local camHeld = nil -- { pc, cam, pawn, mesh, d, pitch, yaw, t, pivot, home, from, turned, free, placed, photo, vt }
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
  -- photo mode (a held death) looks through its own pawn and takes the mouse and WASD; once it closes the view goes
  -- back to this camera, where it was left
  if screen.photo or h.photo then
    local vt = try(function() return pc.PlayerCameraManager.ViewTarget.Target end)
    local at = valid(vt) and vt:GetAddress() or 0
    if at ~= h.vt then
      h.vt = at
      local cls = at ~= 0 and try(function() return vt:GetClass():GetFName():ToString() end) or "nothing"
      if cls:find("PhotoMode") then
        h.photo = true
        log("camera: photo mode open (" .. cls .. ")")
      elseif h.photo then
        h.photo = false
        if at ~= h.cam:GetAddress() then try(function() pc:SetViewTargetWithBlend(h.cam, 0, 0, 0, false) end) end
        h.vt = nil
        log("camera: photo mode closed (the view was on " .. cls .. "), back on the held camera")
      end
    end
    if h.photo then return end
  end
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
-- the death screen's widget, found once and kept (a scan of every object: 17 ms, twice a second, was a stutter of
-- its own, playtest), looked for at most every 2 s in a death while it isn't found. Never its class default
-- (FindFirstOf gave that, kept for good: no death screen was ever seen), and it lives inside the main HUD, so it is
-- never in the viewport itself: shown when it and its CanvasPanel_Dead are visible
-- Both it and the revive item's screen are caught as they are made (every widget made in a death has its class
-- read): the scan every 2 s while it wasn't found was 60 ms each in a big level, and the death screen's class only
-- loads at the death. One scan a death is left, from 5 s in, for one made before the mod loaded
local dead_hud = { scans = 0 }
do
  local ok, err = pcall(NotifyOnNewObject, "/Script/UMG.UserWidget", function(o)
    -- (any time: the death screen may be made in the frame she dies, before the mod's tick knows it)
    local cls = try(function() return o:GetClass():GetFName():ToString() end)
    if (cls == "WB_MainHUD_Dead_C" or cls == "WB_MainHUD_ResurrectionItem_C")
      and tostring(try(function() return o:GetFName():ToString() end)):find("^Default__") then return end
    if cls == "WB_MainHUD_Dead_C" then dead_hud.w = o
    elseif cls == "WB_MainHUD_ResurrectionItem_C" then dead_hud.rv = o end
    if cls and cls:find("[Pp]hoto") and not tostring(try(function() return o:GetFName():ToString() end)):find("^Default__") then
      local ok, err = pcall(screen.photo_widget, o, cls)
      if not ok then log("photo mode widget: " .. tostring(err)) end
    end
    if active and cls and (cls:find("Dead") or cls:find("Resurrect") or cls:find("Revive")) then
      dead_hud.made = (dead_hud.made and dead_hud.made .. ", " or "") .. cls
    end
  end)
  if not ok then print("[StellarBladeGore] widgets: NotifyOnNewObject failed: " .. tostring(err) .. "\n") end
end
local function death_screen()
  local w = dead_hud.w
  if not valid(w) then
    dead_hud.w = nil
    if dead_hud.scans > 0 then return false end
    dead_hud.scans = 1
    for _, x in ipairs(try(function() return FindAllOf("WB_MainHUD_Dead_C") end) or {}) do
      if valid(x) and not tostring(try(function() return x:GetFName():ToString() end)):find("^Default__") then w = x end
    end
    if not w then return false end
    dead_hud.w = w
  end
  local function shown(x)
    local vis = try(function() return x:GetVisibility() end) or 0 -- 1 collapsed, 2 hidden
    return vis ~= 1 and vis ~= 2 and try(function() return x:IsVisible() end) ~= false
      and (try(function() return x:GetRenderOpacity() end) or 1) > 0.01
  end
  if not shown(w) then return false end
  local cp = try(function() return w:GetWidgetFromName(FName("CanvasPanel_Dead")) end)
  return not valid(cp) or shown(cp)
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

-- what covers the view while the death screen is up (it came up all black, the game behind it not showing:
-- playtest): its "black" and "FadeOut" images, its background blur, the camera's fade. Every 0.5 s, logged when it
-- changes (`death screen: ...`)
-- She is got up when a button on it is pressed (tune.recoverOn "button"): the game respawns her only after that, and
-- got up at recoverAfter under the screen she would stand up whole behind it. seen / gone: the screen came up / went
-- away in this death; press: one of its buttons (or its press animation) fired (screen is made above the camera)
-- its buttons (the custom events their clicks call, under either spelling of the name's number) and its animations:
-- the death animation finishing shows it, the press animation a button pressed. Hooked as soon as its class is
-- loaded (tried once a second in a death till then); none had ever been hooked, as the screen was never seen
local SCREEN_FNS = { WB_Common_btn_1_Event_0 = "press", WB_Common_btn_2_Event_0 = "press", WB_Common_btn_1_Event = "press",
  WB_Common_btn_2_Event = "press", FinishPressAnimation = "press", FinishYouDieAnimation = "shown" }
function screen.reset() dead_hud.scans, dead_hud.made, screen.rv.shown = 0, nil, nil; screen.seen, screen.vis, screen.gone, screen.press, screen.respawn, screen.revived, screen.last = false, false, false, false, false, false, nil; screen.frozen = false end
function screen.hook()
  if screen.hooked or os.clock() < (screen.retry or 0) then return end
  screen.retry = os.clock() + 1
  if not valid(try(function() return StaticFindObject("/Game/Art/UI/Widget/HUD/WB_MainHUD_Dead.WB_MainHUD_Dead_C") end)) then return end
  screen.hooked = true
  local got = {}
  for f, what in pairs(SCREEN_FNS) do
    local ok = pcall(RegisterHook, "/Game/Art/UI/Widget/HUD/WB_MainHUD_Dead.WB_MainHUD_Dead_C:" .. f, function()
      if not active then return end
      if what == "shown" then
        if not screen.seen then log("death screen: " .. f) end
        screen.seen = true
      else
        if not screen.press then log("death screen: " .. f) end
        screen.press = true
      end
    end)
    if ok then got[#got + 1] = f end
  end
  table.sort(got)
  log("hook death screen: " .. (#got > 0 and table.concat(got, ", ") or "none"))
end
-- may she be got up now (her ragdoll has run recoverAfter): a button pressed, the screen gone, or no screen at all
-- recoverAfter + screenWait s in (a death without one: F5's)
function screen.ready(t)
  if tune.recoverOn ~= "button" or screen.press or screen.gone then return true end
  -- the revive screen held or up: she waits for the player's choice
  local rv = screen.rv
  if rv.shown and not rv.down then return false end
  for _, v in pairs(rv.held or {}) do if v ~= false then return false end end
  return not screen.seen and t >= (tune.recoverAfter or 10) + (tune.screenWait or 4)
end
-- the revive item's screen: with one on her the game puts its death screen up the moment she dies, over her death
-- (playtest; without one it fades in at about 7 s). Whichever screen is up before tune.reviveAt s into the death (the
-- death screen, or WB_MainHUD_ResurrectionItem should that be it) is held hidden and off till then. Taken down after
-- it showed (the item used or not) with no death screen up REVIVE_WAIT s later, she was revived and is got up at
-- once (`revive screen: ...` in the log)
screen.rv = {}
local REVIVE_WAIT = 2.5
function screen.revive(t)
  local rv = screen.rv
  if not active or saved.manual then
    for w, vis in pairs(rv.held or {}) do if valid(w) then try(function() w:SetVisibility(vis); w:SetIsEnabled(true) end) end end
    rv.held, rv.up, rv.down, rv.told = nil, nil, nil, nil
    return
  end
  if dead_hud.made and not rv.told then
    rv.told = true
    log(string.format("revive screen: made %.1f s into the death: %s", t, dead_hud.made))
  end
  local on = false
  for _, w in ipairs({ dead_hud.w, dead_hud.rv }) do
    if valid(w) then
      local vis = try(function() return w:GetVisibility() end) or 1 -- 1 collapsed, 2 hidden
      local up = vis ~= 1 and vis ~= 2 and try(function() return w:IsVisible() end) ~= false
      rv.held = rv.held or {}
      if t < (tune.reviveAt or 7) or screen.frozen then
        if up then
          if not rv.held[w] then
            rv.held[w] = vis
            log(string.format("revive screen: %s up %.1f s into the death, held hidden %s",
              tostring(try(function() return w:GetClass():GetFName():ToString() end)), t,
              screen.frozen and "while the death is held (Shift+F4)" or string.format("till %.0f s", tune.reviveAt or 7)))
          end
          try(function() w:SetVisibility(1); w:SetIsEnabled(false) end)
        end
      elseif rv.held[w] ~= nil and rv.held[w] ~= false then
        try(function() w:SetVisibility(rv.held[w]); w:SetIsEnabled(true) end)
        rv.held[w], up = false, true
        rv.shown = true
        log(string.format("revive screen: shown %.1f s into the death", t))
      end
      on = on or up
    end
  end
  -- held (Shift+F4): the screens hidden by the mod don't count as gone
  if not rv.shown or screen.frozen then return end
  if on then rv.up, rv.down = true, nil
  elseif rv.up and not rv.down then rv.down = t; log(string.format("revive screen: gone %.1f s into the death", t))
  elseif rv.down and not screen.revived and t - rv.down >= REVIVE_WAIT and not death_screen() then
    screen.revived = true
  end
end
function screen.probe(pawn)
  screen.n = screen.n + 1
  try(function() screen.revive(polls * POLL_MS / 1000 + ahead) end)
  -- (in a death not before 1 s in: registering them took 166 ms, in the frame the killing blow's cut landed,
  -- playtest; while she plays they're tried too, see the tick)
  if not active or (not saved.manual and polls * POLL_MS / 1000 + ahead >= 1) then screen.hook() end
  -- only in a death, from 5 s in (the screen fades in at 7)
  if screen.n % 15 ~= 0 or not active or saved.manual or polls * POLL_MS / 1000 + ahead < 5 then return end
  -- gone only once this probe saw it up (the hook saying it came up while the visibility read no screen got her up
  -- the moment it showed, playtest); while the hook says it is up, what the widget reads is logged
  local on = death_screen()
  if not on then
    if screen.vis and not screen.frozen then
      if screen.last then log("death screen: gone"); screen.last = nil end
      screen.gone = true
    end
    if not (screen.seen and valid(dead_hud.w)) then return end
  else
    screen.vis, screen.seen = true, true
  end
  local w = dead_hud.w
  local function f(x) return x and string.format("%.2f", x) or "?" end
  local parts = { string.format("%s: widget vis %s visible %s in viewport %s opacity %s", on and "up" or "hooked up, reads hidden",
    tostring(try(function() return w:GetVisibility() end)), tostring(try(function() return w:IsVisible() end)),
    tostring(try(function() return w:IsInViewport() end)), f(try(function() return w:GetRenderOpacity() end))) }
  for _, name in ipairs({ "CanvasPanel_Dead", "black", "FadeOut", "BackgroundBlur_116", "Root" }) do
    local c = try(function() return w:GetWidgetFromName(FName(name)) end)
    if valid(c) then
      local vis = try(function() return c:GetVisibility() end)
      local a = try(function() return c.ColorAndOpacity.A end)
      local blur = try(function() return c.BlurStrength end)
      parts[#parts + 1] = string.format("%s vis %s opacity %s%s%s", name, tostring(vis), f(try(function() return c:GetRenderOpacity() end)),
        a and (" alpha " .. f(a)) or "", blur and (" blur " .. f(blur)) or "")
    else parts[#parts + 1] = name .. " none" end
  end
  local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
  local pcm = try(function() return gs:GetPlayerCameraManager(pawn, 0) end)
  if valid(pcm) then
    local fc = try(function() return pcm.FadeColor end)
    parts[#parts + 1] = string.format("camera fade %s amount %s colour %s, view target %s",
      tostring(try(function() return pcm.bEnableFading end)), f(try(function() return pcm.FadeAmount end)),
      fc and string.format("%.2f %.2f %.2f", fc.R, fc.G, fc.B) or "?",
      tostring(try(function() return pcm.ViewTarget.Target:GetFName():ToString() end)))
  end
  local sig = table.concat(parts, "; ")
  if sig ~= screen.last then
    screen.last = sig
    log(string.format("death screen (%.1f s into the death): %s", polls * POLL_MS / 1000 + ahead, sig))
  end
end

local function on_start(pawn, mesh)
  log("ragdoll state at start: " .. ragdoll_state(pawn))
  screen.reset()
  -- her voice for any death: a cry as she dies, nothing after (gore.lua, tune.gore.voice)
  if gore then try(function() gore.voice_death(pawn, mesh) end) end
  if goreCtx.convulse then try(function() goreCtx.convulse.start(pawn, mesh) end) end
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
  -- her arms against her chest (physfix.arm_collision: the collision table leaves those pairs out): the mesh blocks
  -- its own bodies' channel then. Switched off and on, so the engine filters her body pairs again by the new table
  -- (her bodies were already simulating as it was written)
  goreCtx.arm_pairs = nil
  local arms, armsWhy = {}, nil
  if not selfCol and physfix then
    local ok, p, w = pcall(physfix.arm_collision, mesh, paObj)
    if ok then arms, armsWhy = p or {}, w else armsWhy = tostring(p) end
  end
  if not selfCol then
    try(function() mesh:SetCollisionResponseToChannel(CH.PhysicsBody, IGNORE) end)
    if #arms > 0 then
      try(function() mesh:SetCollisionResponseToChannel(CH.PhysicsBody, BLOCK) end)
      goreCtx.arm_pairs = arms
    end
  end
  if armsWhy then log("arms: " .. armsWhy) end
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

-- where the mesh belongs on the capsule: an offset from it (the gameplay one, rel, by default) turned with its yaw
function rel.target(cap, loc, rot)
  loc, rot = loc or rel.loc, rot or rel.rot
  local cl = cap:K2_GetComponentLocation()
  local cr = cap:K2_GetComponentRotation()
  local yaw = math.rad(cr.Yaw)
  return { X = cl.X + loc.X * math.cos(yaw) - loc.Y * math.sin(yaw),
           Y = cl.Y + loc.X * math.sin(yaw) + loc.Y * math.cos(yaw), Z = cl.Z + loc.Z },
    { Pitch = rot.Pitch, Yaw = cr.Yaw + rot.Yaw, Roll = rot.Roll }
end

-- put the mesh back into normal animated gameplay state
local function recover(pawn, mesh, why)
  local cap = try(function() return pawn.CapsuleComponent end)
  -- the muscle tone's drives hold the current bodies, which gore's cleanup recreates: release them first
  if rag then try(function() rag.stop(pawn) end) end
  if gore then try(function() gore.cleanup(pawn, mesh) end) end
  if physfix then try(function() physfix.stop() end) end
  local steps = { "unlock(" .. unlock(pawn, mesh) .. ")" }
  -- the game's own ragdoll count stays 1 after a real death till its respawn (NotifyBP_ReInitActor) clears it; the
  -- revive item's "revive here" never respawns her, so she stayed ragdolled to the game: stuck to the floor, and her
  -- next death's ragdoll key did nothing (a vanilla death, playtest). Cleared here as the respawn does
  local ri = try(function() return pawn.RagdollInfo end)
  if ri and (try(function() return ri.EnableRagdollCount end) or 0) ~= 0 then
    local ok = try(function()
      ri.EnableRagdollCount = 0
      ri.CurrentActiveTime = 0.0
      ri.BlendWeight = 0.0
      return true
    end)
    steps[#steps + 1] = "ragdollCount" .. (ok and "" or "!")
  end
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
    local wl, wr = rel.target(cap)
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

-- Nexus report (0.2.4, revive here): she walked in jumps and stood on air after a jump. The capsule moved, the mesh
-- stayed where it was and was only put back by recover() once 250 cm off it: the game's block on the capsule moving
-- the mesh (unpin) or its lockup (unlock) came back or never cleared on that setup. While she is up after a death the
-- mesh is checked every tick against where its own relative offset puts it on the capsule (so whatever offset the
-- game gives it is kept): more than pin.SLACK cm off, it is not following, so it is unpinned and unlocked again (every
-- pin.RETRY polls) and put there itself meanwhile, so she moves smoothly either way. The log says it once per death
-- (then every 300 such ticks) with the answers
rel.pin = { n = 0, at = -100, told = false, SLACK = 15, RETRY = 30 }
function rel.follow(pawn, mesh)
  local pinned = rel.pin
  local cap = try(function() return pawn.CapsuleComponent end)
  -- off the capsule altogether is recover()'s (attached_to_capsule)
  local parent = try(function() return mesh:GetAttachParent() end)
  if not (valid(cap) and valid(parent) and parent:GetAddress() == cap:GetAddress()) then return end
  local t = try(function()
    local l, r = mesh.RelativeLocation, mesh.RelativeRotation
    return { rel.target(cap, { X = l.X, Y = l.Y, Z = l.Z }, { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll }) }
  end)
  if not t then return end
  local wl, wr = t[1], t[2]
  local d = dist(try(function() return mesh:K2_GetComponentLocation() end), wl)
  if d < 0 or d <= pinned.SLACK then return end
  pinned.n = pinned.n + 1
  local r
  if after - pinned.at >= pinned.RETRY then
    pinned.at = after
    -- the lockup (unlock) holds the mesh as well: set again, it is cleared again
    local lk = try(function() return mesh.bLockupSimulatePhysics or pawn.bLockupSimulatePhysics end)
    r = (lk and "unlock(" .. unlock(pawn, mesh) .. ") " or "") .. "unpin(" .. reattach_transform(mesh) .. ")"
  end
  local ok = try(function() mesh:K2_SetWorldLocationAndRotation(wl, wr, false, {}, true); return true end)
  if r and (not pinned.told or pinned.n % 300 == 1) then
    pinned.told = true
    log(string.format("mesh left behind by the capsule (%.0f cm, a%d, %d ticks so far): %s, put back%s",
      d, after, pinned.n, r, ok and "" or " (failed)"))
  end
end

local lastRecover = -100
local function watch(pawn, mesh)
  local cap = try(function() return pawn.CapsuleComponent end)
  local cloc = cap and try(function() return cap:K2_GetComponentLocation() end)
  local mloc = try(function() return mesh:K2_GetComponentLocation() end)
  local ploc = try(function() return mesh:GetSocketLocation(FName("Bip001-Pelvis")) end)
  log(string.format("a%03d parent=%s capsule%s mesh%s pelvis%s pelvisGap=%.0f visible=%s hidden=%s sim=%s meshLockup=%s move=%s",
    after, name(try(function() return mesh:GetAttachParent() end)), v3(cloc), v3(mloc), v3(ploc), dist(ploc, cloc),
    tostring(try(function() return mesh:IsVisible() end)), tostring(try(function() return pawn.bHidden end)),
    tostring(try(function() return mesh:IsSimulatingPhysics(FName("None")) end)),
    tostring(try(function() return mesh.bLockupSimulatePhysics end)),
    tostring(try(function() return pawn.CharacterMovement.MovementMode end))))
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
  -- a real death's respawn loads the level next: nothing from the pak meanwhile (goreCtx.may_load)
  if not saved.manual then goreCtx.quietUntil = os.clock() + 15 end
  after, lastRecover, respawned, screen.stuck.at = 0, -100, false, nil
  rel.pin.n, rel.pin.at, rel.pin.told = 0, -100, false
  camera_unfollow()
  capsule_report()
  screen.allow_photo(false, "she got up")
  screen.photoOn = false
  camera_release(pawn)
  skip_stop("she got up")
  dface.stop()
  if goreCtx.convulse then try(function() goreCtx.convulse.stop() end) end
  try(function() mesh:SetCollisionResponseToChannel(CH.PhysicsBody, saved.meshPB or BLOCK) end)
  try(function() goreCtx.reset_pairs(mesh) end)
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
  -- a test ragdoll lies there until F8 (recoverAfter is for deaths)
  saved.manual = true
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
  local k = cls and goreCtx.keep(o)
  if k then chars[ad] = { obj = o, cls = cls, k = k } end
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
    if goreCtx.held(e.k) then
      out[#out + 1] = { obj = e.obj, addr = ad, cls = e.cls, k = e.k }
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

-- the killing swing's helpers (one local: this chunk is near Lua's 200): the enemies followed, nearest first (list),
-- when they are looked over again (next)
local sw = { list = {}, next = 0 }
-- the enemies within reach of her, nearest first (at most `most`)
function sw.near(mesh, within, most)
  local me = pawnAddr
  local at = try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Spine1"))) end)
  if not at then return {} end
  local reach = within or (tune.gore or {}).attackerReach or 800
  local out = {}
  for _, e in ipairs(live_chars()) do
    local a = e.obj
    if e.addr ~= me and not ignored(e.cls) and try(function() return a.bActorIsBeingDestroyed end) == false
      and try(function() return a.bHidden end) ~= true then
      local l = try(function() return vof(a:K2_GetActorLocation()) end)
      local d = dist(l, at)
      if l and d >= 0 and d < reach then out[#out + 1] = { actor = a, loc = l, d = d, cls = e.cls, addr = e.addr, k = e.k } end
    end
  end
  table.sort(out, function(x, y) return x.d < y.d end)
  while #out > (most or #out) do table.remove(out) end
  return out, at
end
-- the nearest other character within tune.gore.attackerReach of her: who most likely killed her
local function attacker(pawn, mesh, within)
  local list, at = sw.near(mesh, within, 1)
  local best = list[1]
  if not best then return nil end
  best.name = name(best.actor)
  local fl = try(function() return vof(best.actor:GetActorForwardVector()) end)
  local push = { X = at.X - best.loc.X, Y = at.Y - best.loc.Y, Z = 0 }
  if len(push) < 1 and fl then push = { X = fl.X, Y = fl.Y, Z = 0 } end
  best.push = push
  -- how fast it comes down (a stomp, a leap onto her)
  best.vz = try(function() return best.actor:GetVelocity().Z end)
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
-- (several are followed, the nearest swingFollow, each with its own trail: following only the nearest, its trail
-- started over each time another came nearer, and among a pack of them the killing swing went unseen, playtest)
function sw.state() return { addr = nil, actor = nil, mesh = nil, bones = nil, who = nil, hist = {} } end
local swing = sw.state() -- the nearest one followed, or the one whose blade made the killing blow (weapon_swing)
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
-- its weapon meshes (the weapon slots of its MeshInfoList, as hers): each one's long axis, from its mesh's imported
-- bounds in the component's space, is the blade. Its two ends are sampled with the bones, and the plane the blade
-- sweeps (the blade line and the way it moved) is the cut's: the fastest bone was a grip socket, maybe the empty
-- hand, and its arc ran parallel to her 38 cm off her spine where the blade went through her (playtest 42)
local SWING_WEAPON_SLOTS = { [5] = true, [6] = true, [7] = true, [8] = true }
local function swing_weapons(actor)
  local out = {}
  try(function()
    actor.MeshInfoList:ForEach(function(_, e)
      local info = e:get()
      local c = info.MeshComponent
      if SWING_WEAPON_SLOTS[info.MeshSlot] and valid(c) then
        local b = try(function() local x = c.SkeletalMesh:GetImportedBounds(); return { o = vof(x.Origin), e = vof(x.BoxExtent) } end)
          or try(function() local x = c.StaticMesh:GetBounds(); return { o = vof(x.Origin), e = vof(x.BoxExtent) } end)
        if b and b.o and b.e then
          local ax = b.e.X >= b.e.Y and b.e.X >= b.e.Z and { X = b.e.X, Y = 0, Z = 0 }
            or b.e.Y >= b.e.Z and { X = 0, Y = b.e.Y, Z = 0 } or { X = 0, Y = 0, Z = b.e.Z }
          local nm = try(function() return (c.SkeletalMesh or c.StaticMesh):GetName() end)
            or try(function() return c:GetName() end) or "weapon"
          local sock = try(function() return c:GetAttachSocketName():ToString() end) or "?"
          out[#out + 1] = { comp = c, k = goreCtx.keep(c), o = b.o, ax = ax, name = nm, socket = sock, cm = 2 * len(ax) }
        end
      end
    end)
  end)
  return out
end
-- a point given in a component's space, in the world
local function comp_point(c, p)
  return try(function()
    local wl, f, r, u = c:K2_GetComponentLocation(), c:GetForwardVector(), c:GetRightVector(), c:GetUpVector()
    return { X = wl.X + f.X * p.X + r.X * p.Y + u.X * p.Z, Y = wl.Y + f.Y * p.X + r.Y * p.Y + u.Y * p.Z,
      Z = wl.Z + f.Z * p.X + r.Z * p.Y + u.Z * p.Z }
  end)
end
function sw.drop() swing, sw.list = sw.state(), {} end
local function track_swing(pawn, mesh)
  local g = tune.gore or {}
  if g.weaponSwing == false then return end
  local t0, now = os.clock(), os.clock()
  if now >= sw.next then
    sw.next = now + (g.swingRefresh or 0.25)
    local had = {}
    for _, S in ipairs(sw.list) do had[S.addr] = S end
    local list = {}
    for _, a in ipairs((sw.near(mesh, g.swingReach or 500, g.swingFollow or 3))) do
      local S = had[a.addr]
      if not S then
        local m = try(function() return a.actor.Mesh end)
        if valid(m) and a.cls then
          S = sw.state()
          S.addr, S.actor, S.mesh, S.who, S.k = a.addr, a.actor, m, name(a.actor), a.k
          S.bones = swing_bones(m, a.cls)
          S.weapons = swing_weapons(a.actor)
          local ws = {}
          for _, w in ipairs(S.weapons) do ws[#ws + 1] = string.format("%s %.0f cm on %s", w.name, w.cm, w.socket) end
          log(string.format("swing: %s holds %s", a.cls, #ws > 0 and table.concat(ws, ", ") or "no weapon mesh"))
        end
      end
      if S then list[#list + 1] = S end
    end
    sw.list = list
    swing = sw.list[1] or sw.state()
  end
  -- her pose with them, while she is alive: a killing blow is judged on her body as the weapon met it (gore.blow), not
  -- as the death show has moved it by the time the death starts (an arm raised to block had swung away)
  local pose
  if not active and gore and g.blowPose ~= false and #sw.list > 0 then pose = gore.pose(mesh) end
  local keep = g.swingWindow or 0.6
  for i = #sw.list, 1, -1 do
    local S = sw.list[i]
    if not goreCtx.held(S.k) or try(function() return S.actor.bActorIsBeingDestroyed end) ~= false then
      table.remove(sw.list, i)
      if swing == S then swing = sw.list[1] or sw.state() end
    elseif (S.bones and #S.bones > 0) or (S.weapons and #S.weapons > 0) then
      local s = { t = now, p = {}, w = {}, pose = pose }
      for k, b in ipairs(S.bones or {}) do s.p[k] = try(function() return vof(S.mesh:GetSocketLocation(FName(b))) end) end
      for k, w in ipairs(S.weapons or {}) do
        if goreCtx.held(w.k) then
          local a = comp_point(w.comp, { X = w.o.X - w.ax.X, Y = w.o.Y - w.ax.Y, Z = w.o.Z - w.ax.Z })
          local b = comp_point(w.comp, { X = w.o.X + w.ax.X, Y = w.o.Y + w.ax.Y, Z = w.o.Z + w.ax.Z })
          if a and b then s.w[k] = { a = a, b = b } end
        end
      end
      local h = S.hist
      h[#h + 1] = s
      while #h > 0 and now - h[1].t > keep do table.remove(h, 1) end
    end
  end
  local ms = (os.clock() - t0) * 1000
  if ms >= (g.slowMs or 15) then log(string.format("swing: following %d enemies took %.0f ms", #sw.list, ms)) end
end
-- the swing that killed her, if the weapon moved fast enough: { dir, n, at (the weapon there), speed, bone, fwd }
function sw.of(swing, mesh)
  local g = tune.gore or {}
  local h = swing.hist
  -- an old trail (the enemy gone, or a death that started without it) is no swing
  if #h < 3 or os.clock() - h[#h].t > (g.swingWindow or 0.6) or not goreCtx.held(swing.k) then return nil end
  local fwd = try(function() return vof(swing.actor:GetActorForwardVector()) end)
  -- a weapon mesh's blade: the step (fast enough) whose sweep went through her, the plane through the blade line along
  -- its motion. The fastest step alone was the pull-back after a blocked blow: its plane passed 52 cm beside her, was
  -- moved onto her calf and took a leg, the arms raised in front and the body untouched (playtest). Each step's blade
  -- is swept over spots of its motion (every ~15 cm) against her parts (SWING_AT, where they were with that sample: s.pose);
  -- the nearest wins, a fast one a little ahead (up to swingSpeedPull cm), one moving away from that part well behind
  -- the nearest point of segment a-b to p, and how far
  local function seg_near(p, a, b)
    local ab = sub(b, a)
    local t = math.max(0, math.min(1, dot(sub(p, a), ab) / math.max(dot(ab, ab), 1e-4)))
    local x = { X = a.X + ab.X * t, Y = a.Y + ab.Y * t, Z = a.Z + ab.Z * t }
    return x, dist(p, x)
  end
  local parts_now
  local function parts(s)
    local P = s.pose
    if not P and not parts_now then
      parts_now = {}
      for _, x in ipairs(SWING_AT) do
        parts_now[x[1]] = try(function() return vof(mesh:GetSocketLocation(FName(x[1]))) end)
        if x[3] then parts_now[x[3]] = try(function() return vof(mesh:GetSocketLocation(FName(x[3]))) end) end
      end
    end
    local function at(b) local p = P and P[b]; return p and p.t or (parts_now and parts_now[b]) end
    local out = {}
    for _, x in ipairs(SWING_AT) do
      local a = at(x[1])
      local b = x[3] and at(x[3])
      if a then out[#out + 1] = { b and { X = a.X + 0.4 * (b.X - a.X), Y = a.Y + 0.4 * (b.Y - a.Y), Z = a.Z + 0.4 * (b.Z - a.Z) } or a, x[1] } end
    end
    return out
  end
  local bw, second, fastest, steps, closest = nil, nil, nil, 0, nil
  local minv, pull, full, now = g.swingMinSpeed or 300, g.swingSpeedPull or 30, g.swingSpeedFull or 9000, os.clock()
  for i = 2, #h do
    local dt = h[i].t - h[i - 1].t
    if dt > 1e-3 and h[i].w and h[i - 1].w then
      for k, e in pairs(h[i].w) do
        local o = h[i - 1].w[k]
        if o then
          local v = math.max(dist(o.a, e.a), dist(o.b, e.b)) / dt
          if not fastest or v > fastest then fastest = v end
          if v >= minv and mesh then
            steps = steps + 1
            local near, nd, np, part
            -- (spots every ~15 cm of the blade's motion: three spots of a 190 cm step at 11000 cm/s left 59 cm between
            -- the blade and her calf it went through, playtest)
            local cuts = math.max(2, math.min(12, math.ceil(v * dt / 15)))
            for _, pt in ipairs(parts(h[i])) do
              for j = 0, cuts do
                local f = j / cuts
                local a = { X = o.a.X + (e.a.X - o.a.X) * f, Y = o.a.Y + (e.a.Y - o.a.Y) * f, Z = o.a.Z + (e.a.Z - o.a.Z) * f }
                local b = { X = o.b.X + (e.b.X - o.b.X) * f, Y = o.b.Y + (e.b.Y - o.b.Y) * f, Z = o.b.Z + (e.b.Z - o.b.Z) * f }
                local x, d = seg_near(pt[1], a, b)
                if not nd or d < nd then near, nd, np, part = x, d, pt[1], pt[2] end
              end
            end
            if nd then
              -- (from where the blade started the step: one that went through the part had it ahead)
              local s0 = seg_near(np, o.a, o.b)
              local away = dot(sub((seg_near(np, e.a, e.b)), s0), sub(np, s0)) < 0
              -- (an older step costs more: a slow 2662 cm/s brush past her calf 0.27 s before the death beat the
              -- 9825 cm/s slash across her body after it and took one leg, playtest)
              local sc = nd - pull * math.min(1, v / full) + (away and (g.swingAwayCost or 60) or 0)
                + (g.swingAgeCost or 60) * (now - h[i].t)
              if not closest or nd < closest then closest = nd end
              local c = { speed = v, i = i, k = k, sc = sc, d = nd, at = near, part = part, away = away }
              if not bw or sc < bw.sc then
                if bw and bw.part ~= part then second = bw end
                bw = c
              elseif bw.part ~= part and (not second or sc < second.sc) then second = c end
            end
          elseif v >= minv and (not bw or v > bw.speed) then
            bw = { speed = v, i = i, k = k }
          end
        end
      end
    end
  end
  -- a blade that never came near her (its nearest step swept swingMiss cm off every part of her) didn't make the
  -- blow: its plane, put through her, took a standing Eve's shin with a 433 cm weapon 59 cm off her (playtest). The
  -- death goes on with a made-up blow (the weapon's bones would only miss her wider)
  if closest and closest > (g.swingMiss or 45) then
    log(string.format("swing: %d fast steps of %s's blade, the nearest %.0f cm from her: it missed her, not its plane",
      steps, tostring(swing.who), closest))
    return nil
  end
  if bw and bw.speed >= minv then
    local e, o = h[bw.i].w[bw.k], h[bw.i - 1].w[bw.k]
    local m1 = bw.at or { X = (e.a.X + e.b.X) / 2, Y = (e.a.Y + e.b.Y) / 2, Z = (e.a.Z + e.b.Z) / 2 }
    if bw.d then
      log(string.format("swing: step %.2f s before of %d fast ones, its blade %.0f cm from her %s%s at %.0f cm/s (fastest %.0f)",
        os.clock() - h[bw.i].t, steps, bw.d, tostring(bw.part), bw.away and ", moving away from it" or "", bw.speed, fastest or 0)
        .. (second and string.format("; next best %.2f s before, %.0f cm from her %s at %.0f cm/s", os.clock() - h[second.i].t,
          second.d, tostring(second.part), second.speed) or ""))
    end
    -- the faster end's motion (a blade turning about its grip: the tip's), the midpoint's when it barely moved
    local ta, tb = sub(e.a, o.a), sub(e.b, o.b)
    local dir = unit(len(tb) >= len(ta) and tb or ta)
    local blade = unit(sub(e.b, e.a))
    local c = dir and blade and cross(blade, dir)
    -- (a thrust runs along the blade: no plane from it)
    if c and len(c) > 0.3 then
      local w = swing.weapons[bw.k]
      return { dir = dir, n = unit(c), how = "blade " .. (w and w.name or "weapon"), at = m1, speed = bw.speed,
        bone = w and (w.name .. " on " .. w.socket) or "weapon", fwd = fwd, ago = os.clock() - h[bw.i].t, pose = h[bw.i].pose,
        part = bw.part, part_d = bw.d }
    end
  end
  if not swing.bones or #swing.bones == 0 then return nil end
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
    ago = os.clock() - h[i].t, pose = h[i].pose }
end

-- the killing swing among the enemies followed: the blade that swept nearest her (its weapon meshes), else the
-- fastest weapon bone. It becomes `swing` (who, its trail, the poses noted with it) for the death
local function weapon_swing(mesh)
  local best, bs, sc
  for _, S in ipairs(sw.list) do
    local ws = sw.of(S, mesh)
    local x = ws and (ws.part_d or (1e6 - (ws.speed or 0)))
    if x and (not sc or x < sc) then best, bs, sc = ws, S, x end
  end
  if bs then
    if #sw.list > 1 then
      log(string.format("swing: %d enemies followed, the blow is %s's%s", #sw.list, tostring(bs.who),
        best.part_d and string.format(" (its blade %.0f cm from her)", best.part_d) or ""))
    end
    swing = bs
  end
  return best
end
-- the killing blow: the game's skill hit when it came (swing and forward), else a blade made up around where it came
-- from (her mesh's last hit, else the nearest enemy): pushed from there, swung level, slanted or down across it,
-- through where the mesh says she was hit or a part of her (swing_at)
local function death_hit(pawn, mesh)
  local g = tune.gore or {}
  -- her pose noted with the swing sample nearest time t (within 0.1 s), and how long ago that was
  local function pose_at(t)
    local best
    for _, x in ipairs(swing.hist) do
      if x.pose and (not best or math.abs(x.t - t) < math.abs(best.t - t)) then best = x end
    end
    if best and math.abs(best.t - t) < 0.1 then return best.pose, os.clock() - best.t end
  end
  local h = last_hit(g.hitWindow or 0.6)
  if h and h.dir and h.fwd then
    h.push = h.push or h.fwd
    h.pose, h.pose_ago = pose_at(h.t)
    return h
  end
  local m = meshHit and os.clock() - meshHit.t <= (g.meshHitWindow or 1.0) and meshHit or nil
  local a = attacker(pawn, mesh)
  local push = (m and m.push) or (a and a.push)
  local ws = weapon_swing(mesh)
  if ws then
    -- where the swept plane crosses her: the mesh's hit, else the part of her nearest it and the weapon
    local loc, bone, off = m and m.loc, m and m.bone, nil
    -- a blow from above (a stomp, a slam, an overhead chop) lands on her body or her neck and cuts down through it,
    -- the plane moved onto the part: a stomp 17 cm off her calf took the shin alone, and one 59 cm off her spine
    -- took a thigh, the plane was never moved (playtest). Which part is rolled, the near ones likelier: a stomp's
    -- weapon is its feet, the plane says little about where they landed
    local down = ws.dir and ws.dir.Z < -(g.splitDown or 0.6)
    if not loc then
      local bd, pool, sum = nil, {}, 0
      for _, e in ipairs(SWING_AT) do
        local l = (not down or not e[3]) and try(function()
          -- (where the part was as the weapon swept, ws.pose)
          local function at(b) local p = ws.pose and ws.pose[b]; return p and p.t or mesh:GetSocketLocation(FName(b)) end
          local x = at(e[1])
          if not e[3] then return vof(x) end
          local y = at(e[3])
          return { X = x.X + 0.4 * (y.X - x.X), Y = x.Y + 0.4 * (y.Y - x.Y), Z = x.Z + 0.4 * (y.Z - x.Z) }
        end)
        if l then
          local d = math.abs(dot(sub(l, ws.at), ws.n))
          -- near the plane first, then near the weapon, a little toward the parts a blow most likely lands on
          local sc = d + 0.3 * dist(l, ws.at) - e[2]
          -- the part the blade's sweep went through (or came nearest) is the hit: a tilted plane through her blocking
          -- forearm passed 5 cm from her thigh, which won on the plane alone, and the swing across her arms and chest
          -- took both legs and her waist (playtest)
          if ws.part and e[1] == ws.part and (ws.part_d or 0) <= (g.swingMiss or 45) then sc = sc - 1000 end
          if not bd or sc < bd then bd, loc, bone, off = sc, l, e[1], d end
          if down then
            local w = e[2] / (1 + d / 30)
            pool[#pool + 1] = { l = l, bone = e[1], d = d, w = w }
            sum = sum + w
          end
        end
      end
      if down and sum > 0 then
        local r = math.random() * sum
        for _, x in ipairs(pool) do
          r = r - x.w
          if r <= 0 then loc, bone, off = x.l, x.bone, x.d; break end
        end
      end
      -- on the plane when it passes that close (the point put on it); else the plane is moved onto her, keeping its
      -- angle (the point stays on her part, the plane goes through it)
      if loc and not down and off <= (g.swingSnap or 30) then
        local k = dot(sub(loc, ws.at), ws.n)
        loc = { X = loc.X - k * ws.n.X, Y = loc.Y - k * ws.n.Y, Z = loc.Z - k * ws.n.Z }
      end
    end
    if loc then
      log(string.format("death: swing of %s's %s at %.0f cm/s %.2f s before, %s %s, %.0f deg down, at %s (%s%s)",
        tostring(swing.who), ws.bone, ws.speed, ws.ago, ws.how, v3({ X = ws.n.X * 100, Y = ws.n.Y * 100, Z = ws.n.Z * 100 }),
        math.deg(math.asin(math.max(-1, math.min(1, -ws.dir.Z)))), v3(loc), m and "where the mesh was hit" or tostring(bone),
        off and string.format(", plane %.0f cm off it%s", off, down and ", from above: moved onto it"
          or off > (g.swingSnap or 30) and ", moved onto her" or "") or ""))
      return { t = os.clock(), loc = loc, dir = ws.dir, fwd = ws.fwd or ws.dir, n = ws.n, how = ws.how,
        push = push or ws.dir, attack_dir = 0, src = "weapon", group = h and h.group, show = h and h.show, bone = bone,
        attacker = swing.who, pose = ws.pose, pose_ago = ws.ago }
    end
  end
  if not push then return h end
  local fl = len({ X = push.X, Y = push.Y, Z = 0 })
  if fl < 1e-3 then return h end
  local fwd = { X = push.X / fl, Y = push.Y / fl, Z = 0 }
  local side = math.random() < 0.5 and -1 or 1
  local ang = math.rad(({ 0, 20, 45, 45, 70, 90 })[math.random(6)])
  -- came down on her (her mesh's hit pointing down, or the attacker dropping onto her: a stomp): straight down, never
  -- a level cut (playtest)
  local mp = m and m.push
  local above = (mp and len(mp) > 1e-3 and mp.Z / len(mp) < -(g.splitDown or 0.6) and "her mesh's hit points down")
    or (a and a.vz and a.vz < -(g.stompSpeed or 250) and string.format("%s coming down at %.0f cm/s", a.name, -a.vz))
  if above then ang = math.rad(90) end
  local dir = { X = -fwd.Y * side * math.cos(ang), Y = fwd.X * side * math.cos(ang), Z = -math.sin(ang) }
  local loc = m and m.loc
  local bone = m and m.bone
  if not loc then bone, loc = swing_at(mesh) end
  if not loc then return h end
  local from = (m and m.push and "her mesh's hit") or "the nearest enemy"
  log(string.format("death: blow from %s%s, %d deg down%s, at %s (%s)", from,
    a and string.format(" (nearest enemy %s, %.0f cm off, %.0f cm/s up)", a.name, a.d, a.vz or 0) or "",
    math.floor(math.deg(ang) + 0.5), above and (": " .. above) or "", v3(loc), m and "where the mesh was hit" or ("made up: " .. tostring(bone))))
  local pose, pose_ago
  if m then pose, pose_ago = pose_at(m.t) end
  return { t = os.clock(), loc = loc, dir = dir, fwd = fwd, push = push, attack_dir = 0, src = from, made = true,
    group = h and h.group, show = h and h.show, bone = bone, attacker = a and a.name, pose = pose, pose_ago = pose_ago }
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
  if not (gore and (swing.bones or swing.weapons)) or #hist < 2 or os.clock() - hist[#hist].t > 0.2 then return end
  local a, b = hist[#hist - 1], hist[#hist]
  local dt = b.t - a.t
  if dt < 1e-3 then return end
  local best
  for i = 1, #(swing.bones or {}) do
    local p, q = a.p[i], b.p[i]
    if p and q then
      local v = dist(p, q) / dt
      if not best or v > best.v then best = { v = v, i = i, p = p, q = q, name = swing.bones[i] } end
    end
  end
  -- a weapon mesh's blade (swing_weapons) goes before the bones: its steps are its two ends' and its middle's
  local bb
  for k, e in pairs(b.w or {}) do
    local o = a.w and a.w[k]
    if o then
      local v = math.max(dist(o.a, e.a), dist(o.b, e.b)) / dt
      if not bb or v > bb.v then
        local w = swing.weapons[k]
        local mid = function(x) return { X = (x.a.X + x.b.X) / 2, Y = (x.a.Y + x.b.Y) / 2, Z = (x.a.Z + x.b.Z) / 2 } end
        local far = dist(o.b, e.b) >= dist(o.a, e.a)
        bb = { v = v, p = far and o.b or o.a, q = far and e.b or e.a, name = w and w.name or "weapon",
          steps = { { o.a, e.a }, { mid(o), mid(e) }, { o.b, e.b } }, blade = unit(sub(e.b, e.a)) }
      end
    end
  end
  if bb and bb.v >= (g.swingMinSpeed or 300) then best = bb end
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
    for _, st in ipairs(l and best.steps or {}) do dd = math.min(dd, seg_dist(st[1], st[2], l)) end
    if dd and (not d or dd < d) then at, d, bone = l, dd, e[1] end
  end
  if not at or d > (c.reach or 35) then return end
  ah.armed, ah.n = false, ah.n + 1
  -- the plane: the arc through the last three samples, else the step and the enemy's forward
  local dir = unit(sub(best.q, best.p))
  local fwd = goreCtx.held(swing.k) and try(function() return vof(swing.actor:GetActorForwardVector()) end)
  local n, how
  local cb = best.blade and dir and cross(best.blade, dir)
  if cb and len(cb) > 0.3 then n, how = unit(cb), "blade " .. best.name end
  local pa = not n and best.i and hist[#hist - 2] and hist[#hist - 2].p[best.i]
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
    os.clock() - ah.t0, tostring(swing.who), best.name, best.v, d, bone, ah.n, c.max or 6,
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

-- the killing blow shown at once (tune.gore.woundAtHit): her HP bar read every tick while she lives (a widget already
-- found: a property read); the tick it reaches 0, gore.wound marks where the blade met her. The death itself is only
-- seen at the death show's ragdoll key, 0.2-0.5 s later (playtest); the death logs how long after this it came
hm.lethal = nil
-- her guard, read every tick while she lives: the game keeps it native (no property or function shows it, and her
-- stance read P_Eve_Default all through a block, playtest), so it is the guard key held (her controller's action
-- mappings named Guard or Block, read once; tune's guardKeys, E and L1, when none are), a montage of hers named Guard or
-- Block, or a block stance (ASBCharacter.GetCurrentStanceName: P_Eve_BlockSword, a ..._Guard1 skill). Noted with its
-- time; a killing blow within tune.active.weaponCut.blockWindow of it broke through her guard, and her sword breaks
-- (active.weapon_cut)
hm.stances = {}
function hm.guarding(s) return s and (s:find("Block", 1, true) or s:find("Guard", 1, true)) and s or nil end
function hm.guard_keys(pc)
  if hm.gkeys then return hm.gkeys end
  local keys, acts = {}, {}
  try(function()
    pc.PlayerInput.ActionMappings:ForEach(function(_, e)
      local m = e:get()
      local act, key = m.ActionName:ToString(), m.Key.KeyName:ToString()
      if hm.guarding(act) and not keys[key] then keys[key] = act; acts[#acts + 1] = act .. "=" .. key end
    end)
  end)
  -- (the game's own input reads none of them: tune.active.weaponCut.guardKeys, E and L1 by default)
  if #acts == 0 then
    for _, k in ipairs(((tune.active or {}).weaponCut or {}).guardKeys or { "E", "Gamepad_LeftShoulder" }) do
      keys[k] = "Guard (tune)"; acts[#acts + 1] = k
    end
    acts[1] = "none read, from tune: " .. acts[1]
  end
  hm.gkeys = {}
  for k, act in pairs(keys) do hm.gkeys[#hm.gkeys + 1] = { k = { KeyName = FName(k) }, label = act .. " (" .. k .. ")" } end
  log("guard: keys " .. table.concat(acts, ", "))
  return hm.gkeys
end
function hm.guard_watch(pawn, mesh)
  local st = try(function() return pawn:GetCurrentStanceName():ToString() end)
  if st then
    hm.stance = st
    if tune.dev and not hm.stances[st] then hm.stances[st] = true; log("stance: " .. st) end
  end
  local why = hm.guarding(st) and ("stance " .. st)
  if not why then
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local pc = valid(gs) and try(function() return gs:GetPlayerController(pawn, 0) end)
    if valid(pc) then
      for _, g in ipairs(hm.guard_keys(pc)) do
        if try(function() return pc:IsInputKeyDown(g.k) end) == true then why = "key " .. g.label; break end
      end
    end
  end
  if not why then
    local ai = valid(mesh) and try(function() return mesh:GetAnimInstance() end)
    local mont = valid(ai) and try(function() return ai:GetCurrentActiveMontage() end)
    local mn = valid(mont) and try(function() return mont:GetFName():ToString() end)
    why = hm.guarding(mn) and ("montage " .. mn)
  end
  if why then
    if tune.dev and hm.guardWhy ~= why then log("guard: up (" .. why .. ")") end
    hm.guardT, hm.guardStance = os.clock(), why
  end
  hm.guardWhy = why
end
-- the block stance she held within the window before time t (now), else nil
function hm.blocking(t)
  local w = ((tune.active or {}).weaponCut or {}).blockWindow or 0.5
  if hm.guardT and (t or os.clock()) - hm.guardT <= w then return hm.guardStance end
end
function hm.lethal_watch(pawn, mesh)
  local g = tune.gore or {}
  if not gore or g.enabled == false or g.woundAtHit == false or not goreCtx.glass then return end
  local pct = goreCtx.glass.bar_pct(true)
  -- (the HUD looked for, 35 ms, at most every 30 s till it is found: it is kept after that)
  if not pct and os.clock() >= (hm.barTry or 0) then
    hm.barTry = os.clock() + 30
    pct = goreCtx.glass.bar_pct(false)
  end
  if not pct then return end
  if pct ~= hm.barLast then hm.barLast, hm.barT = pct, os.clock() end
  if pct > 0.0005 then hm.lethal = nil; hm.armed = true; return end
  -- only a bar seen above 0 while she lived and now at 0: right after a respawn it still reads 0, and the watch cut
  -- her there (playtest)
  if hm.lethal or not hm.armed then return end
  hm.armed = false
  hm.lethal = { t = os.clock() }
  gore.blocking = hm.blocking()
  local ws = weapon_swing(mesh)
  local m = meshHit and os.clock() - meshHit.t <= 0.5 and meshHit or nil
  local at = ws and ws.at or (m and m.loc)
  if ws and ws.part and ws.pose and ws.pose[ws.part] then at = ws.pose[ws.part].t or at end
  hm.lethal.at = at
  if at then gore.wound(pawn, mesh, at) end
  log(string.format("lethal hit: her HP bar at 0, the wound %s", at and ("at " .. v3(at) .. (ws and ws.part and (" (" .. ws.part .. ")") or "")) or "nowhere (no blade seen)"))
  -- a limb, the head or her body the blade took is cut now, on her animated body (gore.blow's h.early), and opens
  -- over openTime; a split waits for the death, and so do the blow's further cuts (gore.release_held at the death)
  if g.cutAtHit == false or g.sliceOnDeath == false then return end
  local h = death_hit(pawn, mesh)
  if not (h and not h.made and (h.n or (h.dir and h.fwd))) then return end
  h.early = true
  local fly = h.push or h.dir
  if fly then gore.aim(fly) end
  local ok, err = pcall(gore.blow, pawn, mesh, h, "death")
  if ok and err then hm.lethal.cut, hm.lethal.h = true, h
  elseif not ok then log("lethal hit: early cut failed: " .. tostring(err)) end
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
  -- cut on a ragdoll, she stays down until F8 (as a cut on a standing Eve stays)
  if active then saved.manual = true end
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
  if not valid(show) and LoadAsset and goreCtx.may_load() then show = try(function() return LoadAsset(path) end) end
  if not valid(show) then show = try(function() return StaticFindObject(path) end) end
  if not valid(show) and LoadAsset and goreCtx.may_load() then
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
  -- cut at the hit already (hm.lethal_watch): the blow's further cuts and her sword's now
  if hm.lethal and hm.lethal.cut and os.clock() - hm.lethal.t < 5 then
    hm.lethal.cut = nil
    log(string.format("death: the killing cut was made at the hit, %d more of the blow now", gore.release_held()))
    return
  end
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
    -- a killing blow the game told us about cuts along the blade (gore.blow), else the roll below. A made-up one (no
    -- skill hit, no weapon swing seen: a guessed plane through a guessed part of her, most of the time her spine) is
    -- rolled: cut along, it took her body at most deaths, the legs almost never (playtest)
    if h and h.made then
      log(string.format("death: no blade seen (blow from %s), rolling the odds", tostring(h.src)))
    elseif h then
      log(string.format("death: last hit %.2f s ago (hook called %d times, %d on Eve), cutting along the blade",
        os.clock() - h.t, hitCalls, hitsOnEve))
      if gore.blow(pawn, mesh, h, "death") then return end
    end
    local normal = split_normal(h)
    -- a death always takes something off
    local kind = pick_kind(normal ~= nil)
    -- from above, the body is cut down through her, not across the waist (a stomp's level cut, playtest)
    if normal and kind == "torso" then
      log("death: rolled torso on a blow from above, split down her instead")
      kind = "split"
    end
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
  -- her guard at the blow (at the lethal hit when it was seen, else now)
  local lt = hm.lethal and os.clock() - hm.lethal.t < 5 and hm.lethal.t or nil
  gore.blocking = hm.blocking(lt)
  log(string.format("death: her stance at the blow %s%s", tostring(hm.stance), gore.blocking
    and string.format(", guard up (%s %.2f s before)", gore.blocking, (lt or os.clock()) - hm.guardT) or ""))
  gore_cut(pawn, mesh, h, hit)
  -- a blow through her guard breaks her sword, whatever cut it made (a split, a rolled one with no blade seen)
  if gore.blocking and rag and rag.weapon_cut and not rag.sword_split() then
    local at = (h and h.loc) or hit or try(function() return vof(mesh:GetSocketLocation(FName("Bip001-R-Hand"))) end)
    local n = (h and h.n) or (h and h.dir) or { X = 0, Y = 0, Z = 1 }
    if at then
      local ok, err = pcall(rag.weapon_cut, mesh, at, unit(n) or n, gore.blocking)
      if not ok then log("weapon cut: " .. tostring(err)) end
    end
  end
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
-- P in a death: the death keeps the key from photo mode, so sbslice.dll enters photo mode itself (its answer: the
-- manager and the gates the key's path checks, read before). A death not held yet is held first, as Shift+F4 does:
-- the death screen and getting up would come on over photo mode
function screen.photo_key(label)
  if not active or saved.manual or (camHeld and camHeld.photo) or not gore then return end
  if not screen.frozen then screen.hold(label) end
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  local r = gore.photo_open(mesh)
  log(label .. " in the held death, opening photo mode: " .. r)
  if r:find("entered 1", 1, true) then
    screen.photoOn, screen.photoNext, screen.photoSeen = true, 0, nil
    screen.photoHead = valid(mesh) and try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Head"))) end)
  end
end
RegisterKeyBind(Key.P, on_key("P", function() screen.photo_key("P") end))
-- and the controller's photo mode combo, which the death keeps from photo mode too and UE4SS's key binds can't see:
-- the game's PhotomodeTwoKey1 + PhotomodeTwoKey2 (D-pad left + R1 unless rebound), both down, polled each frame of a
-- death. Read from her controller's input mappings at each death's first look
function screen.pad_photo()
  if not active or saved.manual or (camHeld and camHeld.photo) or not gore then screen.padKeys, screen.padWas, screen.holdWas = nil, nil, nil; return end
  local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
  local pc = valid(gs) and cachedPawn and try(function() return gs:GetPlayerController(cachedPawn, 0) end)
  if not valid(pc) then return end
  if not screen.padKeys then
    local found = {}
    try(function()
      pc.PlayerInput.ActionMappings:ForEach(function(_, e)
        local m = e:get()
        local act = m.ActionName:ToString()
        local key = m.Key.KeyName:ToString()
        if (act == "PhotomodeTwoKey1" or act == "PhotomodeTwoKey2") and key:find("^Gamepad") and not found[act] then found[act] = key end
      end)
    end)
    local a, b = found.PhotomodeTwoKey1 or "Gamepad_DPad_Left", found.PhotomodeTwoKey2 or "Gamepad_RightShoulder"
    screen.padKeys = { { KeyName = FName(a) }, { KeyName = FName(b) }, label = a .. "+" .. b }
    log(string.format("photo mode on the controller in this death: %s%s", screen.padKeys.label,
      (found.PhotomodeTwoKey1 and found.PhotomodeTwoKey2) and "" or " (the game's defaults: its mappings weren't read)"))
  end
  local k = screen.padKeys
  local on = try(function() return pc:IsInputKeyDown(k[1]) and pc:IsInputKeyDown(k[2]) end) == true
  if on and not screen.padWas then screen.photo_key(k.label) end
  screen.padWas = on
  -- Shift+F4 on the controller (tune.holdPad, D-pad down + R1 unless set): both down holds the death or lets it go
  local hp = tune.holdPad
  if type(hp) ~= "table" or not hp[2] then screen.holdWas = nil; return end
  if not screen.holdKeys or screen.holdKeys.label ~= hp[1] .. "+" .. hp[2] then
    screen.holdKeys = { { KeyName = FName(hp[1]) }, { KeyName = FName(hp[2]) }, label = hp[1] .. "+" .. hp[2] }
  end
  local h = screen.holdKeys
  local hold = try(function() return pc:IsInputKeyDown(h[1]) and pc:IsInputKeyDown(h[2]) end) == true
  if hold and not screen.holdWas then screen.hold(h.label) end
  screen.holdWas = hold
end
-- Shift+F4 in a death: hold it, no death screen and no getting up till pressed again (the screen then comes back);
-- the game respawning her on its own still ends it
function screen.hold(why)
  screen.frozen = not screen.frozen
  screen.allow_photo(screen.frozen, why)
  log(string.format("%s: death %s %.1f s in", why, screen.frozen and "held, no death screen or getting up till Shift+F4 (or the pad combo) again" or "let go",
    polls * POLL_MS / 1000 + ahead))
end
RegisterKeyBind(Key.F4, { ModifierKey.SHIFT }, on_key("Shift+F4", function()
  if not active or saved.manual then log("Shift+F4: no death to hold"); return end
  screen.hold("Shift+F4")
end))
-- Esc on her death: fast forward to the death screen (tune.deathSkip; parked for now, untested)
-- RegisterKeyBind(Key.ESCAPE, on_key("Esc", function() if active then skip_start(find_eve()) end end))
-- Ultra Violence (Nexus 3942) has F9 (its menu), F10 and F11 too: with it on, these test keys are on Alt
do
local uv_on = (function()
  local f = io.open("ue4ss/Mods/UltraViolenceBlood/scripts/main.lua", "r")
  if not f then return false end
  f:close()
  local m = io.open("ue4ss/Mods/mods.txt", "r")
  local txt = m and m:read("*a") or ""
  if m then m:close() end
  return not txt:find("UltraViolenceBlood%s*:%s*0")
end)()
local function test_key(key, label, fn)
  if uv_on then RegisterKeyBind(key, { ModifierKey.ALT }, on_key("Alt+" .. label, fn, true))
  else RegisterKeyBind(key, on_key(label, fn, true)) end
end
screen.uv = uv_on
if uv_on then log("Ultra Violence is on: the test keys F9, F10 and F11 are Alt+F9, Alt+F10 and Alt+F11 (its menu, outfit blood and blood stages are on F9-F11)") end
test_key(Key.F9, "F9", sandbox_slice)
-- F10: a living hit's mark on a part at random, on its side facing the camera (tune.gore.hitMarks)
test_key(Key.F10, "F10", function()
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
end)
test_key(Key.F11, "F11", sandbox_split)
end
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
      if label == "NotifyBP_ReInitActor" and after >= 0 then respawned, after, lastRecover, screen.stuck.at = true, 0, -100, nil end
      -- the game respawning her while she is still down (its death screen's button never seen): got up at once, not
      -- broken and with her weapon on the floor for the 1-2 s till the fallback timer (playtest)
      if active and label == "NotifyBP_ReInitActor" then screen.respawn = true end
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
  -- a test ragdoll lies there until F8 (recoverAfter is for deaths)
  saved.manual = true
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
-- while photo mode is on (entered with P, or the game's key with a piece off her): it pauses the game but not this
-- script, whose gore and hits after death went on in wall-clock time; a hit cut her arm as it closed, on a mesh photo
-- mode had posed, and left 284 stretched triangles (playtest). So the tick stops here, but for this watch: every
-- 0.5 s photo mode's state (sbslice f3), and her ragdoll's (photo mode put a cut-off head back on her neck: the game's
-- lockup and pose snapshot, which freeze a mesh in its animated pose, are undone whenever they show up), logged when
-- it changes. Once it closes the enemy's weapon trail starts over (its jump over the pause read as a swing) and hits
-- after death wait photoGrace s
function screen.photo_watch(pawn, mesh)
  local now = os.clock()
  if now < screen.photoNext then return true end
  screen.photoNext = now + 0.5
  local st = gore.photo_state()
  local on = tonumber(st:match(" 84=(%-?%d+)"))
  local head = try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Head"))) end)
  local h0 = screen.photoHead
  local function b(f) local ok, r = pcall(f); return ok and tostring(r) or "?" end
  local seen = string.format("%s; mesh lockup %s, head sim %s, pelvis sim %s, collision %s", ragdoll_state(pawn),
    b(function() return mesh.bLockupSimulatePhysics end), b(function() return mesh:IsSimulatingPhysics(FName("Bip001-Head")) end),
    b(function() return mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end), b(function() return mesh:GetCollisionEnabled() end))
  if seen ~= screen.photoSeen then
    screen.photoSeen = seen
    log(string.format("photo mode %s: %s, head %s off where it was before; %s", on and on ~= 0 and "on" or "off", st,
      head and h0 and string.format("%.0f cm", dist(head, h0)) or "?", seen))
  end
  if on and on ~= 0 then
    local ri = try(function() return pawn.RagdollInfo end)
    if try(function() return mesh.bLockupSimulatePhysics end) or try(function() return pawn.bLockupSimulatePhysics end)
      or (ri and (try(function() return ri.bPoseSnapshot end) or try(function() return ri.bRegisterPoseSnapshot end))) then
      local was = unlock(pawn, mesh)
      no_snapshot(pawn)
      log("photo mode: her lockup / pose snapshot undone (" .. was .. ")")
    end
    return true
  end
  if not on then return true end -- (no answer: try again)
  screen.photoOn = false
  screen.photoOpened = nil
  screen.photoAfter = now + ((tune.gore or {}).photoGrace or 0.5)
  sw.drop()
  log("photo mode closed: the enemy's weapon trail starts over")
  return false
end

-- A piece simulating on her while she lives (F9's head) went back on her neck as photo mode opened, 213 cm in under
-- 0.5 s, its body still simulating (playtest): photo mode pauses the game but keeps her ticking, so her animation goes
-- on while the step that lays the physics pose over it (after physics, which a pause skips) doesn't. A whole ragdoll
-- (a death) kept its pose. So while the game is paused with a piece on her and her pelvis animated, her mesh stops
-- ticking: her own tick runs before her mesh's, and checks every frame for that (a cheap engine call; sbslice's state
-- is a file round trip). It ticks again once the pause ends.
-- Photo mode isn't a pause the engine knows (IsGamePaused stayed false, the freeze never came and her head pulled back
-- to her neck, playtest): what tells it the frame it opens is the view going to photo mode's own pawn (its class
-- looked at only when the view target changes), and sbslice's state read every 0.5 s backs that
-- the view target's class, looked at only when it changes (photo mode's own pawn while its view is up)
-- (through the player's camera manager, not her controller: photo mode possesses its own pawn, and her Controller
-- went with it, so the view target read off her never matched)
function screen.view(pawn, gs)
  gs = gs or StaticFindObject("/Script/Engine.Default__GameplayStatics")
  local vt = valid(gs) and try(function() return gs:GetPlayerCameraManager(pawn, 0).ViewTarget.Target end)
    or try(function() return pawn.Controller.PlayerCameraManager.ViewTarget.Target end)
  local va = valid(vt) and vt:GetAddress() or 0
  if va ~= screen.vtAddr then
    screen.vtAddr = va
    screen.vtClass = va ~= 0 and (try(function() return vt:GetClass():GetFName():ToString() end) or "") or ""
    screen.vtPhoto = screen.vtClass:find("PhotoMode") ~= nil
  end
end
-- The frame photo mode opens is also told by the game's time standing still while the frames go on (its pause stops
-- the world's clock, the death's timers with it): read every frame, so the freeze comes before her mesh ticks once
-- on the animation. A long frame (a hitch, the game's clock capped) isn't a pause
function screen.time_stopped(pawn, gs)
  local now = os.clock()
  local t = valid(gs) and try(function() return gs:GetTimeSeconds(pawn) end)
  local w = screen.clock
  screen.clock = t and { real = now, game = t } or nil
  if not (t and w) then return false end
  local real = now - w.real
  if real <= 0 or real > 0.25 then return screen.stopped == true end
  screen.stopped = (t - w.game) < real * 0.05
  return screen.stopped
end
-- her mesh (and hair) stop ticking / tick again. Her hair's meshes run their own animation (and SBHair its own sim)
-- off her head: with her mesh frozen the head stayed but the hair flew to her neck (playtest). Only what was ticking
-- is stopped, and started again
function screen.freeze(pawn, mesh, why)
  if screen.frozenMesh or not valid(mesh) or try(function() return mesh:IsSimulatingPhysics(PELVIS) end) then return end
  try(function() mesh:SetComponentTickEnabled(false) end)
  -- (photo mode updates her bones itself with her tick off, playtest: the skeleton update is skipped too)
  try(function() mesh.bNoSkeletonUpdate = true end)
  screen.frozenMesh = mesh:GetAddress()
  local hair = gore and gore.hair_of and gore.hair_of(pawn) or {}
  hair[#hair + 1] = try(function() return pawn.SBHair end)
  screen.frozenHair = {}
  for _, c in ipairs(hair) do
    if valid(c) and try(function() return c:IsComponentTickEnabled() end) == true then
      try(function() c:SetComponentTickEnabled(false) end)
      try(function() c.bNoSkeletonUpdate = true end)
      screen.frozenHair[#screen.frozenHair + 1] = c
    end
  end
  log(string.format("game paused (%s) with a piece simulating on her alive: her mesh and %d hair part(s) stop ticking (their animation would pull the piece back)",
    why, #screen.frozenHair))
end
function screen.unfreeze(mesh)
  local fz = screen.frozenMesh
  if not fz then return end
  screen.frozenMesh = nil
  if valid(mesh) and fz == mesh:GetAddress() then
    try(function() mesh.bNoSkeletonUpdate = false end)
    try(function() mesh:SetComponentTickEnabled(true) end)
  end
  for _, c in ipairs(screen.frozenHair or {}) do
    if valid(c) then try(function() c.bNoSkeletonUpdate = false end); try(function() c:SetComponentTickEnabled(true) end) end
  end
  screen.frozenHair = nil
  log("pause over: her mesh and hair tick again")
end
-- photo mode's widgets, as they are made (the widget watch above): her own tick, where the rest of this runs, stops
-- while photo mode is on (playtest: nothing of the mod's logged from photo mode opening till it closed, and the head
-- and hair went to her neck), so the freeze comes here, on the game thread, as photo mode opens. Each one is kept:
-- photo mode is on while one of them shows
function screen.photo_widget(o, cls)
  screen.photoW = screen.photoW or {}
  screen.photoW[#screen.photoW + 1] = o
  local pawn = cachedPawn
  local mesh = valid(pawn) and try(function() return pawn.Mesh end)
  local cut = gore and valid(mesh) and (gore.cuts_on(mesh)) > 0
  -- (the first one as it opens: how far her head is from where it was)
  if cut and not screen.photoOpened then
    local head = try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Head"))) end)
    local h0 = screen.photoHead
    screen.photoOpened = true
    log(string.format("photo mode opening: head %s off where it was", head and h0 and string.format("%.0f cm", dist(head, h0)) or "?"))
  end
  log(string.format("photo mode widget made: %s%s", cls, cut and "" or " (no piece off her)"))
  if cut then screen.freeze(pawn, mesh, "photo mode's widget " .. cls) end
end
local function photo_widget_up()
  local up = false
  for i = #(screen.photoW or {}), 1, -1 do
    local w = screen.photoW[i]
    if not valid(w) then table.remove(screen.photoW, i)
    elseif try(function() return w:IsInViewport() end) == true then up = true end
  end
  return up
end
function screen.photo_freeze(pawn, mesh)
  local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
  local paused = valid(gs) and try(function() return gs:IsGamePaused(pawn) end)
  screen.view(pawn, gs)
  local stopped = screen.time_stopped(pawn, gs)
  local widget = photo_widget_up()
  paused = paused or stopped or widget or screen.vtPhoto or screen.photoOn or screen.photoLive
  if paused then
    screen.freeze(pawn, mesh, screen.vtPhoto and "photo mode's view" or widget and "photo mode's widget"
      or (screen.photoOn or screen.photoLive) and "photo mode" or stopped and "the game's clock stopped" or "paused")
  else screen.unfreeze(mesh) end
end

-- photo mode hides her when its camera comes close (ewanhowell5195's Nexus mod 319 un-hides her as the camera
-- moves): while photo mode is on she is shown again every frame (tune.photoUnhide). Her actor and every part of her
-- (hidden, invisible, owner-no-see; a part hidden as photo mode opened, an outfit piece the gore took off, stays
-- hidden), and her out of the controller's hidden actors; what was undone is logged with the camera's distance.
-- In the last playtest none of her own flags changed as she vanished up close, so the near clip plane is brought in
-- too (screen.unhide_start). Photo mode is on when
-- its view target is photo mode's pawn, or its manager says so (sbslice f3, read every 0.5 s): the view target alone
-- never matched in game, and she was hidden up close as before (playtest)
function screen.photo_unhide(pawn)
  screen.view(pawn)
  local now = os.clock()
  if gore and gore.photo_state and now >= (screen.liveNext or 0) then
    screen.liveNext = now + 0.5
    -- the manager's +0x84 went back to 0 a second after photo mode opened on her alive (playtest): photo mode is
    -- also told by the player's pawn or the camera's view target being photo mode's own
    local st = gore.photo_state() or ""
    local m84 = tonumber(st:match(" 84=(%-?%d+)"))
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local cls = function(o) return valid(o) and (try(function() return o:GetClass():GetFName():ToString() end) or "?") or "none" end
    local pp = valid(gs) and cls(try(function() return gs:GetPlayerPawn(pawn, 0) end)) or "?"
    local vt = valid(gs) and cls(try(function() return gs:GetPlayerCameraManager(pawn, 0).ViewTarget.Target end)) or "?"
    local paused = valid(gs) and try(function() return gs:IsGamePaused(pawn) end)
    local live = (m84 ~= nil and m84 ~= 0) or pp:find("PhotoMode") ~= nil or vt:find("PhotoMode") ~= nil
    local sig = string.format("84=%s 48=%s, player pawn %s, view target %s, paused %s", tostring(m84), st:match(" 48=(%-?%d+)") or "?",
      pp, vt, tostring(paused))
    if sig ~= screen.liveSig then screen.liveSig = sig; log("photo probe: " .. sig) end
    if live ~= screen.photoLive then
      screen.photoLive = live
      log(string.format("photo mode %s (%s)", live and "on" or "off", sig))
    end
  end
  local on = screen.vtPhoto or screen.photoOn or screen.photoLive
  if not on then
    if screen.unhide then screen.unhide_end(pawn) end
    return
  end
  local u = screen.unhide
  if not u then u = screen.unhide_start(pawn) end
  local mesh = try(function() return pawn.Mesh end)
  local fixed = {}
  -- (what the game had set, logged as it changes: another way of hiding her would show here)
  local sig = string.format("actor hidden %s, character hidden %s, mesh hidden %s visible %s", tostring(try(function() return pawn.bHidden end)),
    tostring(try(function() return pawn.bCharacterHiddenInGame end)), tostring(try(function() return mesh.bHiddenInGame end)),
    tostring(try(function() return mesh.bVisible end)))
  if sig ~= screen.unhideSig then screen.unhideSig = sig; log("photo view: " .. sig) end
  if try(function() return pawn.bHidden end) == true then
    try(function() pawn:SetActorHiddenInGame(false) end)
    fixed[#fixed + 1] = "actor"
  end
  local face = gore and gore.face_of and valid(mesh) and try(function() return gore.face_of(pawn, mesh) end)
  local comps = { mesh, face }
  -- and every other part of her (hair, outfit pieces): one hidden as photo mode opened (the gore's) stays hidden
  for _, c in ipairs(u.comps) do comps[#comps + 1] = c.c end
  local seen = {}
  for _, c in ipairs(comps) do
    local a = valid(c) and c:GetAddress()
    if a and not seen[a] then
      seen[a] = true
      local name = function() return try(function() return c:GetName() end) or "?" end
      if not u.hid[a] and try(function() return c.bHiddenInGame end) == true then
        try(function() c:SetHiddenInGame(false, false) end)
        fixed[#fixed + 1] = name() .. " hidden"
      end
      if not u.hid[a] and try(function() return c.bVisible end) == false then
        try(function() c:SetVisibility(true, false) end)
        fixed[#fixed + 1] = name() .. " invisible"
      end
      if try(function() return c.bOwnerNoSee end) == true then
        try(function() c:SetOwnerNoSee(false) end)
        fixed[#fixed + 1] = name() .. " owner-no-see"
      end
    end
  end
  -- the controller's own lists of what it doesn't draw
  local pc = try(function() return pawn.Controller end)
  if valid(pc) then
    local keep, mine = {}, false
    try(function() pc.HiddenActors:ForEach(function(_, e)
      local a = e:get()
      if valid(a) and a:GetAddress() == pawn:GetAddress() then mine = true else keep[#keep + 1] = a end
    end) end)
    if mine and try(function()
      pc.HiddenActors:Empty()
      for i, a in ipairs(keep) do pc.HiddenActors[i] = a end
      return true
    end) then fixed[#fixed + 1] = "the controller's hidden actors" end
    local hp = try(function() return pc.HiddenPrimitiveComponents:GetArrayNum() end) or 0
    if hp ~= u.hp then u.hp = hp; log("photo view: the controller hides " .. hp .. " component(s)") end
  end
  if #fixed > 0 then
    local k = table.concat(fixed, ", ")
    if k ~= u.fixed then
      u.fixed = k
      log(string.format("photo mode hid her up close (camera %.0f cm from her head): shown again (%s)", u.d or -1, k))
    end
  end
  -- the camera's distance to her head, every 0.25 s; the closest is logged as photo mode closes
  local now = os.clock()
  if now >= u.next then
    u.next = now + 0.25
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local cam = valid(gs) and try(function() return vof(gs:GetPlayerCameraManager(pawn, 0):GetCameraLocation()) end)
    local head = valid(mesh) and try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Head"))) end)
    local d = cam and head and dist(cam, head)
    if d then
      u.d = d
      if not u.min or d < u.min then u.min = d end
    end
  end
end
-- photo mode opened: her parts listed (one hidden now, an outfit piece the gore took off, stays hidden), the near
-- clip plane brought in (tune.photoNearClip cm; the game's is 10 cm, and the camera's 10 cm cut into her up close)
function screen.unhide_start(pawn)
  local u = { comps = {}, hid = {}, next = 0, hp = 0 }
  screen.unhide = u
  local hidden = 0
  -- (her parts by her root's attach tree: K2_GetComponentsByClass found none in game)
  local seen = {}
  local function walk(c, depth)
    if not valid(c) or depth > 8 then return end
    local a = c:GetAddress()
    if seen[a] then return end
    seen[a] = true
    if try(function() return c:IsA(StaticFindObject("/Script/Engine.PrimitiveComponent")) end) then
      u.comps[#u.comps + 1] = { c = c, name = try(function() return c:GetName() end) or "?" }
      if try(function() return c.bHiddenInGame end) == true or try(function() return c.bVisible end) == false then
        u.hid[a] = true
        hidden = hidden + 1
      end
    end
    local kids = {}
    try(function() c.AttachChildren:ForEach(function(_, e) kids[#kids + 1] = e:get() end) end)
    for _, k in ipairs(kids) do walk(k, depth + 1) end
  end
  walk(try(function() return pawn.RootComponent end), 0)
  local nc = tune.photoNearClip
  if type(nc) == "number" and nc > 0 then u.clip = screen.console(pawn, string.format("r.SetNearClipPlane %g", nc)) end
  log(string.format("photo mode: %d part(s) of her watched (%d hidden already, left so)%s", #u.comps, hidden,
    u.clip and string.format(", near clip plane %g cm", nc) or ""))
  return u
end
function screen.unhide_end(pawn)
  local u = screen.unhide
  screen.unhide, screen.unhideSig = nil, nil
  if u.clip then screen.console(pawn, "r.SetNearClipPlane 10") end
  log(string.format("photo mode closed: the camera came within %s of her head%s; %s", u.min and string.format("%.0f cm", u.min) or "? cm",
    u.clip and ", near clip plane back to 10 cm" or "", gore and gore.photo_state() or "no sbslice"))
end
function screen.console(pawn, cmd)
  local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
  local pc = try(function() return pawn.Controller end)
  return valid(ksl) and try(function() ksl:ExecuteConsoleCommand(pawn, cmd, valid(pc) and pc or nil); return true end) == true
end

-- once a piece is off her, photo mode may open from the game's own key too: F9's head on her alive went back on her
-- neck as it opened (playtest). So her mesh is shielded as soon as she has a cut (sbslice f4, f5 once none is left),
-- and photo mode's state read every 0.5 s while she has one, her head's place kept from before: the watch above takes
-- over however photo mode opened
function screen.photo_guard(pawn, mesh)
  screen.watchFreeze = screen.frozenMesh ~= nil or (gore.cuts_on(mesh)) > 0
  if not screen.watchFreeze then screen.clock, screen.stopped = nil, nil end
  if screen.photoOn then return screen.photo_watch(pawn, mesh) end
  local a = mesh:GetAddress()
  if (gore.cuts_on(mesh)) == 0 then
    if screen.shielded == a then
      screen.shielded = nil
      log("no piece off her: her mesh unshielded: " .. gore.photo_unshield())
    end
    return false
  end
  if screen.shielded ~= a then
    screen.shielded = a
    log("a piece is off her: her mesh shielded from photo mode's collision switch: " .. gore.photo_shield(mesh))
  end
  local now = os.clock()
  if now < (screen.photoPoll or 0) then return false end
  screen.photoPoll = now + 0.5
  local on = tonumber(gore.photo_state():match(" 84=(%-?%d+)"))
  if on == 0 then screen.photoOpened = nil end
  if on and on ~= 0 then
    screen.photoOn, screen.photoNext, screen.photoSeen = true, 0, nil
    log("photo mode opened by the game's own key")
    return screen.photo_watch(pawn, mesh)
  end
  screen.photoHead = try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Head"))) end)
  return false
end

-- tune.holdDown: knocked down, she stays on the floor till the player gets her up (dodge or jump: the game's fast
-- getup). The data mod chains her tumbling knockdowns into Down_Eve, a copy of the shared Down (1 s, then Getup)
-- lasting held.LIFE s; off, its LifeTime in the loaded EffectTable goes back to Down's 1 s (gore.row_float). Looked at
-- every few seconds and on a change of the setting; written once per change (`hold down:` in the log)
screen.held = { key = nil, next = 0, LIFE = 100000, TABLE = "/Game/Local/Data/EffectTable.EffectTable" }
function screen.held.tick()
  local held = screen.held
  local want = tune.holdDown ~= false
  local now = os.clock()
  if want == held.want and now < held.next then return end
  held.want, held.next = want, now + 5
  if not gore then return end
  local dt = try(function() return StaticFindObject(held.TABLE) end)
  if not valid(dt) then return end
  local key = string.format("%s %x", tostring(want), dt:GetAddress())
  if key == held.key then return end
  local was, why = gore.row_float(dt, "Down_Eve", "LifeTime", want and held.LIFE or 1)
  -- the DLL still starting: again next time
  if not was and (why == "sbslice waiting" or why == "sbslice init") then held.next = 0; return end
  held.key = key
  if not was then
    log("hold down: Down_Eve not set (" .. tostring(why) .. "): the data pak's 100000 s stands if it has the row "
      .. "(\"err no such row\": the pak is missing or another mod's EffectTable wins, knockdowns stay the game's)")
  elseif was ~= held.LIFE and was ~= 1 then log(string.format("hold down: Down_Eve's LifeTime was %g, not the data mod's (another mod's EffectTable?); now %g", was, want and held.LIFE or 1))
  else log(string.format("hold down %s: Down_Eve lasts %g s (was %g)", want and "on" or "off", want and held.LIFE or 1, was)) end
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
  if gore and screen.photo_guard(pawn, mesh) then return end
  local function simulating() return try(function() return mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end) == true end
  local sim = simulating()

  tp.mark("find")
  try(function() screen.probe(pawn) end)
  tp.mark("death screen")
  screen.held.tick()
  if goreCtx.enemies then goreCtx.enemies.tick(pawn, mesh, tp.mark) end
  tp.mark("enemies")
  if gore then
    gore.tick(pawn, tp.mark)
    tp.mark("gore")
    -- a split after its splitAnim switches an animated death to the ragdoll (read again before the death's own
    -- steps below too)
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
    hm.guard_watch(pawn, mesh)
    tp.mark("swing")
    if gore then gore.watch(mesh) end
    tp.mark("bone watch")
    if goreCtx.glass then goreCtx.glass.tick(pawn, mesh) end
    tp.mark("glass")
    hit_marks(pawn, mesh)
    tp.mark("hit marks")
    hm.lethal_watch(pawn, mesh)
    tp.mark("lethal")
  elseif active and ((tune.gore or {}).afterHits or {}).enabled ~= false and (tune.gore or {}).enabled ~= false
    and os.clock() >= (screen.photoAfter or 0) then
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
  -- gore (a split after its splitAnim) or a hit after death (a leg off) can switch an animated death to the ragdoll
  -- this tick: read it again, or the death looked like it had no fall and no ragdoll and ended (she was put back
  -- whole 0.9 s into a beheading, a leg cut after it)
  if not sim and animDeath == nil and active then sim = simulating() end
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
    if hm.lethal then log(string.format("death: %.2f s after her HP bar hit 0", os.clock() - hm.lethal.t))
    elseif hm.armed then
      -- (the bar not yet at 0 as the death comes: the game drains it after; nothing could be cut at the hit)
      log(string.format("death: her HP bar read %s at it, %.2f s since it last changed", tostring(hm.barLast),
        os.clock() - (hm.barT or 0)))
    end
    -- disarmed till the bar is seen above 0 again: it reads 0 through the respawn, and the watch fired there
    hm.armed = false
    local h = death_hit(pawn, mesh)
    tp.mark("death hit")
    if not animated_death(pawn, mesh, h and h.push) and rag then rag.start(pawn, mesh, "death", h and h.push) end
    tp.mark("fall")
    -- the cut is chosen the next frame: with the death's own setup it was one 30-80 ms frame (playtest)
    pending[#pending + 1] = function()
      if not (active and valid(mesh)) then return end
      local t0 = os.clock()
      local ok, err = pcall(gore_death, pawn, mesh, h)
      if not ok then log("death cut failed: " .. tostring(err)) end
      local ms = (os.clock() - t0) * 1000
      if ms >= ((tune.gore or {}).slowMs or 15) then log(string.format("death cut: %.0f ms (a frame of its own)", ms)) end
    end
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
    -- revived where she lay (the item): the death left her movement off (MOVE_None), and she walked in place with
    -- only the camera moving (reported). Checked once 3 s after she got up, it missed when the game turned it off
    -- again later or its respawn event came with the revive. Now any time in screen.stuck.WINDOW after she got up:
    -- off for screen.stuck.POLLS with her capsule still (a skill or a show that moves her with movement off is left
    -- alone)
    if after < screen.stuck.WINDOW then
      local mm = try(function() return pawn.CharacterMovement.MovementMode end)
      local c = mm == 0 and try(function() local v = pawn:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
      local st = screen.stuck.at
      if not c then screen.stuck.at = nil
      elseif not st or dist(c, st.at) > 5 or after < st.since then screen.stuck.at = { since = after, at = c }
      elseif after - st.since >= screen.stuck.POLLS then
        screen.stuck.at = nil
        local ok = try(function() pawn.CharacterMovement:SetMovementMode(1, 0); return true end)
        log(string.format("revived in place: her movement was off for %.1f s, %.1f s after she got up%s, now walking%s",
          screen.stuck.POLLS * POLL_MS / 1000, after * POLL_MS / 1000, respawned and " (respawned)" or "", ok and "" or " (failed)"))
      end
    end
    rel.follow(pawn, mesh)
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
  if active and not saved.manual and (screen.respawn or not screen.frozen and (screen.revived or polls * POLL_MS / 1000 + ahead >= (tune.recoverAfter or 10)
    and screen.ready(polls * POLL_MS / 1000 + ahead))) then
    -- get her up ourselves before the game respawns her (the sandbox (F8) recovery always worked, the one after the
    -- game's respawn never did), once a death screen button is pressed (tune.recoverOn)
    log(string.format("recovering after %.1f s of ragdoll (%.1f of the game's), before the game respawns her (%s)",
      polls * POLL_MS / 1000, polls * POLL_MS / 1000 + ahead, screen.respawn and "the game is respawning her"
      or screen.revived and "revived with the item: the revive screen went and no death screen came"
      or tune.recoverOn ~= "button" and "recoverAfter" or screen.press and "a death screen button"
      or screen.gone and "the death screen went away" or screen.seen and "?" or "no death screen"))
    try(function() mesh:SetAllBodiesSimulatePhysics(false) end)
    try(function() mesh:SetSimulatePhysics(false) end)
    on_end(pawn, mesh)
    if screen.uv and not screen.revived and tune.uvClean ~= false then screen.uvClean = { pawn = pawn, n = 0 } end
  end
  screen.uv_tick()

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
  rel.loc, rel.rot = nil, nil
  meshHit, meshKey = nil, nil
  hm.q, hm.pct, hm.gkeys, hm.guardT, hm.guardWhy = {}, nil, nil, nil, nil
  sw.drop(); swingBones = {}
  chars, charsSeeded = {}, false
  followed = nil
  -- (the still camera went with the old level; the new controller looks through its own pawn)
  camHeld, camWatch, hold = nil, nil, nil
  screen.allow_photo(false, "level reloaded")
  screen.photoOn, screen.frozenMesh, screen.frozenHair, screen.watchFreeze, screen.photoW = false, nil, nil, false, nil
  screen.clock, screen.stopped, screen.uvClean = nil, nil, nil
  -- the photo watch's async loop read the old pawn's parts (freed with the level)
  screen.unhide, screen.unhideSig = nil, nil
  -- the new level may still be streaming in: nothing from the pak for a few seconds more
  goreCtx.quietUntil = math.max(goreCtx.quietUntil, os.clock() + 5)
  skip, ahead = nil, 0
  -- the old face may be gone: dropped without touching it
  dface.on, dface.known, faceCheck = nil, {}, nil
  if gore then gore.forget() end
  if goreCtx.enemies then goreCtx.enemies.forget() end
  if goreCtx.glass then goreCtx.glass.forget() end
  if rag then rag.forget() end
  if goreCtx.convulse then goreCtx.convulse.forget() end
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
local lastFrame, lastTick, lastDil = nil, nil, nil
local lastTickErr, tickErrRepeats = nil, 0
local function game_tick(ctx)
  if not adopt(ctx) then return end
  local now = os.clock()
  local gap = lastFrame and (now - lastFrame) * 1000
  lastFrame = now
  -- her own time dilation: the game's hit-stop slows her (and her tick) on a hit, which reads as a gap here without
  -- any frame taking long. Told with the gap, so a hitch in a fight can be told from a hit-stop
  local dil = try(function() return cachedPawn.CustomTimeDilation end)
  if gap and gap >= HITCH_MS and gap < HITCH_MAX_MS then
    local st = gore and gore.last_stage
    local slow = math.min(dil or 1, lastDil or 1)
    log(string.format("frame hitch: %.0f ms%s%s%s", gap,
      lastTick and now - lastTick.t < 0.5 and string.format(", the mod's last tick %.0f ms", lastTick.ms) or "",
      st and now - st.t < 0.5 and ", after " .. st.what or "",
      slow < 0.99 and string.format(", her time x%.2f (the game's hit-stop)", slow) or ""))
  end
  lastDil = dil
  for _, fn in ipairs(pending) do fn() end
  pending = {}
  if camHeld then camera_orbit() end
  -- (every frame: the tick below skips frames, and one is enough for her animation to pull a piece back)
  -- photo mode's hiding of its subjects (sbslice f6): set once, and again when tune.photoUnhide changes
  if tune.dev and cachedPawn and (not screen.watch or screen.watch.pawn ~= cachedPawn) then
    screen.watch = { pawn = cachedPawn, pc = try(function() return cachedPawn.Controller end) }
  end
  if tune.dev then screen.vis_watch() end
  local keep = tune.photoUnhide ~= false
  if gore and gore.photo_close and screen.closeSet ~= keep then
    local r = gore.photo_close(keep)
    if r:match("^ok") or r:match("^err") then screen.closeSet = keep end
    -- (sbslice still starting answers every tick: logged once)
    if r ~= screen.closeWas then
      screen.closeWas = r
      log("photo mode's hiding of her " .. (keep and "off" or "left to the game") .. ": " .. r)
    end
  end
  if keep and cachedPawn then pcall(screen.photo_unhide, cachedPawn) end
  if screen.watchFreeze then
    local mesh = try(function() return cachedPawn.Mesh end)
    if valid(mesh) then pcall(screen.photo_freeze, cachedPawn, mesh) end
  end
  -- every frame, ahead of her mesh tick: a stump's seam point is rewritten onto the bone its rim rides, or a twist
  -- helper poses it out into a cone. The poll below skips frames, and one is enough
  if gore and gore.hold_seams then gore.hold_seams() end
  if active then
    local ok, err = pcall(screen.pad_photo)
    if not ok then log("controller photo key: " .. tostring(err)) end
    if goreCtx.convulse then
      local ok2, err2 = pcall(goreCtx.convulse.tick, screen.photoOn or screen.vtPhoto or screen.photoLive or screen.stopped)
      if not ok2 then log("convulse: " .. tostring(err2)) end
    end
  elseif screen.padKeys then screen.padKeys, screen.padWas = nil, nil end
  -- and a cut's stages, a frame each (on the poll below the piece came off 350 ms after the blow)
  if gore and gore.pump and not screen.photoOn then
    local ok, err = pcall(gore.pump)
    if not ok then log("cut stage failed: " .. tostring(err)) end
  end
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

-- with dev on, every 0.25 s from her tick: sbslice's f9 (her bHidden, SBCharacter's hide flags, photo mode's manager
-- state, read without calling anything), her parts' hide flags (listed as photo mode opens) and, while photo mode is
-- on, the camera's distance; logged as they change. It ran off the game thread (an async loop, to see through photo
-- mode's pause) and crashed the game at a death screen: finding the command channel and reading a pawn the respawn
-- was remaking, while the level loaded (playtest; the Nexus report of an endless loading screen likely the same)
function screen.vis_watch()
  local now = os.clock()
  if now < (screen.visNext or 0) then return end
  screen.visNext = now + 0.25
  local w = screen.watch
  if not w or not gore or not gore.vis then return end
  pcall(function()
    local p = w.pawn
    local v = gore.vis(p)
    local on = tonumber(v:match(" 84=(%-?%d+)") or "0") ~= 0
    local parts = {}
    for _, c in ipairs((screen.unhide or {}).comps or {}) do
      local h, vi, o = try(function() return c.c.bHiddenInGame end), try(function() return c.c.bVisible end), try(function() return c.c.bOwnerNoSee end)
      if (h == true or vi == false or o == true) and not screen.unhide.hid[c.c:GetAddress()] then
        parts[#parts + 1] = string.format("%s%s%s%s", c.name, h == true and " hidden" or "", vi == false and " invisible" or "", o == true and " owner-no-see" or "")
      end
    end
    local d
    if on then
      local cam = try(function() local l = w.pc.PlayerCameraManager.CameraCachePrivate.POV.Location; return { X = l.X, Y = l.Y, Z = l.Z } end)
      local me = try(function() local l = p.RootComponent.RelativeLocation; return { X = l.X, Y = l.Y, Z = l.Z } end)
      d = cam and me and dist(cam, me)
    end
    local sig = v .. (#parts > 0 and "; parts " .. table.concat(parts, ", ") or "")
    local band = d and math.floor(d / 25) or -1
    if sig ~= w.sig or band ~= w.band then
      w.sig, w.band = sig, band
      log(string.format("vis watch: %s%s", d and string.format("camera %.0f cm from her middle; ", d) or "", sig))
    end
  end)
end

local TICK_FN = "/Game/Art/Character/PC/CH_P_EVE_01/Blueprints/CH_P_EVE_01_Blueprint.CH_P_EVE_01_Blueprint_C:ReceiveTick"
-- hooked once, then the loop stops: her Blueprint stays loaded for the whole game (one hook a session in 163 logged
-- sessions, never again at a respawn), and nothing of the mod's then runs off the game thread through a respawn's
-- level load. (UE4SS's BeginPlay hook never fires in this game: hooked from it, she was never hooked.) Only object
-- lookups from this thread, no engine calls
LoopAsync(250, function()
  if not valid(FindFirstOf("CH_P_EVE_01_Blueprint_C")) then return false end
  local fn = try(function() return StaticFindObject(TICK_FN) end)
  local addr = valid(fn) and fn:GetAddress() or nil
  if not addr then return false end
  local ok, err = pcall(RegisterHook, TICK_FN, function(ctx) game_tick(ctx) end)
  log(string.format("tick hook on %x: %s", addr, ok and "ok" or tostring(err)))
  return ok
end)

log("loaded (stabiliser + logger)")
