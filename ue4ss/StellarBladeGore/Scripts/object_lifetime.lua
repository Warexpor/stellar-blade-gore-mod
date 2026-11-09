-- Frame-scoped guards for Unreal objects retained between callbacks.
return function(goreCtx, try, valid, log, get_tune)
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
-- the poll cycle her watches, the enemies' part and the poll share: advanced once per poll window in game_tick
-- (below), so the character list below is walked once per poll instead of once per phase. Held-object lifetime
-- checks intentionally stay on the per-frame epoch above: the engine runs between phases and can free actors there.
goreCtx.poll = 0
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
function goreCtx.alive(k, single)
  if not k then return false end
  if k.dead then return false end
  if k.frame == goreCtx.frame then return k.alive end
  if not k.idx then
    if os.clock() - k.t > (get_tune().keepFresh or 2) then k.dead, k.stale = true, true; return false end
    if not goreCtx.alive_ask({ k }) then return nil end
    if not k.alive then k.dead = true; return false end
    k.asked, k.listed = os.clock(), true
    goreCtx.heldList[#goreCtx.heldList + 1] = k
    return true
  end
  if single then
    if not goreCtx.alive_ask({ k }) then return nil end
    if not k.alive then k.dead = true; return false end
    if not k.listed then k.listed = true; goreCtx.heldList[#goreCtx.heldList + 1] = k end
    k.asked = os.clock()
    return true
  end
  local keep, now = {}, os.clock()
  for _, x in ipairs(goreCtx.heldList) do
    if not x.dead and (x == k or now - (x.asked or now) < 3) then keep[#keep + 1] = x else x.listed = nil end
  end
  if not k.listed then k.listed = true; keep[#keep + 1] = k end
  goreCtx.heldList = keep
  for i = 1, #keep, 64 do
    local part = { table.unpack(keep, i, math.min(i + 63, #keep)) }
    if not goreCtx.alive_ask(part) then return nil end
  end
  for _, x in ipairs(keep) do if x.frame == goreCtx.frame and not x.alive then x.dead = true end end
  k.asked = now
  return k.alive
end
function goreCtx.held(k, single)
  if not k then return false end
  if k.dead then return false end
  if k.frame == goreCtx.frame then k.asked = os.clock(); return k.alive and valid(k.obj) end
  if not k.idx then
    -- its index is read off it now, while it is surely alive
    if os.clock() - k.t > (get_tune().keepFresh or 2) then k.dead, k.stale = true, true; return false end
    if not goreCtx.alive_ask({ k }) then return false end
    if not k.alive then k.dead = true; return false end
    k.asked, k.listed = os.clock(), true
    goreCtx.heldList[#goreCtx.heldList + 1] = k
    return valid(k.obj)
  end
  -- A frequently polled widget can be the first object checked in a frame.
  -- Validate just that widget instead of making it pay for the full shared
  -- list; other callers may still batch the remaining objects as usual.
  if single then
    if not goreCtx.alive_ask({ k }) then return false end
    if not k.alive then k.dead = true; return false end
    if not k.listed then k.listed = true; goreCtx.heldList[#goreCtx.heldList + 1] = k end
    k.asked = os.clock()
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
end
