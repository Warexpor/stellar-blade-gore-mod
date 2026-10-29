-- bosses.lua: Sandbox Bosses (tune.bosses, F3 → Sandbox): the game's humanoid bosses (Tachy, Raven, Scarlet) spawned
-- in front of her anywhere and killed like any enemy: no death cutscene, no phase change to wait out, their body cut
-- (enemies.lua, as the skulls), then a struggle on the floor (a copy of struggle.lua of its own) and a dead face held
-- on its face mesh (main.lua's death face, goreCtx.new_face).
--
-- A boss can't die as the game has it: its CharacterTable row gives it Passive_Immortal (ActorState_Immortal, for
-- good), its death is a show of its own (M_Tachy_Dead: the cutscene) or none with a ragdoll (Raven, Scarlet:
-- Dead_Monster_StandCommonNoRagdoll), and Raven's corpse despawns a second after. So while one spawned here lives, its
-- row is changed in game (sbslice d / N, as tables.lua's rows; nothing in the pak, no other mod's table overridden):
--   DeadAlias -> deadAs (M_SkullSword's death rows: the common deaths with a ragdoll key), DefaultEffectArray's
--   Passive_Immortal -> Passive_Immortal_Dispel (an effect dispelling it: one no boss row lists, so it is put back
--   exactly), MaxHP and MaxShield times hpScale, DespawnTimeAfterDeath at least despawn s.
-- and put back once none of that kind spawned here is left (a story fight of that boss meanwhile would get it too: it
-- is only ever on while one of yours is up).
-- Their phases' floors (MinimumHP effects some skills put on) can still hold one at a sliver of HP: when the boss bar
-- (WB_MainHUD_EnemyInfo's ProgressBar_HP) sits at floor or below and it is hit again, or reads 0 with it still up for
-- zeroWait s, it is taken down by the mod (enemies.lua kill_one: its AI stopped, ragdolled), as the game would.
-- A phase change that waits on its arena (Scarlet's goes on with the level's MV_Nikke_Scarlet_Phase2 cutscene, never
-- played outside it: she stood there, doing nothing, reported) holds the bar above the floor: the bar unchanged and the
-- boss standing in place (STUCK_CM) through stuckHits hits over stuckS s takes it down too.
local M = {}
local ctx, try, valid
local function cfg() return ctx.tune.bosses or {} end
local function log(s) ctx.log("bosses: " .. s) end

M.CHAR = "/Game/Local/Data/CharacterTable.CharacterTable"
M.IMMORTAL, M.DISPEL = "Passive_Immortal", "Passive_Immortal_Dispel"
M.HUD = "WB_MainHUD_EnemyInfo_C"

local rows = {}   -- row name -> { dt = table address, was = { field -> old u32 }, n = live count, t = last asked }
local live = {}   -- actor address -> { e, k, mine, hitT, floorT, zeroT, face, struggle }
local dead = {}   -- actor address -> { e, face, struggle }
local struggleSrc -- struggle.lua's chunk, loaded once (each boss's death runs a fresh copy of it)

function M.init(c)
  ctx, try, valid = c, c.try, c.valid
end

local function addr(o) return try(function() return o:GetAddress() end) end
local function name_idx(s) return try(function() return FName(s):GetComparisonIndex() end) end
local function f2u(v) return string.unpack("<I4", string.pack("<f", v)) end
local function u2f(u) return string.unpack("<f", string.pack("<I4", u & 0xffffffff)) end

-- the row struct's field offsets, by name (the table's reflection)
local function offsets(rs)
  local out = {}
  try(function() rs:ForEachProperty(function(p) out[p:GetFName():ToString()] = p:GetOffset_Internal() end) end)
  return out
end
local function table_of()
  local dt = try(function() return StaticFindObject(M.CHAR) end)
  local rs = valid(dt) and try(function() return dt.RowStruct end)
  if not valid(rs) then return nil end
  return dt, rs
