-- Floor blood decals, trackers, scheduling and cleanup.
return function(M, enemy, cfg, load_obj, get_guards, get_lists, set_pools, set_no_decals,
  log, vec, add, sub, scale, len, pick, floor_at, pool_radius, addr, bone_loc, POOL_DECALS, DRIP_DECALS, TICK_S)
local function floor_decal(pawn, p, r, list, life, knownAt, knownNormal)
  local try, valid = get_guards()
  local t0 = os.clock()
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  local km = load_obj("/Script/Engine.Default__KismetMathLibrary")
  local mat = M.guarded_asset(pick(list))
  if not (gs and km and mat) then return nil end
  local loaded = os.clock()
  local at, n = knownAt, knownNormal
  if not at then at, n = floor_at(pawn, p) end
  local t1 = os.clock()
  -- the decal projects along its X: into the floor, turned at random about it
  local rot = try(function() return km:MakeRotFromX(scale(n, -1)) end)
  rot = rot and { Pitch = rot.Pitch, Yaw = rot.Yaw, Roll = math.random() * 360 } or { Pitch = -90, Yaw = 0, Roll = math.random() * 360 }
  local d = try(function() return gs:SpawnDecalAtLocation(pawn, mat, vec(8, 1, 1), at, rot, life or 0) end)
  local t2 = os.clock()
  if valid(d) then try(function() d:SetWorldScale3D(vec(1, r, r)) end) end
  -- (each pool or drip pass held a frame 9-14 ms in 0.4.x, playtest: which part)
  local ms = (os.clock() - t0) * 1000
  if ms >= (cfg().slowMs or 15) * 0.5 then
    log(string.format("floor decal took %.1f ms: lookup %.1f, trace %.1f, spawn %.1f, scale %.1f", ms,
      (loaded - t0) * 1000, (t1 - loaded) * 1000, (t2 - t1) * 1000, (os.clock() - t2) * 1000))
  end
  if not valid(d) then return nil end
  -- (one with a life of its own goes by itself, kept off the list and its cap)
  if not life then local _, _, decals = get_lists(); decals[#decals + 1] = d end
  return { d = d, at = at, n = n, r = r }
end

-- at the cap (maxDecals): the oldest drip goes for the new one, a pool only when no drip is left (the oldest no
-- opening still spreads; a moving arm stump's drips had filled the old cap of 60 and the death got no pools). Refused at the
-- cap, a limb cut off her alive (Lose Arm at Low HP) dripped 58 times as she fought on, and her death a minute later
-- left no blood on the floor at all (playtest). (Not a local: the chunk is at Lua's 200)
function M.decal_room(max)
  local try, valid = get_guards()
  local _, trackers, decals = get_lists()
  if #decals < max then return true end
  local live = {}
  for _, k in ipairs(trackers) do if k.pool and k.pool.d then live[k.pool.d] = true end end
  for i, d in ipairs(decals) do
    if M.drips[d] and not M.burstDots[d] then
      table.remove(decals, i)
      M.drips[d] = nil
      if valid(d) then try(function() d:K2_DestroyComponent(d) end) end
      return true
    end
  end
  for i, d in ipairs(decals) do
    if not live[d] and not M.burstDots[d] then
      table.remove(decals, i)
      if valid(d) then try(function() d:K2_DestroyComponent(d) end) end
      return true
    end
  end
  return false
end

-- Niagara's GPU particles do not expose their individual landing positions to Lua.
-- Place small persistent approximations around each spurt, using real floor traces.
-- Each trace/spawn is scheduled independently on an impact-work frame.
function M.queue_burst_dots(pawn, source)
  local try, valid = get_guards()
  if not (valid(pawn) and valid(source)) then return end
  local later = get_lists()
  for _ = 1, 2 do
    later[#later + 1] = { n = 1, label = "burst ground spot", fn = function()
      local try, valid = get_guards()
      local _, _, decals = get_lists()
      local g = cfg()
      if g.blood == false or g.pool == false or not valid(pawn) or not valid(source)
        or #decals >= (g.maxDecals or 60) then return end
      local p = try(function() local v = source:K2_GetComponentLocation(); return vec(v.X, v.Y, v.Z) end)
      if not p then return end
      local angle, radius = math.random() * 2 * math.pi, 12 + math.random() * 55
      local at = add(p, vec(math.cos(angle) * radius, math.sin(angle) * radius, 0))
      local hit, floor, normal = M.pool_trace(pawn, add(at, vec(0, 0, 20)), add(at, vec(0, 0, -400)))
      if not hit or not floor or not normal or normal.Z < 0.5 then return end
      local spot = floor_decal(pawn, at, 1 + math.random() * 2, DRIP_DECALS, nil, floor, normal)
      if spot and valid(spot.d) then M.burstDots[spot.d] = true end
    end }
  end
end

-- the splat under a cut or a hit: a splash of the pools' blood on the floor under `at`, kept off walls as they are.
-- The game's splat effect (NS_Hit_Flesh_Decal_Strong_01) put its own blood decal down (MI_ParBloodDecal_01, coloured
-- by its particles), a brighter red than the pools (playtest). life: s it stays (a hit she lives through; 0: till
-- she is up again, with the pools)
function M.splat(pawn, at, life)
  if not at then return end
  local g = cfg()
  if not life and not M.decal_room(g.maxDecals or 60) then return end
  local r = (g.splatSize or 14) * (0.75 + math.random() * 0.5)
  local f, n = floor_at(pawn, at)
  if f then r = math.min(r, M.wall_room(pawn, f, n, r)) end
  floor_decal(pawn, at, r, POOL_DECALS, life, f, n)
end

-- a pool under her would stain her skin: her meshes take no decals while it is down and she lies in it. Not while
-- she plays (M.decals_back): an arm lost alive kept her body from every decal till it grew back, the game's own too
-- (Nexus report: Altess Levoire's Purification Scanner grid, decals projected on her, only on her head and neck, the
-- face mesh; the hit marks' slashes too)
local function shield(comp)
  local try, valid = get_guards()
  if not valid(comp) then return end
  local _, _, _, no_decals = get_lists()
  local a = addr(comp)
  for _, e in ipairs(no_decals) do if e.addr == a then return end end
  local was = try(function() return comp.bReceivesDecals end)
  if was == false then return end
  no_decals[#no_decals + 1] = { comp = comp, addr = a, was = was }
  try(function() comp:SetReceivesDecals(false) end)
end

-- follow one opening: where(t) gives its live position (nil once it is gone)
local function track(pawn, where, bone, comp, radius, noDrips)
  local g = cfg()
  if g.blood == false or g.pool == false then return end
  shield(comp)
  M.poolSerial = (M.poolSerial or 0) + 1
  local entry = { pawn = pawn, where = where, rmax = (radius or pool_radius(bone)) * (g.poolScale or 1), t = 0,
    still = 0, bone = tostring(bone), noDrips = noDrips, slot = M.poolSerial % 3, sampled = 0 }
  -- Chunk trackers are inserted at the front, so enemy.run's append-only scan cannot tag them.
  -- Record ownership here before insertion; recovery and enemy cleanup use the same tag.
  enemy.owned[entry] = enemy.cur or false
  local _, trackers = get_lists()
  -- The reverse-order spawn budget must service body openings before the many smash chunks.
  if bone == "smash chunk" then table.insert(trackers, 1, entry) else trackers[#trackers + 1] = entry end
end
local function track_opening(q, cap_actor, o, comp, bone)
  local try, valid = get_guards()
  local root = valid(cap_actor) and try(function() return cap_actor:K2_GetRootComponent() end)
  track(q.pawn, function()
    local try, valid = get_guards()
    if valid(root) then return try(function() local l = root:K2_GetComponentLocation(); return vec(l.X, l.Y, l.Z) end) end
    local l = valid(comp) and bone_loc(comp, bone)
    return l and vec(l.X, l.Y, l.Z) or nil
  end, bone, comp, (q.bone == "Bip001-Head" and bone == q.parent) and 110 or nil)
end

local POOL_EVERY = 3 -- ticks between updates (0.1 s); a pool's size follows every tick (pool_grow)
local pool_n = 0
-- every pool's size, every tick, up to the last ring the floor checks held (grown every 0.1 s and only up to each
-- ring as it was checked, it spread in steps, a new stain put down a size larger each time, Nexus report). (On M:
-- gore.lua is at Lua's 200 locals)
function M.pool_grow()
  local now = os.clock()
  local dt = M.poolClock and math.min(now - M.poolClock, 0.1) or 0
  M.poolClock = now
  if dt <= 0 then return end
  local try, valid = get_guards()
  local _, trackers = get_lists()
  local poolGrow = cfg().poolGrow or 5
  -- (pure Lua but for the one resize a pool due one: a pool still growing was looked up and resized each tick, but
  -- under 0.15 cm nothing is set, so a slow one is set every few ticks, a stopped one never)
  for _, k in ipairs(trackers) do
    local q = k.pool
    if q and q.ok then
      -- small chunk pools develop in seconds while body pools spread slowly
      local grow = k.grow or poolGrow
      -- Do not accumulate growth while blocked by pending geometry checks. Otherwise the
      -- first cleared ring releases a backlog of growth in one visible jump.
      local rm = math.min(k.rmax, q.rmax or k.rmax)
      q.age = q.age + dt
      if rm > 4 and q.ok < rm then
        local fraction = math.max(0, math.min((q.ok - 4) / (rm - 4), 0.999999))
        q.age = math.min(q.age, -grow * math.log(1 - fraction))
      end
      -- fast at first, slowing down: 63 % of the way after poolGrow s
      local r = math.min(4 + (rm - 4) * (1 - math.exp(-q.age / grow)), q.ok)
      if r - q.r > 0.15 and valid(q.d) then
        q.r = r
        try(function() q.d:SetWorldScale3D(vec(1, r, r)) end)
      end
    end
  end
end
local function pools_tick()
  local _, trackers = get_lists()
  if #trackers == 0 then M.poolClock = nil; return end
  local _, valid = get_guards()
  local profStart = os.clock()
  M.pool_grow()
  _, trackers = get_lists()
  local profGrow = os.clock()
  pool_n = pool_n + 1
  if pool_n % POOL_EVERY ~= 0 then return end
  local g = cfg()
  local dt = TICK_S * POOL_EVERY
  local life, grow, every = g.poolTime or 12, g.poolGrow or 5, g.dripEvery or 18
  local maxDecals = g.maxDecals or 60
  -- a floor trace and a spawn each run about a millisecond once the material is rooted, so up to four
  -- openings' pools or drips start on a pass (a 64-chunk death reads as a spreading wave, not a drip feed);
  -- unrooted first finds still hitch, which the preload order and wound pre-request keep off the death
  local budget = 4
  for i = #trackers, 1, -1 do
    local k = trackers[i]
    k.t = k.t + dt
    if k.t > life then
      log(string.format("floor blood from %s: %d drips, %d pools, last %.0f cm across", k.bone, k.drips or 0,
        k.pools or 0, k.pool and k.pool.r * 2 or 0))
      table.remove(trackers, i)
    elseif k.slot == (pool_n / POOL_EVERY) % 3 then
      local elapsed = math.max(k.t - k.sampled, dt)
      k.sampled = k.t
      local p = k.where()
      if not p then table.remove(trackers, i)
      else
      local moved = k.last and len(sub(p, k.last)) or 0
      k.last = p
      local speed = moved / elapsed
      if speed < 25 then k.still = k.still + elapsed else k.still = 0 end
      if k.pool then
        local off = len(vec(p.X - k.pool.at.X, p.Y - k.pool.at.Y, 0))
        if off > math.max(k.pool.r * 0.6, 15) then k.pool = nil end
      end
      if not k.pool and k.still >= 0.2 and budget > 0 and M.decal_room(maxDecals) then
        -- it came to rest: a pool starts under it
        budget = budget - 1
        k.pool = floor_decal(k.pawn, p, 4, POOL_DECALS)
        if k.pool then
          k.pool.age, k.pools = 0, (k.pools or 0) + 1
          k.pool.ok = 4
          k.pool.check = { kind = "wall", i = 0, room = k.rmax }
          if k.bone == "smash chunk" then
            -- the meat sits on its own pool: start it at a visible size and develop it fast (pool_grow
            -- clamps the head start back to what the checks held)
            local rm = math.min(k.rmax, k.pool.rmax or k.rmax)
            if rm > 4 then
              k.grow = math.min(grow, 3)
              k.pool.ok, k.pool.age = 4 + (rm - 4) * 0.35, k.grow * 0.43
            end
          end
        end
      elseif not k.pool and not k.noDrips and speed >= 25 and budget > 0 then
        -- on the move: drips every so often
        if (not k.drop or len(sub(p, k.drop)) >= every) and M.decal_room(maxDecals) then
          budget = budget - 1
          k.drop = p
          local dr = floor_decal(k.pawn, p, 2.5 + math.random() * 4, DRIP_DECALS)
          if dr and dr.d then M.drips[dr.d] = true end
          k.drips = (k.drips or 0) + 1
        end
      end
      if k.pool and valid(k.pool.d) then
        local rm = math.min(k.rmax, k.pool.rmax or k.rmax)
        local r = 4 + (rm - 4) * (1 - math.exp(-k.pool.age / grow))
        -- the next ring checked a ring before it grows into it, so the floor checks stay ahead of its spread (one ring a
        -- pass, every pool's together under ringBudget); pool_grow sizes it every tick up to the last that held
        k.pool.ok = k.pool.ok or 4
        if r + 6 > k.pool.ok and k.pool.ok < rm and not k.pool.stopped and not k.pool.check then
          k.pool.check = { kind = "ring", i = 0, ring = math.min(k.pool.ok + 6, rm) }
        end
      end
      end
    end
  end
  local profTrack = os.clock()
  -- Round-robin keeps many simultaneous wounds from monopolising the trace budget.
  local count = #trackers
  if count > 0 then
    local start = (M.poolCheckCursor or 0) % count
    for offset = 1, count do
      local index = (start + offset - 1) % count + 1
      local k = trackers[index]
      if k.pool and k.pool.check and valid(k.pool.d) then
        M.pool_check_step(k, 4)
        M.poolCheckCursor = index
        break
      end
    end
  end
  local profEnd = os.clock()
  if (profEnd - profStart) * 1000 >= (cfg().slowMs or 15) * 0.7 then
    log(string.format("floor pools detail: %.1f ms: grow %.1f, tracking/decal %.1f, checks %.1f; %d trackers",
      (profEnd - profStart) * 1000, (profGrow - profStart) * 1000,
      (profTrack - profGrow) * 1000, (profEnd - profTrack) * 1000, count))
  end
end

-- she plays (alive, main.lua's watch): her meshes take decals again. How many
function M.decals_back(why)
  local try, valid = get_guards()
  local _, _, _, no_decals = get_lists()
  if #no_decals == 0 then return 0 end
  local n = 0
  for _, e in ipairs(no_decals) do
    if valid(e.comp) and addr(e.comp) == e.addr and try(function() e.comp:SetReceivesDecals(e.was ~= false); return true end) then n = n + 1 end
  end
  set_no_decals({})
  log(string.format("her meshes take decals again (%s): %d", why, n))
  return n
end

local function pools_clear()
  local try, valid = get_guards()
  local _, _, decals, no_decals = get_lists()
  local n = 0
  for _, d in ipairs(decals) do if valid(d) then try(function() d:K2_DestroyComponent(d) end); n = n + 1 end end
  set_pools({}, {})
  M.drips = {}
  for _, e in ipairs(no_decals) do
    if valid(e.comp) and addr(e.comp) == e.addr then try(function() e.comp:SetReceivesDecals(e.was ~= false) end) end
  end
  set_no_decals({})
  return n
end

return shield, track, track_opening, pools_tick, pools_clear
end
