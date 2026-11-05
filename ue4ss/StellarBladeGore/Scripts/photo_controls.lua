-- Photo input and death-hold controls.
return function(screen, goreCtx, camera, valid, try, log, vof, find_eve, get_active, get_manual, get_tune, get_gore, get_rag, get_pawn, get_elapsed)
function screen.allow_photo(on, why)
  local gore, tune = get_gore(), get_tune()
  if on == screen.photo or not gore or (on and tune.deathPhoto == false) then return end
  local r = gore.photo(on)
  if r:match("^ok") then screen.photo = on end
  log(string.format("photo mode %s (%s): %s", on and "allowed in the held death" or "back to the game's checks", why, r))
end
function screen.photo_unhold(why)
  local active = get_active()
  if not screen.photoTook then return end
  screen.photoTook = nil
  if not active or not screen.frozen then return end
  screen.frozen = false
  screen.allow_photo(false, why)
  log(string.format("%s: the death P held let go, the death screen and getting up as before %.1f s in", why, get_elapsed()))
end
-- The photo collision snapshot remains on screen for recovery and world cleanup.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/photo_collision.lua")(screen, goreCtx, valid, try, log)
function screen.photo_key(label)
  local active, manual, gore, rag = get_active(), get_manual(), get_gore(), get_rag()
  if not active or manual or (camera.held() and camera.held().photo) or screen.photoOn or not gore then return end
  if not screen.frozen then screen.frozen, screen.photoTook = true, true; screen.allow_photo(true, label) end
  local pawn = find_eve()
  local mesh = pawn and try(function() return pawn.Mesh end)
  -- (her ragdoll stopped, asleep and deaf to photo mode's pawn first: rag.photo_hold)
  local took = rag and rag.photo_hold and not rag.photoHeld
  if valid(pawn) then screen.photo_coll_save(pawn) end
  local held = took and rag.photo_hold(true) or 0
  local r = gore.photo_open(mesh)
  log(label .. " in the held death, opening photo mode: " .. r .. string.format(" (%d of her meshes held still)", held))
  if not r:find("entered 1", 1, true) and took then rag.photo_hold(false) end
  if not r:find("entered 1", 1, true) then screen.photoColl = nil; screen.photo_unhold("photo mode didn't open") end
  if r:find("entered 1", 1, true) then
    screen.photoOn, screen.photoNext, screen.photoSeen = true, 0, nil
    screen.photoHead = valid(mesh) and try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Head"))) end)
  end
end
function screen.pad_photo()
  local held = camera.held()
  if not get_active() or get_manual() or (held and held.photo) or not get_gore() then screen.padKeys, screen.padWas, screen.holdWas = nil, nil, nil; return end
  local cachedPawn, tune = get_pawn(), get_tune()
  local gs = goreCtx.statics()
  local pc = valid(gs) and cachedPawn and try(function() return gs:GetPlayerController(cachedPawn, 0) end)
  if not valid(pc) then return end
  if not screen.padKeys then
    local found = {}
    try(function()
      pc.PlayerInput.ActionMappings:ForEach(function(_, e)
        local m = e:get()
        local act = m.ActionName:ToString()
        local key = m.Key.KeyName:ToString()
        if (act == "PhotomodeTwoKey1" or act == "PhotomodeTwoKey2") and key:find("^Gamepad") and not found[act] then found[act] = key end
      end)
    end)
    local a, b = found.PhotomodeTwoKey1 or "Gamepad_DPad_Left", found.PhotomodeTwoKey2 or "Gamepad_RightShoulder"
    screen.padKeys = { { KeyName = FName(a) }, { KeyName = FName(b) }, label = a .. "+" .. b }
    log(string.format("photo mode on the controller in this death: %s%s", screen.padKeys.label,
      (found.PhotomodeTwoKey1 and found.PhotomodeTwoKey2) and "" or " (the game's defaults: its mappings weren't read)"))
  end
  local k = screen.padKeys
  local on = try(function() return pc:IsInputKeyDown(k[1]) and pc:IsInputKeyDown(k[2]) end) == true
  if on and not screen.padWas then screen.photo_key(k.label) end
  screen.padWas = on
  -- Shift+F4 on the controller (tune.holdPad, D-pad down + R1 unless set): both down shows the death screen or hides it
  local hp = tune.holdPad
  if type(hp) ~= "table" or not hp[2] then screen.holdWas = nil; return end
  if not screen.holdKeys or screen.holdKeys.label ~= hp[1] .. "+" .. hp[2] then
    screen.holdKeys = { { KeyName = FName(hp[1]) }, { KeyName = FName(hp[2]) }, label = hp[1] .. "+" .. hp[2] }
  end
  local h = screen.holdKeys
  -- held down for tune.holdPadFor s: a quick press of both came by accident in a fight's death (D-pad down + R1),
  -- held the death and left her stuck with only the camera and photo mode (Nexus report)
  local hold = try(function() return pc:IsInputKeyDown(h[1]) and pc:IsInputKeyDown(h[2]) end) == true
  if not hold then screen.holdSince, screen.holdWas = nil, false
  elseif not screen.holdWas then
    screen.holdSince = screen.holdSince or os.clock()
    if os.clock() - screen.holdSince >= (tonumber(tune.holdPadFor) or 1.0) then screen.holdWas = true; screen.hold(h.label .. " (held)") end
  end
end
-- Shift+F4 in a death: the death screen up now if it is still hidden (tune.deathScreen "key" waits for this), else
-- hidden and the death held, no getting up, till pressed again; the game respawning her on its own still ends it
function screen.hold(why)
  local t = get_elapsed()
  screen.photoTook = nil
  -- (see-through, Customized Ragdoll support's: the first press shows it)
  if screen.hiding(t) or goreCtx.customrag and goreCtx.customrag.active() and not screen.shown then screen.frozen, screen.shown = false, true
  else screen.frozen = true end
  screen.allow_photo(screen.frozen, why)
  log(string.format("%s: death %s %.1f s in", why, screen.frozen and "held, no death screen or getting up till Shift+F4 (or the pad combo) again" or "screen shown", t))
end
end
