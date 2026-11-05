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
-- Sandbox: F7 ragdolls her with a shove onto her back (tune.lua), F8 recovers (F7, F9 and F11 stay until F8),
-- F9 cuts a limb, the head or the torso (tune.gore), F10 puts a living hit's mark on her (tune.gore.hitMarks: a hit she
-- lives through leaves a slash of blood on her skin, healing fades it), F11 ragdolls her and splits
-- her in half top to bottom, Delete ragdolls her and cuts along a made-up blade (as a killing blow does), F6 tests the
-- struggle (a ragdoll death with set cuts, the next of STRUGGLE_TESTS each press).
-- Enemies (enemies.lua): F5 spawns the picked humanoid enemy in front of her, Insert picks the next, Home shows
-- or hides the spawner window (sbslice.dll), End ragdolls the followed one nearest her (the passive Airborne
-- Squad die no other way); her killing blows and hits on their corpses cut them like her.
-- Glass cannon (glass.lua, off by default, Page Down): the shield guards her HP, once it is down any hit kills her, cut
-- where it landed; her blows do several times the damage.
-- Settings: settings.lua (the player's switches) over tune.lua. The test keys, the spawner and the glass cannon only
-- work with its dev on.
-- Hits: the game tells clients about every skill hit (SBNetworkPlayerController:ClientBroadcast_SkillHitResult,
-- with the swing's direction); the last one on Eve decides whether a killing blow came down from above. In single
-- player it never fires: the blow is made up from her mesh's hit or the nearest enemy (death_hit). Every killing
-- blow cuts, but a blunt one (a hammer, a fist, a stomp: sw.blunt_of) smashes the part to meat (tune.gore.smash).
-- On first load it also dumps the full reflection schema (DumpUSMAP) for asset editing.
-- Log: ue4ss/Mods/StellarBladeGore/stellarbladegore.log (also mirrored into UE4SS.log).

local MOD = "StellarBladeGore"
local VERSION = "0.7.0"
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

-- a log of its own each start, the last one kept as .old (it was appended to forever: 19 MB of every session since
-- the install, and a report meant digging for the one that counted). Past lg.max bytes only errors are written
local lg
do
local previous = io.open(LOG_PATH, "r")
local rotated, rotateError = true, nil
if previous then
  previous:close()
  os.remove(LOG_PATH .. ".old")
  rotated, rotateError = os.rename(LOG_PATH, LOG_PATH .. ".old")
end
-- Never truncate the previous session if a locked file or permissions prevent rotation.
lg = { fh = io.open(LOG_PATH, rotated and "w" or "a"), bytes = 0, max = 20 * 1024 * 1024 }
if not rotated then print("[" .. MOD .. "] log rotation failed; appending to preserve the previous session: " .. tostring(rotateError) .. "\n") end
end
local function log(s)
  local line = string.format("[%s] %s", os.date("%H:%M:%S"), s)
  print("[" .. MOD .. "] " .. line .. "\n")
  if not lg.fh then return end
  if lg.bytes > lg.max and not line:find("error", 1, true) then return end
  lg.bytes = lg.bytes + #line + 1
  lg.fh:write(line, "\n")
  if lg.bytes > lg.max and not lg.full then lg.full = true; lg.fh:write("[log full: only errors from here on]\n") end
  lg.fh:flush()
end

local function try(fn, ...)
  local ok, v = pcall(fn, ...)
  if ok then return v end
  return nil
end

-- (no closure made per call: called hundreds of times a poll, each one garbage for the collector)
local valid
do
  local function is_valid(o) return o:IsValid() end
  valid = function(o)
    if o == nil then return false end
    local ok, v = pcall(is_valid, o)
    return ok and v == true
  end
end
local function name(o) return valid(o) and (try(function() return o:GetFName():ToString() end) or "?") or "<nil>" end
local function v3(v) return v and string.format("(%.0f %.0f %.0f)", v.X, v.Y, v.Z) or "(?)" end
local function len(v) return v and math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) or -1 end
local function dist(a, b) return (a and b) and len({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }) or -1 end
local function copy3(v, k) return v and { [k[1]] = v[k[1]], [k[2]] = v[k[2]], [k[3]] = v[k[3]] } or nil end
local XYZ, PYR = { "X", "Y", "Z" }, { "Pitch", "Yaw", "Roll" }

-- the Eve whose ReceiveTick runs the script (see adopt below)
local cachedPawn, pawnAddr, pawnSeen = nil, nil, 0
local tune = {}
-- the per-poll and per-frame watches (a death's bone speeds, her attachments, face and camera, every hook): only with
-- tune.verboseLog, for chasing a bug (they were most of the log)
function lg.v(s) if tune.verboseLog then log(s) end end
local goreCtx = { tune = tune }
-- UGameplayStatics' default object, found once: looked up by its path every frame (screen.view) and on many polls,
-- each a path lookup on the game thread (a Nexus report of 144 fps down to 100-110 with the mod)
do
  local gsCdo = nil
  function goreCtx.statics()
    if not valid(gsCdo) then gsCdo = try(function() return StaticFindObject("/Script/Engine.Default__GameplayStatics") end) end
    return gsCdo
  end
end
-- Retained-object guards share a frame epoch with the game loop.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/object_lifetime.lua")(goreCtx, try, valid, log, function() return tune end)
-- may an asset be loaded from the pak now (LoadAsset)? Not from her getting up in a death till the new level's Eve has
-- ticked a while: a load on the game thread then waited on the respawn's own loading, whose new objects wait on the
-- Lua lock that thread holds (NotifyOnNewObject: widgets, characters), an endless loading screen (Nexus report).
-- What isn't loaded yet is found or loaded on a later call
goreCtx.quietUntil = 0
goreCtx.may_load = function() return os.clock() >= goreCtx.quietUntil end
-- Settings preserve the player file and publish live tuning to the shared context.
local load_tune, base_tune = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings_manager.lua")(goreCtx, log,
  function(t) tune = t end, TUNE_PATH, SETTINGS_PATH, SETTINGS_DEFAULT, "ue4ss/Mods/StellarBladeGore/Scripts/menu.lua")
log(string.format("Stellar Blade Gore Mod %s", VERSION))
load_tune()
goreCtx.reload_tune, goreCtx.version = load_tune, VERSION
goreCtx.base_tune = base_tune

local gore, rag, physfix = nil, nil, nil
-- an animated death (see animated_death below): { pawn, mesh, push } while her own fall plays, nil otherwise
local animDeath = nil
-- one of the data mod's falls is playing: it holds its last frame for 120 s (the game's dead pose snapped in when it
-- ended 0.9 s after the fall), so recovery stops it, or a test death (F5) left her lying there
local heldShow = false
-- an animated death's pose held from the death's start till its cut is chosen (deathFreeze): her fall played on
-- while the cut was chosen and a split's stages ran, 130 ms and more, and she was seen turning round in it before the
-- cut came (playtest). A split keeps it held till it ragdolls; anything else lets the fall go on at once
-- (on goreCtx: the main chunk is at Lua's 200 locals)
goreCtx.pose = { held = nil }
function goreCtx.pose.hold(mesh)
  if (tune.active or {}).deathFreeze == false or not valid(mesh) then return end
  if try(function() mesh.bNoSkeletonUpdate = true; return true end) then goreCtx.pose.held = { mesh = mesh, t = os.clock() } end
end
function goreCtx.pose.free(why)
  local f = goreCtx.pose.held
  if not f then return end
  goreCtx.pose.held = nil
  if valid(f.mesh) then try(function() f.mesh.bNoSkeletonUpdate = false end) end
  log(string.format("death: her pose let go after %.0f ms (%s)", (os.clock() - f.t) * 1000, why))
end
-- quiet: from her fall's end pose, as she lies (struggle.lua, maimed): no blow, no momentum, she just goes limp
local function ragdoll_now(why, quiet)
  local a = animDeath
  if not a then return end
  animDeath = nil
  goreCtx.pose.free("ragdoll: " .. why)
  if goreCtx.convulse then try(function() goreCtx.convulse.to_ragdoll() end) end
  try(function() a.mesh:SetSimulatePhysics(true) end)
  try(function() a.mesh:SetAllBodiesSimulatePhysics(true) end)
  try(function() a.mesh:SetAllBodiesBelowSimulatePhysics(FName("Bip001"), true, true) end)
  try(function() a.mesh:WakeAllRigidBodies() end)
  log(string.format("animated death: ragdoll after all (%s), pelvis simulating %s", why,
    tostring(try(function() return a.mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end))))
  if rag then
    if quiet then rag.start(a.pawn, a.mesh, "quiet") else rag.start(a.pawn, a.mesh, "death", a.push) end
  end
end
goreCtx.log, goreCtx.try, goreCtx.valid, goreCtx.v3, goreCtx.vlog = log, try, valid, v3, lg.v
-- her mesh's physics asset, the one physfix gave an outfit without one included
goreCtx.physics_of = function(m)
  if physfix then return physfix.asset(m) end
  local pa = try(function() return m:GetPhysicsAsset() end)
  if valid(pa) then return pa end
  pa = try(function() return m.SkeletalMesh.PhysicsAsset end)
  return valid(pa) and pa or nil
end
-- a severed limb stops being driven by the muscle tone
goreCtx.on_cut = function(mesh, bone) if rag then rag.on_cut(mesh, bone, goreCtx.alive and goreCtx.alive()) end end
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
-- her asset has the neutral pose's drives (physfix.lua; active.lua turns them on in a ragdoll)
goreCtx.has_neutral = function(m) return physfix ~= nil and physfix.has_neutral(goreCtx.physics_of(m)) end
goreCtx.arm_table = function(m, p) return physfix and physfix.arm_table(goreCtx.physics_of(m), p) or "no physfix" end
-- she is up: none of her pairs collide any more but her hair's (physfix.alive_pairs). The table lives on her physics asset, so a cut on her standing (F9
-- after F8) took the last ragdoll's pairs, measured in another pose: her hands against her thighs, where they hang
-- now, and the cut flung them off at 2000 cm/s (playtest)
goreCtx.reset_pairs = function(mesh)
  if not goreCtx.arm_pairs then return end
  goreCtx.arm_pairs = nil
  local pa = goreCtx.physics_of(mesh)
  log("collision pairs reset: " .. tostring(physfix and valid(pa) and physfix.alive_table(pa) or "no physfix"))
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
goreCtx.ragdoll_quiet = function(why) ragdoll_now(why, true) end
-- a piece cut off a standing Eve gets human masses
goreCtx.on_piece = function(pawn, mesh, bone) if rag then return rag.piece(pawn, mesh, bone) end end
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
  -- a maimed Eve's struggle on the floor (goreCtx.struggle, tune.struggle)
  local ok7, sg = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/struggle.lua")
  if ok7 and type(sg) == "table" then
    goreCtx.struggle = sg
    sg.init(goreCtx)
  else
    log("struggle.lua failed: " .. tostring(sg))
  end
  local ok3, p = pcall(dofile, PHYSFIX_PATH)
  if ok3 and type(p) == "table" then
    physfix = p
    physfix.init(goreCtx)
  else
    log("physfix.lua failed: " .. tostring(p))
  end
  -- objects as the game makes them, handed out on her tick (goreCtx.newobj: sbslice.dll's listener, not UE4SS's
  -- NotifyOnNewObject, whose callbacks ran on loading threads)
  local okn, nw = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/newobj.lua")
  if okn and type(nw) == "table" then
    goreCtx.newobj = nw
    nw.init(goreCtx)
  else
    log("newobj.lua failed: " .. tostring(nw))
    goreCtx.newobj = { watch = function() end, tick = function() end, mode = function() return "off" end }
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
  -- the sandbox: bosses spawned and killed like any enemy (goreCtx.bosses). (Playing as another character is a mod
  -- of its own, Stellar Blade Play As: gore.lua sees who she looks like by her meshes)
  -- Customized Ragdoll (Nexus 3884) support: its death camera over the mod's ragdoll (goreCtx.customrag)
  -- blood and dirt on her, the game's own switched back on (goreCtx.stains, tune.stains)
  for _, m in ipairs({ { "bosses", "bosses.lua" }, { "customrag", "customrag.lua" }, { "stains", "stains.lua" } }) do
    local okm, mod = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/" .. m[2])
    if okm and type(mod) == "table" then
      goreCtx[m[1]] = mod
      mod.init(goreCtx)
    else
      log(m[2] .. " failed: " .. tostring(mod))
    end
  end
  -- the game's DataTables changed in game (goreCtx.tables): no table in the pak overrides other mods' any more
  local ok7, tb = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/tables.lua")
  if ok7 and type(tb) == "table" then
    goreCtx.tables = tb
    tb.init(goreCtx)
  else
    log("tables.lua failed: " .. tostring(tb))
  end
  -- the mod's keys, rebindable (goreCtx.keys, tune.keys)
  local ok9, ky = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/keys.lua")
  if ok9 and type(ky) == "table" then
    goreCtx.keys = ky
    ky.init(goreCtx)
  else
    log("keys.lua failed: " .. tostring(ky))
  end
  -- the in-game settings menu (goreCtx.gui, F3)
  local ok8, gu = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/gui.lua")
  if ok8 and type(gu) == "table" then
    goreCtx.gui = gu
    gu.init(goreCtx)
  else
    log("gui.lua failed: " .. tostring(gu))
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
-- a cut on her alive (F9, Lose Arm at Low HP) leaves her bodies' PhysicsBody response alone when the table keeps her
-- main bodies apart already: turned off, her ponytail's bodies sank through her head and back again (physfix.alive_pairs)
goreCtx.table_filled = function(mesh) return not active and physfix and physfix.table_filled(goreCtx.physics_of(mesh)) or false end
goreCtx.alive = function() return not active end
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
  if not tune.verboseLog then return end
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

-- Each face controller owns its morph cache and active expression.
goreCtx.make_face = dofile("ue4ss/Mods/StellarBladeGore/Scripts/death_face.lua")(try, valid, name, log,
  function() return tune end, function() return gore end)
local dface = goreCtx.make_face(function() return goreCtx.convulse and goreCtx.convulse.face() or {} end)
-- a sandbox boss's own (bosses.lua): start(actor, mesh, why), tick(), stop(); no convulsions on its face
goreCtx.new_face = function() return goreCtx.make_face(function() return {} end) end
local faceCheck = nil
-- hits after death (hits_after, below): n so far this death, armedBy the enemies (addresses) whose weapon slowed
-- after their last hit, t0 the death
local ah = { n = 0, armedBy = {}, t0 = 0, lastBy = {}, missBy = {} }
-- when her death began (os.clock), nil while she lives (enemies.lua: tune.enemies.afterDeath)
goreCtx.dead_since = function() return active and ah.t0 or nil end
local function sandbox_face()
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not valid(mesh) then log("Page Up: no Eve"); return end
  log("Page Up: " .. face_curves(mesh, gore and gore.face_of and gore.face_of(pawn, mesh)))
  dface.start(pawn, mesh, "Page Up", 6)
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
-- she gets up where the capsule is, and the game drags it after her body with no sweep: a ragdoll at rest against a
-- wall left it half in the wall, and the revive item stood her up inside it (Nexus report, 0.4.0). So it is put back
-- where she went limp (clear then: she was standing there) and swept from there to where it was, stopping at what's
-- in the way. Its collision is on for the sweep
function rel.unstick(pawn)
  local h = hold
  if tune.capsuleUnstick == false or not (h and h.at) then return end
  local cap = try(function() return pawn.CapsuleComponent end)
  local c = try(function() local v = pawn:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
  if not (valid(cap) and c) or dist(h.at, c) < 5 then return end
  local was = try(function() return cap:GetCollisionEnabled() end)
  try(function() cap:SetCollisionEnabled(3) end)
  local ok = try(function()
    pawn:K2_SetActorLocation(h.at, false, {}, true)
    pawn:K2_SetActorLocation(c, true, {}, false)
    return true
  end)
  if was and was ~= 3 then try(function() cap:SetCollisionEnabled(was) end) end
  local now = try(function() local v = pawn:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
  log(string.format("capsule: swept from where she went limp to where it drifted (%.0f cm): %s", dist(h.at, c),
    not ok and "failed" or now and dist(now, c) > 1 and string.format("stopped %.0f cm short, at what was in the way", dist(now, c)) or "nothing in the way"))
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
-- Performance diagnostics share the screen state but own their probe and reporting logic.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/performance.lua")(screen, goreCtx, valid, try, log,
  function() return active end, function() return tune end, function() return cachedPawn end)
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

-- The held camera owns its references; world cleanup drops them without touching old actors.
local PELVIS = FName("Bip001-Pelvis")
local camera = dofile("ue4ss/Mods/StellarBladeGore/Scripts/death_camera.lua")(screen, goreCtx, valid, try,
  log, lg, name, v3, dist, PELVIS, function() return tune end)
-- Esc on a death (tune.deathSkip): the game runs tune.deathSkipSpeed times as fast till its death screen
-- (WB_MainHUD_Dead) shows, instead of the wait. The mod's own clock for getting her up (recoverAfter) counts the
-- game's time meanwhile (ahead: game seconds over real ones), so she still gets up under the screen
local skip, ahead, aheadTick = nil, 0, 0 -- skip: { t0, k, pawn }; aheadTick: this poll's game-time delta
local function time_speed(pawn, k)
  local gs = goreCtx.statics()
  return valid(gs) and valid(pawn) and try(function() gs:SetGlobalTimeDilation(pawn, k); return true end) == true
end
-- Slow-motion death effect (tune.deathSlowmo): the game runs slower for a few
-- seconds when she dies so the damage reads, then time goes back to normal well
-- before the death screen. Esc's fast forward wins over it either way.
local slowmo = dofile("ue4ss/Mods/StellarBladeGore/Scripts/death_slowmo.lua")(
  function() return tune end, os.clock, log)
local function slow_stop(why)
  if slowmo.stop(why, function() time_speed(find_eve(), 1) end) and gore and gore.voice_slow then
    try(function() gore.voice_slow(1) end)
  end
end
-- the death screen's widget, found once and kept (a scan of every object: 17 ms, twice a second, was a stutter of
-- its own, playtest), looked for at most every 2 s in a death while it isn't found. Never its class default
-- (FindFirstOf gave that, kept for good: no death screen was ever seen), and it lives inside the main HUD, so it is
-- never in the viewport itself: shown when it and its CanvasPanel_Dead are visible
-- Both it and the revive item's screen are caught as they are made (every widget made in a death has its class
-- read): the scan every 2 s while it wasn't found was 60 ms each in a big level, and the death screen's class only
-- loads at the death. One scan a death is left, from 5 s in, for one made before the mod loaded
local dead_hud, death_screen = dofile("ue4ss/Mods/StellarBladeGore/Scripts/death_widgets.lua")(
  screen, goreCtx, valid, try, log, function() return active end)
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
  slow_stop("Esc fast forward")
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
  aheadTick = aheadTick + (skip.k - 1) * POLL_MS / 1000
  if death_screen() then skip_stop("the death screen is up")
  elseif polls * POLL_MS / 1000 + ahead >= (tune.recoverAfter or 10) then skip_stop("no death screen seen") end
end
local function slow_start(pawn)
  -- real deaths only: the test ragdolls have no death to highlight
  if slowmo.running() or skip or not active or saved.manual or not valid(pawn) then return end
  local k = slowmo.start()
  if not k then return end
  if not time_speed(pawn, k) then slowmo.stop("the game's speed can't be set"); return end
  if gore and gore.voice_slow then try(function() gore.voice_slow(k) end) end
  log(string.format("death: slow motion x%.2f for %.1f s", k, tonumber((tune.deathSlowmo or {}).duration) or 5))
end
-- every tick of the ragdoll: the game's time it ran behind, and time back once the window is over
local function slow_tick()
  if not slowmo.running() then return end
  ahead = ahead + (slowmo.speed() - 1) * POLL_MS / 1000
  aheadTick = aheadTick + (slowmo.speed() - 1) * POLL_MS / 1000
  if slowmo.done() then slow_stop("its time is up") end
end
-- what the game's clock runs at now (1 normally): the mod's own sounds pitch down with it, never up
goreCtx.time_scale = function() return slowmo.running() and slowmo.speed() or 1 end

-- what covers the view while the death screen is up (it came up all black, the game behind it not showing:
-- playtest): its "black" and "FadeOut" images, its background blur, the camera's fade. Every 0.5 s, logged when it
-- changes (`death screen: ...`)
-- She is got up when a button on it is pressed (tune.recoverOn "button"): the game respawns her only after that, and
-- got up at recoverAfter under the screen she would stand up whole behind it. seen / gone: the screen came up / went
-- away in this death; press: one of its buttons (or its press animation) fired (screen is made above the camera)
-- its buttons (the custom events their clicks call, under either spelling of the name's number) and its animations:
-- the death animation finishing shows it, the press animation a button pressed. Hooked as soon as its class is
-- loaded (tried once a second in a death till then); none had ever been hooked, as the screen was never seen
-- The screen controller keeps its state on screen for recovery and world cleanup.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/death_screen.lua")(screen, goreCtx, dead_hud, death_screen,
  valid, try, log, function() return active end, function() return saved.manual end,
  function() return tune end, function() return cachedPawn end,
  function() return polls * POLL_MS / 1000 + ahead end)
