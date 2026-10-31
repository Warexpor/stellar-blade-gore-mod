-- Experimental Blood and Dirt: the game's existing skin layer, driven through Eve's Blueprint values and
-- MPC_PCDirtyOffset. No material replacements, masks, render targets, outfit paint or extra wound effects.
local M = {}
local ctx, try, valid, log
local MPC = "/Game/Art/FX/MPC/MPC_PCDirtyOffset.MPC_PCDirtyOffset"
local KML = "/Script/Engine.Default__KismetMaterialLibrary"
local st = { pawn = 0, blood = 0, dirt = 0, goalB = 0, goalD = 0, others = {}, next = 0 }
function M.init(c)
  ctx, try, valid = c, c.try, c.valid
  log = function(s) c.log("stains: " .. s) end
end
local function cfg() return ctx.tune.stains or {} end
local function on() return cfg().enabled == true and (ctx.tune.gore or {}).enabled ~= false end
local function number(x, default, lo, hi)
  x = tonumber(x)
  if not x or x ~= x or x == math.huge or x == -math.huge then x = default end
  return math.max(lo, math.min(hi, x))
end
local function dist(a, b)
  local x, y, z = a.X - b.X, a.Y - b.Y, a.Z - b.Z
  return math.sqrt(x*x + y*y + z*z)
end
local function point(v) return v and { X = v.X, Y = v.Y, Z = v.Z } end
local function obj(path)
  local o = try(function() return StaticFindObject(path) end)
  return valid(o) and o or nil
end
local function approach(x, target, step)
  return x < target and math.min(target, x + step) or math.max(target, x - step)
end
local function write(pawn, now)
  -- Libraries/collection belong to this world; dropped without querying them when the pawn changes.
  if not st.kml or not st.mpc then
    if now >= (st.retry or 0) then
      st.retry = now + 1
      st.kml, st.mpc = obj(KML), obj(MPC)
    end
  end
  try(function() pawn.BloodValue = st.blood; pawn.DirtValue = st.dirt end)
  if st.kml and st.mpc then
    try(function() st.kml:SetScalarParameterValue(pawn, st.mpc, FName("BloodOffset"), st.blood) end)
    try(function() st.kml:SetScalarParameterValue(pawn, st.mpc, FName("DirtOffset"), st.dirt) end)
  end
end
function M.add(blood, dirt, why)
  if not on() then return end
  local mx = number(cfg().max, 1, 0, 1)
  st.goalB = number(st.goalB + number(blood, 0, -1, 1), 0, 0, mx)
  st.goalD = number(st.goalD + number(dirt, 0, -1, 1), 0, 0, mx)
  if why then log(string.format("%s: target blood %.3f dirt %.3f", why, st.goalB, st.goalD)) end
end
function M.clean_all(why)
  local had = st.goalB > 0 or st.goalD > 0
  st.goalB, st.goalD = 0, 0
  if had then log("cleaning: " .. tostring(why or "?")) end
end
function M.splash(at, kind)
  local c = cfg().splash or {}
  if not on() or c.enabled == false or st.dead or not st.her or not at then return end
  local range = number(c.range, 1000, 1, 5000)
  local d = dist(at, st.her)
  if d >= range then return end
  local amount = number(kind == "cut" and c.cut or c.amount, kind == "cut" and 0.12 or 0.06, 0, 1)
  M.add(amount * (1 - d / range) * number(cfg().scale, 1, 0, 3), 0,
    ctx.tune.verboseLog and string.format("enemy %s %.0f cm away", kind, d) or nil)
end
local function health(now)
  local gl, c = ctx.glass, cfg()
  -- The shared lethal/HP watches discover the HUD; do not trigger another global widget search here.
  local pct = gl and gl.bar_pct(true)
  if type(pct) ~= "number" or pct ~= pct or pct < 0 or pct > 1 then return end
  local old = st.pct
  -- Keep the reference until tiny changes accumulate; otherwise slow regeneration would be lost each tick.
  if old and math.abs(pct - old) <= 0.00001 and pct ~= 1 then return end
  st.pct = pct
  if not old then return end
  if pct < old - 0.00001 then
    local hc = c.hit or {}
    local drop = old - pct
    -- The HUD may animate one blow over several ticks: its base amount is added once.
    local base = now - (st.dropT or -100) > 0.4 and number(hc.base, 0.04, 0, 1) or 0
    st.dropT = now
    M.add((base + number(hc.perHp, 0.9, 0, 3) * drop) * number(c.scale, 1, 0, 3), 0, "HP lost")
  elseif pct > old and (c.heal or {}).enabled ~= false then
    -- Heal the same share of the stains as the share of missing HP recovered. A full heal clears the target;
    -- the visible native offsets still fade toward it, rather than popping off on the heal's frame.
    local share = pct == 1 and 1 or math.min(1, (pct - old) / math.max(1 - old, 0.00001))
    st.goalB, st.goalD = st.goalB * (1 - share), st.goalD * (1 - share)
    if ctx.tune.verboseLog then log(string.format("healed: %.0f%% of remaining stains washed away", share * 100)) end
  end
