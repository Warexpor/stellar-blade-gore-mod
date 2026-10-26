-- Realistic glass cannon mode (tune.glassCannon, off by default; Page Down turns it on and off in game). Only with
-- settings.lua's dev on.
-- While her shield is up a hit takes the shield, never HP. Once it is down, any hit kills her, cut where it landed
-- (along the weapon's swing when there was one). Her blows do damageMult times the damage.
-- The kill goes by her HUD's HP bar (ProgressBar_HP.Percent, which the game keeps live): the game's shield takes a
-- hit first, so the bar dropping at all is a hit with the shield down. That needs nothing found in memory; the
-- search for her stats went wrong in every playtest (twenty-second to thirty-second: none found, or a stranger's).
-- Her HP and shield live in native memory only, so sbslice.dll looks for them (the damage multiplier, the shield's
-- guard, a death the game takes as its own need them) (stats.c: anchored on what her HUD shows,
-- WB_MainHUD_PlayerInfo's HpValue, MaxHpValue, ShieldValue, MaxShieldValue; the game fills those only now and then,
-- so without them the search goes by her HP bar, ProgressBar_HP.Percent, which the game does keep live (of every
-- stats-shaped array, the ones whose HP / MaxHP reads what the bar shows) and by hits (the ones whose HP drops when
-- she is hit and holds still otherwise)) and, every tick, gives back HP a hit took
-- through the shield, multiplies what the enemies near her lose and tells this script about every hit on her
-- (sbslice.evt). Where a hit landed: the enemy weapon's last steps (main.lua's swing tracker) nearest a part of her,
-- else where her mesh says it was hit, else a part picked by weight.
local M = {}
local ctx, try, valid, log
local function cfg() return ctx.tune.glassCannon or {} end

local EVT = "ue4ss/Mods/StellarBladeGore/sbslice.evt"
local TOAST = "ue4ss/Mods/StellarBladeGore/spawner.cmd" -- sbslice.dll's window thread shows it as a fading note
local HUD = "WB_MainHUD_PlayerInfo_C"
local S_HP = 1

-- on: following her; found: the DLL knows where stats are; eve: her actor followed; foes: actor addr -> "ok" | "no"
local st = { on = false, found = false, nextFind = 0, eve = nil, foes = {}, nextFoes = 0, hud = nil, hudTry = 0, huds = 0,
  kill = nil, dying = nil, faked = false, enemyLogs = 0, shieldLogs = 0 }

function M.init(c)
  ctx = c
  try, valid, log = c.try, c.valid, c.log
end

function M.enabled()
  if not ctx.tune.dev then return false end -- a dev mode for now (settings.lua dev)
  local g = cfg()
  if st.override ~= nil then return st.override end
  return g.enabled == true
end

-- a note at the top of the screen that fades out by itself (sbslice.dll's spawner thread draws it)
local function toast(text)
  local f = io.open(TOAST, "w")
  if f then f:write("toast\t" .. text); f:close() end
end

-- Page Down
function M.toggle()
  st.override = not M.enabled()
  log("glass cannon " .. (st.override and "ON" or "OFF") .. " (Page Down; tune.glassCannon.enabled is the default)")
  toast(st.override and string.format("Glass cannon ON  (shield takes hits, then one hit kills; %gx damage)", cfg().damageMult or 8) or "Glass cannon OFF")
end

local function hex(o) return string.format("%x", try(function() return o:GetAddress() end) or 0) end
local function v(x, y, z) return { X = x or 0, Y = y or 0, Z = z or 0 } end

-- her HUD's numbers (the find's anchor): the live widget showing a MaxHP, found once a level and whenever it went.
-- FindFirstOf handed back the class default (Default__WB_MainHUD_PlayerInfo_C, all zeros) in the first playtest, so
-- every instance is looked at
local function num(w, k) local x = try(function() return w[k] end); return type(x) == "number" and x or nil end
local function hud_values()
  if not (valid(st.hud) and (num(st.hud, "MaxHpValue") or 0) > 0) then
    st.hud = nil
    -- the bar's widget found already and showing no MaxHP: nothing to look for (FindAllOf took 50 ms every 5 s, a
    -- hitch each time, thirty-second playtest)
    if valid(st.barHud) then
      if (num(st.barHud, "MaxHpValue") or 0) <= 0 then return nil end
      st.hud = st.barHud
    end
  end
  if not st.hud then
    if os.clock() < st.hudTry then return nil end
    st.hudTry = os.clock() + 5
    local all = try(function() return FindAllOf(HUD) end) or {}
    st.huds = #all
    for _, w in ipairs(all) do
      local name = try(function() return w:GetFullName() end) or ""
      if valid(w) and not name:find("Default__") then
        if not valid(st.barHud) and type(try(function() return w.ProgressBar_HP.Percent end)) == "number" then st.barHud = w end
        if (num(w, "MaxHpValue") or 0) > 0 then st.hud = w; break end
      end
    end
    if not st.hud then return nil end
  end
  local w = st.hud
  local hp, mhp, sh, msh = num(w, "HpValue"), num(w, "MaxHpValue"), num(w, "ShieldValue"), num(w, "MaxShieldValue")
  if not (hp and mhp and mhp > 0) then return nil end
  return hp, mhp, sh or 0, msh or 0
