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
  rows[k.row] = { dt = addr(dt), was = was, off = off, t = os.clock() }
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
function M.adopted(a, e, mine)
  if not mine then return end
  live[a] = { e = e, k = e.kind, at = os.clock() }
  if rows[e.kind.row] then rows[e.kind.row].t = os.clock() end
end

-- the boss bar: the HUD's enemy info widget's HP bar (0..1), nil when none shows
local hud = { w = nil, next = 0 }
local function bar()
  local now = os.clock()
  if not valid(hud.w) and now >= hud.next then
    hud.next = now + 1
    hud.w = try(function() return FindFirstOf(M.HUD) end)
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
function M.tick(pawn)
  local now = os.clock()
  -- the rows put back once none of their kind spawned here is left (and none asked for in the last 15 s)
  if now >= M.next then
    M.next = now + 1
    local up = {}
    for _, x in pairs(live) do up[x.k.row] = true end
    for _, d in pairs(dead) do up[d.e.kind.row] = true end
    for row, r in pairs(rows) do
      if not up[row] and now - r.t > 15 then put_back(row, "none of yours left") end
    end
    if cfg().enabled ~= true then for row in pairs(rows) do put_back(row, "Sandbox Bosses off") end end
  end
  -- their floors: the nearest live one spawned here is the one the boss bar shows
  if next(live) and cfg().floorKill ~= false then
    local p = bar()
    local her = try(function() local l = pawn:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
    local best, bd, ba, bl
    for a, x in pairs(live) do
      local l = her and valid(x.e.obj) and try(function() local v = x.e.obj:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
      local d = l and math.sqrt((l.X - her.X) ^ 2 + (l.Y - her.Y) ^ 2)
      if d and (not bd or d < bd) then best, bd, ba, bl = x, d, a, l end
    end
    if best and p then
      local floor = tonumber(cfg().floor) or 0.05
      local hit = best.e.hit and best.e.hit.t
      if p <= floor then
        if not best.floorT then
          best.floorT, best.floorHit = now, hit
          log(string.format("%s %x: its bar at %.3f (floor %.2f): the next hit takes it down", best.k.alias, ba, p, floor))
        elseif hit and hit ~= best.floorHit and hit > best.floorT then
          take_down(pawn, ba, best, string.format("its bar held at %.3f and hit again", p))
        elseif p <= 0.001 and now - best.floorT > (tonumber(cfg().zeroWait) or 1.5) then
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
