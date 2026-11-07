-- Follow-up attacks and projectile dispatch after death.
return function(sw, ah, goreCtx, get_tune, get_gore, get_swing, try, vof, len, dist, sub, dot, cross, unit, log)
-- the game's seconds per real one for motion: trail speeds divide by real time, so under slow motion they
-- read slow and every follow-up is let go as too slow. Scale by the clock as it runs
local function game_scale()
  local s = 1
  try(function() s = goreCtx.time_scale and goreCtx.time_scale() or 1 end)
  return (s and s > 0) and s or 1
end
-- Fresh steps from one enemy; blade meshes take priority over fallback bones. A fast miss must not hide a
-- slower crossing by its other blade or a packmate. Every candidate still passes the same blow/contact gates.
function sw.after_steps(S, g)
  local hist = S.hist
  if not (S.bones or S.weapons) or #hist < 2 or os.clock() - hist[#hist].t > 0.2 then return {} end
  local a, b = hist[#hist - 1], hist[#hist]
  local realDt = b.t - a.t
  if realDt < 1e-3 then return {} end
  local dt = realDt * game_scale()
  local bones, blades = {}, {}
  for i = 1, #(S.bones or {}) do
    local p, q = a.p[i], b.p[i]
    if p and q then
      local v = dist(p, q) / dt
      bones[#bones + 1] = { v = v, i = i, p = p, q = q, name = S.bones[i] }
    end
  end
  for k, e in pairs(b.w or {}) do
    local o = a.w and a.w[k]
    if o then
      local v = math.max(dist(o.a, e.a), dist(o.b, e.b)) / dt
      if v >= (g.swingMinSpeed or 300) then
        local w = S.weapons and S.weapons[k]
        local mid = function(x) return { X = (x.a.X + x.b.X) / 2, Y = (x.a.Y + x.b.Y) / 2, Z = (x.a.Z + x.b.Z) / 2 } end
        local far = dist(o.b, e.b) >= dist(o.a, e.a)
        blades[#blades + 1] = { v = v, p = far and o.b or o.a, q = far and e.b or e.a, name = w and w.name or "weapon",
          steps = { { o.a, e.a }, { mid(o), mid(e) }, { o.b, e.b } }, blade = unit(sub(e.b, e.a)) }
      end
    end
  end
  local steps = #blades > 0 and blades or bones
  table.sort(steps, function(x, y) return x.v > y.v end)
  return steps
end
function sw.after_step(S, g)
  return sw.after_steps(S, g)[1]
end
local function hit_step(pawn, mesh, S, best, g, c, gore)
  local hist = S.hist
  if ah.blunt or os.clock() - ah.t0 < (c.from or 0.6) then
    -- (the killing swing's own follow-through, and a blunt-ragdoll death: never a hit. Told once a death: a second
    -- hit right after it that cut nothing left no line at all, playtest)
    if best and not ah.blunt and not ah.toldSoon then
      ah.toldSoon = true
      log(string.format("after death: %s's %s at %.0f cm/s %.1f s in: too soon after the death, not a hit",
        tostring(S.who), best.name, best.v, os.clock() - ah.t0))
    end
    return
  end
  -- (why a blow that came in was let go, told once a swing: a second hit after death that cut nothing left no line
  -- at all, playtest)
  -- (armed again once its weapon slowed down, or rearm s after its last cut: a combo's next blow came with the
  -- hands never slowing in between, and a second hit right after her death cut nothing, playtest)
  local addr = S.addr or 0
  if not ah.armedBy[addr] and os.clock() - (ah.lastBy[addr] or ah.t0) >= (c.rearm or 0.35) then ah.armedBy[addr] = true end
  local gate = not ah.armedBy[addr] and "its weapon not slowed since the last"
    or (c.max and ah.n >= c.max) and string.format("%d hits already", ah.n)
    or gore.busy() and "a cut still being made"
  if gate and (best.v < (c.minSpeed or 500) or ah.gated == best.q) then
    -- (slow or already reported: told, capped, like the gate below. A gated hit at her that cut nothing left no line
    -- at all, playtest)
    if (best.q == nil or ah.gated ~= best.q) and (ah.brushes or 0) < 6 then
      ah.brushes = (ah.brushes or 0) + 1
      if best.q then ah.gated = best.q end
      log(string.format("after death: %s's %s at %.0f cm/s: not cut, %s", tostring(S.who), best.name, best.v, gate))
    end
    return
  end
  local cfgReach = best.steps and (c.reach or 25) or (c.handReach or 40)
  -- a part already cut off her is no target (after a beheading her head flies off: a swing at her body must read the
  -- torso, never the severed head)
  local cut = gore.already_cut and function(b)
    local ok, r = pcall(gore.already_cut, mesh, b)
    return ok and r or false
  end or nil
  local at, d, bone, allow = sw.after_geometry(mesh, best, cfgReach, cut)
  -- (a hand or claw with no weapon mesh: its bone sits in the palm, the fingers reach on past it. The palm
  -- sphere above keeps that reach; the old 40 cm window is now only a ceiling.)
  local reach = allow or cfgReach
  if gate then
    if at and d <= reach and (ah.brushes or 0) < 6 then
      ah.brushes, ah.gated = (ah.brushes or 0) + 1, best.q
      log(string.format("after death: %s's %s passed %.0f cm from her %s at %.0f cm/s: not cut, %s", tostring(S.who),
        best.name, d, bone, best.v, gate))
    end
    return
  end
  if not at then
    -- (no part of her near the swing: every socket missing, or all of her cut away. Told, capped: a hit at her body
    -- after a decapitation that did nothing left no line at all, playtest)
    if (ah.noGeo or 0) < 4 then
      ah.noGeo = (ah.noGeo or 0) + 1
      log(string.format("after death: %s's %s at %.0f cm/s: no part of her near the swing", tostring(S.who),
        best.name, best.v))
    end
    return
  end
  if d > reach then
    -- (a fast one in an attack passing near: told, a few a death)
    if best.v >= (c.minSpeed or 500) and d <= 3 * cfgReach and (ah.misses or 0) < 4 and ah.missBy[S.addr or 0] ~= ah.n then
      ah.misses = (ah.misses or 0) + 1
      ah.missBy[S.addr or 0] = ah.n
      log(string.format("after death: %s's %s passed %.0f cm from her %s at %.0f cm/s: out of reach (%d cm)",
        tostring(S.who), best.name, d, bone, best.v, math.floor(reach + 0.5)))
    -- (too far or too slow to count: told, capped, not silent. A hit at her body after a decapitation that did
    -- nothing left no line at all, playtest)
    elseif (ah.farDrops or 0) < 4 then
      ah.farDrops = (ah.farDrops or 0) + 1
      log(string.format("after death: %s's %s passed %.0f cm from her %s at %.0f cm/s: too far or too slow (reach %d cm)",
        tostring(S.who), best.name, d, bone, best.v, math.floor(reach + 0.5)))
    end
    return
  end
  -- only a blow: the enemy in an attack (a montage of one, or its swing at her body) and its weapon fast. A weapon
  -- only brushing her as it walked or turned by cut her (reported)
  local en = goreCtx.enemies
  local atk = not (en and en.attacking) or (goreCtx.held(S.k) and en.attacking(S.actor, S.addr))
  local mn = not atk and en and en.montage_of and goreCtx.held(S.k) and select(3, en.montage_of(S.actor))
  -- Some enemies attack through their animation graph without a montage. Require a much faster weapon motion
  -- relative to the actor for those, so walking past her with a stationary weapon still cannot cut.
  local prev, cur = hist[#hist - 1], hist[#hist]
  local travel = prev.origin and cur.origin and sub(cur.origin, prev.origin)
  local gdt = (cur.t - prev.t) * game_scale()
  local relative = travel and len(sub(sub(best.q, best.p), travel)) / gdt
  if not atk and not mn and relative and relative >= (c.noMontageSpeed or 1500) then
    atk = "fast swing without montage"
  end
  if not atk or best.v < (c.minSpeed or 500) then
    if (ah.brushes or 0) < 3 then
      ah.brushes = (ah.brushes or 0) + 1
      -- (the montage it plays named: Raven's weapon 21 cm from her at 777 cm/s was "not attacking", and nothing said
      -- what it was doing, playtest)
      log(string.format("after death: %s's %s passed %.0f cm from her %s at %.0f cm/s, %s: not a blow", tostring(S.who),
        best.name, d, bone, best.v, atk and string.format("under %s cm/s", c.minSpeed or 500)
          or string.format("not attacking (%s)", mn and ("montage " .. mn) or "no montage")))
    -- (past the first few: told, capped, not silent. A hit at her body after a decapitation that did nothing left no
    -- line at all, playtest)
    elseif (ah.quietBlow or 0) < 4 then
      ah.quietBlow = (ah.quietBlow or 0) + 1
      log(string.format("after death: %s's %s passed %.0f cm from her %s at %.0f cm/s, %s: not a blow (%d)",
        tostring(S.who), best.name, d, bone, best.v, atk and "too slow" or "not attacking", ah.quietBlow))
    end
    ah.armedBy[S.addr or 0] = false
    return
  end
  ah.armedBy[addr], ah.n, ah.lastBy[addr] = false, ah.n + 1, os.clock()
  -- the plane: the arc through the last three samples, else the step and the enemy's forward
  local dir = unit(sub(best.q, best.p))
  local fwd = goreCtx.held(S.k) and try(function() return vof(S.actor:GetActorForwardVector()) end)
  local n, how
  local cb = best.blade and dir and cross(best.blade, dir)
  if cb and len(cb) > 0.3 then n, how = unit(cb), "blade " .. best.name end
  local pa = not n and best.i and hist[#hist - 2] and hist[#hist - 2].p[best.i]
  if pa then
    local u, w = sub(best.p, pa), sub(best.q, best.p)
    local cc = cross(u, w)
    if len(cc) > 0.2 * len(u) * len(w) then n, how = unit(cc), "weapon arc" end
  end
  if not n and dir and fwd then
    local cc = cross(dir, fwd)
    if len(cc) > 0.3 then n, how = unit(cc), "weapon swing x forward" end
  end
  -- onto the plane, through the part it passed
  if n then
    local k = dot(sub(at, best.q), n)
    at = { X = at.X - k * n.X, Y = at.Y - k * n.Y, Z = at.Z - k * n.Z }
  end
  local ncut, split = gore.cuts_on(mesh)
  log(string.format("after death (%.1f s in): %s's %s at %.0f cm/s passed %.0f cm from her %s, hit %d%s%s",
    os.clock() - ah.t0, tostring(S.who), best.name, best.v, d, bone, ah.n,
    c.max and string.format(" of %d", c.max) or "",
    split and ", she is split: blood only" or ""))
  if atk == "fast swing without montage" then log(string.format("after death: no montage; relative weapon speed %.0f cm/s", relative)) end
  gore.on_hit(pawn, mesh, at)
  if split then return true end
  gore.aim(dir)
  -- a split needs her whole: once something is off her, a lengthwise or diagonal blow is a hit mark instead
  -- (across her body still cuts the torso)
  local weaponNames = {}
  for _, w in ipairs(S.weapons or {}) do weaponNames[#weaponNames + 1] = w.name end
  local h = { t = os.clock(), loc = at, dir = dir, fwd = fwd or dir, n = n, how = how, push = dir, attack_dir = 0,
    bone = bone, wbone = best.name, noSplit = ncut > 0, attacker = S.who, attackerClass = S.cls, weaponNames = weaponNames }
  -- a blunt follow-up smashes as projectiles do: a second hammer blow after the upper body went
  -- smashed the lower body instead of leaving blood-only (Marionette hair excluded: sharp, cuts)
  if (g.smash or {}).enabled == true and sw.blunt_of then
    local okb, blunt = pcall(sw.blunt_of, h)
    if okb and blunt then
      gore.aim(dir)
      local oks, made = pcall(gore.smash, pawn, mesh,
        { loc = at, dir = dir, push = dir, attacker = S.who, src = "after death blunt " .. tostring(best.name) }, "after")
      if oks and made then log(string.format("after death: %s's %s smashed her %s", tostring(S.who), best.name, bone)); return true end
      if not oks then log("after death: smash failed: " .. tostring(made)) end
    end
  end
  -- (the marks off, as they ship: every hit cuts. The cutChance share alone left a quarter of them showing nothing,
  -- playtest)
  local marks = (g.hitMarks or {}).enabled ~= false
  if (not marks or math.random() <= (c.cutChance or 0.75)) and gore.blow(pawn, mesh, h, "after") then return true end
  if not marks then log("after death: the hit didn't cut, and hit marks are off: blood only"); return true end
  gore.hit_mark(pawn, mesh, at, dir, nil)
  return true
end

local function hits_after(pawn, mesh)
  local tune, gore, swing = get_tune(), get_gore(), get_swing()
  local g = tune.gore or {}
  local c = g.afterHits or {}
  if not gore then return end
  local q = ah.projectiles
  if q and #q > 0 then
    local now = os.clock()
    while q[1] and now - q[1].t > 1.5 do table.remove(q, 1) end
    if q[1] and not ah.blunt and (not c.max or ah.n < c.max) and (g.smash or {}).enabled == true
      and now - ah.t0 >= (c.from or 0.6)
      and now - (ah.projectileAt or ah.t0) >= (c.rearm or 0.35) and not gore.busy() then
      local h = table.remove(q, 1)
      local _, split = gore.cuts_on(mesh)
      if not split then
        gore.aim(h.push or h.dir)
        local ok, made = pcall(gore.smash, pawn, mesh, h, "after")
        if ok and made then
          ah.n, ah.projectileAt = ah.n + 1, now
          log(c.max and string.format("projectile after death: smash %d of %d (%s)", ah.n, c.max, h.src)
            or string.format("projectile after death: smash %d (%s)", ah.n, h.src))
        elseif not ok then log("projectile after death: smash failed: " .. tostring(made)) end
      end
    end
  end
  -- Rearm per attacker, then try every fast candidate until one genuine contact is dispatched.
  local candidates = {}
  for _, x in ipairs(#sw.list > 0 and sw.list or { swing }) do
    local steps = sw.after_steps(x, g)
    if steps[1] and steps[1].v < (g.swingMinSpeed or 300) then
      ah.armedBy[x.addr or 0] = true
    else
      for _, st in ipairs(steps) do
        if st.v >= (g.swingMinSpeed or 300) then candidates[#candidates + 1] = { step = st, tracker = x } end
      end
    end
  end
  table.sort(candidates, function(x, y) return x.step.v > y.step.v end)
  for _, hit in ipairs(candidates) do
    if hit_step(pawn, mesh, hit.tracker, hit.step, g, c, gore) then return end
  end
  if #candidates == 0 then
    -- an attack was ordered at her body but no weapon trail reached geometry: told, capped, never silent (an ordered
    -- close-range swing that registered nothing left no line at all, playtest)
    local ordered = goreCtx.afterOrderedAt and os.clock() - goreCtx.afterOrderedAt or 99
    if ordered < 1.5 and (ah.noTrail or 0) < 4 then
      ah.noTrail = (ah.noTrail or 0) + 1
      log(string.format("after death: an attack was ordered at her body %.1f s ago but no weapon trail: nothing to judge", ordered))
    end
  end
end

return hits_after
end
