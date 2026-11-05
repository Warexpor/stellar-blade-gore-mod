-- Motion blur suppression while the game runs slow, and the follow camera de-lagged (its boom smooths
-- on dilated time): dilation smears the velocity buffer, so Eve's body blurs when the camera turns. An
-- unbound post-process volume with the blur at zero rides along, her follow camera gets the same override
-- the death camera uses, and the boom's lag goes off; all handed back after. The caller says when slow
-- starts and stops; this only holds them.
return function(get_statics, try, valid, log)
  local M = { vol = nil, cam = nil, booms = nil }
  local function children_of(root)
    local out, seen, stack = {}, {}, { root }
    while #stack > 0 do
      local c = table.remove(stack)
      if valid(c) then
        local a = try(function() return c:GetAddress() end)
        if a and not seen[a] then
          seen[a] = true
          out[#out + 1] = c
          try(function() c.AttachChildren:ForEach(function(_, e) stack[#stack + 1] = e:get() end) end)
        end
      end
    end
    return out
  end
  local function spawn(pawn)
    local gs = get_statics and get_statics()
    local cls = gs and try(function() return StaticFindObject("/Script/Engine.PostProcessVolume") end)
    if not (valid(gs) and valid(cls) and valid(pawn)) then return nil end
    local tm = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 },
      Scale3D = { X = 1, Y = 1, Z = 1 } }
    local v = try(function()
      local d = gs:BeginDeferredActorSpawnFromClass(pawn, cls, tm, 1, nil)
      return gs:FinishSpawningActor(d, tm)
    end)
    if not valid(v) then return nil end
    local ok = try(function()
      v.bUnbound = true
      v.Priority = 100000
      local pp = v.Settings
      pp.bOverride_MotionBlurAmount = true
      pp.MotionBlurAmount = 0
      return pp.bOverride_MotionBlurAmount == true and pp.MotionBlurAmount == 0
    end)
    if not ok then try(function() v:K2_DestroyActor() end); return nil end
    return v
  end
  -- Eve's follow camera and boom, by name off her pawn (FollowCamera, CameraBoom)
  local function camera_of(pawn)
    local root = valid(pawn) and try(function() return pawn.RootComponent end)
    for _, c in ipairs(children_of(root)) do
      if try(function() return c:GetFName():ToString() end) == "FollowCamera" then return c end
    end
  end
  local function booms_of(pawn)
    local out = {}
    local root = valid(pawn) and try(function() return pawn.RootComponent end)
    for _, c in ipairs(children_of(root)) do
      if try(function() return c:GetFName():ToString() end) == "CameraBoom" then out[#out + 1] = c end
    end
    return out
  end
  -- slow on or off: hold the volume, the camera override and the de-lagged boom while slow, hand all back
  -- after. Idempotent; anything that doesn't take logs and stays out of the way
  function M.want(pawn, slowed)
    if slowed then
      if not valid(M.vol) then
        M.vol = spawn(pawn)
        if valid(M.vol) then log("slow motion: motion blur volume up (blur off while slow)")
        else log("slow motion: motion blur volume not spawned (the blur stays)") end
      end
      if not M.cam then
        local cc = camera_of(pawn)
        local ok = cc and try(function()
          M.cam = { cc = cc, over = cc.PostProcessSettings.bOverride_MotionBlurAmount,
            amt = cc.PostProcessSettings.MotionBlurAmount }
          cc.PostProcessSettings.bOverride_MotionBlurAmount = true
          cc.PostProcessSettings.MotionBlurAmount = 0
          return cc.PostProcessSettings.MotionBlurAmount == 0
        end)
        if M.cam and ok then log("slow motion: her camera's blur off while slow")
        else M.cam = nil; log("slow motion: her camera not found (its blur stays)") end
      end
      if not M.booms then
        M.booms = {}
        for _, b in ipairs(booms_of(pawn)) do
          local was = try(function() return b.bEnableCameraLag end)
          if was ~= nil and try(function() b.bEnableCameraLag = false; return true end) then
            M.booms[#M.booms + 1] = { b = b, was = was }
          end
        end
        log(string.format("slow motion: camera lag %s while slow",
          #M.booms > 0 and ("off on " .. #M.booms .. " boom(s)") or "untouched (no boom found)"))
      end
      return true
    end
    if M.cam and valid(M.cam.cc) then try(function()
      M.cam.cc.PostProcessSettings.bOverride_MotionBlurAmount = M.cam.over
      M.cam.cc.PostProcessSettings.MotionBlurAmount = M.cam.amt
    end) end
    M.cam = nil
    if M.booms then
      for _, e in ipairs(M.booms) do if valid(e.b) then try(function() e.b.bEnableCameraLag = e.was end) end end
      M.booms = nil
    end
    if valid(M.vol) then try(function() M.vol:K2_DestroyActor() end); log("slow motion: blur and lag back") end
    M.vol = nil
    return true
  end
  function M.forget()
    if M.cam and valid(M.cam.cc) then try(function()
      M.cam.cc.PostProcessSettings.bOverride_MotionBlurAmount = M.cam.over
      M.cam.cc.PostProcessSettings.MotionBlurAmount = M.cam.amt
    end) end
    M.cam = nil
    if M.booms then
      for _, e in ipairs(M.booms) do if valid(e.b) then try(function() e.b.bEnableCameraLag = e.was end) end end
      M.booms = nil
    end
    if valid(M.vol) then try(function() M.vol:K2_DestroyActor() end) end
    M.vol = nil
  end
  return M
end
