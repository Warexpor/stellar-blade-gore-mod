-- Death-face factory, shared by the player and sandbox bosses.
return function(try, valid, name, log, get_tune, get_gore)
-- ---- the death face ----
-- DIE1 (Proper Death Expression) does start as she dies: her eyelids were closing 0.2 s in (upLid_down_L 0.95 on her
-- body's curves), and by 1 s every curve was back at 0 and she stared with her eyes open (twentieth playtest; the
-- sequencer calls tried before had nothing to be called on). So the mod holds a dead face itself: morph targets set on
-- her face mesh (SetMorphTarget; a master-posed face adds its own over the curves it takes from her body), faded in
-- from tune.gore.deathFace.at over fade seconds and held until she gets up. Each entry of deathFace.morphs names a
-- JALI morph, its ARKit twin and a weight: the first name her face mesh has is used (both would close the eyes twice).
-- A mood (tune.gore.deathFace.moods) is picked per death and every weight and time jittered, with her eyes' last
-- opening, their drift and her jaw's hang picked too, so no two deaths wear the same face. Page Up shows the moods
-- in turn on her living face, 6 s each.
-- One per face (goreCtx.make_face; no local to spare here): hers, and each sandbox boss's (bosses.lua, through
-- goreCtx.new_face); conv: the convulsions' face poses laid over it (by morph target name)
return function(conv)
local dface = { known = {}, on = nil } -- known: mesh asset addr -> { set of its morph names, count }; on: the face held
function dface.names(face)
  local sm = try(function() return face.SkeletalMesh end)
  local a = valid(sm) and try(function() return sm:GetAddress() end)
  if not a then return {}, 0 end
  if dface.known[a] then return dface.known[a].set, dface.known[a].n end
  local set, n = {}, 0
  try(function()
    sm.MorphTargets:ForEach(function(_, e)
      local m = e:get()
      local nm = valid(m) and try(function() return m:GetFName():ToString() end)
      if nm then set[nm], n = true, n + 1 end
    end)
  end)
  dface.known[a] = { set = set, n = n }
  return set, n
