-- Photo mode collision snapshots and restoration.
return function(screen, goreCtx, valid, try, log)
-- Her other meshes' and her capsule's collision as P opens photo mode in a death, put back as it closes (her own
-- mesh is shielded from its switch: gore.photo_shield). With an arm cut off her alive her mesh has the Ragdoll profile
-- (a PhysicsBody) and her hair and capsule are made to ignore PhysicsBody (gore's stage_open); photo mode's switch
-- back as it closed set them blocking again, and her hair, riding her head, shoved her bodies apart in every direction
-- (playtest: her whole body shifted and stretched after photo mode closed, with an arm lost at low HP only)
function screen.photo_coll_save(pawn)
  screen.photoColl = nil
  local body = try(function() return pawn.Mesh end)
  local list = {}
  local comps = screen.cloth_meshes(pawn)
  comps[#comps + 1] = try(function() return pawn.CapsuleComponent end)
  comps[#comps + 1] = body
  local seen = {}
  for _, m in ipairs(comps) do
    if valid(m) and not seen[m:GetAddress()] then
      seen[m:GetAddress()] = true
      local e = try(function() return m:GetCollisionEnabled() end)
      local k = e and goreCtx.keep(m)
      if k then
        k.enabled, k.resp, k.body = e, {}, valid(body) and m:GetAddress() == body:GetAddress()
        for ch = 0, 31 do k.resp[ch] = try(function() return m:GetCollisionResponseToChannel(ch) end) end
        list[#list + 1] = k
      end
    end
  end
  if #list > 0 and goreCtx.alive_ask(list) then screen.photoColl = list end
end
function screen.photo_coll_restore()
  local list = screen.photoColl
  screen.photoColl = nil
  if not list or not goreCtx.alive_ask(list) then return end
  local fixed, bodyFixed = {}, {}
  for _, k in ipairs(list) do
    if k.alive and valid(k.obj) then
      local m, what = k.obj, {}
      local e = try(function() return m:GetCollisionEnabled() end)
      if e and e ~= k.enabled and try(function() m:SetCollisionEnabled(k.enabled); return true end) then
        what[#what + 1] = string.format("enabled %s>%s", tostring(e), tostring(k.enabled))
      end
      for ch = 0, 31 do
        local r = try(function() return m:GetCollisionResponseToChannel(ch) end)
        if r and k.resp[ch] and r ~= k.resp[ch] and try(function() m:SetCollisionResponseToChannel(ch, k.resp[ch]); return true end) then
          what[#what + 1] = string.format("ch%d %s>%s", ch, tostring(r), tostring(k.resp[ch]))
        end
      end
      if #what > 0 then
        local out = k.body and bodyFixed or fixed
        out[#out + 1] = (try(function() return m:GetFName():ToString() end) or "?") .. " " .. table.concat(what, " ")
      end
    end
  end
  log(string.format("photo mode closed: her other meshes' collision as before it: %s",
    #fixed > 0 and ("put back on " .. table.concat(fixed, "; ")) or "unchanged"))
  log("photo mode closed: body collision " .. (#bodyFixed > 0 and ("restored on " .. table.concat(bodyFixed, "; ")) or "unchanged"))
end
end
