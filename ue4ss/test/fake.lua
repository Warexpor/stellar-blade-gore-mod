-- A made-up game for the mod's Lua (the scripts as they ship, unchanged): UE4SS's globals, a clock the scenario
-- drives, and objects that answer what the scripts ask of them. Anything not made up answers nil (a no-op call), as
-- an engine call inside the scripts' try() that comes to nothing. sbslice.dll is faked at its command boundary (the
-- cheat manager's repointed UFunction): every command is recorded, and answered by F.sbslice (a scenario can add).
local F = { calls = {}, cmds = {}, hooks = {}, notify = {}, loops = {}, t = 1000.0, errors = {} }

-- the scripts' time: os.clock, advanced by F.step
os.clock = function() return F.t end

local nextAddr = 0x7f0000100000
local Base = {}
local OMT = {}
OMT.__index = function(t, k)
  local b = Base[k]
  if b then return b end
  -- (anything else named like a method: one that does nothing, its calls recorded; a property: nil)
  if type(k) ~= "string" or not F.is_method(k) then return nil end
  return function(self, ...)
    F.calls[#F.calls + 1] = (rawget(t, "__name") or "?") .. ":" .. tostring(k)
    return nil
  end
end

local VERBS = { "Get", "Set", "Is", "K2_", "Add", "Remove", "Show", "Hide", "Create", "Destroy", "Wake", "Put",
  "Break", "Reset", "Play", "Stop", "Activate", "Deactivate", "Attach", "Detach", "Recreate", "Update", "Force",
  "Clear", "Enable", "Disable", "Init", "Register", "Unregister", "Mark", "Copy", "Apply", "Begin", "End", "Can",
  "Has", "Find", "Spawn", "SB", "Sb", "Client", "Server", "Notify", "Receive", "Toggle", "Refresh", "Change", "Lock",
  "Unlock", "Move", "Teleport", "Trace", "LineTrace", "Release", "Finish", "Snap", "Reinit",
  "Override", "Bind", "Unbind", "Restore", "Suspend", "Resume", "Tick", "Advance", "Blend", "Cancel", "Launch",
  "Jump", "Draw", "Fire", "Load", "Unload", "Request", "Send", "Make", "Calc", "Compute" }
function F.is_method(k)
  for _, v in ipairs(VERBS) do if k:sub(1, #v) == v then return true end end
  return false
end
function F.fname(s)
  return setmetatable({ s = s }, {
    __index = { ToString = function(self) return self.s end, IsValid = function() return true end },
    __eq = function(a, b) return a.s == b.s end,
    __tostring = function(self) return self.s end,
  })
end
function F.obj(name, cls, props)
  local o = props or {}
  o.__name, o.__cls = name, cls or "Object"
  o.__addr = nextAddr
  nextAddr = nextAddr + 0x1000
  return setmetatable(o, OMT)
end
Base.IsValid = function(self) return rawget(self, "__dead") ~= true end
Base.GetAddress = function(self) return rawget(self, "__addr") end
Base.GetFName = function(self) return F.fname(rawget(self, "__name")) end
Base.GetFullName = function(self) return rawget(self, "__cls") .. " " .. rawget(self, "__name") end
Base.GetClass = function(self)
  local c = rawget(self, "__cls")
  return F.obj(c, "Class", { GetFName = function() return F.fname(c) end })
end
Base.type = function(self) return "UObject" end

-- UE4SS's globals
FName = function(s) return F.fname(tostring(s)) end
FText = function(s) return setmetatable({ s = s }, { __index = { ToString = function(self) return self.s end } }) end
Key = setmetatable({}, { __index = function(_, k) return k end })
ModifierKey = setmetatable({}, { __index = function(_, k) return k end })
F.objects = {}      -- path -> object (StaticFindObject, LoadAsset)
F.classes = {}      -- short class name -> { objects } (FindAllOf, FindFirstOf)
StaticFindObject = function(path) return F.objects[path] end
LoadAsset = function(path) return F.objects[path] end
FindAllOf = function(cls) local l = F.classes[cls]; return l and #l > 0 and l or nil end
FindFirstOf = function(cls) local l = F.classes[cls]; return l and l[1] or nil end
StaticConstructObject = function() return nil end
RegisterHook = function(fn, cb) F.hooks[fn] = F.hooks[fn] or {}; table.insert(F.hooks[fn], cb); return 1, 2 end
NotifyOnNewObject = function(cls, cb) F.notify[#F.notify + 1] = { cls = cls, cb = cb } end
LoopAsync = function(ms, cb) F.loops[#F.loops + 1] = { ms = ms, cb = cb, at = F.t } end
ExecuteInGameThread = function(cb) cb() end
DumpUSMAP = function() end
F.binds = {}
RegisterKeyBind = function(key, a, b)
  local mods, cb = {}, b
  if type(a) == "function" then cb = a else mods = a end
  F.binds[#F.binds + 1] = { key = key, mods = table.concat(mods, "+"), cb = cb }
end
-- a key pressed: its bind with exactly these modifiers ("Alt", "Ctrl+Shift": UE4SS's ModifierKey names)
function F.press(key, mods)
  for _, b in ipairs(F.binds) do if b.key == key and b.mods == (mods or "") then b.cb(); return true end end
  return false
end
F.printed = {}
F.say = print
print = function(s) F.printed[#F.printed + 1] = s end

-- a hook's parameters, as UE4SS hands them (RemoteUnrealParam)
function F.param(v) return { get = function() return v end, set = function() end } end
function F.fire(fn, ...)
  local n = 0
  for _, cb in ipairs(F.hooks[fn] or {}) do
    local ok, err = pcall(cb, ...)
    if not ok then F.errors[#F.errors + 1] = fn .. ": " .. tostring(err) end
    n = n + 1
  end
  return n
end

-- what happened, in order (sbslice's commands and the scenario's own events)
F.events = {}
function F.event(what)
  F.events[#F.events + 1] = { t = F.t, frame = F.frame, what = what }
  return #F.events
end

-- ---- sbslice.dll, faked ----
local RESULT = "ue4ss/Mods/StellarBladeGore/sbslice.cut"
-- answers by the command's first letter (a scenario sets more); a function gets the command
F.sbslice = {
  r = "ok restored 0",
  x = "ok cleared, restored 1",
  y = function(s) return "ok copied 1" end,
  V = function(s) return "ok vanish 100 kept 50 on 1 borrowed 0 stuck 0 mats -" end,
  -- held objects' liveness: every one alive, at a made-up index
  G = function(s)
    local out, n = {}, 0
    for _ in s:sub(2):gmatch("(%x+),(%x+)") do n = n + 1; out[#out + 1] = "1:" .. (1000 + n) .. " " end
    return "ok " .. table.concat(out)
  end,
}
local function write(path, s) local f = assert(io.open(path, "w")); f:write(s); f:close() end
F.cdo = F.obj("Default__SBCheatManager", "SBCheatManager", {
  SBRewardGroupDropFormationPathLocation = function(self, _n, _x, _y, _z, s)
    F.cmds[#F.cmds + 1] = { t = F.t, s = s, frame = F.frame, n = F.event("sbslice " .. s) }
    local a = F.sbslice[s:sub(1, 1)]
    if type(a) == "function" then a = a(s) end
    write(RESULT, a or ("err fake sbslice: no answer for " .. s:sub(1, 1)))
  end,
})
F.objects["/Script/SB.Default__SBCheatManager"] = F.cdo
F.objects["/Script/SB.SBCheatManager:SBRewardGroupDropFormationPathLocation"] = F.obj("SBRewardGroupDropFormationPathLocation", "Function")
-- the DLL's handshake: it answers the request file at once
function F.sbslice_ready()
  write("ue4ss/Mods/StellarBladeGore/sbslice.ok", "patched +0xd8, cpu copy LOD0 on, addresses as in the Steam build")
end

-- ---- running ----
F.frame = 0
-- one game frame of dt s: the async loops due, then her ReceiveTick (main.lua's game_tick), then the scenario's world
F.world = nil
local REQ = "ue4ss/Mods/StellarBladeGore/sbslice.req"
function F.step(dt, pawn)
  F.t = F.t + dt
  -- (the DLL's handshake: the script's request answered at once)
  local rq = io.open(REQ, "r")
  if rq then rq:close(); os.remove(REQ); F.sbslice_ready() end
  F.frame = F.frame + 1
  for _, l in ipairs(F.loops) do
    if not l.done and F.t >= l.at + l.ms / 1000 then
      l.at = F.t
      local ok, r = pcall(l.cb)
      if not ok then F.errors[#F.errors + 1] = "loop: " .. tostring(r) elseif r == true then l.done = true end
    end
  end
  if F.world then F.world(dt) end
  if pawn then F.fire(F.TICK_FN, F.param(pawn), F.param(dt)) end
end
function F.run(s, pawn, dt)
  dt = dt or 1 / 60
  local n = math.floor(s / dt + 0.5)
  for _ = 1, n do F.step(dt, pawn) end
end

-- the mod's log as written so far
F.LOG = "ue4ss/Mods/StellarBladeGore/stellarbladegore.log"
function F.log_lines()
  local out = {}
  local f = io.open(F.LOG, "r")
  if not f then return out end
  for l in f:lines() do out[#out + 1] = l end
  f:close()
  return out
end
function F.find(pat, from)
  for i, l in ipairs(F.log_lines()) do if i >= (from or 1) and l:find(pat) then return l, i end end
end

return F