end
local function vector_key(v)
  return v and string.format("%.3f,%.3f,%.3f", v.X, v.Y, v.Z) or "?"
end
local function near_hits(pawn)
  local c = cfg().splash or {}
  if c.enabled == false or not ctx.live_chars then return end
  local range, chars = number(c.range, 1000, 1, 5000), ctx.live_chars()
  -- Bound engine property reads in crowded areas; finish one pass before discarding absent actors.
  local total = #chars
  local i = math.min(st.hitIndex or 1, math.max(total, 1))
  local seen = st.hitSeen or {}
  local count = math.min(total, 8)
  for _ = 1, count do
    local e = chars[i]
    if e.addr ~= st.pawn then
      local p = ctx.char_at(e)
      if p and st.her and dist(p, st.her) < range + 250 then
        local m = try(function() return e.obj.Mesh end)
        if valid(m) then
          local at = try(function() return point(m.PhysicalHitForceLocation) end)
          local force = try(function() return point(m.PhysicalHitForceVector) end)
          local shake = try(function() return point(m.VertexShakeInfo.ShakeHitPosition) end)
          local dir = try(function() return point(m.VertexShakeInfo.ShakeHitDirection) end)
          local key = vector_key(at) .. "/" .. vector_key(force) .. "/" .. vector_key(shake) .. "/" .. vector_key(dir)
          seen[e.addr] = true
          local old = st.others[e.addr]
          st.others[e.addr] = key
          if old and key ~= old and at and dist(at, p) < 250 then M.splash(at, "hit") end
        end
      end
    end
    i = i + 1
    if i > total then
      for a in pairs(st.others) do if not seen[a] then st.others[a] = nil end end
      seen, i = {}, 1
    end
  end
  if total == 0 then st.others, seen, i = {}, {}, 1 end
  st.hitIndex, st.hitSeen = i, seen
end
local function moves(pawn, dead, now, dt)
  local c, dc = cfg(), cfg().dirt or {}
  local cm = try(function() return pawn.CharacterMovement end)
  local mm = valid(cm) and try(function() return cm.MovementMode end)
  local vz = valid(cm) and try(function() return cm.Velocity.Z end) or 0
  if not dead then
    if mm == 3 then st.minVz = math.min(st.minVz or 0, vz)
    else
      if st.mm == 3 and (mm == 1 or mm == 2) and dc.enabled ~= false then
        local need = number(dc.landSpeed, 900, 1, 10000)
        local speed = -(st.minVz or 0)
        if speed > need then M.add(0, number(dc.land, 0.15, 0, 1) * number((speed - need) / need + 0.5, 0.5, 0.5, 1.5), "hard landing") end
      end
      st.minVz = 0
    end
    local stance = try(function() return pawn:GetCurrentStanceName():ToString() end) or ""
    local down = stance:find("Down", 1, true) or stance:find("Tumbl", 1, true)
    if down and not st.down and dc.enabled ~= false then M.add(0, number(dc.knock, 0.12, 0, 1), "knocked down") end
    st.down = down
    if c.rest ~= false and mm == 0 and (st.goalB > 0 or st.goalD > 0) and ctx.rest_seq and try(function() return pawn:IsBattle() end) ~= true then
      if now >= (st.seatNext or 0) then
        st.seatNext = now + 5
        local rested, seq = ctx.rest_seq()
        local chair = false
        for _, n in ipairs(seq or {}) do if n == "Interaction_Camp_Chair" or n == "Interaction_Camp_Chair_End" then chair = true end end
        if rested or chair then M.clean_all("camp rest") end
      end
    else st.seatNext = nil end
  end
  st.mm = mm
  if mm == 4 and (c.wash or {}).enabled ~= false then
    local r = number((c.wash or {}).rate, 0.35, 0, 3) * dt
    st.goalB, st.goalD = math.max(0, st.goalB - r), math.max(0, st.goalD - r)
  end
  if dead and mm ~= 4 and dc.enabled ~= false and now - (st.deadAt or now) > 1.5 then
    local limit = number(dc.death, 0.6, 0, 1)
    if st.goalD < limit then st.goalD = math.min(limit, st.goalD + number(dc.rate, 0.08, 0, 1) * dt) end
  end
