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
local VERSION = "0.5.2"
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
os.remove(LOG_PATH .. ".old")
os.rename(LOG_PATH, LOG_PATH .. ".old")
local lg = { fh = io.open(LOG_PATH, "w"), bytes = 0, max = 20 * 1024 * 1024 }
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
-- an object held past this tick. Garbage collection frees an object's memory, and IsValid on a freed one reads it
-- and crashes UE4SS (no pcall catches that: a death crashed so once the game freed a killed enemy, 0.3.0). 0.3.0
-- looked each one up by its path in the name table, but UE4SS's StaticFindObject finds no level actor by its path
-- (".../F02.F02:PersistentLevel.X": "held: ... the name table has 0", playtest), so no enemy was ever held, none
-- followed, no swing seen and every death rolled its cut (a level slash took a leg, a vertical one the head); the
-- lookup by name under its level crashed the game at launch. sbslice's "G" asks the object's item in GUObjectArray
-- instead, never touching the object: every held object in one call a tick (goreCtx.frame), the answers kept for
-- that tick. The object's index is read off it at its first check, within keepFresh s of keep(): keep() runs in
-- NotifyOnNewObject's callback too (characters as they spawn, photo mode's widgets), and an object that new isn't
-- freed yet; one checked later is never held (live_chars finds such characters again with FindAllOf)
goreCtx.frame, goreCtx.heldList, goreCtx.heldMiss = 0, {}, 0
function goreCtx.keep(o)
  local a = o and try(function() return o:GetAddress() end)
  return a and { obj = o, addr = a, t = os.clock() } or nil
end
-- one "G" for the listed held objects; nil when sbslice isn't up
function goreCtx.alive_ask(list)
  local g = goreCtx.gore
  if not (g and g.native_ready and g.native_ready()) then return nil end
  local f = {}
  for _, k in ipairs(list) do f[#f + 1] = string.format("%x,%x", k.addr, k.idx or 0xffffffff) end
  local r = g.command("G" .. table.concat(f, ","))
  local bits = r:match("^ok (.*)$")
  if not bits then log("held: sbslice " .. tostring(r)); return nil end
  -- one 0/1 per object, an asked one's followed by ":<index> " (its index -1 when unreadable). (The index was read
  -- with an optional colon: the bits of the objects after one not asked ran into it, 20 of them made a float, and
  -- every tick after failed in format, the whole tick with it: her hair jiggled, nothing else ran, playtest)
  local pos, n = 1, 0
  while n < #list do
    local b = bits:sub(pos, pos)
    if b ~= "0" and b ~= "1" then break end
    pos, n = pos + 1, n + 1
    local k = list[n]
    if bits:sub(pos, pos) == ":" then
      local s, e = bits:find("^%-?%d+", pos + 1)
      if not s then n = n - 1; break end
      local ix = math.tointeger(tonumber(bits:sub(s, e)))
      pos = e + 1
      if bits:sub(pos, pos) == " " then pos = pos + 1 end
      if ix and ix >= 0 then k.idx = ix else b = "0" end
    end
    k.alive, k.frame = b == "1", goreCtx.frame
  end
  if n < #list then log(string.format("held: sbslice answered %d of %d (%s)", n, #list, bits:sub(1, 80))); return nil end
  return true
