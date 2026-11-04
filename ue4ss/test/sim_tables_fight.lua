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
print(fails == 0 and "PASS" or "FAIL")
