-- Photo-mode observation, piece freezing and detached-head face updates.
return function(screen, goreCtx, valid, try, log, lg, vof, dist, PELVIS, dface, get_gore, get_rag, get_pawn)
function screen.view(pawn, gs)
  gs = gs or goreCtx.statics()
  local vt = valid(gs) and try(function() return gs:GetPlayerCameraManager(pawn, 0).ViewTarget.Target end)
    or try(function() return pawn.Controller.PlayerCameraManager.ViewTarget.Target end)
  local va = valid(vt) and vt:GetAddress() or 0
  if va ~= screen.vtAddr then
    screen.vtAddr = va
    screen.vtClass = va ~= 0 and (try(function() return vt:GetClass():GetFName():ToString() end) or "") or ""
    screen.vtPhoto = screen.vtClass:find("PhotoMode") ~= nil
  end
end
-- The frame photo mode opens is also told by the game's time standing still while the frames go on (its pause stops
-- the world's clock, the death's timers with it): read every frame, so the freeze comes before her mesh ticks once
-- on the animation. A long frame (a hitch, the game's clock capped) isn't a pause
function screen.time_stopped(pawn, gs)
  local now = os.clock()
  local t = valid(gs) and try(function() return gs:GetTimeSeconds(pawn) end)
  local w = screen.clock
  screen.clock = t and { real = now, game = t } or nil
  if not (t and w) then return false end
  local real = now - w.real
  if real <= 0 or real > 0.25 then return screen.stopped == true end
  -- the game's clock runs behind real time on purpose under slow motion: compare against the expected speed,
  -- full speed as before when nothing is slowed (a true pause advances nothing either way)
  local scale = 1
  try(function() scale = goreCtx.time_scale and goreCtx.time_scale() or 1 end)
  if not (scale and scale > 0) then scale = 1 end
  screen.stopped = (t - w.game) < real * 0.05 * scale
  return screen.stopped
end
-- her mesh (and hair) stop ticking / tick again. Her hair's meshes run their own animation (and SBHair its own sim)
-- off her head: with her mesh frozen the head stayed but the hair flew to her neck (playtest). Only what was ticking
-- is stopped, and started again.
-- Photo mode (photo): her mesh stopped ticking took its poses and expressions with it (reported), so there it ticks on
-- and the pieces cut off her lie on a copy of her mesh instead (gore.hide_pieces), till photo mode closes. Alive only:
-- in a death her mesh stops as before (on a copy her cut-off head went back onto her neck, 0.4.3 playtest)
function screen.freeze(pawn, mesh, why, photo)
  local gore = get_gore()
  if not valid(mesh) or try(function() return mesh:IsSimulatingPhysics(PELVIS) end) then return end
  if photo and (goreCtx.dead_since() or screen.hpZero) then photo = nil end
  if photo and gore and gore.hide_pieces then
    if gore.pieceHid then return end
    if screen.frozenMesh then screen.unfreeze(mesh) end
    local np = gore.hide_pieces(pawn, mesh, true)
    if gore.pieceHid and gore.pieceHid.face then pcall(screen.head_hook, mesh) end
    log(string.format("photo mode (%s) with %d piece(s) off her alive: her mesh ticks on (poses, expressions), the pieces on their copy till it closes",
      why, np))
    return
  end
  if screen.frozenMesh then return end
  try(function() mesh:SetComponentTickEnabled(false) end)
  -- (photo mode updates her bones itself with her tick off, playtest: the skeleton update is skipped too)
  try(function() mesh.bNoSkeletonUpdate = true end)
  screen.frozenMesh = mesh:GetAddress()
  local hair = gore and gore.hair_of and gore.hair_of(pawn) or {}
  hair[#hair + 1] = try(function() return pawn.SBHair end)
  screen.frozenHair = {}
  for _, c in ipairs(hair) do
    if valid(c) and try(function() return c:IsComponentTickEnabled() end) == true then
      try(function() c:SetComponentTickEnabled(false) end)
      try(function() c.bNoSkeletonUpdate = true end)
      screen.frozenHair[#screen.frozenHair + 1] = c
    end
  end
  log(string.format("game paused (%s) with a piece simulating on her alive: her mesh and %d hair part(s) stop ticking (their animation would pull the piece back)",
    why, #screen.frozenHair))
end
function screen.unfreeze(mesh)
  local gore = get_gore()
  -- (a piece settled on its copy before photo mode opened stays there: hm.piece_watch)
  if gore and gore.pieceHid and not gore.pieceHid.baked then
    pcall(screen.head_end)
    local np, nr = gore.hide_pieces(nil, nil, false)
    log(string.format("photo mode over: %d piece(s) back on her, with %d part(s) riding them; their copy gone", np, nr))
  end
  local fz = screen.frozenMesh
  if not fz then return end
  screen.frozenMesh = nil
  if valid(mesh) and fz == mesh:GetAddress() then
    try(function() mesh.bNoSkeletonUpdate = false end)
    try(function() mesh:SetComponentTickEnabled(true) end)
  end
  for _, c in ipairs(screen.frozenHair or {}) do
    if valid(c) then try(function() c.bNoSkeletonUpdate = false end); try(function() c:SetComponentTickEnabled(true) end) end
  end
  screen.frozenHair = nil
  log("pause over: her mesh and hair tick again")
end
-- the freeze holds this many seconds after photo mode's pawn or a widget of its is made: her tick ran between its
-- pawn and its widgets, before its view or widgets showed, found no photo mode, and let her mesh and hair tick again
-- for a frame: the hair on a cut-off head flew back to where it sits on her (playtest)
screen.PHOTO_HOLD = 1.5
-- photo mode's widgets, as they are made (the widget watch above): her own tick, where the rest of this runs, stops
-- while photo mode is on (playtest: nothing of the mod's logged from photo mode opening till it closed, and the head
-- and hair went to her neck), so the freeze comes here, on the game thread, as photo mode opens. Each one is kept:
-- photo mode is on while one of them shows
-- (pawn_made: photo mode's pawn, not a widget to watch)
function screen.photo_widget(o, cls, pawn_made)
  local gore, rag, cachedPawn = get_gore(), get_rag(), get_pawn()
  screen.photoW = screen.photoW or {}
  -- (kept by path: photo mode frees its widgets as it closes, and asking a freed one IsValid crashed UE4SS, playtest)
  -- Only its panels: its ~90 slots and tab buttons are never in the viewport themselves, and each kept one is a name
  -- table lookup a frame
  if not pawn_made and not cls:find("_Slot_C$") and not cls:find("_Btn_C$") then
    screen.photoW[#screen.photoW + 1] = goreCtx.keep(o)
  end
  local pawn = cachedPawn
  local mesh = valid(pawn) and try(function() return pawn.Mesh end)
  local cut = gore and valid(mesh) and (gore.cuts_on(mesh)) > 0
  -- (the first one as it opens: how far her head is from where it was)
  if cut and not screen.photoOpened then
    local head = try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Head"))) end)
    local h0 = screen.photoHead
    screen.photoOpened = true
    log(string.format("photo mode opening: head %s off where it was", head and h0 and string.format("%.0f cm", dist(head, h0)) or "?"))
  end
  ;(pawn_made and log or lg.v)(string.format("photo mode %s made: %s%s", pawn_made and "pawn" or "widget", cls, cut and "" or " (no piece off her)"))
  -- the game's own key on her ragdoll (P did this before opening it: screen.photo_key): her bodies stopped, asleep
  -- and deaf to its pawn, her other meshes' collision kept, both put back as it closes (photo_watch, on her tick's
  -- first look). Skipped, her hair and capsule came back blocking her bodies and threw her about, bent and
  -- stretched (playtest, F7's ragdoll)
  if pawn_made and not screen.photoOn and rag and rag.photo_hold and not rag.photoHeld and rag.view and rag.view() then
    if valid(pawn) then screen.photo_coll_save(pawn) end
    local held = rag.photo_hold(true)
    screen.photoOn, screen.photoNext, screen.photoSeen, screen.photoWait = true, 0, nil, os.clock() + 2
    screen.photoHead = valid(mesh) and try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Head"))) end)
    log(string.format("photo mode opening on her ragdoll by the game's own key: %d of her meshes held still", held))
  end
  if cut then
    screen.freeze(pawn, mesh, "photo mode's " .. (pawn_made and "pawn " or "widget ") .. cls, true)
    screen.photoHold = os.clock() + screen.PHOTO_HOLD
  end
end
local function photo_widget_up()
  for i = #(screen.photoW or {}), 1, -1 do
    local k = screen.photoW[i]
    local w = goreCtx.held(k) and k.obj
    if not w then table.remove(screen.photoW, i)
    elseif try(function() return w:IsInViewport() end) == true then return true end
  end
  return false
end
-- photo mode with her head cut off, on the piece's copy (gore.hide_pieces): her face took its expression from her
-- body's animation curves, and posed by the copy (no animation) it went blank and ignored photo mode's expressions and
-- look at the camera (playtest). Her tick doesn't run in photo mode, but her animation does, so its Blueprint update is
-- hooked (once, on the game thread) and each frame her body's curves for the face's morphs are set on the face. Her
-- hair on the head is reset to it for a few frames after each pose change: the pose brings its own hair snapshot,
-- which threw it back where her head would be (playtest)
screen.head = { hooked = nil, tried = false, cur = nil }
function screen.head_hook(mesh)
  local hd = screen.head
  if hd.hooked or hd.tried then return end
  hd.tried = true
  local paths = {}
  for _, inst in ipairs({ try(function() return mesh:GetAnimInstance() end), try(function() return mesh:GetPostProcessInstance() end) }) do
    local full = valid(inst) and try(function() return inst:GetClass():GetFullName() end)
    local path = full and full:match("^%S+%s+(.+)$")
    if path then paths[#paths + 1] = path .. ":BlueprintUpdateAnimation" end
  end
  for _, p in ipairs(paths) do
    if valid(try(function() return StaticFindObject(p) end)) then
      local ok = pcall(RegisterHook, p, function()
        local ok2, err = pcall(screen.head_tick)
        if not ok2 and not hd.err then hd.err = true; log("photo mode head: " .. tostring(err)) end
      end)
      if ok then hd.hooked = p; break end
    end
  end
  log("photo mode: a cut-off head follows photo mode's face settings " .. (hd.hooked and "through " .. hd.hooked
    or "never: no Blueprint update of hers to hook (" .. table.concat(paths, ", ") .. ")"))
end
function screen.head_tick()
  local gore, cachedPawn = get_gore(), get_pawn()
  local h = gore and gore.pieceHid
  local hd = screen.head
  local pawn = cachedPawn
  if not (h and valid(h.face) and valid(pawn)) then
    if hd.cur then screen.head_end() end
    return
  end
  local cur = hd.cur
  if not cur then
    local anim = try(function() return pawn.Mesh:GetAnimInstance() end)
    if not valid(anim) then return end
    local set = dface.names(h.face)
    -- (not reset from the start: her ponytail is cloth, reset as it went onto the copy it moved off the head as photo
    -- mode opened and came back as it closed, its bones never moving, playtest; reset on a pose change only)
    cur = { face = h.face, anim = anim, names = {}, fn = {}, vals = {}, reset = 0, hair = {}, n = 0 }
    for nm, _ in pairs(set) do cur.names[#cur.names + 1] = nm; cur.fn[#cur.fn + 1] = FName(nm) end
    local sk = StaticFindObject("/Script/Engine.SkeletalMeshComponent")
    for _, r in ipairs(h.riders or {}) do
      if valid(r.c) and try(function() return r.c:IsA(sk) end) then cur.hair[#cur.hair + 1] = r.c end
    end
    for _, k in ipairs(h.posed or {}) do cur.hair[#cur.hair + 1] = k end
    hd.cur = cur
    log(string.format("photo mode: the cut-off head's face takes her body's curves (%d morphs), %d part(s) of her hair reset on a pose change",
      #cur.names, #cur.hair))
  end
  local set = 0
  for i, f in ipairs(cur.fn) do
    local v = try(function() return cur.anim:GetCurveValue(f) end) or 0
    if math.abs(v - (cur.vals[i] or 0)) > 0.002 then
      cur.vals[i] = v
      try(function() cur.face:SetMorphTarget(f, v, false) end)
      set = set + 1
    end
  end
  cur.n = cur.n + 1
  -- where her hair parts are as photo mode opens, against the copy's head and her own (on her neck): which part goes
  -- back to her neck (reported on CH_P_EVE_30: her hair snapped back as photo mode opened, with or without the fork)
  -- where her hair parts are while photo mode is open, against the cut-off head and her neck: which part goes back to
  -- her neck (reported on CH_P_EVE_30: her hair snapped back as photo mode opened, with or without the fork). Every
  -- 5th frame, logged on the first and whenever a part moved 5 cm or more since the last line (the first second was
  -- quiet: the snap came as photo mode fully opened, 84=14, about 3 s in, playtest)
  if cur.n % 5 == 1 then
    -- (never in the way of the face and the reset below)
    local okd, ed = pcall(function()
      local ch = h.copies and h.copies[1]
      local mesh = try(function() return pawn.Mesh end)
      local hc = valid(ch) and try(function() return vof(ch:GetSocketLocation(FName("Bip001-Head"))) end)
      local hn = valid(mesh) and try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Neck"))) end)
      if not cur.list then
        -- (the hair bones of each, Hair/Pony in their names, found once: a component's Bounds isn't a property UE4SS
        -- reads, playtest)
        cur.list = {}
        local all = { { "copy", ch }, { "her", mesh } }
        for _, k in ipairs(cur.hair) do all[#all + 1] = { nil, k } end
        for _, e in ipairs(all) do
          local k = e[2]
          if valid(k) and valid(try(function() return k.SkeletalMesh end)) then
            local bones = {}
            local n = try(function() return k:GetNumBones() end) or 0
            for i = 0, n - 1 do
              local bn = try(function() return k:GetBoneName(i):ToString() end)
              if bn and (bn:find("[Hh]air") or bn:find("[Pp]ony")) then bones[#bones + 1] = FName(bn) end
            end
            if #bones > 0 then
              cur.list[#cur.list + 1] = { nm = e[1] or try(function() return k.SkeletalMesh:GetFName():ToString() end) or "?", k = k, bones = bones }
            end
          end
        end
      end
      local parts, moved = {}, cur.n == 1
      for _, e in ipairs(cur.list) do
        local sx, sy, sz, c = 0, 0, 0, 0
        if valid(e.k) then
          for _, f in ipairs(e.bones) do
            local p = try(function() return vof(e.k:GetSocketLocation(f)) end)
            if p and type(p.X) == "number" then sx, sy, sz, c = sx + p.X, sy + p.Y, sz + p.Z, c + 1 end
          end
        end
        local o = c > 0 and { X = sx / c, Y = sy / c, Z = sz / c } or nil
        if o and e.last and dist(o, e.last) >= 5 then moved = true end
        if o and not e.last then e.last = o end
        if moved and o then e.last = o end
        parts[#parts + 1] = string.format("%s %s/%s", e.nm, (o and hc) and string.format("%.0f", dist(o, hc)) or "?",
          (o and hn) and string.format("%.0f", dist(o, hn)) or "?")
      end
      if moved then
        local st = (screen.liveSig or ""):match("^84=%S+") or ""
        log(string.format("photo mode frame %d%s: hair cm from the cut-off head / her neck: %s; the head %s from her neck",
          cur.n, st ~= "" and (" (" .. st .. ")") or "", table.concat(parts, ", "),
          (hc and hn) and string.format("%.0f cm", dist(hc, hn)) or "?"))
      end
    end)
    if not okd then log("photo mode frame " .. cur.n .. ": " .. tostring(ed)) end
  end
  if set > 0 and not cur.said then cur.said = true; log(string.format("photo mode: the cut-off head's face moved (%d morphs)", set)) end
  local sig = tostring(try(function() return pawn.PoseName_PhotoMode:ToString() end)) .. "/" ..
    tostring(try(function() return pawn.bChangedPose_PhotoMode end))
  if cur.sig and sig ~= cur.sig then
    cur.reset = 10
    log("photo mode: her pose changed (" .. sig .. "): the hair on her cut-off head reset to it")
  end
  cur.sig = sig
  if cur.reset > 0 then
    cur.reset = cur.reset - 1
    -- (cloth, and the rigid body chains of her hair's own animation: ResetPhysics)
    for _, k in ipairs(cur.hair) do
      if valid(k) then
        try(function() k:ForceClothNextUpdateTeleportAndReset() end)
        try(function() k:ResetAnimInstanceDynamics(2) end)
      end
    end
  end
end
-- the face's morphs set from her curves back off as photo mode closes (her body's curves drive it again)
function screen.head_end()
  local cur = screen.head.cur
  screen.head.cur = nil
  if not cur or not valid(cur.face) then return end
  for i, f in ipairs(cur.fn) do
    if (cur.vals[i] or 0) ~= 0 then try(function() cur.face:SetMorphTarget(f, 0, true) end) end
  end
end
function screen.photo_freeze(pawn, mesh)
  local gs = goreCtx.statics()
  local paused = valid(gs) and try(function() return gs:IsGamePaused(pawn) end)
  screen.view(pawn, gs)
  local stopped = screen.time_stopped(pawn, gs)
  local widget = photo_widget_up()
  local photo = widget or screen.vtPhoto or screen.photoOn or screen.photoLive or os.clock() < (screen.photoHold or 0)
  paused = paused or stopped or photo
  if paused then
    screen.freeze(pawn, mesh, screen.vtPhoto and "photo mode's view" or widget and "photo mode's widget"
      or (screen.photoOn or screen.photoLive) and "photo mode" or stopped and "the game's clock stopped" or "paused", photo)
  else
    screen.unfreeze(mesh)
    -- (where her head is the last frame before a pause, for the log as photo mode opens: the 0.5 s poll's was off by
    -- however far a thrown piece had gone since)
    screen.photoHead = try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Head"))) end) or screen.photoHead
  end
end

end
