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
--   * jiggle bodies: the torso's (breasts, belly and hip correctives) sit inside her and shove her arms and torso
--     every frame; they collide with nothing (the data mod keeps every accessory off her bodies, by the collision
--     table, which can't be reached from here).
--   * loose bodies: twist and helper bones that carry a cape or skirt chain, with a body but no joint to anything
--     (in a ragdoll they fly off and drag the arm's skin with them), get a locked constraint to the nearest body
--     above them while she is ragdolled.
--   * no physics asset at all: an outfit mod's mesh exported without one (Eve with no Clothes on) has no bodies,
--     so she can't ragdoll. It gets the asset next to it by the game's naming (<mesh>_Physics, which the data mod
--     ships patched), else tune.physfix.fallback (Eve's base body's).
-- Self-collision is already off for an unpatched asset (main.lua, tune.selfCollision "auto") and masses come from
-- active.lua either way. CPU access needs nothing from here: sbslice.dll makes the engine keep every skeletal mesh's
-- LOD0 CPU copy (its NeedCPUData patch), so any outfit can be cut; without the DLL a mesh lacking it can't be.

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

-- the torso's jiggle bodies (breasts, belly and hip correctives): a leaf body whose nearest body above is one of these
local TORSO = { ["Bip001-Pelvis"] = true, ["Bip001-Spine"] = true, ["Bip001-Spine1"] = true, ["Bip001-Spine2"] = true,
  ["Bip001-Neck"] = true }

-- the data mod keeps every accessory body from touching her (patch_shows.py, accessory_collision); from here the
-- collision table can't be reached, so the torso's jiggle bodies get the body's own "collides with nothing"
-- (UBodySetup.CollisionReponse, the engine's spelling): they sit inside her chest and shoved her arms and torso
-- every frame, and she buzzed on the floor (CH_P_EVE_30's breasts; CH_P_EVE_10 has none and lay still). Only
-- leaves: a cape or skirt chain keeps the floor under it
local function quiet_jiggle(pa, mesh)
  local list, has, above = bodies_of(pa), {}, {}
  for _, bs in ipairs(list) do has[try(function() return bs.BoneName:ToString() end) or ""] = true end
  local inner = {}
  for b in pairs(has) do
    if b ~= "" and not MAIN[b] then
      local up = try(function() return mesh:GetParentBone(FName(b)):ToString() end)
      while up and up ~= "None" and not has[up] do up = try(function() return mesh:GetParentBone(FName(up)):ToString() end) end
      if up and up ~= "None" then above[b] = up; inner[up] = true end
    end
  end
  local done = {}
  for _, bs in ipairs(list) do
    local b = try(function() return bs.BoneName:ToString() end) or ""
    if above[b] and TORSO[above[b]] and not inner[b] and try(function() bs.CollisionReponse = 1; return true end) then
      done[#done + 1] = b
    end
  end
  table.sort(done)
  return #done > 0 and string.format("%d jiggle bodies collide with nothing (%s)", #done, table.concat(done, " "))
    or "no jiggle bodies in the torso"
end

-- Every outfit, patched or not: an outfit's breasts, neck pieces, arm twists and armour plates are authored kinematic
-- (PhysType_Kinematic) on joints of 0.1-1 deg with soft stiffness, to ride their bone while she lives. The ragdoll
-- simulates every body, and those light bodies fought their stiff joints: she buzzed and spun on every outfit but
-- CH_P_EVE_10, whose only extra bodies are its simulated hair and the hips. Their joints are locked solid now, so they
-- ride their bone as one with it. (Keeping them kinematic instead pinned her: an immovable body jointed to the chest
-- and thighs held her half of a split standing while the copy fell, playtest.)
local welded = {}      -- physics asset address -> true once its kinematic accessories' joints are locked
local steadied = {}    -- physics asset address -> true once its solver and end damping are set

-- every asset: more solver iterations on every body (the engine's 8 position / 1 velocity let joints come apart and
-- snap back: a ragdoll that started mid-fall shot her off at 10-23 m/s, and her hands and head spun at the cap for
-- seconds, thirty-fourth playtest), and the head, hands and feet turn-damped (light ends on a loose joint flick about)
local ENDS = { ["Bip001-Head"] = "head", ["Bip001-L-Hand"] = "hands", ["Bip001-R-Hand"] = "hands",
  ["Bip001-L-Foot"] = "feet", ["Bip001-R-Foot"] = "feet" }
local function steady(pa)
  local g = cfg()
  local pos, vel = g.positionIterations or 16, g.velocityIterations or 4
  local damp = g.endsAngularDamping or { head = 2.0, hands = 3.0, feet = 3.0 }
  local n, e = 0, 0
  for _, bs in ipairs(bodies_of(pa)) do
    if try(function()
      local d = bs.DefaultInstance
      if d.PositionSolverIterationCount < pos then d.PositionSolverIterationCount = pos end
      if d.VelocitySolverIterationCount < vel then d.VelocitySolverIterationCount = vel end
      return true
    end) then n = n + 1 end
    local k = ENDS[try(function() return bs.BoneName:ToString() end) or ""]
    if k and damp[k] and try(function()
      if bs.DefaultInstance.AngularDamping < damp[k] then bs.DefaultInstance.AngularDamping = damp[k] end
      return true
    end) then e = e + 1 end
  end
  return string.format("solver %d/%d on %d bodies, %d ends turn-damped", pos, vel, n, e)
end
-- Only a joint to the body right above it in her skeleton: the hips (Ab-L/R-Hip) hang under the thighs but are jointed
-- to Bip001-Spine, and locked that welded each thigh to her spine (a cut leg stayed on, her legs couldn't swing, every
-- outfit, playtest). Such cross joints keep the author's soft limits.
local function weld_kinematic(pa, mesh)
  local kin, has = {}, {}
  for _, bs in ipairs(bodies_of(pa)) do
    local b = try(function() return bs.BoneName:ToString() end) or ""
    local t = try(function() return bs.PhysicsType end)
    has[b] = true
    if b ~= "" and not MAIN[b] and (t == 1 or tostring(t):find("Kinematic") ~= nil) then kin[b] = true end
  end
  -- nil when the way up crosses a limb bone without a body (EVE_21 has no thigh bodies: Ab-L-Thigh-Tw0 under
  -- Bip001-L-Thigh is jointed to Bip001-Spine, and locked it held her leg to the spine)
  local function above(b)
    local up = try(function() return mesh:GetParentBone(FName(b)):ToString() end)
    while up and up ~= "None" and not has[up] do
      if MAIN[up] then return nil end
      up = try(function() return mesh:GetParentBone(FName(up)):ToString() end)
    end
    return up
  end
  local done = {}
  for _, t in ipairs(constraints_of(pa)) do
    local child = try(function() return t.DefaultInstance.ConstraintBone1:ToString() end)
    local parent = try(function() return t.DefaultInstance.ConstraintBone2:ToString() end)
    if child and kin[child] and parent and above(child) == parent and try(function()
      local p = t.DefaultInstance.ProfileInstance
      p.ConeLimit.Swing1Motion = ACM_LOCKED
      p.ConeLimit.Swing2Motion = ACM_LOCKED
      p.TwistLimit.TwistMotion = ACM_LOCKED
      p.LinearLimit.XMotion = LCM_LOCKED
      p.LinearLimit.YMotion = LCM_LOCKED
      p.LinearLimit.ZMotion = LCM_LOCKED
      return true
    end) then done[#done + 1] = child end
  end
  table.sort(done)
  return done
end

local function fix_defaults(pa, mesh)
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
  local q = g.quietJiggle ~= false and (", " .. quiet_jiggle(pa, mesh)) or ""
  return string.format("damping %.1f/%.1f on %d main bodies (pelvis reads back %s), hard limits on %d joints%s",
    lin, ang, nb, back and string.format("%.2f", back) or "?", nc, q)
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
    local now = try(function() return mesh:GetPhysicsAsset() end)
    if not live and state and state.borrowed and valid(state.pa)
      and not (valid(now) and try(function() return now:GetAddress() == state.pa:GetAddress() end)) then
      local ok = try(function() mesh:SetPhysicsAsset(state.pa, true); return true end)
      state.lost = (state.lost or 0) + 1
      if state.lost <= 3 or not ok then
        log(string.format("outfit %s lost the physics asset it was given: %s%s", name(sk), ok and "given again" or "NOT given again",
          state.lost == 3 and " (not logged again)" or ""))
      end
    end
    return
  end
  seenMesh = addr
  local pa = M.asset(mesh)
  local cpu = cpu_access(sk)
  local borrowed = ""
  if not valid(pa) and cfg().borrow ~= false then
    local o, path = borrow_physics(sk)
    -- on the mesh asset too: the game drops the component's override on every outfit apply and gore's undo, and a
    -- death started with none (InnerSuit, physics <nil>, after a dozen "given again" in a second)
    if o then try(function() sk.PhysicsAsset = o end) end
    if o and try(function() mesh:SetPhysicsAsset(o, true); return true end) then
      pa = o
      borrowed = string.format(" (the mesh has none: gave it %s)", path)
    else
      borrowed = string.format(" (the mesh has none, and %s didn't load: she can't ragdoll)", path)
    end
  end
  -- an asset missing main bodies (CH_P_EVE_21 has no thighs: its calves are jointed to the spine) can't ragdoll or
  -- lose a limb right: a body-less thigh's skin stays on the hip while the calf flies, and the clothes on it
  -- stretched between them (playtest 30). Such an outfit gets a complete asset instead (its skirt bodies go: the
  -- skirt rides its bones)
  if valid(pa) and cfg().complete ~= false then
    local has, miss = {}, {}
    for _, bs in ipairs(bodies_of(pa)) do has[try(function() return bs.BoneName:ToString() end) or ""] = true end
    for b in pairs(MAIN) do if not has[b] then miss[#miss + 1] = b:gsub("^Bip001%-", "") end end
    if #miss > 0 then
      table.sort(miss)
      local path = cfg().completeWith or "/Game/Art/Character/PC/CH_P_EVE_InnerSuit/CH_P_EVE_InnerSuit_Physics.CH_P_EVE_InnerSuit_Physics"
      local o = load(path)
      local own = name(pa)
      if o and o ~= pa then
        try(function() sk.PhysicsAsset = o end)
        if try(function() mesh:SetPhysicsAsset(o, true); return true end) then
          pa = o
          borrowed = string.format(" (its own %s has no body on %s: gave it %s)", own, table.concat(miss, ","), path)
        end
      else
        borrowed = string.format(" (no body on %s, and %s didn't load)", table.concat(miss, ","), path)
      end
    end
  end
  local paddr = valid(pa) and try(function() return pa:GetAddress() end)
  local weld = ""
  if paddr and not steadied[paddr] and cfg().steady ~= false then
    steadied[paddr] = true
    weld = "; " .. steady(pa)
    if not live then
      local ok = try(function() mesh:SetPhysicsAsset(pa, true); return true end)
      weld = weld .. (ok and ", bodies re-made" or ", bodies NOT re-made")
    end
  end
  if paddr and not welded[paddr] and cfg().weldKinematic ~= false then
    welded[paddr] = true
    local w = weld_kinematic(pa, mesh)
    if #w > 0 then
      weld = string.format("; %d kinematic accessory joints locked (%s)", #w, table.concat(w, " "))
      if not live then
        local ok = try(function() mesh:SetPhysicsAsset(pa, true); return true end)
        weld = weld .. (ok and ", bodies re-made" or ", bodies NOT re-made")
      end
    end
  end
  -- an asset fixed here reads as patched from then on: it isn't
  state = { patched = valid(pa) and not fixed[paddr or 0] and patched(pa), cpu = cpu, pa = pa, borrowed = borrowed:find("gave it") ~= nil }
  -- (the asset's flag; sbslice.dll keeps every skeletal mesh's LOD0 CPU copy whatever it says)
  local forced = ctx and ctx.cpu_forced
  local what = string.format("outfit %s, physics %s%s: %s, LOD0 CPU access %s%s", name(sk), name(pa), borrowed,
    state.patched and "patched" or "NOT patched", forced and "kept by sbslice.dll" or cpu == nil and "unknown" or tostring(cpu), weld)
  if state.patched and (cpu ~= false or forced) then log(what); return end
  local note = forced and " (an outfit the build didn't see: its physics fixed from here)"
    or " (an outfit mod the build didn't see, or one that loads after this mod: rerun ./build.sh --install)"
  -- the flag isn't the whole story: InnerSuit read false and still cut (nineteenth playtest)
  if cpu == false and not forced then note = note .. "; cuts may not read this mesh (a failed cut logs 'no CPU copy')" end
  if not valid(pa) or state.patched then log(what .. note); return end
  if paddr and not fixed[paddr] then
    fixed[paddr] = true
    what = what .. "; " .. fix_defaults(pa, mesh)
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
