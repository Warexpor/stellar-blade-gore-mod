-- Track nearby weapons and preserve their time-bounded motion and body-pose history.
return function(sw, goreCtx, settings, get_swing, set_swing, get_active, get_gore, SWING_NAMES, try, valid, vof, len, name, log)
local swingBones = {} -- enemy class -> its weapon bones, found once per world
local function swing_bones(m, cls)
  if swingBones[cls] then return swingBones[cls] end
  local n = try(function() return m:GetNumBones() end) or 0
  local names, ranked = {}, {}
  for i = 0, n - 1 do
    local nm = try(function() return m:GetBoneName(i):ToString() end)
    if nm then
      names[#names + 1] = nm
      local low = nm:lower()
      for r, p in ipairs(SWING_NAMES) do
        if low:find(p, 1, true) and not low:find("finger") and not low:find("twist") then
          ranked[#ranked + 1] = { nm, r }
          break
        end
      end
    end
  end
  table.sort(ranked, function(a, b) return a[2] < b[2] end)
  local out, most = {}, (settings().gore or {}).swingBones or 8
  for _, e in ipairs(ranked) do if #out < most then out[#out + 1] = e[1] end end
  swingBones[cls] = out
  log(string.format("swing: %s has %d bones, following %s%s", cls, n, #out > 0 and table.concat(out, ", ") or "none",
    #out == 0 and (": " .. table.concat(names, " ", 1, math.min(#names, 80))) or ""))
  return out
end
-- its weapon meshes (the weapon slots of its MeshInfoList, as hers): each one's long axis, from its mesh's imported
-- bounds in the component's space, is the blade. Its two ends are sampled with the bones, and the plane the blade
-- sweeps (the blade line and the way it moved) is the cut's: the fastest bone was a grip socket, maybe the empty
-- hand, and its arc ran parallel to her 38 cm off her spine where the blade went through her (playtest 42)
local SWING_WEAPON_SLOTS = { [5] = true, [6] = true, [7] = true, [8] = true }
local function swing_weapons(actor)
  local out = {}
  try(function()
    actor.MeshInfoList:ForEach(function(_, e)
      local info = e:get()
      local c = info.MeshComponent
      if SWING_WEAPON_SLOTS[info.MeshSlot] and valid(c) then
        local b = try(function() local x = c.SkeletalMesh:GetImportedBounds(); return { o = vof(x.Origin), e = vof(x.BoxExtent) } end)
          or try(function() local x = c.StaticMesh:GetBounds(); return { o = vof(x.Origin), e = vof(x.BoxExtent) } end)
        if b and b.o and b.e then
          local ax = b.e.X >= b.e.Y and b.e.X >= b.e.Z and { X = b.e.X, Y = 0, Z = 0 }
            or b.e.Y >= b.e.Z and { X = 0, Y = b.e.Y, Z = 0 } or { X = 0, Y = 0, Z = b.e.Z }
          local nm = try(function() return (c.SkeletalMesh or c.StaticMesh):GetName() end)
            or try(function() return c:GetName() end) or "weapon"
          local sock = try(function() return c:GetAttachSocketName():ToString() end) or "?"
          out[#out + 1] = { comp = c, k = goreCtx.keep(c), o = b.o, ax = ax, name = nm, socket = sock, cm = 2 * len(ax),
            impactRadius = sw.cross_radius(b.e, try(function() return vof(c:K2_GetComponentScale()) end)) }
        end
      end
    end)
  end)
  return out
end
-- a point given in a component's space, in the world
local function comp_blade(c, o, axis)
  return try(function()
    local wl, f, r, u = c:K2_GetComponentLocation(), c:GetForwardVector(), c:GetRightVector(), c:GetUpVector()
    local x = wl.X + f.X * o.X + r.X * o.Y + u.X * o.Z
    local y = wl.Y + f.Y * o.X + r.Y * o.Y + u.Y * o.Z
    local z = wl.Z + f.Z * o.X + r.Z * o.Y + u.Z * o.Z
    local dx = f.X * axis.X + r.X * axis.Y + u.X * axis.Z
    local dy = f.Y * axis.X + r.Y * axis.Y + u.Y * axis.Z
    local dz = f.Z * axis.X + r.Z * axis.Y + u.Z * axis.Z
    return { a = { X = x - dx, Y = y - dy, Z = z - dz }, b = { X = x + dx, Y = y + dy, Z = z + dz } }
  end)
end
local function track_swing(pawn, mesh)
  local g = settings().gore or {}
  if g.weaponSwing == false then return end
  local t0, now = os.clock(), os.clock()
  if now >= sw.next then
    sw.next = now + (g.swingRefresh or 0.25)
    local had = {}
    for _, S in ipairs(sw.list) do had[S.addr] = S end
    local list = {}
    -- (one already followed is kept out to swingKeep times the reach, its trail with it: the dual-blade enemy stepped
    -- back past 5 m and in again between attacks, its trail started over each time, and the blow that came right
    -- after went unseen, 5 of 9 deaths a playtest)
    local reach = g.swingReach or 500
    local cand = {}
    local tn = os.clock()
    for _, a in ipairs((sw.near(mesh, reach * (g.swingKeep or 2.5)))) do
      if a.d < reach or had[a.addr] then cand[#cand + 1] = a end
      if #cand >= (g.swingFollow or 3) then break end
    end
    sw.nearMs = (os.clock() - tn) * 1000
    tn = os.clock()
    for _, a in ipairs(cand) do
      local S = had[a.addr]
      if not S then
        local m = try(function() return a.actor.Mesh end)
        if valid(m) and a.cls then
          S = sw.state()
          S.addr, S.actor, S.mesh, S.who, S.k, S.cls = a.addr, a.actor, m, name(a.actor), a.k, a.cls
          S.bones = swing_bones(m, a.cls)
          S.weapons = swing_weapons(a.actor)
          local ws = {}
          for _, w in ipairs(S.weapons) do ws[#ws + 1] = string.format("%s %.0f cm on %s", w.name, w.cm, w.socket) end
          log(string.format("swing: %s holds %s", a.cls, #ws > 0 and table.concat(ws, ", ") or "no weapon mesh"))
        end
      end
      if S then list[#list + 1] = S end
    end
    -- (why one followed was let go: the trail goes with it)
    local kept = {}
    for _, S in ipairs(list) do kept[S.addr] = true end
    for addr, S in pairs(had) do
      if not kept[addr] then
        local far
        for _, a in ipairs(cand) do if a.addr == addr then far = a.d end end
        log(string.format("swing: %s no longer followed (%s)", tostring(S.who),
          far and string.format("%.0f cm off", far) or string.format("hidden, gone or past %.0f cm", reach * (g.swingKeep or 2.5))))
      end
    end
    sw.list = list
    set_swing(sw.list[1] or sw.state())
    sw.newMs = (os.clock() - tn) * 1000
  else
    sw.nearMs, sw.newMs = 0, 0
  end
  -- her pose with them, while she is alive: a killing blow is judged on her body as the weapon met it (gore.blow), not
  -- as the death show has moved it by the time the death starts (an arm raised to block had swung away)
  local pose
  local gore = get_gore()
  if not get_active() and gore and g.blowPose ~= false and #sw.list > 0 then pose = gore.pose(mesh) end
  local keep = g.swingWindow or 0.6
  -- the window is game seconds: under slow motion it spans more real ones, capped so a deep slow-mo doesn't
  -- make the death's swing analysis walk thousands of samples
  local scale = 1
  try(function() scale = goreCtx.time_scale and goreCtx.time_scale() or 1 end)
  if not (scale and scale > 0) then scale = 1 end
  for i = #sw.list, 1, -1 do
    local S = sw.list[i]
    if not goreCtx.held(S.k) or try(function() return S.actor.bActorIsBeingDestroyed end) ~= false then
      table.remove(sw.list, i)
      if get_swing() == S then set_swing(sw.list[1] or sw.state()) end
    elseif (S.bones and #S.bones > 0) or (S.weapons and #S.weapons > 0) then
      local s = { t = now, p = {}, w = {}, pose = pose, origin = try(function() return vof(S.actor:K2_GetActorLocation()) end) }
      for k, b in ipairs(S.bones or {}) do s.p[k] = try(function() return vof(S.mesh:GetSocketLocation(FName(b))) end) end
      for k, w in ipairs(S.weapons or {}) do
        if goreCtx.held(w.k) then
          local blade = comp_blade(w.comp, w.o, w.ax)
          if blade then s.w[k] = blade end
        end
      end
      local h = S.hist
      h[#h + 1] = s
      while #h > 0 and (now - h[1].t) * scale > keep do table.remove(h, 1) end
      while #h > 240 do table.remove(h, 1) end
    end
  end
  local ms = (os.clock() - t0) * 1000
  -- (by part: the 422 ms slow tick of a playtest was all "swing")
  if ms >= (g.slowMs or 15) then
    log(string.format("swing: following %d enemies took %.0f ms (who is near %.0f, new ones' bones and weapons %.0f, their trails %.0f)",
      #sw.list, ms, sw.nearMs or 0, sw.newMs or 0, ms - (sw.nearMs or 0) - (sw.newMs or 0)))
  end
end
return track_swing, function() swingBones = {} end
end
