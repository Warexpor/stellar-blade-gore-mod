-- Death and revive widget discovery and new-object watches.
return function(screen, goreCtx, valid, try, log, get_active)
local dead_hud = { scans = 0 }
-- (kept through goreCtx.keep and asked through held before each use: the last death's screen, freed after the
-- respawn, was read at the next death and crashed the game, UE4SS reading the freed widget's class, playtest)
-- One made while a level loads (her tick waits 2 s on a new level) went stale unchecked, and Shift+F4's hold never
-- found the screen (playtest): in a death, one missing is looked for once by its class (find)
dead_hud.CLASS = { w = "WB_MainHUD_Dead_C", rv = "WB_MainHUD_ResurrectionItem_C" }
local hudClass = "WB_MainHUD_Master_C"
local hudNames = { w = "WB_MainHUD_Dead", rv = "WB_MainHUD_ResurrectionItem" }
function dead_hud.find_master()
  local master
  for _, m in ipairs(try(function() return FindAllOf(hudClass) end) or {}) do
    if valid(m) and not tostring(try(function() return m:GetFName():ToString() end)):find("^Default__") then
      master = m
      if try(function() return m:IsInViewport() end) == true then break end
    end
  end
  local k = master and goreCtx.keep(master)
  if k and goreCtx.held(k, true) then screen.hudMaster = k; return master end
end
function dead_hud.get(f, find, grabWaiting)
  local k = dead_hud[f]
  if k and goreCtx.held(k, true) then return k.obj end
  dead_hud[f] = nil
  if not (find and (get_active() or grabWaiting)) then return end
  -- A missed or late notification can leave the widget discoverable in the live HUD tree.
  local master = screen.hudMaster
  if master and not goreCtx.held(master, true) then screen.hudMaster, master = nil, nil end
  if master then
    local w = try(function() return master.obj:GetWidgetFromName(FName(hudNames[f])) end)
    if valid(w) and try(function() return w:GetClass():GetFName():ToString() end) == dead_hud.CLASS[f] then
      k = goreCtx.keep(w)
      if k and goreCtx.held(k, true) then dead_hud[f] = k; return w end
    end
  end
  if find == "hud" then return end
  local search = find == "early" and (f .. ":early") or f
  if (dead_hud.found or {})[search] then return end
  dead_hud.found = dead_hud.found or {}
  dead_hud.found[search] = true
  for _, x in ipairs(try(function() return FindAllOf(dead_hud.CLASS[f]) end) or {}) do
    if valid(x) and not tostring(try(function() return x:GetFName():ToString() end)):find("^Default__") then
      dead_hud[f] = goreCtx.keep(x)
    end
  end
  if dead_hud[f] and goreCtx.held(dead_hud[f], true) then return dead_hud[f].obj end
  dead_hud[f] = nil
end
-- (watched from the mod's start, START_S after the lobby's player start: see screen.started)
screen.late = screen.late or {}
screen.late[#screen.late + 1] = function()
  goreCtx.newobj.watch("/Script/UMG.UserWidget", function(o)
    -- (any time: the death screen may be made in the frame she dies, before the mod's tick knows it)
    local cls = try(function() return o:GetClass():GetFName():ToString() end)
    if (cls == dead_hud.CLASS.w or cls == dead_hud.CLASS.rv or cls == hudClass)
      and tostring(try(function() return o:GetFName():ToString() end)):find("^Default__") then return end
    if cls == dead_hud.CLASS.w then dead_hud.w = goreCtx.keep(o)
    elseif cls == dead_hud.CLASS.rv then dead_hud.rv = goreCtx.keep(o)
    elseif cls == hudClass then screen.hudMaster = goreCtx.keep(o)
    elseif cls == "WB_MainHUD_PlayerInfo_C" and goreCtx.glass and goreCtx.glass.hud_made
      and not tostring(try(function() return o:GetFName():ToString() end)):find("^Default__") then
      goreCtx.glass.hud_made(o)
    end
    if cls and cls:find("[Pp]hoto") and not tostring(try(function() return o:GetFName():ToString() end)):find("^Default__") then
      local ok, err = pcall(screen.photo_widget, o, cls)
      if not ok then log("photo mode widget: " .. tostring(err)) end
    end
    if get_active() and cls and (cls:find("Dead") or cls:find("Resurrect") or cls:find("Revive")) then
      dead_hud.made = (dead_hud.made and dead_hud.made .. ", " or "") .. cls
    end
  end)
  -- photo mode's own pawn, made as it opens, before its widgets: with a piece off her alive her head and upper body
  -- were already back on her neck by the first widget (playtest), so the freeze comes here first
  goreCtx.newobj.watch("/Script/SB.SBPhotoModePawn", function(o)
    if tostring(try(function() return o:GetFName():ToString() end)):find("^Default__") then return end
    local cls = try(function() return o:GetClass():GetFName():ToString() end) or "SBPhotoModePawn"
    local ok2, err2 = pcall(screen.photo_widget, o, cls, true)
    if not ok2 then log("photo mode pawn: " .. tostring(err2)) end
  end, true)
end
local function death_screen()
  local w = dead_hud.get("w")
  if not w then
    if dead_hud.scans > 0 then return false end
    dead_hud.scans = 1
    for _, x in ipairs(try(function() return FindAllOf("WB_MainHUD_Dead_C") end) or {}) do
      if valid(x) and not tostring(try(function() return x:GetFName():ToString() end)):find("^Default__") then w = x end
    end
    if not w then return false end
    dead_hud.w = goreCtx.keep(w)
  end
  local function shown(x)
    local vis = try(function() return x:GetVisibility() end) or 0 -- 1 collapsed, 2 hidden
    return vis ~= 1 and vis ~= 2 and try(function() return x:IsVisible() end) ~= false
      and (try(function() return x:GetRenderOpacity() end) or 1) > 0.01
  end
  if not shown(w) then return false end
  local cp = try(function() return w:GetWidgetFromName(FName("CanvasPanel_Dead")) end)
  return not valid(cp) or shown(cp)
end
return dead_hud, death_screen
end
