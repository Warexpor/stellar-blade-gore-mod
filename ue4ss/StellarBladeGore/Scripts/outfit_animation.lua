-- Outfit post-process animation and physics controls.
return function(M, get_guards)
local function try(...) local f = get_guards(); return f(...) end
local function valid(...) local _, f = get_guards(); return f(...) end
-- the outfit's post-process AnimBP (CH_P_EVE_09_AnimBP) poses the rig's Dm- drivers after her arms and legs. A split
-- half has too few other helpers, so some of its sinks are on drivers of the limbs it keeps (Dm-R-Trape, Dm-R-AX2-Root:
-- "a sink ... a Dm- driver moves" in the harness): as those limbs flailed in the ragdoll the drivers carried the
-- collapsed skin out through the lid, spikes and patches over the cut face (playtest). Off on both halves before the
-- cut (prep waits 3 frames), so the drivers hold their place on the spine and pelvis as the harness has them; back on
-- for her when the split is undone or she is reused
-- the outfit's KawaiiPhysics (its post-process AnimBP: Raven's suit, CH_P_EVE_11, swings its front flap, back tail and
-- thigh charm with it) off while the body is a ragdoll: it chased bones the ragdoll flung about, and her front flap,
-- a chain with no bodies of its own, jumped about like crazy (playtest, Play As Raven). Each node's Alpha 0 (the bones
-- then ride their parents as animated), back to what it was with on. The ControlRig node moving her Dm- drivers runs
-- on. Nodes found by their struct type, once a class (up through its parents). Returns how many were switched
-- (class address -> its nodes' names; "instance:node" -> its Alpha before. Module fields: gore.lua is at Lua's local limit)
M.kawaiiNodes, M.kawaiiWas = {}, {}
function M.kawaii(mesh, on)
  local kawaiiNodes, kawaiiWas = M.kawaiiNodes, M.kawaiiWas
  local inst = valid(mesh) and try(function() return mesh:GetPostProcessInstance() end)
  if not valid(inst) then return 0 end
  local cls = try(function() return inst:GetClass() end)
  local ca = cls and try(function() return cls:GetAddress() end)
  if not ca then return 0 end
  local names = kawaiiNodes[ca]
  if not names then
    names = {}
    local c = cls
    for _ = 1, 4 do
      if not valid(c) then break end
      try(function() c:ForEachProperty(function(p)
        local st = try(function() return p:GetStruct():GetFName():ToString() end)
        if st == "AnimNode_KawaiiPhysics" then names[#names + 1] = p:GetFName():ToString() end
      end) end)
      c = try(function() return c:GetSuperStruct() end)
      local cn = valid(c) and try(function() return c:GetFName():ToString() end)
      if not cn or cn == "AnimInstance" or cn == "SBAnimInstance" then break end
    end
    kawaiiNodes[ca] = names
  end
  local ia = try(function() return inst:GetAddress() end) or 0
  local n = 0
  for _, nm in ipairs(names) do
    local key = string.format("%x:%s", ia, nm)
    local ok = try(function()
      local node = inst[nm]
      if not on then
        if kawaiiWas[key] == nil then kawaiiWas[key] = node.Alpha end
        node.Alpha = 0
      else
        node.Alpha = kawaiiWas[key] or 1
        kawaiiWas[key] = nil
      end
      return true
    end)
    if ok then n = n + 1 end
  end
  return n, #names
end

function M.rig(mesh, on)
  if not valid(mesh) then return false end
  local ok = try(function() mesh:SetDisablePostProcessBlueprint(not on); return true end) == true
  if not on and ok then M.rigoff = M.rigoff or {}; M.rigoff[#M.rigoff + 1] = mesh end
  return ok
end
function M.rig_back()
  for _, m in ipairs(M.rigoff or {}) do M.rig(m, true) end
  M.rigoff = {}
end

-- A new world can free old meshes and reuse object addresses. Drop references and derived state without probing them.
function M.outfit_forget()
  M.rigoff, M.kawaiiWas, M.kawaiiNodes = {}, {}, {}
end
end