end
-- the 4 bytes at a row's field: read, and written with u when given. The old value, or nil and the DLL's answer
local function field(dt, rs, row, off, u)
  local idx = name_idx(row)
  if not (idx and off) then return nil, "no name or field" end
  local s = string.format("d%x,%x,%x,0,%x", addr(dt), addr(rs), idx, off)
  if u then s = s .. string.format(",%x", u & 0xffffffff) end
  local r = ctx.gore.command(s)
  local was = r:match("^ok row %x+ (%x+) %x+$")
  if not was then return nil, r end
  return tonumber(was:sub(-8), 16)
end
local function swap_names(dt, rs, row, off, from, to)
  local ri, a, b = name_idx(row), name_idx(from), name_idx(to)
  if not (ri and a and b and off) then return nil, "no name or field" end
  local r = ctx.gore.command(string.format("N%x,%x,%x,0,%x,%x,0,%x,0", addr(dt), addr(rs), ri, off, a, b))
  local n = r:match("^ok names (%d+)")
  if not n then return nil, r end
  return tonumber(n)
end

-- the row of kind k made mortal (once; a second spawn of it counts on). nil when done, else why not
function M.prepare(k)
  if cfg().enabled ~= true then return "Sandbox Bosses is off (F3 → Sandbox)" end
  if not ctx.gore or ctx.gore.native_state() ~= "ready" then return "sbslice.dll isn't up yet" end
  -- (a new one may bring its bar: looked for again soon)
  if M.bar_soon then M.bar_soon() end
  local r = rows[k.row]
  if r then r.t = os.clock(); return nil end
  local dt, rs = table_of()
  if not dt then return "no CharacterTable loaded" end
  local off = offsets(rs)
  local was, out = {}, {}
  -- its deaths: another row's (a ragdoll in each)
  local deadAs = k.deadAs or cfg().deadAs or "M_SkullSword"
  local di = name_idx(deadAs)
  local old, err = field(dt, rs, k.row, off.DeadAlias, di)
  if not old then return "its DeadAlias not set: " .. tostring(err) end
  was.DeadAlias = old
  out[#out + 1] = "dies as " .. deadAs
  local n = swap_names(dt, rs, k.row, off.DefaultEffectArray, M.IMMORTAL, M.DISPEL)
  if n and n > 0 then was.immortal = true; out[#out + 1] = "not immortal" else out[#out + 1] = "had no " .. M.IMMORTAL end
  local sc = math.max(math.min(tonumber(cfg().hpScale) or 0.25, 1), 0.01)
  for _, f in ipairs({ "MaxHP", "MaxShield" }) do
    local v = field(dt, rs, k.row, off[f])
    if v and v > 0 and sc ~= 1 then
      local to = math.max(1, math.floor(v * sc + 0.5))
      if field(dt, rs, k.row, off[f], to) then was[f] = v; out[#out + 1] = string.format("%s %d -> %d", f, v, to) end
    end
  end
  local ds = field(dt, rs, k.row, off.DespawnTimeAfterDeath)
  local want = tonumber(cfg().despawn) or 120
  if ds and u2f(ds) < want and field(dt, rs, k.row, off.DespawnTimeAfterDeath, f2u(want)) then
    was.DespawnTimeAfterDeath = ds
    out[#out + 1] = string.format("despawns after %.0f s (was %.1f)", want, u2f(ds))
  end
  local mhp, msh = field(dt, rs, k.row, off.MaxHP), field(dt, rs, k.row, off.MaxShield)
  rows[k.row] = { dt = addr(dt), was = was, off = off, t = os.clock(), mhp = mhp, msh = msh }
  log(string.format("%s's row made mortal while one of yours is up: %s", k.row, table.concat(out, ", ")))
  return nil
end

-- a row as the game had it (only while its table is the one changed: a table made again has its own rows)
local function put_back(row, why)
  local r = rows[row]
  rows[row] = nil
  if not r then return end
  local dt, rs = table_of()
  if not dt or addr(dt) ~= r.dt then log(string.format("%s: its table is gone (%s), nothing to put back", row, why)); return end
  local off, n = r.off, 0
  for f, v in pairs(r.was) do
    if f == "immortal" then
      if swap_names(dt, rs, row, off.DefaultEffectArray, M.DISPEL, M.IMMORTAL) then n = n + 1 end
    elseif field(dt, rs, row, off[f], v) then
      n = n + 1
    end
  end
  log(string.format("%s's row put back as the game has it (%s): %d fields", row, why, n))
end

-- enemies.lua: a boss kind followed (mine: spawned here)
-- one spawned here standing still (Passive Bosses): its hand by her is no grab (enemies.grab_tick)
function M.is_passive(a) local x = live[a]; return x ~= nil and x.passive == true end
-- its body's physics asset as the game made it (kind.physics): an outfit mod's mesh for the boss can point at one the
-- game doesn't have (Naked Tachy, Nexus 3183: none the game can load, so its ragdoll had the wrong bodies or none and
-- it went wild as it died; Nexus report). Put back when its own isn't one from the boss's folder; told either way.
-- Its bodies are made again simulating (the mesh is set to, with no bodies till then): the pelvis simulating is an
-- enemy's death (enemies.lua), so Tachy was cut and thrown across the map as she came in (playtest). They are made
-- kinematic again at once, and for PHYS_HOLD s the enemies' watch does it again rather than take it for her death.
-- It goes on her mesh asset too (a body made again from the mesh's then has hers). Her ragdoll still stopped
-- within a second of her death, standing (playtests); starting it again with hers stretched her legs out across
-- the map: her death's physics is logged (M.physics_line) and left to the game
M.PHYS_HOLD = 1.0
local function own_physics(e)
  local want = e.kind.physics
  local mesh = e.mesh or try(function() return e.obj.Mesh end)
  if not (want and valid(mesh)) then return end
  local pa = try(function() return mesh:GetPhysicsAsset() end)
  local path = valid(pa) and try(function() return pa:GetFullName() end) or "none"
  local sm = try(function() return mesh.SkeletalMesh:GetFName():ToString() end) or "?"
  local dir = want:match("^(.*)/[^/]+$")
  if valid(pa) and path:find(dir, 1, true) then
    log(string.format("%s's body %s: its own physics asset (%s)", e.kind.alias, sm, path:match("([^/]+)$") or path))
    return
  end
  local nm = want:match("([^/]+)$")
  local full = want .. "." .. nm
  local p = try(function() return StaticFindObject(full) end)
  if not valid(p) and LoadAsset then
    try(function() LoadAsset(full) end)
    p = try(function() return StaticFindObject(full) end)
  end
  if not valid(p) then
    log(string.format("%s's body %s has physics asset %s, not its own, and %s didn't load: left as it is", e.kind.alias, sm, path, nm))
    return
  end
  local sk = try(function() return mesh.SkeletalMesh end)
  if valid(sk) then try(function() sk.PhysicsAsset = p end) end
  local onAsset = valid(sk) and try(function() return sk.PhysicsAsset:GetFName():ToString() end) == nm
  try(function() mesh:SetPhysicsAsset(p, true) end)
  e.physHold = os.clock() + M.PHYS_HOLD
  local sim = M.kinematic(mesh)
  local now = try(function() return mesh:GetPhysicsAsset():GetFName():ToString() end)
    or try(function() return mesh.PhysicsAssetOverride:GetFName():ToString() end) or "?"
  log(string.format("%s's body %s had physics asset %s (an outfit mod's mesh): the game's own %s put back (%s, %s)%s",
    e.kind.alias, sm, path, nm, now == nm and "ok" or "FAILED, it has " .. now,
    onAsset and "on its mesh asset too" or "its mesh asset NOT changed", sim and ", its bodies made kinematic (they came simulating)" or ""))
  log(string.format("%s: %s", e.kind.alias, M.physics_line(e)))
  return true
end
-- its bodies kinematic, as a live one's are; true when they were simulating
function M.kinematic(mesh)
  local was = try(function() return mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end) == true
  try(function() mesh:SetSimulatePhysics(false) end)
  try(function() mesh:SetAllBodiesSimulatePhysics(false) end)
  return was
end
-- what its body's physics is made of, for the log: its component's override, its mesh asset's own, what the
-- component answers, and whether its pelvis simulates (Naked Tachy playtests: at her death her ragdoll stopped and
-- the asset read none, with hers put on the mesh asset at spawn)
function M.physics_line(e)
  local mesh = e.mesh
  local function nm(o) return valid(o) and (try(function() return o:GetFName():ToString() end) or "?") or "none" end
  local function ad(o) return valid(o) and string.format("%x", try(function() return o:GetAddress() end) or 0) or "-" end
  local sk = try(function() return mesh.SkeletalMesh end)
  return string.format("mesh %s %s, override %s, asset's own %s, answers %s, pelvis %s", nm(sk), ad(sk),
    nm(try(function() return mesh.PhysicsAssetOverride end)), nm(valid(sk) and try(function() return sk.PhysicsAsset end)),
    nm(try(function() return mesh:GetPhysicsAsset() end)),
    try(function() return mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end) == true and "simulating" or "not simulating")
end
function M.adopted(a, e, mine)
  if not mine then return end
  live[a] = { e = e, k = e.kind, at = os.clock() }
  own_physics(e)
  if rows[e.kind.row] then rows[e.kind.row].t = os.clock() end
end

-- the boss bar: the HUD's enemy info widget's HP bar (0..1), nil when none shows. Its class's default object is
-- never the one: FindFirstOf could hand that back, kept for good (valid), and no bar was ever read. Looked for while
-- none is held (a scan of every object, 35 ms): 5 s after, then twice as long each time it isn't found, to a minute
-- (every 5 s it was a stutter of its own while a passive boss, which never shows one, stood there)
local hud = { w = nil, next = 0, wait = 5 }
function M.bar_soon() if not valid(hud.w) then hud.next, hud.wait = math.min(hud.next, os.clock() + 1), 5 end end
local function bar()
  local now = os.clock()
  if not valid(hud.w) and now >= hud.next then
    hud.w = nil
    for _, x in ipairs(try(function() return FindAllOf(M.HUD) end) or {}) do
      if valid(x) and not tostring(try(function() return x:GetFName():ToString() end)):find("^Default__") then hud.w = x; break end
    end
    hud.next = now + hud.wait
    hud.wait = hud.w and 5 or math.min(hud.wait * 2, 60)
  end
  local w = hud.w
  if not valid(w) then return nil end
  if try(function() return w:IsVisible() end) == false then return nil end
  local p = try(function() return w.ProgressBar_HP.Percent end)
  return type(p) == "number" and p or nil
end

-- its death: the cut is enemies.lua's; here its face and its struggle
local function new_struggle(e)
  if cfg().struggle == false or ctx.tune.deathMoves == false then return nil end
  if not struggleSrc then
    local f, err = loadfile("ue4ss/Mods/StellarBladeGore/Scripts/struggle.lua")
    if not f then log("struggle.lua not read: " .. tostring(err)); struggleSrc = false; return nil end
    struggleSrc = f
  end
  if not struggleSrc then return nil end
  local ok, s = pcall(struggleSrc)
  if not (ok and type(s) == "table") then log("struggle copy failed: " .. tostring(s)); return nil end
  local mesh, t0 = e.mesh, os.clock()
  local still, last = 0, os.clock()
  -- (its ragdoll as struggle.lua reads Eve's, active.lua's view: how long it has run, whether it lies still yet)
  local rag = {
    MASS = ctx.rag and ctx.rag.MASS or {},
    view = function()
      if not valid(mesh) then return nil end
      local now = os.clock()
      local v = try(function() local x = mesh:GetPhysicsLinearVelocity(FName("Bip001-Pelvis")); return math.sqrt(x.X * x.X + x.Y * x.Y + x.Z * x.Z) end)
      if v and v < 20 then still = still + (now - last) else still = 0 end
      last = now
      return { mesh = mesh, comps = { mesh }, t = now - t0, settled = still > 0.3 }
    end,
    severed = function(m, b) return ctx.gore and ctx.gore.enemy_off and (ctx.gore.enemy_off(e.addr) or {})[b] == true end,
    live = function(m, b) return try(function() return m:IsSimulatingPhysics(FName(b)) end) ~= false end,
    twitch = function() end,
  }
  local sctx = setmetatable({
    log = function(x) ctx.log("boss " .. x) end, rag = rag, gore = false, animated = function() return false end,
    ragdoll_quiet = false, struggle_test = false,
    convulse = { effort = function() return "" end, resting = function() return false end, face = function() return {} end },
  }, { __index = ctx })
  s.init(sctx)
  s.start(e.obj, mesh)
  return s
end

function M.died(pawn, a, e)
  local x = live[a]
  live[a] = nil
  if not x then return end
  e.addr = a
  local d = { e = e, t = os.clock() }
  local df = (ctx.tune.gore or {}).deathFace or {}
  if cfg().face ~= false and df.enabled ~= false and ctx.new_face then d.faceAt = os.clock() + (df.at or 0.3) end
  d.struggle = new_struggle(e)
  dead[a] = d
  if e.kind.physics then
    d.probe = { 0.1, 0.3, 0.6, 1.0, 2.0 }
    log(string.format("%s %x at its death: %s", e.kind.alias, a, M.physics_line(e)))
  end
  log(string.format("%s %x died (%s)", e.kind.alias, a, x.how or "the game's death"))
end

function M.gone(a, e)
  live[a] = nil
  local d = dead[a]
  dead[a] = nil
  if d then
    if d.face then try(function() d.face.stop() end) end
    if d.struggle then try(function() d.struggle.forget() end) end
  end
end

-- the mod's own kill of a boss the game holds at a sliver of HP
local function take_down(pawn, a, x, why)
  if x.downed or not (ctx.enemies and ctx.enemies.kill_one) then return end
  x.how, x.downed = why, true
  local her = try(function() local l = pawn:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
  ctx.enemies.kill_one(x.e, her, a, why)
end

-- bosses.passive: one spawned here stands where it is and never fights back. Its behaviour tree is its own: an
-- SBBehaviorTreeComponent on the pawn (SBCharacter.BrainComponent), its SBAIController's BrainComponent is none. Its
-- controller's tree stopped and the controller letting go of it did nothing (playtests: Raven fought on, grabbed her
-- and killed her, never possessed again), so the pawn's own tree is stopped, its controller still lets go of it
-- (UnPossess: no moving to her) and the attack it is in is cut short; looked at every AI_EVERY s (the game starting
-- its tree or possessing it again: stopped, let go again). Off again, the controller takes it back and both trees
-- start over
M.AI_EVERY = 0.25
local function cls_of(o) return valid(o) and try(function() return o:GetClass():GetFName():ToString() end) or "none" end
local function hold_ai(a, x, on, now)
  if now < (x.aiAt or 0) then return end
  x.aiAt = now + M.AI_EVERY
  local o = x.e.obj
  if not valid(o) then return end
  local ctl = try(function() return o.Controller end)
  if not valid(ctl) then ctl = nil end
  local own = try(function() return o.BrainComponent end)
  if not valid(own) then own = nil end
  if on then
    local running = own and try(function() return own:IsRunning() end)
    if own and running ~= false then try(function() own:StopLogic("SBGore passive") end) end
    if ctl then
      local br = try(function() return ctl.BrainComponent end)
      if valid(br) then try(function() br:StopLogic("SBGore passive") end) end
      try(function() ctl:StopMovement() end)
      try(function() ctl:UnPossess() end)
    end
    local held = valid(try(function() return o.Controller end))
    -- (the attack it was in, its montage, cut short; its movement stopped where it stands)
    if ctl or running == true or not x.passive then
      try(function() o.Mesh:GetAnimInstance():Montage_Stop(0.25, nil) end)
      try(function() o.CharacterMovement:StopMovementImmediately() end)
    end
    if not x.passive then
      if not ctl and not own then
        if not x.noCtl then x.noCtl = true; log(string.format("%s %x: no tree or controller to stop (Passive Bosses)", x.k.alias, a)) end
        return
      end
      x.passive, x.ctl, x.own = true, ctl, own
      log(string.format("%s %x stands still (Passive Bosses): its tree %s stopped%s, %s", x.k.alias, a, cls_of(own),
        own and running == nil and " (running unknown)" or "",
        ctl and string.format("its %s let go of it%s", cls_of(ctl), held and " NOT (still possessed)" or "") or "no controller"))
    else
      if ctl and not held then log(string.format("%s %x: possessed again, let go again", x.k.alias, a)) end
      if running == true then log(string.format("%s %x: its tree started again, stopped again", x.k.alias, a)) end
      if ctl then x.ctl = ctl end
    end
  elseif x.passive then
    x.passive = nil
    local c, b = x.ctl, x.own
    x.ctl, x.own = nil, nil
    if not ctl and valid(c) then try(function() c:Possess(o) end) end
    local br = valid(c) and try(function() return c.BrainComponent end)
    if valid(br) then try(function() br:RestartLogic() end) end
    if valid(b) then try(function() b:RestartLogic() end) end
    log(string.format("%s %x fights again (%s, its tree %s)", x.k.alias, a,
      valid(try(function() return o.Controller end)) and "possessed" or "NOT possessed",
      valid(b) and (try(function() return b:IsRunning() end) == false and "NOT running" or "started over") or "none"))
  end
end

M.next = 0
M.STUCK_CM = 50
-- its bar and place since they last changed, and the hits on it meanwhile: stood through stuckHits over stuckS s
local function stuck(x, p, l, hit, now)
  local h = x.held
  local moved = h and l and h.l and math.sqrt((l.X - h.l.X) ^ 2 + (l.Y - h.l.Y) ^ 2) > M.STUCK_CM
  if not h or math.abs(p - h.p) > 0.0005 or moved then
    x.held = { p = p, l = l, t = now, hits = 0, hit = hit }
    return false
  end
  if hit and hit ~= h.hit then h.hit, h.hits = hit, h.hits + 1 end
  return h.hits >= (tonumber(cfg().stuckHits) or 3) and now - h.t >= (tonumber(cfg().stuckS) or 4)
end
-- its HP, read where the game keeps it (sbslice vb: its stats found by the MaxHP and MaxShield its row was given, else
-- their ratio). The boss bar is no help on one spawned here: it never showed for a passive one (playtest, "its bar not
-- shown"), and a hit reaction is no sign of damage (Tachy reacted to blows that took nothing). Read every HP_EVERY s;
-- the search (a scan of its memory, a frame's worth) is tried at most HP_TRIES times, HP_RETRY s apart
M.HP_EVERY, M.HP_TRIES, M.HP_RETRY = 0.2, 3, 5
local function read_hp(a, x, now)
  local r = rows[x.k.row]
  if not (r and r.mhp and r.mhp > 0) or (x.hpTries or 0) >= M.HP_TRIES and not x.hp then return x.hp end
  if now < (x.hpAt or 0) then return x.hp end
  local cmd = string.format("vb%x,%x,%x", a, r.mhp, r.msh or 0)
  local got = x.hp ~= nil
  local res = ctx.gore.command(cmd)
  local hp, mhp, sh, msh = res:match("^ok [%a ]*(%-?[%d.]+) (%-?[%d.]+) (%-?[%d.]+) (%-?[%d.]+)$")
  -- a maximum nowhere near its row's is some other pair of numbers (by its ratio: 0/250 and 0/15.27 on a Tachy of
  -- 5456, 1/51.48 on a Raven of 12415, playtest: each put at its floor seconds after it came, down in a hit or two)
  local m = tonumber(mhp)
  if m and (m < r.mhp * 0.1 or m > r.mhp * 10) then
    if not x.hpOdd then
      x.hpOdd = true
      log(string.format("%s %x: a read of its HP left (%s): its maximum isn't near %.0f", x.k.alias, a, res, r.mhp))
    end
    hp = nil
    res = "not near its row's maximum"
  end
  if hp then
    x.hp = { hp = tonumber(hp), mhp = tonumber(mhp), sh = tonumber(sh), msh = tonumber(msh) }
    x.hpAt = now + M.HP_EVERY
    if res:find("found") then
      log(string.format("%s %x: its HP found in memory (%s): %s", x.k.alias, a, res:find("ratio") and "by its ratio" or "by its maximum",
        res:match("^ok [%a ]*(.+)$")))
    end
  else
    x.hp = nil
    if not got then x.hpTries = (x.hpTries or 0) + 1 end
    x.hpAt = now + (got and M.HP_EVERY or M.HP_RETRY)
    if got or x.hpTries >= M.HP_TRIES then
      log(string.format("%s %x: its HP %s (%s)", x.k.alias, a, got and "lost" or "not found in memory", res))
    end
  end
  return x.hp
end

-- blows that land on nothing: her blade through one (enemies.struck) with no hit reaction on it (its mesh's,
-- enemies poll_hit) and its bar unmoved since the blow before. A phase change can hold one invincible until its
-- behaviour tree plays the change: one standing still (Passive Bosses) never does (playtest: Tachy and Scarlet took no
-- more damage partway down, their bars above the floor, no hit reaction for the stuck check to count). stuckHits such
-- blows over stuckS s take it down (twice that while it fights: a guarded blow lands on nothing too)
local function unanswered(pawn, a, x, p, now)
  local t = ctx.enemies and ctx.enemies.struck and ctx.enemies.struck(pawn, x.e, (x.blow or {}).t)
  if not t then return false end
  local b = x.blow
  local h = x.hp
  local life = h and h.hp + h.sh
  -- (its HP read: only HP or shield lost counts as a blow taken; else its hit reaction or its bar moving)
  local took
  if life then took = b and b.life and life < b.life - 0.01
  else
    local hit = x.e.hit and x.e.hit.t
    took = b and ((hit and hit > b.t - 0.1) or (p and b.p and math.abs(p - b.p) > 0.0005))
  end
  if not b or took or (life ~= nil) ~= (b.life ~= nil) then
    x.blow = { t = t, p = p, life = life, n = 0, from = t }
    return false
  end
  b.t, b.p, b.n = t, p, b.n + 1
  if b.n == 1 then
    log(string.format("%s %x: struck, no hit taken (%s)", x.k.alias, a, h and string.format("its HP %.0f/%.0f, shield %.0f/%.0f",
      h.hp, h.mhp, h.sh, h.msh) or p and string.format("its bar %.3f", p) or "its bar not shown, its HP not read"))
  end
  local k = x.passive and 1 or 2
  return b.n >= (tonumber(cfg().stuckHits) or 3) * k and now - b.from >= (tonumber(cfg().stuckS) or 4) * k
end
function M.tick(pawn)
  local now = os.clock()
  -- the rows put back once none of their kind spawned here is left (and none asked for in the last 15 s); one whose
  -- actor went without enemies.lua telling (removed from the spawner window, destroyed) isn't left counted: its row
  -- stayed mortal for good
  if now >= M.next then
    M.next = now + 1
    local up = {}
    for a, x in pairs(live) do
      if valid(x.e.obj) and try(function() return x.e.obj.bActorIsBeingDestroyed end) ~= true then up[x.k.row] = true
      else live[a] = nil end
    end
    for _, d in pairs(dead) do up[d.e.kind.row] = true end
    for row, r in pairs(rows) do
      if not up[row] and now - r.t > 15 then put_back(row, "none of yours left") end
    end
    if cfg().enabled ~= true then for row in pairs(rows) do put_back(row, "Sandbox Bosses off") end end
  end
  local passive = cfg().passive == true and cfg().enabled == true
  for a, x in pairs(live) do if not x.downed then hold_ai(a, x, passive, now) end end
  -- their floors: the nearest live one spawned here is the one the boss bar shows
  if next(live) and cfg().floorKill ~= false then
    local p = bar()
    local her = try(function() local l = pawn:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
    local best, bd, ba, bl
    local reach = tonumber(cfg().barReach) or 3000
    for a, x in pairs(live) do
      local l = her and valid(x.e.obj) and try(function() local v = x.e.obj:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
      local d = l and math.sqrt((l.X - her.X) ^ 2 + (l.Y - her.Y) ^ 2)
      -- (one far off isn't the one the bar shows: another enemy's bar at 0 took it down from across the level)
      if d and d <= reach and (not bd or d < bd) then best, bd, ba, bl = x, d, a, l end
    end
    -- (its own HP, read, before the bar: the bar shows whichever boss the game has in its fight)
    if best and best.hp and best.hp.mhp > 0 then p = best.hp.hp / best.hp.mhp end
    if best and p then
      local floor = tonumber(cfg().floor) or 0.05
      local hit = best.e.hit and best.e.hit.t
      if p <= floor then
        if not best.floorT then
          best.floorT, best.floorHit = now, hit
          log(string.format("%s %x: its bar at %.3f (floor %.2f): the next hit takes it down", best.k.alias, ba, p, floor))
        elseif hit and hit ~= best.floorHit and hit > best.floorT then
          take_down(pawn, ba, best, string.format("its bar held at %.3f and hit again", p))
        elseif p <= 0.001 and now - best.floorT > (tonumber(cfg().zeroWait) or 1.5) and hit and now - hit < 10 then
          take_down(pawn, ba, best, "its bar at 0 and still up")
        end
      else
        best.floorT = nil
        if stuck(best, p, bl, hit, now) then
          take_down(pawn, ba, best, string.format("its bar held at %.3f, standing in place, through %d hits over %.1f s "
            .. "(a phase change waiting on its arena)", p, best.held.hits, now - best.held.t))
        end
      end
    end
  end
  if next(live) and cfg().floorKill ~= false then
    local p = bar()
    for a, x in pairs(live) do
      local h = not x.downed and read_hp(a, x, now)
      if not x.downed and unanswered(pawn, a, x, h and h.mhp > 0 and h.hp / h.mhp or p, now) then
        take_down(pawn, a, x, string.format("struck %d times over %.1f s, no hit taken (held invincible: a phase change "
          .. "waiting on its AI or its arena)", x.blow.n + 1, now - x.blow.from))
      end
    end
  end
  -- the dead ones: the face from at s in, the struggle on its own
  local paused = false
  for a, d in pairs(dead) do
    if not valid(d.e.mesh) then
      dead[a] = nil
    else
      if d.faceAt and now >= d.faceAt then
        d.faceAt = nil
        d.face = ctx.new_face()
        try(function() d.face.start(d.e.obj, d.e.mesh, d.e.kind.alias) end)
      end
      if d.face then try(function() d.face.tick() end) end
      if d.probe and d.probe[1] and now - d.t >= d.probe[1] then
        log(string.format("%s %x %.1f s after its death: %s", d.e.kind.alias, a, now - d.t, M.physics_line(d.e)))
        table.remove(d.probe, 1)
      end
      if d.struggle then
        local ok, err = pcall(d.struggle.tick, paused)
        if not ok then log(d.e.kind.alias .. " struggle: " .. tostring(err)); d.struggle = nil end
      end
    end
  end
end

-- F3 → Sandbox → Spawn Boss: the picked one in front of her
function M.spawn_pick(pawn)
  local pick = cfg().pick or "tachy"
  for _, k in ipairs(cfg().kinds or {}) do
    if k.key == pick then
      if not (ctx.enemies and ctx.enemies.spawn_kind) then log("spawn: no enemies.lua"); return end
      if not valid(pawn) then log("spawn: no Eve"); return end
      ctx.enemies.spawn_kind(pawn, k, 1)
      return
    end
  end
  log("spawn: no boss " .. tostring(pick) .. " in tune.bosses.kinds")
end
-- F3 → Sandbox → Remove Spawned: everything the spawner made goes
function M.remove(pawn)
  if ctx.enemies and ctx.enemies.remove_spawned then ctx.enemies.remove_spawned() end
  for a in pairs(dead) do M.gone(a) end
  live = {}
end

-- the level reloaded: the old world's dropped without touching it; the rows put back (the tables outlive levels)
function M.forget()
  for a, d in pairs(dead) do if d.struggle then pcall(d.struggle.forget) end end
  live, dead, hud.w = {}, {}, nil
  for row in pairs(rows) do pcall(put_back, row, "level reloaded") end
end

-- (the sims)
M._rows, M._live, M._dead = function() return rows end, function() return live end, function() return dead end
return M