end
function goreCtx.held(k)
  if not k then return false end
  if k.dead then return false end
  if k.frame == goreCtx.frame then k.asked = os.clock(); return k.alive and valid(k.obj) end
  if not k.idx then
    -- its index is read off it now, while it is surely alive
    if os.clock() - k.t > (tune.keepFresh or 2) then k.dead, k.stale = true, true; return false end
    if not goreCtx.alive_ask({ k }) then return false end
    if not k.alive then k.dead = true; return false end
    k.asked, k.listed = os.clock(), true
    goreCtx.heldList[#goreCtx.heldList + 1] = k
    return valid(k.obj)
  end
  -- the first check this tick: every held object asked at once (64 to a call), the ones not asked for 3 s let go
  local keep, now = {}, os.clock()
  for _, x in ipairs(goreCtx.heldList) do
    if not x.dead and (x == k or now - (x.asked or now) < 3) then keep[#keep + 1] = x else x.listed = nil end
  end
  if not k.listed then k.listed = true; keep[#keep + 1] = k end
  goreCtx.heldList = keep
  for i = 1, #keep, 64 do
    local part = { table.unpack(keep, i, math.min(i + 63, #keep)) }
    if not goreCtx.alive_ask(part) then return false end
  end
  for _, x in ipairs(keep) do if x.frame == goreCtx.frame and not x.alive then x.dead = true end end
  k.asked = now
  if not k.alive then
    if goreCtx.heldMiss < 6 then
      goreCtx.heldMiss = goreCtx.heldMiss + 1
      log(string.format("held: %x gone (index %s)", k.addr, tostring(k.idx)))
    end
    return false
  end
  return valid(k.obj)
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
    -- the in-game menu's changes (gui.lua) over both: { ["path.to.key"] = value }
    local mok, m = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/menu.lua")
    if mok and type(m) == "table" then
      for path, v in pairs(m) do
        local x, parts = t, {}
        for part in tostring(path):gmatch("[^.]+") do parts[#parts + 1] = tonumber(part) or part end
        for i = 1, #parts - 1 do
          if type(x[parts[i]]) ~= "table" then x[parts[i]] = {} end
          x = x[parts[i]]
        end
        if #parts > 0 then x[parts[#parts]] = v end
      end
    elseif not mok and not tostring(m):find("No such file", 1, true) then
      -- (a broken menu.lua dropped every menu change without a word)
      log("menu.lua failed, the menu's changes not applied: " .. tostring(m))
    end
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
    if goreCtx.tables then goreCtx.tables.redo_dead() end
  else
    log("tune.lua failed: " .. tostring(t))
  end
end
log(string.format("Stellar Blade Gore Mod %s", VERSION))
load_tune()
goreCtx.reload_tune, goreCtx.version = load_tune, VERSION
-- the settings without the menu's changes (tune.lua under settings.lua): what the menu's per-tab reset goes back to
goreCtx.base_tune = function()
  local ok, t = pcall(dofile, TUNE_PATH)
  if not ok or type(t) ~= "table" then return nil end
  local sok, st = pcall(dofile, SETTINGS_PATH)
  if not sok and tostring(st):find("No such file", 1, true) then sok, st = pcall(dofile, SETTINGS_DEFAULT) end
  if sok and type(st) == "table" then overlay(t, st) end
  return t
end

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
  for _, m in ipairs({ { "bosses", "bosses.lua" }, { "customrag", "customrag.lua" } }) do
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

-- ---- the death face ----
-- DIE1 (Proper Death Expression) does start as she dies: her eyelids were closing 0.2 s in (upLid_down_L 0.95 on her
-- body's curves), and by 1 s every curve was back at 0 and she stared with her eyes open (twentieth playtest; the
-- sequencer calls tried before had nothing to be called on). So the mod holds a dead face itself: morph targets set on
-- her face mesh (SetMorphTarget; a master-posed face adds its own over the curves it takes from her body), faded in
-- from tune.gore.deathFace.at over fade seconds and held until she gets up. Each entry of deathFace.morphs names a
-- JALI morph, its ARKit twin and a weight: the first name her face mesh has is used (both would close the eyes twice).
-- A mood (tune.gore.deathFace.moods) is picked per death and every weight and time jittered, with her eyes' last
-- opening, their drift and her jaw's hang picked too, so no two deaths wear the same face. Page Up shows the moods
-- in turn on her living face, 6 s each.
-- One per face (goreCtx.make_face; no local to spare here): hers, and each sandbox boss's (bosses.lua, through
-- goreCtx.new_face); conv: the convulsions' face poses laid over it (by morph target name)
function goreCtx.make_face(conv)
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
  -- the mood: by weight, never the one before while there's another (Page Up: the next in turn)
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
  local c = conv() or {}
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
return dface
end
local dface = goreCtx.make_face(function() return goreCtx.convulse and goreCtx.convulse.face() or {} end)
-- a sandbox boss's own (bosses.lua): start(actor, mesh, why), tick(), stop(); no convulsions on its face
goreCtx.new_face = function() return goreCtx.make_face(function() return {} end) end
local faceCheck = nil
-- hits after death (hits_after, below): n so far this death, armedBy the enemies (addresses) whose weapon slowed
-- after their last hit, t0 the death
local ah = { n = 0, armedBy = {}, t0 = 0 }
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
-- slow ticks and frame hitches: each one with verboseLog, else one line a minute with how many and the worst of each
-- (one line per hitch was a sixth of the log)
screen.perf = { t = os.clock(), slow = { n = 0, ms = 0 }, hitch = { n = 0, ms = 0 } }
-- (in a death's first DEATH_S s each one at once, with how far into it: the minute's line was lost to a quit before
-- it, a death's hitch that put the cut after her turn as she fell untold, playtest)
screen.DEATH_S = 6
function screen.perf_note(kind, ms, line)
  local into = active and screen.deathAt and os.clock() - screen.deathAt
  if tune.verboseLog or (into and into < screen.DEATH_S) then
    log(into and string.format("%s (%.2f s into the death)", line, into) or line); return
  end
  local k = screen.perf[kind]
  k.n = k.n + 1
  if ms > k.ms then k.ms, k.line = ms, line end
end
-- the engine's garbage collection: a probe object nothing holds, in the transient package; once a find by its path
-- misses, a GC pass has run (a find is a hash lookup, the freed object is never read). Each frame hitch says whether
-- one ran in its frame, and the minute's line how many ran and how many hitches had one: half-second game-thread
-- stalls with no disk or memory pressure were seen in vanilla too, and GC is the suspect (gc = { path, n, runs, hit })
screen.gc = { n = 0, runs = 0, hit = 0 }
screen.GC_S = 0.25
function screen.gc_ran(now_too)
  local g = screen.gc
  if g.off then return false end
  -- looked at every GC_S s, and in a hitch's frame (each frame cost too much: 15 fps, playtest)
  local now = os.clock()
  if not now_too and now < (g.next or 0) then return false end
  g.next = now + screen.GC_S
  local gm = goreCtx.gore
  if not (gm and gm.native_ready and gm.native_ready()) then return false end
  -- asked of sbslice by its index ("G", as goreCtx.held), never read: UE4SS's StaticFindObject finds no subobject by
  -- its path (".../GameEngine_X:SBGameInstance_Y.SBGore_GCProbe1": "not found by its path", playtest)
  local k = g.k
  if k then
    if not goreCtx.alive_ask({ k }) then return false end
    if k.alive then return false end
    g.runs = g.runs + 1
  end
  -- (in the game instance, as the menu's widgets. An outer doesn't hold what is in it, so the probe still goes at
  -- the next pass)
  g.cls = valid(g.cls) and g.cls or try(function() return StaticFindObject("/Script/CoreUObject.Object") end)
  g.outer = valid(g.outer) and g.outer or try(function() return FindFirstOf("GameInstance") end)
  g.k = nil
  local why = not valid(g.cls) and "no Object class" or not valid(g.outer) and "no game instance"
  if not why then
    g.n = g.n + 1
    local o = try(function() return StaticConstructObject(g.cls, g.outer, FName("SBGore_GCProbe" .. g.n)) end)
    g.k = valid(o) and goreCtx.keep(o) or nil
    -- its index read now, while it is surely alive; alive at once, or the probe would read a pass every look
    if not g.k then why = "not made"
    elseif not goreCtx.alive_ask({ g.k }) then g.k = nil; return k ~= nil -- sbslice not up yet: made again next look
    elseif not g.k.alive then why = "not alive as it was made" end
  end
  -- a probe that can't be made is given up (one line), not tried again every look
  if why then g.off, g.k = true, nil; log("garbage collection probe: " .. why .. ", off") end
  return k ~= nil
end
-- fewer garbage collection passes (tune.fewerGC): the engine forces a pass each time a streamed level goes out, and
-- keeps incremental passes going while one waits to be purged. 9 passes a minute were counted, against the 61 s
-- timer, with the worst hitch of that minute (1296 ms) in one (playtest). Both are turned off; the timed pass still
-- runs, so nothing piles up past a minute. Each cvar's own value is read first and put back when the option goes off
-- (checked at the start and once a minute, so the menu's switch takes effect within a minute)
screen.GC_CVARS = { "s.ForceGCAfterLevelStreamedOut", "s.ContinuouslyIncrementalGCWhileLevelsPendingPurge" }
function screen.gc_tune()
  local want = tune.fewerGC == true
  local g = screen.gc
  if (g.tuned or false) == want then return end
  local pawn = cachedPawn
  local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
  if not (valid(pawn) and valid(ksl)) then return end
  g.was = g.was or {}
  local out = {}
  for _, cv in ipairs(screen.GC_CVARS) do
    local cur = try(function() return ksl:GetConsoleVariableIntValue(cv) end)
    if want and g.was[cv] == nil then g.was[cv] = cur or 1 end
    local to = want and 0 or (g.was[cv] or 1)
    local ok = screen.console(pawn, string.format("%s %d", cv, to))
    local now = try(function() return ksl:GetConsoleVariableIntValue(cv) end)
    out[#out + 1] = string.format("%s %s -> %s%s", cv, tostring(cur), tostring(now), ok and "" or " (not run)")
  end
  g.tuned = want
  log(string.format("garbage collection: %s: %s", want and "fewer passes" or "the game's own passes", table.concat(out, ", ")))
end
function screen.perf_flush()
  local p = screen.perf
  if os.clock() - p.t < 60 then return end
  p.t = os.clock()
  screen.gc_tune()
  for _, kind in ipairs({ "slow", "hitch" }) do
    local k = p[kind]
    if k.n > 0 then log(string.format("%d %s in the last minute, the worst %s", k.n, kind == "slow" and "slow ticks" or "frame hitches", k.line)) end
    p[kind] = { n = 0, ms = 0 }
  end
  local g = screen.gc
  log(string.format("garbage collection: %d runs in the last minute, %d of them in a frame hitch%s", g.runs, g.hit,
    g.off and " (no probe: can't tell)" or ""))
  g.runs, g.hit = 0, 0
end
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
  -- Customized Ragdoll's death camera instead, when that support is on and the mod is there (customrag.lua)
  if goreCtx.customrag and try(function() return goreCtx.customrag.camera_on(pawn) end) then return end
  if tune.cameraStill == false or tune.cameraFollow == true or camHeld then return end
  local gs = goreCtx.statics()
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
  if goreCtx.customrag then try(goreCtx.customrag.camera_off) end
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
    local v = goreCtx.statics():GetPlayerCameraManager(pawn, 0):GetCameraLocation()
    return { X = v.X, Y = v.Y, Z = v.Z }
  end)
  local c = try(function() local v = pawn:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
  local h = try(function() local v = mesh:GetSocketLocation(FName("Bip001-Head")); return { X = v.X, Y = v.Y, Z = v.Z } end)
  lg.v(string.format("camera at %.1f s: view%s, %.0f cm from her capsule%s, %.0f from her head%s",
    t, v3(cam), dist(cam, c), v3(c), dist(cam, h), v3(h)))
end

-- Esc on a death (tune.deathSkip): the game runs tune.deathSkipSpeed times as fast till its death screen
-- (WB_MainHUD_Dead) shows, instead of the wait. The mod's own clock for getting her up (recoverAfter) counts the
-- game's time meanwhile (ahead: game seconds over real ones), so she still gets up under the screen
local skip, ahead = nil, 0 -- skip: { t0, k, pawn }
local function time_speed(pawn, k)
  local gs = goreCtx.statics()
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
-- (kept through goreCtx.keep and asked through held before each use: the last death's screen, freed after the
-- respawn, was read at the next death and crashed the game, UE4SS reading the freed widget's class, playtest)
-- One made while a level loads (her tick waits 2 s on a new level) went stale unchecked, and Shift+F4's hold never
-- found the screen (playtest): in a death, one missing is looked for once by its class (find)
dead_hud.CLASS = { w = "WB_MainHUD_Dead_C", rv = "WB_MainHUD_ResurrectionItem_C" }
function dead_hud.get(f, find)
  local k = dead_hud[f]
  if k and goreCtx.held(k) then return k.obj end
  dead_hud[f] = nil
  if not (find and active) or (dead_hud.found or {})[f] then return end
  dead_hud.found = dead_hud.found or {}
  dead_hud.found[f] = true
  for _, x in ipairs(try(function() return FindAllOf(dead_hud.CLASS[f]) end) or {}) do
    if valid(x) and not tostring(try(function() return x:GetFName():ToString() end)):find("^Default__") then
      dead_hud[f] = goreCtx.keep(x)
    end
  end
  if dead_hud[f] and goreCtx.held(dead_hud[f]) then return dead_hud[f].obj end
  dead_hud[f] = nil
end
-- (watched from the mod's start, START_S after the lobby's player start: see screen.started)
screen.late = screen.late or {}
screen.late[#screen.late + 1] = function()
  goreCtx.newobj.watch("/Script/UMG.UserWidget", function(o)
    -- (any time: the death screen may be made in the frame she dies, before the mod's tick knows it)
    local cls = try(function() return o:GetClass():GetFName():ToString() end)
    if (cls == "WB_MainHUD_Dead_C" or cls == "WB_MainHUD_ResurrectionItem_C")
      and tostring(try(function() return o:GetFName():ToString() end)):find("^Default__") then return end
    if cls == "WB_MainHUD_Dead_C" then dead_hud.w = goreCtx.keep(o)
    elseif cls == "WB_MainHUD_ResurrectionItem_C" then dead_hud.rv = goreCtx.keep(o) end
    if cls and cls:find("[Pp]hoto") and not tostring(try(function() return o:GetFName():ToString() end)):find("^Default__") then
      local ok, err = pcall(screen.photo_widget, o, cls)
      if not ok then log("photo mode widget: " .. tostring(err)) end
    end
    if active and cls and (cls:find("Dead") or cls:find("Resurrect") or cls:find("Revive")) then
      dead_hud.made = (dead_hud.made and dead_hud.made .. ", " or "") .. cls
    end
  end)
  -- photo mode's own pawn, made as it opens, before its widgets: with a piece off her alive her head and upper body
  -- were already back on her neck by the first widget (playtest), so the freeze comes here first
  goreCtx.newobj.watch("/Script/SB.SBPhotoModePawn", function(o)
    if tostring(try(function() return o:GetFName():ToString() end)):find("^Default__") then return end
    local cls = try(function() return o:GetClass():GetFName():ToString() end) or "SBPhotoModePawn"
    local ok2, err2 = pcall(screen.photo_widget, o, cls, true)
    if not ok2 then log("photo mode pawn: " .. tostring(err2)) end
  end, true)
end
local function death_screen()
  local w = dead_hud.get("w")
  if not w then
    if dead_hud.scans > 0 then return false end
    dead_hud.scans = 1
    for _, x in ipairs(try(function() return FindAllOf("WB_MainHUD_Dead_C") end) or {}) do
      if valid(x) and not tostring(try(function() return x:GetFName():ToString() end)):find("^Default__") then w = x end
    end
    if not w then return false end
    dead_hud.w = goreCtx.keep(w)
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
-- the death screen's animations playing now (its intro as the game puts it up), by name
function screen.playing(w)
  local out = {}
  local cls = valid(w) and try(function() return w:GetClass() end)
  if not cls then return out end
  try(function()
    cls.Animations:ForEach(function(_, e)
      local a = e:get()
      if valid(a) and try(function() return w:IsAnimationPlaying(a) end) == true then
        out[#out + 1] = tostring(try(function() return a:GetFName():ToString() end))
      end
    end)
  end)
  return out
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
function screen.reset() dead_hud.scans, dead_hud.made, dead_hud.found, screen.rv.shown = 0, nil, nil, nil; screen.seen, screen.vis, screen.gone, screen.press, screen.respawn, screen.revived, screen.last = false, false, false, false, false, false, nil; screen.frozen, screen.shown, screen.hpZero, screen.hpBack, screen.photoTook = false, false, false, 0, nil; screen.offSince, screen.shownAt = nil, nil end
-- the death and revive screens kept hidden t s into the death: held (Shift+F4, photo mode), else as tune.deathScreen
-- says: "game" when the game puts them up (at once), "delay" till tune.reviveAt s, "key" till Shift+F4 (or the pad
-- combo) shows them. Customized Ragdoll support (tune.customizedRagdoll) puts them up as the game does, see-through
-- (screen.revive)
function screen.hiding(t)
  if screen.frozen then return true end
  if screen.shown then return false end
  if tune.customizedRagdoll == true then return false end
  local m = tune.deathScreen
  if m == "game" then return false end
  if m == "key" then return true end
  return t < (tune.reviveAt or 10)
end
-- one hook a call, a second apart: all four in one tick were a 206-213 ms freeze while she played, once a session
-- (playtest); hook = { left = { [f] = what }, got = {} }
function screen.hook()
  if screen.hooked or os.clock() < (screen.retry or 0) then return end
  screen.retry = os.clock() + 1
  if not valid(try(function() return StaticFindObject("/Game/Art/UI/Widget/HUD/WB_MainHUD_Dead.WB_MainHUD_Dead_C") end)) then return end
  local hk = screen.hookQ
  if not hk then
    hk = { left = {}, got = {} }
    for f, what in pairs(SCREEN_FNS) do hk.left[f] = what end
    screen.hookQ = hk
  end
  local f, what = next(hk.left)
  if f then
    hk.left[f] = nil
    local ok = pcall(RegisterHook, "/Game/Art/UI/Widget/HUD/WB_MainHUD_Dead.WB_MainHUD_Dead_C:" .. f, function()
      -- (any time: a death the mod never saw is told by it, hm.dead_proof)
      if what == "shown" then screen.youDieAt = os.clock() end
      if not active then return end
      if what == "shown" then
        if not screen.seen then log("death screen: " .. f) end
        screen.seen = true
      else
        if not screen.press then log("death screen: " .. f) end
        screen.press = true
      end
    end)
    if ok then hk.got[#hk.got + 1] = f end
    if next(hk.left) then return end
  end
  screen.hooked = true
  table.sort(hk.got)
  log("hook death screen: " .. (#hk.got > 0 and table.concat(hk.got, ", ") or "none"))
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
screen.SHOWN_S, screen.GONE_S = 1.5, 0.75
local REVIVE_WAIT = 2.5
function screen.revive(t)
  local rv = screen.rv
  screen.intro_look()
  screen.fade_in()
  if not active or saved.manual then
    for f, vis in pairs(rv.held or {}) do
      local w = vis and dead_hud.get(f)
      if w then try(function() w:SetVisibility(vis); w:SetIsEnabled(true) end) end
    end
    for _, w in pairs(rv.ghost or {}) do if valid(w) then try(function() w:SetRenderOpacity(1) end) end end
    rv.held, rv.up, rv.down, rv.told, rv.ghost = nil, nil, nil, nil, nil
    return
  end
  if dead_hud.made and not rv.told then
    rv.told = true
    log(string.format("revive screen: made %.1f s into the death: %s", t, dead_hud.made))
  end
  local on = false
  for _, f in ipairs({ "w", "rv" }) do
    -- (the death screen looked for by class from 1 s in when not caught as it was made: the fall's first second is
    -- busy. The revive item's is made in the death, always caught)
    local w = dead_hud.get(f, f == "w" and t >= 1)
    if w then
      local vis = try(function() return w:GetVisibility() end) or 1 -- 1 collapsed, 2 hidden
      local up = vis ~= 1 and vis ~= 2 and try(function() return w:IsVisible() end) ~= false
      rv.held = rv.held or {}
      if screen.hiding(t) then
        if up then
          if not rv.held[f] then
            rv.held[f] = vis
            log(string.format("revive screen: %s up %.1f s into the death, held hidden %s",
              tostring(try(function() return w:GetClass():GetFName():ToString() end)), t,
              screen.frozen and "while the death is held (Shift+F4)" or tune.deathScreen == "key" and "till Shift+F4"
              or string.format("till %.0f s", tune.reviveAt or 10)))
          end
          try(function() w:SetVisibility(1); w:SetIsEnabled(false) end)
        end
      elseif rv.held[f] ~= nil and rv.held[f] ~= false then
        try(function() w:SetVisibility(rv.held[f]); w:SetIsEnabled(true) end)
        rv.held[f], up = false, true
        rv.shown, screen.shownAt = true, os.clock()
        log(string.format("revive screen: shown %.1f s into the death%s", t, screen.skip_intro(w)))
        if screen.shown == true then
          try(function() w:SetRenderOpacity(0) end)
          screen.fade = { w = w, t = os.clock() }
        end
      end
      -- Customized Ragdoll support, as that mod has it: the screen up as the game puts it but see-through, its keys
      -- (F / R) working, no holding needed; Shift+F4 shows it (fading in), and once shown holds the death as ever
      if up and tune.customizedRagdoll == true and not screen.frozen then
        rv.ghost = rv.ghost or {}
        if not screen.shown then
          if not rv.ghost[f] then
            rv.ghost[f] = w
            log(string.format("death screen: %s up %.1f s into the death, see-through (Customized Ragdoll support), its keys working",
              tostring(try(function() return w:GetClass():GetFName():ToString() end)), t))
          end
          try(function() w:SetRenderOpacity(0) end)
        elseif rv.ghost[f] then
          rv.ghost[f] = nil
          screen.fade = { w = w, t = os.clock() }
          log(string.format("death screen: shown %.1f s into the death", t))
        end
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
-- a screen shown after being held hidden: its intro (the death screen's You Die, 3.98 s) doesn't run while it is
-- collapsed, so it played from its start once shown: 2-3 s after Shift+F4 before anything showed (playtest). Put at
-- its end it popped up with no animation; sped up it was no longer the game's (playtest). So shown by Shift+F4, it
-- plays at the game's own speed from INTRO_FROM s in, past its lead-in (a guess, read from the log's opacity
-- samples below). Returns a note for the log
screen.INTRO_FROM = 2.0
-- and as its intro is half in by then (the opacity samples: 5 of 10.9 at 2 s), it popped in with no transition
-- (playtest): the whole screen fades in over FADE_S as well
screen.FADE_S = 0.5
function screen.fade_in()
  local f = screen.fade
  if not f then return end
  local k = math.min(1, (os.clock() - f.t) / screen.FADE_S)
  if not valid(f.w) then screen.fade = nil; return end
  try(function() f.w:SetRenderOpacity(k * k * (3 - 2 * k)) end)
  if k >= 1 then screen.fade = nil end
end
function screen.skip_intro(w)
  local out = {}
  local cls = try(function() return w:GetClass() end)
  local jump = screen.shown == true
  try(function()
    cls.Animations:ForEach(function(_, e)
      local a = e:get()
      if not valid(a) then return end
      local nm = tostring(try(function() return a:GetFName():ToString() end))
      if try(function() return w:IsAnimationPlaying(a) end) ~= true then return end
      local at, en = try(function() return w:GetAnimationCurrentTime(a) end), try(function() return a:GetEndTime() end)
      local from = jump and en and math.min(screen.INTRO_FROM, en - 0.1) or nil
      if from and (at or 0) < from then try(function() w:SetAnimationCurrentTime(a, from) end) else from = nil end
      out[#out + 1] = string.format("%s %.2f/%.2f s%s", nm, at or -1, en or -1, from and string.format(", from %.2f s", from) or "")
      screen.introLook = screen.introLook or { w = w, a = a, t = os.clock(), next = 0, line = {} }
    end)
  end)
  return #out > 0 and (", intro at the game's speed: " .. table.concat(out, ", ")) or ", no animation playing"
end
-- the intro's opacity over time, logged once as it finishes: the summed opacity of every visible widget under the
-- screen, each 0.25 s with the animation's own time, so INTRO_FROM can be put where something first shows
function screen.intro_look()
  local L = screen.introLook
  if not L then return end
  local now = os.clock()
  if now < L.next then return end
  L.next = now + 0.25
  local w, a = L.w, L.a
  local playing = valid(w) and try(function() return w:IsAnimationPlaying(a) end) == true
  if not playing or now - L.t > 6 then
    screen.introLook = nil
    log("revive screen: intro opacity (anim time = summed opacity): " .. table.concat(L.line, ", "))
    return
  end
  local sum = 0
  local function walk(x, depth)
    if not valid(x) or depth > 12 then return end
    local v = try(function() return x:GetVisibility() end)
    if v == 1 or v == 2 then return end
    local op = try(function() return x:GetRenderOpacity() end) or 1
    if op <= 0.01 then return end
    local n = try(function() return x:GetChildrenCount() end)
    if not n or n == 0 then sum = sum + op; return end
    for k = 0, n - 1 do walk(try(function() return x:GetChildAt(k) end), depth + 1) end
  end
  walk(try(function() return w.WidgetTree.RootWidget end), 0)
  L.line[#L.line + 1] = string.format("%.2f=%.1f", try(function() return w:GetAnimationCurrentTime(a) end) or -1, sum)
end
-- the rest of the HUD hidden through a death (tune.hideHud): her HP bar, skills, minimap, notices, all inside
-- WB_MainHUD_Master, which holds the death screen too. Every widget in it is collapsed but the branch down to the
-- death and revive screens (by class or name), put back as the death ends. Asked for in a comment on Nexus (another
-- ragdoll mod hides the UI on death)
screen.hudHid = nil -- { master = kept, list = { { w, vis } } }
screen.HUD_KEEP = { "Dead", "Resurrection", "Revive" }
function screen.hud_keeps(w)
  local n = tostring(try(function() return w:GetFName():ToString() end)) .. " "
    .. tostring(try(function() return w:GetClass():GetFName():ToString() end))
  for _, k in ipairs(screen.HUD_KEEP) do if n:find(k, 1, true) then return true end end
  return false
end
-- whether a widget holds a kept one (a panel: its children, depth at most 6; a user widget isn't looked into)
function screen.hud_holds(w, depth)
  if screen.hud_keeps(w) then return true end
  if depth > 6 then return false end
  local n = try(function() return w:GetChildrenCount() end) or 0
  for i = 0, n - 1 do
    local c = try(function() return w:GetChildAt(i) end)
    if valid(c) and screen.hud_holds(c, depth + 1) then return true end
  end
  return false
end
function screen.hud_hide(depth, panel, list)
  local n = try(function() return panel:GetChildrenCount() end) or 0
  for i = 0, n - 1 do
    local c = try(function() return panel:GetChildAt(i) end)
    if valid(c) and not screen.hud_keeps(c) then
      if screen.hud_holds(c, depth + 1) then screen.hud_hide(depth + 1, c, list)
      else
        local vis = try(function() return c:GetVisibility() end)
        if vis and vis ~= 1 and vis ~= 2 then
          try(function() c:SetVisibility(1) end)
          list[#list + 1] = { w = c, vis = vis }
        end
      end
    end
  end
end
function screen.hud(t)
  local h = screen.hudHid
  if not active or saved.manual or tune.hideHud == false then
    if h then
      screen.hudHid = nil
      local n = 0
      if goreCtx.held(h.master) then
        for _, x in ipairs(h.list) do
          if valid(x.w) then try(function() x.w:SetVisibility(x.vis) end); n = n + 1 end
        end
      end
      log(string.format("HUD: %d widgets shown again", n))
    end
    return
  end
  if h or t < 0.3 then return end
  -- the master: off the death screen's outers (its widget tree, then the master), else kept from the last death, else
  -- looked for (one scan a death at most)
  local m
  local w = dead_hud.get("w")
  if w then
    m = try(function() return w:GetOuter():GetOuter() end)
    if not (valid(m) and tostring(try(function() return m:GetClass():GetFName():ToString() end)) == "WB_MainHUD_Master_C") then m = nil end
  end
  if not m and screen.hudMaster and goreCtx.held(screen.hudMaster) then m = screen.hudMaster.obj end
  if not m then
    for _, x in ipairs(try(function() return FindAllOf("WB_MainHUD_Master_C") end) or {}) do
      if valid(x) and not tostring(try(function() return x:GetFName():ToString() end)):find("^Default__") then m = x end
    end
  end
  local k = m and goreCtx.keep(m)
  -- (its index read now, while it is surely alive: held reads it only within keepFresh s of keep)
  if not (k and goreCtx.held(k)) then screen.hudHid = { master = k or {}, list = {} }; log("HUD: no WB_MainHUD_Master, left up"); return end
  screen.hudMaster = k
  local root = try(function() return m.WidgetTree.RootWidget end)
  local list = {}
  if valid(root) then screen.hud_hide(0, root, list) end
  screen.hudHid = { master = k, list = list }
  log(string.format("HUD: %d widgets hidden for the death", #list))
end
function screen.probe(pawn)
  screen.n = screen.n + 1
  try(function() screen.hud(polls * POLL_MS / 1000 + ahead) end)
  -- (asked while new: a kept object's index is read at its first check, within keepFresh s of being made)
  if dead_hud.w and not dead_hud.w.idx then dead_hud.get("w") end
  if dead_hud.rv and not dead_hud.rv.idx then dead_hud.get("rv") end
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
    -- gone only once it read hidden for GONE_S, and not in its first SHOWN_S after it was shown (Shift+F4, reviveAt):
    -- shown again after the mod held it, it read hidden a moment and she got up the moment it came (playtest)
    local now = os.clock()
    if screen.vis and not screen.frozen and now - (screen.shownAt or -100) >= screen.SHOWN_S then
      screen.offSince = screen.offSince or now
      if now - screen.offSince >= screen.GONE_S and not screen.gone then
        log(string.format("death screen: gone %.1f s into the death", polls * POLL_MS / 1000 + ahead)); screen.last = nil
        screen.gone = true
      end
    end
    if not (screen.seen and dead_hud.get("w")) then return end
  else
    screen.vis, screen.seen, screen.offSince = true, true, nil
  end
  local w = dead_hud.get("w")
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
  local gs = goreCtx.statics()
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
  if goreCtx.struggle then try(function() goreCtx.struggle.start(pawn, mesh) end) end
  ah.n, ah.armedBy, ah.t0, ah.blunt = 0, {}, os.clock(), nil
  no_snapshot(pawn)
  hold = nil
  hold_capsule(pawn)
  camera_hold(pawn)
  deaths = deaths + 1
  active, polls, ahead = true, 0, 0
  screen.deathAt = os.clock()
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
  camera_release(pawn)
  skip_stop("she got up")
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

local function sandbox_recover(why)
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not valid(mesh) then return end
  try(function() mesh:SetAllBodiesSimulatePhysics(false) end)
  try(function() mesh:SetSimulatePhysics(false) end)
  -- a cut on a living Eve (F9) never starts a full ragdoll, so undo it here too
  if gore and not active then gore.cleanup(pawn, mesh) end
  if rag and not active then rag.stop(pawn) end
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
screen.late[#screen.late + 1] = function()
  goreCtx.newobj.watch("/Script/SB.SBCharacter", add_char)
end
local function live_chars()
  -- (none till sbslice is up: held() can't tell yet, and a character it said no to would be dropped for good)
  local g = goreCtx.gore
  if not (g and g.native_ready and g.native_ready()) then return {} end
  if goreCtx.reseed and os.clock() - (goreCtx.seededAt or -99) > 5 then charsSeeded, goreCtx.reseed = false, nil end
  -- (not watched as they spawn: the new ones found by a seed every 10 s)
  if goreCtx.newobj.mode() == "off" and os.clock() - (goreCtx.seededAt or -99) > 10 then charsSeeded = false end
  if not charsSeeded then
    charsSeeded, goreCtx.seededAt = true, os.clock()
    for _, a in ipairs(try(function() return FindAllOf("SBCharacter") end) or {}) do add_char(a) end
  end
  local out = {}
  for ad, e in pairs(chars) do
    if goreCtx.held(e.k) then
      out[#out + 1] = { obj = e.obj, addr = ad, cls = e.cls, k = e.k }
    else
      -- (one spawned while no tick ran, a level loading, came too late to be checked: found again by a new seed)
      if e.k.stale then goreCtx.reseed = true end
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
    -- (one already followed is kept out to swingKeep times the reach, its trail with it: the dual-blade enemy stepped
    -- back past 5 m and in again between attacks, its trail started over each time, and the blow that came right
    -- after went unseen, 5 of 9 deaths a playtest)
    local reach = g.swingReach or 500
    local cand = {}
    for _, a in ipairs((sw.near(mesh, reach * (g.swingKeep or 2.5)))) do
      if a.d < reach or had[a.addr] then cand[#cand + 1] = a end
      if #cand >= (g.swingFollow or 3) then break end
    end
    for _, a in ipairs(cand) do
      local S = had[a.addr]
      if not S then
        local m = try(function() return a.actor.Mesh end)
        if valid(m) and a.cls then
          S = sw.state()
          S.addr, S.actor, S.mesh, S.who, S.k, S.cls = a.addr, a.actor, m, name(a.actor), a.k, a.cls
          S.bones = swing_bones(m, a.cls)
          S.weapons = swing_weapons(a.actor)
          local ws = {}
          for _, w in ipairs(S.weapons) do ws[#ws + 1] = string.format("%s %.0f cm on %s", w.name, w.cm, w.socket) end
          log(string.format("swing: %s holds %s", a.cls, #ws > 0 and table.concat(ws, ", ") or "no weapon mesh"))
        end
      end
      if S then list[#list + 1] = S end
    end
    -- (why one followed was let go: the trail goes with it)
    local kept = {}
    for _, S in ipairs(list) do kept[S.addr] = true end
    for addr, S in pairs(had) do
      if not kept[addr] then
        local far
        for _, a in ipairs(cand) do if a.addr == addr then far = a.d end end
        log(string.format("swing: %s no longer followed (%s)", tostring(S.who),
          far and string.format("%.0f cm off", far) or string.format("hidden, gone or past %.0f cm", reach * (g.swingKeep or 2.5))))
      end
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
  local perw = {} -- each weapon's best step (a second blade of the swing: a cross slash with two)
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
              if not perw[k] or sc < perw[k].sc then perw[k] = c end
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
    -- a step's plane: the faster end's motion (a blade turning about its grip: the tip's), the midpoint's when it
    -- barely moved, across the blade (a thrust runs along the blade: no plane from it)
    local function plane(x)
      local e, o = h[x.i].w[x.k], h[x.i - 1].w[x.k]
      local ta, tb = sub(e.a, o.a), sub(e.b, o.b)
      local dir = unit(len(tb) >= len(ta) and tb or ta)
      local blade = unit(sub(e.b, e.a))
      local c = dir and blade and cross(blade, dir)
      if c and len(c) > 0.3 then return dir, unit(c) end
    end
    local dir, n = plane(bw)
    if n then
      local w = swing.weapons[bw.k]
      -- the other weapon's best step, when it swept another part of her within swingMiss (a cross slash with two
      -- blades took one arm, the second blade's never came off, playtest question): cut along its own plane too
      -- (of the same blow: as fast as half the first blade and within 0.15 s of it, on another limb. A slow 2900 cm/s
      -- drift of the idle blade past her calf 0.28 s before passed for one, under a slash through the same leg)
      local function limb(p) local sd = p and p:match("^Bip001%-(%a)%-"); return sd and (sd .. ((p:find("Arm") or p:find("Hand")) and "arm" or "leg")) or p end
      local two
      for k, x in pairs(perw) do
        if k ~= bw.k and x.d and x.d <= (g.swingMiss or 45) and x.part and limb(x.part) ~= limb(bw.part)
          and x.speed >= math.max(minv, 0.5 * bw.speed) and math.abs(h[x.i].t - h[bw.i].t) <= 0.15
          and (not two or x.sc < two.sc) then two = x end
      end
      local second
      if two then
        local d2, n2 = plane(two)
        local w2 = swing.weapons[two.k]
        if n2 then
          second = { dir = d2, n = n2, at = two.at, part = two.part, part_d = two.d, speed = two.speed,
            ago = os.clock() - h[two.i].t, bone = w2 and (w2.name .. " on " .. w2.socket) or "weapon" }
          log(string.format("swing: its second blade (%s) %.2f s before, %.0f cm from her %s at %.0f cm/s",
            second.bone, second.ago, two.d, tostring(two.part), two.speed))
        end
      end
      return { dir = dir, n = n, how = "blade " .. (w and w.name or "weapon"), at = m1, speed = bw.speed,
        bone = w and (w.name .. " on " .. w.socket) or "weapon", fwd = fwd, ago = os.clock() - h[bw.i].t, pose = h[bw.i].pose,
        part = bw.part, part_d = bw.d, second = second }
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
        attacker = swing.who, pose = ws.pose, pose_ago = ws.ago, second = ws.second, wbone = ws.bone }
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

-- ---- blunt or sharp (tune.gore.smash, experimental) ----
-- A killing blow from a blunt weapon smashes the part it landed on to meat (gore.smash) instead of cutting it. What
-- hit her is told by names, each against smash.sharp first, then smash.blunt: the weapon meshes of the enemy that
-- swung, its swinging bone, then the enemy itself (its name and class). Failing those, a bare hand or foot with no
-- weapon mesh is blunt (smash.bareHands), and so is a blow from above with no weapon (a stomp). Anything else cuts.
-- Returns blunt (true / false) and why. Asked with gore.smash or gore.bluntRagdoll on, else every blow is a blade.
-- real: what hit her only, smash.always aside (bluntRagdoll's ask)
function sw.blunt_of(h, real)
  local g = tune.gore or {}
  local s = g.smash or {}
  if (s.enabled ~= true and g.bluntRagdoll ~= true) or not h then return false, "off" end
  if s.enabled == true and s.always == true and not real then return true, "smash.always" end
  local function judge(what, text)
    local low = tostring(text or ""):lower()
    if low == "" then return nil end
    for _, list in ipairs({ { s.sharp or {}, false }, { s.blunt or {}, true } }) do
      for _, w in ipairs(list[1]) do
        if low:find(tostring(w):lower(), 1, true) then return list[2], string.format("%s %s: %s", what, text, w) end
      end
    end
  end
  -- (the swing's weapons only when it was the swing that killed her: a made-up blow names the nearest enemy)
  local mine = h.attacker == nil or h.attacker == swing.who
  local weapons = mine and swing.weapons or {}
  for _, w in ipairs(weapons) do
    local b, why = judge("weapon", w.name)
    if why then return b, why end
  end
  local wb = h.wbone
  if wb then
    local b, why = judge("weapon bone", wb)
    if why then return b, why end
  end
  for _, t in ipairs({ h.attacker or swing.who, mine and swing.cls or nil }) do
    local b, why = judge("enemy", t)
    if why then return b, why end
  end
  if #weapons == 0 and s.bareHands ~= false and wb then
    local low = wb:lower()
    for _, w in ipairs({ "hand", "fist", "foot", "toe", "knee", "elbow" }) do
      if low:find(w, 1, true) then return true, string.format("bare %s (%s), no weapon mesh", w, wb) end
    end
  end
  local d = h.dir
  if #weapons == 0 and d and len(d) > 1e-3 and d.Z / len(d) < -(g.splitDown or 0.6) then
    return true, "a blow from above with no weapon (a stomp)"
  end
  return false, string.format("nothing blunt about %s%s", tostring(h.attacker or swing.who),
    wb and (" (" .. wb .. ")") or "")
end
-- a blunt killing blow smashed (gore.smash); true when it did. why: "death"
function sw.smash_kill(pawn, mesh, h, why)
  if not (gore and gore.smash) or (tune.gore or {}).enabled == false then return false end
  local blunt, how = sw.blunt_of(h)
  log(string.format("death: the blow is %s (%s)", blunt and "blunt" or "a blade", how))
  if not blunt then return false end
  local ok, r, later = pcall(gore.smash, pawn, mesh, h, why)
  if not ok then log("smash failed: " .. tostring(r)); return false end
  return r, later
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
  for _, c in ipairs(try(function() return FindAllOf("SBLaserComponent") end) or {}) do
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
-- the fastest step one followed enemy's weapon just made (its blade meshes before its bones), nil with no fresh step
function sw.after_step(S, g)
  local hist = S.hist
  if not (S.bones or S.weapons) or #hist < 2 or os.clock() - hist[#hist].t > 0.2 then return nil end
  local a, b = hist[#hist - 1], hist[#hist]
  local dt = b.t - a.t
  if dt < 1e-3 then return nil end
  local best
  for i = 1, #(S.bones or {}) do
    local p, q = a.p[i], b.p[i]
    if p and q then
      local v = dist(p, q) / dt
      if not best or v > best.v then best = { v = v, i = i, p = p, q = q, name = S.bones[i] } end
    end
  end
  local bb
  for k, e in pairs(b.w or {}) do
    local o = a.w and a.w[k]
    if o then
      local v = math.max(dist(o.a, e.a), dist(o.b, e.b)) / dt
      if not bb or v > bb.v then
        local w = S.weapons[k]
        local mid = function(x) return { X = (x.a.X + x.b.X) / 2, Y = (x.a.Y + x.b.Y) / 2, Z = (x.a.Z + x.b.Z) / 2 } end
        local far = dist(o.b, e.b) >= dist(o.a, e.a)
        bb = { v = v, p = far and o.b or o.a, q = far and e.b or e.a, name = w and w.name or "weapon",
          steps = { { o.a, e.a }, { mid(o), mid(e) }, { o.b, e.b } }, blade = unit(sub(e.b, e.a)) }
      end
    end
  end
  if bb and bb.v >= (g.swingMinSpeed or 300) then best = bb end
  return best
end
local function hits_after(pawn, mesh)
  local g = tune.gore or {}
  local c = g.afterHits or {}
  if not gore then return end
  -- every enemy followed, not only the nearest (the one swinging at her body needn't be: enemies.lua's swings after
  -- death), each armed again once its own weapon slowed down (one cut a swing)
  local best, S
  for _, x in ipairs(#sw.list > 0 and sw.list or { swing }) do
    local st = sw.after_step(x, g)
    if st and st.v < (g.swingMinSpeed or 300) then ah.armedBy[x.addr or 0] = true
    elseif st and (not best or st.v > best.v) then best, S = st, x end
  end
  if not best then return end
  local hist = S.hist
  if ah.blunt or not ah.armedBy[S.addr or 0] or ah.n >= (c.max or 6) or os.clock() - ah.t0 < (c.from or 0.6) or gore.busy() then return end
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
  ah.armedBy[S.addr or 0], ah.n = false, ah.n + 1
  -- the plane: the arc through the last three samples, else the step and the enemy's forward
  local dir = unit(sub(best.q, best.p))
  local fwd = goreCtx.held(S.k) and try(function() return vof(S.actor:GetActorForwardVector()) end)
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
    os.clock() - ah.t0, tostring(S.who), best.name, best.v, d, bone, ah.n, c.max or 6,
    split and ", she is split: blood only" or ""))
  gore.on_hit(pawn, mesh, at)
  if split then return end
  gore.aim(dir)
  -- a split needs her whole: once something is off her, a blow through her body is a hit mark instead
  local h = { t = os.clock(), loc = at, dir = dir, fwd = fwd or dir, n = n, how = how, push = dir, attack_dir = 0,
    bone = bone, noSplit = ncut > 0, attacker = S.who }
  -- (the marks off, as they ship: every hit cuts. The cutChance share alone left a quarter of them showing nothing,
  -- playtest)
  local marks = (g.hitMarks or {}).enabled ~= false
  if (not marks or math.random() <= (c.cutChance or 0.75)) and gore.blow(pawn, mesh, h, "after") then return end
  if not marks then log("after death: the hit didn't cut, and hit marks are off: blood only"); return end
  gore.hit_mark(pawn, mesh, at, dir, nil)
end

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
  for _, k in ipairs(KINDS) do total = total + math.max(tonumber(odds[k]) or 0, 0) end
  local sp = math.max(tonumber(odds.split) or 0, 0)
  -- (odds that are all split still split every death, blade or not)
  local follow = math.min(math.max(tonumber(g.bladeFollow) or 1, 0), 1)
  if seen and not (total > 0 and sp >= total) and math.random() < follow then return "blade" end
  if near then
    local nt = 0
    for _, k in ipairs(KINDS) do nt = nt + math.max(tonumber(odds[k]) or 0, 0) * (near[k] or 0) end
    if nt > 0 then sp, total = sp * (near.split or 0), nt end
  end
  if g.deathSplit ~= false and total > 0 and math.random() * total < sp then
    return "split", odds.split, total
  end
  -- (no blade seen: "blade" still, which gore_cut rolls the odds for as a made-up blow)
  return seen and "odds" or "blade"
end
-- the killing cut made at the hit on a blow she lived through (a revive, a skill, her bar back up, no death within
-- LIVED_S): it stayed on her alive, a stump's seam at her neck as she played on (reported). Undone as the death's end
-- undoes it
hm.LIVED_S = 6
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
  -- (a death came after the hit: the cut was its own, undone with it at its end. A death that began 5 s or more after
  -- the hit left it on record, gore_cut not taking it, and her first tick up logged "she lived" and cleaned up again)
  if hm.lethal and hm.lethal.cut and (screen.deathAt or -1) >= hm.lethal.t then hm.lethal.cut = nil end
  if hm.lethal and hm.lethal.cut and os.clock() - hm.lethal.t > hm.LIVED_S then
    hm.lived(pawn, mesh, string.format("no death %d s after her HP bar hit 0", hm.LIVED_S))
  end
  local pct = goreCtx.glass.bar_pct(true)
  -- (the HUD looked for, 35 ms, at most every 30 s till it is found: it is kept after that)
  if not pct and os.clock() >= (hm.barTry or 0) then
    hm.barTry = os.clock() + 30
    pct = goreCtx.glass.bar_pct(false)
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
      local scripted = mn and hm.scripted(mn) or not fall and mm == 3 and "falling, a kill volume" or nil
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
      end
    end
  end
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
  -- (the blow seen: a blunt one crunches, a blade slices)
  local h = ws and death_hit(pawn, mesh)
  local blunt = h and not h.made and sw.blunt_of(h)
  if at then gore.wound(pawn, mesh, at, blunt and "crunch" or nil) end
  log(string.format("lethal hit: her HP bar at 0, the wound %s", at and ("at " .. v3(at) .. (ws and ws.part and (" (" .. ws.part .. ")") or "")) or "nowhere (no blade seen)"))
  -- gore.bluntRagdoll: a blunt killing blow cuts nothing, the death is a plain ragdoll (gore_cut)
  if g.bluntRagdoll == true and h and not h.made then
    local b, how = sw.blunt_of(h, true)
    if b then
      log("lethal hit: the blow is blunt (" .. how .. "): no cut, a plain ragdoll (bluntRagdoll)")
      hm.lethal.blunt, hm.lethal.roll, hm.lethal.judged = true, "none", true
      return
    end
  end
  -- a limb, the head or her body the blade took is cut now, on her animated body (gore.blow's h.early), and opens
  -- over openTime; a split waits for the death, and so do the blow's further cuts (gore.release_held at the death)
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
    if later == "later" then return end
  end
  if hm.lethal.roll ~= "blade" then return end
  h = h or death_hit(pawn, mesh)
  if not (h and not h.made and (h.n or (h.dir and h.fwd))) then return end
  h.early = true
  local fly = h.push or h.dir
  if fly then gore.aim(fly) end
  local ok, err = pcall(gore.blow, pawn, mesh, h, "death")
  if ok and err then hm.lethal.cut, hm.lethal.h = true, h
  elseif not ok then log("lethal hit: early cut failed: " .. tostring(err)) end
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
hm.BLOCK_STANCE, hm.SWORD_LAB = "P_Eve_BlockSword", "^AltesLab"
function hm.stance_of(pawn) return try(function() return pawn:GetCurrentStanceName():ToString() end) end
function hm.level(pawn)
  local gs = goreCtx.statics()
  return valid(gs) and try(function() return gs:GetCurrentLevelName(pawn, true):ToString() end) or nil
end
function hm.sword_later_tick(pawn)
  local w = hm.swordLater
  if not w or not valid(pawn) then return end
  local st, lvl = hm.stance_of(pawn), hm.level(pawn)
  if st and st ~= hm.BLOCK_STANCE then
    hm.swordLater = nil
    log("low HP arm: out of the swordless stance (the game gave her sword back): nothing left to lift")
  elseif lvl and not lvl:find(hm.SWORD_LAB) then
    hm.swordLater = nil
    log("low HP arm: out of Altess Levoire (" .. lvl .. "): sword back (" .. tostring(select(2, pcall(goreCtx.tables.sword_gate, false))) .. ")")
  end
end
function hm.low_block(pawn, on, why)
  local b = hm.lowBlock
  local a = valid(pawn) and try(function() return pawn:GetAddress() end)
  if on and hm.lowSide == "right" then
    if b or not a or not goreCtx.tables then return end
    if hm.swordLater then
      -- (ours still on, its end waiting: kept)
      hm.swordLater = nil
      hm.lowBlock = { pawn = a, sword = true }
      log("low HP arm: " .. why .. ": no sword (the stance still on)")
      return
    end
    local lvl = hm.level(pawn)
    if hm.stance_of(pawn) == hm.BLOCK_STANCE then
      hm.lowBlock = { pawn = a, sword = true, game = true }
      log("low HP arm: " .. why .. ": no sword already (the game's own block" .. (lvl and (", " .. lvl) or "") .. "): left to the game")
      return
    end
    hm.lowBlock = { pawn = a, sword = true, level = lvl }
    log("low HP arm: " .. why .. ": no sword (" .. tostring(select(2, pcall(goreCtx.tables.sword_gate, true))) .. ")")
    return
  end
  if not on and b and b.sword then
    hm.lowBlock = nil
    if b.game then log("low HP arm: " .. why .. ": the sword left to the game (its own block)"); return end
    local lvl = valid(pawn) and hm.level(pawn)
    -- (cut in it too, before the game took her sword there: its block came on over ours, and lifting ours lifted it)
    if lvl and lvl:find(hm.SWORD_LAB) and hm.stance_of(pawn) == hm.BLOCK_STANCE then
      hm.swordLater = { at = os.clock() }
      log("low HP arm: " .. why .. ": in Altess Levoire with no sword (the game's own block may be on too): " ..
        "the sword comes back as she leaves it, unless the game gives it back first")
      return
    end
    -- (its end fired whatever pawn she has now: a dispel of nothing does nothing)
    log("low HP arm: " .. why .. ": sword back (" .. tostring(select(2, pcall(goreCtx.tables.sword_gate, false))) .. ")")
    return
  end
  if on then
    if b or not a then return end
    b = { pawn = a, states = {} }
    hm.noticeKeys = nil
    local out = {}
    for _, st in ipairs(hm.LOW_STATES) do
      local r = gore.command(string.format("a%x,%x,1", a, st[2]))
      if r:match("^ok state") then b.states[#b.states + 1] = st[2] end
      out[#out + 1] = st[1] .. " " .. r
    end
    -- (and her gun's aim: its stances, ruled out by the shots' state)
    if goreCtx.tables then
      b.gate = true
      out[#out + 1] = "gun " .. tostring(select(2, pcall(goreCtx.tables.gun_gate, true)))
    end
    hm.lowBlock = b
    log("low HP arm: " .. why .. ": no heals or shots (" .. table.concat(out, "; ") .. ")")
    return
  end
  if not b then return end
  hm.lowBlock = nil
  -- (the skill table is the game's, not her pawn's: always put back)
  local gun = b.gate and goreCtx.tables and ("; gun " .. tostring(select(2, pcall(goreCtx.tables.gun_gate, false)))) or ""
  if a ~= b.pawn then log("low HP arm: " .. why .. ": its blocks went with her old pawn" .. gun); return end
  local out = {}
  for _, s in ipairs(b.states) do
    local r = gore.command(string.format("a%x,%x,0", a, s))
    -- (the game holding her at a life of 3-5 takes no take-off: cleared to 0 then, the game's own count with ours)
    local was, now = r:match("^ok state %d+ (%-?%d+) %-> (%-?%d+)")
    if was and tonumber(now) > 0 and now == was then r = r .. ", cleared: " .. gore.command(string.format("a%x,%x,3", a, s)) end
    out[#out + 1] = r
  end
  log("low HP arm: " .. why .. ": heals and shots back (" .. table.concat(out, "; ") .. gun .. ")")
end
-- lowArm.notice: her aim or a heal tried with the arm off (a key of her controller's TPSMode or Item_UseHeal mappings
-- going down, read when the blocks go on: a rebind shows at the next cut) answered by the game's own "Cannot use right
-- now." (UI_GetNotice_Fail_ActiveTpsMode, the line its refused aim shows) with its sound: sbslice U, the HUD's system
-- notice. At most once a second, not while the game is paused (a menu). The AZERTY layout's mappings are left out (its
-- heal key A is QWERTY's strafe left)
hm.NOTICE = "UStringTable_UI;UI_GetNotice_Fail_ActiveTpsMode"
function hm.low_notice(pawn)
  local la = (tune.gore or {}).lowArm or {}
  if la.notice == false then hm.noticeDown = nil; return end
  local gs = goreCtx.statics()
  local pc = valid(gs) and try(function() return gs:GetPlayerController(pawn, 0) end)
  if not valid(pc) then return end
  if not hm.noticeKeys then
    local keys, seen, names = {}, {}, {}
    try(function()
      pc.PlayerInput.ActionMappings:ForEach(function(_, e)
        local m = e:get()
        local act, key = m.ActionName:ToString(), m.Key.KeyName:ToString()
        local azerty = try(function() return m.bAZERTY end) == true
        if (act == "TPSMode" or act == "Item_UseHeal") and key ~= "None" and not azerty and not seen[key] then
          seen[key] = true
          keys[#keys + 1] = { KeyName = FName(key) }
          names[#names + 1] = act .. "=" .. key
        end
      end)
    end)
    if #keys == 0 then
      for _, k in ipairs({ "LeftControl", "Gamepad_LeftTrigger", "Q", "Gamepad_DPad_Up" }) do keys[#keys + 1] = { KeyName = FName(k) } end
      names[1] = "none read, the game's defaults"
    end
    hm.noticeKeys, hm.noticeDown = keys, {}
    log("low HP arm: 'Cannot use' notice on " .. table.concat(names, ", "))
  end
  -- (a key going down: polled, a tick may come later than the frame it was pressed in)
  local hit
  for i, k in ipairs(hm.noticeKeys) do
    local down = try(function() return pc:IsInputKeyDown(k) end) == true
    if down and not hm.noticeDown[i] then hit = true end
    hm.noticeDown[i] = down
  end
  local now = os.clock()
  if not hit or now - (hm.noticeAt or -10) < 1 then return end
  if try(function() return gs:IsGamePaused(pawn) end) == true then return end
  hm.noticeAt = now
  local r = gore.command(hm.NOTICE)
  if r ~= hm.noticeSaid then hm.noticeSaid = r; log("low HP arm: 'Cannot use' notice: " .. r) end
end
-- the parts grown back out of her (sbslice Z on every asset of hers with a part's bones: her body, an outfit's sleeve
-- or glove, her face and hair for a head), over lowArm.regrow s; each tick while they grow
function hm.low_regrow(pawn, mesh, T, parts)
  local comps = {}
  local cand = { mesh }
  try(function()
    for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.SkeletalMeshComponent"))) do cand[#cand + 1] = c end
  end)
  for _, part in ipairs(parts) do
    local jn, by = hm.GROW_JOINTS[part] or { part }, {}
    for _, c in ipairs(cand) do
      local sm = valid(c) and try(function() return c.SkeletalMesh:GetAddress() end)
      local i = sm and not by[sm] and try(function() return c:GetBoneIndex(FName(jn[1])) end)
      if i and i >= 0 then
        by[sm] = true
        local f = { try(function() return c:GetAddress() end), i }
        for k = 2, 3 do
          local j = jn[k] and try(function() return c:GetBoneIndex(FName(jn[k])) end)
          f[k + 1] = j and j >= 0 and j or 0xffff
        end
        if f[1] then comps[#comps + 1] = { c = c, f = f } end
      end
    end
  end
  if #comps == 0 then log("regrow: nothing of hers has the parts' bones: back at once"); return end
  hm.regrow = { t0 = os.clock(), T = T, comps = comps }
  log(string.format("regrow: %s growing back over %.1f s (%d meshes)", table.concat(parts, ", "), T, #comps))
  hm.grow_tick()
end
function hm.grow_tick()
  local r = hm.regrow
  if not r then return end
  local x = math.min((os.clock() - r.t0) / r.T, 1)
  if x >= 1 then hm.grow_stop("grown"); return end
  local f = {}
  for _, c in ipairs(r.comps) do
    if valid(c.c) and try(function() return c.c:GetAddress() end) == c.f[1] then
      f[#f + 1] = string.format("%x,%x,%x,%x,%x", c.f[1], c.f[2], c.f[3], c.f[4], math.floor(x * 1000 + 0.5))
    end
  end
  -- (eight meshes a command: sbslice reads 40 fields) The first frame asks: the bones it set on each mesh, -1 where it
  -- couldn't read one (the arm came back at once with no growing seen, playtest)
  for i = 1, #f, 8 do
    local z = "Z" .. table.concat(f, ",", i, math.min(i + 7, #f))
    if r.asked then gore.fire(z) else log("regrow: first frame: " .. gore.command(z)) end
  end
  r.asked = true
end
-- every matrix put back: grown, or stopped (her death)
function hm.grow_stop(why)
  if not hm.regrow then return end
  hm.regrow = nil
  gore.fire("Z")
  log("regrow: " .. why)
end
-- the parts dissolving back in (lowArm.dissolve, gore.ghost_begin: the cut stays on till they are in, then is undone);
-- each tick while they do. Done, stopped (her death, photo mode) or gone wrong: the ghost's copies away, the cuts undone
-- (once in: her own part back under the copy, which dissolves out over it in the last FADE_S, dissolve.fade)
hm.GHOST_FADE_S = 0.6
function hm.ghost_tick()
  local h = hm.ghost
  if not h then return end
  if screen.photoLive or screen.vtPhoto then hm.ghost_stop("photo mode: back at once"); return end
  local now = os.clock()
  if h.handed then
    local y = (now - h.handed) / h.F
    if y >= 1 then hm.ghost_stop("dissolved in"); return end
    try(function() gore.ghost_fade(h.g, y) end)
    return
  end
  local x = math.min((now - h.t0) / h.T, 1)
  try(function() gore.ghost_set(h.g, x) end)
  if x < 1 then return end
  if h.F <= 0 then hm.ghost_stop("dissolved in"); return end
  -- (the cut undone under the copy, kept on: gore.ghost_release)
  try(function() gore.ghost_release(h.g) end)
  local ok, err = pcall(gore.cleanup, h.pawn, h.mesh)
  if not ok then log("regrow: cleanup under the copy: " .. tostring(err)) end
  h.handed, h.cleaned = now, true
end
function hm.ghost_stop(why)
  local h = hm.ghost
  if not h then return end
  hm.ghost = nil
  if not h.handed then try(function() gore.ghost_set(h.g, 1) end) end
  local sk = try(function() return gore.ghost_end(h.g) end) or ""
  local ok, err = true, nil
  if not h.cleaned then ok, err = pcall(gore.cleanup, h.pawn, h.mesh) end
  log(string.format("regrow: %s %s after %.1f s%s%s", table.concat(h.parts, ", "), why, os.clock() - h.t0, sk,
    ok and "" or (", cleanup: " .. tostring(err))))
end
-- every part cut off her alive back: dissolving in (lowArm.dissolve.time s), else grown back (lowArm.regrow s) or at
-- once, the arm's blocks off
function hm.parts_back(pawn, mesh, why)
  local la = (tune.gore or {}).lowArm or {}
  -- (not while a cut still opens: its pieces aren't off yet, and the dissolve's copy took the wrong vertices, off
  -- where the arm was; the rest's sequence and the HP bar are read again next time)
  if gore.busy() then return end
  if hm.lowCut or hm.lowBlock then hm.lowCut = false; hm.low_block(pawn, false, why) end
  local parts = gore.cut_parts(mesh)
  if #parts == 0 then return end
  -- (its bodies stop simulating onto her pose, on her mesh: not on its copy)
  hm.piece_back("it grows back")
  log(string.format("regrow: %s: %s back", why, table.concat(parts, ", ")))
  -- (lowArm.effect false, F3's Regrow Effect: back at once)
  local fx = la.effect ~= false
  local d = la.dissolve
  local T = type(d) == "table" and tonumber(d.time) or (d == false and 0) or 3
  if fx and T > 0 then
    local ok, g, err = pcall(gore.ghost_begin, pawn, mesh, parts)
    if ok and g then
      local F = type(d) == "table" and tonumber(d.fade) or hm.GHOST_FADE_S
      hm.ghost = { g = g, t0 = os.clock(), T = T, F = F, pawn = pawn, mesh = mesh, parts = parts }
      log(string.format("regrow: %s dissolving back in over %.1f s", table.concat(parts, ", "), T))
      return
    end
    log("regrow: no dissolve (" .. tostring(ok and err or g) .. "): grown back instead")
  end
  try(function() gore.cleanup(pawn, mesh) end)
  if fx and (la.regrow or 1.5) > 0 then hm.low_regrow(pawn, mesh, la.regrow or 1.5, parts) end
end
-- a limb cut off her alive goes onto a copy of her mesh once it has lain still hm.STILL_S s (gore.hide_pieces, as
-- photo mode does), its bones hidden on her: grabbing a ladder, from the ground or in the air, drew her mesh on her
-- animation without its physics for a frame or two, and the cut-off arm was back on her shoulder for those frames
-- (Nexus report, 0.5.0). On the copy, not ticking, it lies where it fell whatever her mesh does. Limbs only (a head
-- takes her face and hair along, photo mode's). Back on her mesh as soon as anything needs it there: a cut, a regrow,
-- her death, an outfit change or an undo (gore.cleanup)
hm.STILL_S, hm.STILL_CM = 1.0, 2
function hm.piece_back(why)
  local h = gore and gore.pieceHid
  hm.still = nil
  if not (h and h.baked) then return end
  local np, nr = gore.hide_pieces(nil, nil, false)
  log(string.format("piece settled: %d piece(s) back on her mesh, with %d part(s) riding them (%s)", np, nr, why))
end
function hm.piece_watch(pawn, mesh)
  if not gore or not gore.hide_pieces then return end
  local h = gore.pieceHid
  if h and not h.baked then hm.still = nil; return end -- photo mode's
  local parts = gore.cut_parts(mesh, true)
  local busy = gore.busy() or hm.regrow or hm.ghost
  if h then
    local same = valid(h.mesh) and h.mesh:GetAddress() == mesh:GetAddress() and #parts == #h.roots
    if busy or not same then hm.piece_back(busy and "a cut or a regrow" or "her cut parts changed") end
    return
  end
  if busy or #parts == 0 or screen.photoLive or screen.vtPhoto or screen.frozenMesh then hm.still = nil; return end
  -- (a copy that failed for these parts isn't tried again till they change)
  local key = string.format("%x %s", mesh:GetAddress(), table.concat(parts, ","))
  if hm.stillFailed == key then return end
  for _, b in ipairs(parts) do
    if b == "Bip001-Head" or b == "Bip001-Spine1" then hm.still = nil; return end
  end
  local now, a = os.clock(), mesh:GetAddress()
  local s = hm.still
  if not s or s.mesh ~= a or s.n ~= #parts then s = { mesh = a, n = #parts, at = {}, t = now }; hm.still = s end
  for _, b in ipairs(parts) do
    local v = try(function() local l = mesh:GetSocketLocation(FName(b)); return { X = l.X, Y = l.Y, Z = l.Z } end)
    if not v then hm.still = nil; return end
    local o = s.at[b]
    if not o or dist(v, o) > hm.STILL_CM then s.at[b], s.t = v, now end
  end
  if now - s.t < hm.STILL_S then return end
  hm.still = nil
  local t0 = os.clock()
  local np, nr = gore.hide_pieces(pawn, mesh, true, true)
  local h = gore.pieceHid
  -- (no copy: the piece stays on her mesh, as before, not hidden with nothing to show it)
  if h and #h.copies == 0 then
    hm.stillFailed = key
    gore.hide_pieces(nil, nil, false)
    log("piece settled: no copy of her mesh for it, left on her mesh")
    return
  end
  log(string.format("piece settled: %d piece(s) onto a copy of her mesh, %d part(s) riding them, %.0f ms", np, nr,
    (os.clock() - t0) * 1000))
end
-- a camp rest: she sits down out of battle (her movement mode none, the camp's seat) with a part cut off her alive,
-- and then rests: the game's Camp_Restore sequence plays (the save, her heal, the enemies back), or her HP bar, under
-- full as she sat, is full within lowArm.restWindow s (the rest's heal; no heal item of hers does that with the arm
-- off). Any part: Lose Arm at Low HP's arm, and F9's. Sitting down alone grew them back as she sat, before the rest
-- (playtest: F9's come off at full HP, so the bar's check passed at once). The sequence is looked for (FindAllOf, 35
-- ms) once a second while she sits
hm.REST_SEQ = "Camp_Restore"
-- the camp's own chair: its sequence (Interaction_Camp_Chair) plays as she sits at a camp, not at another seat, and
-- the rest (the save, her heal, the enemies back) comes lowArm.restDelay (5) s later (playtest: her heal 5 s after
-- it both times), or as she gets up (Interaction_Camp_Chair_End). The game's save and zone reset were hooked on its
-- network controller first: never called through anything hookable (playtest), and the sequence's name read "?"
hm.CHAIR_SEQ, hm.CHAIR_END = "Interaction_Camp_Chair", "Interaction_Camp_Chair_End"
function hm.rest_seq()
  local seen = {}
  for _, a in ipairs(try(function() return FindAllOf("LevelSequenceActor") end) or {}) do
    local pl = valid(a) and try(function() return a.SequencePlayer end)
    if valid(pl) and try(function() return pl:IsPlaying() end) == true then
      -- (the player's sequence, else the actor's own LevelSequence path, else the actor's name)
      local sq = try(function() local q = pl:GetSequence(); return valid(q) and q:GetFullName() or nil end)
        or try(function() local q = a.LevelSequence.AssetPathName:ToString(); return q ~= "None" and q or nil end)
        or "?"
      local an = try(function() return a:GetFullName() end) or "?"
      seen[#seen + 1] = (sq:match("[^%.]+$") or sq) .. (sq == "?" and (" (" .. (an:match("[^%.:]+$") or an) .. ")") or "")
      if sq:find(hm.REST_SEQ, 1, true) or an:find(hm.REST_SEQ, 1, true) then return true, seen end
    end
  end
  return false, seen
end
function hm.rest_watch(pawn, mesh)
  -- (not in photo mode or a pause: photo mode stops her movement too, and the pieces sit on their copy)
  if not gore or (tune.gore or {}).enabled == false or hm.regrow or hm.ghost or gore.busy()
    or (gore.pieceHid and not gore.pieceHid.baked) or screen.photoLive
    or screen.vtPhoto or screen.frozenMesh then
    hm.restAt, hm.restSeat = nil, false
    return
  end
  local parts = gore.cut_parts(mesh)
  if #parts == 0 then hm.restAt, hm.restSeat = nil, false; return end
  local now = os.clock()
  local seated = try(function() return pawn.CharacterMovement.MovementMode end) == 0
    and try(function() return pawn:IsBattle() end) ~= true
  local pct = goreCtx.glass and goreCtx.glass.bar_pct(false)
  if seated then
    if not hm.restSeat then
      hm.restPct, hm.restSeqAt, hm.restSeqSeen, hm.restChair = pct, 0, {}, nil
      log(string.format("regrow: she sat down out of battle with %s off, her HP bar %s (a camp rest?)",
        table.concat(parts, ", "), pct and string.format("%.3f", pct) or "?"))
    end
    hm.restAt = now
  end
  hm.restSeat = seated
  local la = (tune.gore or {}).lowArm or {}
  if not hm.restAt or now - hm.restAt > (la.restWindow or 20) then return end
  -- at the camp's chair restDelay s, or up from it
  local ch = hm.restChair
  if ch and (ch.up or now - ch.t >= (la.restDelay or 5)) then
    hm.restAt, hm.restChair = nil, nil
    hm.parts_back(pawn, mesh, ch.up and "a camp rest (up from the camp's chair)"
      or string.format("a camp rest (%.0f s at the camp's chair)", now - ch.t))
    return
  end
  -- her heal: the bar under full as she sat, full now
  if pct and pct >= 0.99 and hm.restPct and hm.restPct < 0.99 then
    hm.restAt = nil
    hm.parts_back(pawn, mesh, string.format("a camp rest (her HP bar %.3f -> %.3f)", hm.restPct, pct))
    return
  end
  if now < (hm.restSeqAt or 0) then return end
  hm.restSeqAt = now + 1
  local rest, seen = hm.rest_seq()
  -- (each sequence seen playing logged once: the rest's own, if its name isn't Camp_Restore)
  for _, n in ipairs(seen) do
    if not hm.restSeqSeen[n] then hm.restSeqSeen[n] = true; log("regrow: sequence playing as she sits: " .. n) end
    if n == hm.CHAIR_SEQ and not hm.restChair then hm.restChair = { t = now } end
    if n == hm.CHAIR_END then hm.restChair = hm.restChair or { t = now }; hm.restChair.up = true end
  end
  if not rest then return end
  hm.restAt = nil
  hm.parts_back(pawn, mesh, "a camp rest (" .. hm.REST_SEQ .. " playing)")
end
-- her death's end, a load (recover): the arm back with every other cut, the blocks off (the game's own respawn may
-- clear them first: a take-off of none is no change)
function screen.low_reset(pawn, why)
  if hm.regrow then hm.grow_stop(why) end
  if hm.ghost then hm.ghost_stop("back at once: " .. why) end
  if hm.lowCut or hm.lowBlock then log("low HP arm: " .. why .. ": back") end
  hm.lowCut, hm.restAt, hm.lowLast, hm.lowPend = false, nil, nil, nil
  if hm.lowBlock then hm.low_block(pawn, false, why) end
end
function hm.low_arm(pawn, mesh)
  hm.grow_tick()
  hm.ghost_tick()
  -- (her arm cut again on a new Eve first: till then it reads as back, and the arm was taken for grown back)
  if hm.carry and not hm.carry.cut then return end
  if hm.swordLater then hm.sword_later_tick(pawn) end
  local g = tune.gore or {}
  local la = g.lowArm or {}
  local on = gore and g.enabled ~= false and la.enabled == true
  if not on then
    hm.lowLast, hm.lowPend = nil, nil
    -- (turned off in the menu with the arm off: it comes back at the next rest or life as it would, blocks off now)
    if hm.lowBlock then hm.low_block(pawn, false, "Lose Arm at Low HP off") end
    return
  end
  local now = os.clock()
  -- the blocks follow the menu's switch while the arm is off
  local right = hm.lowSide == "right"
  local block = hm.lowCut and (right and la.noSword ~= false or not right and la.noHealGun ~= false)
  if block and not hm.lowBlock then hm.low_block(pawn, true, "her " .. hm.lowSide .. " arm is off")
  elseif not block and hm.lowBlock then
    hm.low_block(pawn, false, hm.lowCut and (right and "No Sword off" or "No Heals or Gun off") or "the arm is back")
  end
  if hm.lowBlock and not hm.lowBlock.sword then hm.low_notice(pawn) end
  if not goreCtx.glass then return end
  -- (the HUD looked for at most every 5 s till found, 35 ms: glass.lua keeps it)
  local pct = goreCtx.glass.bar_pct(false)
  if not pct then return end
  local last = hm.lowLast
  hm.lowLast = pct
  -- a new bar (a new level, a level gone into: Altess Levoire) reads full till the game sets it, after its cutscene:
  -- full to her low HP read as a blow, and the arm that came back with the new level came off again, sound and all
  -- (reported). A new bar's first move down from full with no hit on her mesh is the game setting it, not a blow
  local bid = goreCtx.glass.bar_id and goreCtx.glass.bar_id()
  if bid ~= hm.lowBarId or (goreCtx.levelAt or -1) ~= hm.lowLevelAt then
    hm.lowBarId, hm.lowLevelAt, hm.lowBarSync = bid, goreCtx.levelAt or -1, true
  end
  -- (judged by nothing while it reads full: its healBack neither; the arm back with the level still seen below)
  local syncing = false
  if hm.lowBarSync then
    if pct >= 0.999 then
      syncing = true
    else
      hm.lowBarSync = false
      if last and last >= 0.999 and not (meshHit and now - meshHit.t < hm.LOW_HIT_S + 0.5) then
        syncing = true
        log(string.format("low HP arm: a new HP bar went from full to %.3f: the game setting it, not a blow", pct))
      end
    end
    if syncing then hm.lowPend = nil end
  end
  if hm.lowCut then
    -- (a camp rest: hm.rest_watch) lowArm.healBack: her HP back up to healAt any way at all (gear that heals on
    -- kills, over time)
    -- (at least 1% over the mark it came off under: a mark over healAt grew it back the tick after the cut)
    local at = math.max(la.healAt or 0.9, (la.below or 0.25) + 0.01)
    -- (and only once the bar was under it since the cut, the cut done: the test keys cut at full HP, and the arm and
    -- her sword were back the same tick, the dissolve begun on a cut still opening, on the wrong vertices; playtest)
    if pct < at and not syncing then hm.lowUnder = true end
    if la.healBack == true and not syncing and pct >= at and hm.lowUnder and now - (hm.lowT or 0) > 3 and not gore.busy() then
      hm.parts_back(pawn, mesh, string.format("her HP bar back at %.3f (healBack, %.2f)", pct, at))
    -- (undone by something else: a lethal hit she lived through, F8. Not while the cut still opens)
    elseif now - (hm.lowT or 0) > 3 and not gore.busy() and not gore.has_cut(mesh, hm.LOW_BONES[hm.lowSide]) then
      hm.lowCut = false
      hm.low_block(pawn, false, "the arm came back with the other cuts")
    end
    return
  end
  if syncing then return end
  if hm.regrow or hm.ghost then hm.lowPend = nil; return end
  -- a hit (the bar dropped since the last tick) that she lives through, leaving her under the mark. The bar slides
  -- down after a hit: a fall damage death read 0.499 -> 0.066 on its way to 0, the arm came off on the killing
  -- blow, and the cut opening as the death began kept the death from being seen (no ragdoll, the death screen at
  -- once; playtest). The cut waits till the bar has held still for SETTLE s above 0
  local p = hm.lowPend
  if not p then
    if not (last and pct < last - 0.002 and pct < (la.below or 0.25)) then return end
    local ws = weapon_swing(mesh)
    hm.lowPend = { from = last, t = now, t0 = now, dir = ws and ws.dir, at = ws and ws.at }
    return
  end
  if pct >= (la.below or 0.25) then
    log(string.format("low HP arm: her HP bar %.3f -> %.3f: back over the mark, not cut", p.from, pct))
    hm.lowPend = nil
    return
  end
  if pct ~= last then p.t = now; return end
  -- the bar reads 0 at about 1 % shown (a fall left her alive there, playtest): at 0 it waits LOW_ZERO_S for her
  -- death to start (her death's tick doesn't come here; screen.low_reset drops the wait)
  if now - p.t < (pct <= 0.0005 and hm.LOW_ZERO_S or hm.LOW_SETTLE) then return end
  hm.lowPend = nil
  -- a blow, not a fall: a drop as she lands (a drop of LOW_LAND_CM or more, LOW_LAND_S around it) with no hit on her
  -- mesh (the game's physical hit reaction) is the landing's damage. Any other drop is a blow: the physical hit
  -- reaction alone missed most of them (ranged hits, grabs, explosions; Nexus: under 70% it came off now and then)
  local struck = meshHit and meshHit.t >= p.t0 - hm.LOW_HIT_S
  local land = hm.landAny
  if not struck and land and math.abs(land.t - p.t0) < hm.LOW_LAND_S then
    log(string.format("low HP arm: her HP bar %.3f -> %.3f as she landed from a %.0f cm drop, no hit on her mesh: fall damage, not cut",
      p.from, pct, land.drop))
    return
  end
  if gore.busy() then return end
  -- (lowArm.side "hit", the default: the side of her the blow landed on, the mesh's hit bone or where it landed, else
  -- the weapon's sweep; one at random when it landed on her middle or nothing tells. "either": one at random. Either
  -- way the other one when that one is already off, F9's)
  local side, how = la.side, nil
  if side ~= "left" and side ~= "right" and side ~= "either" then
    local m = struck and meshHit or nil
    side, how = gore.hit_side(mesh, m and m.loc or p.at, m and m.bone)
    how = side and ("the blow landed " .. how) or ("no side to the blow (" .. how .. "), at random")
  end
  if side ~= "left" and side ~= "right" then side = math.random(2) == 1 and "left" or "right" end
  if la.side ~= "left" and la.side ~= "right" and gore.has_cut(mesh, hm.LOW_BONES[side]) then side = side == "left" and "right" or "left" end
  hm.low_cut(pawn, mesh, side, p.dir, string.format("her HP bar %.3f -> %.3f (held %.2f s), under %.2f%s", p.from, pct,
    hm.LOW_SETTLE, la.below or 0.25, how and (", " .. how) or ""))
end
-- the arm off (side "left" or "right"), along dir when given, with its blocks: the low HP hit's, and the test keys'
function hm.low_cut(pawn, mesh, side, dir, why)
  local la = (tune.gore or {}).lowArm or {}
  if gore.has_cut(mesh, hm.LOW_BONES[side]) or gore.busy() then return end
  if dir then gore.aim(dir) end
  local ok, r = pcall(gore.slice_bone, pawn, mesh, hm.LOW_BONES[side], nil, "low HP")
  hm.lowCut = ok and r and true or false
  if hm.lowCut then
    hm.lowT, hm.restAt, hm.lowSide, hm.lowLast, hm.lowPend, hm.lowUnder = os.clock(), nil, side, nil, nil, false
  end
  log(string.format("low HP arm: %s: %s", why,
    not ok and ("failed: " .. tostring(r)) or r and ("her " .. side .. " arm cut off") or "not cut"))
  if hm.lowCut and (side == "right" and la.noSword ~= false or side == "left" and la.noHealGun ~= false) then
    hm.low_block(pawn, true, "her " .. side .. " arm is off")
  end
end
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
  -- cut at the hit already (hm.lethal_watch): the blow's further cuts and her sword's now
  if hm.lethal and hm.lethal.cut and os.clock() - hm.lethal.t < 5 then
    hm.lethal.cut = nil
    log(string.format("death: the killing cut was made at the hit, %d more of the blow now", gore.release_held()))
    return
  end
  -- fall damage cuts nothing (no blade in it): a death taken over after a drop (hm.take), or her HP bar at 0 within
  -- LOW_LAND_S of landing from LOW_LAND_CM or more with no hit on her mesh (low_arm's rule: a kill after a jump still
  -- cuts). The 16 m drop's death rolled both legs off on the odds (playtest); hits after it still cut
  local fell = hm.fellAt and os.clock() - hm.fellAt < 1
  hm.fellAt = nil
  local t0 = hm.lethal and os.clock() - hm.lethal.t < 5 and hm.lethal.t or os.clock()
  local land = hm.landAny and math.abs(hm.landAny.t - t0) < hm.LOW_LAND_S and hm.landAny
  local struck = meshHit and meshHit.t >= t0 - hm.LOW_HIT_S
  if fell or (land and not struck) then
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
  if g.sliceOnDeath ~= false then
    local lh = sw.laser_hit(pawn, mesh)
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
  if g.sliceOnDeath ~= false and (h or always) and not judged and sw.smash_kill(pawn, mesh, h or {}, "death") then
    return
  end
  if fly then gore.aim(fly) end
  -- rolled at the lethal hit already, else now. The odds' split share stands whatever the blade (the glass cannon's
  -- too): a blade decides only the rest. It needed a blow from above, which single player never reports, or a blade
  -- down her length, rare: no split in many deaths (reported)
  local roll = hm.lethal and os.clock() - hm.lethal.t < 5 and hm.lethal.roll
  -- (the odds shaped by where the blow landed, gore.near_odds: the killing blow's own if seen, else the lethal hit's)
  local ok, near = pcall(gore.near_odds, mesh, h, hit)
  near = ok and near or (roll and hm.lethal.near) or nil
  if near then log("death: odds by the hit: " .. near.why) end
  if not roll then
    roll = (g.sliceOnDeath == false or math.random() > (g.sliceChance or 1.0)) and "none" or hm.death_roll(h ~= nil and not h.made, near)
  end
  -- a split rolled where the killing blade crossed both her arms: they come off instead, armsOverSplit of the time
  if roll == "split" and h and not h.made and math.random() < (g.armsOverSplit or 0.6) then
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
      if normal and g.deathSplit ~= false then gore.split(pawn, mesh, at, normal, "death"); return end
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
    local kind = pick_kind(false, near, (g.diagonal or {}).enabled ~= false and g.deathSplit ~= false)
    -- from above, the body is cut down through her, not across the waist (a stomp's level cut, playtest). Not on a
    -- made-up blow: it comes from the nearest enemy, mostly "from above", and turned most waist cuts into splits
    if normal and kind == "torso" and not (h and h.made) then
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
function screen.photo_unhold(why)
  if not screen.photoTook then return end
  screen.photoTook = nil
  if not active or not screen.frozen then return end
  screen.frozen = false
  screen.allow_photo(false, why)
  log(string.format("%s: the death P held let go, the death screen and getting up as before %.1f s in", why, polls * POLL_MS / 1000 + ahead))
end
-- Her other meshes' and her capsule's collision as P opens photo mode in a death, put back as it closes (her own
-- mesh is shielded from its switch: gore.photo_shield). With an arm cut off her alive her mesh has the Ragdoll profile
-- (a PhysicsBody) and her hair and capsule are made to ignore PhysicsBody (gore's stage_open); photo mode's switch
-- back as it closed set them blocking again, and her hair, riding her head, shoved her bodies apart in every direction
-- (playtest: her whole body shifted and stretched after photo mode closed, with an arm lost at low HP only)
function screen.photo_coll_save(pawn)
  screen.photoColl = nil
  local body = try(function() return pawn.Mesh end)
  local list = {}
  local comps = screen.cloth_meshes(pawn)
  comps[#comps + 1] = try(function() return pawn.CapsuleComponent end)
  for _, m in ipairs(comps) do
    if valid(m) and not (valid(body) and m:GetAddress() == body:GetAddress()) then
      local e = try(function() return m:GetCollisionEnabled() end)
      local k = e and goreCtx.keep(m)
      if k then
        k.enabled, k.resp = e, {}
        for ch = 0, 31 do k.resp[ch] = try(function() return m:GetCollisionResponseToChannel(ch) end) end
        list[#list + 1] = k
      end
    end
  end
  if #list > 0 and goreCtx.alive_ask(list) then screen.photoColl = list end
end
function screen.photo_coll_restore()
  local list = screen.photoColl
  screen.photoColl = nil
  if not list or not goreCtx.alive_ask(list) then return end
  local fixed = {}
  for _, k in ipairs(list) do
    if k.alive and valid(k.obj) then
      local m, what = k.obj, {}
      local e = try(function() return m:GetCollisionEnabled() end)
      if e and e ~= k.enabled and try(function() m:SetCollisionEnabled(k.enabled); return true end) then
        what[#what + 1] = string.format("enabled %s>%s", tostring(e), tostring(k.enabled))
      end
      for ch = 0, 31 do
        local r = try(function() return m:GetCollisionResponseToChannel(ch) end)
        if r and k.resp[ch] and r ~= k.resp[ch] and try(function() m:SetCollisionResponseToChannel(ch, k.resp[ch]); return true end) then
          what[#what + 1] = string.format("ch%d %s>%s", ch, tostring(r), tostring(k.resp[ch]))
        end
      end
      if #what > 0 then
        fixed[#fixed + 1] = (try(function() return m:GetFName():ToString() end) or "?") .. " " .. table.concat(what, " ")
      end
    end
  end
  log(string.format("photo mode closed: her other meshes' collision as before it: %s",
    #fixed > 0 and ("put back on " .. table.concat(fixed, "; ")) or "unchanged"))
end
function screen.photo_key(label)
  if not active or saved.manual or (camHeld and camHeld.photo) or screen.photoOn or not gore then return end
  if not screen.frozen then screen.frozen, screen.photoTook = true, true; screen.allow_photo(true, label) end
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  -- (her ragdoll stopped, asleep and deaf to photo mode's pawn first: rag.photo_hold)
  local took = rag and rag.photo_hold and not rag.photoHeld
  if valid(pawn) then screen.photo_coll_save(pawn) end
  local held = took and rag.photo_hold(true) or 0
  local r = gore.photo_open(mesh)
  log(label .. " in the held death, opening photo mode: " .. r .. string.format(" (%d of her meshes held still)", held))
  if not r:find("entered 1", 1, true) and took then rag.photo_hold(false) end
  if not r:find("entered 1", 1, true) then screen.photoColl = nil; screen.photo_unhold("photo mode didn't open") end
  if r:find("entered 1", 1, true) then
    screen.photoOn, screen.photoNext, screen.photoSeen = true, 0, nil
    screen.photoHead = valid(mesh) and try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Head"))) end)
  end
end
key_on("photo", function() screen.photo_key(screen.key_name("photo")) end)
-- and the controller's photo mode combo, which the death keeps from photo mode too and UE4SS's key binds can't see:
-- the game's PhotomodeTwoKey1 + PhotomodeTwoKey2 (D-pad left + R1 unless rebound), both down, polled each frame of a
-- death. Read from her controller's input mappings at each death's first look
function screen.pad_photo()
  if not active or saved.manual or (camHeld and camHeld.photo) or not gore then screen.padKeys, screen.padWas, screen.holdWas = nil, nil, nil; return end
  local gs = goreCtx.statics()
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
  -- Shift+F4 on the controller (tune.holdPad, D-pad down + R1 unless set): both down shows the death screen or hides it
  local hp = tune.holdPad
  if type(hp) ~= "table" or not hp[2] then screen.holdWas = nil; return end
  if not screen.holdKeys or screen.holdKeys.label ~= hp[1] .. "+" .. hp[2] then
    screen.holdKeys = { { KeyName = FName(hp[1]) }, { KeyName = FName(hp[2]) }, label = hp[1] .. "+" .. hp[2] }
  end
  local h = screen.holdKeys
  -- held down for tune.holdPadFor s: a quick press of both came by accident in a fight's death (D-pad down + R1),
  -- held the death and left her stuck with only the camera and photo mode (Nexus report)
  local hold = try(function() return pc:IsInputKeyDown(h[1]) and pc:IsInputKeyDown(h[2]) end) == true
  if not hold then screen.holdSince, screen.holdWas = nil, false
  elseif not screen.holdWas then
    screen.holdSince = screen.holdSince or os.clock()
    if os.clock() - screen.holdSince >= (tonumber(tune.holdPadFor) or 1.0) then screen.holdWas = true; screen.hold(h.label .. " (held)") end
  end
end
-- Shift+F4 in a death: the death screen up now if it is still hidden (tune.deathScreen "key" waits for this), else
-- hidden and the death held, no getting up, till pressed again; the game respawning her on its own still ends it
function screen.hold(why)
  local t = polls * POLL_MS / 1000 + ahead
  screen.photoTook = nil
  -- (see-through, Customized Ragdoll support's: the first press shows it)
  if screen.hiding(t) or tune.customizedRagdoll == true and not screen.shown then screen.frozen, screen.shown = false, true
  else screen.frozen = true end
  screen.allow_photo(screen.frozen, why)
  log(string.format("%s: death %s %.1f s in", why, screen.frozen and "held, no death screen or getting up till Shift+F4 (or the pad combo) again" or "screen shown", t))
end
key_on("hold", function()
  if not active or saved.manual then log(screen.key_name("hold") .. ": no death"); return end
  screen.hold(screen.key_name("hold"))
end)
-- Esc on her death: fast forward to the death screen (tune.deathSkip; parked for now, untested)
-- (a key "skip": if active then skip_start(find_eve()) end)
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
screen.uv = uv_on
if goreCtx.keys then goreCtx.keys.uv = uv_on end
if uv_on then log("Ultra Violence is on: the test keys F9, F10 and F11 are Alt+F9, Alt+F10 and Alt+F11 unless set (its menu, outfit blood and blood stages are on F9-F11)") end
key_on("slice", sandbox_slice)
-- F10: a living hit's mark on a part at random, on its side facing the camera (tune.gore.hitMarks)
key_on("mark", function()
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  if not (gore and valid(mesh)) then log("F10: no Eve or no gore.lua"); return end
  local w = gore.MARK_AT[math.random(#gore.MARK_AT)]
  local a = try(function() return vof(mesh:GetSocketLocation(FName(w.bone))) end)
  local b = try(function() return vof(mesh:GetSocketLocation(FName(w.to))) end)
  local cam = try(function()
    local gs = goreCtx.statics()
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
function screen.cloth_meshes(pawn)
  local out, seen = {}, {}
  local cls = StaticFindObject("/Script/Engine.SkeletalMeshComponent")
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
function screen.cloth_restore()
  local list = screen.clothColl
  screen.clothColl = nil
  if not list or #list == 0 then return 0 end
  local n = 0
  if goreCtx.alive_ask(list) then
    for _, k in ipairs(list) do
      if k.alive and valid(k.obj) and try(function() k.obj:SetCollisionEnabled(k.was); return true end) then
        n = n + 1
        -- (its simulated hair kinematic for a moment: back onto the animation's pose, simulated again from there)
        if k.sim then
          for _, b in ipairs(k.sim) do try(function() k.obj:SetAllBodiesBelowSimulatePhysics(FName(b), false, true) end) end
          screen.clothSim = { k = k, at = os.clock() }
        end
      end
    end
  end
  return n
end
-- the bodies on her mesh that simulate while she lives, not under a simulating Bip001 bone (a piece cut off her):
-- her hair's (CH_P_EVE_30's ponytail, Ab-TL-HairB01-09)
function screen.sim_bodies(mesh)
  local out = {}
  if not (rag and rag.bodies) then return out end
  local function sim(b) return try(function() return mesh:IsSimulatingPhysics(FName(b)) end) == true end
  for _, b in ipairs(rag.bodies(mesh)) do
    if b:sub(1, 6) ~= "Bip001" and sim(b) then
      local p, free = b, true
      for _ = 1, 32 do
        p = try(function() return mesh:GetParentBone(FName(p)):ToString() end)
        if not p or p == "None" then break end
        if p:sub(1, 6) == "Bip001" then free = not sim(p); break end
      end
      if free then out[#out + 1] = b end
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
function screen.auto_f8(pawn)
  if not screen.autoF8 or os.clock() < screen.autoF8 then return end
  if active or screen.photoOn or screen.cloth or hm.regrow or hm.ghost then return end
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
  local body = try(function() return pawn.Mesh end)
  return valid(body) and gore and #(gore.cut_parts(body) or {}) > 0 and body or nil
end
function screen.cloth_tick(pawn)
  screen.cloth_sim_tick()
  screen.auto_f8(pawn)
  local c = screen.cloth
  local piece = screen.piece_off(pawn)
  local bodyOff = piece and screen.clothColl and (function()
    for _, k in ipairs(screen.clothColl) do if valid(k.obj) and k.obj:GetAddress() == piece:GetAddress() then return true end end
  end)()
  if screen.clothColl and (active or screen.photoOn or not c or bodyOff) then
    local n = screen.cloth_restore()
    log(string.format("cloth: her meshes' collision given back early (%d)%s", n, piece and ": a part is off her" or ""))
  end
  if not c or active or screen.photoOn then return end
  local wait = screen.CLOTH_AFTER[c.i]
  if not wait then screen.cloth = nil; return end
  if os.clock() - c.at < wait then return end
  c.i = c.i + 1
  local meshes = screen.cloth_meshes(pawn)
  if c.i == 3 then
    local n = screen.cloth_restore()
    log(string.format("cloth: her meshes' collision given back (%d)", n))
    screen.cloth = nil
    -- (not after the one an auto F8 itself set going: its cleanup may re-make her bodies)
    if os.clock() - (screen.autoF8Ran or -100) > screen.AUTO_F8_S + 10 then screen.autoF8 = os.clock() + screen.AUTO_F8_S end
    return
  end
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
local function animated_death(pawn, mesh, push)
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
  return anim_fall(pawn, mesh, push)
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
function screen.photo_watch(pawn, mesh)
  local now = os.clock()
  -- (a death lying still stays so while it is on: rag.hold_still)
  if rag and rag.hold_still then rag.hold_still() end
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
  screen.stillTill = now + 1
  if rag and rag.photo_hold then rag.photo_hold(false) end
  screen.photo_coll_restore()
  sw.drop()
  log("photo mode closed: the enemy's weapon trail starts over")
  screen.photo_unhold("photo mode closed")
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
  gs = gs or goreCtx.statics()
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
-- is stopped, and started again.
-- Photo mode (photo): her mesh stopped ticking took its poses and expressions with it (reported), so there it ticks on
-- and the pieces cut off her lie on a copy of her mesh instead (gore.hide_pieces), till photo mode closes. Alive only:
-- in a death her mesh stops as before (on a copy her cut-off head went back onto her neck, 0.4.3 playtest)
function screen.freeze(pawn, mesh, why, photo)
  if not valid(mesh) or try(function() return mesh:IsSimulatingPhysics(PELVIS) end) then return end
  if photo and (goreCtx.dead_since() or screen.hpZero) then photo = nil end
  if photo and gore and gore.hide_pieces then
    if gore.pieceHid then return end
    if screen.frozenMesh then screen.unfreeze(mesh) end
    local np = gore.hide_pieces(pawn, mesh, true)
    if gore.pieceHid and gore.pieceHid.face then pcall(screen.head_hook, mesh) end
    log(string.format("photo mode (%s) with %d piece(s) off her alive: her mesh ticks on (poses, expressions), the pieces on their copy till it closes",
      why, np))
    return
  end
  if screen.frozenMesh then return end
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
  -- (a piece settled on its copy before photo mode opened stays there: hm.piece_watch)
  if gore and gore.pieceHid and not gore.pieceHid.baked then
    pcall(screen.head_end)
    local np, nr = gore.hide_pieces(nil, nil, false)
    log(string.format("photo mode over: %d piece(s) back on her, with %d part(s) riding them; their copy gone", np, nr))
  end
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
-- the freeze holds this many seconds after photo mode's pawn or a widget of its is made: her tick ran between its
-- pawn and its widgets, before its view or widgets showed, found no photo mode, and let her mesh and hair tick again
-- for a frame: the hair on a cut-off head flew back to where it sits on her (playtest)
screen.PHOTO_HOLD = 1.5
-- photo mode's widgets, as they are made (the widget watch above): her own tick, where the rest of this runs, stops
-- while photo mode is on (playtest: nothing of the mod's logged from photo mode opening till it closed, and the head
-- and hair went to her neck), so the freeze comes here, on the game thread, as photo mode opens. Each one is kept:
-- photo mode is on while one of them shows
-- (pawn_made: photo mode's pawn, not a widget to watch)
function screen.photo_widget(o, cls, pawn_made)
  screen.photoW = screen.photoW or {}
  -- (kept by path: photo mode frees its widgets as it closes, and asking a freed one IsValid crashed UE4SS, playtest)
  -- Only its panels: its ~90 slots and tab buttons are never in the viewport themselves, and each kept one is a name
  -- table lookup a frame
  if not pawn_made and not cls:find("_Slot_C$") and not cls:find("_Btn_C$") then
    screen.photoW[#screen.photoW + 1] = goreCtx.keep(o)
  end
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
  ;(pawn_made and log or lg.v)(string.format("photo mode %s made: %s%s", pawn_made and "pawn" or "widget", cls, cut and "" or " (no piece off her)"))
  if cut then
    screen.freeze(pawn, mesh, "photo mode's " .. (pawn_made and "pawn " or "widget ") .. cls, true)
    screen.photoHold = os.clock() + screen.PHOTO_HOLD
  end
end
local function photo_widget_up()
  for i = #(screen.photoW or {}), 1, -1 do
    local k = screen.photoW[i]
    local w = goreCtx.held(k) and k.obj
    if not w then table.remove(screen.photoW, i)
    elseif try(function() return w:IsInViewport() end) == true then return true end
  end
  return false
end
-- photo mode with her head cut off, on the piece's copy (gore.hide_pieces): her face took its expression from her
-- body's animation curves, and posed by the copy (no animation) it went blank and ignored photo mode's expressions and
-- look at the camera (playtest). Her tick doesn't run in photo mode, but her animation does, so its Blueprint update is
-- hooked (once, on the game thread) and each frame her body's curves for the face's morphs are set on the face. Her
-- hair on the head is reset to it for a few frames after each pose change: the pose brings its own hair snapshot,
-- which threw it back where her head would be (playtest)
screen.head = { hooked = nil, tried = false, cur = nil }
function screen.head_hook(mesh)
  local hd = screen.head
  if hd.hooked or hd.tried then return end
  hd.tried = true
  local paths = {}
  for _, inst in ipairs({ try(function() return mesh:GetAnimInstance() end), try(function() return mesh:GetPostProcessInstance() end) }) do
    local full = valid(inst) and try(function() return inst:GetClass():GetFullName() end)
    local path = full and full:match("^%S+%s+(.+)$")
    if path then paths[#paths + 1] = path .. ":BlueprintUpdateAnimation" end
  end
  for _, p in ipairs(paths) do
    if valid(try(function() return StaticFindObject(p) end)) then
      local ok = pcall(RegisterHook, p, function()
        local ok2, err = pcall(screen.head_tick)
        if not ok2 and not hd.err then hd.err = true; log("photo mode head: " .. tostring(err)) end
      end)
      if ok then hd.hooked = p; break end
    end
  end
  log("photo mode: a cut-off head follows photo mode's face settings " .. (hd.hooked and "through " .. hd.hooked
    or "never: no Blueprint update of hers to hook (" .. table.concat(paths, ", ") .. ")"))
end
function screen.head_tick()
  local h = gore and gore.pieceHid
  local hd = screen.head
  local pawn = cachedPawn
  if not (h and valid(h.face) and valid(pawn)) then
    if hd.cur then screen.head_end() end
    return
  end
  local cur = hd.cur
  if not cur then
    local anim = try(function() return pawn.Mesh:GetAnimInstance() end)
    if not valid(anim) then return end
    local set = dface.names(h.face)
    -- (not reset from the start: her ponytail is cloth, reset as it went onto the copy it moved off the head as photo
    -- mode opened and came back as it closed, its bones never moving, playtest; reset on a pose change only)
    cur = { face = h.face, anim = anim, names = {}, fn = {}, vals = {}, reset = 0, hair = {}, n = 0 }
    for nm, _ in pairs(set) do cur.names[#cur.names + 1] = nm; cur.fn[#cur.fn + 1] = FName(nm) end
    local sk = StaticFindObject("/Script/Engine.SkeletalMeshComponent")
    for _, r in ipairs(h.riders or {}) do
      if valid(r.c) and try(function() return r.c:IsA(sk) end) then cur.hair[#cur.hair + 1] = r.c end
    end
    for _, k in ipairs(h.posed or {}) do cur.hair[#cur.hair + 1] = k end
    hd.cur = cur
    log(string.format("photo mode: the cut-off head's face takes her body's curves (%d morphs), %d part(s) of her hair reset on a pose change",
      #cur.names, #cur.hair))
  end
  local set = 0
  for i, f in ipairs(cur.fn) do
    local v = try(function() return cur.anim:GetCurveValue(f) end) or 0
    if math.abs(v - (cur.vals[i] or 0)) > 0.002 then
      cur.vals[i] = v
      try(function() cur.face:SetMorphTarget(f, v, false) end)
      set = set + 1
    end
  end
  cur.n = cur.n + 1
  -- where her hair parts are as photo mode opens, against the copy's head and her own (on her neck): which part goes
  -- back to her neck (reported on CH_P_EVE_30: her hair snapped back as photo mode opened, with or without the fork)
  -- where her hair parts are while photo mode is open, against the cut-off head and her neck: which part goes back to
  -- her neck (reported on CH_P_EVE_30: her hair snapped back as photo mode opened, with or without the fork). Every
  -- 5th frame, logged on the first and whenever a part moved 5 cm or more since the last line (the first second was
  -- quiet: the snap came as photo mode fully opened, 84=14, about 3 s in, playtest)
  if cur.n % 5 == 1 then
    -- (never in the way of the face and the reset below)
    local okd, ed = pcall(function()
      local ch = h.copies and h.copies[1]
      local mesh = try(function() return pawn.Mesh end)
      local hc = valid(ch) and try(function() return vof(ch:GetSocketLocation(FName("Bip001-Head"))) end)
      local hn = valid(mesh) and try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Neck"))) end)
      if not cur.list then
        -- (the hair bones of each, Hair/Pony in their names, found once: a component's Bounds isn't a property UE4SS
        -- reads, playtest)
        cur.list = {}
        local all = { { "copy", ch }, { "her", mesh } }
        for _, k in ipairs(cur.hair) do all[#all + 1] = { nil, k } end
        for _, e in ipairs(all) do
          local k = e[2]
          if valid(k) and valid(try(function() return k.SkeletalMesh end)) then
            local bones = {}
            local n = try(function() return k:GetNumBones() end) or 0
            for i = 0, n - 1 do
              local bn = try(function() return k:GetBoneName(i):ToString() end)
              if bn and (bn:find("[Hh]air") or bn:find("[Pp]ony")) then bones[#bones + 1] = FName(bn) end
            end
            if #bones > 0 then
              cur.list[#cur.list + 1] = { nm = e[1] or try(function() return k.SkeletalMesh:GetFName():ToString() end) or "?", k = k, bones = bones }
            end
          end
        end
      end
      local parts, moved = {}, cur.n == 1
      for _, e in ipairs(cur.list) do
        local sx, sy, sz, c = 0, 0, 0, 0
        if valid(e.k) then
          for _, f in ipairs(e.bones) do
            local p = try(function() return vof(e.k:GetSocketLocation(f)) end)
            if p and type(p.X) == "number" then sx, sy, sz, c = sx + p.X, sy + p.Y, sz + p.Z, c + 1 end
          end
        end
        local o = c > 0 and { X = sx / c, Y = sy / c, Z = sz / c } or nil
        if o and e.last and dist(o, e.last) >= 5 then moved = true end
        if o and not e.last then e.last = o end
        if moved and o then e.last = o end
        parts[#parts + 1] = string.format("%s %s/%s", e.nm, (o and hc) and string.format("%.0f", dist(o, hc)) or "?",
          (o and hn) and string.format("%.0f", dist(o, hn)) or "?")
      end
      if moved then
        local st = (screen.liveSig or ""):match("^84=%S+") or ""
        log(string.format("photo mode frame %d%s: hair cm from the cut-off head / her neck: %s; the head %s from her neck",
          cur.n, st ~= "" and (" (" .. st .. ")") or "", table.concat(parts, ", "),
          (hc and hn) and string.format("%.0f cm", dist(hc, hn)) or "?"))
      end
    end)
    if not okd then log("photo mode frame " .. cur.n .. ": " .. tostring(ed)) end
  end
  if set > 0 and not cur.said then cur.said = true; log(string.format("photo mode: the cut-off head's face moved (%d morphs)", set)) end
  local sig = tostring(try(function() return pawn.PoseName_PhotoMode:ToString() end)) .. "/" ..
    tostring(try(function() return pawn.bChangedPose_PhotoMode end))
  if cur.sig and sig ~= cur.sig then
    cur.reset = 10
    log("photo mode: her pose changed (" .. sig .. "): the hair on her cut-off head reset to it")
  end
  cur.sig = sig
  if cur.reset > 0 then
    cur.reset = cur.reset - 1
    -- (cloth, and the rigid body chains of her hair's own animation: ResetPhysics)
    for _, k in ipairs(cur.hair) do
      if valid(k) then
        try(function() k:ForceClothNextUpdateTeleportAndReset() end)
        try(function() k:ResetAnimInstanceDynamics(2) end)
      end
    end
  end
end
-- the face's morphs set from her curves back off as photo mode closes (her body's curves drive it again)
function screen.head_end()
  local cur = screen.head.cur
  screen.head.cur = nil
  if not cur or not valid(cur.face) then return end
  for i, f in ipairs(cur.fn) do
    if (cur.vals[i] or 0) ~= 0 then try(function() cur.face:SetMorphTarget(f, 0, true) end) end
  end
end
function screen.photo_freeze(pawn, mesh)
  local gs = goreCtx.statics()
  local paused = valid(gs) and try(function() return gs:IsGamePaused(pawn) end)
  screen.view(pawn, gs)
  local stopped = screen.time_stopped(pawn, gs)
  local widget = photo_widget_up()
  local photo = widget or screen.vtPhoto or screen.photoOn or screen.photoLive or os.clock() < (screen.photoHold or 0)
  paused = paused or stopped or photo
  if paused then
    screen.freeze(pawn, mesh, screen.vtPhoto and "photo mode's view" or widget and "photo mode's widget"
      or (screen.photoOn or screen.photoLive) and "photo mode" or stopped and "the game's clock stopped" or "paused", photo)
  else
    screen.unfreeze(mesh)
    -- (where her head is the last frame before a pause, for the log as photo mode opens: the 0.5 s poll's was off by
    -- however far a thrown piece had gone since)
    screen.photoHead = try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Head"))) end) or screen.photoHead
  end
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
    local st = gore.photo_state(pawn) or ""
    local m84 = tonumber(st:match(" 84=(%-?%d+)"))
    -- (hidden with photo mode's own option: left so)
    screen.ownHide = st:match(" own=1") ~= nil
    -- (her caps and stubs, actors of their own, hidden and shown with her)
    if gore.photo_hide and screen.ownHide ~= (gore.photoHid ~= nil) then
      local n = gore.photo_hide(pawn, screen.ownHide)
      log(string.format("photo mode %s her: %d cap(s) and stub(s) with her", screen.ownHide and "hides" or "shows", n))
    end
    local gs = goreCtx.statics()
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
    screen.ownHide = nil
    if gore and gore.photoHid then gore.photo_hide(pawn, false) end
    return
  end
  if screen.ownHide then return end
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
    -- (what rode a piece cut off her, hidden while photo mode is on: gore.hide_pieces)
    if a and gore and gore.pieceHid and gore.pieceHid.set[a] then a = nil end
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
    local gs = goreCtx.statics()
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
-- over however photo mode opened.
-- A ragdoll with nothing cut off (F7's, or a death before its cut) is shielded too: photo mode opened on it by the
-- game's key turned its physics off, and back on as it closed from wherever the bones had gone; on stairs she shifted
-- and stretched (playtest)
function screen.photo_guard(pawn, mesh)
  if screen.stillTill and rag and rag.hold_still then
    if os.clock() < screen.stillTill then rag.hold_still() else screen.stillTill = nil end
  end
  screen.watchFreeze = screen.frozenMesh ~= nil or gore.pieceHid ~= nil or (gore.cuts_on(mesh)) > 0
  if not screen.watchFreeze then screen.clock, screen.stopped = nil, nil end
  if screen.photoOn then return screen.photo_watch(pawn, mesh) end
  local a = mesh:GetAddress()
  local cut = (gore.cuts_on(mesh)) > 0
  local why = cut and "a piece is off her"
    or try(function() return mesh:IsSimulatingPhysics(PELVIS) end) == true and "her ragdoll on"
  if not why then
    if screen.shielded == a then
      screen.shielded = nil
      log("no piece off her, no ragdoll: her mesh unshielded: " .. gore.photo_unshield())
    end
    return false
  end
  if screen.shielded ~= a then
    screen.shielded = a
    log(why .. ": her mesh shielded from photo mode's collision switch: " .. gore.photo_shield(mesh))
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
  if gore and gore.decals_back then gore.decals_back("she plays") end
  hm.carry_tick(pawn, mesh)
  hm.carry_note(pawn, mesh)
  if goreCtx.customrag then try(function() goreCtx.customrag.keep(pawn, mesh) end) end
  hm.swap_watch(pawn, mesh, false)
  track_swing(pawn, mesh)
  hm.guard_watch(pawn, mesh)
  tp.mark("swing")
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
  if active then hold_capsule(pawn, sim); camera_watch(pawn, mesh) end
  -- the outfit she has on, whenever she is animated (the respawn window included: an outfit put on right after a
  -- reset went unchecked, fifteenth playtest)
  if physfix and not sim and not active then physfix.check(pawn, mesh, false) end
  if rag and not sim then rag.track(pawn) end
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
    if hm.lethal then log(string.format("death: %.2f s after her HP bar hit 0", os.clock() - hm.lethal.t))
    elseif hm.armed then
      -- (the bar not yet at 0 as the death comes: the game drains it after; nothing could be cut at the hit)
      log(string.format("death: her HP bar read %s at it, %.2f s since it last changed", tostring(hm.barLast),
        os.clock() - (hm.barT or 0)))
    end
    -- disarmed till the bar is seen above 0 again: it reads 0 through the respawn, and the watch fired there
    hm.armed = false
    -- how far she turned from her last tick alive (the game's death show turns her, playtest: a 180 before the cut)
    local yaw = try(function() return pawn:K2_GetActorRotation().Yaw end)
    if yaw and hm.yaw then
      log(string.format("death: she faces %.0f deg, %.0f deg from her last tick alive (%.2f s before)", yaw,
        (yaw - hm.yaw + 540) % 360 - 180, os.clock() - hm.yawT))
    end
    local h = death_hit(pawn, mesh)
    tp.mark("death hit")
    if animated_death(pawn, mesh, h and h.push) then goreCtx.pose.hold(mesh)
    elseif rag then rag.start(pawn, mesh, "death", h and h.push) end
    hm.at.on = nil
    tp.mark("fall")
    -- the cut is chosen the next frame: with the death's own setup it was one 30-80 ms frame (playtest)
    pending[#pending + 1] = function()
      if not (active and valid(mesh)) then return end
      local t0 = os.clock()
      local ok, err = true, nil
      if not test then ok, err = pcall(gore_death, pawn, mesh, h) end
      if not ok then log("death cut failed: " .. tostring(err)) end
      if goreCtx.pose.held then goreCtx.pose.held.cut = true end
      if not (gore and gore.splitting()) then goreCtx.pose.free("no split: the fall plays on") end
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

  if active then skip_tick() end
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
-- pawn: the new Eve
local function forget_world(pawn)
  -- (her alive cuts go on into the new level: a death's reload takes none)
  hm.carry_take(active)
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
  -- her watches and the enemies' part, queued by the old one's last poll for a frame after it with her pawn and
  -- mesh: run on the new one's first tick, asking the freed old pawn crashed the game (quit to the main menu with her
  -- alive, playtest; a death's reload had none queued). And F7's push, and the dev watch, held the old pawn too
  screen.aliveDue, screen.enemiesDue, screen.watch, f7_push = nil, nil, nil, nil
  -- a held death (Shift+F4) or a hidden HUD went with the old level: none carried into the new one
  screen.frozen, screen.hudHid, screen.hudMaster, screen.hpBack, screen.photoTook = false, nil, nil, 0, nil
  -- the photo watch's async loop read the old pawn's parts (freed with the level)
  screen.unhide, screen.unhideSig = nil, nil
  -- the new level may still be streaming in: nothing from the pak for a few seconds more
  goreCtx.quietUntil = math.max(goreCtx.quietUntil, os.clock() + 5)
  skip, ahead = nil, 0
  -- the old face may be gone: dropped without touching it
  dface.on, dface.known, faceCheck = nil, {}, nil
  -- (a regrow's copy went with the old level)
  hm.ghost, hm.regrow = nil, nil
  if gore then gore.forget(pawn) end
  if goreCtx.enemies then goreCtx.enemies.forget() end
  if goreCtx.bosses then goreCtx.bosses.forget() end
  if goreCtx.glass then goreCtx.glass.forget() end
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
  if not adopt(ctx) then return end
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
    if goreCtx.customrag then pcall(goreCtx.customrag.tick, screen.photoOn or screen.vtPhoto or screen.photoLive) end
    local ok, err = pcall(screen.pad_photo)
    if not ok then log("controller photo key: " .. tostring(err)) end
    if goreCtx.convulse then
      local ok2, err2 = pcall(goreCtx.convulse.tick, screen.photoOn or screen.vtPhoto or screen.photoLive or screen.stopped)
      if not ok2 then log("convulse: " .. tostring(err2)) end
    end
    if goreCtx.struggle then
      local ok3, err3 = pcall(goreCtx.struggle.tick, screen.photoOn or screen.vtPhoto or screen.photoLive or screen.stopped)
      if not ok3 then log("struggle: " .. tostring(err3)) end
    end
  elseif screen.padKeys then screen.padKeys, screen.padWas = nil, nil end
  -- and a cut's stages, a frame each (on the poll below the piece came off 350 ms after the blow)
  if gore and gore.pump and not screen.photoOn then
    local ok, err = pcall(gore.pump)
    if not ok then log("cut stage failed: " .. tostring(err)) end
  end
  -- her watches while she plays, a third of a poll after it, and the enemies' part, two thirds: the poll was 3-6 ms
  -- on one frame every ~5 at 144 fps (a Nexus report of microstutter), the enemies ~1 ms of it, her watches ~2
  local ad = screen.aliveDue
  if ad and now >= nextTick - POLL_MS * 2 / 3000 then
    screen.aliveDue = nil
    if not screen.photoOn and not active and valid(ad.pawn) and valid(ad.mesh)
      and try(function() return ad.mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end) ~= true then
      for i = #tp, 1, -1 do tp[i] = nil end
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
      tp.t = now
      local ok, err = pcall(goreCtx.enemies.tick, ed.pawn, ed.mesh, tp.mark)
      if not ok then log("enemies: " .. tostring(err)) end
      tp.mark("enemies")
      local ms = (os.clock() - now) * 1000
      screen.cost.pollMs = screen.cost.pollMs + ms
      if ms >= ((tune.gore or {}).slowMs or 15) then screen.perf_note("slow", ms, string.format("slow tick: %.0f ms: enemies (on its own frame)", ms)) end
    end
    if now < nextTick then return end
    now = os.clock()
  end
  if now < nextTick then return end
  nextTick = now + POLL_MS / 1000
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
function screen.cost_tick(dt)
  local c = screen.cost
  local ms = dt * 1000
  c.n, c.ms = c.n + 1, c.ms + ms
  if ms > c.most then c.most = ms end
  if ms >= 2 then c.o2 = c.o2 + 1; if ms >= 4 then c.o4 = c.o4 + 1; if ms >= 8 then c.o8 = c.o8 + 1 end end end
  local now = os.clock()
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

log("loaded (stabiliser + logger)")
