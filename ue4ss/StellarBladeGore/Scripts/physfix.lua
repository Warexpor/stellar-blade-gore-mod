-- physfix.lua: what the script can do for an outfit the data mod didn't patch (tune.physfix).
--
-- The data mod's outfits container patches every outfit mesh it found at build time: LOD0 CPU access (the cut reads
-- her skin from it) and the ragdoll fixes in its physics asset (assetkit/outfits.py). An outfit mod installed after
-- the build, one that loads after this mod, or a build without the outfits container leaves her in a mesh with
-- neither. This tells the log which, and fixes what can be fixed from here:
--   * damping: vanilla bodies fall at ~2 m/s (linear 5.0) and turn as if under water (angular 10). The main
--     bodies get the data mod's values in the physics asset's defaults, and the mesh re-creates its bodies from it
--     while she is animated (they are kinematic then, so nothing shows).
--   * joint limits: the main joints' soft limits give way under a push; they're made hard. The data mod also
--     re-centres the ranges on her bind pose, which needs the reference skeleton's rotations: not from here.
--   * loose bodies: twist and helper bones that carry a cape or skirt chain, with a body but no joint to anything
--     (in a ragdoll they fly off and drag the arm's skin with them), get a locked constraint to the nearest body
--     above them while she is ragdolled.
--   * no physics asset at all: an outfit mod's mesh exported without one (Eve with no Clothes on) has no bodies,
--     so she can't ragdoll. It gets the asset next to it by the game's naming (<mesh>_Physics, which the data mod
--     ships patched), else tune.physfix.fallback (Eve's base body's).
-- Self-collision is already off for an unpatched asset (main.lua, tune.selfCollision "auto") and masses come from
-- active.lua either way. A mesh without CPU access can't be cut: gore says so when it tries.

local M = {}
local ctx
local try, valid

local function cfg() return ctx.tune.physfix or {} end
local function log(s) ctx.log("physfix: " .. s) end
local function name(o) return valid(o) and (try(function() return o:GetFName():ToString() end) or "?") or "<nil>" end

local MAIN = {
  ["Bip001-Pelvis"] = true, ["Bip001-Spine"] = true, ["Bip001-Spine1"] = true, ["Bip001-Spine2"] = true,
  ["Bip001-Neck"] = true, ["Bip001-Head"] = true, ["Bip001-L-Clavicle"] = true, ["Bip001-R-Clavicle"] = true,
  ["Bip001-L-UpperArm"] = true, ["Bip001-R-UpperArm"] = true, ["Bip001-L-Forearm"] = true, ["Bip001-R-Forearm"] = true,
  ["Bip001-L-Hand"] = true, ["Bip001-R-Hand"] = true, ["Bip001-L-Thigh"] = true, ["Bip001-R-Thigh"] = true,
  ["Bip001-L-Calf"] = true, ["Bip001-R-Calf"] = true, ["Bip001-L-Foot"] = true, ["Bip001-R-Foot"] = true,
}
local ACM_LOCKED = 2
local LCM_LOCKED = 2

local seenMesh = nil   -- address of the SkeletalMesh last checked
local fixed = {}       -- physics asset address -> true once its defaults are changed (the asset stays loaded)
local state = nil      -- { patched, cpu, pa } for the current mesh
local locks = {}       -- constraint components made for this ragdoll

function M.init(c)
  ctx = c
  try, valid = c.try, c.valid
end

local function bodies_of(pa)
  local out = {}
  try(function()
    pa.SkeletalBodySetups:ForEach(function(_, e)
      local bs = e:get()
      if valid(bs) then out[#out + 1] = bs end
    end)
  end)
  return out
end

local function constraints_of(pa)
  local out = {}
  try(function()
    pa.ConstraintSetup:ForEach(function(_, e)
      local t = e:get()
      if valid(t) then out[#out + 1] = t end
    end)
  end)
  return out
end

-- the data mod sets LinearDamping 0.2 on the main bodies (vanilla 5.0), as main.lua tells them apart
local function patched(pa)
  for _, bs in ipairs(bodies_of(pa)) do
    if try(function() return bs.BoneName:ToString() end) == "Bip001-Pelvis" then
      return (try(function() return bs.DefaultInstance.LinearDamping end) or 5) < 1.0
    end
  end
  return false
end

-- LOD0's bAllowCPUAccess, nil if it can't be read
local function cpu_access(sk)
  return try(function() return sk.LODInfo[1].bAllowCPUAccess end)
end

local function load(path)
  local o = try(function() return StaticFindObject(path) end)
  if not valid(o) and LoadAsset then o = try(function() return LoadAsset(path) end) end
  return valid(o) and o or nil
end

-- the physics asset a mesh without one should have: "/Game/.../X.X" -> "/Game/.../X_Physics.X_Physics"
local function borrow_physics(sk)
  local full = try(function() return sk:GetFullName() end) or ""
  local pkg, obj = full:match("(/Game/[^%.%s]+)%.([%w_]+)$")
  local tried = {}
  -- a variant's trailing digit (CH_P_EVE_InnerSuit1) is still the same outfit
  for _, base in ipairs({ pkg, pkg and pkg:gsub("%d+$", "") }) do
    if base then
      local dir, leaf = base:match("^(.*)/([^/]+)$")
      local path = string.format("%s/%s_Physics.%s_Physics", dir, leaf, leaf)
      if not tried[path] then
        tried[path] = true
        local o = load(path)
        if o then return o, path end
      end
    end
  end
  local fb = cfg().fallback or "/Game/Art/Character/PC/CH_P_EVE_01/CH_P_EVE_01_Physics.CH_P_EVE_01_Physics"
  return load(fb), fb
end

local function fix_defaults(pa)
  local g = cfg()
  local lin, ang = g.linearDamping or 0.2, g.angularDamping or 1.0
  local nb, nc = 0, 0
  for _, bs in ipairs(bodies_of(pa)) do
    if MAIN[try(function() return bs.BoneName:ToString() end) or ""] then
      if try(function() bs.DefaultInstance.LinearDamping = lin; bs.DefaultInstance.AngularDamping = ang; return true end) then
        nb = nb + 1
      end
    end
  end
  if g.hardLimits ~= false then
    for _, t in ipairs(constraints_of(pa)) do
      local child = try(function() return t.DefaultInstance.ConstraintBone1:ToString() end)
      if MAIN[child or ""] and try(function()
        local p = t.DefaultInstance.ProfileInstance
        p.ConeLimit.bSoftConstraint = false
        p.TwistLimit.bSoftConstraint = false
        return true
      end) then nc = nc + 1 end
    end
  end
  local back = try(function()
    for _, bs in ipairs(bodies_of(pa)) do
      if bs.BoneName:ToString() == "Bip001-Pelvis" then return bs.DefaultInstance.LinearDamping end
    end
  end)
  return string.format("damping %.1f/%.1f on %d main bodies (pelvis reads back %s), hard limits on %d joints",
    lin, ang, nb, back and string.format("%.2f", back) or "?", nc)
end

-- her mesh's physics asset: the component's, else the mesh's, else the one given to this mesh here. A null
-- UObject comes back from UE4SS as an invalid wrapper, which is truthy, so `a() or b()` never reached b().
function M.asset(mesh)
  local pa = try(function() return mesh:GetPhysicsAsset() end)
  if valid(pa) then return pa end
  pa = try(function() return mesh.SkeletalMesh.PhysicsAsset end)
  if valid(pa) then return pa end
  local addr = try(function() return mesh.SkeletalMesh:GetAddress() end)
  if state and state.borrowed and addr and addr == seenMesh and valid(state.pa) then return state.pa end
  return nil
end

-- every gameplay tick: a new outfit mesh is checked once, and an unpatched physics asset fixed (bodies re-made
-- from it while they are kinematic). live: she is ragdolled already, so the bodies are left as they are
function M.check(pawn, mesh, live)
  if cfg().enabled == false then return end
  local sk = try(function() return mesh.SkeletalMesh end)
  local addr = valid(sk) and try(function() return sk:GetAddress() end)
  if not addr then return end
  if addr == seenMesh then
    -- a borrowed asset is the component's own override, which the mesh's own (none) can replace again: gore's undo
    -- and recovery re-make the bodies from the mesh's asset (nineteenth playtest: InnerSuit read no physics asset at
    -- death, so the active ragdoll found no bodies to weigh)
    if not live and state and state.borrowed and valid(state.pa)
      and not valid(try(function() return mesh:GetPhysicsAsset() end)) then
      local ok = try(function() mesh:SetPhysicsAsset(state.pa, true); return true end)
      log(string.format("outfit %s lost the physics asset it was given: %s", name(sk), ok and "given again" or "NOT given again"))
    end
    return
  end
  seenMesh = addr
  local pa = M.asset(mesh)
  local cpu = cpu_access(sk)
  local borrowed = ""
  if not valid(pa) and cfg().borrow ~= false then
    local o, path = borrow_physics(sk)
    if o and try(function() mesh:SetPhysicsAsset(o, true); return true end) then
      pa = o
      borrowed = string.format(" (the mesh has none: gave it %s)", path)
    else
      borrowed = string.format(" (the mesh has none, and %s didn't load: she can't ragdoll)", path)
    end
  end
  local paddr = valid(pa) and try(function() return pa:GetAddress() end)
  -- an asset fixed here reads as patched from then on: it isn't
  state = { patched = valid(pa) and not fixed[paddr or 0] and patched(pa), cpu = cpu, pa = pa, borrowed = borrowed:find("gave it") ~= nil }
  local what = string.format("outfit %s, physics %s%s: %s, LOD0 CPU access %s", name(sk), name(pa), borrowed,
    state.patched and "patched" or "NOT patched", cpu == nil and "unknown" or tostring(cpu))
  if state.patched and cpu ~= false then log(what); return end
  local note = " (an outfit mod the build didn't see, or one that loads after this mod: rerun ./build.sh --install)"
  -- the flag isn't the whole story: InnerSuit read false and still cut (nineteenth playtest)
  if cpu == false then note = note .. "; cuts may not read this mesh (a failed cut logs 'no CPU copy')" end
  if not valid(pa) or state.patched then log(what .. note); return end
  if paddr and not fixed[paddr] then
    fixed[paddr] = true
    what = what .. "; " .. fix_defaults(pa)
  end
  if not live then
    local ok = try(function() mesh:SetPhysicsAsset(pa, true); return true end)
    what = what .. (ok and ", bodies re-made" or ", bodies NOT re-made")
  end
  log(what .. note)
end

-- main.lua's selfCollision "auto" goes by the damping too: an asset fixed here still has vanilla's collision pairs
function M.runtime_fixed(pa)
  local a = valid(pa) and try(function() return pa:GetAddress() end)
  return a and fixed[a] == true or false
end

-- ragdoll start: lock the loose bodies of an unpatched asset to the body above them
function M.start(pawn, mesh)
  M.check(pawn, mesh, true)
  if cfg().enabled == false or cfg().lockLoose == false or not state or state.patched or not valid(state.pa) then return "" end
  local cls = try(function() return StaticFindObject("/Script/Engine.PhysicsConstraintComponent") end)
  if not valid(cls) then return "no PhysicsConstraintComponent class" end
  local has, held = {}, {}
  for _, bs in ipairs(bodies_of(state.pa)) do has[try(function() return bs.BoneName:ToString() end) or ""] = true end
  for _, t in ipairs(constraints_of(state.pa)) do
    held[try(function() return t.DefaultInstance.ConstraintBone1:ToString() end) or ""] = true
  end
  local done = {}
  for b in pairs(has) do
    if b ~= "" and not MAIN[b] and not held[b] then
      local up = try(function() return mesh:GetParentBone(FName(b)):ToString() end)
      while up and up ~= "None" and not has[up] do up = try(function() return mesh:GetParentBone(FName(up)):ToString() end) end
      local at = up and up ~= "None" and try(function() return mesh:GetSocketLocation(FName(b)) end)
      local pc = at and try(function()
        return pawn:AddComponentByClass(cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
          Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
      end)
      if valid(pc) then
        locks[#locks + 1] = pc
        try(function() pc:K2_SetWorldLocation(at, false, {}, true) end)
        try(function() pc:SetLinearXLimit(LCM_LOCKED, 0) end)
        try(function() pc:SetLinearYLimit(LCM_LOCKED, 0) end)
        try(function() pc:SetLinearZLimit(LCM_LOCKED, 0) end)
        try(function() pc:SetAngularSwing1Limit(ACM_LOCKED, 0) end)
        try(function() pc:SetAngularSwing2Limit(ACM_LOCKED, 0) end)
        try(function() pc:SetAngularTwistLimit(ACM_LOCKED, 0) end)
        if try(function() pc:SetConstrainedComponents(mesh, FName(up), mesh, FName(b)); return true end) then
          done[#done + 1] = b .. ">" .. up
        end
      end
    end
  end
  local s = #done > 0 and ("loose bodies locked: " .. table.concat(done, ", ")) or "no loose bodies"
  log(s)
  return s
end

-- recovery: the locks go (the mesh's bodies are re-made by the game anyway)
function M.stop()
  for _, pc in ipairs(locks) do
    if valid(pc) then
      try(function() pc:BreakConstraint() end)
      try(function() pc:K2_DestroyComponent(pc) end)
    end
  end
  locks = {}
  -- the respawn may hand her the same mesh with bodies made from scratch: check again
  seenMesh = nil
end

-- a reloaded level: everything held is gone (the assets' changed defaults stay with them)
function M.forget()
  locks, seenMesh, state = {}, nil, nil
end

return M
