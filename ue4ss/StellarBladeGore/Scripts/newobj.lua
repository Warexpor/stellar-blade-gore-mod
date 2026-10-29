-- Objects watched as the game makes them (characters, the death and photo mode widgets, photo mode's pawn, knockdown
-- checks), through sbslice.dll ("O", new_watch there): the engine's own listener queues them on whatever thread makes
-- them, and they are handed to the watchers here, on her tick, one at a time. UE4SS's NotifyOnNewObject ran our Lua on
-- that thread itself: with the Nexus "SB UE4SS 1.3" build the game crashed at launch in its Lua (a callback on a
-- loading thread and her tick in the mod's Lua at once, a Nexus report's dump). Without sbslice.dll (it refused:
-- another game build) it is NotifyOnNewObject as before; tune.newObjectWatch = false watches nothing.
-- UE4SS's Lua can't make an object of an address, so sbslice leaves each one in an object property of the cheat
-- manager's default object (CheatManager's DebugCameraControllerRef, unused on a default object) for this to read
local M = {}
local ctx, log, try, valid
local CDO, FIELD_OWNER, FIELD = "/Script/SB.Default__SBCheatManager", "/Script/Engine.CheatManager", "DebugCameraControllerRef"
local PER_TICK = 200 -- at most this many a tick (a level's worth of widgets queued while she didn't tick)
local watchers = {} -- { path, fn, cls }
-- mode: nil till decided, "native" (sbslice), "lua" (NotifyOnNewObject), "off"
local st = { mode = nil, dirty = false, cdo = nil, statusAt = 0, dropped = 0 }

local function lua_watch(w)
  local ok, err = pcall(NotifyOnNewObject, w.path, w.fn)
  if not ok then log("NotifyOnNewObject " .. w.path .. " failed: " .. tostring(err)) end
end

-- the watched classes to sbslice: the field's address, a child/parent pair (its SuperStruct offset), the classes
local function setup()
  local g = ctx.gore
  local cdo = try(function() return StaticFindObject(CDO) end)
  local owner = try(function() return StaticFindObject(FIELD_OWNER) end)
  local child = valid(cdo) and try(function() return cdo:GetClass() end)
  local off
  if valid(owner) then
    try(function() owner:ForEachProperty(function(p) if p:GetFName():ToString() == FIELD then off = p:GetOffset_Internal() end end) end)
  end
  if not (valid(cdo) and valid(child) and off) then return "no " .. (not valid(cdo) and CDO or not off and FIELD or "cheat manager class") end
  local cls, missing = {}, {}
  for _, w in ipairs(watchers) do
    w.cls = w.cls or try(function() return StaticFindObject(w.path) end)
    if valid(w.cls) then cls[#cls + 1] = string.format("%x", w.cls:GetAddress()) else missing[#missing + 1] = w.path end
  end
  local r = g.command(string.format("O%x,%x,%x,%s", cdo:GetAddress() + off, child:GetAddress(), owner:GetAddress(), table.concat(cls, ",")))
  if not r:match("^ok") then return r end
  st.cdo = cdo
  log("watched as they are made (sbslice.dll): " .. r .. (#missing > 0 and ("; no class " .. table.concat(missing, ", ")) or ""))
  return nil
end

-- watch the objects of class path (and its subclasses) as they are made: fn(object) on her tick.
-- now: fn the moment it is made, through NotifyOnNewObject, for a class only ever made on the game thread (photo
-- mode's pawn: a native class, its default object made at boot, the pawn spawned as photo mode opens). Handed out on
-- her next tick, photo mode had already started on her and a cut-off head snapped back onto her neck (playtest)
function M.watch(path, fn, now)
  local w = { path = path, fn = fn }
  if now then
    if ctx.tune.newObjectWatch ~= false then lua_watch(w) end
    return
  end
  watchers[#watchers + 1] = w
  if st.mode == "lua" then lua_watch(w) elseif st.mode == "native" then st.dirty = true end
end

local function decide()
  if ctx.tune.newObjectWatch == false then
    st.mode = "off"
    log("not watched as they are made (newObjectWatch false): found with FindAllOf")
    return
  end
  local state = ctx.gore and ctx.gore.native_state and ctx.gore.native_state()
  if state ~= "ready" and state ~= "failed" then return end
  local err = "sbslice.dll " .. tostring(state)
  -- ("ue4ss": NotifyOnNewObject for all of them, as up to 0.5.0; UE4SS 3.1.0-6 only, the Nexus 1.3 build crashes on it)
  if ctx.tune.newObjectWatch == "ue4ss" then state, err = "asked", "newObjectWatch \"ue4ss\"" end
  if state == "ready" then err = setup() end
  if not err then st.mode = "native"; return end
  st.mode = "lua"
  log("watched as they are made by UE4SS's NotifyOnNewObject (" .. err .. ")")
  for _, w in ipairs(watchers) do lua_watch(w) end
end

-- her tick: the ones made since, to their watchers
function M.tick()
  if not st.mode then decide() end
  if st.mode ~= "native" or #watchers == 0 then return end
  if st.dirty then
    st.dirty = false
    local err = setup()
    if err then log("watch not changed: " .. err) end
  end
  local g = ctx.gore
  for _ = 1, PER_TICK do
    g.fire("O")
    local o = try(function() return st.cdo[FIELD] end)
    if not valid(o) then break end
    for _, w in ipairs(watchers) do
      if valid(w.cls) and try(function() return o:IsA(w.cls) end) then
        local ok, err = pcall(w.fn, o)
        if not ok then log("watch " .. w.path .. ": " .. tostring(err)) end
      end
    end
  end
  -- (a full queue drops the rest: told once a minute when it did)
  local now = os.clock()
  if now - st.statusAt >= 60 then
    st.statusAt = now
    local r = g.command("O?")
    local d = tonumber(r:match("(%d+) dropped") or "")
    if d and d > st.dropped then log("watch: " .. r); st.dropped = d end
  end
end

function M.mode() return st.mode end
-- objects of class path are handed out as they are made (its class found, the watch on)
function M.watched(path)
  if st.mode == "lua" then return true end
  if st.mode ~= "native" then return false end
  for _, w in ipairs(watchers) do if w.path == path and valid(w.cls) then return true end end
  return false
end

function M.init(c)
  ctx = c
  log = function(s) c.log("newobj: " .. s) end
  try, valid = c.try, c.valid
end

return M
