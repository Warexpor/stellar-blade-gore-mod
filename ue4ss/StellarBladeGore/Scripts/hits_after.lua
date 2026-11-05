-- Follow-up attacks and projectile dispatch after death.
return function(sw, ah, goreCtx, get_tune, get_gore, get_swing, try, vof, len, dist, sub, dot, cross, unit, log)
-- the fastest step one followed enemy's weapon just made (its blade meshes before its bones), nil with no fresh step
function sw.after_step(S, g)
  local hist = S.hist
  if not (S.bones or S.weapons) or #hist < 2 or os.clock() - hist[#hist].t > 0.2 then return nil end
  local a, b = hist[#hist - 1], hist[#hist]
  local dt = b.t - a.t
  if dt < 1e-3 then return nil end
  local best
  for i = 1, #(S.bones or {}) do
    local p, q = a.p[i], b.p[i]
    if p and q then
      local v = dist(p, q) / dt
      if not best or v > best.v then best = { v = v, i = i, p = p, q = q, name = S.bones[i] } end
    end
  end
  local bb
  for k, e in pairs(b.w or {}) do
    local o = a.w and a.w[k]
    if o then
      local v = math.max(dist(o.a, e.a), dist(o.b, e.b)) / dt
      if not bb or v > bb.v then
        local w = S.weapons[k]
        local mid = function(x) return { X = (x.a.X + x.b.X) / 2, Y = (x.a.Y + x.b.Y) / 2, Z = (x.a.Z + x.b.Z) / 2 } end
        local far = dist(o.b, e.b) >= dist(o.a, e.a)
        bb = { v = v, p = far and o.b or o.a, q = far and e.b or e.a, name = w and w.name or "weapon",
          steps = { { o.a, e.a }, { mid(o), mid(e) }, { o.b, e.b } }, blade = unit(sub(e.b, e.a)) }
      end
    end
  end
  if bb and bb.v >= (g.swingMinSpeed or 300) then best = bb end
  return best
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
    if q[1] and not ah.blunt and ah.n < (c.max or 6) and (g.smash or {}).enabled == true
      and now - ah.t0 >= (c.from or 0.6)
      and now - (ah.projectileAt or ah.t0) >= (c.rearm or 0.35) and not gore.busy() then
      local h = table.remove(q, 1)
      local _, split = gore.cuts_on(mesh)
      if not split then
        gore.aim(h.push or h.dir)
        local ok, made = pcall(gore.smash, pawn, mesh, h, "after")
        if ok and made then
          ah.n, ah.projectileAt = ah.n + 1, now
          log(string.format("projectile after death: smash %d of %d (%s)", ah.n, c.max or 6, h.src))
        elseif not ok then log("projectile after death: smash failed: " .. tostring(made)) end
      end
    end
  end
  -- every enemy followed, not only the nearest (the one swinging at her body needn't be: enemies.lua's swings after
  -- death), each armed again once its own weapon slowed down (one cut a swing)
  local best, S
  for _, x in ipairs(#sw.list > 0 and sw.list or { swing }) do
    local st = sw.after_step(x, g)
    if st and st.v < (g.swingMinSpeed or 300) then ah.armedBy[x.addr or 0] = true
    elseif st and (not best or st.v > best.v) then best, S = st, x end
  end
  if not best then return end
  local hist = S.hist
  if ah.blunt or os.clock() - ah.t0 < (c.from or 0.6) then return end
  -- (why a blow that came in was let go, told once a swing: a second hit after death that cut nothing left no line
  -- at all, playtest)
  -- (armed again once its weapon slowed down, or rearm s after its last cut: a combo's next blow came with the
  -- hands never slowing in between, and a second hit right after her death cut nothing, playtest)
  local addr = S.addr or 0
  if not ah.armedBy[addr] and os.clock() - (ah.lastBy[addr] or ah.t0) >= (c.rearm or 0.35) then ah.armedBy[addr] = true end
  local gate = not ah.armedBy[addr] and "its weapon not slowed since the last"
    or ah.n >= (c.max or 6) and string.format("%d hits already", ah.n)
    or gore.busy() and "a cut still being made"
  if gate and (best.v < (c.minSpeed or 500) or ah.gated == best.q) then return end
  local cfgReach = best.steps and (c.reach or 25) or (c.handReach or 40)
  local at, d, bone, allow = sw.after_geometry(mesh, best, cfgReach)
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
  if not at then return end
  if d > reach then
    -- (a fast one in an attack passing near: told, a few a death)
    if best.v >= (c.minSpeed or 500) and d <= 3 * cfgReach and (ah.misses or 0) < 4 and ah.missBy[S.addr or 0] ~= ah.n then
      ah.misses = (ah.misses or 0) + 1
      ah.missBy[S.addr or 0] = ah.n
      log(string.format("after death: %s's %s passed %.0f cm from her %s at %.0f cm/s: out of reach (%d cm)",
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
  local relative = travel and len(sub(sub(best.q, best.p), travel)) / (cur.t - prev.t)
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
  log(string.format("after death (%.1f s in): %s's %s at %.0f cm/s passed %.0f cm from her %s, hit %d of %d%s",
    os.clock() - ah.t0, tostring(S.who), best.name, best.v, d, bone, ah.n, c.max or 6,
    split and ", she is split: blood only" or ""))
  if atk == "fast swing without montage" then log(string.format("after death: no montage; relative weapon speed %.0f cm/s", relative)) end
  gore.on_hit(pawn, mesh, at)
  if split then return end
  gore.aim(dir)
  -- a split needs her whole: once something is off her, a blow through her body is a hit mark instead
  local h = { t = os.clock(), loc = at, dir = dir, fwd = fwd or dir, n = n, how = how, push = dir, attack_dir = 0,
    bone = bone, noSplit = ncut > 0, attacker = S.who }
  -- (the marks off, as they ship: every hit cuts. The cutChance share alone left a quarter of them showing nothing,
  -- playtest)
  local marks = (g.hitMarks or {}).enabled ~= false
  if (not marks or math.random() <= (c.cutChance or 0.75)) and gore.blow(pawn, mesh, h, "after") then return end
  if not marks then log("after death: the hit didn't cut, and hit marks are off: blood only"); return end
  gore.hit_mark(pawn, mesh, at, dir, nil)
end


return hits_after
end
