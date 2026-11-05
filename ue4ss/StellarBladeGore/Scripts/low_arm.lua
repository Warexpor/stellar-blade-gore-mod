-- Low-health limb loss, restrictions, regrowth and recovery share lifecycle state on hm and screen.
return function(hm, screen, goreCtx, get_gore, settings, get_mesh_hit, weapon_swing, try, valid, dist, log)
hm.BLOCK_STANCE, hm.SWORD_LAB = "P_Eve_BlockSword", "^AltesLab"
function hm.stance_of(pawn) return try(function() return pawn:GetCurrentStanceName():ToString() end) end
function hm.level(pawn)
  local gs = goreCtx.statics()
  return valid(gs) and try(function() return gs:GetCurrentLevelName(pawn, true):ToString() end) or nil
end
function hm.sword_later_tick(pawn)
  local w = hm.swordLater
  if not w or not valid(pawn) then return end
  local st, lvl = hm.stance_of(pawn), hm.level(pawn)
  if st and st ~= hm.BLOCK_STANCE then
    hm.swordLater = nil
    log("low HP arm: out of the swordless stance (the game gave her sword back): nothing left to lift")
  elseif lvl and not lvl:find(hm.SWORD_LAB) then
    hm.swordLater = nil
    log("low HP arm: out of Altess Levoire (" .. lvl .. "): sword back (" .. tostring(select(2, pcall(goreCtx.tables.sword_gate, false))) .. ")")
  end
