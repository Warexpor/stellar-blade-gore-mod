-- Death and revive screen state, hooks, timing and transitions.
return function(screen, goreCtx, dead_hud, death_screen, valid, try, log, get_active, get_manual, get_tune, get_pawn, get_elapsed)
-- the death screen's animations playing now (its intro as the game puts it up), by name
function screen.playing(w)
  local out = {}
  local cls = valid(w) and try(function() return w:GetClass() end)
  if not cls then return out end
  try(function()
    cls.Animations:ForEach(function(_, e)
      local a = e:get()
      if valid(a) and try(function() return w:IsAnimationPlaying(a) end) == true then
        out[#out + 1] = tostring(try(function() return a:GetFName():ToString() end))
      end
    end)
  end)
  return out
end
local SCREEN_FNS = { WB_Common_btn_1_Event_0 = "press", WB_Common_btn_2_Event_0 = "press", WB_Common_btn_1_Event = "press",
  WB_Common_btn_2_Event = "press", FinishPressAnimation = "press", FinishYouDieAnimation = "shown" }
function screen.reset() dead_hud.scans, dead_hud.made, dead_hud.found, screen.rv.shown = 0, nil, nil, nil; screen.seen, screen.vis, screen.gone, screen.press, screen.respawn, screen.revived, screen.last = false, false, false, false, false, false, nil; screen.frozen, screen.shown, screen.hpZero, screen.hpBack, screen.photoTook = false, false, false, 0, nil; screen.offSince, screen.shownAt, screen.introSound = nil, nil, nil end
-- the death and revive screens kept hidden t s into the death: held (Shift+F4, photo mode), else as tune.deathScreen
-- says: "game" when the game puts them up (at once), "delay" till tune.reviveAt s, "key" till Shift+F4 (or the pad
-- combo) shows them. Customized Ragdoll support (tune.customizedRagdoll) puts them up as the game does, see-through
-- (screen.revive)
function screen.hiding(t)
  local tune = get_tune()
  if screen.frozen then return true end
  if screen.shown then return false end
  if goreCtx.customrag and goreCtx.customrag.active() then return false end
  local m = tune.deathScreen
  if m == "game" then return false end
  if m == "key" then return true end
  return t < (tune.reviveAt or 10)
end
-- one hook a call, a second apart: all four in one tick were a 206-213 ms freeze while she played, once a session
-- (playtest); hook = { left = { [f] = what }, got = {} }
function screen.hook()
  if screen.hooked or os.clock() < (screen.retry or 0) then return end
  screen.retry = os.clock() + 1
  local hk = screen.hookQ
  -- The class lookup traverses the object array. Once found, keep a lifetime-checked reference for the remaining
  -- hook registrations; if it went away, look it up again before trying the next function.
  local heldClass = hk and hk.class and goreCtx.held(hk.class)
  local cls = heldClass and hk.class.obj
  if not cls then cls = try(function() return StaticFindObject("/Game/Art/UI/Widget/HUD/WB_MainHUD_Dead.WB_MainHUD_Dead_C") end) end
  if not valid(cls) then if hk then hk.class = nil end; return end
  if not hk then
    hk = { left = {}, got = {} }
    for f, what in pairs(SCREEN_FNS) do hk.left[f] = what end
    screen.hookQ = hk
  end
  if not heldClass then
    hk.class = goreCtx.keep(cls)
    if hk.class and not goreCtx.held(hk.class) then hk.class = nil end
  end
  local f, what = next(hk.left)
  if f then
    hk.left[f] = nil
    local ok = pcall(RegisterHook, "/Game/Art/UI/Widget/HUD/WB_MainHUD_Dead.WB_MainHUD_Dead_C:" .. f, function()
      -- (any time: a death the mod never saw is told by it, hm.dead_proof)
      if what == "shown" then screen.youDieAt = os.clock() end
      if not get_active() then return end
      if what == "shown" then
        if not screen.seen then log("death screen: " .. f) end
        screen.seen = true
      else
        if not screen.press then log("death screen: " .. f) end
        screen.press = true
      end
    end)
    if ok then hk.got[#hk.got + 1] = f end
    if next(hk.left) then return end
  end
  screen.hooked = true
  table.sort(hk.got)
  log("hook death screen: " .. (#hk.got > 0 and table.concat(hk.got, ", ") or "none"))
end
-- may she be got up now (her ragdoll has run recoverAfter): a button pressed, the screen gone, or no screen at all
-- recoverAfter + screenWait s in (a death without one: F5's)
function screen.ready(t)
  local tune = get_tune()
  if tune.recoverOn ~= "button" or screen.press or screen.gone then return true end
  -- the revive screen held or up: she waits for the player's choice
  local rv = screen.rv
  if rv.shown and not rv.down then return false end
  for _, v in pairs(rv.held or {}) do if v ~= false then return false end end
  return not screen.seen and t >= (tune.recoverAfter or 10) + (tune.screenWait or 4)
end
-- the revive item's screen: with one on her the game puts its death screen up the moment she dies, over her death
-- (playtest; without one it fades in at about 7 s). Whichever screen is up before tune.reviveAt s into the death (the
-- death screen, or WB_MainHUD_ResurrectionItem should that be it) is held hidden and off till then. Taken down after
-- it showed (the item used or not) with no death screen up REVIVE_WAIT s later, she was revived and is got up at
-- once (`revive screen: ...` in the log)
screen.rv = {}
screen.SHOWN_S, screen.GONE_S = 1.5, 0.75
local REVIVE_WAIT = 2.5
function screen.revive(t)
  local tune = get_tune()
  local rv = screen.rv
  screen.intro_look()
  screen.fade_in()
  if not get_active() or get_manual() then
    for f, vis in pairs(rv.held or {}) do
      local w = vis and dead_hud.get(f)
      if w then try(function() w:SetVisibility(vis); w:SetIsEnabled(true) end) end
    end
    for _, w in pairs(rv.ghost or {}) do if valid(w) then try(function() w:SetRenderOpacity(1) end) end end
    rv.held, rv.up, rv.down, rv.told, rv.ghost = nil, nil, nil, nil, nil
    return
  end
  if dead_hud.made and not rv.told then
    rv.told = true
    log(string.format("revive screen: made %.1f s into the death: %s", t, dead_hud.made))
  end
  local on = false
  for _, f in ipairs({ "w", "rv" }) do
    -- (the death screen looked for by class from 1 s in when not caught as it was made: the fall's first second is
    -- busy. The revive item's is made in the death, always caught)
    local w = dead_hud.get(f, f == "w" and t >= 1)
    if w then
      local vis = try(function() return w:GetVisibility() end) or 1 -- 1 collapsed, 2 hidden
      local up = vis ~= 1 and vis ~= 2 and try(function() return w:IsVisible() end) ~= false
      rv.held = rv.held or {}
      if screen.hiding(t) then
        if up then
          if not rv.held[f] then
            rv.held[f] = vis
            log(string.format("revive screen: %s up %.1f s into the death, held hidden %s",
              tostring(try(function() return w:GetClass():GetFName():ToString() end)), t,
              screen.frozen and "while the death is held (Shift+F4)" or tune.deathScreen == "key" and "till Shift+F4"
              or string.format("till %.0f s", tune.reviveAt or 10)))
          end
          try(function() w:SetVisibility(1); w:SetIsEnabled(false) end)
        end
      elseif rv.held[f] ~= nil and rv.held[f] ~= false then
        try(function() w:SetVisibility(rv.held[f]); w:SetIsEnabled(true) end)
        rv.held[f], up = false, true
        rv.shown, screen.shownAt = true, os.clock()
        log(string.format("revive screen: shown %.1f s into the death%s", t, screen.skip_intro(w)))
        if screen.shown == true then
          try(function() w:SetRenderOpacity(0) end)
          screen.fade = { w = w, t = os.clock() }
        end
      end
      -- Customized Ragdoll support, as that mod has it: the screen up as the game puts it but see-through, its keys
      -- (F / R) working, no holding needed; Shift+F4 shows it (fading in), and once shown holds the death as ever
      if up and goreCtx.customrag and goreCtx.customrag.active() and not screen.frozen then
        rv.ghost = rv.ghost or {}
        if not screen.shown then
          if not rv.ghost[f] then
            rv.ghost[f] = w
            log(string.format("death screen: %s up %.1f s into the death, see-through (Customized Ragdoll support), its keys working",
              tostring(try(function() return w:GetClass():GetFName():ToString() end)), t))
          end
          try(function() w:SetRenderOpacity(0) end)
        elseif rv.ghost[f] then
          rv.ghost[f] = nil
          screen.fade = { w = w, t = os.clock() }
          log(string.format("death screen: shown %.1f s into the death", t))
        end
      end
      on = on or up
    end
  end
  -- held (Shift+F4): the screens hidden by the mod don't count as gone
  if not rv.shown or screen.frozen then return end
  if on then rv.up, rv.down = true, nil
  elseif rv.up and not rv.down then rv.down = t; log(string.format("revive screen: gone %.1f s into the death", t))
  elseif rv.down and not screen.revived and t - rv.down >= REVIVE_WAIT and not death_screen() then
    screen.revived = true
  end
end
-- a screen shown after being held hidden: its intro (the death screen's You Die, 3.98 s) doesn't run while it is
-- collapsed, so it played from its start once shown: 2-3 s after Shift+F4 before anything showed (playtest). Put at
-- its end it popped up with no animation; sped up it was no longer the game's (playtest). So shown by Shift+F4, it
-- plays at the game's own speed from INTRO_FROM s in, past its lead-in (a guess, read from the log's opacity
-- samples below). Returns a note for the log
screen.INTRO_FROM = 2.0
-- and as its intro is half in by then (the opacity samples: 5 of 10.9 at 2 s), it popped in with no transition
-- (playtest): the whole screen fades in over FADE_S as well
screen.FADE_S = 0.5
function screen.fade_in()
  local f = screen.fade
  if not f then return end
  local k = math.min(1, (os.clock() - f.t) / screen.FADE_S)
  if not valid(f.w) then screen.fade = nil; return end
  try(function() f.w:SetRenderOpacity(k * k * (3 - 2 * k)) end)
  if k >= 1 then screen.fade = nil end
end
function screen.skip_intro(w)
  local tune = get_tune()
  local out = {}
  local cls = try(function() return w:GetClass() end)
  local jump = screen.shown == true
  try(function()
    cls.Animations:ForEach(function(_, e)
      local a = e:get()
      if not valid(a) then return end
      local nm = tostring(try(function() return a:GetFName():ToString() end))
      if try(function() return w:IsAnimationPlaying(a) end) ~= true then return end
      local at, en = try(function() return w:GetAnimationCurrentTime(a) end), try(function() return a:GetEndTime() end)
      local from = jump and en and math.min(screen.INTRO_FROM, en - 0.1) or nil
      if from and (at or 0) < from then
        local jumped = try(function() w:SetAnimationCurrentTime(a, from); return true end)
        if jumped and nm:lower():find("youdi", 1, true) and not screen.introSound then
          screen.introSound = true
          local path = "/Game/Sound/UI/UI_YouDied.UI_YouDied"
          local cue = try(function() return StaticFindObject(path) end)
          if not valid(cue) and LoadAsset then cue = try(function() return LoadAsset(path) end) end
          local gs = goreCtx.statics()
          local pawn = get_pawn()
          if valid(cue) and valid(gs) and pawn then
            local ok = try(function() gs:PlaySound2D(pawn, cue, 1.0, 1.0, 0.0, nil, nil, true); return true end)
            log("revive screen: skipped intro sound " .. (ok and "played" or "could not play"))
          else log("revive screen: skipped intro sound not loaded") end
        end
      else from = nil end
      out[#out + 1] = string.format("%s %.2f/%.2f s%s", nm, at or -1, en or -1, from and string.format(", from %.2f s", from) or "")
      if (tune.gore or {}).probes then
        screen.introLook = screen.introLook or { w = w, a = a, t = os.clock(), next = 0, line = {} }
      end
    end)
  end)
  return #out > 0 and (", intro at the game's speed: " .. table.concat(out, ", ")) or ", no animation playing"
end
-- the intro's opacity over time, logged once as it finishes: the summed opacity of every visible widget under the
-- screen, each 0.25 s with the animation's own time, so INTRO_FROM can be put where something first shows
function screen.intro_look()
  local L = screen.introLook
  if not L then return end
  local now = os.clock()
  if now < L.next then return end
  L.next = now + 0.25
  local w, a = L.w, L.a
  local playing = valid(w) and try(function() return w:IsAnimationPlaying(a) end) == true
  if not playing or now - L.t > 6 then
    screen.introLook = nil
    log("revive screen: intro opacity (anim time = summed opacity): " .. table.concat(L.line, ", "))
    return
  end
  local sum = 0
  local function walk(x, depth)
    if not valid(x) or depth > 12 then return end
    local v = try(function() return x:GetVisibility() end)
    if v == 1 or v == 2 then return end
    local op = try(function() return x:GetRenderOpacity() end) or 1
    if op <= 0.01 then return end
    local n = try(function() return x:GetChildrenCount() end)
    if not n or n == 0 then sum = sum + op; return end
    for k = 0, n - 1 do walk(try(function() return x:GetChildAt(k) end), depth + 1) end
  end
  walk(try(function() return w.WidgetTree.RootWidget end), 0)
  L.line[#L.line + 1] = string.format("%.2f=%.1f", try(function() return w:GetAnimationCurrentTime(a) end) or -1, sum)
end
function screen.probe(pawn)
  local active, manual, elapsed = get_active(), get_manual(), get_elapsed()
  screen.n = screen.n + 1
  -- (its parts timed for the slow tick's line: "death screen" was 13-28 ms of slow ticks, playtest)
  local mk = screen.mark or function() end
  mk("find")
  try(function() screen.hud(elapsed) end)
  mk("death screen: hud")
  -- (asked while new: a kept object's index is read at its first check, within keepFresh s of being made)
  if dead_hud.w and not dead_hud.w.idx then dead_hud.get("w") end
  if dead_hud.rv and not dead_hud.rv.idx then dead_hud.get("rv") end
  try(function() screen.revive(elapsed) end)
  mk("death screen: revive")
  -- (in a death not before 1 s in: registering them took 166 ms, in the frame the killing blow's cut landed,
  -- playtest; while she plays they're tried too, see the tick)
  if not active or (not manual and elapsed >= 1) then screen.hook() end
  mk("death screen: hook")
  -- only in a death, from 5 s in (the screen fades in at 7)
  if screen.n % 15 ~= 0 or not active or manual or elapsed < 5 then return end
  -- gone only once this probe saw it up (the hook saying it came up while the visibility read no screen got her up
  -- the moment it showed, playtest); while the hook says it is up, what the widget reads is logged
  local on = death_screen()
  if not on then
    -- gone only once it read hidden for GONE_S, and not in its first SHOWN_S after it was shown (Shift+F4, reviveAt):
    -- shown again after the mod held it, it read hidden a moment and she got up the moment it came (playtest)
    local now = os.clock()
    if screen.vis and not screen.frozen and now - (screen.shownAt or -100) >= screen.SHOWN_S then
      screen.offSince = screen.offSince or now
      if now - screen.offSince >= screen.GONE_S and not screen.gone then
        log(string.format("death screen: gone %.1f s into the death", elapsed)); screen.last = nil
        screen.gone = true
      end
    end
    if not (screen.seen and dead_hud.get("w")) then return end
  else
    screen.vis, screen.seen, screen.offSince = true, true, nil
  end
  local w = dead_hud.get("w")
  local function f(x) return x and string.format("%.2f", x) or "?" end
  local parts = { string.format("%s: widget vis %s visible %s in viewport %s opacity %s", on and "up" or "hooked up, reads hidden",
    tostring(try(function() return w:GetVisibility() end)), tostring(try(function() return w:IsVisible() end)),
    tostring(try(function() return w:IsInViewport() end)), f(try(function() return w:GetRenderOpacity() end))) }
  for _, name in ipairs({ "CanvasPanel_Dead", "black", "FadeOut", "BackgroundBlur_116", "Root" }) do
    local c = try(function() return w:GetWidgetFromName(FName(name)) end)
    if valid(c) then
      local vis = try(function() return c:GetVisibility() end)
      local a = try(function() return c.ColorAndOpacity.A end)
      local blur = try(function() return c.BlurStrength end)
      parts[#parts + 1] = string.format("%s vis %s opacity %s%s%s", name, tostring(vis), f(try(function() return c:GetRenderOpacity() end)),
        a and (" alpha " .. f(a)) or "", blur and (" blur " .. f(blur)) or "")
    else parts[#parts + 1] = name .. " none" end
  end
  local gs = goreCtx.statics()
  local pcm = try(function() return gs:GetPlayerCameraManager(pawn, 0) end)
  if valid(pcm) then
    local fc = try(function() return pcm.FadeColor end)
    parts[#parts + 1] = string.format("camera fade %s amount %s colour %s, view target %s",
      tostring(try(function() return pcm.bEnableFading end)), f(try(function() return pcm.FadeAmount end)),
      fc and string.format("%.2f %.2f %.2f", fc.R, fc.G, fc.B) or "?",
      tostring(try(function() return pcm.ViewTarget.Target:GetFName():ToString() end)))
  end
  local sig = table.concat(parts, "; ")
  if sig ~= screen.last then
    screen.last = sig
    log(string.format("death screen (%.1f s into the death): %s", elapsed, sig))
  end
end

end