-- HUD state remains on screen so world cleanup can discard stale widget references.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/death_hud.lua")(screen, goreCtx, dead_hud, valid, try, log,
  function() return active end, function() return saved.manual end, function() return tune end)
-- Short-lived CNS diagnostic: compare each breast bone with its parent before and during F7, including scale.
-- The screenshot alone cannot tell which bone in a multi-body chain is responsible for a deformed mesh.
function screen.breast_probe(mesh, phase)
  local full = try(function() return mesh.SkeletalMesh:GetFullName() end) or ""
  if not full:lower():find("/game/cnsrepacked/", 1, true) then return end
  for _, side in ipairs({ "L", "R" }) do
    local out = {}
    for _, b in ipairs({ "Dm-" .. side .. "-Breast-Point", "Dm-" .. side .. "-Breast",
      "Ab-" .. side .. "-Breast-Link", "Ab-" .. side .. "-Breast",
      "Ab-" .. side .. "-Hip", "Ab-" .. side .. "-Hip-Reg" }) do
      local s = try(function()
        if mesh:GetBoneIndex(FName(b)) < 0 then return nil end
        local parent = mesh:GetParentBone(FName(b))
        local t, p = mesh:GetSocketTransform(FName(b), 0), mesh:GetSocketTransform(parent, 0)
        local a, q = t.Rotation, p.Rotation
        local dx, dy, dz = t.Translation.X - p.Translation.X, t.Translation.Y - p.Translation.Y, t.Translation.Z - p.Translation.Z
        local x = q.W*a.X - q.X*a.W - q.Y*a.Z + q.Z*a.Y
        local y = q.W*a.Y + q.X*a.Z - q.Y*a.W - q.Z*a.X
        local z = q.W*a.Z - q.X*a.Y + q.Y*a.X - q.Z*a.W
        local w = q.W*a.W + q.X*a.X + q.Y*a.Y + q.Z*a.Z
        local scale = t.Scale3D
        local sim = try(function() return mesh:IsSimulatingPhysics(FName(b)) end)
        local vel = try(function() local v = mesh:GetPhysicsAngularVelocityInDegrees(FName(b))
          return string.format("%.1f", math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)) end) or "?"
        return string.format("%s parent=%s d=%.2f q=(%.3f,%.3f,%.3f,%.3f) scale=(%.3f,%.3f,%.3f) sim=%s spin=%s",
          b, parent:ToString(), math.sqrt(dx*dx+dy*dy+dz*dz), x, y, z, w, scale.X, scale.Y, scale.Z, tostring(sim), vel)
      end)
      if s then out[#out + 1] = s end
    end
    if #out > 0 then log("breast probe " .. phase .. " " .. side .. ": " .. table.concat(out, "; ")) end
  end
end

-- Wedding Dress 3504's simulated breast links and their parent can rotate far beyond their authored limits. Keep those bodies simulated
-- for their joints, but use their animated bone transforms for skinning. The rest of the ragdoll stays physics-driven.
-- This is scoped to the one diagnosed asset; its visual result still needs an in-game check.
function screen.wedding_blend(mesh)
  if saved.weddingBlend or saved.weddingBlendFailed then return end
  local full = try(function() return mesh.SkeletalMesh:GetFullName() end) or ""
  if not full:lower():find("/game/cnsrepacked/5a2518e03d16a0cd/", 1, true) then return end
  if try(function() return mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end) ~= true then return end
  local names = { "Dm-L-Breast", "Dm-R-Breast" }
  for _, b in ipairs(names) do
    if (try(function() return mesh:GetBoneIndex(FName(b)) end) or -1) < 0 then
      saved.weddingBlendFailed = true; log("wedding blend: missing " .. b); return
    end
  end
  local force = try(function() return mesh.bBlendPhysics end)
  if force ~= true and force ~= false then saved.weddingBlendFailed = true; log("wedding blend: physics blend flag unreadable"); return end
  if force then
    -- bBlendPhysics bypasses per-body weights; retain the rest of her physics before clearing the override.
    if not try(function() mesh:SetAllBodiesPhysicsBlendWeight(1.0, false); mesh:SetEnablePhysicsBlending(false); return true end) then
      saved.weddingBlendFailed = true; log("wedding blend: could not prepare per-body weights"); return
    end
  end
  local ok = true
  for _, b in ipairs(names) do
    if not try(function() mesh:SetAllBodiesBelowPhysicsBlendWeight(FName(b), 0.0, false, true); return true end) then ok = false end
  end
  if not ok then
    for _, b in ipairs(names) do try(function() mesh:SetAllBodiesBelowPhysicsBlendWeight(FName(b), 1.0, false, true) end) end
    if force then try(function() mesh:SetEnablePhysicsBlending(true) end) end
    saved.weddingBlendFailed = true; log("wedding blend: could not set both link weights"); return
  end
  saved.weddingBlend = { mesh = mesh, forced = force }
  log("wedding blend: both breast chains use animated skinning; remaining bodies use physics")
end

local function on_start(pawn, mesh)
  local timings, stamp = {}, os.clock()
  local function phase(label)
    local now = os.clock()
    local ms = (now - stamp) * 1000
    if ms >= 1 then timings[#timings + 1] = string.format("%s %.0f", label, ms) end
    stamp = now
  end
  local wasSimulating = try(function() return mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end) == true
  screen.cloth_give_back()
  log("ragdoll state at start: " .. ragdoll_state(pawn))
  screen.reset()
  phase("screen")
  -- her voice for any death: a cry as she dies, nothing after (gore.lua, tune.gore.voice)
  if gore then try(function() gore.voice_death(pawn, mesh) end) end
  phase("voice")
  if goreCtx.convulse then try(function() goreCtx.convulse.start(pawn, mesh) end) end
  if goreCtx.struggle then try(function() goreCtx.struggle.start(pawn, mesh) end) end
  ah.n, ah.armedBy, ah.t0, ah.blunt, ah.brushes, ah.misses, ah.gated, ah.lastBy, ah.missBy = 0, {}, os.clock(), nil, 0, 0, nil, {}, {}
  ah.projectiles, ah.projectileRecent, ah.projectileAt = {}, {}, nil
  no_snapshot(pawn)
  hold = nil
  hold_capsule(pawn)
  camera.hold(pawn)
  phase("camera and state")
  deaths = deaths + 1
  active, polls, ahead, aheadTick = true, 0, 0, 0
  screen.deathAt = os.clock()
  saved = { meshPB = try(function() return mesh:GetCollisionResponseToChannel(CH.PhysicsBody) end) }
  -- "auto": the data mod fixes the collision table of every outfit's physics asset (mod/ragdoll_spec.json,
  -- "outfits"), so those keep self-collision (limbs can't pass through each other); vanilla ones (outfit mods
  -- that ship their own physics asset) overlap at rest and fling
  -- an outfit the data mod didn't patch: its loose bodies are locked to the body above them, and a mesh with no
  -- physics asset gets one (physfix.lua)
  local remakes = physfix and (physfix.remakes or 0) or 0
  if physfix then try(function() physfix.start(pawn, mesh) end) end
  phase("physics setup")
  -- Assigning a missing physics asset recreates bodies and can stop the ragdoll that brought us here.
  if wasSimulating and try(function() return mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end) ~= true then
    try(function() mesh:SetSimulatePhysics(true) end)
    try(function() mesh:SetAllBodiesBelowSimulatePhysics(FName("Bip001"), true, true) end)
    try(function() mesh:WakeAllRigidBodies() end)
    log("ragdoll: restored simulation after physics asset setup: " .. tostring(try(function()
      return mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end)))
  end
  if physfix and (physfix.remakes or 0) > remakes and gore and gore.rebreak_cuts then
    try(function() gore.rebreak_cuts(mesh) end)
  end
  if gore then
    local ok, n, all = pcall(gore.kawaii, mesh, false)
    if ok and (all or 0) > 0 then log(string.format("ragdoll: her outfit's KawaiiPhysics off (%d of %d nodes)", n, all))
    elseif not ok then log("ragdoll: her outfit's KawaiiPhysics: " .. tostring(n)) end
  end
  phase("simulation and outfit")
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
  phase("collision pairs")
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
  phase("finish")
  if #timings > 0 then log("death start timings: " .. table.concat(timings, ", ")) end
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

-- rotators and quaternions as UE's FRotator::Quaternion and FQuat::Rotator
function rel.quat(r)
  local h = math.pi / 360
  local sp, cp = math.sin(r.Pitch * h), math.cos(r.Pitch * h)
  local sy, cy = math.sin(r.Yaw * h), math.cos(r.Yaw * h)
  local sr, cr = math.sin(r.Roll * h), math.cos(r.Roll * h)
  return { X = cr * sp * sy - sr * cp * cy, Y = -cr * sp * cy - sr * cp * sy,
           Z = cr * cp * sy - sr * sp * cy, W = cr * cp * cy + sr * sp * sy }
end
function rel.rotator(q)
  local d = 180 / math.pi
  local s = q.Z * q.X - q.W * q.Y
  local yaw = math.atan(2 * (q.W * q.Z + q.X * q.Y), 1 - 2 * (q.Y * q.Y + q.Z * q.Z)) * d
  local function axis(a) a = a % 360; return a > 180 and a - 360 or a end
  if s < -0.4999995 then return { Pitch = -90, Yaw = yaw, Roll = axis(-yaw - 2 * math.atan(q.X, q.W) * d) } end
  if s > 0.4999995 then return { Pitch = 90, Yaw = yaw, Roll = axis(yaw - 2 * math.atan(q.X, q.W) * d) } end
  return { Pitch = math.asin(2 * s) * d, Yaw = yaw,
           Roll = math.atan(-2 * (q.W * q.X + q.Y * q.Z), 1 - 2 * (q.X * q.X + q.Y * q.Y)) * d }
end

-- where the mesh belongs on the capsule: an offset from it (the gameplay one, rel, by default) in its whole frame.
-- Turned with its yaw alone, she went upside down on a climbing bar, where the capsule pitches, and walked on her head
-- after it (Nexus report, 0.4.3): rel.follow put the mesh where the yaw said, every tick, each from the last
function rel.target(cap, loc, rot)
  loc, rot = loc or rel.loc, rot or rel.rot
  local cl = cap:K2_GetComponentLocation()
  local cq = try(function() local q = cap:K2_GetComponentToWorld().Rotation; return { X = q.X, Y = q.Y, Z = q.Z, W = q.W } end)
  if not cq then
    local cr = cap:K2_GetComponentRotation()
    cq = rel.quat({ Pitch = cr.Pitch, Yaw = cr.Yaw, Roll = cr.Roll })
  end
  -- the offset turned by the capsule (q v q*), the rotation the capsule's then the offset's (cq * rq)
  local tx, ty, tz = 2 * (cq.Y * loc.Z - cq.Z * loc.Y), 2 * (cq.Z * loc.X - cq.X * loc.Z), 2 * (cq.X * loc.Y - cq.Y * loc.X)
  local wl = { X = cl.X + loc.X + cq.W * tx + cq.Y * tz - cq.Z * ty, Y = cl.Y + loc.Y + cq.W * ty + cq.Z * tx - cq.X * tz,
               Z = cl.Z + loc.Z + cq.W * tz + cq.X * ty - cq.Y * tx }
  local rq = rel.quat(rot)
  return wl, rel.rotator({ X = cq.W * rq.X + cq.X * rq.W + cq.Y * rq.Z - cq.Z * rq.Y,
                            Y = cq.W * rq.Y - cq.X * rq.Z + cq.Y * rq.W + cq.Z * rq.X,
                            Z = cq.W * rq.Z + cq.X * rq.Y - cq.Y * rq.X + cq.Z * rq.W,
                            W = cq.W * rq.W - cq.X * rq.X - cq.Y * rq.Y - cq.Z * rq.Z })
end

-- put the mesh back into normal animated gameplay state
local function recover(pawn, mesh, why)
  local cap = try(function() return pawn.CapsuleComponent end)
  -- the muscle tone's drives hold the current bodies, which gore's cleanup recreates: release them first
  if rag then try(function() rag.stop(pawn) end) end
  if gore then try(function() gore.cleanup(pawn, mesh) end) end
  if gore and screen.low_reset then try(function() screen.low_reset(pawn, why or "her recovery") end) end
  if physfix then try(function() physfix.stop() end) end
  if gore then
    local ok, n, all = pcall(gore.kawaii, mesh, true)
    if ok and (all or 0) > 0 then log(string.format("recover: her outfit's KawaiiPhysics back on (%d of %d nodes)", n, all)) end
  end
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
  -- fallback if the mesh is still away from the capsule after the unlock: retry the place, then leave it to rel.follow
  local attempts = {
    { "world", function() end },
    { "world2", function() end },
    { "world3", function() end },
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
  -- (a climb or a rope swing places her mesh itself)
  if try(function() return pawn:IsClimbing() or pawn:IsRopeSwing() end) == true then return end
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
  lg.v(string.format("a%03d parent=%s capsule%s mesh%s pelvis%s pelvisGap=%.0f visible=%s hidden=%s sim=%s meshLockup=%s move=%s",
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
  rel.unstick(pawn)
  capsule_report()
  screen.allow_photo(false, "she got up")
  screen.photoOn, screen.photoColl = false, nil
  camera.release(pawn)
  skip_stop("she got up")
  slow_stop("she got up")
  dface.stop()
  if goreCtx.convulse then try(function() goreCtx.convulse.stop() end) end
  if goreCtx.struggle then try(function() goreCtx.struggle.stop() end) end
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
  if saved.collision or saved.takeColl then
    -- sandbox ragdoll (or the mod's own on a death with none): put back the exact gameplay collision setup
    local c = saved.collision or saved.takeColl
    try(function() mesh:SetCollisionObjectType(c.obj) end)
    for ch, r in pairs(c.resp) do try(function() mesh:SetCollisionResponseToChannel(ch, r) end) end
    try(function() mesh:SetCollisionEnabled(c.enabled) end)
  end
  recover(pawn, mesh, "ragdoll ended")
  if saved.weddingBlend and saved.weddingBlend.forced and valid(saved.weddingBlend.mesh) then
    try(function() saved.weddingBlend.mesh:SetEnablePhysicsBlending(true) end)
  end
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
  -- A body already flying (tower F7s read 14-28k cm/s before any push) would get the shove on top and leave the map.
  -- Stop it first so the shove starts from rest.
  if before and before > 2000 then
    try(function() mesh:SetAllPhysicsLinearVelocity({ X = 0, Y = 0, Z = 0 }, false) end)
    try(function() mesh:SetAllPhysicsAngularVelocityInDegrees({ X = 0, Y = 0, Z = 0 }, false) end)
    try(function() mesh:WakeAllRigidBodies() end)
    log(string.format("F7: pelvis already at %.0f cm/s, stopped before the shove", before))
    before = body_speed(mesh, "Bip001-Pelvis")
  end
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
  screen.cloth_give_back()
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
  screen.breast_probe(mesh, "before F7")
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

local function sandbox_recover(why)
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not valid(mesh) then return end
  try(function() mesh:SetAllBodiesSimulatePhysics(false) end)
  try(function() mesh:SetSimulatePhysics(false) end)
  -- a cut on a living Eve (F9) never starts a full ragdoll, so undo it here too. Its physics remake stops the
  -- simulated accessories (hair, hand straps) with everything else, and nothing restarts them: the yellow suit's
  -- right-arm strap hung dead after F8 (playtest). The equip path restarts them through the cloth reset, so schedule
  -- the same reset when a piece was actually undone.
  local hadPiece = gore and not active and #(gore.cut_parts(mesh) or {}) > 0
  if gore and not active then gore.cleanup(pawn, mesh) end
  if rag and not active then rag.stop(pawn) end
  if hadPiece then screen.cloth_soon("piece recovered") end
  log(why or "F8: recover requested")
  -- a test death that stayed animated (Test: Animated Death's, a cut keeping her fall) has no physics to turn off,
  -- and the tick only ends a death when it does: F8 did nothing (playtest)
  if active and saved.manual and animDeath then on_end(pawn, mesh) end
end

-- what a killing blow does, by tune.gore.death's odds: "limb", "head", "torso", "split" or "diagonal" (split only when
-- allowed, diagonal with diag: a split's kinds need her ragdoll, F9 cuts her standing). near (gore.near_odds): each kind's weight times its factor, where the blow
-- landed; odds with nothing left near the hit (the only one above 0 far from it) are rolled as they are
local KINDS = { "limb", "head", "torso", "split", "diagonal" }
local function pick_kind(split, near, diag)
  local odds = (tune.gore or {}).death or { limb = 42, head = 25, torso = 15, split = 18, diagonal = 0 }
  local function raw(k)
    if (k == "split" and not split) or (k == "diagonal" and not diag) then return 0 end
    return math.max(tonumber(odds[k]) or 0, 0)
  end
  local function sum(f)
    local t = 0
    for _, k in ipairs(KINDS) do t = t + f(k) end
    return t
  end
  local w = near and function(k) return raw(k) * (near[k] or 0) end or raw
  local total = sum(w)
  if total <= 0 and w ~= raw then w, total = raw, sum(raw) end
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
-- when the last of them landed (enemies.lua: her hand thrown about by a blow is no swing of hers)
goreCtx.hit_at = function() return meshHit and meshHit.t end
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
  if k then chars[ad] = { obj = o, addr = ad, cls = cls, k = k } end
end
screen.late[#screen.late + 1] = function()
  goreCtx.newobj.watch("/Script/SB.SBCharacter", add_char)
  -- (the laser traps, for sw.laser_hit at her death: kept as they are made, seeded with the characters once a level.
  -- Looked for at the death, FindAllOf was 35 ms of the death's cut frame, a stutter at every death, playtest)
  goreCtx.newobj.watch("/Script/SB.SBLaserComponent", function(o)
    local k = goreCtx.keep(o)
    if k then goreCtx.lasers[k.addr] = k end
  end)
end
goreCtx.lasers = {}
-- (the list made once a frame: the swing, the grab watch, the enemies and the glass cannon each asked it, every
-- character checked and its location read again by each, in a fight a good part of the poll; 0.5.2 Nexus report of
-- the frame rate down. Read only: the callers only walk it, and a character's location is goreCtx.char_at's)
-- (goreCtx.charsPoll / charsList, not locals: this chunk is at Lua's 200)
local function live_chars()
  -- One walk per poll window: her watches, the enemies' part and the poll each run on a frame of their own, and
  -- each walked the whole list before (two walks of every three wasted: same game state, 33 ms apart at most).
  -- Positions still refresh through char_at's own clock cache, and every consumer guards dying and vanishing actors.
  if goreCtx.charsPoll == goreCtx.poll and goreCtx.charsList then return goreCtx.charsList end
  local started = os.clock()
  -- (none till sbslice is up: held() can't tell yet, and a character it said no to would be dropped for good)
  local g = goreCtx.gore
  if not (g and g.native_ready and g.native_ready()) then return {} end
  if goreCtx.reseed and os.clock() - (goreCtx.seededAt or -99) > 5 then charsSeeded, goreCtx.reseed = false, nil end
  -- (not watched as they spawn: the new ones found by a seed every 10 s)
  if goreCtx.newobj.mode() == "off" and os.clock() - (goreCtx.seededAt or -99) > 10 then charsSeeded = false end
  -- A seed walks the whole object array (15-69 ms on a poll frame, playtest): never on a frame where a cut is
  -- opening. Spawns are still caught as they happen by the new-object watch, so only the backfill waits; the flag
  -- stays down and the seed runs on the first quiet poll.
  local cutBusy = g.busy and g.busy()
  if not charsSeeded and not cutBusy then
    charsSeeded, goreCtx.seededAt = true, os.clock()
    local t0 = os.clock()
    local all = try(function() return FindAllOf("SBCharacter") end) or {}
    for _, a in ipairs(all) do add_char(a) end
    -- (the whole object array walked: 20-50 ms "following 0 enemies" after outfit changes and level loads, playtest)
    local ms = (os.clock() - t0) * 1000
    if ms >= 10 then log(string.format("characters looked up again (%d): %.0f ms", #all, ms)) end
  end
  -- (the laser traps seeded on a frame of their own, a second after the characters: in theirs it was 73 ms, playtest.
  -- Once a session when the watch hands them out as they are made, else once a level)
  if not goreCtx.lasersSeeded and goreCtx.seededAt and os.clock() - goreCtx.seededAt > 1 then
    goreCtx.lasersSeeded = true
    local scanAt = os.clock()
    local found = try(function() return FindAllOf("SBLaserComponent") end) or {}
    for _, o in ipairs(found) do
      local k = goreCtx.keep(o)
      if k then goreCtx.lasers[k.addr] = k end
    end
    local ms = (os.clock() - scanAt) * 1000
    if ms >= 10 then log(string.format("laser components looked up (%d): %.0f ms", #found, ms)) end
  end
  -- Validate all character guards not already checked this frame together. Listed guards can have aged out while
  -- the game was paused: held() would then prune them on the first check and recheck the growing list per character.
  local validationAt = os.clock()
  local fresh, now = {}, os.clock()
  for _, e in pairs(chars) do
    local k = e.k
    if k and k.frame ~= goreCtx.frame and not k.dead and (k.idx or now - k.t <= (tune.keepFresh or 2)) then fresh[#fresh + 1] = k end
  end
  for i = 1, #fresh, 64 do
    local part = { table.unpack(fresh, i, math.min(i + 63, #fresh)) }
    if goreCtx.alive_ask(part) then
      for _, k in ipairs(part) do
        if k.alive and k.idx then
          k.asked = now
          if not k.listed then k.listed = true; goreCtx.heldList[#goreCtx.heldList + 1] = k end
        elseif not k.alive then k.dead = true end
      end
    end
  end
  local walkAt = os.clock()
  local out = {}
  -- (her place this frame, for char_at's far ones)
  goreCtx.herAt = cachedPawn and try(function() return vof(cachedPawn:K2_GetActorLocation()) end)
  for ad, e in pairs(chars) do
    if goreCtx.held(e.k) then
      out[#out + 1] = e
    else
      -- (one spawned while no tick ran, a level loading, came too late to be checked: found again by a new seed)
      if e.k.stale then goreCtx.reseed = true end
      chars[ad] = nil
    end
  end
  local doneAt = os.clock()
  if (doneAt - started) * 1000 >= 15 then
    log(string.format("character list timing: seed %.0f ms, batch %.0f ms (%d guards), walk %.0f ms (%d live, %d held)",
      (validationAt - started) * 1000, (walkAt - validationAt) * 1000, #fresh,
      (doneAt - walkAt) * 1000, #out, #goreCtx.heldList))
  end
  goreCtx.charsPoll, goreCtx.charsList = goreCtx.poll, out
  return out
end
goreCtx.live_chars = live_chars
-- a live_chars entry's actor location, else nil: read at most once a poll however many watches ask (her watches, the
-- enemies' part and the poll each run on a frame of their own, and each read every character again). One past
-- CHAR_FAR cm from her is read again only once it could have come within that, at CHAR_RUN cm/s, her own way since
-- counted too: no watch reaches past CHAR_FAR (the glass cannon's 4000), so each sees it out of reach as it is; at
-- most CHAR_KEEP s, and not in its first CHAR_NEW s (one spawned is put in its place a moment later). Every
-- character of the level read 3 times a poll was a good part of the poll in a hub or a big fight (0.5.2 Nexus report)
-- (goreCtx fields, not locals: this chunk is at Lua's 200)
goreCtx.CHAR_FAR, goreCtx.CHAR_RUN, goreCtx.CHAR_KEEP, goreCtx.CHAR_NEW = 4500, 2000, 1, 3
function goreCtx.char_at(e)
  local now = os.clock()
  local her = goreCtx.herAt
  if e.atT then
    local age = now - e.atT
    local spent = age * goreCtx.CHAR_RUN + (her and e.atHer and dist(her, e.atHer) or 0)
    if age < 0.025 or e.atFar and spent < e.atFar and age < goreCtx.CHAR_KEEP
      and now - (e.k and e.k.t or now) > goreCtx.CHAR_NEW then return e.at end
  end
  local o = e.obj
  e.at, e.atT, e.atHer = try(function() return vof(o:K2_GetActorLocation()) end), now, her
  local d = e.at and her and dist(e.at, her)
  e.atFar = d and d > goreCtx.CHAR_FAR and d - goreCtx.CHAR_FAR or nil
  return e.at
end
-- not an enemy: her drone and the other playable characters (tune.gore.attackerIgnore, parts of class names)
local function ignored(cls)
  for _, p in ipairs((tune.gore or {}).attackerIgnore or { "Drone", "CH_P_", "AirborneSquad" }) do
    if cls:find(p, 1, true) then return true end
  end
  return false
end
goreCtx.ignored = ignored

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
  local scanAt = os.clock()
  local live = live_chars()
  local listAt = os.clock()
  for _, e in ipairs(live) do
    local a = e.obj
    -- (its place first: the flags only for one within reach, two engine reads less for every other)
    local l = e.addr ~= me and not ignored(e.cls) and goreCtx.char_at(e)
    local d = l and dist(l, at)
    if d and d >= 0 and d < reach and try(function() return a.bActorIsBeingDestroyed end) == false
      and try(function() return a.bHidden end) ~= true then
      out[#out + 1] = { actor = a, loc = l, d = d, cls = e.cls, addr = e.addr, k = e.k }
    end
  end
  -- (the single-nearest lookup, the killing-blow search, skips the full sort: the same nearest entry)
  if most == 1 and #out > 1 then
    local bi = 1
    for i = 2, #out do if out[i].d < out[bi].d then bi = i end end
    out = { out[bi] }
  else
    table.sort(out, function(x, y) return x.d < y.d end)
    while #out > (most or #out) do table.remove(out) end
  end
  local endAt = os.clock()
  if (endAt - scanAt) * 1000 >= 15 then
    log(string.format("nearby characters detail: %d candidates, list %.0f ms, positions %.0f ms", #live,
      (listAt - scanAt) * 1000, (endAt - listAt) * 1000))
  end
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
-- The same impact may arrive through several hooks. Retain only primitive data and bound both queues.
function sw.projectile_record(h, key)
  h.key = key
  -- A short, bounded history lets a simultaneous volley affect the killing smash.
  -- Only distinct known projectile objects/IDs count; the same impact can use multiple hooks.
  local volley = sw.projectileVolley or {}
  for i = #volley, 1, -1 do
    if h.t - volley[i].t > 0.35 or h.t < volley[i].t then table.remove(volley, i) end
  end
  local duplicate = not key
  for _, r in ipairs(volley) do
    if key == r.key or (h.src ~= r.src and dist(h.loc, r.loc) < 25) then duplicate = true; break end
  end
  if not duplicate then
    volley[#volley + 1] = { t = h.t, key = key, loc = h.loc, src = h.src, hit = h }
    if #volley > 8 then table.remove(volley, 1) end
  end
  sw.projectileVolley = volley
  h.volley = #volley
  for _, r in ipairs(volley) do r.hit.volley = #volley end
  sw.projectileLast = h
  local g, c = tune.gore or {}, (tune.gore or {}).afterHits or {}
  if (key and duplicate) or not active or ah.blunt or g.enabled == false or c.enabled == false or (g.smash or {}).enabled ~= true
    or not ah.t0 or h.t < ah.t0 or ah.n >= (c.max or 6) then return end
  local recent = ah.projectileRecent or {}
  for i = #recent, 1, -1 do
    local r = recent[i]
    if h.t - r.t > 0.25 then table.remove(recent, i)
    elseif (key and r.key and key == r.key) or (h.src ~= r.src and dist(h.loc, r.loc) < 25) then return end
  end
  recent[#recent + 1] = {t=h.t, loc=h.loc, key=key, src=h.src}
  if #recent > 8 then table.remove(recent, 1) end
  ah.projectileRecent = recent
  ah.projectiles = ah.projectiles or {}
  if #ah.projectiles < 4 then ah.projectiles[#ah.projectiles + 1] = h end
end
-- Projectile hooks retain live pawn, hit and gore state supplied by the main loop.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/projectile_hits.lua")(sw, hm,
  function() return os.clock() - pawnSeen < 0.5 and cachedPawn or nil end,
  function() return gore end, function() return meshHit end, try, valid, vof, len, dist, v3, log)
-- Keep the hook wrappers in the main lifecycle, which owns the pawn freshness clock.
sw.projectileImpl = { blueprint = sw.projectile_blueprint_event, rock = sw.rock_event }
function sw.projectile_blueprint_event(...)
  return sw.projectileImpl.blueprint(os.clock() - pawnSeen < 0.5 and cachedPawn or nil, ...)
end
function sw.rock_event(...)
  return sw.projectileImpl.rock(os.clock() - pawnSeen < 0.5 and cachedPawn or nil, ...)
end
screen.late[#screen.late + 1] = function() goreCtx.newobj.watch("/Script/SB.SBProjectile", sw.projectile_watch) end

local function cross(a, b) return { X = a.Y * b.Z - a.Z * b.Y, Y = a.Z * b.X - a.X * b.Z, Z = a.X * b.Y - a.Y * b.X } end
local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function sub(a, b) return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z } end
local function unit(v) local l = len(v); return l > 1e-6 and { X = v.X / l, Y = v.Y / l, Z = v.Z / l } or nil end
function sw.drop() swing, sw.list = sw.state(), {} end
local track_swing, clear_swing_bones = dofile("ue4ss/Mods/StellarBladeGore/Scripts/swing_tracking.lua")(
  sw, goreCtx, function() return tune end, function() return swing end, function(v) swing = v end,
  function() return active end, function() return gore end, SWING_NAMES, try, valid, vof, len, name, log)
-- the swing that killed her, if the weapon moved fast enough: { dir, n, at (the weapon there), speed, bone, fwd }
sw.of = dofile("ue4ss/Mods/StellarBladeGore/Scripts/swing_selection.lua")(
  function() return tune end, function(k) return goreCtx.held(k) end, try, vof, SWING_AT, sub, dot, dist, len, unit, cross, log)

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
function sw.explosion_hit(pawn, mesh)
  local limit = try(function() return pawn.RagdollInfo.ImpulseLimitVelocity end)
  if type(limit) ~= "number" or math.abs(limit - 702) > 0.01 then return nil end
  local at = try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Spine2"))) end)
    or try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Pelvis"))) end)
    or try(function() return vof(pawn:K2_GetActorLocation()) end)
  if not at then return nil end
  try(function() pawn.RagdollInfo.ImpulseLimitVelocity = 700 end)
  local push = try(function() return vof(pawn.RagdollInfo.ImpulseValue) end)
  if not push or len(push) < 1e-3 then push = { X = 0, Y = 0, Z = -1 } end
  log("death: explosion death show on Eve, blunt smash at " .. v3(at))
  return { t = os.clock(), loc = at, push = push, dir = push, blast = true, src = "explosion death show" }
end
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
  local projectile = sw.explosion_hit(pawn, mesh) or sw.rock_blow(mesh) or sw.projectile_hit() or sw.death_projectile(mesh)
  if projectile then return projectile end
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
        attacker = swing.who, pose = ws.pose, pose_ago = ws.ago, second = ws.second, wbone = ws.bone,
        impactRadius = ws.impactRadius, impactSizeSource = ws.impactSizeSource }
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

-- Attack classification reads the current settings, tracked swing and gore module.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/hit_classification.lua")(sw,
  function() return tune end, function() return swing end, function() return gore end, len, log)

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

-- ---- a laser trap's beam (tune.gore.laserCut) ----
-- A laser trap death (P_Eve_Dead_Laser, the balance beam's) had no blow: the death odds were rolled, one part off
-- wherever the beam was. The game's beams are SBLaserComponents, each a list of straight segments (LaserSegmentArray:
-- StartPosition, EndPosition, the actor it hit). The segment that hit her (HitActor), else the one passing nearest her
-- parts within laserReach cm, is the blade: cut along a plane holding the beam, level across it (a beam across her
-- cuts her at its height), or with her forward for an upright one, and every arm, leg and her body that plane goes
-- through comes off (gore.blow's h.laser: no turning it at random, no reach limit from the hit)
function sw.laser_hit(pawn, mesh)
  local g = tune.gore or {}
  if g.laserCut == false or not valid(mesh) then return nil end
  local parts = { { "Bip001-Head" } }
  for _, e in ipairs(SWING_AT) do parts[#parts + 1] = e end
  local pts = {}
  for _, e in ipairs(parts) do
    local l = try(function()
      local x = mesh:GetSocketLocation(FName(e[1]))
      if not e[3] then return vof(x) end
      local y = mesh:GetSocketLocation(FName(e[3]))
      return { X = (x.X + y.X) / 2, Y = (x.Y + y.Y) / 2, Z = (x.Z + y.Z) / 2 }
    end)
    if l then pts[#pts + 1] = { l = l, bone = e[1] } end
  end
  if #pts == 0 then return nil end
  local me = pawn:GetAddress()
  local best, n = nil, 0
  -- (the ones kept as they were made, live_chars; not watched, looked for here as before)
  local list = {}
  if goreCtx.newobj.mode() == "off" then
    list = try(function() return FindAllOf("SBLaserComponent") end) or {}
  else
    for ad, k in pairs(goreCtx.lasers) do
      if goreCtx.held(k) then list[#list + 1] = k.obj else goreCtx.lasers[ad] = nil end
    end
  end
  for _, c in ipairs(list) do
    if valid(c) and try(function() return c.bActiveLaser end) ~= false then
      n = n + 1
      try(function()
        c.LaserSegmentArray:ForEach(function(_, e)
          local s = e:get()
          if try(function() return s.bDisable end) == true then return end
          local a, b = vof(s.StartPosition), vof(s.EndPosition)
          if not (a and b) or dist(a, b) < 1 then return end
          local x = try(function() return s.HitActor:Get() end) or try(function() return s.HitActor end)
          local mine = valid(x) and try(function() return x:GetAddress() == me end) == true
          for _, p in ipairs(pts) do
            local d = seg_dist(a, b, p.l)
            if not best or (mine and not best.mine) or (mine == best.mine and d < best.d) then
              best = { a = a, b = b, d = d, p = p, mine = mine, owner = c }
            end
          end
        end)
      end)
    end
  end
  if not best then return nil end
  if not best.mine and best.d > (g.laserReach or 40) then
    log(string.format("death: %d laser(s) about, the nearest beam %.0f cm off her %s: not a laser death", n, best.d, best.p.bone))
    return nil
  end
  local d = unit(sub(best.b, best.a))
  local nrm
  if math.abs(d.Z) < 0.8 then
    nrm = unit({ X = -d.Z * d.X, Y = -d.Z * d.Y, Z = 1 - d.Z * d.Z })
  else
    local f = try(function() return vof(pawn:GetActorForwardVector()) end) or { X = 1, Y = 0, Z = 0 }
    nrm = unit(cross(d, f)) or unit(cross(d, { X = 1, Y = 0, Z = 0 }))
  end
  if not nrm then return nil end
  -- (the point of the beam nearest her part)
  local ab = sub(best.b, best.a)
  local t = math.max(0, math.min(1, dot(sub(best.p.l, best.a), ab) / math.max(dot(ab, ab), 1e-4)))
  local loc = { X = best.a.X + t * ab.X, Y = best.a.Y + t * ab.Y, Z = best.a.Z + t * ab.Z }
  local owner = try(function() return best.owner:GetOwner():GetFName():ToString() end) or "?"
  log(string.format("death: a laser beam of %s %s her (%.0f cm off her %s), at %s, %.0f deg from level: cut along it",
    owner, best.mine and "hit" or "passes by", best.d, best.p.bone, v3(loc), math.deg(math.asin(math.min(1, math.abs(d.Z))))))
  return { t = os.clock(), loc = loc, n = nrm, how = "laser", src = "laser", attack_dir = 0, laser = true,
    bone = best.p.bone:find("%-[LR]%-") and best.p.bone or nil }
end
-- Spatial hit testing is kept separate from attack gating and cut dispatch.
sw.after_geometry = dofile("ue4ss/Mods/StellarBladeGore/Scripts/after_hit_geometry.lua")(try, vof, SWING_AT, sub, dot, dist, seg_dist)
local hits_after = dofile("ue4ss/Mods/StellarBladeGore/Scripts/hits_after.lua")(sw, ah, goreCtx,
  function() return tune end, function() return gore end, function() return swing end,
  try, vof, len, dist, sub, dot, cross, unit, log)

-- the killing blow shown at once (tune.gore.woundAtHit): her HP bar read every tick while she lives (a widget already
-- found: a property read); the tick it reaches 0, gore.wound marks where the blade met her. The death itself is only
-- seen at the death show's ragdoll key, 0.2-0.5 s later (playtest); the death logs how long after this it came
hm.lethal = nil
-- her guard, read every tick while she lives: the game keeps it native (no property or function shows it, and her
-- stance read P_Eve_Default all through a block, playtest), so it is the guard key held (her controller's action
-- mappings named Guard or Block, read once; tune's guardKeys, E and L1, when none are), a montage of hers named Guard or
-- Block, or a block stance (ASBCharacter.GetCurrentStanceName: a ..._Guard1 skill). Noted with its
-- time; a killing blow within tune.active.weaponCut.blockWindow of it broke through her guard, and her sword breaks
-- (active.weapon_cut)
hm.stances = {}
-- (not the swordless stances, P_Eve_BlockSword and her gun's P_Eve_GunBlockSword: no guard in them, her sword taken
-- (Altess Levoire, No Sword Without It); a death in one read as a guard broken through, and broke the sword)
function hm.guarding(s)
  if not s or s:find("BlockSword", 1, true) then return nil end
  return (s:find("Block", 1, true) or s:find("Guard", 1, true)) and s or nil
end
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
    local gs = goreCtx.statics()
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
-- what a death does, rolled once (at the lethal hit, else at the death): "blade" (cut along the blade seen, the
-- bladeFollow share of deaths with one), "split" (the odds' split share of the rest) or "odds". The cut at the hit
-- took the blade every time, and a split share of 100 never split (reported). A blade seen decides first: with the
-- split share rolled ahead of it a dual blades' cross across both arms and a level swing both split her down her
-- length (playtest). near (gore.near_odds): the split share as pick_kind shapes it, by where the blow landed
function hm.death_roll(seen, near)
  local g = tune.gore or {}
  local odds, total = g.death or {}, 0
  local function weight(k)
    if k == "diagonal" and ((g.diagonal or {}).enabled == false or g.deathSplit == false or g.noSplits == true) then return 0 end
    return math.max(tonumber(odds[k]) or 0, 0)
  end
  for _, k in ipairs(KINDS) do total = total + weight(k) end
  -- (gore.noSplits: none at all, its share rolled as the others)
  local sp = g.noSplits == true and 0 or weight("split")
  if g.noSplits == true then total = total - weight("split") end
  -- (odds that are all split still split every death, blade or not)
  local follow = math.min(math.max(tonumber(g.bladeFollow) or 1, 0), 1)
  if seen and not (total > 0 and sp >= total) and math.random() < follow then return "blade" end
  if near then
    local nt = 0
    for _, k in ipairs(KINDS) do
      if k ~= "split" or g.noSplits ~= true then nt = nt + weight(k) * (near[k] or 0) end
    end
    if nt > 0 then sp, total = sp * (near.split or 0), nt end
  end
  if g.deathSplit ~= false and total > 0 and math.random() * total < sp then
    return "split", odds.split, total
  end
  -- (no blade seen: "blade" still, which gore_cut rolls the odds for as a made-up blow)
  return seen and "odds" or "blade"
end
-- the killing cut made at the hit on a blow she lived through (a revive, a skill, her bar back up, or no death and
-- proof she plays on, hm.plays_on): it stayed on her alive, a stump's seam at her neck as she played on (reported).
-- Undone as the death's end undoes it. Time alone is no proof: a death slow to show (a long death show before its
-- ragdoll key) would have had its cut taken back and rolled again
hm.LIVED_S, hm.LIVED_CM = 6, 150
-- her bar still at 0 (a fall leaves her at 1 HP, read as 0) LIVED_S on from the hit: why she is seen alive, else nil.
-- Her movement on, no death screen, no death montage, and her capsule moved LIVED_CM from where the blow found her
function hm.plays_on(pawn, mesh, lt)
  if os.clock() - lt.t <= hm.LIVED_S then return end
  local mm = try(function() return pawn.CharacterMovement.MovementMode end)
  if mm == nil or mm == 0 or death_screen() or hm.dead_proof(lt.t) then return end
  local mn = hm.montage(mesh)
  if mn and (mn:find("Dead", 1, true) or mn:find("Die", 1, true)) then return end
  local at = try(function() return vof(pawn:K2_GetActorLocation()) end)
  if not (at and lt.from) then return end
  local d = len(sub(at, lt.from))
  if d < hm.LIVED_CM then return end
  return string.format("no death %.0f s after her HP bar hit 0, her movement on (mode %s) and %.0f cm walked",
    os.clock() - lt.t, tostring(mm), d)
end
function hm.lived(pawn, mesh, why)
  hm.lethal.cut = nil
  log("lethal hit: she lived (" .. why .. "): the cut made at the hit undone")
  if gore then try(function() gore.cleanup(pawn, mesh) end) end
  if rag then try(function() rag.stop(pawn) end) end
end
-- the montage her body plays now, by name, else nil
function hm.montage(mesh)
  local ai = valid(mesh) and try(function() return mesh:GetAnimInstance() end)
  local mont = valid(ai) and try(function() return ai:GetCurrentActiveMontage() end)
  return valid(mont) and try(function() return mont:GetFName():ToString() end) or nil
end
-- the game's scripted deaths (CharacterDeadTable, Player: Custom1, 4, 6, 8, swimming), their own animations left to
-- them when the mod didn't see the death: the ocean, sliding off a ledge, the desert's sand hole, the grinder
hm.SCRIPTED = { "Swim", "Sliding", "DesertHole", "Grinder", "Dead_Empty" }
function hm.scripted(mn)
  for _, p in ipairs(hm.SCRIPTED) do if mn:find(p, 1, true) then return p end end
end
-- proof the game has her dead since t, else nil: its death screen's intro playing, or done (FinishYouDieAnimation)
function hm.dead_proof(t)
  if (screen.youDieAt or -1) >= t then return "its YouDie animation done" end
  if not death_screen() then return end
  local on = screen.playing(dead_hud.get("w"))
  if #on > 0 then return "its intro playing: " .. table.concat(on, ", ") end
end
function hm.lethal_watch(pawn, mesh)
  local g = tune.gore or {}
  if not gore or g.enabled == false or g.woundAtHit == false or not goreCtx.glass then return end
  -- (an enemy's grab on her, followed while she lives: a death in it waits for its end, enemies.grab_now)
  local en = goreCtx.enemies
  if en and en.grab_tick and not hm.lethal then
    local started = os.clock()
    local ok, err = pcall(en.grab_tick, pawn, mesh)
    local ms = (os.clock() - started) * 1000
    if ms >= 10 then log(string.format("lethal watch: grab check %.0f ms", ms)) end
    if not ok then log("grab watch: " .. tostring(err)) end
  end
  -- (a death came after the hit: the cut was its own, undone with it at its end. A death that began 5 s or more after
  -- the hit left it on record, gore_cut not taking it, and her first tick up logged "she lived" and cleaned up again)
  if hm.lethal and hm.lethal.cut and (screen.deathAt or -1) >= hm.lethal.t then hm.lethal.cut = nil end
  -- (in a grab the game holds her death till it lets go: LIVED_S counts from there)
  local why = hm.lethal and hm.lethal.cut and not hm.lethal.grab and hm.plays_on(pawn, mesh, hm.lethal)
  if why then hm.lived(pawn, mesh, why) end
  local pct = goreCtx.glass.bar_pct(true)
  if pct and hm.barLost then
    log(string.format("HP bar: found %.1f s after the level loaded", os.clock() - hm.barLost))
    hm.barLost = nil
  end
  -- (the HUD looked for, 35 ms, when glass's back-off allows (1 s doubling to a minute) till it is found: it is kept
  -- after that, and a new one the game makes is taken without a search (glass.hud_made). A new level looks 5 s on
  -- (forget_world): this watch's own 30 s on top left the bar unread for up to a minute after a level load, a death
  -- in it cut late, at the ragdoll instead of the hit, playtest)
  if not pct and os.clock() >= (hm.barTry or 0) then
    pct = goreCtx.glass.bar_pct(false)
    hm.barTry = not pct and goreCtx.glass.bar_next and goreCtx.glass.bar_next() or os.clock() + 30
    if pct and hm.barLost then
      log(string.format("HP bar: found %.1f s after the level loaded (looked for)", os.clock() - hm.barLost))
      hm.barLost = nil
    end
  end
  if not pct then return end
  if pct ~= hm.barLast then hm.barLast, hm.barT = pct, os.clock() end
  if pct > 0.0005 then
    if hm.lethal and hm.lethal.cut then hm.lived(pawn, mesh, string.format("her HP bar back at %.3f", pct)) end
    hm.lethal = nil; hm.armed = true; return
  end
  -- a death the mod never saw: the death screen up with her bar at 0 and no ragdoll (a death show without a ragdoll
  -- key of the pak's). A fall damage death is taken over (hm.take: the mod's ragdoll, the death from there as any):
  -- from a 16 m drop the game's falling death (Landing_Height_Stiff_Damage, Custom5, P_Eve_Dead_Falling, its key at
  -- 0 s) gave none, she froze where she landed and the death screen came up at once (playtest, twice). Any other is
  -- named, so it is found (her swimming deaths and the desert's sand hole play their own animations)
  local lt = hm.lethal
  if lt and not lt.missed and os.clock() - lt.t > 0.1 and os.clock() >= (lt.screenAt or 0) then
    lt.screenAt = os.clock() + 0.1
    -- in an enemy's grab: the death waits till it lets go (its montage over) or grab.most s, then comes as any (the
    -- killing cut made at the hit already, the limb or head off while it holds her)
    if lt.grab then
      local most = ((tune.enemies or {}).grab or {}).most or 6
      local long = os.clock() - lt.grab.t0 >= most
      if not long and en and en.grab_holds(lt.grab) then return end
      log(string.format("lethal hit: %s's grab over after %.1f s (%s): her death now", lt.grab.cls,
        os.clock() - lt.grab.t0, long and string.format("waited the most, %s s", most) or lt.grab.mont and "its montage ended" or "it let go of her"))
      lt.grab, lt.t = nil, os.clock() - 0.15
      lt.from = try(function() return vof(pawn:K2_GetActorLocation()) end) or lt.from
    end
    -- (the death screen's widget is made with the level and reads visible all along: a 16 m fall leaving her at 1 HP,
    -- the bar at 0, was taken for a death and ragdolled her alive, the player walking off from her body, playtest.
    -- Her movement is no proof either: the game's falling death left it on, walking, 1.4 s on and more, and was never
    -- taken over (playtest). Proof is the death screen's intro playing or done (hm.dead_proof), or her movement off.
    -- Alive at 1 HP the watch goes on: a death later on the same bar is still found)
    local mm = try(function() return pawn.CharacterMovement.MovementMode end)
    local swim = mm == 4
    local proof = mm == 0 and "her movement off" or hm.dead_proof(lt.t)
    if not proof then
      if not lt.alive and hm.landAny and math.abs(lt.t - hm.landAny.t) < 1.5 then
        lt.alive = true
        log(string.format("lethal hit: her HP bar at 0 as she landed from a %.0f cm drop, her movement on (mode %s), "
          .. "the death screen not playing: alive at 1 HP so far, watched on", hm.landAny.drop, tostring(mm)))
      end
    elseif death_screen() then
      lt.missed = true
      local now = os.clock()
      local land = hm.landAny and (math.abs(lt.t - hm.landAny.t) < 1.5 or now - hm.landAny.t < 1.5) and hm.landAny
      local dm = hm.deadMsg and now - hm.deadMsg.t < 3 and hm.deadMsg
      local fall = land or (dm and hm.FALL_FX[dm.effect or -1])
      local a = tune.active or {}
      local mn = hm.montage(mesh)
      local what = string.format("%s, %s, playing %s", land and string.format("%.0f cm drop %.1f s before", land.drop,
        now - land.t) or "no drop", dm and hm.dead_what(dm) or "no death broadcast", mn or "no montage")
      -- any other death without a ragdoll is taken over too (0.5.0 report: enemy attacks went straight to the death
      -- screen, no ragdoll), cut as any death; her swimming and the scripted deaths (hm.SCRIPTED) stay the game's
      -- (still falling, no landing: the level's kill volumes, Custom4's Dead_Empty, warp her back to safe ground)
      -- A lethal physical hit while airborne is not evidence of a kill volume. Keep the game's
      -- named scripted deaths, but let the normal no-show fallback handle a confirmed hit.
      local scripted = mn and hm.scripted(mn) or not fall and mm == 3 and not lt.airHit and "falling, a kill volume" or nil
      local takes = a.enabled ~= false and not swim and not scripted
        and (not fall or a.fallRagdoll ~= false)
      if takes then
        hm.take = { why = string.format("%s: %s", fall and "fall damage" or "no ragdoll from its show", what), t = now,
          fall = fall and true or nil }
        log(string.format("death: the death screen up %.2f s after her HP bar hit 0 (%s) and no ragdoll (%s): the "
          .. "mod's own ragdoll instead", now - lt.t, proof, what))
      else
        log(string.format("death NOT seen: the death screen is up %.1f s after her HP bar hit 0 (%s) and she never "
          .. "ragdolled (%s%s); its death show has no ragdoll key of the pak's", now - lt.t, proof, what,
          swim and ", swimming" or scripted and (", a scripted death: " .. scripted) or ""))
        -- no ragdoll and no scripted cause: her death shows may not be ours any more (another death mod rewrote
        -- them after us); look again, and the re-run names the fields it fought over
        if goreCtx.tables and not swim and not scripted then pcall(goreCtx.tables.recheck_dead) end
      end
    end
  end
  -- only a bar seen above 0 while she lived and now at 0: right after a respawn it still reads 0, and the watch cut
  -- her there (playtest)
  if hm.lethal or not hm.armed then return end
  hm.armed = false
  hm.lethal = { t = os.clock(), from = try(function() return vof(pawn:K2_GetActorLocation()) end) }
  gore.blocking = hm.blocking()
  local ws = weapon_swing(mesh)
  local m = meshHit and os.clock() - meshHit.t <= 0.5 and meshHit or nil
  hm.lethal.airHit = m and m.loc and m.push and true or nil
  local at = ws and ws.at or (m and m.loc)
  if ws and ws.part and ws.pose and ws.pose[ws.part] then at = ws.pose[ws.part].t or at end
  hm.lethal.at = at
  -- (the blow seen: a blunt one crunches, a blade slices)
  local h = sw.explosion_hit(pawn, mesh) or sw.rock_blow(mesh) or sw.projectile_hit() or sw.death_projectile(mesh) or (ws and death_hit(pawn, mesh))
  if h and h.blast then hm.lethal.blast = h; at = h.loc; hm.lethal.at = at end
  if h and h.projectile then hm.lethal.projectile = h; at = h.loc; hm.lethal.at = at end
  local blunt = h and not h.made and sw.blunt_of(h)
  if at then gore.wound(pawn, mesh, at, blunt and "crunch" or nil) end
  log(string.format("lethal hit: her HP bar at 0, the wound %s", at and ("at " .. v3(at) .. (ws and ws.part and (" (" .. ws.part .. ")") or "")) or "nowhere (no blade seen)"))
  -- (what the enemies near her play: a grab's montage named in the log)
  local gb = en and en.grab_now and en.grab_now()
  if en and en.near_montages then log("lethal hit: near her: " .. tostring(select(2, pcall(en.near_montages, pawn)))) end
  if gb then
    hm.lethal.grab = { obj = gb.obj, mont = gb.mont, cls = gb.cls, t0 = os.clock() }
    -- (no montage: the grab lasts while its hand stays on her, enemies.grab_holds). The cut comes now as below, a
    -- limb falling off her while it holds her; her head, body and ragdoll and a split wait for it to let go
    log(string.format("lethal hit: in %s's grab (%s, %s on her for %.1f s): her death waits for it to let go, the cut now",
      gb.cls, gb.mn, gb.how, gb.last - gb.since))
  end
  -- gore.bluntRagdoll: a blunt killing blow cuts nothing, the death is a plain ragdoll (gore_cut)
  if g.bluntRagdoll == true and h and not h.made then
    local b, how = sw.blunt_of(h, true)
    if b then
      log("lethal hit: the blow is blunt (" .. how .. "): no cut, a plain ragdoll (bluntRagdoll)")
      hm.lethal.blunt, hm.lethal.roll, hm.lethal.judged = true, "none", true
      return
    end
  end
  -- a limb the blade took is cut now, on her animated body (gore.blow's h.early), and opens
  -- over openTime; her head and body in a grab and a split wait for the death, and so do the blow's further cuts (gore.release_held at the death)
  if g.cutAtHit == false or g.sliceOnDeath == false then return end
  if math.random() > (g.sliceChance or 1.0) then hm.lethal.roll = "none"; return end
  hm.lethal.near = gore.near_odds(mesh, h, at)
  hm.lethal.roll = hm.death_roll(ws ~= nil, hm.lethal.near)
  -- a blunt blow seen smashes the part it landed on instead, whatever the roll (blunt_of)
  if h and not h.made then
    h.early = true
    if h.push or h.dir then gore.aim(h.push or h.dir) end
    local done, later = sw.smash_kill(pawn, mesh, h, "death")
    -- (her body waits for her death and its ragdoll, smashed there)
    hm.lethal.judged = later ~= "later"
    if done then hm.lethal.cut, hm.lethal.h = true, h; return end
    if later == "later" then hm.grab_keep(h); return end
  end
  if hm.lethal.roll ~= "blade" then return end
  h = h or death_hit(pawn, mesh)
  if not (h and not h.made and (h.n or (h.dir and h.fwd))) then return end
  h.early = true
  -- (in a grab her head and body cuts wait too, as a split does: the finisher still poses her neck and waist)
  h.grab = hm.lethal.grab and true or nil
  local fly = h.push or h.dir
  if fly then gore.aim(fly) end
  local ok, err = pcall(gore.blow, pawn, mesh, h, "death")
  h.grab = nil
  if ok and err then hm.lethal.cut, hm.lethal.h = true, h
  elseif ok then hm.grab_keep(h)
  else log("lethal hit: early cut failed: " .. tostring(err)) end
end
-- a killing blow in a grab whose cut waits for her death (a split, her head or body): kept for it, as the grab can hold her
-- for longer than death_hit remembers a blow (its later hits would be taken instead). gore.blow carries its plane
-- from her pose at the blow to her pose then (h.pose)
function hm.grab_keep(h)
  if not (hm.lethal.grab and h) then return end
  h.early = nil
  hm.lethal.held = h
end

-- tune.gore.lowArm: a hit that leaves her HP bar under lowArm.below (a quarter) takes an arm off where she stands
-- (lowArm.side: hit, the side the blow landed on; left, right or either), once till it is back: it grows back out of her shoulder at a camp rest
-- (lowArm.regrow s), or comes back at her next life (the death's end undoes every cut). Meanwhile, with the left arm
-- off (lowArm.noHealGun) she can't use heal items or shoot, with the right one (lowArm.noSword) she can't use her sword
hm.LOW_BONES = { left = "Bip001-L-UpperArm", right = "Bip001-R-UpperArm" }
hm.lowSide = "left" -- the arm cut off (hm.lowCut), or last cut
-- s her HP bar holds still under the mark before the arm goes (low_arm: a killing blow slides it on to 0)
hm.LOW_SETTLE = 0.3
hm.LOW_ZERO_S = 1.5
-- a part cut off her alive grows back at a camp rest (hm.rest_watch: Lose Arm at Low HP's arm, F9's limbs, head and
-- upper body), its joints one after another from the root (sbslice Z takes three)
hm.GROW_JOINTS = {
  ["Bip001-L-UpperArm"] = { "Bip001-L-UpperArm", "Bip001-L-Forearm", "Bip001-L-Hand" },
  ["Bip001-R-UpperArm"] = { "Bip001-R-UpperArm", "Bip001-R-Forearm", "Bip001-R-Hand" },
  ["Bip001-L-Forearm"] = { "Bip001-L-Forearm", "Bip001-L-Hand" },
  ["Bip001-R-Forearm"] = { "Bip001-R-Forearm", "Bip001-R-Hand" },
  ["Bip001-L-Thigh"] = { "Bip001-L-Thigh", "Bip001-L-Calf", "Bip001-L-Foot" },
  ["Bip001-R-Thigh"] = { "Bip001-R-Thigh", "Bip001-R-Calf", "Bip001-R-Foot" },
  ["Bip001-L-Calf"] = { "Bip001-L-Calf", "Bip001-L-Foot" },
  ["Bip001-R-Calf"] = { "Bip001-R-Calf", "Bip001-R-Foot" },
  ["Bip001-Head"] = { "Bip001-Head" },
  ["Bip001-Spine1"] = { "Bip001-Spine1", "Bip001-Spine2", "Bip001-Neck" },
}
-- a drop of her HP bar is a blow unless she landed from LOW_LAND_CM or higher within LOW_LAND_S s of it with no hit on
-- her mesh this long before it (or while it settles): the landing's fall damage takes no arm
hm.LOW_HIT_S = 0.5
hm.LOW_LAND_S, hm.LOW_LAND_CM = 1, 200
-- her death as the game tells it: SBNetworkPlayerController:ClientBroadcast_ActorDead(inTurn, InActorGUID,
-- inHitSkillID, inEffectID, inProjectileID, inCauseActorGUID, inDoNotResetSPExp, inHaveRevivalItem) as the SDK dump
-- declares it. What killed her goes in the log (and a fall damage effect counts for hm.take); the game may not send
-- it in single player at all (glass.lua's calls of it did nothing), the death screen is what hm.lethal_watch trusts
hm.FALL_FX = { [8000003] = "Landing_Height_Damage", [8000005] = "Landing_Height_Stiff_Damage" }
function hm.dead_what(d)
  return string.format("the game's death broadcast: effect %s%s, skill %s, projectile %s", tostring(d.effect),
    hm.FALL_FX[d.effect or -1] and (" " .. hm.FALL_FX[d.effect]) or "", tostring(d.skill), tostring(d.proj))
end
function hm.on_actor_dead(_, _turn, guid, skill, effect, proj, cause)
  local function num(p) local v = try(function() return p:get() end); return type(v) == "number" and v or nil end
  local pawn = os.clock() - pawnSeen < 0.5 and cachedPawn or nil
  local mine = pawn and try(function() return pawn.BroadcastSpawnInfo.ActorGuid end)
  local g = num(guid)
  if not (mine and g and g == mine) then return end
  hm.deadMsg = { t = os.clock(), skill = num(skill), effect = num(effect), proj = num(proj), cause = num(cause) }
  log("death: " .. hm.dead_what(hm.deadMsg))
end
-- the game's own blocks on her (ESBActorState, counted on her native actor: sbslice a): heal items, and the gun's shots
-- (they use up bullet items)
hm.LOW_STATES = { { "heals", 67 }, { "shots", 100 } } -- ActorState_BlockItemUseHeal, ActorState_BlockItemUseBullet
-- (the right arm's: no sword, the game's own stance for it, tables.lua's sword_gate)
-- The stance is the game's own, and its end ends it whoever put it on: in Altess Levoire (AltesLab_P), where the game
-- takes her sword, the arm back or her death gave the sword back (reported). So her sword is left to the game when she
-- was in that stance already as the arm went, and when she is in Altess Levoire, swordless, as the arm comes back (the
-- game's block may have come on since the cut, inside it too: no telling the two apart), the end waits
-- (hm.swordLater) till she leaves Altess Levoire or is out of the stance (the game gave it back itself)
dofile("ue4ss/Mods/StellarBladeGore/Scripts/low_arm.lua")(hm, screen, goreCtx,
  function() return gore end, function() return tune end, function() return meshHit end, weapon_swing, try, valid, dist, log)
-- the test keys (Alt+F7 / Alt+F8): Lose Arm at Low HP's cut now, that arm, as a hit under the mark would. Needs Lose
-- Arm at Low HP on (off, its tick lifts the blocks) and no arm of its off already
function hm.low_test(side)
  local key = "Test: Lose " .. (side == "left" and "Left" or "Right") .. " Arm"
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not (gore and valid(mesh)) then log(key .. ": no Eve or no gore.lua"); return end
  local g = tune.gore or {}
  if g.enabled == false or (g.lowArm or {}).enabled ~= true then log(key .. ": Lose Arm at Low HP is off (F3 → Gameplay)"); return end
  if active then log(key .. ": she is dead"); return end
  if hm.lowCut then log(key .. ": her " .. hm.lowSide .. " arm is already off (a camp rest or her next life brings it back)"); return end
  if gore.has_cut(mesh, hm.LOW_BONES[side]) then log(key .. ": that arm is already off (F9)"); return end
  if hm.regrow or hm.ghost then log(key .. ": an arm is still growing back"); return end
  hm.low_cut(pawn, mesh, side, nil, key)
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
  -- (a death stays the game's: F9 made it a test ragdoll's, so the HUD and the held revive screen came back and,
  -- revived from it, she was left a ragdoll with no control, reported. F7's and F11's are test ones already)
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

-- F10: a random remaining part smashed, on a test ragdoll so the torso can be tested too.
function hm.smash_key()
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not (gore and valid(mesh)) then log("Test: Blunt Smash: no Eve or no gore.lua"); return end
  if (tune.gore or {}).enabled == false then log("Test: Blunt Smash: gore is off"); return end
  if not active then sandbox_ragdoll() end
  gore.smash(pawn, mesh, nil, "test")
end

-- Alt+Delete: ragdoll her and cut her diagonally (gore.diagonal), from over her right shoulder, then her left, ...
hm.diagSide = "L"
function hm.diagonal_key()
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not (gore and valid(mesh)) then log("Test: Diagonal: no Eve or no gore.lua"); return end
  if not active then sandbox_ragdoll() end
  hm.diagSide = hm.diagSide == "R" and "L" or "R"
  log("Test: Diagonal: from over her " .. (hm.diagSide == "R" and "right" or "left") .. " shoulder")
  gore.diagonal(pawn, mesh, nil, "test", hm.diagSide)
end

-- Delete: ragdoll her and cut along a made-up blade, as a killing blow would (gore.blow): a swing level, slanted or
-- straight down through a random part of her, the attacker standing where the camera looks from
local function sandbox_blade()
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not (gore and valid(mesh)) then log("Delete: no Eve or no gore.lua"); return end
  if not active then sandbox_ragdoll() end
  local rot = try(function() return pawn:GetControlRotation() end)
  local yaw = math.rad(rot and rot.Yaw or 0)
  local fwd = { X = math.cos(yaw), Y = math.sin(yaw), Z = 0 }
  local side = math.random() < 0.5 and -1 or 1
  local a = math.rad(({ 0, 30, 60, 90 })[math.random(4)])
  local dir = { X = -math.sin(yaw) * side * math.cos(a), Y = math.cos(yaw) * side * math.cos(a), Z = -math.sin(a) }
  local bone, loc = swing_at(mesh)
  if not loc then log("Delete: no " .. bone); return end
  log(string.format("Delete: blade through %s, %d deg down", bone, math.floor(math.deg(a) + 0.5)))
  gore.aim(dir)
  gore.blow(pawn, mesh, { t = os.clock(), loc = loc, dir = dir, fwd = fwd, attack_dir = 0, bone = bone }, "F5")
end

-- more falls for an animated death: the data mod's death shows made from her knockdown falls (Ragdoll/EveDeath_*,
-- no ragdoll key; the knockdown shows themselves are untouched). One is picked at random with her own death show
-- (tune.active.animatedPool) and played over it
local DEATH_FALLS = { "Knock_Down_Start", "Knock_Down_Start1", "Knock_Down_Forward", "Knock_Down_Backward",
  "KnockDown_S_Fw", "KnockDown_S_Bw", "KnockDown_Tumble_Fw", "KnockDown_Tumble_Bw" }
local forceFall = nil -- the fall to play next ("own" = her death show's own)
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

-- F6: a death made to test the struggle (struggle.lua): each press the next of STRUGGLE_TESTS, a ragdoll death with
-- those cuts, so the struggle always comes (deathMoves or not: the test switches it on for that death; a death show
-- with its cut rolled ended in its animated fall or a split, no struggle, most presses). She lies till F8
local STRUGGLE_TESTS = {
  { what = "her right arm off at the shoulder", bones = { "Bip001-R-UpperArm" } },
  { what = "her left leg off at the hip", bones = { "Bip001-L-Thigh" } },
  { what = "cut across the waist", bones = { "Bip001-Spine1" } },
  { what = "her left arm and right leg off", bones = { "Bip001-L-UpperArm", "Bip001-R-Thigh" } },
  { what = "both legs off", bones = { "Bip001-L-Thigh", "Bip001-R-Thigh" } },
  { what = "her left forearm off at the elbow", bones = { "Bip001-L-Forearm" } },
  { what = "no cut: sitting up only", bones = {}, alone = true },
}
local f5_n = 0
local f5_test = nil -- the struggle test F6 asked for: its death starts on the next tick (game_tick)
local function sandbox_death()
  local pawn = find_eve()
  if not pawn then log("F6: no Eve"); return end
  if active then log("F6: she is already down (F8 gets her up)"); return end
  f5_n = f5_n % #STRUGGLE_TESTS + 1
  f5_test = STRUGGLE_TESTS[f5_n]
  log(string.format("F6: struggle test %d of %d: %s", f5_n, #STRUGGLE_TESTS, f5_test.what))
end

-- Test: Animated Death (Alt+F6): the game's own death shows played on her, the next each press, so a mod replacing
-- their animations (death_anim_P: Result_Stand_Dead, Eve_Stand_Dead2/3, Eve_Dead_DownFaceUp/Down) shows in the mod's
-- animated death. The death starts with the show (on her alive its ragdoll key never fired: waited for 3 s, the
-- death and its cut came as the animation ended, playtest), as animated whatever active.animated says, her own fall
-- (no knockdown fall over it), and no cut: a split, a beheading or a leg takes her to the ragdoll, and the
-- animation is what is tested. She lies till F8
-- (on hm: main.lua is at Lua's 200 locals)
hm.at = { n = 0, on = nil, -- on: { t, what }, the show it played, till its death starts
  tests = {
    { show = "CH_P_EVE_01/Basic/P_Eve_Dead", what = "her standing death (P_Eve_Dead)" },
    { show = "CH_P_EVE_01/Basic/P_Eve_Dead2", what = "a hit's death (P_Eve_Dead2)" },
    { show = "CH_P_EVE_01/Basic/P_Eve_Dead3", what = "a heavier hit's death (P_Eve_Dead3)" },
    { show = "CH_P_EVE_01/Basic/Eve_Dead_Down", what = "her death lying down (Eve_Dead_Down)" },
  } }
function hm.at.key()
  local pawn = find_eve()
  if not pawn then log("Test: Animated Death: no Eve"); return end
  if active then log("Test: Animated Death: she is already down (F8 gets her up)"); return end
  if hm.at.on then return end
  hm.at.n = hm.at.n % #hm.at.tests + 1
  local t = hm.at.tests[hm.at.n]
  log(string.format("Test: Animated Death %d of %d: %s", hm.at.n, #hm.at.tests, t.what))
  if not play_show(pawn, t.show, "Test: Animated Death") then log("Test: Animated Death: the show didn't play"); return end
  hm.at.on = { t = os.clock(), what = t.what }
end
local function gore_cut(pawn, mesh, h, hit)
  local g = tune.gore or {}
  if hm.lethal and os.clock() - hm.lethal.t < 5 then
    if h and h.blast and hm.lethal.blast ~= h then
      hm.lethal.cut, hm.lethal.judged = nil, nil
      gore.held, gore.held_sword = {}, nil
      hm.lethal.blast = h
    end
    if hm.lethal.blast then
      h = hm.lethal.blast
      h.early, hm.lethal.held = nil, nil
    end
  end
  if not (h and h.blast) and hm.lethal and os.clock() - hm.lethal.t < 5 and hm.lethal.projectile then
    h = hm.lethal.projectile
    h.early = nil
  end
  -- cut at the hit already (hm.lethal_watch): the blow's further cuts and her sword's now
  if hm.lethal and hm.lethal.cut and os.clock() - hm.lethal.t < 5 then
    hm.lethal.cut = nil
    log(string.format("death: the killing cut was made at the hit, %d more of the blow now", gore.release_held()))
    return
  end
  -- the killing blow of a grab, its cut held for her death (hm.grab_keep): that blow, not the grab's later hits
  local held = hm.lethal and os.clock() - hm.lethal.t < 5 and hm.lethal.held
  if held then
    hm.lethal.held = nil
    h = held
    h.early = nil -- the deferred torso hit is being replayed at the death now
    log("death: the cut of the killing blow in the grab now")
  end
  -- fall damage cuts nothing (no blade in it): a death taken over after a drop (hm.take), or her HP bar at 0 within
  -- LOW_LAND_S of landing from LOW_LAND_CM or more with no hit on her mesh (low_arm's rule: a kill after a jump still
  -- cuts). The 16 m drop's death rolled both legs off on the odds (playtest); hits after it still cut
  local fell = hm.fellAt and os.clock() - hm.fellAt < 1
  hm.fellAt = nil
  local t0 = hm.lethal and os.clock() - hm.lethal.t < 5 and hm.lethal.t or os.clock()
  local land = hm.landAny and math.abs(hm.landAny.t - t0) < hm.LOW_LAND_S and hm.landAny
  local struck = meshHit and meshHit.t >= t0 - hm.LOW_HIT_S
  if not (h and h.blast) and (fell or (land and not struck)) then
    log(string.format("death: fall damage (%.0f cm drop%s): no cut, a plain ragdoll", land and land.drop or 0,
      fell and ", taken over" or ""))
    return
  end
  -- gore.bluntRagdoll: a blunt killing blow (judged at the lethal hit, else now) leaves her whole, a plain ragdoll,
  -- and hits after it cut nothing either
  if g.bluntRagdoll == true then
    local lb = hm.lethal and os.clock() - hm.lethal.t < 5 and hm.lethal.blunt
    local b, how = lb, "judged at the lethal hit"
    if not lb and h and not h.made then b, how = sw.blunt_of(h, true) end
    if b then
      log("death: the blow is blunt (" .. how .. "): no cut, a plain ragdoll (bluntRagdoll)")
      ah.blunt = true
      return
    end
  end
  -- a laser trap's beam on her: cut along it (sw.laser_hit)
  if g.sliceOnDeath ~= false and not (h and h.blast) then
    local lh = sw.laser_hit(pawn, mesh)
    gore.mark("laser")
    if lh then
      local ok, cut = pcall(gore.blow, pawn, mesh, lh, "death")
      if not ok then log("death: laser cut failed: " .. tostring(cut)) end
      if ok and cut then return end
      log("death: the laser's plane took nothing off her, on to the odds")
    end
  end
  -- what comes off flies the way the blow went: from the attacker through her, else the swing, else her push
  local fly = h and (h.push or h.dir)
  if fly and fly.X == 0 and fly.Y == 0 and fly.Z == 0 then fly = nil end
  fly = fly or try(function() local v = pawn.RagdollInfo.ImpulseValue; return { X = v.X, Y = v.Y, Z = v.Z } end)
  gore.aim(fly)
  -- a blunt killing blow smashes the part it landed on (blunt_of; at the lethal hit already when the blow was seen
  -- then). smash.always: every death (no blow: a part at random)
  local judged = hm.lethal and os.clock() - hm.lethal.t < 5 and hm.lethal.judged
  local always = (g.smash or {}).always == true
  local roll = hm.lethal and os.clock() - hm.lethal.t < 5 and hm.lethal.roll
  -- Smash replaces the cut, so it obeys its chance too (including a failed roll at the lethal hit).
  -- With Smash off the normal cut keeps its RNG order; near_odds can itself sample a plane from the hit.
  local checkedChance = false
  if (g.smash or {}).enabled == true and g.sliceOnDeath ~= false and (h or always) and not judged then
    if not roll then
      checkedChance = true
      if (g.sliceChance or 1.0) <= 0 or math.random() > (g.sliceChance or 1.0) then roll = "none" end
    end
    if roll ~= "none" and sw.smash_kill(pawn, mesh, h or {}, "death") then return end
  end
  if fly then gore.aim(fly) end
  -- rolled at the lethal hit already, else now. The odds' split share stands whatever the blade (the glass cannon's
  -- too): a blade decides only the rest. It needed a blow from above, which single player never reports, or a blade
  -- down her length, rare: no split in many deaths (reported)
  -- (the odds shaped by where the blow landed, gore.near_odds: the killing blow's own if seen, else the lethal hit's)
  gore.mark("smash")
  local ok, near = pcall(gore.near_odds, mesh, h, hit)
  near = ok and near or (hm.lethal and roll and hm.lethal.near) or nil
  gore.mark("odds")
  if near then log("death: odds by the hit: " .. near.why) end
  if not roll then
    roll = (g.sliceOnDeath == false or (not checkedChance and math.random() > (g.sliceChance or 1.0)))
      and "none" or hm.death_roll(h ~= nil and not h.made, near)
  end
  -- a split rolled where the killing blade crossed both her arms: they come off instead, armsOverSplit of the time
  if roll == "split" and not gore.only_split() and h and not h.made and math.random() < (g.armsOverSplit or 0.6) then
    h.armsOnly = true
    local ok, cut = pcall(gore.blow, pawn, mesh, h, "death")
    h.armsOnly = nil
    if not ok then log("death: both arms check: " .. tostring(cut)) end
    if ok and cut then log("death: split rolled, the blade crossed both arms: they came off instead"); return end
  end
  if roll == "split" then
    log(string.format("death: split rolled (%s in the odds), down her length", tostring((g.death or {}).split)))
    if gore.split(pawn, mesh, hit or (h and h.loc), split_normal(h), "death") then return end
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
      if normal and g.deathSplit ~= false and g.noSplits ~= true then gore.split(pawn, mesh, at, normal, "death"); return end
      if gore.slice(pawn, mesh, at, "death", "torso") then return end
    elseif gk.bone then
      if gore.slice_bone(pawn, mesh, gk.bone, at, "death") then return end
    end
  end
  if roll ~= "none" then
    -- a killing blow the game told us about cuts along the blade (gore.blow), else the roll below. A made-up one (no
    -- skill hit, no weapon swing seen: a guessed plane through a guessed part of her, most of the time her spine) is
    -- rolled: cut along, it took her body at most deaths, the legs almost never (playtest)
    -- (bladeFollow: the share of deaths with a blade seen that it decides; the rest roll the odds as well, near
    -- where it hit: a blade mostly crossed her body, and waist cuts and splits were nearly every death, playtest)
    if h and h.made then
      log(string.format("death: no blade seen (blow from %s), rolling the odds", tostring(h.src)))
    elseif h and roll ~= "blade" then
      log(string.format("death: last hit %.2f s ago, its blade left aside (%s), rolling the odds", os.clock() - h.t,
        roll == "split" and "the split failed" or "bladeFollow"))
    elseif h then
      log(string.format("death: last hit %.2f s ago (hook called %d times, %d on Eve), cutting along the blade",
        os.clock() - h.t, hitCalls, hitsOnEve))
      if gore.blow(pawn, mesh, h, "death") then return end
    end
    local normal = split_normal(h)
    -- a death always takes something off
    local kind = pick_kind(false, near, (g.diagonal or {}).enabled ~= false and g.deathSplit ~= false and g.noSplits ~= true)
    -- from above, the body is cut down through her, not across the waist (a stomp's level cut, playtest). Not on a
    -- made-up blow: it comes from the nearest enemy, mostly "from above", and turned most waist cuts into splits
    if normal and kind == "torso" and g.noSplits ~= true and g.deathSplit ~= false and not (h and h.made) then
      log("death: rolled torso on a blow from above, split down her instead")
      kind = "split"
    end
    log(string.format("death: last hit %s (hook called %d times, %d on Eve), from above %s, rolled %s",
      h and string.format("%.2f s ago", os.clock() - h.t) or "none", hitCalls, hitsOnEve, tostring(normal ~= nil), kind))
    if kind == "split" then
      gore.split(pawn, mesh, hit or (h and h.loc), normal, "death")
    elseif kind == "diagonal" then
      gore.diagonal(pawn, mesh, hit or (h and h.loc), "death")
    else
      if gore.slice(pawn, mesh, hit, "death", kind) and kind == "limb" then gore.more_limbs(pawn, mesh, hit, "death") end
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
  gore.mark("guard")
  gore_cut(pawn, mesh, h, hit)
  gore.mark("cut chosen")
  -- a blow through her guard breaks her sword, whatever cut it made (a split, a rolled one with no blade seen)
  if gore.blocking and rag and rag.weapon_cut and not rag.sword_split() then
    local at = (h and h.loc) or hit or try(function() return vof(mesh:GetSocketLocation(FName("Bip001-R-Hand"))) end)
    local n = (h and h.n) or (h and h.dir) or { X = 0, Y = 0, Z = 1 }
    if at then
      local ok, err = pcall(rag.weapon_cut, mesh, at, unit(n) or n, gore.blocking)
      if not ok then log("weapon cut: " .. tostring(err)) end
    end
  end
  gore.mark("her sword")
  if not gore.splitting() then
    gore.on_hit(pawn, mesh, hit or try(function() return mesh:GetSocketLocation(FName("Bip001-Spine2")) end))
  end
  gore.mark("blood")
end

-- work for the next game-thread tick (game_tick below): the death's cut, a frame after it starts
local pending = {}
-- the keys (keys.lua: rebindable, tune.keys; each run on the game thread, a test key's only with dev on). Without
-- keys.lua none of them work: told in the log
local function key_on(id, fn) if goreCtx.keys then goreCtx.keys.on(id, fn) end end
function screen.key_name(id) return goreCtx.keys and goreCtx.keys.show(goreCtx.keys.binding(id)) or id end
key_on("ragdoll", sandbox_ragdoll)
key_on("face", sandbox_face)
key_on("recover", function() sandbox_recover() end)
key_on("menu", function() if goreCtx.gui then goreCtx.gui.toggle(find_eve()) end end)
-- P in a death: the death keeps the key from photo mode, so sbslice.dll enters photo mode itself (its answer: the
-- manager and the gates the key's path checks, read before). A death not held yet is held first, as Shift+F4 does:
-- the death screen and getting up would come on over photo mode
-- Photo mode open already (screen.photoOn: its view goes to its own pawn only once its menu is up, seconds after):
-- the key there is photo mode's own. Asked again it came back busy and let her hold go with photo mode still on:
-- she woke and answered its pawn again, and the camera pushed her about, 100-350 cm, till she stood up in the air
-- (Nexus log, P pressed in photo mode). A hold this press didn't take isn't let go either.
-- A hold P took is let go as photo mode closes (screen.photo_unhold), or at once when it didn't open: kept, the death
-- screen never came back and she couldn't respawn, with nothing to say Shift+F4 was needed (Nexus report). A hold made
-- with Shift+F4 (before or during photo mode) stays
-- Photo and hold controls use live lifecycle state supplied by the main loop.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/photo_controls.lua")(screen, goreCtx, camera, valid, try, log, vof,
  find_eve, function() return active end, function() return saved.manual end, function() return tune end,
  function() return gore end, function() return rag end, function() return cachedPawn end,
  function() return polls * POLL_MS / 1000 + ahead end)
key_on("photo", function() screen.photo_key(screen.key_name("photo")) end)
-- and the controller's photo mode combo, which the death keeps from photo mode too and UE4SS's key binds can't see:
-- the game's PhotomodeTwoKey1 + PhotomodeTwoKey2 (D-pad left + R1 unless rebound), both down, polled each frame of a
-- death. Read from her controller's input mappings at each death's first look
key_on("hold", function()
  if not active or saved.manual then log(screen.key_name("hold") .. ": no death"); return end
  screen.hold(screen.key_name("hold"))
end)
-- Esc on her death: fast forward to the death screen (tune.deathSkip; parked for now, untested)
-- (a key "skip": if active then skip_start(find_eve()) end)
-- Ultra Violence (Nexus 3942) has F9 (its menu), F10 and F11 too: its cut/split conflicts default to Alt.
-- Blunt Smash stays on the explicitly chosen F10; Hit Mark is always Alt+F10.
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
screen.uv = uv_on
goreCtx.uv = function() return screen.uv end
if goreCtx.keys then goreCtx.keys.uv = uv_on end
if uv_on then log("Ultra Violence is on: Cut and Split default to Alt+F9 and Alt+F11; Blunt Smash is F10. Rebind conflicts in Keys.") end
key_on("slice", sandbox_slice)
key_on("smash", hm.smash_key)
-- Alt+F10: a living hit's mark on a part at random, on its side facing the camera (tune.gore.hitMarks)
key_on("mark", function()
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not (gore and valid(mesh)) then log("Test: Hit Mark: no Eve or no gore.lua"); return end
  local w = gore.MARK_AT[math.random(#gore.MARK_AT)]
  local a = try(function() return vof(mesh:GetSocketLocation(FName(w.bone))) end)
  local b = try(function() return vof(mesh:GetSocketLocation(FName(w.to))) end)
  local cam = try(function()
    local gs = goreCtx.statics()
    return vof(gs:GetPlayerCameraManager(pawn, 0):GetCameraLocation())
  end)
  if not (a and b and cam) then log("Test: Hit Mark: no bone or camera"); return end
  local mid = { X = (a.X + b.X) / 2, Y = (a.Y + b.Y) / 2, Z = (a.Z + b.Z) / 2 }
  local to = unit(sub(cam, mid))
  local at = to and { X = mid.X + to.X * w.r * 2, Y = mid.Y + to.Y * w.r * 2, Z = mid.Z + to.Z * w.r * 2 } or mid
  local dir = { X = math.random() - 0.5, Y = math.random() - 0.5, Z = math.random() - 0.5 }
  log("Test: Hit Mark: hit mark on " .. w.bone)
  gore.hit_mark(pawn, mesh, at, dir, hm.pct)
end)
key_on("split", sandbox_split)
key_on("diagonal", hm.diagonal_key)
end
key_on("death", sandbox_death)
key_on("animDeath", hm.at.key)
key_on("loseLeft", function() hm.low_test("left") end)
key_on("loseRight", function() hm.low_test("right") end)
key_on("blade", sandbox_blade)
-- the enemy spawner (enemies.lua): F5 spawns the kind picked in front of her, Insert picks the next, Home opens
-- the spawner window, End kills the one nearest her
key_on("spawn", function()
  if goreCtx.enemies and find_eve() then goreCtx.enemies.spawn_pick(find_eve()) end
end)
key_on("nextEnemy", function() if goreCtx.enemies then goreCtx.enemies.next_pick() end end)
key_on("spawner", function() if goreCtx.enemies then goreCtx.enemies.toggle_window() end end)
key_on("kill", function()
  if goreCtx.enemies and find_eve() then goreCtx.enemies.kill_nearest(find_eve()) end
end)
-- the glass cannon mode on and off (glass.lua, tune.glassCannon)
key_on("glass", function() if goreCtx.glass then goreCtx.glass.toggle() end end)
if goreCtx.keys then goreCtx.keys.register() else log("keys: keys.lua didn't load, no key of the mod works") end

-- who touches the mesh around death/respawn: Blueprint-level destroys and Eve's (re)init events
local hooked = false
-- Cloth reset owns its scheduling and collision restoration on screen state.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/cloth_reset.lua")(screen, goreCtx, hm,
  function() return active end, function() return rag end, function() return gore end, sandbox_recover, try, valid, log)

local function hook_once()
  if hooked then return end
  hooked = true
  local function h(path, label)
    local ok, err = pcall(RegisterHook, path, function(ctx)
      local o = try(function() return ctx:get() end)
      lg.v(string.format("HOOK %s on %s", label, name(o)))
      if label == "NotifyBP_ReInitActor" and after >= 0 then respawned, after, lastRecover, screen.stuck.at = true, 0, -100, nil end
      -- the game respawning her while she is still down (its death screen's button never seen): got up at once, not
      -- broken and with her weapon on the floor for the 1-2 s till the fallback timer (playtest)
      if active and label == "NotifyBP_ReInitActor" then screen.respawn = true end
      if label ~= "NotifyBP_InitActor" then screen.cloth_soon(label) end
    end)
    log(string.format("hook %s: %s", label, ok and "ok" or tostring(err)))
  end
  -- no native hooks on K2_DestroyComponent/K2_DestroyActor: reading the dying object there crashed the game
  local bp = "/Game/Art/Character/PC/CH_P_EVE_01/Blueprints/CH_P_EVE_01_Blueprint.CH_P_EVE_01_Blueprint_C:"
  for _, f in ipairs({ "NotifyBP_ReInitActor", "NotifyBP_InitActor", "NotifyBP_SetMesh", "ApplyMeshInfo" }) do
    h(bp .. f, f)
  end
  for _, f in ipairs({ "OnPhysicsShapeHit", "OnCollisionOriginBeginOverlap" }) do
    local path = "/Script/SB.SBProjectile:" .. f
    local okc, errc = pcall(RegisterHook, path, function(...)
      local ok2, e = pcall(sw.projectile_collision, ...)
      if not ok2 then log("projectile collision hook error: " .. tostring(e)) end
    end)
    log("hook projectile " .. f .. ": " .. (okc and "ok" or tostring(errc)))
  end
  local projectile_fn = "/Script/SB.SBNetworkPlayerController:ClientBroadcast_ProjectileHitResult"
  local okp, errp = pcall(RegisterHook, projectile_fn, function(...)
    local ok2, e = pcall(sw.projectile_event, ...)
    if not ok2 then log("projectile hit hook error: " .. tostring(e)) end
  end)
  log("hook ClientBroadcast_ProjectileHitResult: " .. (okp and "ok" or tostring(errp)))
  local dead_fn = "/Script/SB.SBNetworkPlayerController:ClientBroadcast_ActorDead"
  local okd, errd = pcall(RegisterHook, dead_fn, function(...)
    local ok2, e = pcall(hm.on_actor_dead, ...)
    if not ok2 then log("death broadcast hook error: " .. tostring(e)) end
  end)
  log("hook ClientBroadcast_ActorDead: " .. (okd and "ok" or tostring(errd)))
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
  lg.v(string.format("p%03d %s", polls, table.concat(parts, " ")))
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
local function animated_death(pawn, mesh, hit)
  local a = tune.active or {}
  if a.enabled == false or (a.animated == false and not hm.at.on) then return false end
  -- with the cuts off nothing would ever switch her fall to the ragdoll: a plain ragdoll, as the menu says (reported)
  if (tune.gore or {}).enabled == false then
    log("death: cuts off, the ragdoll")
    return false
  end
  local marked, v = animated_marker(pawn)
  if not marked then
    log(string.format("death: ragdoll show (ImpulseLimitVelocity %s)", tostring(v)))
    return false
  end
  -- The game's light-hit show may be marked animated even when a projectile killed her. Keep its
  -- already-running ragdoll; the lethal-watch record survives longer than the immediate hit event.
  local lethal = hm.lethal and os.clock() - hm.lethal.t < 5 and hm.lethal.projectile
  if not hm.at.on and ((hit and (hit.projectile or hit.rock)) or (lethal and lethal.projectile)) then
    log("death: projectile hit, the ragdoll instead of an animated fall")
    return false
  end
  -- in the air: her fall animation played on mid-air and she sank at 1.2 m/s for 3 s (thirty-fifth playtest)
  if try(function() return pawn.CharacterMovement:IsFalling() end) then
    log("death: animated show in the air, the ragdoll instead")
    return false
  end
  -- killed in mid-air: the death show stops her movement before this, so it no longer says falling, and a floor
  -- further than the trace reaches reads as unknown. She hung in the air playing her fall (0.4.1 report): airborne
  -- on any of her last ticks alive (hm.airT) is the ragdoll too
  if hm.airT and os.clock() - hm.airT < 0.5 then
    log(string.format("death: airborne %.2f s before it, the ragdoll instead", os.clock() - hm.airT))
    return false
  end
  -- fall damage: the landing's own damage (Landing_Height_Damage) leaves her at 1 HP as the game does (playtest with
  -- the mod off), and a high drop's (Landing_Height_Stiff_Damage) plays P_Eve_Dead_Falling, a ragdoll already; a
  -- death soon after a drop (the last HP to a hit as she lands) played her animated fall where she landed
  if a.fallRagdoll ~= false and hm.land and os.clock() - hm.land.t < (a.landWindow or 2) then
    log(string.format("death: %.2f s after landing from a %.0f cm drop (fall damage), the ragdoll instead",
      os.clock() - hm.land.t, hm.land.drop))
    return false
  end
  -- nor with her feet off the floor while her movement doesn't say falling (killed in mid-air, it was already off):
  -- the fall played where she died, up in the air, and she hung there (0.4.0 report)
  local feet = try(function() local l = mesh:K2_GetComponentLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
  local over = feet and rag and rag.over_floor and rag.over_floor(pawn, feet)
  if over and over > 30 then
    log(string.format("death: animated show with her feet %.0f cm over the floor, the ragdoll instead", over))
    return false
  end
  try(function() mesh:SetAllBodiesSimulatePhysics(false) end)
  try(function() mesh:SetSimulatePhysics(false) end)
  -- a part cut off her while she lived (tune.gore.lowArm, F9) simulates on, where it lies: turned off with the rest,
  -- the arm lying on the floor went back to her shoulder with her animation, and flew off it at 72 m/s once the
  -- death's ragdoll turned it on again, a stretch (playtest)
  local kept = {}
  for _, b in ipairs(gore and gore.cut_parts(mesh, true) or {}) do
    if try(function() mesh:SetAllBodiesBelowSimulatePhysics(FName(b), true, true); return true end) then kept[#kept + 1] = b end
  end
  if #kept > 0 then log("death: the parts cut off her alive simulate on: " .. table.concat(kept, ", ")) end
  return anim_fall(pawn, mesh, hit and hit.push)
end

-- her fall plays on as the death (the show's own, or one of DEATH_FALLS over it)
anim_fall = function(pawn, mesh, push)
  local a = tune.active or {}
  animDeath = { pawn = pawn, mesh = mesh, push = push, z0 = try(function() return mesh:K2_GetComponentLocation().Z end),
    p0 = try(function() return mesh:GetSocketLocation(FName("Bip001-Pelvis")) end) }
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

-- the glass cannon mode's death when the game doesn't take HP 0 as one: straight into the fall and
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
screen.mark = function(what) tp.mark(what) end
-- (and summed by part for the minute's frame cost line, screen.cost_tick)
tp.sum = {}
function tp.mark(what)
  local t = os.clock()
  local ms = (t - tp.t) * 1000
  if ms >= 1 then tp[#tp + 1] = string.format("%s %.0f", what, ms) end
  if ms > 0 then tp.sum[what] = (tp.sum[what] or 0) + ms end
  tp.t = t
end
-- while photo mode is on (entered with P, or the game's key with a piece off her): it pauses the game but not this
-- script, whose gore and hits after death went on in wall-clock time; a hit cut her arm as it closed, on a mesh photo
-- mode had posed, and left 284 stretched triangles (playtest). So the tick stops here, but for this watch: every
-- 0.5 s photo mode's state (sbslice f3), and her ragdoll's (photo mode put a cut-off head back on her neck: the game's
-- lockup and pose snapshot, which freeze a mesh in its animated pose, are undone whenever they show up), logged when
-- it changes. Once it closes the enemy's weapon trail starts over (its jump over the pause read as a swing) and hits
-- after death wait photoGrace s
-- Photo guard and watch share state with the freeze and visibility controllers.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/photo_guard.lua")(screen, try, log, vof, dist, PELVIS,
  hold_capsule, ragdoll_state, unlock, no_snapshot, sw, function() return active end,
  function() return rag end, function() return gore end, function() return tune end)

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
-- Photo freeze state stays on screen so recovery and world cleanup can discard it.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/photo_freeze.lua")(screen, goreCtx, valid, try, log, lg, vof, dist,
  PELVIS, dface, function() return gore end, function() return rag end, function() return cachedPawn end)
-- photo mode hides her when its camera comes close (ewanhowell5195's Nexus mod 319 un-hides her as the camera
-- moves): while photo mode is on she is shown again every frame (tune.photoUnhide). Her actor and every part of her
-- (hidden, invisible, owner-no-see; a part hidden as photo mode opened, an outfit piece the gore took off, stays
-- hidden), and her out of the controller's hidden actors; what was undone is logged with the camera's distance.
-- In the last playtest none of her own flags changed as she vanished up close, so the near clip plane is brought in
-- too (screen.unhide_start). Photo mode is on when
-- its view target is photo mode's pawn, or its manager says so (sbslice f3, read every 0.5 s): the view target alone
-- never matched in game, and she was hidden up close as before (playtest)
-- Visibility state remains on screen so photo close and recovery share cleanup.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/photo_visibility.lua")(screen, goreCtx, valid, try, log, vof, dist,
  function() return gore end, function() return tune end)
-- once a piece is off her, photo mode may open from the game's own key too: F9's head on her alive went back on her
-- neck as it opened (playtest). So her mesh is shielded as soon as she has a cut (sbslice f4, f5 once none is left),
-- and photo mode's state read every 0.5 s while she has one, her head's place kept from before: the watch above takes
-- over however photo mode opened.
-- A ragdoll with nothing cut off (F7's, or a death before its cut) is shielded too: photo mode opened on it by the
-- game's key turned its physics off, and back on as it closed from wherever the bones had gone; on stairs she shifted
-- and stretched (playtest)
-- tune.holdDown: knocked down, she stays on the floor till the player gets her up (dodge or jump: the game's fast
-- getup). tables.lua chains her tumbling knockdowns into Down_Eve, a copy of the shared Down (1 s, then Getup)
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
  -- after tables.lua made Down_Eve
  local tb = goreCtx.tables
  if tb and not tb.done[tb.EFFECT] then held.want = nil; return end
  local dt = try(function() return StaticFindObject(held.TABLE) end)
  if not valid(dt) then return end
  local key = string.format("%s %x", tostring(want), dt:GetAddress())
  if key == held.key then return end
  local was, why = gore.row_float(dt, "Down_Eve", "LifeTime", want and held.LIFE or 1)
  -- the DLL still starting: again next time
  if not was and (why == "sbslice waiting" or why == "sbslice init") then held.next = 0; return end
  held.key = key
  if not was then
    log("hold down: Down_Eve not set (" .. tostring(why) .. "): knockdowns stay the game's")
  elseif was ~= held.LIFE and was ~= 1 then log(string.format("hold down: Down_Eve's LifeTime was %g (another mod's row?); now %g", was, want and held.LIFE or 1))
  else log(string.format("hold down %s: Down_Eve lasts %g s (was %g)", want and "on" or "off", want and held.LIFE or 1, was)) end
end

-- her watches while she plays (the swing, her guard, the bone watch, the HUD, hit marks, a lethal hit, Lose Arm at
-- Low HP, a camp rest, her fall): a third of a poll after it, on a frame of their own (game_tick). With the rest of
-- the poll and the enemies' part on one frame they were 3-6 ms on one frame in five at 144 fps (microstutter)
-- an outfit put on her over her cuts (Nexus 672, ESE: her suit torn or gone as her shield breaks, or as she dies):
-- the new asset's weights are uncut and the cut-off arm was back on her (reported). Alive, the cuts are undone (as a
-- regrow at once) and those parts cut again on the new outfit; dead, an undo would stop her ragdoll (cleanup stops
-- the simulation), so their records are dropped and they are cut again as cuts after her death
function hm.swap_watch(pawn, mesh, dead)
  if not (gore and gore.swapped) or gore.busy() or hm.regrow or hm.ghost or (gore.pieceHid and not gore.pieceHid.baked)
    or screen.photoLive then return end
  local parts, _, quiet = gore.swapped(mesh)
  if #parts == 0 then return end
  if dead then
    local kept
    parts, kept = gore.swapped(mesh, true)
    if #kept > 0 then log("outfit changed over her waist cut (" .. table.concat(kept, ", ") .. "): left as it is, dead") end
    if #parts == 0 then return end
  end
  log(string.format("outfit changed over her cuts (%s): cut again on the new one%s", table.concat(parts, ", "),
    dead and " (dead: as cuts after her death)" or ""))
  if not dead then
    local ok, err = pcall(gore.cleanup, pawn, mesh)
    if not ok then log("outfit changed: undo failed: " .. tostring(err)) end
    -- (a part carried over a level change has no piece here: hidden on the new outfit too, hm.carry_tick)
    local loud = {}
    for _, b in ipairs(parts) do if not (quiet or {})[b] then loud[#loud + 1] = b end end
    if #loud < #parts then
      local q = {}
      for _, b in ipairs(parts) do if quiet[b] then q[#q + 1] = b end end
      hm.carry = { parts = q, done = {}, t = os.clock(), why = "outfit changed" }
      parts = loud
    end
    if #parts == 0 then return end
  end
  gore.slice_bones(pawn, mesh, parts, dead and "after" or "outfit changed")
end

-- A level change while she lives (Altess Levoire gone into, an elevator, a load) brings a new Eve, uncut: the parts
-- cut off her alive were back on her, the level's cutscene showed her whole and the arm stayed back (Nexus report,
-- 0.5.0: then came off again as the new HP bar was set, sound and all; 0.5.1 kept it on). The game's cutscenes play on
-- her own pawn (their sequences bind "Player"), so the new Eve is cut again at once: quietly (gore's "carried": the
-- stump, the piece hidden, no sound, no blood, no piece falling), Lose Arm at Low HP's blocks on the new pawn with it.
-- A save loaded is a new Eve too: her HP bar, once the game sets it (a new bar reads full till then, after the
-- level's cutscene), tells. Set to another value than she had (CARRY_HP off), or still full CARRY_FULL_S s on when she
-- wasn't, the carried parts are put back at once. A death's reload carries nothing (her next life is whole)
hm.CARRY_HP, hm.CARRY_FULL_S = 0.02, 60
-- while she plays: the parts cut off her alive, and her HP bar, for a level change
function hm.carry_note(pawn, mesh)
  -- (not while a carry is under way: the new level's HP bar reads full till the game sets it, and that full bar was
  -- taken for hers, sim)
  if not gore or hm.regrow or hm.ghost or hm.carry then return end
  local parts = gore.cut_parts(mesh)
  if #parts == 0 then hm.carryParts = nil; return end
  hm.carryParts = parts
  hm.carryBar = hm.lowLast or (goreCtx.glass and goreCtx.glass.bar_pct(false)) or hm.carryBar
end
-- the level gone: what goes on with her into the new one (forget_world)
function hm.carry_take(dead)
  local parts, bar = hm.carryParts, hm.carryBar
  hm.carryParts, hm.carryBar = nil, nil
  -- (a level gone before the last one's were cut again, or her HP bar was set: those go on, with the bar she had)
  if hm.carry then parts, bar = hm.carry.parts, hm.carry.bar end
  -- (blocks on her old pawn's actor went with it; the gun's table gate is the game's, put back: low_arm puts them all
  -- on the new one)
  local b = hm.lowBlock
  hm.lowBlock = nil
  if b and b.gate and goreCtx.tables then pcall(goreCtx.tables.gun_gate, false) end
  if dead or not parts or #parts == 0 then hm.carry = nil; return end
  hm.carry = { parts = parts, done = {}, t = os.clock(), bar = bar, why = "level change" }
  log(string.format("level change with %s cut off her alive (HP bar %s): cut again on the new Eve", table.concat(parts, ", "),
    bar and string.format("%.3f", bar) or "unread"))
end
-- on the new Eve: each carried part cut again, one at a time (gore's "carried"), then her HP bar watched for a save
function hm.carry_tick(pawn, mesh)
  local c = hm.carry
  if not c or not gore then return end
  if not c.cut then
    -- (not while the new level may still stream in: goreCtx.quietUntil, forget_world)
    if gore.busy() or not gore.native_ready() or os.clock() < (goreCtx.quietUntil or 0) then return end
    for _, b in ipairs(c.parts) do
      if not c.done[b] then
        c.done[b] = true
        if not gore.has_cut(mesh, b) then
          local ok, r = pcall(gore.slice_bone, pawn, mesh, b, nil, "carried")
          log(string.format("carried (%s): %s %s", c.why, b, not ok and ("failed: " .. tostring(r)) or r and "cut again" or "not cut"))
          return
        end
      end
    end
    c.cut, c.cutT = true, os.clock()
    if not c.bar then hm.carry = nil end
    return
  end
  -- (the cut opening first: undone mid-cut, its stages ran on a mesh put back)
  if gore.busy() or not goreCtx.glass then return end
  local pct = goreCtx.glass.bar_pct(false)
  if not pct then return end
  local why
  if pct < 0.999 then
    if math.abs(pct - c.bar) > hm.CARRY_HP then why = string.format("her HP bar set to %.3f, not her %.3f", pct, c.bar) end
  elseif c.bar < 0.98 then
    if os.clock() - c.cutT < hm.CARRY_FULL_S then return end
    why = string.format("her HP bar full %d s on, not her %.3f", hm.CARRY_FULL_S, c.bar)
  end
  hm.carry = nil
  if not why then log(string.format("carried: her HP bar at %.3f as she had it: a level change, the parts stay off", pct)); return end
  log("carried: " .. why .. ": a save loaded, the parts back")
  local ok, err = pcall(gore.cleanup, pawn, mesh)
  if not ok then log("carried: undo failed: " .. tostring(err)) end
  if hm.lowCut then hm.lowCut = false; hm.low_block(pawn, false, "a save loaded") end
end
function hm.alive_watch(pawn, mesh)
  -- (each part marked: a 417 ms tick logged as "swing" was none of track_swing's, which logs its own over slowMs)
  if gore and gore.decals_back then gore.decals_back("she plays") end
  hm.carry_tick(pawn, mesh)
  hm.carry_note(pawn, mesh)
  tp.mark("carry")
  if goreCtx.customrag then try(function() goreCtx.customrag.keep(pawn, mesh) end) end
  tp.mark("customrag")
  if goreCtx.stains then
    local ok, err = pcall(goreCtx.stains.tick, pawn, mesh, false)
    if not ok then log("stains: " .. tostring(err)) end
  end
  tp.mark("stains")
  hm.swap_watch(pawn, mesh, false)
  tp.mark("outfit swap")
  track_swing(pawn, mesh)
  tp.mark("swing")
  hm.guard_watch(pawn, mesh)
  tp.mark("guard")
  if gore then gore.watch(mesh, tp.mark) end
  tp.mark("bone watch")
  if goreCtx.glass then goreCtx.glass.tick(pawn, mesh) end
  tp.mark("glass")
  hit_marks(pawn, mesh)
  tp.mark("hit marks")
  hm.lethal_watch(pawn, mesh)
  tp.mark("lethal")
  hm.low_arm(pawn, mesh)
  tp.mark("low HP arm")
  hm.rest_watch(pawn, mesh)
  tp.mark("regrow")
  hm.piece_watch(pawn, mesh)
  tp.mark("piece")
  hm.yaw, hm.yawT = try(function() return pawn:K2_GetActorRotation().Yaw end), os.clock()
  -- falling or flying (an air combo) on this tick alive: a death in the next moment is a ragdoll (animated_death)
  local z = try(function() return pawn:K2_GetActorLocation().Z end)
  if try(function() local cm = pawn.CharacterMovement; return cm:IsFalling() or cm.MovementMode == 5 end) then
    hm.airT = os.clock()
    if z then hm.airTop = math.max(hm.airTop or z, z) end
  elseif hm.airTop then
    -- landed: the drop from the top of the fall, for a fall damage death on the ground (animated_death)
    if z and hm.airTop - z >= ((tune.active or {}).landDrop or 400) then hm.land = { t = os.clock(), drop = hm.airTop - z } end
    -- (any drop that may hurt her, Lose Arm at Low HP's fall check: low_arm)
    if z and hm.airTop - z >= hm.LOW_LAND_CM then hm.landAny = { t = os.clock(), drop = hm.airTop - z } end
    hm.airTop = nil
  end
  tp.mark("landing")
end
local function tick()
  for i = #tp, 1, -1 do tp[i] = nil end
  tp.t = os.clock()
  aheadTick = 0
  local pawn = find_eve()
  if not pawn then return end
  -- a pawn from a level that is still streaming in (or being torn down): leave it alone
  if try(function() return pawn.bActorIsBeingDestroyed end) ~= false
    or (try(function() return pawn:GetGameTimeSinceCreation() end) or 0) < 2 then return end
  maybe_dump_usmap()
  hook_once()
  local mesh = try(function() return pawn.Mesh end)
  if not valid(mesh) then return end
  if screen.clothFor ~= pawnAddr then
    screen.clothFor, screen.clothColl, screen.clothSim = pawnAddr, nil, nil
    -- her meshes are new objects: their bone-ancestor cache goes with the old ones
    screen.simReach = {}
    screen.cloth_soon("she came into the world")
  end
  screen.cloth_tick(pawn)
  if gore and screen.photo_guard(pawn, mesh) then return end
  local function simulating() return try(function() return mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end) == true end
  local sim = simulating()

  tp.mark("find")
  try(function() screen.probe(pawn) end)
  tp.mark("death screen")
  if goreCtx.tables then goreCtx.tables.tick() end
  if goreCtx.gui then goreCtx.gui.tick(pawn) end
  screen.held.tick()
  -- (the enemies' part runs half a poll later, on a frame of its own: game_tick)
  if goreCtx.enemies then screen.enemiesDue = { pawn = pawn, mesh = mesh } end
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
  -- a death taken over (hm.take) with the player moving her: she lived, so the ragdoll ends and she gets up, not left
  -- walking about with her body on the floor (playtest). Her movement mode alone is no sign: the game's falling death
  -- leaves it on, walking (playtest); her acceleration is the player's input, none in a death
  if hm.taken and (not active or saved.manual) then hm.taken = nil end
  if hm.taken and sim then
    local mm = try(function() return pawn.CharacterMovement.MovementMode end)
    local acc = (mm == 1 or mm == 2) and try(function() return pawn.CharacterMovement:GetCurrentAcceleration() end)
    local push = acc and math.sqrt((acc.X or 0) ^ 2 + (acc.Y or 0) ^ 2) or 0
    if push > 1 then
      log(string.format("death: taken over %.1f s ago, but the player moves her (mode %d, input %.0f): she lives, the "
        .. "ragdoll ends", os.clock() - hm.taken.t, mm, push))
      hm.taken = nil
      try(function() mesh:SetAllBodiesSimulatePhysics(false) end)
      try(function() mesh:SetSimulatePhysics(false) end)
      sim = false
    end
  end
  if active then hold_capsule(pawn, sim); camera.watch(pawn, mesh) end
  -- the outfit she has on, whenever she is animated (the respawn window included: an outfit put on right after a
  -- reset went unchecked, fifteenth playtest)
  if physfix and not sim and not active then physfix.check(pawn, mesh, false) end
  if rag and not sim then rag.track(pawn) end
  if not sim and not active then screen.camera_learn(pawn) end
  if not sim then poll_mesh_hit(mesh) end
  tp.mark("outfit, hits")
  if hm.regrow and (sim or active) then hm.grow_stop("stopped: her death") end
  if hm.ghost and (sim or active) then hm.ghost_stop("back at once: her death") end
  if sim or active then hm.piece_back("her death") end
  if active then hm.swap_watch(pawn, mesh, true) end
  if not sim and not active then
    -- (her watches while she plays run a third of a poll later, on a frame of their own: game_tick)
    screen.aliveDue = { pawn = pawn, mesh = mesh }
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
    if valid(f.mesh) then log("Page Up 0.8 s later: " .. face_curves(f.mesh, gore and gore.face_of and gore.face_of(f.pawn, f.mesh))) end
  end
  -- gore (a split after its splitAnim) or a hit after death (a leg off) can switch an animated death to the ragdoll
  -- this tick: read it again, or the death looked like it had no fall and no ragdoll and ended (she was put back
  -- whole 0.9 s into a beheading, a leg cut after it)
  if not sim and animDeath == nil and active then sim = simulating() end
  -- a fall damage death with no ragdoll from its show (hm.lethal_watch): her bodies simulate here, as the show's key
  -- would have made them, and the death starts below on this tick as any other
  if hm.take and not sim and not active then
    local tk = hm.take
    hm.take = nil
    hm.takeColl = ragdoll_collision(mesh)
    try(function() mesh:SetSimulatePhysics(true) end)
    try(function() mesh:SetAllBodiesBelowSimulatePhysics(FName("Bip001"), true, true) end)
    try(function() mesh:WakeAllRigidBodies() end)
    sim = simulating()
    log(string.format("death: taken over (%s), pelvis simulating %s", tk.why, tostring(sim)))
    -- (a fall's cuts nothing; any other's cuts as any death)
    hm.fellAt = tk.fall and os.clock() or nil
    hm.taken = sim and { t = os.clock() } or nil
    if not sim then
      local c = hm.takeColl
      hm.takeColl = nil
      try(function() mesh:SetCollisionObjectType(c.obj) end)
      for ch, r in pairs(c.resp) do try(function() mesh:SetCollisionResponseToChannel(ch, r) end) end
      try(function() mesh:SetCollisionEnabled(c.enabled) end)
    end
  elseif hm.take and (active or os.clock() - hm.take.t > 1) then
    hm.take = nil
  end
  if hm.at.on and not sim and not active then
    log(string.format("Test: Animated Death: %s: her death starts with it, no cut", hm.at.on.what))
    hm.at.on = nil
    after = -1
    local c = ragdoll_collision(mesh)
    saved = {}
    on_start(pawn, mesh)
    saved.collision, saved.manual = c, true
    forceFall = "own"
    anim_fall(pawn, mesh, nil)
  end
  if f5_test and not sim and not active then
    -- F6's struggle test: straight into the ragdoll, with no death show to set her collision up for it (she stayed
    -- kinematic and the death ended on the next tick, twelfth playtest), then its cuts one after the other
    local t = f5_test
    f5_test = nil
    after = -1
    local c = ragdoll_collision(mesh)
    saved = {}
    goreCtx.struggle_test = t
    on_start(pawn, mesh)
    goreCtx.struggle_test = nil
    saved.collision = c
    -- (a test ragdoll lies there until F8: recoverAfter would get her up mid-struggle)
    saved.manual = true
    forceFall = "own"
    anim_fall(pawn, mesh, nil)
    ragdoll_now("F6: struggle test")
    -- (F7's shove, a couple of ticks on once her bodies simulate: she goes down with it instead of folding in place)
    if (tune.impulse or 0) > 0 or (tune.push or 0) > 0 then f7_push = { pawn = pawn, mesh = mesh, n = F7_WAIT } end
    if gore and #t.bones > 0 then
      local n = try(function() return gore.slice_bones(pawn, mesh, t.bones, "death") end) or 0
      log(string.format("F6: struggle test: %d of %d cuts started", n, #t.bones))
    end
  elseif sim and not active then
    after = -1
    saved = {}
    on_start(pawn, mesh)
    -- (the mod's own ragdoll for a death with none: her collision put back at its end, as a test ragdoll's)
    saved.takeColl, hm.takeColl = hm.takeColl, nil
    local test = hm.at.on
    if test then
      -- (Test: Animated Death's, its ragdoll key come before the tick started it: her own fall, no cut, and she lies
      -- till F8)
      saved.manual, forceFall = true, "own"
      log(string.format("Test: Animated Death: %s's ragdoll key %.1f s in, no cut", test.what, os.clock() - test.t))
    end
    tp.mark("death start")
    -- slow motion highlights the damage from here; the test ragdolls sit out (slow_start checks)
    slow_start(pawn)
    -- (the game let her death go before the watch saw the grab end: the killing cut made in it counts from here)
    if hm.lethal and hm.lethal.grab then
      log(string.format("lethal hit: %s's grab over after %.1f s (her death came)", hm.lethal.grab.cls,
        os.clock() - hm.lethal.grab.t0))
      hm.lethal.grab, hm.lethal.t = nil, os.clock() - 0.15
    end
    if hm.lethal then log(string.format("death: %.2f s after her HP bar hit 0", os.clock() - hm.lethal.t))
    elseif hm.armed then
      -- (the bar not yet at 0 as the death comes: the game drains it after; nothing could be cut at the hit)
      log(string.format("death: her HP bar read %s at it, %.2f s since it last changed", tostring(hm.barLast),
        os.clock() - (hm.barT or 0)))
    elseif hm.barLost then
      log(string.format("death: her HP bar not found since the level loaded %.0f s ago: nothing cut at the hit",
        os.clock() - hm.barLost))
    end
    -- This lethal hit has a death already. Keep its details for the cut, but never take it over after recovery:
    -- the empty bar and visible death screen can outlive the ragdoll until the game finishes respawning her.
    if hm.lethal then hm.lethal.missed = true end
    -- disarmed till the bar is seen above 0 again: it reads 0 through the respawn, and the watch fired there
    hm.armed = false
    -- how far she turned from her last tick alive (the game's death show turns her, playtest: a 180 before the cut)
    local yaw = try(function() return pawn:K2_GetActorRotation().Yaw end)
    if yaw and hm.yaw then
      log(string.format("death: she faces %.0f deg, %.0f deg from her last tick alive (%.2f s before)", yaw,
        (yaw - hm.yaw + 540) % 360 - 180, os.clock() - hm.yawT))
    end
    log(string.format("death: game evidence: ragdoll limit %s, montage %s, actor-dead %s, projectile %s, mesh hit %s",
      tostring(try(function() return pawn.RagdollInfo.ImpulseLimitVelocity end)), tostring(hm.montage(mesh)),
      hm.deadMsg and hm.dead_what(hm.deadMsg) or "none", sw.projectile_hit() and sw.projectile_hit().src or "none",
      meshHit and string.format("%.2f s ago", os.clock() - meshHit.t) or "none"))
    local h = death_hit(pawn, mesh)
    tp.mark("death hit")
    local animated = animated_death(pawn, mesh, h)
    if animated then goreCtx.pose.hold(mesh) end
    hm.at.on = nil
    tp.mark("fall")
    -- Capture the hit now; ragdoll setup and cut selection each get a separate frame.
    local deathNumber = deaths
    pending[#pending + 1] = function()
      if not (active and deaths == deathNumber and valid(mesh)) then return end
      if not animated and rag then
        local started = os.clock()
        rag.start(pawn, mesh, "death", h and h.push)
        local ms = (os.clock() - started) * 1000
        if ms >= ((tune.gore or {}).slowMs or 15) then log(string.format("death ragdoll setup: %.0f ms (a frame of its own)", ms)) end
      end
      pending[#pending + 1] = function()
      if not (active and deaths == deathNumber and valid(mesh)) then return end
      local t0 = os.clock()
      local ok, err = true, nil
      if gore then gore.prof_begin() end
      if not test then ok, err = pcall(gore_death, pawn, mesh, h) end
      if not ok then log("death cut failed: " .. tostring(err)) end
      if goreCtx.pose.held then goreCtx.pose.held.cut = true end
      if not (gore and gore.splitting()) then goreCtx.pose.free("no split: the fall plays on") end
      if gore then gore.mark("pose let go") end
      local steps = gore and gore.prof_end() or ""
      local ms = (os.clock() - t0) * 1000
      if ms >= ((tune.gore or {}).slowMs or 15) then
        log(string.format("death cut: %.0f ms (a frame of its own)%s", ms, steps ~= "" and ": " .. steps or ""))
      end
      end
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
    -- her fall never played: another mod drives her pose (a body slider), and she stood frozen with pieces stuck in
    -- the air (reported). Pelvis still and head at standing height 0.7 s in: the ragdoll instead
    if polls == 20 and animDeath.p0 then
      local p = try(function() return mesh:GetSocketLocation(FName("Bip001-Pelvis")) end)
      local h = try(function() return mesh:GetSocketLocation(FName("Bip001-Head")).Z - mesh:K2_GetComponentLocation().Z end)
      local a0 = animDeath.p0
      if p and h and h > 100 and math.abs(p.X - a0.X) + math.abs(p.Y - a0.Y) + math.abs(p.Z - a0.Z) < 3 then
        ragdoll_now(string.format("her fall didn't play: pelvis still, head %.0f cm up", h))
      end
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
    if chatty and after % 60 == 0 then lg.v("ragdoll state after: " .. ragdoll_state(pawn)) end
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

  if active then skip_tick(); slow_tick() end
  -- her HP bar back up for 0.5 s while the death still runs: the game brought her back past every sign the mod
  -- watches (a load, a respawn with no ReInitActor). Left alone she got up still cut, her movement off (walking in
  -- circles, Nexus report): got up here as for a respawn
  if active and not saved.manual and goreCtx.glass and polls * POLL_MS / 1000 > 3 then
    local pct = try(function() return goreCtx.glass.bar_pct(true) end)
    -- (only after the bar read empty in this death: a fall's death may leave it up)
    if pct and pct <= 0.0005 then screen.hpZero = true end
    screen.hpBack = screen.hpZero and pct and pct > 0.05 and (screen.hpBack or 0) + 1 or 0
    if screen.hpBack >= 15 and not screen.respawn then
      log(string.format("her HP bar is back (%.0f%%) %.1f s into the death: the game brought her back", pct * 100, polls * POLL_MS / 1000))
      screen.respawn, screen.hpBack = true, 0
    end
  end
  if active and not saved.manual and (screen.respawn or not screen.frozen and (screen.revived or screen.press
    or polls * POLL_MS / 1000 + ahead >= (tune.recoverAfter or 10) and screen.ready(polls * POLL_MS / 1000 + ahead))) then
    -- get her up ourselves before the game respawns her (the sandbox (F8) recovery always worked, the one after the
    -- game's respawn never did), once a death screen button is pressed (tune.recoverOn). A press gets her up at once,
    -- recoverAfter or not: the game respawns her right after it, and pressed 9 s in (the screen shown early with
    -- Shift+F4) its respawn set her meshes while they still held her cut weights, which the engine frees unreleased
    -- on a mesh change (InitLODInfos): "A FRenderResource was deleted without being released first!" (playtest)
    log(string.format("recovering after %.1f s of ragdoll (%.1f of the game's), before the game respawns her (%s)",
      polls * POLL_MS / 1000, polls * POLL_MS / 1000 + ahead, screen.respawn and "the game is respawning her"
      or screen.revived and "revived with the item: the revive screen went and no death screen came"
      or tune.recoverOn ~= "button" and "recoverAfter" or screen.press and "a death screen button"
      or screen.gone and "the death screen went away" or screen.seen and "?" or "no death screen"))
    -- The mesh must be restored before the game's respawn changes its LODs. Hide the transient animated pose,
    -- then restore only visibility we changed; do not postpone the crash-preventing cleanup.
    if screen.press and not screen.respawn and not screen.revived and try(function() return pawn.bHidden end) == false then
      local k = goreCtx.keep(pawn)
      if k and goreCtx.held(k) and try(function() pawn:SetActorHiddenInGame(true); return true end) then
        screen.recoverHidden = { k = k, untilAt = os.clock() + 0.4 }
        log("recovery: hid transient pose for 0.4 s")
      end
    end
    try(function() mesh:SetAllBodiesSimulatePhysics(false) end)
    try(function() mesh:SetSimulatePhysics(false) end)
    on_end(pawn, mesh)
    if screen.uv and not screen.revived and tune.uvClean ~= false then screen.uvClean = { pawn = pawn, n = 0 } end
  end
  screen.uv_tick()

  -- a piece cut off her while she is alive (F9) settles on its own clock
  tp.mark("recover")
  if not active and rag then rag.tick(POLL_MS / 1000 + aheadTick) end
  if active then
    no_snapshot(pawn)
    if rag then rag.tick(POLL_MS / 1000 + aheadTick, tp.mark) end
    screen.wedding_blend(mesh)
    if polls == 45 then log("ragdoll state at 1.5 s: " .. ragdoll_state(pawn)) end
    if saved.manual and (polls == 6 or polls == 30 or polls == 90) then
      screen.breast_probe(mesh, polls == 6 and "0.2 s" or polls == 30 and "1 s" or "3 s")
    end
    local df = (tune.gore or {}).deathFace or {}
    if df.enabled ~= false and polls == math.max(1, math.floor((df.at or 0.3) * 1000 / POLL_MS)) then
      try(function() dface.start(pawn, mesh, "death") end)
    end
    if polls == 6 or polls == 30 or polls == 90 then try(function() face_probe(pawn, mesh, polls / 30) end) end
    if polls == 30 and gore and not saved.collision then gore.on_settled(pawn, mesh) end
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
-- pawn: the new Eve
local function forget_world(pawn)
  -- (her alive cuts go on into the new level: a death's reload takes none)
  hm.carry_take(active)
  active, polls, after, respawned, lastRecover = false, 0, -1, false, -100
  saved, hits, pending, animDeath = {}, {}, {}, nil
  rel.loc, rel.rot = nil, nil
  meshHit, meshKey, sw.rockLast, sw.projectileLast, hm.deadMsg = nil, nil, nil, nil, nil
  sw.projectileVolley = nil
  hm.q, hm.pct, hm.gkeys, hm.guardT, hm.guardWhy = {}, nil, nil, nil, nil
  sw.drop(); clear_swing_bones()
  chars, charsSeeded = {}, false
  -- (the laser traps kept: the watch may have handed the new level's out before this; gone ones are dropped as read)
  if not goreCtx.newobj.watched("/Script/SB.SBLaserComponent") then goreCtx.lasersSeeded = false end
  -- (her HP bar's widget went with the old level: the new one is handed out by the widget watch as the game makes it
  -- (glass.hud_made), and looked for 5 s on if it wasn't. The lethal watch waited up to 30 s before looking, a death
  -- in that time not seen at its hit, its cut late, playtest)
  hm.barTry, hm.barLost = os.clock() + 5, os.clock()
  followed = nil
  -- (the still camera went with the old level; the new controller looks through its own pawn)
  camera.forget(); hold = nil
  screen.allow_photo(false, "level reloaded")
  screen.photoOn, screen.frozenMesh, screen.frozenHair, screen.watchFreeze, screen.photoW = false, nil, nil, false, nil
  screen.clock, screen.stopped, screen.uvClean = nil, nil, nil
  -- her watches and the enemies' part, queued by the old one's last poll for a frame after it with her pawn and
  -- mesh: run on the new one's first tick, asking the freed old pawn crashed the game (quit to the main menu with her
  -- alive, playtest; a death's reload had none queued). And F7's push, and the dev watch, held the old pawn too
  screen.aliveDue, screen.enemiesDue, screen.watch, f7_push = nil, nil, nil, nil
  -- a held death (Shift+F4) or a hidden HUD went with the old level: none carried into the new one
  screen.frozen, screen.hudHid, screen.hudMaster, screen.hpBack, screen.photoTook = false, nil, nil, 0, nil
  -- the photo watch's async loop read the old pawn's parts (freed with the level)
  screen.unhide, screen.unhideSig = nil, nil
  -- A reload can destroy the old UI before the new pawn ticks. Drop every transient revive-screen reference
  -- without reading it: the normal inactive-screen path would otherwise touch held/ghost widgets from the old world.
  screen.introLook, screen.fade, screen.rv = nil, nil, {}
  -- the new level may still be streaming in: nothing from the pak for a few seconds more
  goreCtx.quietUntil = math.max(goreCtx.quietUntil, os.clock() + 5)
  slow_stop("the level reloaded")
  skip, ahead, aheadTick = nil, 0, 0
  -- the old face may be gone: dropped without touching it
  dface.on, dface.known, faceCheck = nil, {}, nil
  -- (a regrow's copy went with the old level. Its matrices are written into her mesh asset, which the new Eve wears:
  -- dropped as they were, her arm stayed collapsed on the asset, the carried cut was made over them and their put
  -- back came later over that cut (Nexus report: the game crashed resting at a camp with the left arm off). "Z" puts
  -- them back; sbslice drops, unwritten, those of an asset gone with the level)
  if (hm.ghost or hm.regrow) and gore then gore.fire("Z") end
  hm.ghost, hm.regrow = nil, nil
  if gore then gore.forget(pawn) end
  if goreCtx.enemies then goreCtx.enemies.forget() end
  if goreCtx.bosses then goreCtx.bosses.forget() end
  if goreCtx.glass then goreCtx.glass.forget() end
  if goreCtx.stains then goreCtx.stains.forget() end
  if rag then rag.forget() end
  if goreCtx.convulse then goreCtx.convulse.forget() end
  if goreCtx.struggle then goreCtx.struggle.forget() end
  if physfix then physfix.forget() end
end
local function adopt(ctx)
  local self = ctx and try(function() return ctx:get() end)
  local a = self and try(function() return self:GetAddress() end)
  if not a then return false end
  local now = os.clock()
  if a == pawnAddr then pawnSeen = now; return true end
  if pawnAddr and now - pawnSeen < 1.0 then return false end
  if pawnAddr then goreCtx.levelAt = os.clock(); log(string.format("new Eve %x (was %x, the level reloaded): dropped everything held from the old one", a, pawnAddr)) end
  if pawnAddr then forget_world(self) end
  pawnAddr, pawnSeen, cachedPawn = a, now, self
  return true
end

local nextTick = 0
-- a frame that took long (a stutter): told with what the mod did just before, so a stutter at a cut shows whether
-- the mod's own work or the engine's (render state, physics) held it; longer gaps are menus and loading
local HITCH_MS, HITCH_MAX_MS = 70, 1500
local lastFrame, lastTick, lastDil = nil, nil, nil
local lastTickErr, tickErrRepeats = nil, 0
-- the mod starts START_S s after the lobby's player start: nothing of it runs while the lobby loads. The game crashed
-- on launch now and then in its audio mixer's thread (a null lock at exe+0xb4b8817, five launches) as the lobby
-- loaded, with the mod's tick and object watches already on; moving its sound loading later didn't stop it
screen.START_S = 10
local function game_tick(ctx)
  if not screen.started then
    if os.clock() - (screen.hookedAt or 0) < screen.START_S then return end
    screen.started = true
    for _, fn in ipairs(screen.late or {}) do fn() end
    screen.late = nil
    log(string.format("started (%d s after the player start)", screen.START_S))
    screen.gc_tune()
  end
  goreCtx.newobj.tick()
  local h = screen.recoverHidden
  if h and os.clock() >= h.untilAt then
    screen.recoverHidden = nil
    if goreCtx.held(h.k) then
      try(function() h.k.obj:SetActorHiddenInGame(false) end)
      log("recovery: transient pose cover removed")
    end
  end
  if not adopt(ctx) then return end
  -- the F3 menu paused the game: only the menu runs (and its key), the mod's own work waits with the world (its
  -- clocks too: the frame after reads no gap)
  if goreCtx.gui and goreCtx.gui.pausing() then
    lastFrame = nil
    goreCtx.gui.tick(cachedPawn)
    if goreCtx.keys then goreCtx.keys.flush("menu") end
    return
  end
  goreCtx.frame = goreCtx.frame + 1
  local now = os.clock()
  local gap = lastFrame and (now - lastFrame) * 1000
  lastFrame = now
  -- her own time dilation: the game's hit-stop slows her (and her tick) on a hit, which reads as a gap here without
  -- any frame taking long. Told with the gap, so a hitch in a fight can be told from a hit-stop
  local dil = try(function() return cachedPawn.CustomTimeDilation end)
  -- (one past HITCH_MAX_MS, a load or a pause, still told early in a death)
  local early = active and screen.deathAt and now - screen.deathAt < screen.DEATH_S
  local hitch = gap and gap >= HITCH_MS and (gap < HITCH_MAX_MS or early)
  local gc = screen.gc_ran(hitch)
  if hitch then
    local st = gore and gore.last_stage
    local slow = math.min(dil or 1, lastDil or 1)
    if gc then screen.gc.hit = screen.gc.hit + 1 end
    screen.perf_note("hitch", gap, string.format("frame hitch: %.0f ms%s%s%s%s", gap,
      lastTick and now - lastTick.t < 0.5 and string.format(", the mod's last tick %.0f ms", lastTick.ms) or "",
      st and now - st.t < 0.5 and ", after " .. st.what or "",
      slow < 0.99 and string.format(", her time x%.2f (the game's hit-stop)", slow) or "",
      gc and ", garbage collection ran" or ""))
  end
  screen.perf_flush()
  -- a run of slow frames with the mod's own tick short (an fps dip, playtest): told once with what the mod has out
  if gap and gap >= HITCH_MS and gap < HITCH_MAX_MS and not (lastTick and now - lastTick.t < 0.5 and lastTick.ms > 20) then
    local d = screen.dip or { t = {}, told = 0 }
    screen.dip = d
    d.t[#d.t + 1] = now
    while d.t[1] and now - d.t[1] > 1.5 do table.remove(d.t, 1) end
    if #d.t >= 4 and now - d.told > 10 then
      d.told = now
      log(string.format("fps dip: %d slow frames in 1.5 s, the mod's tick short; out now: %s", #d.t,
        gore and gore.load_counts and (try(gore.load_counts) or "?") or "?"))
    end
  end
  lastDil = dil
  if goreCtx.keys then goreCtx.keys.flush() end
  -- (held at most a second, and never past the death or a split that came to nothing)
  local held = goreCtx.pose.held
  if held and (not active or now - held.t > 1 or held.cut and not (gore and gore.splitting())) then
    goreCtx.pose.free(not active and "the death ended" or held.cut and "the split came to nothing" or "held too long")
  end
  local fa = os.clock()
  local ready = pending
  pending = {}
  for _, fn in ipairs(ready) do fn() end
  local fb = os.clock()
  -- Photo mode steps physics every frame while the death poll stops: re-sleep every frame or bodies drift between
  -- polls (12 cm head drift in the photo log) while caps frozen with the tick stretch.
  if screen.photoOn and rag and rag.hold_still then rag.hold_still() end
  if camera.held() then camera.orbit() end
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
  local fc = os.clock()
  if screen.watchFreeze then
    local mesh = try(function() return cachedPawn.Mesh end)
    if valid(mesh) then pcall(screen.photo_freeze, cachedPawn, mesh) end
  end
  -- every frame, ahead of her mesh tick: a stump's seam point is rewritten onto the bone its rim rides, or a twist
  -- helper poses it out into a cone. The poll below skips frames, and one is enough
  if gore and gore.hold_seams then gore.hold_seams() end
  local fd = os.clock()
  if active then
    -- (every frame of a death, timed: a slow one is logged by part, as the poll's are)
    local f0 = os.clock()
    local ft = { os.clock() }
    if goreCtx.customrag then pcall(goreCtx.customrag.tick, screen.photoOn or screen.vtPhoto or screen.photoLive) end
    ft[2] = os.clock()
    local ok, err = pcall(screen.pad_photo)
    if not ok then log("controller photo key: " .. tostring(err)) end
    ft[3] = os.clock()
    if goreCtx.convulse then
      local ok2, err2 = pcall(goreCtx.convulse.tick, screen.photoOn or screen.vtPhoto or screen.photoLive or screen.stopped)
      if not ok2 then log("convulse: " .. tostring(err2)) end
    end
    ft[4] = os.clock()
    if goreCtx.struggle then
      local ok3, err3 = pcall(goreCtx.struggle.tick, screen.photoOn or screen.vtPhoto or screen.photoLive or screen.stopped)
      if not ok3 then log("struggle: " .. tostring(err3)) end
    end
    if goreCtx.stains and cachedPawn then
      local ok4, err4 = pcall(goreCtx.stains.tick, cachedPawn, nil, true)
      if not ok4 then log("stains: " .. tostring(err4)) end
    end
    ft[5] = os.clock()
    local fms = (ft[5] - f0) * 1000
    if fms >= ((tune.gore or {}).slowMs or 15) then
      screen.perf_note("slow", fms, string.format("slow frame: %.0f ms of the death's every-frame part: customrag %.0f, photo key %.0f, convulse %.0f, struggle %.0f",
        fms, (ft[2] - ft[1]) * 1000, (ft[3] - ft[2]) * 1000, (ft[4] - ft[3]) * 1000, (ft[5] - ft[4]) * 1000))
    end
  elseif screen.padKeys then screen.padKeys, screen.padWas = nil, nil end
  -- and a cut's stages, a frame each (on the poll below the piece came off 350 ms after the blow)
  if gore and gore.pump and not screen.photoOn then
    local ok, err = pcall(gore.pump)
    if not ok then log("cut stage failed: " .. tostring(err)) end
  end
  -- (the frame's own part, timed: a 126-140 ms "carry" and a 434 ms "enemies attack-down" of a 0.5.2 playtest were
  -- this part, the watches' timer started at the frame's start; now it starts at the watches' own)
  do
    local fe = os.clock()
    local fms = (fe - now) * 1000
    -- (in a death its own every-frame part is told above)
    if fms >= ((tune.gore or {}).slowMs or 15) and not (active and (fe - fd) * 1000 >= ((tune.gore or {}).slowMs or 15)) then
      screen.perf_note("slow", fms, string.format("slow frame: %.0f ms of the every-frame part: start %.0f, queued work %.0f, photo mode %.0f, seams %.0f, the death's part and cut stages %.0f",
        fms, (fa - now) * 1000, (fb - fa) * 1000, (fc - fb) * 1000, (fd - fc) * 1000, (fe - fd) * 1000))
    end
  end
  -- her watches while she plays, a third of a poll after it, and the enemies' part, two thirds: the poll was 3-6 ms
  -- on one frame every ~5 at 144 fps (a Nexus report of microstutter), the enemies ~1 ms of it, her watches ~2
  local ad = screen.aliveDue
  if ad and now >= nextTick - POLL_MS * 2 / 3000 then
    screen.aliveDue = nil
    if not screen.photoOn and not active and valid(ad.pawn) and valid(ad.mesh)
      and try(function() return ad.mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end) ~= true then
      for i = #tp, 1, -1 do tp[i] = nil end
      now = os.clock()
      tp.t = now
      local ok, err = xpcall(hm.alive_watch, debug and debug.traceback or tostring, ad.pawn, ad.mesh)
      if not ok then log("her watches: " .. tostring(err)) end
      local ms = (os.clock() - now) * 1000
      screen.cost.pollMs = screen.cost.pollMs + ms
      if ms >= ((tune.gore or {}).slowMs or 15) then screen.perf_note("slow", ms, string.format("slow tick: %.0f ms (her watches, on their own frame): %s", ms, table.concat(tp, ", "))) end
    end
    -- (with the next poll due already, at a low frame rate, all in this frame as before: a frame each made the poll
    -- come every third frame, 100 ms at 30 fps)
    if now < nextTick then return end
    now = os.clock()
  end
  local ed = screen.enemiesDue
  if ed and now >= nextTick - POLL_MS / 3000 then
    screen.enemiesDue = nil
    if not screen.photoOn and valid(ed.pawn) and valid(ed.mesh) then
      for i = #tp, 1, -1 do tp[i] = nil end
      now = os.clock()
      tp.t = now
      local ok, err = pcall(goreCtx.enemies.tick, ed.pawn, ed.mesh, tp.mark)
      if not ok then log("enemies: " .. tostring(err)) end
      tp.mark("enemies")
      local ms = (os.clock() - now) * 1000
      screen.cost.pollMs = screen.cost.pollMs + ms
      if ms >= ((tune.gore or {}).slowMs or 15) then screen.perf_note("slow", ms, string.format("slow tick: %.0f ms: enemies (on its own frame): %s", ms, table.concat(tp, ", "))) end
    end
    if now < nextTick then return end
    now = os.clock()
  end
  if now < nextTick then return end
  nextTick = now + POLL_MS / 1000
  -- a new poll window: her watches and the enemies' part due in it share it (live_chars reads it)
  goreCtx.poll = goreCtx.poll + 1
  local ok, err = xpcall(tick, debug and debug.traceback or tostring)
  lastTick = { t = os.clock(), ms = (os.clock() - now) * 1000 }
  screen.cost.polls, screen.cost.pollMs = screen.cost.polls + 1, screen.cost.pollMs + lastTick.ms
  if lastTick.ms >= ((tune.gore or {}).slowMs or 15) then
    screen.perf_note("slow", lastTick.ms, string.format("slow tick: %.0f ms: %s", lastTick.ms, table.concat(tp, ", ")))
  end
  if not ok then
    -- the same error on every tick filled the log (900 lines in 30 s): once with its traceback, then a count
    -- (by its message alone: the same error reached by two paths alternated tracebacks and was told every tick)
    err = tostring(err)
    if err:match("^[^\n]*") == (lastTickErr or ""):match("^[^\n]*") then
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
-- hooked once: her Blueprint stays loaded for the whole game (one hook a session in 163 logged sessions, never again
-- at a respawn). (UE4SS's BeginPlay hook never fires in this game: hooked from it, she was never hooked.) From the
-- player controller's ClientRestart, on the game thread as the level's player starts: hooked from an async loop
-- (a FindFirstOf over every object, then RegisterHook, off the game thread while the save loaded) the game now and
-- then crashed on launch a second or two after it (null + 0x88, four launches, playtest). The loop is left only for
-- a script reloaded mid-game, which sees no ClientRestart: from 20 s on, a name lookup alone
screen.tickHooked, screen.loadedAt = false, os.clock()
-- the mod's own time on her tick, logged once a minute (a Nexus report of 24-30 fps with the mod: the log says
-- whether it is this mod's time or not). The UE4SS hook's own cost around it isn't in it. Split into the work done
-- every frame and the poll (every POLL_MS), and the poll by its parts (tp.mark's), the costliest first: a report of
-- 144 fps down to 100-110 and microstutter, 1.6-2.4 ms a frame in our own log, said nothing of where
-- (and how many frames of ours took 2, 4 and 8 ms or more: a microstutter is those, not the average)
screen.cost = { n = 0, ms = 0, most = 0, at = os.clock(), polls = 0, pollMs = 0, o2 = 0, o4 = 0, o8 = 0 }
-- Focus and short-window tick timing: compare before and after alt-tab without changing gameplay.
-- Pawn ticks are a proxy for FPS, not a renderer/GPU measurement; paused windows are excluded.
screen.focusPerf = { next = 0, n = 0, ms = 0 }
function screen.focus_perf(dt, now)
  local f = screen.focusPerf
  local menu = goreCtx.gui and goreCtx.gui.state
  if menu and menu.focusLost then
    menu.focusLost, f.state, f.next = nil, "0", 0
    log("focus perf: window background (menu focus check)")
  end
  if now >= f.next then
    f.next = now + 1
    local r = gore and gore.native_ready and gore.native_ready() and gore.command and gore.command("K")
    local state = type(r) == "string" and r:match(" fg([01])")
    if state and state ~= f.state then
      f.state, f.at, f.n, f.ms = state, now, 0, 0
      f.untilAt = state == "1" and now + 31 or nil
      log("focus perf: window " .. (state == "1" and "foreground" or "background") .. "; sampling pawn ticks")
    end
  end
  if f.state ~= "1" or not f.untilAt or now > f.untilAt then return end
  if goreCtx.gui and goreCtx.gui.pausing() then f.at, f.n, f.ms = now, 0, 0; return end
  f.n, f.ms = f.n + 1, f.ms + dt * 1000
  local elapsed = now - f.at
  if elapsed >= 10 then
    log(string.format("focus perf: %.1f s foreground, %d pawn ticks (%.1f ticks/s), mod tick %.2f ms average", elapsed, f.n, f.n / elapsed, f.ms / math.max(f.n, 1)))
    f.at, f.n, f.ms = now, 0, 0
  end
end
function screen.cost_tick(dt)
  screen.focus_perf(dt, os.clock())
  local c = screen.cost
  local ms = dt * 1000
  -- Short post-death windows distinguish sustained frame loss from one slow
  -- mod callback; pawn ticks are a proxy and can include game time dilation.
  local now = os.clock()
  if active and screen.deathAt then
    local d = screen.deathCost
    if not d or d.deathAt ~= screen.deathAt then
      d = { deathAt = screen.deathAt, at = now, n = 0, ms = 0, peak = 0, window = 0 }
      screen.deathCost = d
    end
    if d.window < 6 then
      d.n, d.ms, d.peak = d.n + 1, d.ms + ms, math.max(d.peak, ms)
      local elapsed = now - d.at
      if elapsed >= 1 then
        log(string.format("death perf: %.1f-%.1f s, %.1f pawn ticks/s, mod %.2f ms/tick (max %.0f ms)",
          d.at - d.deathAt, now - d.deathAt, d.n / elapsed, d.ms / d.n, d.peak))
        d.at, d.n, d.ms, d.peak, d.window = now, 0, 0, 0, d.window + 1
      end
    end
  else
    screen.deathCost = nil
  end
  c.n, c.ms = c.n + 1, c.ms + ms
  if ms > c.most then c.most = ms end
  if ms >= 2 then c.o2 = c.o2 + 1; if ms >= 4 then c.o4 = c.o4 + 1; if ms >= 8 then c.o8 = c.o8 + 1 end end end
  if now - c.at < 60 then return end
  if c.n > 0 then
    local parts = {}
    for k, v in pairs(tp.sum) do parts[#parts + 1] = { k, v } end
    table.sort(parts, function(a, b) return a[2] > b[2] end)
    local pl = {}
    for i = 1, math.min(8, #parts) do pl[#pl + 1] = string.format("%s %.2f", parts[i][1], parts[i][2] / math.max(c.polls, 1)) end
    log(string.format("frame cost: %.2f ms a frame on average over %d frames (%.0f fps), %.1f ms at most%s, %d frames 2 ms or more, %d 4 ms, %d 8 ms; every frame %.2f ms, the poll %.2f ms each (%d polls)%s",
      c.ms / c.n, c.n, c.n / (now - c.at), c.most, active and " (in a death)" or "", c.o2, c.o4, c.o8, (c.ms - c.pollMs) / c.n,
      c.pollMs / math.max(c.polls, 1), c.polls, #pl > 0 and ("; the poll's parts, ms each: " .. table.concat(pl, ", ")) or ""))
  end
  c.n, c.ms, c.most, c.at, c.polls, c.pollMs, c.o2, c.o4, c.o8 = 0, 0, 0, now, 0, 0, 0, 0, 0
  tp.sum = {}
end
function screen.hook_tick(how)
  if screen.tickHooked then return true end
  local fn = try(function() return StaticFindObject(TICK_FN) end)
  local addr = valid(fn) and fn:GetAddress() or nil
  if not addr then return false end
  local ok, err = pcall(RegisterHook, TICK_FN, function(ctx)
    local t0 = os.clock()
    game_tick(ctx)
    screen.cost_tick(os.clock() - t0)
  end)
  screen.tickHooked, screen.hookedAt = ok, os.clock()
  log(string.format("tick hook on %x (%s): %s", addr, how, ok and "ok" or tostring(err)))
  return ok
end
screen.restartHook, screen.restartErr = pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function()
  if not screen.tickHooked then pcall(screen.hook_tick, "player start") end
end)
if not screen.restartHook then log("ClientRestart hook failed: " .. tostring(screen.restartErr) .. " (her tick hooked from the loop)") end
-- still not hooked a while in: said once a minute, so a log that stops at "loaded" tells a session that never got
-- into the game (the main menu: her Blueprint isn't loaded) from one where the hook failed (a Nexus log stopped at
-- "loaded", no death in it)
screen.waitSaid = 0
LoopAsync(1000, function()
  if screen.tickHooked then return true end
  if screen.restartHook and os.clock() - screen.loadedAt < 20 then return false end
  local ok = screen.hook_tick("late")
  local s = os.clock() - screen.loadedAt
  if not ok and s >= 30 + 60 * screen.waitSaid then
    screen.waitSaid = screen.waitSaid + 1
    log(string.format("not started %.0f s after loading: her Blueprint isn't loaded (the main menu?), ClientRestart hook %s",
      s, screen.restartHook and "set, never fired in game" or "failed"))
  end
  return ok
end)

-- the F3 menu's pause, should it stop her tick after all (the menu runs on it): unpaused from here once the menu has
-- gone 2 s without a tick, and closed by its next one (gui.tick)
LoopAsync(500, function()
  local g = goreCtx.gui
  local s = g and g.state
  if s and g.pausing() and os.clock() - (s.tickAt or os.clock()) > 2 and not s.unstuck then
    s.unstuck = true
    ExecuteInGameThread(function()
      local p = s.paused
      local gs = goreCtx.statics()
      if p and p.world and valid(gs) and valid(p.pawn) then
        p.world = false
        try(function() gs:SetGamePaused(p.pawn, false) end)
        try(function() p.pawn:SetTickableWhenPaused(p.tick == true) end)
      end
    end)
  end
  return false
end)

log("loaded (stabiliser + logger)")