end
-- other faces on her: a skeletal mesh by her root's attach tree, not the face slot's, with the eyelid morphs (a CNS
-- head swap, TK_Scarlet_Head, puts its face mesh on a component of its own and hides hers: the dead face held on the
-- hidden one only, her eyes stayed open, user report). Held on all of them (on a hidden one it shows nothing)
local LIDS = { "upLid_down_L", "eyeBlinkLeft" }
function dface.others(pawn, face, need)
  local function addr(c) return try(function() return c:GetAddress() end) end
  local out, seen = {}, { [addr(face) or 0] = true }
  local SMC = StaticFindObject("/Script/Engine.SkeletalMeshComponent")
  local function walk(c, depth)
    local a = valid(c) and depth <= 8 and addr(c)
    if not a or seen[a] then return end
    seen[a] = true
    if try(function() return c:IsA(SMC) end) then
      local set = dface.names(c)
      for _, l in ipairs(LIDS) do if set[l] then out[#out + 1] = c; break end end
    end
    local kids = {}
    try(function() c.AttachChildren:ForEach(function(_, e) kids[#kids + 1] = e:get() end) end)
    for _, k in ipairs(kids) do walk(k, depth + 1) end
  end
  walk(try(function() return pawn.RootComponent end), 0)
  -- and every skeletal mesh off that tree she owns or that takes her body's pose (another mod's actor may own it: CNS's
  -- ModActor; second playtest with the head: her face slot was empty and none on her tree had the morphs, the dead
  -- face went on her body). Only then: FindAllOf walks every object (35-50 ms), a hitch on each death 0.3 s in
  if #out > 0 or not need then return out end
  local pa = addr(pawn)
  for _, c in ipairs(try(function() return FindAllOf("SkeletalMeshComponent") end) or {}) do
    local a = addr(c)
    if a and not seen[a] and dface.hers(pawn, c, pa) then
      seen[a] = true
      local set = dface.names(c)
      for _, l in ipairs(LIDS) do if set[l] then out[#out + 1] = c; break end end
    end
  end
  return out
end
-- one she owns, or posed off her body (its master pose her mesh)
function dface.hers(pawn, c, pa)
  local o = try(function() return c:GetOwner() end)
  if valid(o) and try(function() return o:GetAddress() end) == pa then return true end
  local m = try(function() return c.MasterPoseComponent:Get() end)
  local body = try(function() return pawn.Mesh end)
  return valid(m) and valid(body) and try(function() return m:GetAddress() == body:GetAddress() end) == true
end
-- what she wears, when no face with the morphs is found: each skeletal mesh she owns, its asset, morph count, shown
function dface.dump(pawn)
  local pa = try(function() return pawn:GetAddress() end)
  local out = {}
  for _, c in ipairs(try(function() return FindAllOf("SkeletalMeshComponent") end) or {}) do
    if dface.hers(pawn, c, pa) then
      local o = try(function() return c:GetOwner() end)
      local _, n = dface.names(c)
      local par = try(function() return c:GetAttachParent() end)
      out[#out + 1] = string.format("%s of %s (%s, %d morphs, %s, on %s)", name(c), name(o), name(try(function() return c.SkeletalMesh end)), n,
        try(function() return c:IsVisible() end) and "shown" or "hidden", valid(par) and name(par) or "nothing")
    end
  end
  log(string.format("face: no face with the morphs on her; her %d skeletal meshes: %s", #out, table.concat(out, "; ")))
end
function dface.start(pawn, mesh, why, hold)
  local df = (get_tune().gore or {}).deathFace or {}
  local gm = get_gore()
  local face = gm and gm.face_of and gm.face_of(pawn, mesh)
  if not valid(face) then face = mesh end
  local set, n = dface.names(face)
  -- another face on her (dface.others); one of them in the lead when the face slot's has none of the morphs
  local function lids(st) return st.upLid_down_L or st.eyeBlinkLeft end
  -- (the wide search only when her own face can't show it: none of the morphs, or hidden)
  local others = dface.others(pawn, face, not lids(set) or try(function() return face:IsVisible() end) == false)
  if not lids(set) and #others > 0 then
    face = table.remove(others, 1)
    set, n = dface.names(face)
  end
  if not lids(set) and not dface.dumped then
    dface.dumped = true
    dface.dump(pawn)
  end
  -- the mood: by weight, never the one before while there's another (Page Up: the next in turn)
  local moods, mood = df.moods or {}, nil
  if #moods > 0 then
    if hold then
      dface.turn = (dface.turn or 0) % #moods + 1
      mood = moods[dface.turn]
    else
      local sum = 0
      for i, m in ipairs(moods) do if i ~= dface.last or #moods == 1 then sum = sum + (m.weight or 1) end end
      local r = math.random() * sum
      for i, m in ipairs(moods) do
        if i ~= dface.last or #moods == 1 then
          r = r - (m.weight or 1)
          if r <= 0 or not mood then mood, dface.pick = m, i end
          if r <= 0 then break end
        end
      end
      dface.last = dface.pick
    end
  end
  -- this death's own: how far her eyes end up shut, where they drift, which way the jaw hangs
  local function rnd(a, b) return a + math.random() * (b - a) end
  local ls = df.lidsShut or { 1, 1 }
  local shut = rnd(ls[1] or 1, ls[2] or ls[1] or 1)
  local extra = {}
  local g = df.gaze or 0
  if g > 0 and not (mood and mood.noGaze) then
    local dirs = { { "eye_up_L", "eye_up_R" }, { "eye_down_L", "eye_down_R" }, { "eye_left_L", "eye_left_R" },
      { "eye_right_L", "eye_right_R" } }
    local d, a = dirs[math.random(#dirs)], rnd(0.3, 1) * g
    local over = rnd(2, 5)
    extra[#extra + 1] = { d[1], a, from = 0, over = over }
    extra[#extra + 1] = { d[2], a, from = 0, over = over }
  end
  -- a mood made for one side (mirror) is turned to the other half the time: _L/_R, _left/_right, Left/Right swapped
  local flip = mood and mood.mirror and math.random() < 0.5
  local function side_of(nm)
    if not flip then return nm end
    for _, sw in ipairs({ { "_L$", "_R" }, { "_R$", "_L" }, { "_left$", "_right" }, { "_right$", "_left" },
      { "Left$", "Right" }, { "Right$", "Left" } }) do
      if nm:find(sw[1]) then return (nm:gsub(sw[1], sw[2])) end
    end
    return nm
  end
  if (df.jawSide or 0) > 0 and not (mood and mood.mirror) then
    extra[#extra + 1] = { math.random() < 0.5 and "jaw_left" or "jaw_right", rnd(0, df.jawSide), from = 0, over = rnd(4, 8) }
  end
  local j = df.jitter or 0
  local function jit(x) return x and x * rnd(1 - j, 1 + j) end
  -- base, then the mood's, then this death's (a morph named again: the later entry)
  local list, shown, at = {}, {}, {}
  local function add(src, sided)
    for _, e in ipairs(src or {}) do
      local w = e[#e]
      for i = 1, #e - 1 do
        local nm = sided and side_of(e[i]) or e[i]
        if set[nm] then
          -- (from: its weight as the face comes on, easing to w over `over` s: her eyes half open closing, the
          -- grimace slackening)
          w = jit(w)
          if nm:find("^upLid_down") or nm == "eyeBlinkLeft" or nm == "eyeBlinkRight" then w = w * shut end
          local x = { FName(nm), math.min(1, w), nil, from = e.from and math.min(1, jit(e.from)), over = jit(e.over), name = nm }
          if at[nm] then list[at[nm]] = x else list[#list + 1], at[nm] = x, #list + 1 end
          break
        end
      end
    end
  end
  add(df.morphs); add(mood and mood.morphs, true); add(extra)
  for _, e in ipairs(list) do
    shown[#shown + 1] = e.from and string.format("%s %.2f>%.2f", e.name, e.from, e[2]) or string.format("%s %.2f", e.name, e[2])
  end
  if #list == 0 then
    local some = {}
    for k in pairs(set) do if #some < 40 then some[#some + 1] = k end end
    log(string.format("face (%s): none of deathFace.morphs on %s (%d morph targets: %s)", why, name(face), n,
      table.concat(some, " ")))
    return
  end
  dface.stop()
  local has = {}
  for _, e in ipairs(list) do has[e.name] = true end
  local faces = { face }
  for _, c in ipairs(others) do faces[#faces + 1] = c end
  dface.on = { face = face, faces = faces, list = list, set = set, has = has, extra = {}, t0 = os.clock(), fade = math.max(df.fade or 0.5, 0.01),
    till = hold and os.clock() + hold, mouth = df.mouthMax or {} }
  local more = {}
  for i = 2, #faces do more[#more + 1] = name(faces[i]) .. " (" .. name(try(function() return faces[i].SkeletalMesh end)) .. ")" end
  log(string.format("face (%s): %s, holding %d of her %d morph targets on %s%s: %s", why,
    mood and (mood.name .. (flip and " (mirrored)" or "")) or "no mood",
    #list, n, name(face) .. " (" .. name(try(function() return face.SkeletalMesh end)) .. ")", #more > 0 and (" and " .. table.concat(more, ", ")) or "", table.concat(shown, ", ")))
end
-- every tick: the weights again (the game resets the morph targets it drives, and the fade)
function dface.tick()
  local f = dface.on
  if not f then return end
  -- Every other poll: the weights ease on wall-clock curves over half a second or more, so a 66 ms step is
  -- invisible, while a death face writes a hundred or more morph targets a poll (an 89 ms spike, playtest).
  -- Expiry is checked on the same cadence; holding the final weights one poll longer is equally invisible.
  dface.n = (dface.n or 0) + 1
  if dface.n % 2 == 0 then return end
  if not valid(f.face) or (f.till and os.clock() >= f.till) then dface.stop(); return end
  local t = os.clock() - f.t0
  local k = math.min(1, t / f.fade)
  -- the convulsions' face over it (convulse.lua's poses, by morph target name): winces, gasps, tics, flutters
  local c = conv() or {}
  -- (the morphs dropping her mouth: at most deathFace.mouthMax, all added up; a sided one by its stem)
  local function most(m) return f.mouth[m] or f.mouth[m:gsub("_[%a]+$", "")] or 1 end
  for _, e in ipairs(f.list) do
    local w = e[2]
    if e.from and (e.over or 0) > 0 then
      local u = math.min(1, t / e.over)
      w = e.from + (w - e.from) * u * u * (3 - 2 * u)
    end
    w = math.max(0, math.min(most(e.name), w * k + (c[e.name] or 0)))
    for _, x in ipairs(f.faces) do try(function() x:SetMorphTarget(e[1], w, false) end) end
  end
  -- the ones the death face doesn't hold: set while a pose moves them, back to 0 after
  for m, x in pairs(f.extra) do
    if not c[m] then
      for _, y in ipairs(f.faces) do try(function() y:SetMorphTarget(x, 0, false) end) end
      f.extra[m] = nil
    end
  end
  for m, d in pairs(c) do
    if not f.has[m] and f.set[m] then
      f.extra[m] = f.extra[m] or FName(m)
      local x = f.extra[m]
      for _, y in ipairs(f.faces) do try(function() y:SetMorphTarget(x, math.max(0, math.min(most(m), d)), false) end) end
    end
  end
end
function dface.stop()
  local f = dface.on
  dface.on = nil
  if not (f and valid(f.face)) then return end
  for _, y in ipairs(f.faces) do
    if valid(y) then
      for _, e in ipairs(f.list) do try(function() y:SetMorphTarget(e[1], 0, true) end) end
      for _, x in pairs(f.extra or {}) do try(function() y:SetMorphTarget(x, 0, true) end) end
    end
  end
end
return dface
end
end
