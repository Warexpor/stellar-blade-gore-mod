-- Copies belonging to other mods: discovery, synchronization, and split cleanup.
return function(M, d)
local addr, mesh_name, name_of, command, clone_of, log = d.addr, d.mesh_name, d.name_of, d.command, d.clone_of, d.log
local function try(...) local f = d.guards(); return f(...) end
local function valid(...) local _, f = d.guards(); return f(...) end
-- other mods' copies of a cut mesh on its pose: Ultra Violence draws her outfit and face blood on a see-through copy
-- of the mesh (the same asset following her, with its own weights). It kept her whole skin and stretched from the
-- stump to the flying limb, so each copy gets the cut mesh's weights ("y") and loses them with its own
M.copies = { of = {}, dirty = {}, next = 0 } -- of[mesh addr] = { [copy addr] = copy }
function M.copies_find(mesh)
  local out, me = {}, addr(mesh)
  local sk = me and try(function() return addr(mesh.SkeletalMesh) end)
  if not sk then return out end
  local ours = {}
  for _, c in ipairs(d.clones()) do local a = addr(c); if a then ours[a] = true end end
  -- (on its pose, or on the pose of the mesh's own master: Ultra Violence's face blood follows her body, the face's
  -- master, and kept the face's whole skin, stretched from her neck to the flying head, playtest)
  local lead = try(function() local m = mesh.MasterPoseComponent:Get(); return m and addr(m) end)
  try(function() mesh.AttachChildren:ForEach(function(_, e)
    local c = e:get()
    local a = valid(c) and addr(c)
    if a and not ours[a] and mesh_name(c) and try(function() return addr(c.SkeletalMesh) end) == sk then
      local m = try(function() return c.MasterPoseComponent:Get() end)
      local ma = m and addr(m)
      if ma and (ma == me or ma == lead) then out[#out + 1] = c end
    end
  end) end)
  return out
end
-- every copy (all = true) or the ones not given its weights yet
function M.copies_sync(mesh, all, extra)
  local me = addr(mesh)
  if not me then return end
  local had = M.copies.of[me] or {}
  local send = {}
  for a, c in pairs(had) do if all and valid(c) then send[#send + 1] = c elseif not valid(c) then had[a] = nil end end
  for _, c in ipairs(extra or M.copies_find(mesh)) do
    local a = addr(c)
    if not had[a] then had[a] = c; send[#send + 1] = c end
  end
  M.copies.of[me] = next(had) and had or nil
  if #send == 0 then return end
  -- The native y command accepts at most 16 destinations per call.
  for first = 1, #send, 16 do
    local list = {}
    for i = first, math.min(first + 15, #send) do
      list[#list + 1] = string.format("%x", send[i]:GetAddress())
      M.lod0(send[i], true)
      if M.copies.of[me] ~= had then return end
    end
    local r = command(string.format("y%x,0,%s", me, table.concat(list, ",")))
    if M.copies.of[me] ~= had then return end
    log(string.format("%s's cut weights on %d cop%s of it on her pose (another mod's): %s", name_of(mesh), #list,
      #list == 1 and "y" or "ies", r))
  end
end
function M.copies_clear(a)
  local had = M.copies.of[a]
  M.copies.of[a], M.copies.dirty[a] = nil, nil
  if not had then return end
  local list = {}
  for _, c in pairs(had) do
    if valid(c) then list[#list + 1] = string.format("%x", c:GetAddress()); M.lod0(c, false) end
  end
  for first = 1, #list, 16 do
    local batch = {}
    for i = first, math.min(first + 15, #list) do batch[#batch + 1] = list[i] end
    log(string.format("cut weights off %d cop%s: %s", #batch, #batch == 1 and "y" or "ies",
      command(string.format("y%x,0,%s", a, table.concat(batch, ",")))))
  end
end
-- the meshes cut this frame, and every half second the copies made since (Ultra Violence remakes its copy when her
-- blood or outfit changes)
function M.copies_flush()
  local now = os.clock()
  local look = now >= M.copies.next
  if not look and not next(M.copies.dirty) then return end
  if look then M.copies.next = now + 0.5 end
  -- Consume only the work present at entry. Native and engine callbacks may mark a new cut while syncing.
  local dirty, seen = M.copies.dirty, {}
  M.copies.dirty = {}
  local cuts = d.cuts()
  for _, c in ipairs(cuts) do
    local a = c.addr
    if a and not seen[a] and (look or dirty[a]) and valid(c.mesh) and addr(c.mesh) == a then
      seen[a] = true
      local ok, err = pcall(M.copies_sync, c.mesh, dirty[a])
      if not ok then
        -- The scheduler reports the error; retain unprocessed work for its next attempt.
        for pending in pairs(dirty) do M.copies.dirty[pending] = true end
        error(err, 0)
      end
      dirty[a] = nil
      if d.cuts() ~= cuts then
        -- Cleanup replaced the cut list. Keep only old work whose cut still exists.
        for _, current in ipairs(d.cuts()) do
          if current.addr and dirty[current.addr] then M.copies.dirty[current.addr] = true end
        end
        return
      end
    end
  end
end

-- a split: another mod's copies of her mesh stay on her half (her half's weights), and the copy's half gets a copy of
-- each that shows, on its pose with its weights (an animated split's copy is posed by her till they fall apart)
function M.copies_split(q)
  local b2, made = q.body2, {}
  q.copies2 = {}
  for _, o in ipairs(M.copies_find(q.mesh)) do
    if try(function() return o:IsVisible() end) == true then
      local c = clone_of(q.pawn, o)
      if c then
        try(function() c:K2_AttachToComponent(b2, FName("None"), 2, 2, 2, false) end)
        try(function() c:SetMasterPoseComponent(q.anim and q.mesh or b2, true) end)
        try(function() c:SetCastShadow(false) end)
        try(function() c:SetHiddenInGame(false, false) end)
        made[#made + 1] = c
        q.copies2[#q.copies2 + 1] = c
      end
    end
  end
  if #made > 0 then M.copies_sync(b2, false, made) end
end


end