end
function hm.low_block(pawn, on, why)
  local gore = get_gore()
  local b = hm.lowBlock
  local a = valid(pawn) and try(function() return pawn:GetAddress() end)
  if on and hm.lowSide == "right" then
    if b or not a or not goreCtx.tables then return end
    if hm.swordLater then
      -- (ours still on, its end waiting: kept)
      hm.swordLater = nil
      hm.lowBlock = { pawn = a, sword = true }
      log("low HP arm: " .. why .. ": no sword (the stance still on)")
      return
    end
    local lvl = hm.level(pawn)
    if hm.stance_of(pawn) == hm.BLOCK_STANCE then
      hm.lowBlock = { pawn = a, sword = true, game = true }
      log("low HP arm: " .. why .. ": no sword already (the game's own block" .. (lvl and (", " .. lvl) or "") .. "): left to the game")
      return
    end
    hm.lowBlock = { pawn = a, sword = true, level = lvl }
    log("low HP arm: " .. why .. ": no sword (" .. tostring(select(2, pcall(goreCtx.tables.sword_gate, true))) .. ")")
    return
  end
  if not on and b and b.sword then
    hm.lowBlock = nil
    if b.game then log("low HP arm: " .. why .. ": the sword left to the game (its own block)"); return end
    local lvl = valid(pawn) and hm.level(pawn)
    -- (cut in it too, before the game took her sword there: its block came on over ours, and lifting ours lifted it)
    if lvl and lvl:find(hm.SWORD_LAB) and hm.stance_of(pawn) == hm.BLOCK_STANCE then
      hm.swordLater = { at = os.clock() }
      log("low HP arm: " .. why .. ": in Altess Levoire with no sword (the game's own block may be on too): " ..
        "the sword comes back as she leaves it, unless the game gives it back first")
      return
    end
    -- (its end fired whatever pawn she has now: a dispel of nothing does nothing)
    log("low HP arm: " .. why .. ": sword back (" .. tostring(select(2, pcall(goreCtx.tables.sword_gate, false))) .. ")")
    return
  end
  if on then
    if b or not a then return end
    b = { pawn = a, states = {} }
    hm.noticeKeys = nil
    local out = {}
    for _, st in ipairs(hm.LOW_STATES) do
      local r = gore.command(string.format("a%x,%x,1", a, st[2]))
      if r:match("^ok state") then b.states[#b.states + 1] = st[2] end
      out[#out + 1] = st[1] .. " " .. r
    end
    -- (and her gun's aim: its stances, ruled out by the shots' state)
    if goreCtx.tables then
      b.gate = true
      out[#out + 1] = "gun " .. tostring(select(2, pcall(goreCtx.tables.gun_gate, true)))
    end
    hm.lowBlock = b
    log("low HP arm: " .. why .. ": no heals or shots (" .. table.concat(out, "; ") .. ")")
    return
  end
  if not b then return end
  hm.lowBlock = nil
  -- (the skill table is the game's, not her pawn's: always put back)
  local gun = b.gate and goreCtx.tables and ("; gun " .. tostring(select(2, pcall(goreCtx.tables.gun_gate, false)))) or ""
  if a ~= b.pawn then log("low HP arm: " .. why .. ": its blocks went with her old pawn" .. gun); return end
  local out = {}
  for _, s in ipairs(b.states) do
    local r = gore.command(string.format("a%x,%x,0", a, s))
    -- (the game holding her at a life of 3-5 takes no take-off: cleared to 0 then, the game's own count with ours)
    local was, now = r:match("^ok state %d+ (%-?%d+) %-> (%-?%d+)")
    if was and tonumber(now) > 0 and now == was then r = r .. ", cleared: " .. gore.command(string.format("a%x,%x,3", a, s)) end
    out[#out + 1] = r
  end
  log("low HP arm: " .. why .. ": heals and shots back (" .. table.concat(out, "; ") .. gun .. ")")
end
-- lowArm.notice: her aim or a heal tried with the arm off (a key of her controller's TPSMode or Item_UseHeal mappings
-- going down, read when the blocks go on: a rebind shows at the next cut) answered by the game's own "Cannot use right
-- now." (UI_GetNotice_Fail_ActiveTpsMode, the line its refused aim shows) with its sound: sbslice U, the HUD's system
-- notice. At most once a second, not while the game is paused (a menu). The AZERTY layout's mappings are left out (its
-- heal key A is QWERTY's strafe left)
hm.NOTICE = "UStringTable_UI;UI_GetNotice_Fail_ActiveTpsMode"
function hm.low_notice(pawn)
  local gore, tune = get_gore(), settings()
  local la = (tune.gore or {}).lowArm or {}
  if la.notice == false then hm.noticeDown = nil; return end
  local gs = goreCtx.statics()
  local pc = valid(gs) and try(function() return gs:GetPlayerController(pawn, 0) end)
  if not valid(pc) then return end
  if not hm.noticeKeys then
    local keys, seen, names = {}, {}, {}
    try(function()
      pc.PlayerInput.ActionMappings:ForEach(function(_, e)
        local m = e:get()
        local act, key = m.ActionName:ToString(), m.Key.KeyName:ToString()
        local azerty = try(function() return m.bAZERTY end) == true
        if (act == "TPSMode" or act == "Item_UseHeal") and key ~= "None" and not azerty and not seen[key] then
          seen[key] = true
          keys[#keys + 1] = { KeyName = FName(key) }
          names[#names + 1] = act .. "=" .. key
        end
      end)
    end)
    if #keys == 0 then
      for _, k in ipairs({ "LeftControl", "Gamepad_LeftTrigger", "Q", "Gamepad_DPad_Up" }) do keys[#keys + 1] = { KeyName = FName(k) } end
      names[1] = "none read, the game's defaults"
    end
    hm.noticeKeys, hm.noticeDown = keys, {}
    log("low HP arm: 'Cannot use' notice on " .. table.concat(names, ", "))
  end
  -- (a key going down: polled, a tick may come later than the frame it was pressed in)
  local hit
  for i, k in ipairs(hm.noticeKeys) do
    local down = try(function() return pc:IsInputKeyDown(k) end) == true
    if down and not hm.noticeDown[i] then hit = true end
    hm.noticeDown[i] = down
  end
  local now = os.clock()
  if not hit or now - (hm.noticeAt or -10) < 1 then return end
  if try(function() return gs:IsGamePaused(pawn) end) == true then return end
  hm.noticeAt = now
  local r = gore.command(hm.NOTICE)
  if r ~= hm.noticeSaid then hm.noticeSaid = r; log("low HP arm: 'Cannot use' notice: " .. r) end
end
-- the parts grown back out of her (sbslice Z on every asset of hers with a part's bones: her body, an outfit's sleeve
-- or glove, her face and hair for a head), over lowArm.regrow s; each tick while they grow
function hm.low_regrow(pawn, mesh, T, parts)
  local comps = {}
  local cand = { mesh }
  try(function()
    for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.SkeletalMeshComponent"))) do cand[#cand + 1] = c end
  end)
  for _, part in ipairs(parts) do
    local jn, by = hm.GROW_JOINTS[part] or { part }, {}
    for _, c in ipairs(cand) do
      local sm = valid(c) and try(function() return c.SkeletalMesh:GetAddress() end)
      local i = sm and not by[sm] and try(function() return c:GetBoneIndex(FName(jn[1])) end)
      if i and i >= 0 then
        by[sm] = true
        local f = { try(function() return c:GetAddress() end), i }
        for k = 2, 3 do
          local j = jn[k] and try(function() return c:GetBoneIndex(FName(jn[k])) end)
          f[k + 1] = j and j >= 0 and j or 0xffff
        end
        if f[1] then comps[#comps + 1] = { c = c, f = f } end
      end
    end
  end
  if #comps == 0 then log("regrow: nothing of hers has the parts' bones: back at once"); return end
  hm.regrow = { t0 = os.clock(), T = T, comps = comps }
  log(string.format("regrow: %s growing back over %.1f s (%d meshes)", table.concat(parts, ", "), T, #comps))
  hm.grow_tick()
end
function hm.grow_tick()
  local gore = get_gore()
  local r = hm.regrow
  if not r then return end
  local x = math.min((os.clock() - r.t0) / r.T, 1)
  if x >= 1 then hm.grow_stop("grown"); return end
  local f = {}
  for _, c in ipairs(r.comps) do
    if valid(c.c) and try(function() return c.c:GetAddress() end) == c.f[1] then
      f[#f + 1] = string.format("%x,%x,%x,%x,%x", c.f[1], c.f[2], c.f[3], c.f[4], math.floor(x * 1000 + 0.5))
    end
  end
  -- (eight meshes a command: sbslice reads 40 fields) The first frame asks: the bones it set on each mesh, -1 where it
  -- couldn't read one (the arm came back at once with no growing seen, playtest)
  for i = 1, #f, 8 do
    local z = "Z" .. table.concat(f, ",", i, math.min(i + 7, #f))
    if r.asked then gore.fire(z) else log("regrow: first frame: " .. gore.command(z)) end
  end
  r.asked = true
end
-- every matrix put back: grown, or stopped (her death)
function hm.grow_stop(why)
  local gore = get_gore()
  if not hm.regrow then return end
  hm.regrow = nil
  gore.fire("Z")
  log("regrow: " .. why)
end
-- the parts dissolving back in (lowArm.dissolve, gore.ghost_begin: the cut stays on till they are in, then is undone);
-- each tick while they do. Done, stopped (her death, photo mode) or gone wrong: the ghost's copies away, the cuts undone
-- (once in: her own part back under the copy, which dissolves out over it in the last FADE_S, dissolve.fade)
hm.GHOST_FADE_S = 0.6
function hm.ghost_tick()
  local gore = get_gore()
  local h = hm.ghost
  if not h then return end
  if screen.photoLive or screen.vtPhoto then hm.ghost_stop("photo mode: back at once"); return end
  local now = os.clock()
  if h.handed then
    local y = (now - h.handed) / h.F
    if y >= 1 then hm.ghost_stop("dissolved in"); return end
    try(function() gore.ghost_fade(h.g, y) end)
    return
  end
  local x = math.min((now - h.t0) / h.T, 1)
  try(function() gore.ghost_set(h.g, x) end)
  if x < 1 then return end
  if h.F <= 0 then hm.ghost_stop("dissolved in"); return end
  -- (the cut undone under the copy, kept on: gore.ghost_release)
  try(function() gore.ghost_release(h.g) end)
  local ok, err = pcall(gore.cleanup, h.pawn, h.mesh)
  if not ok then log("regrow: cleanup under the copy: " .. tostring(err)) end
  h.handed, h.cleaned = now, true
end
function hm.ghost_stop(why)
  local gore = get_gore()
  local h = hm.ghost
  if not h then return end
  hm.ghost = nil
  if not h.handed then try(function() gore.ghost_set(h.g, 1) end) end
  local sk = try(function() return gore.ghost_end(h.g) end) or ""
  local ok, err = true, nil
  if not h.cleaned then ok, err = pcall(gore.cleanup, h.pawn, h.mesh) end
  log(string.format("regrow: %s %s after %.1f s%s%s", table.concat(h.parts, ", "), why, os.clock() - h.t0, sk,
    ok and "" or (", cleanup: " .. tostring(err))))
end
-- every part cut off her alive back: dissolving in (lowArm.dissolve.time s), else grown back (lowArm.regrow s) or at
-- once, the arm's blocks off
function hm.parts_back(pawn, mesh, why)
  local gore, tune = get_gore(), settings()
  local la = (tune.gore or {}).lowArm or {}
  -- (not while a cut still opens: its pieces aren't off yet, and the dissolve's copy took the wrong vertices, off
  -- where the arm was; the rest's sequence and the HP bar are read again next time)
  if gore.busy() then return end
  if hm.lowCut or hm.lowBlock then hm.lowCut = false; hm.low_block(pawn, false, why) end
  local parts = gore.cut_parts(mesh)
  if #parts == 0 then return end
  -- (back for good: nothing carried into a new level. hm.carry_note stops noting while they grow back, so a camp
  -- rest's level reload took the parts noted before it and cut them again on the new Eve, mid regrow)
  hm.carryParts, hm.carryBar, hm.carry = nil, nil, nil
  -- (its bodies stop simulating onto her pose, on her mesh: not on its copy)
  hm.piece_back("it grows back")
  log(string.format("regrow: %s: %s back", why, table.concat(parts, ", ")))
  -- (lowArm.effect false, F3's Regrow Effect: back at once)
  local fx = la.effect ~= false
  local d = la.dissolve
  local T = type(d) == "table" and tonumber(d.time) or (d == false and 0) or 3
  if fx and T > 0 then
    local ok, g, err = pcall(gore.ghost_begin, pawn, mesh, parts)
    if ok and g then
      local F = type(d) == "table" and tonumber(d.fade) or hm.GHOST_FADE_S
      hm.ghost = { g = g, t0 = os.clock(), T = T, F = F, pawn = pawn, mesh = mesh, parts = parts }
      log(string.format("regrow: %s dissolving back in over %.1f s", table.concat(parts, ", "), T))
      return
    end
    log("regrow: no dissolve (" .. tostring(ok and err or g) .. "): grown back instead")
  end
  try(function() gore.cleanup(pawn, mesh) end)
  if fx and (la.regrow or 1.5) > 0 then hm.low_regrow(pawn, mesh, la.regrow or 1.5, parts) end
end
-- a limb cut off her alive goes onto a copy of her mesh once it has lain still hm.STILL_S s (gore.hide_pieces, as
-- photo mode does), its bones hidden on her: grabbing a ladder, from the ground or in the air, drew her mesh on her
-- animation without its physics for a frame or two, and the cut-off arm was back on her shoulder for those frames
-- (Nexus report, 0.5.0). On the copy, not ticking, it lies where it fell whatever her mesh does. Limbs only (a head
-- takes her face and hair along, photo mode's). Back on her mesh as soon as anything needs it there: a cut, a regrow,
-- her death, an outfit change or an undo (gore.cleanup)
hm.STILL_S, hm.STILL_CM = 1.0, 2
function hm.piece_back(why)
  local gore = get_gore()
  local h = gore and gore.pieceHid
  hm.still = nil
  if not (h and h.baked) then return end
  local np, nr = gore.hide_pieces(nil, nil, false)
  log(string.format("piece settled: %d piece(s) back on her mesh, with %d part(s) riding them (%s)", np, nr, why))
end
function hm.piece_watch(pawn, mesh)
  local gore = get_gore()
  if not gore or not gore.hide_pieces then return end
  local h = gore.pieceHid
  if h and not h.baked then hm.still = nil; return end -- photo mode's
  local parts = gore.cut_parts(mesh, true)
  if #parts == 0 then hm.stillFailed = nil end
  local busy = gore.busy() or hm.regrow or hm.ghost
  if h then
    local same = valid(h.mesh) and h.mesh:GetAddress() == mesh:GetAddress() and #parts == #h.roots
    if busy or not same then hm.piece_back(busy and "a cut or a regrow" or "her cut parts changed") end
    return
  end
  if busy or #parts == 0 or screen.photoLive or screen.vtPhoto or screen.frozenMesh then hm.still = nil; return end
  -- (a copy that failed for these parts isn't tried again till they change)
  local key = string.format("%x %s", mesh:GetAddress(), table.concat(parts, ","))
  if hm.stillFailed == key then return end
  for _, b in ipairs(parts) do
    if b == "Bip001-Head" or b == "Bip001-Spine1" then hm.still = nil; return end
  end
  local now, a = os.clock(), mesh:GetAddress()
  local s = hm.still
  if not s or s.mesh ~= a or s.n ~= #parts then s = { mesh = a, n = #parts, at = {}, t = now }; hm.still = s end
  for _, b in ipairs(parts) do
    local v = try(function() local l = mesh:GetSocketLocation(FName(b)); return { X = l.X, Y = l.Y, Z = l.Z } end)
    if not v then hm.still = nil; return end
    local o = s.at[b]
    if not o or dist(v, o) > hm.STILL_CM then s.at[b], s.t = v, now end
  end
  if now - s.t < hm.STILL_S then return end
  hm.still = nil
  local t0 = os.clock()
  local np, nr = gore.hide_pieces(pawn, mesh, true, true)
  local h = gore.pieceHid
  -- (no copy: the piece stays on her mesh, as before, not hidden with nothing to show it)
  if not h or #h.copies == 0 then
    hm.stillFailed = key
    if h then gore.hide_pieces(nil, nil, false) end
    log("piece settled: no copy of her mesh for it, left on her mesh")
    return
  end
  log(string.format("piece settled: %d piece(s) onto a copy of her mesh, %d part(s) riding them, %.0f ms", np, nr,
    (os.clock() - t0) * 1000))
end
-- a camp rest: she sits down out of battle (her movement mode none, the camp's seat) with a part cut off her alive,
-- and then rests: the game's Camp_Restore sequence plays (the save, her heal, the enemies back), or her HP bar, under
-- full as she sat, is full within lowArm.restWindow s (the rest's heal; no heal item of hers does that with the arm
-- off). Any part: Lose Arm at Low HP's arm, and F9's. Sitting down alone grew them back as she sat, before the rest
-- (playtest: F9's come off at full HP, so the bar's check passed at once). The sequence is looked for (FindAllOf, 35
-- ms) once a second while she sits
hm.REST_SEQ = "Camp_Restore"
-- the camp's own chair: its sequence (Interaction_Camp_Chair) plays as she sits at a camp, not at another seat, and
-- the rest (the save, her heal, the enemies back) comes lowArm.restDelay (5) s later (playtest: her heal 5 s after
-- it both times), or as she gets up (Interaction_Camp_Chair_End). The game's save and zone reset were hooked on its
-- network controller first: never called through anything hookable (playtest), and the sequence's name read "?"
hm.CHAIR_SEQ, hm.CHAIR_END = "Interaction_Camp_Chair", "Interaction_Camp_Chair_End"
function hm.rest_seq()
  local seen = {}
  for _, a in ipairs(try(function() return FindAllOf("LevelSequenceActor") end) or {}) do
    local pl = valid(a) and try(function() return a.SequencePlayer end)
    if valid(pl) and try(function() return pl:IsPlaying() end) == true then
      -- (the player's sequence, else the actor's own LevelSequence path, else the actor's name)
      local sq = try(function() local q = pl:GetSequence(); return valid(q) and q:GetFullName() or nil end)
        or try(function() local q = a.LevelSequence.AssetPathName:ToString(); return q ~= "None" and q or nil end)
        or "?"
      local an = try(function() return a:GetFullName() end) or "?"
      seen[#seen + 1] = (sq:match("[^%.]+$") or sq) .. (sq == "?" and (" (" .. (an:match("[^%.:]+$") or an) .. ")") or "")
      if sq:find(hm.REST_SEQ, 1, true) or an:find(hm.REST_SEQ, 1, true) then return true, seen end
    end
  end
  return false, seen
end
goreCtx.rest_seq = hm.rest_seq
function hm.rest_watch(pawn, mesh)
  local gore, tune = get_gore(), settings()
  -- (not in photo mode or a pause: photo mode stops her movement too, and the pieces sit on their copy)
  if not gore or (tune.gore or {}).enabled == false or hm.regrow or hm.ghost or gore.busy()
    or (gore.pieceHid and not gore.pieceHid.baked) or screen.photoLive
    or screen.vtPhoto or screen.frozenMesh then
    hm.restAt, hm.restSeat = nil, false
    return
  end
  local parts = gore.cut_parts(mesh)
  if #parts == 0 then hm.restAt, hm.restSeat = nil, false; return end
  local now = os.clock()
  local seated = try(function() return pawn.CharacterMovement.MovementMode end) == 0
    and try(function() return pawn:IsBattle() end) ~= true
  local pct = goreCtx.glass and goreCtx.glass.bar_pct(false)
  if seated then
    if not hm.restSeat then
      hm.restPct, hm.restSeqAt, hm.restSeqSeen, hm.restChair = pct, 0, {}, nil
      log(string.format("regrow: she sat down out of battle with %s off, her HP bar %s (a camp rest?)",
        table.concat(parts, ", "), pct and string.format("%.3f", pct) or "?"))
    end
    hm.restAt = now
  end
  hm.restSeat = seated
  local la = (tune.gore or {}).lowArm or {}
  if not hm.restAt or now - hm.restAt > (la.restWindow or 20) then return end
  -- at the camp's chair restDelay s, or up from it
  local ch = hm.restChair
  if ch and (ch.up or now - ch.t >= (la.restDelay or 5)) then
    hm.restAt, hm.restChair = nil, nil
    hm.parts_back(pawn, mesh, ch.up and "a camp rest (up from the camp's chair)"
      or string.format("a camp rest (%.0f s at the camp's chair)", now - ch.t))
    return
  end
  -- her heal: the bar under full as she sat, full now
  if pct and pct >= 0.99 and hm.restPct and hm.restPct < 0.99 then
    hm.restAt = nil
    hm.parts_back(pawn, mesh, string.format("a camp rest (her HP bar %.3f -> %.3f)", hm.restPct, pct))
    return
  end
  if now < (hm.restSeqAt or 0) then return end
  hm.restSeqAt = now + 1
  local rest, seen = hm.rest_seq()
  -- (each sequence seen playing logged once: the rest's own, if its name isn't Camp_Restore)
  for _, n in ipairs(seen) do
    if not hm.restSeqSeen[n] then hm.restSeqSeen[n] = true; log("regrow: sequence playing as she sits: " .. n) end
    if n == hm.CHAIR_SEQ and not hm.restChair then hm.restChair = { t = now } end
    if n == hm.CHAIR_END then hm.restChair = hm.restChair or { t = now }; hm.restChair.up = true end
  end
  if not rest then return end
  hm.restAt = nil
  hm.parts_back(pawn, mesh, "a camp rest (" .. hm.REST_SEQ .. " playing)")
end
-- her death's end, a load (recover): the arm back with every other cut, the blocks off (the game's own respawn may
-- clear them first: a take-off of none is no change)
function screen.low_reset(pawn, why)
  if hm.regrow then hm.grow_stop(why) end
  if hm.ghost then hm.ghost_stop("back at once: " .. why) end
  if hm.lowCut or hm.lowBlock then log("low HP arm: " .. why .. ": back") end
  hm.lowCut, hm.restAt, hm.lowLast, hm.lowPend = false, nil, nil, nil
  if hm.lowBlock then hm.low_block(pawn, false, why) end
end
function hm.low_arm(pawn, mesh)
  local gore, tune, meshHit = get_gore(), settings(), get_mesh_hit()
  hm.grow_tick()
  hm.ghost_tick()
  -- (her arm cut again on a new Eve first: till then it reads as back, and the arm was taken for grown back)
  if hm.carry and not hm.carry.cut then return end
  if hm.swordLater then hm.sword_later_tick(pawn) end
  local g = tune.gore or {}
  local la = g.lowArm or {}
  local on = gore and g.enabled ~= false and la.enabled == true
  if not on then
    hm.lowLast, hm.lowPend = nil, nil
    -- (turned off in the menu with the arm off: it comes back at the next rest or life as it would, blocks off now)
    if hm.lowBlock then hm.low_block(pawn, false, "Lose Arm at Low HP off") end
    return
  end
  local now = os.clock()
  -- the blocks follow the menu's switch while the arm is off
  local right = hm.lowSide == "right"
  local block = hm.lowCut and (right and la.noSword ~= false or not right and la.noHealGun ~= false)
  if block and not hm.lowBlock then hm.low_block(pawn, true, "her " .. hm.lowSide .. " arm is off")
  elseif not block and hm.lowBlock then
    hm.low_block(pawn, false, hm.lowCut and (right and "No Sword off" or "No Heals or Gun off") or "the arm is back")
  end
  if hm.lowBlock and not hm.lowBlock.sword then hm.low_notice(pawn) end
  if not goreCtx.glass then return end
  -- (the HUD looked for at most every 5 s till found, 35 ms: glass.lua keeps it)
  local pct = goreCtx.glass.bar_pct(false)
  if not pct then return end
  local last = hm.lowLast
  hm.lowLast = pct
  -- a new bar (a new level, a level gone into: Altess Levoire) reads full till the game sets it, after its cutscene:
  -- full to her low HP read as a blow, and the arm that came back with the new level came off again, sound and all
  -- (reported). A new bar's first move down from full with no hit on her mesh is the game setting it, not a blow
  local bid = goreCtx.glass.bar_id and goreCtx.glass.bar_id()
  if bid ~= hm.lowBarId or (goreCtx.levelAt or -1) ~= hm.lowLevelAt then
    hm.lowBarId, hm.lowLevelAt, hm.lowBarSync = bid, goreCtx.levelAt or -1, true
  end
  -- (judged by nothing while it reads full: its healBack neither; the arm back with the level still seen below)
  local syncing = false
  if hm.lowBarSync then
    if pct >= 0.999 then
      syncing = true
    else
      hm.lowBarSync = false
      if last and last >= 0.999 and not (meshHit and now - meshHit.t < hm.LOW_HIT_S + 0.5) then
        syncing = true
        log(string.format("low HP arm: a new HP bar went from full to %.3f: the game setting it, not a blow", pct))
      end
    end
    if syncing then hm.lowPend = nil end
  end
  if hm.lowCut then
    -- (a camp rest: hm.rest_watch) lowArm.healBack: her HP back up to healAt any way at all (gear that heals on
    -- kills, over time)
    -- (at least 1% over the mark it came off under: a mark over healAt grew it back the tick after the cut)
    local at = math.max(la.healAt or 0.9, (la.below or 0.25) + 0.01)
    -- (and only once the bar was under it since the cut, the cut done: the test keys cut at full HP, and the arm and
    -- her sword were back the same tick, the dissolve begun on a cut still opening, on the wrong vertices; playtest)
    if pct < at and not syncing then hm.lowUnder = true end
    if la.healBack == true and not syncing and pct >= at and hm.lowUnder and now - (hm.lowT or 0) > 3 and not gore.busy() then
      hm.parts_back(pawn, mesh, string.format("her HP bar back at %.3f (healBack, %.2f)", pct, at))
    -- (undone by something else: a lethal hit she lived through, F8. Not while the cut still opens)
    elseif now - (hm.lowT or 0) > 3 and not gore.busy() and not gore.has_cut(mesh, hm.LOW_BONES[hm.lowSide]) then
      hm.lowCut = false
      hm.low_block(pawn, false, "the arm came back with the other cuts")
    end
    return
  end
  if syncing then return end
  if hm.regrow or hm.ghost then hm.lowPend = nil; return end
  -- a hit (the bar dropped since the last tick) that she lives through, leaving her under the mark. The bar slides
  -- down after a hit: a fall damage death read 0.499 -> 0.066 on its way to 0, the arm came off on the killing
  -- blow, and the cut opening as the death began kept the death from being seen (no ragdoll, the death screen at
  -- once; playtest). The cut waits till the bar has held still for SETTLE s above 0
  local p = hm.lowPend
  if not p then
    if not (last and pct < last - 0.002 and pct < (la.below or 0.25)) then return end
    local ws = weapon_swing(mesh)
    hm.lowPend = { from = last, t = now, t0 = now, dir = ws and ws.dir, at = ws and ws.at }
    return
  end
  if pct >= (la.below or 0.25) then
    log(string.format("low HP arm: her HP bar %.3f -> %.3f: back over the mark, not cut", p.from, pct))
    hm.lowPend = nil
    return
  end
  if pct ~= last then p.t = now; return end
  -- the bar reads 0 at about 1 % shown (a fall left her alive there, playtest): at 0 it waits LOW_ZERO_S for her
  -- death to start (her death's tick doesn't come here; screen.low_reset drops the wait)
  if now - p.t < (pct <= 0.0005 and hm.LOW_ZERO_S or hm.LOW_SETTLE) then return end
  hm.lowPend = nil
  -- a blow, not a fall: a drop as she lands (a drop of LOW_LAND_CM or more, LOW_LAND_S around it) with no hit on her
  -- mesh (the game's physical hit reaction) is the landing's damage. Any other drop is a blow: the physical hit
  -- reaction alone missed most of them (ranged hits, grabs, explosions; Nexus: under 70% it came off now and then)
  local struck = meshHit and meshHit.t >= p.t0 - hm.LOW_HIT_S
  local land = hm.landAny
  if not struck and land and math.abs(land.t - p.t0) < hm.LOW_LAND_S then
    log(string.format("low HP arm: her HP bar %.3f -> %.3f as she landed from a %.0f cm drop, no hit on her mesh: fall damage, not cut",
      p.from, pct, land.drop))
    return
  end
  if gore.busy() then return end
  -- (lowArm.side "hit", the default: the side of her the blow landed on, the mesh's hit bone or where it landed, else
  -- the weapon's sweep; one at random when it landed on her middle or nothing tells. "either": one at random. Either
  -- way the other one when that one is already off, F9's)
  local side, how = la.side, nil
  if side ~= "left" and side ~= "right" and side ~= "either" then
    local m = struck and meshHit or nil
    side, how = gore.hit_side(mesh, m and m.loc or p.at, m and m.bone)
    how = side and ("the blow landed " .. how) or ("no side to the blow (" .. how .. "), at random")
  end
  if side ~= "left" and side ~= "right" then side = math.random(2) == 1 and "left" or "right" end
  if la.side ~= "left" and la.side ~= "right" and gore.has_cut(mesh, hm.LOW_BONES[side]) then side = side == "left" and "right" or "left" end
  hm.low_cut(pawn, mesh, side, p.dir, string.format("her HP bar %.3f -> %.3f (held %.2f s), under %.2f%s", p.from, pct,
    hm.LOW_SETTLE, la.below or 0.25, how and (", " .. how) or ""))
end
-- the arm off (side "left" or "right"), along dir when given, with its blocks: the low HP hit's, and the test keys'
function hm.low_cut(pawn, mesh, side, dir, why)
  local gore, tune = get_gore(), settings()
  local la = (tune.gore or {}).lowArm or {}
  if gore.has_cut(mesh, hm.LOW_BONES[side]) or gore.busy() then return end
  if dir then gore.aim(dir) end
  local ok, r = pcall(gore.slice_bone, pawn, mesh, hm.LOW_BONES[side], nil, "low HP")
  hm.lowCut = ok and r and true or false
  if hm.lowCut then
    hm.lowT, hm.restAt, hm.lowSide, hm.lowLast, hm.lowPend, hm.lowUnder = os.clock(), nil, side, nil, nil, false
  end
  log(string.format("low HP arm: %s: %s", why,
    not ok and ("failed: " .. tostring(r)) or r and ("her " .. side .. " arm cut off") or "not cut"))
  if hm.lowCut and (side == "right" and la.noSword ~= false or side == "left" and la.noHealGun ~= false) then
    hm.low_block(pawn, true, "her " .. side .. " arm is off")
  end
end
end
