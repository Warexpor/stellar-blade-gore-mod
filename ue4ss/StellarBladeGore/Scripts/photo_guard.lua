-- Shield and watch ragdolls and cut pieces across photo mode.
return function(screen, try, log, vof, dist, PELVIS, hold_capsule, ragdoll_state, unlock, no_snapshot, sw, get_active, get_rag, get_gore, get_tune)
function screen.photo_watch(pawn, mesh)
  local active, rag, gore, tune = get_active(), get_rag(), get_gore(), get_tune()
  local now = os.clock()
  -- (a death lying still stays so while it is on: rag.hold_still; the engine keeps stepping under photo mode while
  -- the death tick stops, so hold every poll and keep the ragdoll from dragging the capsule after it)
  if rag and rag.hold_still then rag.hold_still() end
  if active then hold_capsule(pawn, true) end
  if now < screen.photoNext then return true end
  screen.photoNext = now + 0.5
  local st = gore.photo_state()
  local on = tonumber(st:match(" 84=(%-?%d+)"))
  local head = try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Head"))) end)
  local h0 = screen.photoHead
  local function b(f) local ok, r = pcall(f); return ok and tostring(r) or "?" end
  local seen = string.format("%s; mesh lockup %s, head sim %s, pelvis sim %s, collision %s", ragdoll_state(pawn),
    b(function() return mesh.bLockupSimulatePhysics end), b(function() return mesh:IsSimulatingPhysics(FName("Bip001-Head")) end),
    b(function() return mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end), b(function() return mesh:GetCollisionEnabled() end))
  if seen ~= screen.photoSeen then
    screen.photoSeen = seen
    log(string.format("photo mode %s: %s, head %s off where it was before; %s", on and on ~= 0 and "on" or "off", st,
      head and h0 and string.format("%.0f cm", dist(head, h0)) or "?", seen))
  end
  if on and on ~= 0 then
    screen.photoWait = nil
    local ri = try(function() return pawn.RagdollInfo end)
    if try(function() return mesh.bLockupSimulatePhysics end) or try(function() return pawn.bLockupSimulatePhysics end)
      or (ri and (try(function() return ri.bPoseSnapshot end) or try(function() return ri.bRegisterPoseSnapshot end))) then
      local was = unlock(pawn, mesh)
      no_snapshot(pawn)
      log("photo mode: her lockup / pose snapshot undone (" .. was .. ")")
    end
    return true
  end
  if not on then return true end -- (no answer: try again)
  -- (held from its pawn on, the game's key: her tick may look before photo mode's state shows it open)
  if screen.photoWait and now < screen.photoWait then return true end
  screen.photoWait = nil
  screen.photoOn = false
  screen.photoOpened = nil
  screen.photoAfter = now + ((tune.gore or {}).photoGrace or 0.5)
  screen.stillTill = now + 1
  screen.photo_coll_restore()
  if rag and rag.photo_hold then rag.photo_hold(false) end
  sw.drop()
  log("photo mode closed: the enemy's weapon trail starts over")
  screen.photo_unhold("photo mode closed")
  return false
end

function screen.photo_guard(pawn, mesh)
  local rag, gore = get_rag(), get_gore()
  if screen.stillTill and rag and rag.hold_still then
    if os.clock() < screen.stillTill then rag.hold_still() else screen.stillTill = nil end
  end
  screen.watchFreeze = screen.frozenMesh ~= nil or gore.pieceHid ~= nil or (gore.cuts_on(mesh)) > 0
  if not screen.watchFreeze then screen.clock, screen.stopped = nil, nil end
  if screen.photoOn then return screen.photo_watch(pawn, mesh) end
  local a = mesh:GetAddress()
  local cut = (gore.cuts_on(mesh)) > 0
  local why = cut and "a piece is off her"
    or try(function() return mesh:IsSimulatingPhysics(PELVIS) end) == true and "her ragdoll on"
  if not why then
    if screen.shielded == a then
      screen.shielded = nil
      log("no piece off her, no ragdoll: her mesh unshielded: " .. gore.photo_unshield())
    end
    return false
  end
  if screen.shielded ~= a then
    screen.shielded = a
    log(why .. ": her mesh shielded from photo mode's collision switch: " .. gore.photo_shield(mesh))
  end
  local now = os.clock()
  if now < (screen.photoPoll or 0) then return false end
  screen.photoPoll = now + 0.5
  local on = tonumber(gore.photo_state():match(" 84=(%-?%d+)"))
  if on == 0 then screen.photoOpened = nil end
  if on and on ~= 0 then
    screen.photoOn, screen.photoNext, screen.photoSeen = true, 0, nil
    log("photo mode opened by the game's own key")
    return screen.photo_watch(pawn, mesh)
  end
  screen.photoHead = try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Head"))) end)
  return false
end

end
