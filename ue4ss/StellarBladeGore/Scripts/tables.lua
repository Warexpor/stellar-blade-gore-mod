-- The game's DataTables as this mod wants them, changed in game by sbslice.dll (D, N, A, d). They were whole tables
-- in the data pak (EffectTable, CharacterDeadTable), built from the vanilla ones: loaded last, they overrode every
-- other mod's copy, and the rows those mods added were gone (Nexus: the nano suits gone with a moveset mod, buying
-- in a shop mod crashed). Now only these rows change, in whatever table the game loaded:
--   EffectTable: Down_Eve, a copy of Down (ID 3009001), her tumbling knockdowns chained into it (main.lua's holdDown
--     sets its LifeTime)
--   CharacterDeadTable, Player: the death shows (the data pak's ragdoll and animated deaths) and the revive screen's
--     delay
local M = {}
local ctx, log, try, valid

M.EFFECT = "/Game/Local/Data/EffectTable.EffectTable"
M.DEAD = "/Game/Local/Data/CharacterDeadTable.CharacterDeadTable"
M.HOLD = { row = "Down_Eve", from = "Down", id = 3009001,
  chains = { "KnockDownForwardTumbling_Eve", "KnockDownBackwardTumbling_Eve", "KnockDownTumbling_Eve_EffectArea" } }
M.CHAIN = true -- her knockdowns chained into Down_Eve (false: left the game's, Down_Eve made but unused)
M.DEAD_ROW = "Player"
M.SHOWS = {
  StandDeadShow = "CH_P_EVE_01/Basic/P_Eve_Dead",
  Step0DeadShow = "CH_P_EVE_01/Basic/P_Eve_Dead2",
  Step1DeadShow = "CH_P_EVE_01/Basic/P_Eve_Dead3",
  Step2DeadShow = "CH_P_EVE_01/Ragdoll/EveRD_Step2",
  Step3DeadShow = "CH_P_EVE_01/Ragdoll/EveRD_Step3",
  Explosion1DeadShow = "CH_P_EVE_01/Ragdoll/EveRD_Explosion1",
  Explosion2DeadShow = "CH_P_EVE_01/Ragdoll/EveRD_Explosion2",
  AirborneDeadShow = "CH_P_EVE_01/Basic/P_Eve_AirDead",
}
-- the revive screen's delay in every death kind the pak set (main.lua holds it hidden on top of this: screen.*)
M.DELAYS = { "Default", "Stand", "Step0", "Step1", "Step2", "Step3", "Explosion1", "Explosion2", "Custom2", "Custom3",
  "Custom5", "Custom9", "Down", "Airborne" }
M.done = {}

function M.init(c)
  ctx, log, try, valid = c, c.log, c.try, c.valid
end

local function addr(o) return try(function() return o:GetAddress() end) end
local function name_idx(s) return try(function() return FName(s):GetComparisonIndex() end) end
-- one of sbslice's memory scans (Y, Yd, Mh, Mi: a pass over all the game's memory, about 0.5 s each) on its thread
-- ("&"): the four at once held one frame 2.2 s at the level's start (playtest). Its answer kept by command; while it
-- runs, PENDING is thrown and game_ids is run again from M.tick 0.1 s later (its other commands are cheap, the
-- scans done kept). An sbslice without "&": on the game thread as before
local PENDING = {}
M.memo, M.running = {}, nil
local function scan(cmd)
  if M.memo[cmd] then return M.memo[cmd] end
  if M.running == cmd then
    local r = ctx.gore.command("&?")
    if r == "busy" and os.clock() - M.runAt < 30 then error(PENDING, 0) end
    M.running = nil
    local got = r:match("^done (.*)$")
    -- (the game freed memory under the scan, a level streaming in: sbslice gave it up, it runs again in 2 s)
    if got == "err memory freed" and (M.retries or 0) < 10 then
      M.retries = (M.retries or 0) + 1
      if M.cont then M.cont.at = os.clock() + 2 end
      error(PENDING, 0)
    end
    M.memo[cmd] = got or ("err scan: " .. r)
    return M.memo[cmd]
  end
  local r = ctx.gore.command("&" .. cmd)
  if r == "ok started" then M.running, M.runAt = cmd, os.clock(); error(PENDING, 0) end
  M.memo[cmd] = ctx.gore.command(cmd)
  return M.memo[cmd]
end

-- a row struct's fields: { name = { off, class } }, and its size as far as known types go
local SIZE = { BoolProperty = 1, ByteProperty = 1, EnumProperty = 1, Int8Property = 1, Int16Property = 2,
  UInt16Property = 2, IntProperty = 4, UInt32Property = 4, FloatProperty = 4, Int64Property = 8, UInt64Property = 8,
  DoubleProperty = 8, NameProperty = 8, ObjectProperty = 8, ClassProperty = 8, StrProperty = 16, ArrayProperty = 16 }
local STRUCTS = { Vector = 12, Rotator = 12, Vector2D = 8, LinearColor = 16, Color = 4, Quat = 16, Guid = 16 }
local function fields(st)
  local out, least, bad = {}, 0, nil
  try(function() st:ForEachProperty(function(p)
    local nm = p:GetFName():ToString()
    local cls = p:GetClass():GetFName():ToString()
    local off = p:GetOffset_Internal()
    local sz = SIZE[cls]
    local f = { off = off, class = cls, p = p }
    if cls == "StructProperty" then
      local s = try(function() return p:GetStruct():GetFName():ToString() end)
      sz = STRUCTS[s or ""]
      f.struct = s
    end
    if not sz then bad = bad or (nm .. " " .. cls .. (f.struct and (" " .. f.struct) or "")) end
    out[nm] = f
    least = math.max(least, off + (sz or 0))
  end) end)
  return out, least, bad
end

-- the heap fields a copy of a row needs buffers of its own for, as sbslice's A takes them; nil and why when a field
-- can't be copied that way
local function heap_list(st)
  local fs, least, bad = fields(st)
  if bad then return nil, "a field of unknown size: " .. bad end
  local list = {}
  for nm, f in pairs(fs) do
    if f.class == "StrProperty" then
      list[#list + 1] = string.format("%x:2", f.off)
    elseif f.class == "ArrayProperty" then
      local inner = try(function() return f.p:GetInner() end)
      local ic = inner and try(function() return inner:GetClass():GetFName():ToString() end)
      if ic == "StructProperty" then
        local ist = try(function() return inner:GetStruct() end)
        if not ist then return nil, nm .. ": no element struct" end
        local efs, eleast, ebad = fields(ist)
        if ebad then return nil, nm .. ": " .. ebad end
        local subs = {}
        for en, ef in pairs(efs) do
          if ef.class == "StrProperty" then subs[#subs + 1] = string.format("%x", ef.off)
          elseif ef.class == "ArrayProperty" then return nil, nm .. "." .. en .. ": an array in an array element" end
        end
        if #subs > 4 then return nil, nm .. ": more than 4 strings in an element" end
        local stride = (eleast + 7) // 8 * 8
        list[#list + 1] = string.format("%x:%x", f.off, stride) .. (#subs > 0 and (":" .. table.concat(subs, "/")) or "")
      elseif ic == "StrProperty" then
        return nil, nm .. ": an array of strings"
      elseif ic and SIZE[ic] then
        list[#list + 1] = string.format("%x:%x", f.off, SIZE[ic])
      else
        return nil, nm .. ": an array of " .. tostring(ic)
      end
    end
  end
  return table.concat(list, ","), least, fs
end

local function table_of(path)
  local dt = try(function() return StaticFindObject(path) end)
  if not valid(dt) then return nil end
  local rs = try(function() return dt.RowStruct end)
  if not valid(rs) then return nil end
  return dt, rs
end

-- the game's own lookups of the effect table, made from it at load: alias -> ID and ID -> alias (sbslice M). Down_Eve
-- in the table alone was in neither: a knockdown chained into it stood her straight up, no getup (playtest). Found by
-- where a knockdown row's name (sbslice Y: the element whose value is its ID) and its ID (Yd: the element whose value
-- is its name) sit in memory, their headers by Mh / Mi. One full memory scan each, once a launch (about 0.5 s)
-- (on addresses and the ID field's offset only: it is run again each 0.1 s while a scan runs, and the table objects
-- aren't read again across that; t0: when it was first run)
local function game_ids(adt, ars, idoff, from, to, t0)
  local row = M.HOLD.chains[1]
  local key = name_idx(row)
  local id = key and ctx.gore.command(string.format("d%x,%x,%x,0,%x", adt, ars, key, idoff)):match("^ok row %x+ (%x+)")
  id = id and tonumber(id, 16) & 0xffffffff
  if not id then return "the game's ID maps NOT looked for (no ID for " .. row .. ")" end
  local function hits(r)
    local out = {}
    -- (each hit: its address, then the 4 qwords before its own and the 4 after; the 5th is its own)
    for at, rest in r:gmatch("(%x+) ([%x %?]+)") do
      local q = {}
      for x in rest:gmatch("%S+") do q[#q + 1] = x end
      out[#out + 1] = { at = at, q = q }
    end
    return out
  end
  local aliases, ids, tried = nil, nil, {}
  if not M.memo["log alias"] then M.memo["log alias"] = true; log("tables: looking for the game's ID maps (alias)") end
  for _, h in ipairs(hits(scan(string.format("Y%x", key)))) do
    -- (the qword after the key: its ID, then its hash chain's next)
    if not aliases and ((tonumber(h.q[5] or "", 16) or 0) & 0xffffffff) == id then
      local a = scan(string.format("Mh%s,14", h.at))
      aliases = a:match("^ok set (%x+)")
      if not aliases then tried[#tried + 1] = h.at .. ": " .. a:sub(1, 300) end
    end
  end
  if not M.memo["log ID"] then M.memo["log ID"] = true; log("tables: looking for the game's ID maps (ID)") end
  for _, h in ipairs(hits(scan(string.format("Yd%x", id)))) do
    -- (the 4 bytes after the ID: its name. The 5th qword is the ID's own 8-aligned one)
    local at = tonumber(h.at, 16)
    local q5 = tonumber(h.q[5] or "", 16) or 0
    local after = (at % 8 == 0) and (q5 >> 32) or ((tonumber(h.q[6] or "", 16) or 0) & 0xffffffff)
    if not ids and after == key then
      local a = scan(string.format("Mi%s,14", h.at))
      ids = a:match("^ok set (%x+)")
      if not ids then tried[#tried + 1] = h.at .. ": " .. a:sub(1, 300) end
    end
  end
  if not (aliases and ids) then
    return string.format("the game's ID maps NOT found (alias -> ID %s, ID -> alias %s)%s", tostring(aliases), tostring(ids),
      #tried > 0 and (" (" .. table.concat(tried, "; ") .. ")") or "")
  end
  -- (the effect table made again while the scans ran: its addresses gone with it)
  local now = try(function() return StaticFindObject(M.EFFECT) end)
  if not (valid(now) and addr(now) == adt) then return "the game's ID maps NOT given it: the effect table changed meanwhile" end
  log("tables: adding Down_Eve to the game's ID maps")
  local a = ctx.gore.command(string.format("M%s,%s,%x,%x,%x,%x,%x", aliases, ids, adt, ars, from, to, idoff))
  local made = a:match("^ok ids (%a+)")
  if not made then return "the game's ID maps NOT given it: " .. a end
  return string.format("in the game's ID maps (%s, %.0f ms)", made, (os.clock() - t0) * 1000)
end

-- EffectTable: Down_Eve made, her tumbling knockdowns chained into it
local function effect_rows()
  local dt, rs = table_of(M.EFFECT)
  if not dt then return nil end
  local h = M.HOLD
  local heap, least, fs = heap_list(rs)
  if not heap then return "Down_Eve NOT made: " .. tostring(least) end
  local from, to = name_idx(h.from), name_idx(h.row)
  if not (from and to and fs.ID and fs.ChainEffectAliasArray) then return "Down_Eve NOT made: no names or fields" end
  log("tables: adding Down_Eve to the effect table")
  local r = ctx.gore.command(string.format("A%x,%x,%x,0,%x,0,%x;%s", addr(dt), addr(rs), from, to, least, heap))
  local made = r:match("^ok row (%a+)")
  if not made then return "Down_Eve NOT made: " .. r end
  local out = { "Down_Eve " .. made }
  if made == "added" then
    local idr = ctx.gore.command(string.format("d%x,%x,%x,0,%x,%x", addr(dt), addr(rs), to, fs.ID.off, h.id))
    if idr:sub(1, 2) ~= "ok" then out[#out + 1] = "its ID NOT set: " .. idr end
  end
  -- (the game resolves a chain through alias -> ID maps of its own, made at load: game_ids gives Down_Eve to them
  -- below; in the table alone, a knockdown chained into it stood her straight up with no getup, playtest)
  if not M.CHAIN then
    out[#out + 1] = "knockdowns left the game's (not chained into it)"
    return table.concat(out, ", ")
  end
  local chained = 0
  for _, row in ipairs(h.chains) do
    local ri = name_idx(row)
    local c = ri and ctx.gore.command(string.format("N%x,%x,%x,0,%x,%x,0,%x,0", addr(dt), addr(rs), ri, fs.ChainEffectAliasArray.off, from, to)) or "no name"
    local n = c:match("^ok names (%d+)")
    if n then chained = chained + 1 else out[#out + 1] = row .. " NOT chained: " .. c end
  end
  out[#out + 1] = string.format("%d of %d knockdowns chained into it", chained, #h.chains)
  -- (the game's ID maps: through M.tick while its scans run)
  M.memo, M.retries = {}, 0
  M.cont = { out = out, args = { addr(dt), addr(rs), fs.ID.off, from, to, os.clock() } }
  return PENDING
end

-- CharacterDeadTable, Player: the death shows and the revive screen's delay
local function dead_rows()
  local dt, rs = table_of(M.DEAD)
  if not dt then return nil end
  local fs = fields(rs)
  local row = name_idx(M.DEAD_ROW)
  if not row then return "Player NOT changed: no name" end
  local set, same, failed = 0, 0, {}
  for field, show in pairs(M.SHOWS) do
    local f = fs[field]
    local r = f and ctx.gore.command(string.format("D%x,%x,%x,0,%x;%s", addr(dt), addr(rs), row, f.off, show)) or "no field"
    if r == "ok str set" then set = set + 1 elseif r == "ok str same" then same = same + 1 else failed[#failed + 1] = field .. ": " .. r end
  end
  -- the game's own 0 in every mode: the screen and its intro start at once, and main.lua holds it hidden as
  -- deathScreen says (its intro waits while it is hidden). At reviveAt the game started the intro only then, so
  -- Shift+F4 earlier showed an empty screen till reviveAt s into the death (playtest)
  local delay = 0
  local delays = 0
  for _, k in ipairs(M.DELAYS) do
    local was = ctx.gore.row_float(dt, M.DEAD_ROW, k .. "DeadUIDelayTime", delay)
    if was then delays = delays + 1 end
  end
  return string.format("Player: %d death shows set, %d already ours%s, revive screen delay %g s in %d of %d", set, same,
    #failed > 0 and (", NOT: " .. table.concat(failed, "; ")) or "", delay, delays, #M.DELAYS)
end

-- every few seconds till both are done (sbslice.dll answers a few seconds after the start). A table object made again
-- (another address) is done again
M.next = 0
function M.tick()
  local now = os.clock()
  -- (the game's ID maps looked for while sbslice's scans run: again each 0.1 s till they are done)
  if M.cont then
    if now < (M.cont.at or 0) then return end
    M.cont.at = now + 0.1
    local c = M.cont
    local ok, r = pcall(game_ids, table.unpack(c.args))
    if not ok and r == PENDING then return end
    M.cont, M.memo, M.running = nil, {}, nil
    c.out[#c.out + 1] = ok and r or ("the game's ID maps failed: " .. tostring(r))
    log("tables: " .. table.concat(c.out, ", "))
    M.next = 0
    return
  end
  if now < M.next then return end
  M.next = now + 3
  local st = ctx.gore and ctx.gore.native_state()
  if st ~= "ready" then return end
  -- not in the title screen's first seconds: the game still loading there, the launch crashed twice in Lua as these
  -- scans and writes ran (playtest). Once the level is in and 5 s on, or 60 s into the session (scripts reloaded in
  -- a level: no reload comes)
  M.since = M.since or now
  if not ((ctx.levelAt and now - ctx.levelAt > 5) or now - M.since > 60) then return end
  for _, t in ipairs({ { M.EFFECT, effect_rows }, { M.DEAD, dead_rows } }) do
    local dt = try(function() return StaticFindObject(t[1]) end)
    local a = valid(dt) and addr(dt)
    if a and M.done[t[1]] ~= a then
      local ok, r = pcall(t[2])
      if ok and r == PENDING then M.done[t[1]] = a; return end
      if ok and r then
        M.done[t[1]] = a
        log("tables: " .. r)
      elseif not ok then
        M.done[t[1]] = a
        log("tables: " .. t[1] .. " failed: " .. tostring(r))
      end
    end
  end
end

-- the revive screen's delay changed in game (the menu): Player's delays written again
function M.redo_dead() M.done[M.DEAD] = nil; M.next = 0 end

return M
