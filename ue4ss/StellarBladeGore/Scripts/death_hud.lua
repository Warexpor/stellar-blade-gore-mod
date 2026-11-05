-- Death HUD visibility and restoration. The caller supplies live lifecycle state.
return function(screen, goreCtx, dead_hud, valid, try, log, get_active, get_manual, get_tune)
-- the rest of the HUD hidden through a death (tune.hideHud): her HP bar, skills, minimap, notices, all inside
-- WB_MainHUD_Master, which holds the death screen too. Every widget in it is collapsed but the branch down to the
-- death and revive screens (by class or name), put back as the death ends. Asked for in a comment on Nexus (another
-- ragdoll mod hides the UI on death)
screen.hudHid = nil -- { master = kept, list = { { w, vis } } }
screen.HUD_KEEP = { "Dead", "Resurrection", "Revive" }
function screen.hud_keeps(w)
  local n = tostring(try(function() return w:GetFName():ToString() end)) .. " "
    .. tostring(try(function() return w:GetClass():GetFName():ToString() end))
  for _, k in ipairs(screen.HUD_KEEP) do if n:find(k, 1, true) then return true end end
  return false
end
-- whether a widget holds a kept one (a panel: its children, depth at most 6; a user widget isn't looked into)
function screen.hud_holds(w, depth, memo)
  if screen.hud_keeps(w) then return true end
  if depth > 6 then return false end
  local key = memo and try(function() return w:GetAddress() end)
  if key and memo[key] ~= nil then return memo[key] end
  local found = false
  local n = try(function() return w:GetChildrenCount() end) or 0
  for i = 0, n - 1 do
    local c = try(function() return w:GetChildAt(i) end)
    if valid(c) and screen.hud_holds(c, depth + 1, memo) then found = true; break end
  end
  if key then memo[key] = found end
  return found
end
function screen.hud_hide(depth, panel, list, memo)
  memo = memo or {}
  local n = try(function() return panel:GetChildrenCount() end) or 0
  for i = 0, n - 1 do
    local c = try(function() return panel:GetChildAt(i) end)
    if valid(c) and not screen.hud_keeps(c) then
      if screen.hud_holds(c, depth + 1, memo) then screen.hud_hide(depth + 1, c, list, memo)
      else
        local vis = try(function() return c:GetVisibility() end)
        if vis and vis ~= 1 and vis ~= 2 then
          try(function() c:SetVisibility(1) end)
          list[#list + 1] = { w = c, vis = vis }
        end
      end
    end
  end
end
function screen.hud(t)
  local h = screen.hudHid
  if not get_active() or get_manual() or get_tune().hideHud == false then
    if h then
      screen.hudHid = nil
      local n = 0
      if goreCtx.held(h.master) then
        for _, x in ipairs(h.list) do
          if valid(x.w) then try(function() x.w:SetVisibility(x.vis) end); n = n + 1 end
        end
      end
      log(string.format("HUD: %d widgets shown again", n))
    end
    return
  end
  -- The widget-tree walk hid a death's HUD for 12-58 ms on cut-opening frames (playtest). Hiding at 1 s into the
  -- death instead lands past every cut and split stage (the screen itself fades in at about 7 s), which reads the same.
  if h or t < 1.0 then return end
  -- the master: off the death screen's outers (its widget tree, then the master), else kept from the last death, else
  -- looked for (one scan a death at most)
  local m
  local w = dead_hud.get("w")
  if w then
    m = try(function() return w:GetOuter():GetOuter() end)
    if not (valid(m) and tostring(try(function() return m:GetClass():GetFName():ToString() end)) == "WB_MainHUD_Master_C") then m = nil end
  end
  if not m and screen.hudMaster and goreCtx.held(screen.hudMaster) then m = screen.hudMaster.obj end
  if not m then
    for _, x in ipairs(try(function() return FindAllOf("WB_MainHUD_Master_C") end) or {}) do
      if valid(x) and not tostring(try(function() return x:GetFName():ToString() end)):find("^Default__") then m = x end
    end
  end
  local k = m and goreCtx.keep(m)
  -- (its index read now, while it is surely alive: held reads it only within keepFresh s of keep)
  if not (k and goreCtx.held(k)) then screen.hudHid = { master = k or {}, list = {} }; log("HUD: no WB_MainHUD_Master, left up"); return end
  screen.hudMaster = k
  local root = try(function() return m.WidgetTree.RootWidget end)
  local list = {}
  if valid(root) then screen.hud_hide(0, root, list) end
  screen.hudHid = { master = k, list = list }
  log(string.format("HUD: %d widgets hidden for the death", #list))
end
end
