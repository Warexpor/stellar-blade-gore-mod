-- Check behavior of the GC probe and reversible cvar settings without depending on main.lua upvalues.
local screen, ctx, messages = {}, {}, {}
local tune, active, pawn = { verboseLog = false, fewerGC = false }, true, {}
local calls, old = 0, nil
local cvs = { ["s.ForceGCAfterLevelStreamedOut"] = 2, ["s.ContinuouslyIncrementalGCWhileLevelsPendingPurge"] = 1 }
local ksl = { GetConsoleVariableIntValue = function(_, key) return cvs[key] end }
local cls, outer = {}, {}
StaticFindObject = function(path) return path:find("KismetSystemLibrary", 1, true) and ksl or cls end
FindFirstOf = function() return outer end
FName = function(s) return s end
StaticConstructObject = function() return {} end
ctx.gore = { native_ready = function() return true end }
ctx.keep = function(obj) return { obj = obj } end
ctx.alive_ask = function(list) calls = calls + 1; list[1].alive = list[1] ~= old; return true end
local function safe(fn) local ok, result = pcall(fn); if ok then return result end end
local function valid(obj) return obj ~= nil end
local function log(s) messages[#messages + 1] = s end
screen.console = function(_, command)
  local key, value = command:match("^(%S+) (%d+)$")
  cvs[key] = tonumber(value)
  return true
end
dofile("ue4ss/Mods/StellarBladeGore/Scripts/performance.lua")(screen, ctx, valid, safe, log,
  function() return active end, function() return tune end, function() return pawn end)
local fails = 0
local function check(ok, text) print((ok and "ok   " or "FAIL ") .. text); if not ok then fails = fails + 1 end end
screen.deathAt = os.clock()
check(not screen.gc_ran(true) and calls == 0, "death window suppresses even forced native probes")
screen.deathAt = os.clock() - 7
check(not screen.gc_ran(true) and calls == 1 and screen.gc.k ~= nil, "first probe makes and validates a guard")
old = screen.gc.k
check(screen.gc_ran(true) and calls == 3 and screen.gc.runs == 1 and screen.gc.k ~= old,
  "a freed probe records one collection and validates its replacement")
tune.fewerGC = true
screen.gc_tune()
check(cvs["s.ForceGCAfterLevelStreamedOut"] == 0 and cvs["s.ContinuouslyIncrementalGCWhileLevelsPendingPurge"] == 0,
  "fewer GC applies both engine options")
tune.fewerGC = false
screen.gc_tune()
check(cvs["s.ForceGCAfterLevelStreamedOut"] == 2 and cvs["s.ContinuouslyIncrementalGCWhileLevelsPendingPurge"] == 1,
  "disabling fewer GC restores each original engine option")
-- A missing original must not be replaced with a guessed value. A failed write must
-- remain recoverable even when the player switches the option off before a retry.
local originalRead, originalConsole = ksl.GetConsoleVariableIntValue, screen.console
local missing = "s.ForceGCAfterLevelStreamedOut"
ksl.GetConsoleVariableIntValue = function(self, key) if key == missing then error("unavailable") end; return originalRead(self, key) end
tune.fewerGC = true
screen.gc_tune()
check(cvs[missing] == 2 and screen.gc.tuned == nil, "unknown original is left untouched and remains retryable")
ksl.GetConsoleVariableIntValue = originalRead
screen.console = function(p, command) if command:find(missing, 1, true) then return false end; return originalConsole(p, command) end
screen.gc_tune()
check(cvs[missing] == 2 and screen.gc.tuned == nil, "failed application remains retryable")
screen.console = originalConsole
tune.fewerGC = false
screen.gc_tune()
check(cvs[missing] == 2 and cvs["s.ContinuouslyIncrementalGCWhileLevelsPendingPurge"] == 1,
  "turning off after partial application restores known originals")
tune.fewerGC = true
screen.gc_tune()
screen.console = function(p, command) if command:find(missing, 1, true) then return false end; return originalConsole(p, command) end
tune.fewerGC = false
screen.gc_tune()
check(cvs[missing] == 0 and screen.gc.tuned == nil, "failed restoration keeps the original for retry")
screen.console = originalConsole
screen.gc_tune()
check(cvs[missing] == 2 and screen.gc.tuned == false, "later restoration retries and succeeds")
print(fails == 0 and "PASS" or "FAIL")
