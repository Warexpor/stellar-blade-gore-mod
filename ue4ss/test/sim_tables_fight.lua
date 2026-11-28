-- Death-show fight detection: another mod rewriting the Player death shows after us is named in the log.
local M = dofile("ue4ss/Mods/StellarBladeGore/Scripts/tables.lua")

local SHOW_FIELDS = { "StandDeadShow", "Step0DeadShow", "Step1DeadShow", "Step2DeadShow", "Step3DeadShow",
  "Explosion1DeadShow", "Explosion2DeadShow", "AirborneDeadShow" }
local ADDR, RS_ADDR = 0x1000, 0x2000
local offOf, byOff = {}, {}
for i, f in ipairs(SHOW_FIELDS) do offOf[f], byOff[0x10 * i] = 0x10 * i, f end

-- the table's shows as the game holds them (nil = never written); a foreign mod writes its own path
local current = {}
local function prop(fname, class, off)
  return {
    GetFName = function() return { ToString = function() return fname end } end,
    GetClass = function() return { GetFName = function() return { ToString = function() return class end } end } end,
    GetOffset_Internal = function() return off end,
  }
end
local rs = {
  GetAddress = function() return RS_ADDR end,
  ForEachProperty = function(_, cb)
    for _, f in ipairs(SHOW_FIELDS) do cb(prop(f, "StrProperty", offOf[f])) end
  end,
}
local dt = { RowStruct = rs, GetAddress = function() return ADDR end }
function StaticFindObject(path)
  if path == M.DEAD then return dt end
  return nil
end
function FName(_) return { GetComparisonIndex = function() return 7 end } end

local logs = {}
local ctx = {
  log = function(s) logs[#logs + 1] = s end,
  try = function(fn, ...) local ok, v = pcall(fn, ...); if ok then return v end return nil end,
  valid = function(o) return o ~= nil end,
  levelAt = os.clock() - 10,
  gore = {
    native_state = function() return "ready" end,
    row_float = function() return 0 end,
    command = function(s)
      local off, show = s:match("^D%x+,%x+,%x+,%x+,(%x+);(.*)$")
      local field = off and byOff[tonumber(off, 16)]
      if not field then return "err fields" end
      if current[field] == show then return "ok str same" end
      current[field] = show
      return "ok str set"
    end,
  },
}
M.init(ctx)

local fails = 0
local function check(ok, msg) print((ok and "ok   " or "FAIL ") .. msg); if not ok then fails = fails + 1 end end
local function lastlog() return logs[#logs] or "" end

M.tick()
check(#logs == 1 and lastlog():find("8 death shows set, 0 already ours", 1, true), "first run writes all shows")
check(not lastlog():find("another mod", 1, true), "first run names no fight")
check(M.done[M.DEAD] == ADDR and M.wroteDead == ADDR, "first run records the table address")

M.tick()
check(#logs == 1, "second tick re-runs nothing")

-- another death mod (e.g. in the DEGEN AIO collection) rewrites a show after us; the next unseen death rechecks
current.Step2DeadShow = "OTHER_MOD/Show"
M.recheck_dead()
M.tick()
check(#logs == 2 and lastlog():find("7 already ours", 1, true), "recheck keeps our shows")
check(lastlog():find("another mod rewrote her death shows after us (Step2DeadShow)", 1, true),
  "recheck names the rewritten field")

-- a remade table (new level) is a fresh write, not a fight
ADDR = 0x3000
for _, f in ipairs(SHOW_FIELDS) do current[f] = "OTHER_MOD/Show" end
M.recheck_dead()
M.tick()
check(#logs == 3 and lastlog():find("8 death shows set, 0 already ours", 1, true), "remade table written again")
check(not lastlog():find("another mod", 1, true), "remade table is no fight")

local now = os.clock()
os.clock = function() return now end
local chain = prop("ChainEffectAliasArray", "ArrayProperty", 0x18)
chain.GetInner = function() return prop("Name", "NameProperty", 0) end
local effectAddr = 0x4000
local effectRs = {
  GetAddress = function() return 0x5000 end,
  ForEachProperty = function(_, cb) cb(prop("ID", "IntProperty", 0)); cb(chain) end,
}
local effect = { RowStruct = effectRs, GetAddress = function() return effectAddr end }
local find = StaticFindObject
StaticFindObject = function(path) if path == M.EFFECT then return effect end; return find(path) end
local names = { Down = 2, Down_Eve = 3 }
for i, name in ipairs(M.HOLD.chains) do names[name] = 6 + i end
function FName(name) return { GetComparisonIndex = function() return names[name] or 1 end } end
local ordering, maps = {}, false
local retriedLink = 0
local command = ctx.gore.command
ctx.tune = { holdDown = true }
ctx.gore.command = function(s)
  if s:match("^A") then return "ok row added" end
  if s:match("^d") then return "ok row 1 48" end
  if s == "&Y7" then return "ok started" end
  if s == "&?" then return "done 1000 0 0 0 0 48 0 0 0 0" end
  if s == "Mh1000,14" then return "ok set 2000" end
  if s == "Yd48" then return "1000 0 0 0 0 700000048 0 0 0 0" end
  if s == "Mi1000,14" then return "ok set 3000" end
  if s:match("^M") then
    ordering[#ordering + 1] = "maps"
    return maps and "ok ids added" or "err test map failure"
  end
  if s:match("^N") then
    ordering[#ordering + 1] = "chain"
    if effectAddr == 0x4000 then return "ok names 1 of 1, existing 0" end
    local name = s:match("^N%x+,%x+,(%x+),")
    if name == "7" then return "ok names 0 of 1, existing 1" end
    if name == "8" then return "ok names 0 of 1, existing 0" end
    retriedLink = retriedLink + 1
    return retriedLink == 1 and "err test busy" or "ok names 1 of 1, existing 0"
  end
  return command(s)
end
ctx.gore.row_float = function(obj, row, field, value)
  if obj == effect and row == "Down_Eve" and field == "LifeTime" then ordering[#ordering + 1] = value end
  return 1
end
local function tick(step) now = now + step; M.tick() end
tick(3)
tick(0.2)
check(#ordering == 0, "knockdown chains wait through the lookup scan")
tick(0.2)
check(#ordering == 1 and ordering[1] == "maps", "a failed lookup map write leaves vanilla chains intact")
maps = true
tick(3.1)
tick(0.2)
tick(0.2)
check(table.concat(ordering, ",") == "maps,maps,100000,chain,chain,chain",
  "retry installs both maps and the held lifetime before changing any knockdown chains")
ctx.tune.holdDown = false
tick(0.2)
check(ordering[#ordering] == 1 and #ordering == 7, "turning the option off restores the one-second lifetime")
effectAddr = 0x6000
tick(3.1)
tick(0.2)
tick(0.2)
check(lastlog():find("1 of 3 knockdowns chained", 1, true) and lastlog():find("no Down or Down_Eve link", 1, true),
  "already-correct links count and unrelated aliases are left alone and reported")
tick(3.1)
tick(0.2)
tick(0.2)
check(retriedLink == 2 and lastlog():find("2 of 3 knockdowns chained", 1, true),
  "a transient chain failure can retry independently of map setup")
print(fails == 0 and "PASS" or "FAIL")
