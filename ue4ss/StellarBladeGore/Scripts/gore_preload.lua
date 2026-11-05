-- Native rooted assets and asynchronous preload protocol.
return function(native, command, cfg, get_guards, log)
-- (load_obj's) an asset the cuts use, kept loaded for good once loaded (sbslice "o" roots it): nothing else held
-- them, so garbage collection freed them between deaths and every cut loaded the bone stub, the cap material, the
-- effects and the sounds again from the pak on the game thread (stubs 54 ms, bleeds 35, blood 24: twenty-fifth
-- playtest). Tried once a path; a refusal is logged
native.rooted = {}
function native.root(path, o)
  if native.rooted[path] ~= nil or native.state ~= "ready" then return end
  local r = command(string.format("o%x", type(o) == "number" and o or o:GetAddress()))
  native.rooted[path] = r:sub(1, 2) == "ok"
  if not native.rooted[path] then log("keeping " .. path .. " loaded refused: " .. r) end
end

-- the preloads loaded by the game's async loader (sbslice "J", tune.gore.asyncLoad): loaded on the game thread one a
-- look, the first blood effect held a frame 1.4 s and every sound 30 ms, a minute of stutters at the start (playtest).
-- Asked for, then found by path once in: loaded (no NeedLoad / NeedPostLoad, not async loading) on two looks in a row,
-- kept (native.root). One not in after ASYNC_S s is loaded as before. Off (as before) when the DLL hasn't the command or
-- the library's parameters aren't laid out as it builds them
native.async = { pending = {}, seen = {}, queue = {}, warm = {}, on = nil, asked = 0, got = 0, late = 0 }
-- Broken async deliveries (this build never delivers the pool materials) used to hold up their sync
-- fallback for the full 20 s; working assets arrive within a second, so 5 s is generous.
native.ASYNC_S = 5
-- MakeSoftObjectPath's PathString 0, ReturnValue 0x10 (0x28 in all); LoadAsset's WorldContextObject 0, Asset 8, OnLoaded
-- 0x30, LatentInfo 0x40 (0x58)
native.ASYNC_LAYOUT = "ok 0,16 size 40 / 0,8,48,64 size 88"
-- Conv_SoftObjectReferenceToObject's SoftObject 0, ReturnValue 0x28 (0x30 in all): how the asked-for assets are looked
-- for ("J=", sbslice's lookup through the engine's object hash). UE4SS's StaticFindObject walks every object comparing
-- names when what it looks for isn't there: four a poll for the assets still loading held the game thread ~100 ms
-- every third of a second for the first 20 s of every level (perf, playtest)
native.FIND_LAYOUT = "ok 0,40 size 48"
function native.async_ready()
  local try, valid = get_guards()
  local a = native.async
  if a.on ~= nil then return a.on end
  if native.state ~= "ready" then return false end
  if cfg().asyncLoad == false then a.on = false; return false end
  local why
  local cdo = try(function() return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end)
  local mk = try(function() return StaticFindObject("/Script/Engine.KismetSystemLibrary:MakeSoftObjectPath") end)
  local la = try(function() return StaticFindObject("/Script/Engine.KismetSystemLibrary:LoadAsset") end)
  if not (valid(cdo) and valid(mk) and valid(la)) then why = "the library's MakeSoftObjectPath / LoadAsset not found"
  else
    -- (UE4SS's Lua UFunction has no ForEachProperty: the DLL reads their parameters' offsets and sizes)
    local r = command(string.format("J?%x,%x", mk:GetAddress(), la:GetAddress()))
    if r ~= native.ASYNC_LAYOUT then why = "parameters laid out otherwise (" .. tostring(r) .. ")" end
  end
  a.on, a.cdo, a.mk, a.la = not why, cdo, mk, la
  log("async loads: " .. (why and ("off, " .. why .. ": loaded as before") or "on (the game's LoadAsset)"))
  if a.on then
    local cv = try(function() return StaticFindObject("/Script/Engine.KismetSystemLibrary:Conv_SoftObjectReferenceToObject") end)
    local r = valid(cv) and command(string.format("J?%x", cv:GetAddress()))
    a.conv = r == native.FIND_LAYOUT and cv or nil
    if not a.conv then log("async loads: looked for by UE4SS's StaticFindObject (" .. (valid(cv) and ("its parameters laid out otherwise: " .. tostring(r)) or "Conv_SoftObjectReferenceToObject not found") .. ")") end
  end
  return a.on
end
-- asked for: true, else nil (and the async loads off: a refusal means the DLL can't)
function native.async_load(path, world)
  local try, valid = get_guards()
  local a = native.async
  if not (a.on and valid(a.cdo) and valid(a.mk) and valid(a.la) and valid(world)) then return nil end
  local r = command(string.format("J%x,%x,%x,%x;%s", a.cdo:GetAddress(), a.mk:GetAddress(), a.la:GetAddress(),
    world:GetAddress(), path))
  if r:sub(1, 2) ~= "ok" then
    a.on = false
    log("async loads: off, asking for " .. path .. " refused (" .. r .. "): loaded as before")
    return nil
  end
  a.pending[path], a.asked = os.clock(), a.asked + 1
  a.queue[#a.queue + 1] = path
  return true
end
-- the ones asked for that are in now: kept; one past ASYNC_S handed back (true: load it as before)
function native.async_poll(budget)
  local try, valid = get_guards()
  local a, now, late = native.async, os.clock(), nil
  for _ = 1, math.min(budget, #a.queue) do
    local path = table.remove(a.queue, 1)
    local t = a.pending[path]
    local o, done
    if a.conv and valid(a.conv) then
      local r = command(string.format("J=%x,%x,%x;%s", a.cdo:GetAddress(), a.mk:GetAddress(), a.conv:GetAddress(), path))
      local at, d = r:match("^ok (%x+) ([01])$")
      o, done = at and tonumber(at, 16) or nil, d == "1"
      if not at then a.conv = nil; log("async loads: sbslice's lookup refused (" .. r .. "): looked for by StaticFindObject") end
    else
      o = try(function() return StaticFindObject(path) end)
      done = valid(o) and try(function() return o:HasAnyFlags(0x1400) end) == false
        and try(function() return o:HasAnyInternalFlags(0x08000000) end) == false
    end
    if done and a.seen[path] then
      a.pending[path], a.seen[path], a.got = nil, nil, a.got + 1
      native.root(path, o)
      -- Rooting by address does not create a Lua wrapper. Resolve and guard it on a separate quiet update,
      -- otherwise the first sound/effect still pays StaticFindObject's full lookup during the cut.
      a.warm[#a.warm + 1] = path
      if a.got <= 3 or now - t > 5 then log(string.format("async loads: %s in after %.1f s", path, now - t)) end
    elseif done then a.seen[path] = true
    elseif now - t > native.ASYNC_S then
      a.pending[path], a.seen[path], a.late = nil, nil, a.late + 1
      log(string.format("async loads: %s not in after %d s: loaded as before", path, native.ASYNC_S))
      late = late or {}
      late[#late + 1] = path
    end
    if a.pending[path] then a.queue[#a.queue + 1] = path end
  end
  return late
end

end
