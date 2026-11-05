-- Photo-mode visibility and near-clip restoration.
return function(screen, goreCtx, valid, try, log, vof, dist, get_gore, get_tune)
function screen.photo_unhide(pawn)
  local gore = get_gore()
  screen.view(pawn)
  local now = os.clock()
  if gore and gore.photo_state and now >= (screen.liveNext or 0) then
    screen.liveNext = now + 0.5
    -- the manager's +0x84 went back to 0 a second after photo mode opened on her alive (playtest): photo mode is
    -- also told by the player's pawn or the camera's view target being photo mode's own
    local st = gore.photo_state(pawn) or ""
    local m84 = tonumber(st:match(" 84=(%-?%d+)"))
    -- (hidden with photo mode's own option: left so)
    screen.ownHide = st:match(" own=1") ~= nil
    -- (her caps and stubs, actors of their own, hidden and shown with her)
    if gore.photo_hide and screen.ownHide ~= (gore.photoHid ~= nil) then
      local n = gore.photo_hide(pawn, screen.ownHide)
      log(string.format("photo mode %s her: %d cap(s) and stub(s) with her", screen.ownHide and "hides" or "shows", n))
    end
    local gs = goreCtx.statics()
    local cls = function(o) return valid(o) and (try(function() return o:GetClass():GetFName():ToString() end) or "?") or "none" end
    local pp = valid(gs) and cls(try(function() return gs:GetPlayerPawn(pawn, 0) end)) or "?"
    local vt = valid(gs) and cls(try(function() return gs:GetPlayerCameraManager(pawn, 0).ViewTarget.Target end)) or "?"
    local paused = valid(gs) and try(function() return gs:IsGamePaused(pawn) end)
    local live = (m84 ~= nil and m84 ~= 0) or pp:find("PhotoMode") ~= nil or vt:find("PhotoMode") ~= nil
    local sig = string.format("84=%s 48=%s, player pawn %s, view target %s, paused %s", tostring(m84), st:match(" 48=(%-?%d+)") or "?",
      pp, vt, tostring(paused))
    if sig ~= screen.liveSig then screen.liveSig = sig; log("photo probe: " .. sig) end
    if live ~= screen.photoLive then
      screen.photoLive = live
      log(string.format("photo mode %s (%s)", live and "on" or "off", sig))
    end
  end
  local on = screen.vtPhoto or screen.photoOn or screen.photoLive
  if not on then
    if screen.unhide then screen.unhide_end(pawn) end
    screen.ownHide = nil
    if gore and gore.photoHid then gore.photo_hide(pawn, false) end
    return
  end
  if screen.ownHide then return end
  local u = screen.unhide
  if not u then u = screen.unhide_start(pawn) end
  local mesh = try(function() return pawn.Mesh end)
  local fixed = {}
  -- (what the game had set, logged as it changes: another way of hiding her would show here)
  local sig = string.format("actor hidden %s, character hidden %s, mesh hidden %s visible %s", tostring(try(function() return pawn.bHidden end)),
    tostring(try(function() return pawn.bCharacterHiddenInGame end)), tostring(try(function() return mesh.bHiddenInGame end)),
    tostring(try(function() return mesh.bVisible end)))
  if sig ~= screen.unhideSig then screen.unhideSig = sig; log("photo view: " .. sig) end
  if try(function() return pawn.bHidden end) == true then
    try(function() pawn:SetActorHiddenInGame(false) end)
    fixed[#fixed + 1] = "actor"
  end
  local face = gore and gore.face_of and valid(mesh) and try(function() return gore.face_of(pawn, mesh) end)
  local comps = { mesh, face }
  -- and every other part of her (hair, outfit pieces): one hidden as photo mode opened (the gore's) stays hidden
  for _, c in ipairs(u.comps) do comps[#comps + 1] = c.c end
  local seen = {}
  for _, c in ipairs(comps) do
    local a = valid(c) and c:GetAddress()
    -- (what rode a piece cut off her, hidden while photo mode is on: gore.hide_pieces)
    if a and gore and gore.pieceHid and gore.pieceHid.set[a] then a = nil end
    if a and not seen[a] then
      seen[a] = true
      local name = function() return try(function() return c:GetName() end) or "?" end
      if not u.hid[a] and try(function() return c.bHiddenInGame end) == true then
        try(function() c:SetHiddenInGame(false, false) end)
        fixed[#fixed + 1] = name() .. " hidden"
      end
      if not u.hid[a] and try(function() return c.bVisible end) == false then
        try(function() c:SetVisibility(true, false) end)
        fixed[#fixed + 1] = name() .. " invisible"
      end
      if try(function() return c.bOwnerNoSee end) == true then
        try(function() c:SetOwnerNoSee(false) end)
        fixed[#fixed + 1] = name() .. " owner-no-see"
      end
    end
  end
  -- the controller's own lists of what it doesn't draw
  local pc = try(function() return pawn.Controller end)
  if valid(pc) then
    local keep, mine = {}, false
    try(function() pc.HiddenActors:ForEach(function(_, e)
      local a = e:get()
      if valid(a) and a:GetAddress() == pawn:GetAddress() then mine = true else keep[#keep + 1] = a end
    end) end)
    if mine and try(function()
      pc.HiddenActors:Empty()
      for i, a in ipairs(keep) do pc.HiddenActors[i] = a end
      return true
    end) then fixed[#fixed + 1] = "the controller's hidden actors" end
    local hp = try(function() return pc.HiddenPrimitiveComponents:GetArrayNum() end) or 0
    if hp ~= u.hp then u.hp = hp; log("photo view: the controller hides " .. hp .. " component(s)") end
  end
  if #fixed > 0 then
    local k = table.concat(fixed, ", ")
    if k ~= u.fixed then
      u.fixed = k
      log(string.format("photo mode hid her up close (camera %.0f cm from her head): shown again (%s)", u.d or -1, k))
    end
  end
  -- the camera's distance to her head, every 0.25 s; the closest is logged as photo mode closes
  local now = os.clock()
  if now >= u.next then
    u.next = now + 0.25
    local gs = goreCtx.statics()
    local cam = valid(gs) and try(function() return vof(gs:GetPlayerCameraManager(pawn, 0):GetCameraLocation()) end)
    local head = valid(mesh) and try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Head"))) end)
    local d = cam and head and dist(cam, head)
    if d then
      u.d = d
      if not u.min or d < u.min then u.min = d end
    end
  end
end
-- photo mode opened: her parts listed (one hidden now, an outfit piece the gore took off, stays hidden), the near
-- clip plane brought in (tune.photoNearClip cm; the game's is 10 cm, and the camera's 10 cm cut into her up close)
function screen.unhide_start(pawn)
  local tune = get_tune()
  local u = { comps = {}, hid = {}, next = 0, hp = 0 }
  screen.unhide = u
  local hidden = 0
  -- (her parts by her root's attach tree: K2_GetComponentsByClass found none in game)
  local seen = {}
  local function walk(c, depth)
    if not valid(c) or depth > 8 then return end
    local a = c:GetAddress()
    if seen[a] then return end
    seen[a] = true
    if try(function() return c:IsA(StaticFindObject("/Script/Engine.PrimitiveComponent")) end) then
      u.comps[#u.comps + 1] = { c = c, name = try(function() return c:GetName() end) or "?" }
      if try(function() return c.bHiddenInGame end) == true or try(function() return c.bVisible end) == false then
        u.hid[a] = true
        hidden = hidden + 1
      end
    end
    local kids = {}
    try(function() c.AttachChildren:ForEach(function(_, e) kids[#kids + 1] = e:get() end) end)
    for _, k in ipairs(kids) do walk(k, depth + 1) end
  end
  walk(try(function() return pawn.RootComponent end), 0)
  local nc = tune.photoNearClip
  if type(nc) == "number" and nc > 0 then u.clip = screen.console(pawn, string.format("r.SetNearClipPlane %g", nc)) end
  log(string.format("photo mode: %d part(s) of her watched (%d hidden already, left so)%s", #u.comps, hidden,
    u.clip and string.format(", near clip plane %g cm", nc) or ""))
  return u
end
function screen.unhide_end(pawn)
  local gore = get_gore()
  local u = screen.unhide
  screen.unhide, screen.unhideSig = nil, nil
  if u.clip then screen.console(pawn, "r.SetNearClipPlane 10") end
  log(string.format("photo mode closed: the camera came within %s of her head%s; %s", u.min and string.format("%.0f cm", u.min) or "? cm",
    u.clip and ", near clip plane back to 10 cm" or "", gore and gore.photo_state() or "no sbslice"))
end
function screen.console(pawn, cmd)
  local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
  local pc = try(function() return pawn.Controller end)
  return valid(ksl) and try(function() ksl:ExecuteConsoleCommand(pawn, cmd, valid(pc) and pc or nil); return true end) == true
end

end