end
function M.tick(pawn, mesh, dead)
  if not valid(pawn) then return end
  local pa = try(function() return pawn:GetAddress() end)
  local now = os.clock()
  if pa ~= st.pawn then
    -- Old world objects may already be freed: no IsValid/material restore on the previous pawn or libraries.
    st.pawn, st.pct, st.blood, st.dirt, st.goalB, st.goalD = pa, nil, 0, 0, 0, 0
    st.others, st.kml, st.mpc, st.retry, st.next, st.last = {}, nil, nil, 0, 0, now
    st.hitIndex, st.hitSeen, st.writtenB, st.writtenD = nil, nil, nil, nil
    st.active, st.dead, st.deadAt, st.mm, st.minVz, st.down, st.dropT, st.seatNext = false, false, nil, nil, 0, nil, nil, nil
  end
  if now < st.next then return end
  st.next = now + 0.1
  local dt = number(now - (st.last or now), 0, 0, 0.25)
  st.last = now
  if not on() then
    -- Off never owns the collection. Only a transition out of the enabled feature clears its own values.
    if st.active then
      st.blood, st.dirt, st.goalB, st.goalD = 0, 0, 0, 0
      write(pawn, now)
      st.active = false
      st.writtenB, st.writtenD = nil, nil
    end
    st.pct, st.others, st.hitIndex, st.hitSeen = nil, {}, nil, nil
    return
  end
  if not st.active then st.active = true; st.pct = nil end
  st.her = try(function() return point(pawn:K2_GetActorLocation()) end)
  if dead and not st.dead then st.deadAt = now
  elseif not dead and st.dead then
    M.clean_all("next life")
    st.pct, st.blood, st.dirt = nil, 0, 0
    st.writtenB, st.writtenD = nil, nil
  end
  st.dead = dead == true
  local start = os.clock()
  health(now)
  local hpTime = os.clock()
  if not dead then near_hits(pawn) end
  local hitsTime = os.clock()
  moves(pawn, dead, now, dt)
  local movesTime = os.clock()
  local fade = number(cfg().fade, 0, 0, 120)
  if fade > 0 then
    local r = dt / (fade * 60)
    st.goalB, st.goalD = math.max(0, st.goalB - r), math.max(0, st.goalD - r)
  end
  local up = number(cfg().rise, 0.6, 0.01, 5) * dt
  local down = number(cfg().clearRate, 0.35, 0.01, 5) * dt
  st.blood = approach(st.blood, st.goalB, st.goalB > st.blood and up or down)
  st.dirt = approach(st.dirt, st.goalD, st.goalD > st.dirt and up or down)
  local bpBlood = try(function() return pawn.BloodValue end)
  local bpDirt = try(function() return pawn.DirtValue end)
  if st.writtenB ~= st.blood or st.writtenD ~= st.dirt or bpBlood ~= st.blood or bpDirt ~= st.dirt then
    write(pawn, now)
    if st.kml and st.mpc then st.writtenB, st.writtenD = st.blood, st.dirt end
  end
  local finish = os.clock()
  if (finish - start) * 1000 >= ((ctx.tune.gore or {}).slowMs or 15) then
    log(string.format("slow update: %.0f ms (HP %.0f, nearby hits %.0f, movement/rest %.0f, write %.0f)",
      (finish-start)*1000, (hpTime-start)*1000, (hitsTime-hpTime)*1000,
      (movesTime-hitsTime)*1000, (finish-movesTime)*1000))
  end
end
function M.test_blood() M.add(0.25, 0, "menu: Add Blood") end
function M.test_dirt() M.add(0, 0.25, "menu: Add Dirt") end
function M.clean() M.clean_all("menu: Clean Her") end
function M.forget()
  -- Called with the other world caches, including when a new pawn reuses the old pawn's address.
  st.pawn, st.blood, st.dirt, st.goalB, st.goalD = 0, 0, 0, 0, 0
  st.others, st.kml, st.mpc, st.next, st.active, st.pct = {}, nil, nil, 0, false, nil
  st.hitIndex, st.hitSeen, st.writtenB, st.writtenD = nil, nil, nil, nil
end
M._st = st
return M