end

-- her HUD's HP bar (0..1): the one HUD value the game kept live in the twenty-sixth playtest (0.41 after a hit, while
-- HpValue and MaxHpValue stayed 0 and the text read "123 / 123")
-- cached: read only a widget already found, never look for one (the hit marks' reading while no mark waits)
local function bar_pct(cached)
  local function pct_of(w)
    local bar = try(function() return w.ProgressBar_HP end)
    local pct = valid(bar) and try(function() return bar.Percent end)
    return type(pct) == "number" and pct or nil
  end
  -- the widget showing it, kept: FindAllOf costs about 35 ms, looked for again at most every 5 s
  if valid(st.barHud) then
    local pct = pct_of(st.barHud)
    if pct then return pct end
  end
  st.barHud = nil
  if cached or os.clock() < (st.barTry or 0) then return nil end
  st.barTry = os.clock() + 5
  for _, w in ipairs(try(function() return FindAllOf(HUD) end) or {}) do
    local name = try(function() return w:GetFullName() end) or ""
    local pct = not name:find("Default__") and valid(w) and pct_of(w)
    if pct then st.barHud = w; return pct end
  end
  return nil
end

-- the bar's check: when it has held still (it may slide after a hit) at a reading that isn't full and is new, the
-- candidates whose HP / MaxHP reads it stay. Returns the DLL's answer, or nil when nothing was asked
local function bar_check(addr)
  local pct = bar_pct()
  local last = st.barLast
  st.barLast = pct
  if not (pct and pct > 0.005 and pct < 0.98 and last and math.abs(pct - last) < 0.002) then return nil end
  if st.barSent and math.abs(pct - st.barSent) < 0.005 then return nil end
  st.barSent = pct
  return ctx.gore.command(string.format("vd%s,3", addr), v(pct))
end

-- what her HUD widgets hold, for the log: the numbers, the HP bar, the HP text (which of them the game keeps filled)
local function hud_probe()
  local out = {}
  for _, w in ipairs(try(function() return FindAllOf(HUD) end) or {}) do
    local name = try(function() return w:GetFullName() end) or ""
    if not name:find("Default__") then
      local bar = try(function() return w.ProgressBar_HP end)
      local pct = valid(bar) and try(function() return bar.Percent end)
      local txt = try(function() return w.TextBlock_HPInfo:GetText():ToString() end)
      out[#out + 1] = string.format("hp %s/%s shield %s/%s bar %s text %q", tostring(num(w, "HpValue")), tostring(num(w, "MaxHpValue")),
        tostring(num(w, "ShieldValue")), tostring(num(w, "MaxShieldValue")), tostring(pct), tostring(txt))
    end
  end
  return " | HUD: " .. (#out > 0 and table.concat(out, "; ") or "none")
end

-- the search by hits (no HUD numbers): every stats-shaped array is a candidate; a quiet check (no hit for a while)
-- keeps those that held still, a check just after a hit keeps those whose HP dropped. The first hit lands as in the
-- vanilla game: it is what finds her stats
local function search(pawn)
  local now = os.clock()
  if now < (st.nextSearch or 0) then return end
  st.nextSearch = now + 0.25
  local gore, addr = ctx.gore, hex(pawn)
  if not st.cands or st.candsOf ~= addr then
    local r = gore.command("vs" .. addr)
    st.cands, st.candsOf, st.searchHit = tonumber(r:match("cands=(%d+)")) or 0, addr, (ctx.mesh_hit() or {}).t
    st.barSent = nil
    log("glass: searching her stats by her hits: " .. r)
    if st.cands == 0 then st.cands, st.nextSearch = nil, now + 5 end
    return
  end
  -- her HP bar, at most every 0.5 s (FindAllOf costs)
  if now >= (st.nextBar or 0) then
    st.nextBar = now + 0.5
    local r = bar_check(addr)
    if r then
      log(string.format("glass: her HP bar at %.3f: %s", st.barSent, r))
      if r:match("^ok") then
        st.found, st.cands = true, nil
        toast("Glass cannon: her HP found, on from now")
        return
      elseif not r:match("^more") then
        st.cands = nil
        return
      end
    end
  end
  local m = ctx.mesh_hit()
  local hit = m and m.t and m.t ~= st.searchHit and now - m.t >= 0.3
  if m and m.t and m.t ~= st.searchHit and not hit then return end -- a hit just now: its damage may not be in yet
  if not hit and m and m.t and now - m.t < 1.5 then return end
  if hit then st.searchHit = m.t end
  local r = gore.command(string.format("vd%s,%d", addr, hit and 1 or 0))
  if hit or not r:match("^more") then log("glass: " .. (hit and "after a hit: " or "quiet: ") .. r .. (hit and hud_probe() or "")) end
  if r:match("^ok") then
    st.found, st.cands = true, nil
    toast("Glass cannon: her HP found, on from now")
  elseif not r:match("^more") then
    st.cands = nil -- none left: noted again
  end
end

local function stop()
  if st.on and ctx.gore.state() == "ready" then ctx.gore.command("vz") end
  st.on, st.eve, st.foes, st.dying, st.kill = false, nil, {}, nil, nil
end

-- the parts of her a hit can land on: SWING_AT (main.lua) and the head
local function parts()
  local list = { { "Bip001-Head", 1.5 } }
  for _, e in ipairs(ctx.SWING_AT) do list[#list + 1] = e end
  return list
end
local function part_loc(mesh, e)
  return try(function()
    local x = mesh:GetSocketLocation(FName(e[1]))
    if not e[3] then return { X = x.X, Y = x.Y, Z = x.Z } end
    local y = mesh:GetSocketLocation(FName(e[3]))
    return { X = x.X + 0.4 * (y.X - x.X), Y = x.Y + 0.4 * (y.Y - x.Y), Z = x.Z + 0.4 * (y.Z - x.Z) }
  end)
end
local function class_of(bone)
  if bone:find("Head") or bone:find("Neck") then return "head" end
  if bone:find("Spine") or bone:find("Pelvis") then return "torso" end
  if bone:find("UpperArm") or bone:find("Forearm") or bone:find("Hand") then return "arm" end
  return "leg"
end

-- where the hit just now landed: { bone, at, h (a blow along the weapon's plane, for gore), src }
local function hit_part(pawn, mesh)
  local g = cfg()
  local sw, list = ctx.swing, parts()
  local hist = sw.hist or {}
  local best
  -- the weapon's steps over the last `swingBack` s that were fast enough: the one passing nearest a part
  for i = #hist, 2, -1 do
    local a, b = hist[i - 1], hist[i]
    if os.clock() - b.t > (g.swingBack or 0.45) then break end
    local dt = b.t - a.t
    for k = 1, #(sw.bones or {}) do
      local p, q = a.p[k], b.p[k]
      if p and q and dt > 1e-3 and ctx.dist(p, q) / dt >= ((ctx.tune.gore or {}).swingMinSpeed or 300) then
        for _, e in ipairs(list) do
          local l = part_loc(mesh, e)
          local d = l and ctx.seg_dist(p, q, l)
          if d and (not best or d < best.d) then best = { d = d, bone = e[1], at = l, p = p, q = q, i = i, k = k } end
        end
      end
    end
  end
  if best and best.d <= (g.reach or 60) then
    local dir = ctx.unit(ctx.sub(best.q, best.p))
    local fwd = try(function() local f = sw.actor:GetActorForwardVector(); return { X = f.X, Y = f.Y, Z = f.Z } end)
    local n
    local pa = hist[best.i - 2] and hist[best.i - 2].p[best.k]
    if pa then
      local u, w = ctx.sub(best.p, pa), ctx.sub(best.q, best.p)
      local c = ctx.cross(u, w)
      if ctx.len(c) > 0.2 * ctx.len(u) * ctx.len(w) then n = ctx.unit(c) end
    end
    if not n and dir and fwd then
      local c = ctx.cross(dir, fwd)
      if ctx.len(c) > 0.3 then n = ctx.unit(c) end
    end
    return { bone = best.bone, at = best.at, src = string.format("%s's weapon %.0f cm off", tostring(sw.who), best.d),
      h = { t = os.clock(), loc = best.at, dir = dir, fwd = fwd or dir, n = n, push = dir, attack_dir = 0, bone = best.bone, attacker = sw.who } }
  end
  -- where her mesh says it was hit
  local m = ctx.mesh_hit()
  if m and m.loc and os.clock() - m.t <= (g.meshHitWindow or 0.6) then
    local bd, bb, bl
    for _, e in ipairs(list) do
      local l = part_loc(mesh, e)
      local d = l and ctx.dist(l, m.loc)
      if d and (not bd or d < bd) then bd, bb, bl = d, e[1], l end
    end
    if bb then
      return { bone = bb, at = bl, src = string.format("her mesh's hit %.0f cm off", bd),
        h = { t = os.clock(), loc = bl, dir = m.push, fwd = m.push, push = m.push, attack_dir = 0, bone = bb } }
    end
  end
  -- nothing says where: a part by weight
  local sum = 0
  for _, e in ipairs(list) do sum = sum + e[2] end
  local r, pick = math.random() * sum, list[#list]
  for _, e in ipairs(list) do r = r - e[2]; if r <= 0 then pick = e; break end end
  local l = part_loc(mesh, pick)
  return { bone = pick[1], at = l, src = "made up", h = { t = os.clock(), loc = l, attack_dir = 0, bone = pick[1] } }
end

-- the bone to cut for an arm hit (nil: that arm is already gone)
local function arm_bone(mesh, bone)
  local side = bone:find("%-L%-") and "L" or "R"
  local up, fore = "Bip001-" .. side .. "-UpperArm", "Bip001-" .. side .. "-Forearm"
  if ctx.gore.has_cut(mesh, up) or ctx.gore.has_cut(mesh, fore) then return nil end
  return bone:find("UpperArm") and up or fore
end
local function leg_bone(mesh, bone)
  local side = bone:find("%-L%-") and "L" or "R"
  local up, low = "Bip001-" .. side .. "-Thigh", "Bip001-" .. side .. "-Calf"
  if ctx.gore.has_cut(mesh, up) or ctx.gore.has_cut(mesh, low) then return nil end
  return bone:find("Thigh") and up or low
end

-- the game's own stat and death calls: client RPCs on her controller (SBNetworkPlayerController), which a single-player
-- game runs locally. The game itself never sends them in single player, so what they do with these arguments is being
-- found out (the log says what the HP bar did after each)
local function game_call(pawn, fn, ...)
  local args = { ... }
  local pc = try(function() return pawn.Controller end)
  local g = try(function() return pawn.BroadcastSpawnInfo.ActorGuid end)
  if not (valid(pc) and g) then return "no controller or actor guid" end
  for i, a in ipairs(args) do if a == "guid" then args[i] = g end end
  local ok, err = pcall(function() pc[fn](pc, table.unpack(args)) end)
  return ok and string.format("sent (guid %d)", g) or tostring(err)
end
-- her MaxHP as the HUD's HP text shows it ("123 / 123"; the text is stale, its maximum isn't), or nil
local function text_mhp()
  local t = valid(st.barHud) and try(function() return st.barHud.TextBlock_HPInfo:GetText():ToString() end)
  return t and tonumber(t:match("/%s*([%d%.]+)"))
end

-- her shield, off the HUD: one widget per segment (WB_MainHud_Shield_N in HB_Shield_Slots, each a ProgressBar_Shield).
-- true while any shown segment holds some, false when none does, nil when the HUD has none to read
local function shield_up()
  local w = st.barHud
  if not valid(w) then return nil end
  -- the segments are their own widgets (WB_MainHud_Shield_C), not reachable as properties of the HUD's (none were,
  -- thirty-fourth playtest: "0 segments"): looked for among all of them, at most every 5 s while none are known
  local slots = {}
  for _, sl in ipairs(st.shieldSlots or {}) do if valid(sl) then slots[#slots + 1] = sl end end
  if #slots == 0 and os.clock() >= (st.shieldTry or 0) then
    st.shieldTry = os.clock() + 5
    for _, sl in ipairs(try(function() return FindAllOf("WB_MainHud_Shield_C") end) or {}) do
      local name = try(function() return sl:GetFullName() end) or ""
      if valid(sl) and not name:find("Default__") then slots[#slots + 1] = sl end
    end
    st.shieldSlots = slots
    if #slots > 0 then st.shieldLogged = nil end
  end
  local up, seen, desc = false, 0, {}
  for _, sl in ipairs(slots) do
    local pct = valid(sl) and try(function() return sl.ProgressBar_Shield.Percent end)
    if type(pct) == "number" then
      local shown = try(function() return sl:IsVisible() end) ~= false
      seen = seen + 1
      desc[#desc + 1] = string.format("%.2f%s", pct, shown and "" or " hidden")
      if shown and pct > 0.01 then up = true end
    end
  end
  if not st.shieldLogged then
    st.shieldLogged = true
    log(string.format("glass: her shield on the HUD: %d segments (%s)", seen, table.concat(desc, ", ")))
  end
  if seen == 0 then return nil end
  if up ~= st.shieldWas then log("glass: her shield " .. (up and "up" or "down") .. " (" .. table.concat(desc, ", ") .. ")") end
  st.shieldWas = up
  return up
end

-- any hit with the shield down: she dies now. Her HP goes to 0; if the game doesn't take that as a death within deathWait
-- seconds, the mod's own death runs (main.lua: ragdoll, the cut, up again after recoverAfter at full HP)
local function kill(pawn, mesh, part)
  local kind = class_of(part.bone)
  local bone
  if kind == "arm" then bone = arm_bone(mesh, part.bone) elseif kind == "leg" then bone = leg_bone(mesh, part.bone) end
  st.kill = { kind = kind, part = part, bone = bone, t = os.clock() }
  st.barSeen = nil
  os.remove(EVT) -- (a hit the DLL told of too: not taken again once she is up)
  local r
  if st.found then
    ctx.gore.command("vy0") -- no guard on the way down
    r = "HP to 0: " .. ctx.gore.command(string.format("vw%s,%x", hex(pawn), S_HP), v(0))
  else
    -- (ApplyStat's value read as the HP to set: 0. Read as a change, it does nothing, and ActorDead follows)
    r = "HP to 0 through the game's ApplyStat: " .. game_call(pawn, "ClientBroadcast_ActorApplyStat", 0, "guid", S_HP, 0, true, true, 0, 0)
  end
  -- the game's death, else its ActorDead call, else the mod's own death (tick)
  st.dying = { t = os.clock(), step = 0, pawn = pawn, mesh = mesh }
  log(string.format("glass: %s hit (%s) with the shield down: instant death, %s", kind, part.src, r))
end

local function on_hit(pawn, mesh, line)
  -- (a hit with her shield up never gets here: the DLL gave the HP back and told "guard")
  local part = hit_part(pawn, mesh)
  log(string.format("glass: %s; landed on %s (%s)", line, part.bone, part.src))
  kill(pawn, mesh, part)
end

-- her HP bar dropped since the last tick: a hit with the shield down (with it up, or within 0.8 s of a hit it took,
-- not). Not while the game is paused (a menu: gear
-- that raises her MaxHP lowers the bar's share); the reading after a pause starts over
local function bar_hit(pawn, mesh)
  if not valid(st.gs) then st.gs = try(function() return StaticFindObject("/Script/Engine.Default__GameplayStatics") end) end
  local gs = st.gs
  if valid(gs) and try(function() return gs:IsGamePaused(pawn) end) == true then st.barSeen = nil; return false end
  local pct = bar_pct()
  local last = st.barSeen
  st.barSeen = pct
  -- the shield as it was before this tick's reading (a hit that breaks it is still the shield's)
  local was = st.shieldUp
  st.shieldUp = shield_up()
  if not (pct and last and pct < last - (cfg().barDrop or 0.002)) then return false end
  if os.clock() - (st.guardT or -9) < 0.8 then return false end
  if was or st.shieldUp then
    -- the game lets part of a hit through the shield: given back (the shield takes it all)
    local mhp = text_mhp()
    local r = "no MaxHP on the HUD"
    if mhp and not st.found and cfg().shieldGuard ~= false then
      r = game_call(pawn, "ClientBroadcast_ActorApplyStat", 0, "guid", S_HP, last * mhp, true, true, 0, last * mhp)
      st.restore = { t = os.clock(), from = pct, to = last }
    end
    -- the bar slides down over a few ticks (1.000 -> 0.994, then 0.951): the rest of the slide is this hit's too
    st.guardT = os.clock()
    log(string.format("glass: her HP bar %.3f -> %.3f with her shield up: no death, HP given back (%s)", last, pct, r))
    return false
  end
  on_hit(pawn, mesh, string.format("her HP bar %.3f -> %.3f", last, pct))
  return true
end

-- the enemies near her: their losses multiplied (damageMult), each told to the DLL once
local function follow_foes(pawn)
  if os.clock() < st.nextFoes then return end
  st.nextFoes = os.clock() + 1
  local g = cfg()
  local mult = g.damageMult or 8
  if mult <= 1 then return end
  local here = try(function() local l = pawn:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
  if not here then return end
  local me = try(function() return pawn:GetAddress() end)
  for _, e in ipairs(ctx.live_chars()) do
    if e.addr ~= me and not st.foes[e.addr] and not ctx.ignored(e.cls) then
      local l = try(function() local x = e.obj:K2_GetActorLocation(); return { X = x.X, Y = x.Y, Z = x.Z } end)
      if l and ctx.dist(l, here) < (g.foeReach or 4000) then
        local r = ctx.gore.command(string.format("ve%x,%x", e.addr, math.floor(mult * 100 + 0.5)))
        st.foes[e.addr] = r:match("^ok") and "ok" or "no"
        if st.foes[e.addr] == "ok" then log(string.format("glass: %s takes %gx damage (%s)", e.cls, mult, r)) end
      end
    end
  end
end

local function read_events()
  local f = io.open(EVT, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  os.remove(EVT)
  return s
end

-- every tick she is alive and animated (main.lua)
M.bar_pct = bar_pct -- (main.lua: the hit marks heal with it)

function M.tick(pawn, mesh)
  if not M.enabled() then if st.on then stop(); log("glass cannon off") end return end
  local gore = ctx.gore
  if not gore or gore.state() ~= "ready" then return end
  if not st.on then st.on = true; log("glass cannon on: the shield takes the hits, with it down any hit kills, " .. (cfg().damageMult or 8) .. "x her damage") end
  -- her death on its way: the game's own, else the mod's
  if st.dying then
    local d, age, wait = st.dying, os.clock() - st.dying.t, cfg().deathWait or 0.3
    if d.step == 0 and age >= wait then
      d.step = 1
      log(string.format("glass: still up %.2f s on (HP bar %s): the game's ActorDead: %s", age, tostring(bar_pct(true)),
        game_call(pawn, "ClientBroadcast_ActorDead", 0, "guid", 0, 0, 0, 0, false, false)))
    elseif d.step == 1 and age >= 2 * wait then
      st.dying = nil
      st.faked = true
      log(string.format("glass: the game took neither as a death (HP bar %s): the mod's own death", tostring(bar_pct(true))))
      ctx.death(pawn, mesh)
    end
    return
  end
  -- a shield hit's HP given back: what the bar did (finding out what ApplyStat takes)
  if st.restore and os.clock() - st.restore.t >= 0.3 then
    log(string.format("glass: HP bar %.3f after giving back %.3f (wanted %.3f)", bar_pct(true) or -1, st.restore.from, st.restore.to))
    st.restore = nil
  end
  M.follow(pawn, mesh)
  if not st.dying then bar_hit(pawn, mesh) end
end

-- her stats in memory: looked for, then followed (the shield's guard, the enemies' multiplied losses, hits the DLL saw)
function M.follow(pawn, mesh)
  local gore = ctx.gore
  if not st.found then
    if os.clock() < st.nextFind then return end
    st.nextFind = os.clock() + 5
    local hp, mhp, sh, msh = hud_values()
    -- without them nothing is guessed (by shape alone, thousands of float runs look like stats): tried again in 5 s
    if not hp then
      if not st.hudLogged then
        st.hudLogged = true
        log(string.format("glass: no HUD numbers to find her stats by (%d %s, none showing a MaxHP yet): searching by her hits",
          st.huds or 0, HUD))
      end
      st.nextFind = 0
      search(pawn)
      return
    end
    local t0 = os.clock()
    local r = gore.command("vf" .. hex(pawn), v(hp or 0, mhp or 0, sh or 0), v(msh or 0))
    log(string.format("glass: her stats (HUD hp %s/%s shield %s/%s): %s (%.0f ms)", tostring(hp), tostring(mhp),
      tostring(sh), tostring(msh), r, (os.clock() - t0) * 1000))
    st.found = r:match("^ok") ~= nil
    if not st.found then return end
  end
  local addr = hex(pawn)
  if st.eve ~= addr then
    local r = gore.command(string.format("vy%s,%x", addr, cfg().shieldGuard == false and 0 or 1))
    if not r:match("^ok") then
      log("glass: following her failed (" .. r .. "), looking for her stats again")
      st.found = false
      return
    end
    st.eve = addr
  end
  -- the stats found must keep her HUD's maximums (its HP lags what the guard gives back, the game doesn't redraw it):
  -- three checks 2 s apart off them, and they are looked for again
  if os.clock() >= (st.nextCheck or 0) then
    st.nextCheck = os.clock() + 2
    local hp, mhp, _, msh = hud_values()
    local r = hp and gore.command("vr" .. addr) or ""
    local rmhp, rmsh = tonumber(r:match("maxhp=([%d.]+)")), tonumber(r:match("maxshield=([%d.]+)"))
    if hp and rmhp and rmsh then
      if math.abs(rmhp - mhp) > mhp * 0.01 + 1 or math.abs(rmsh - msh) > 0.5 then
        st.off = (st.off or 0) + 1
        if st.off >= 3 then
          log(string.format("glass: her stats read max %s HP %s shield, her HUD shows %s, %s: looking for them again",
            rmhp, rmsh, mhp, msh))
          st.found, st.off, st.eve = false, 0, nil
          gore.command("vy0")
          return
        end
      else st.off = 0 end
    end
  end
  follow_foes(pawn)
  gore.quiet("vt")
  local ev = read_events()
  if not ev then return end
  for line in ev:gmatch("[^\n]+") do
    local w = line:match("^(%a+)")
    if w == "hit" then
      on_hit(pawn, mesh, line)
      if st.dying then return end
    elseif w == "guard" then
      st.guardT = os.clock() -- (the bar may dip before the HP given back shows: not a hit)
      log("glass: " .. line .. " (the shield took it, HP given back)")
    elseif w == "shield" then
      if st.shieldLogs < 50 then st.shieldLogs = st.shieldLogs + 1; log("glass: " .. line) end
    elseif w == "enemy" then
      if st.enemyLogs < 50 then st.enemyLogs = st.enemyLogs + 1; log("glass: " .. line) end
    elseif w == "lost" then
      local a = tonumber(line:match("lost (%x+)"), 16)
      if a then st.foes[a] = nil end
      if string.format("%x", a or 0) == st.eve then st.eve = nil end
    end
  end
end

-- the death's cut (main.lua gore_cut): what glass decided, or where the killing blow landed; nil when off
function M.death_cut(pawn, mesh)
  if not M.enabled() then return nil end
  -- her stats still searched for: her HP is 0 now, the one sign that never goes unseen (her hits mostly did: the
  -- mesh's hit shake came 18 times in a whole log, and no hit was seen in a fight she died in, twenty-fifth
  -- playtest). This life went as in the vanilla game; the next ones have the mode
  if not st.found and st.cands and st.candsOf == hex(pawn) then
    -- her bar first: the twenty-sixth playtest's death left it at 0.044, her HP not 0 (nothing was at 0)
    local pct = bar_pct()
    if pct and pct > 0.005 and pct < 0.98 and not (st.barSent and math.abs(pct - st.barSent) < 0.005) then
      st.barSent = pct
      local r = ctx.gore.command(string.format("vd%s,3", hex(pawn)), v(pct))
      log(string.format("glass: at her death, her HP bar at %.3f: %s", pct, r))
      if r:match("^ok") then
        st.found, st.cands = true, nil
        toast("Glass cannon: her HP found, on from her next life")
      elseif not r:match("^more") then
        st.cands = nil
      end
    end
  end
  if not st.found and st.cands and st.candsOf == hex(pawn) then
    local r = ctx.gore.command(string.format("vd%s,2", hex(pawn)))
    log("glass: at her death: " .. r .. hud_probe())
    if r:match("^ok") then
      st.found, st.cands = true, nil
      toast("Glass cannon: her HP found, on from her next life")
    elseif not r:match("^more") and not r:match("kept") then
      st.cands = nil
    end
  end
  local k = st.kill
  st.kill, st.dying = nil, nil
  if k and os.clock() - k.t < 5 then return k end
  -- the game's own death (HP ran out): the finishing blow takes off what it landed on, a leg too
  local part = hit_part(pawn, mesh)
  local c = class_of(part.bone)
  local bone
  if c == "arm" then bone = arm_bone(mesh, part.bone) elseif c == "leg" then bone = leg_bone(mesh, part.bone) end
  return { kind = c, part = part, bone = bone, t = os.clock() }
end

-- the mod's own death is over and she is up: full HP again, followed again
function M.revived(pawn)
  st.barSeen = nil
  if not st.faked then return end
  st.faked = false
  local r = ctx.gore.command("vr" .. hex(pawn))
  local mhp = tonumber(r:match("maxhp=([%d.]+)"))
  if mhp then ctx.gore.command(string.format("vw%s,%x", hex(pawn), S_HP), v(mhp)) end
  st.eve = nil
  log("glass: up again after the mod's death, " .. (mhp and "HP back to " .. mhp or "HP as it was (her stats not found)"))
end

-- a new level: every actor is new (the stats' path stays)
function M.forget()
  if st.on and ctx.gore and ctx.gore.state() == "ready" then pcall(ctx.gore.command, "vz") end
  st.on, st.eve, st.foes, st.dying, st.kill, st.faked, st.hud, st.hudLogged = false, nil, {}, nil, nil, false, nil, false
  st.cands, st.candsOf, st.barLast, st.barSent, st.barHud, st.barTry, st.barSeen = nil, nil, nil, nil, nil, 0, nil
end

return M
