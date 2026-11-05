-- Background bone preparation and paced asset preloading.
return function(M, d, get_guards, get_ctx, get_pending)
local native, cfg, load_obj, log, command = d.native, d.cfg, d.load_obj, d.log, d.command
local POOL_DECALS, FX, SFX, vox = d.POOL_DECALS, d.FX, d.SFX, d.vox
local MPC_DIRTY, CAP_MATERIAL, STUB_MESH = d.MPC_DIRTY, d.CAP_MATERIAL, d.STUB_MESH
local nosink_list, nocarry_list, limbs_list, LIMB_ROOTS = d.nosink_list, d.nocarry_list, d.limbs_list, d.LIMB_ROOTS
-- her bones looked at while she plays, every WATCH_EVERY ticks: a stub's carrier must be a helper that held still
-- against its parent all along (sbslice "w"; an animation-driven corrective flung a thigh's stub about, twenty-fifth
-- playtest)
-- tm: main.lua's slow tick marker, each part named (a look held a frame 466-563 ms in the first minute with no asset
-- load over 15 ms, playtest)
-- gap: s between two preloads (each one 30-35 ms of the game thread: a sound a look, every 5 ticks, was 20 hitches in
-- a row, a stutter run, playtest)
M.watching = { every = 5, n = 0, gap = 0.5, at = 0 }
function M.watch(mesh, tm)
  local w = M.watching
  if cfg().enabled == false or native.state ~= "ready" then return end
  local try, valid = get_guards()
  if not valid(mesh) or M.busy() then return end
  local ctx = get_ctx()
  w.n = w.n + 1
  -- Pool creation can itself cost a frame. Run it on the poll after the bone scan, not alongside that scan and
  -- preload work; recheck all safety conditions because a cut or load may have started in between.
  if w.fillNext then
    w.fillNext = nil
    if not get_pending() and w.next and w.sounds and w.next >= w.sounds and not next(native.async.pending) then
      local owner = try(function() return mesh:GetOwner() end)
      if valid(owner) then M.pool_fill(owner) end
      if tm then tm("bone watch pool") end
      return
    end
  end
  local scan = w.n % w.every == 0
  tm = tm or function() end
  if scan then
    local r = command(string.format("w%x", mesh:GetAddress()))
    if r:sub(1, 2) ~= "ok" and not w.logged then w.logged = true; log("bone watch refused: " .. r) end
    tm("bone watch w")
  end
  -- and while she plays, the cuts' assets are loaded (and kept: native.root) one a look, so even the first cut
  -- loads nothing
  if not w.preload then
    local g, list = cfg(), {}
    -- floor blood first: every death needs it within seconds, while hit effects get exercised (and rooted)
    -- by combat anyway; a death in the first seconds used to pay a full object scan per pool
    for _, v in ipairs(POOL_DECALS) do list[#list + 1] = v end
    if M.niagaraBlood then for _, v in pairs(FX) do list[#list + 1] = v end end
    list[#list + 1] = M.SMASH_BLOOD
    -- (the sounds after the rest, and not in her first 30 s: loaded as the lobby came up, while the game's audio
    -- mixer was starting, its render thread crashed on a null lock, exe+0xb4b8817, on one launch in a few since
    -- 0.3.0 added her breaths and moans here, playtest)
    local sounds = {}
    for _, sets in pairs(SFX) do for _, set in ipairs(sets) do for _, v in ipairs(set) do sounds[#sounds + 1] = v end end end
    for _, v in ipairs(vox.DIE) do sounds[#sounds + 1] = v end
    -- Player-selected and character-specific recordings otherwise first load at the death or gasp.
    local voice = type(g.voice) == "table" and g.voice or {}
    local function add_voice(names)
      if type(names) ~= "table" then return end
      for _, path in ipairs(vox.list({ sounds = names })) do sounds[#sounds + 1] = path end
    end
    if type(voice.sounds) == "table" and #voice.sounds > 0 then add_voice(voice.sounds) end
    if voice.asHer ~= false and not (type(voice.sounds) == "table" and #voice.sounds > 0)
      and type(voice.as) == "table" then
      local owner = try(function() return mesh:GetOwner() end)
      local who = valid(owner) and M.looks_as(owner, mesh)
      local character = who and voice.as[who]
      if type(character) == "table" then
        for _, kind in ipairs({ "die", "breaths", "moans" }) do
          if type(character[kind]) == "table" and #character[kind] > 0 then add_voice(character[kind]) end
        end
      end
    end
    local cv = type(ctx.tune.convulse) == "table" and ctx.tune.convulse.voice
    if type(cv) == "table" and cv.enabled ~= false then
      for _, names in ipairs({ cv.breaths or {}, cv.moans or {} }) do
        for _, n in ipairs(names) do
          n = tostring(n)
          if n:sub(1, 1) ~= "/" then n = vox.DIR .. n:gsub("_VO$", "") .. "_VO" end
          if not n:find(".", 1, true) then n = n .. "." .. n:match("([^/]+)$") end
          sounds[#sounds + 1] = n
        end
      end
    end
    for _, v in ipairs(M.MARK_DECALS) do list[#list + 1] = v end
    for _, v in ipairs(M.MARK_SLASH) do list[#list + 1] = v end
    for _, v in ipairs({ MPC_DIRTY, g.capMaterial or CAP_MATERIAL, g.stubMesh or STUB_MESH }) do list[#list + 1] = v end
    if M.tachy() then list[#list + 1] = M.TACHY_MAT end
    if type(g.capMatte) == "table" and g.capMatte.enabled ~= false then
      list[#list + 1] = g.capMatte.material or M.matte.master
      for _, v in pairs(M.matte.tex) do list[#list + 1] = v end
    end
    -- (physfix's complete physics asset, kept too: an outfit missing main bodies worn as a level loads finds it while
    -- nothing may load, and a death in those first seconds ragdolls on it, Lemi21's Latex Nun)
    local pf = type(ctx.tune.physfix) == "table" and ctx.tune.physfix or {}
    if pf.enabled ~= false and pf.complete ~= false and pf.completeWith then list[#list + 1] = pf.completeWith end
    sounds[#sounds + 1] = vox.ATTENUATION
    local seen, unique = {}, {}
    for _, v in ipairs(list) do if not seen[v] then seen[v] = true; unique[#unique + 1] = v end end
    w.sounds = #unique + 1
    for _, v in ipairs(sounds) do if not seen[v] then seen[v] = true; unique[#unique + 1] = v end end
    w.preload, w.next, w.t0 = unique, 1, os.clock()
  end
  M.smashed.preload(w)
  tm("bone watch list")
  -- and her outfit's bone tree, 40 bones a look, then the cut's bone lists made from it, one a look (warm: nothing
  -- left to read when the cut comes)
  if scan then
    local t = M.bone_tree(mesh, 40)
    tm("bone watch tree")
    if t and (t.warm or 0) < 8 then
      t.warm = (t.warm or 0) + 1
      local k = t.warm
      if k == 1 then nosink_list(mesh) elseif k == 2 then nocarry_list(mesh) elseif k == 3 then limbs_list(mesh, nil)
      elseif k == 4 then M.driven_list(mesh) else limbs_list(mesh, LIMB_ROOTS[k - 4]) end
      tm("bone watch warm " .. k)
    end
    -- Pool actors wait until their assets and Lua wrappers are warm; their creation gets its own update.
    if w.next >= w.sounds and not next(native.async.pending) and #native.async.warm == 0 then w.fillNext = true end
    return -- Bone scans and warm-up never share an update with asset polling/loading.
  end
  if #native.async.warm > 0 then
    load_obj(table.remove(native.async.warm, 1))
    tm("bone watch cache")
    return
  end
  -- (the async ones in so far kept; one that never came in goes back to be loaded as before)
  if next(native.async.pending) and (w.asyncTurn ~= false or w.next > #w.preload) then
    for _, p in ipairs(native.async_poll(1) or {}) do w.late = w.late or {}; w.late[#w.late + 1] = p end
    w.asyncTurn = false
    tm("bone watch async")
    return
  end
  local path = w.preload[w.next]
  if path and w.next >= w.sounds and os.clock() - w.t0 < 30 then path = nil end
  -- Keep timed-out requests until the fallback actually runs; a closed load window or
  -- the pacing gap must not discard them. Service one before asking for more assets.
  local late = w.late and w.late[1] and os.clock() >= w.at and ctx.may_load() and w.late[1]
  if late then path = late end
  if path and native.rooted[path] then
    if late then table.remove(w.late, 1) else w.next = w.next + 1 end
  elseif path and not late and native.async.pending[path] then w.next = w.next + 1
  elseif path and not late and os.clock() >= w.at and ctx.may_load() and native.async_ready()
    and native.async_load(path, mesh) then
    w.next = w.next + 1
    w.asyncTurn = true
    tm("bone watch async ask")
  elseif path and os.clock() >= w.at and ctx.may_load() then
    if late then table.remove(w.late, 1) else w.next = w.next + 1 end
    w.at = os.clock() + w.gap
    local t0 = os.clock()
    load_obj(path)
    w.asyncTurn = true
    -- (a look held a frame 440-540 ms in the first minute, playtest: which asset)
    local ms = (os.clock() - t0) * 1000
    if ms >= (cfg().slowMs or 15) then log(string.format("cut asset load took %.0f ms: %s", ms, path)) end
    tm("bone watch load")
  end
  -- No request was eligible (the delayed sound section, for example): keep draining pending assets fairly.
  if next(native.async.pending) then w.asyncTurn = true end
  if w.next > #w.preload and not next(native.async.pending) and not (w.late and #w.late > 0) and not w.told then
    w.told = true
    local n = 0
    for _, ok in pairs(native.rooted) do if ok then n = n + 1 end end
    local a = native.async
    log(string.format("cut assets loaded and kept: %d of %d%s", n, #w.preload, a.asked > 0
      and string.format(" (%d by the async loader, %d late and loaded as before)", a.got, a.late) or ""))
  end
end

end
