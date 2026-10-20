-- gore.lua: dismemberment and blood for Eve.
--
-- Cutting (sbslice.dll, see "skin cut" in native/sbslice/sbslice.c): the DLL splits her skin weights at a plane
-- through a limb, so the limb side follows only limb bones and the body side only body bones, collapses the
-- triangles across the cut onto helper bones next to the joint, and reports where both openings are. This
-- script then breaks the ragdoll constraint at that limb (its bodies carry the piece away), covers both
-- openings with a flesh cap and adds blood. The game's own slicer can't do this on Eve: it hides the cut region
-- through a material parameter only its gore master has. Eve needs LOD0 CPU access on her outfit mesh for the
-- DLL to read it (data mod, mode "cpuaccess").
-- The DLL is reached through the unused cheat SBRewardGroupDropFormationPathLocation, which it repoints.
-- Blood: the game's own Niagara systems, spawned on hits, on the cut and as a pool under the body.
-- Everything here is undone when she recovers (skin weights, the collapsed helper bones on the shared mesh
-- asset, caps, effects, broken constraints, forced LOD).

local M = {}
local ctx -- log, try, valid, v3, tune (set by M.init)

local UFUNC = "/Script/SB.SBCheatManager:SBRewardGroupDropFormationPathLocation"
local CHEAT_CDO = "/Script/SB.Default__SBCheatManager"
local REQ = "ue4ss/Mods/EveRagdollProbe/sbslice.req"
local OK = "ue4ss/Mods/EveRagdollProbe/sbslice.ok"
local ERR = "ue4ss/Mods/EveRagdollProbe/sbslice.err"
local RESULT = "ue4ss/Mods/EveRagdollProbe/sbslice.cut"
-- limbs that can come off, and the next joint along each one (the cut plane is perpendicular to it)
local CHILD = {
  ["Bip001-L-UpperArm"] = "Bip001-L-Forearm",
  ["Bip001-R-UpperArm"] = "Bip001-R-Forearm",
  ["Bip001-L-Forearm"] = "Bip001-L-Hand",
  ["Bip001-R-Forearm"] = "Bip001-R-Hand",
  ["Bip001-L-Thigh"] = "Bip001-L-Calf",
  ["Bip001-R-Thigh"] = "Bip001-R-Calf",
  ["Bip001-L-Calf"] = "Bip001-L-Foot",
  ["Bip001-R-Calf"] = "Bip001-R-Foot",
  ["Bip001-Spine1"] = "Bip001-Spine2",
}
-- where along the limb "auto" cuts (0 = joint, 1 = next joint): close to the joint, so the stump that now
-- follows the body rigidly stays short
local CUT_AT = { ["Bip001-Spine1"] = 0.5 }
local CUT_AT_DEFAULT = 0.15
-- "auto" picks among these (no torso unless tune allows it, no lower limbs: a whole limb reads better)
local AUTO = { "Bip001-L-UpperArm", "Bip001-R-UpperArm", "Bip001-L-Thigh", "Bip001-R-Thigh" }
local FX = {
  slice = "/Game/Art/FX/Char/Common/Hit/Flesh/NS_Hit_Flesh_Slice_Big.NS_Hit_Flesh_Slice_Big",
  bleed = "/Game/Art/FX/Char/Common/Hit/Link/NS_Blood_Flooded_Attached.NS_Blood_Flooded_Attached",
  hit = "/Game/Art/FX/Char/Common/Hit/NS_HitBlood_Monster_01_Strong_Bld_02.NS_HitBlood_Monster_01_Strong_Bld_02",
  splat = "/Game/Art/FX/Char/Common/Hit/NS_HitBlood_SpawnDecal_L.NS_HitBlood_SpawnDecal_L",
  pool = "/Game/Art/FX/Char/Common/Hit/Link/NS_Blood_FloorDecalLoop.NS_Blood_FloorDecalLoop",
}
-- the cap: the engine's sphere (radius 50) flattened onto the opening, with the game's cut-flesh material
local CAP_MESH = "/Engine/BasicShapes/Sphere.Sphere"
local CAP_MATERIAL = "/Game/Art/FX/Char/Common/Hit/Flesh/MI_CutDamage.MI_CutDamage"

local native = { state = "init", waited = 0 }
local spawned = {}  -- Niagara components to remove on recovery
local bleeds = {}   -- { comp, left } looping bleed effects, stopped after tune.gore.bleedTime
local caps = {}     -- cap actors
local cuts = {}     -- { mesh, addr, bone } per cut, in order
local forced = {}   -- mesh addresses this script forced to LOD0
-- the cut in progress, in stages a few ticks apart (see M.slice): { stage, wait, pawn, mesh, hit, why, ... }
local pending = nil
local collision_saved = nil -- the living mesh's collision setup, while a cut piece needs world collision
local TICK_S = 0.033 -- main.lua polls every 33 ms
local cache = {}

local function cfg() return ctx.tune.gore or {} end
local function log(s) ctx.log("gore: " .. s) end
local try, valid, v3 = nil, nil, nil

local function file_exists(p) local f = io.open(p, "r"); if f then f:close(); return true end; return false end
local function read_file(p) local f = io.open(p, "r"); if not f then return nil end; local s = f:read("a"); f:close(); return s end

local function load_obj(path)
  -- nothing roots the Niagara systems once their components are cleaned up, so GC frees them; a cached
  -- wrapper then points at a dead object (crash on the next death's blood spawn). Re-check every use.
  if cache[path] and valid(cache[path]) then return cache[path] end
  local o = try(function() return StaticFindObject(path) end)
  if not valid(o) and LoadAsset then o = try(function() return LoadAsset(path) end) end
  if not valid(o) then o = try(function() return StaticFindObject(path) end) end
  cache[path] = valid(o) and o or false
  if not valid(o) then log("could not load " .. path) end
  return valid(o) and o or nil
end

local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local function sub(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
local function add(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
local function scale(a, s) return vec(a.X * s, a.Y * s, a.Z * s) end
local function norm(a)
  local l = math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
  return l > 1e-4 and scale(a, 1 / l) or nil
end

-- one command to sbslice.dll (see exec_slice there); the answer it leaves in sbslice.cut
local function command(s, p, n)
  os.remove(RESULT)
  local cdo = load_obj(CHEAT_CDO)
  if not cdo then return "err no cheat manager" end
  p, n = p or vec(0, 0, 0), n or vec(0, 0, 0)
  local ok, err = pcall(function()
    cdo:SBRewardGroupDropFormationPathLocation(FName("None"), p.X, p.Y, p.Z, s, n.X, n.Y, n.Z)
  end)
  if not ok then return "err call: " .. tostring(err) end
  return read_file(RESULT) or "err no answer"
end

-- handshake with sbslice.dll: hand it the UFunction to repoint, then wait for its answer
local function native_tick()
  if native.state == "ready" or native.state == "failed" then return end
  if native.state == "init" then
    os.remove(OK); os.remove(ERR)
    local f = try(function() return StaticFindObject(UFUNC) end)
    if not valid(f) then native.state = "failed"; log("no " .. UFUNC); return end
    local w = io.open(REQ, "w")
    if not w then native.state = "failed"; log("cannot write " .. REQ); return end
    w:write(string.format("%x", f:GetAddress())); w:close()
    native.state = "waiting"
    log(string.format("asked sbslice.dll to take over %s (UFunction %x)", UFUNC, f:GetAddress()))
    return
  end
  native.waited = native.waited + 1
  if file_exists(OK) then
    native.state = "ready"
    -- a reloaded script forgets its cuts, the DLL doesn't: put back anything a previous run left collapsed
    log("sbslice.dll ready: " .. tostring(read_file(OK)) .. ", leftovers: " .. command("r"))
  elseif file_exists(ERR) then
    native.state = "failed"; log("sbslice.dll refused: " .. tostring(read_file(ERR)))
  elseif native.waited > 150 then
    native.state = "failed"
    log("sbslice.dll did not answer (is Mods/SBSlice/dlls/main.dll installed and SBSlice : 1 in mods.txt?)")
  end
end

function M.init(c)
  ctx = c
  try, valid, v3 = c.try, c.valid, c.v3
end

local function niagara(sys_path, comp, bone, loc, attached)
  local sys = load_obj(sys_path)
  local lib = load_obj("/Script/Niagara.Default__NiagaraFunctionLibrary")
  if not (sys and lib) then return nil end
  local c
  if attached then
    -- EAttachLocation::SnapToTarget = 2, ENCPoolMethod::None = 0
    c = try(function() return lib:SpawnSystemAttached(sys, comp, FName(bone or "None"), vec(0, 0, 0),
      { Pitch = 0, Yaw = 0, Roll = 0 }, 2, false, true, 0, false) end)
  else
    c = try(function() return lib:SpawnSystemAtLocation(comp, sys, loc, { Pitch = 0, Yaw = 0, Roll = 0 },
      vec(1, 1, 1), false, true, 0, false) end)
  end
  if valid(c) then spawned[#spawned + 1] = c end
  return c
end

local function bone_loc(mesh, b) return try(function() return mesh:GetSocketLocation(FName(b)) end) end
local function parent_bone(mesh, b)
  local p = try(function() return mesh:GetParentBone(FName(b)):ToString() end)
  return p ~= "None" and p or nil
end
local function addr(o) return try(function() return o:GetAddress() end) end
local function already_cut(mesh, bone)
  local a = addr(mesh)
  for _, c in ipairs(cuts) do if c.addr == a and c.bone == bone then return true end end
  return false
end

-- the limbs to try, closest to the hit first; only the one tune names, if it names one
local function rank_bones(mesh, hit)
  local want = cfg().bone or "auto"
  if CHILD[want] then return already_cut(mesh, want) and {} or { want } end
  local list = {}
  local pool = { table.unpack(AUTO) }
  if cfg().allowTorso then pool[#pool + 1] = "Bip001-Spine1" end
  for _, bone in ipairs(pool) do
    if not already_cut(mesh, bone) then
      local l = bone_loc(mesh, bone)
      local d = (l and hit) and math.sqrt((l.X - hit.X) ^ 2 + (l.Y - hit.Y) ^ 2 + (l.Z - hit.Z) ^ 2) or math.random()
      list[#list + 1] = { bone = bone, d = d }
    end
  end
  table.sort(list, function(x, y) return x.d < y.d end)
  for i, e in ipairs(list) do list[i] = e.bone end
  return list
end

local function num(r, key) return tonumber(r:match(" " .. key .. "=(%-?[%d.]+)")) end
local function triple(r, key, k)
  local x, y, z = r:match(" " .. key .. "=(%-?[%d.]+),(%-?[%d.]+),(%-?[%d.]+)")
  if not x then return nil end
  return vec(tonumber(x) * k, tonumber(y) * k, tonumber(z) * k)
end
-- one opening from the DLL's answer: centre, major axis, normal, half extents (major, minor, depth)
local function opening(r, tag)
  local o = { c = triple(r, tag .. "c", 1), x = triple(r, tag .. "x", 0.001), z = triple(r, tag .. "z", 0.001),
    e = triple(r, tag .. "e", 1) }
  if not (o.c and o.x and o.z and o.e) then return nil end
  -- the outline: rim points in order, counter-clockwise seen from the side the normal points to
  local list = r:match(" " .. tag .. "p=([%d%.,;%-]+)")
  if list then
    o.p = {}
    for x, y, z in list:gmatch("(%-?[%d.]+),(%-?[%d.]+),(%-?[%d.]+)") do o.p[#o.p + 1] = vec(tonumber(x), tonumber(y), tonumber(z)) end
    if #o.p < 3 then o.p = nil end
  end
  return o
end

local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function cross(a, b) return vec(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end

-- the lid as a procedural mesh: the outline (pushed out a little past the skin), a ring halfway in and the centre
-- raised into a low dome, both faces. Vertices relative to the actor at the outline's centroid.
local function lid_mesh(o, k)
  local n = #o.p
  local c = vec(0, 0, 0)
  for _, q in ipairs(o.p) do c = add(c, q) end
  c = scale(c, 1 / n)
  local z = o.z
  local r = 0
  for _, q in ipairs(o.p) do local d = sub(q, c); r = r + math.sqrt(dot(d, d) - dot(d, z) ^ 2) end
  r = r / n
  local dome = math.min(math.max(r * 0.18, 0.4), 1.8)
  local u = norm(sub(o.p[1], add(c, scale(z, dot(sub(o.p[1], c), z))))) or o.x
  local w = cross(z, u)
  local verts, normals, uvs, tris = {}, {}, {}, {}
  local function vert(pos, nrm)
    verts[#verts + 1] = pos
    normals[#normals + 1] = nrm
    uvs[#uvs + 1] = { X = dot(pos, u) / 12 + 0.5, Y = dot(pos, w) / 12 + 0.5 }
    return #verts - 1
  end
  for side = 1, 2 do
    local nz = side == 1 and z or scale(z, -1)
    local base = #verts
    vert(scale(z, dome), nz) -- centre
    for _, q in ipairs(o.p) do
      local d = sub(q, c)
      local h = dot(d, z)
      local flat = sub(d, scale(z, h))
      vert(add(scale(flat, k), scale(z, h + 0.2)), nz)                 -- rim
      vert(add(scale(flat, k * 0.55), scale(z, h * 0.5 + dome * 0.7)), nz) -- inner ring
    end
    -- the outline runs counter-clockwise seen from +z; UE's front faces are clockwise, so the +z face lists
    -- each triangle backwards and the -z face forwards
    for i = 0, n - 1 do
      local j = (i + 1) % n
      local ri, ii, rj, ij = base + 1 + 2 * i, base + 2 + 2 * i, base + 1 + 2 * j, base + 2 + 2 * j
      local quad = { { ri, rj, ij }, { ri, ij, ii }, { ii, ij, base } }
      for _, t in ipairs(quad) do
        if side == 1 then tris[#tris + 1] = t[3]; tris[#tris + 1] = t[2]; tris[#tris + 1] = t[1]
        else tris[#tris + 1] = t[1]; tris[#tris + 1] = t[2]; tris[#tris + 1] = t[3] end
      end
    end
  end
  return c, verts, tris, normals, uvs
end

-- one cap over an opening, riding on the bone that carries that side: the lid mesh when the DLL sent an
-- outline and the procedural mesh takes it, else a flattened sphere fitted to the opening
local function cap(pawn, mesh, o, bone)
  if not o then return end
  local g = cfg()
  local mat = load_obj(g.capMaterial or CAP_MATERIAL)
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  local km = load_obj("/Script/Engine.Default__KismetMathLibrary")
  local cls = load_obj("/Script/Engine.StaticMeshActor")
  if not (gs and km and cls) then return end
  local spawn_at = function(at)
    local tm = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = at, Scale3D = vec(1, 1, 1) }
    local a = try(function()
      local d = gs:BeginDeferredActorSpawnFromClass(pawn, cls, tm, 1, nil)
      return gs:FinishSpawningActor(d, tm)
    end)
    if not valid(a) then return nil end
    caps[#caps + 1] = a
    try(function() a:SetActorHiddenInGame(true) end)
    local root = try(function() return a.StaticMeshComponent end)
    if valid(root) then
      -- a spawned StaticMeshActor is static: it can't take a mesh or follow a bone until it is movable
      try(function() root:SetMobility(2) end)
      try(function() root:SetCollisionEnabled(0) end)
    end
    return a, root
  end
  local kind
  local a, root
  local pmc_cls = o.p and load_obj("/Script/ProceduralMeshComponent.ProceduralMeshComponent")
  if pmc_cls then
    local c, verts, tris, normals, uvs = lid_mesh(o, g.capScale or 1.05)
    a, root = spawn_at(c)
    if not a then log("cap: spawn failed"); return end
    local pmc = try(function()
      return a:AddComponentByClass(pmc_cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }, false)
    end)
    if valid(pmc) then
      -- 4.27 takes UV0..UV3; older builds only UV0
      local made = try(function() pmc:CreateMeshSection_LinearColor(0, verts, tris, normals, uvs, {}, {}, {}, {}, {}, false); return true end)
        or try(function() pmc:CreateMeshSection_LinearColor(0, verts, tris, normals, uvs, {}, {}, false); return true end)
      local sections = made and try(function() return pmc:GetNumSections() end) or 0
      if sections > 0 then
        if mat then try(function() pmc:SetMaterial(0, mat) end) end
        try(function() pmc:SetCollisionEnabled(0) end)
        try(function() pmc:SetCastShadow(false) end)
        kind = string.format("lid %d points", #o.p)
      else
        try(function() pmc:K2_DestroyComponent(pmc) end)
      end
    end
  end
  if not kind then
    -- fallback: the engine's sphere (radius 50) squashed onto the opening's ellipse
    local sm = load_obj(g.capMesh or CAP_MESH)
    if not sm then return end
    if not a then
      a, root = spawn_at(o.c)
      if not a then log("cap: spawn failed"); return end
    end
    if valid(root) then
      try(function() root:SetStaticMesh(sm) end)
      if mat then try(function() root:SetMaterial(0, mat) end) end
    end
    local k = (g.capScale or 1.05) / 50
    local depth = math.min(math.max(0.3 * math.min(o.e.X, o.e.Y), 0.8), 2.5)
    local rot = try(function() return km:MakeRotFromXZ(o.x, o.z) end)
    if rot then try(function() a:K2_SetActorRotation(rot, false) end) end
    try(function() a:SetActorScale3D(vec(o.e.X * k, o.e.Y * k, depth / 50)) end)
    kind = "sphere"
  end
  -- EAttachmentRule::KeepWorld = 1
  try(function() a:K2_AttachToComponent(mesh, FName(bone), 1, 1, 1, false) end)
  return a, kind
end

local function cut_limb(pawn, mesh, bone, why)
  local g = cfg()
  local a, b = bone_loc(mesh, bone), bone_loc(mesh, CHILD[bone])
  if not (a and b) then log("cut skipped: no bone transform for " .. tostring(bone)); return nil end
  local axis = norm(sub(b, a))
  if not axis then return nil end
  local t = tonumber(g.cutAt) or CUT_AT[bone] or CUT_AT_DEFAULT
  local at = add(a, scale(sub(b, a), t))
  -- tilted a little so it doesn't look machined
  local tilt = g.tilt or 0.25
  local n = norm(add(axis, vec((math.random() - 0.5) * tilt, (math.random() - 0.5) * tilt, (math.random() - 0.5) * tilt))) or axis
  local index = try(function() return mesh:GetBoneIndex(FName(bone)) end)
  if not index or index < 0 then log("cut skipped: no bone " .. bone); return nil end
  local r = command(string.format("c%x,0,%x", mesh:GetAddress(), index), at, n)
  log(string.format("cut %s (%s) at %.2f %s normal %s: %s", bone, why, t, v3(at), v3(n), r))
  if r:sub(1, 2) ~= "ok" or (num(r, "limb") or 0) == 0 or (num(r, "seam") or 0) == 0 then return nil end
  return { at = at, n = n, result = r }
end

-- stage 1: new weights on the GPU, caps placed (hidden); nothing visible changes yet
local function stage_cut(q)
  for _, b in ipairs(rank_bones(q.mesh, q.hit)) do
    q.c = cut_limb(q.pawn, q.mesh, b, q.why)
    if q.c then q.bone = b; break end
  end
  if not q.bone then log("nothing cut (" .. q.why .. ")"); return false end
  cuts[#cuts + 1] = { mesh = q.mesh, addr = addr(q.mesh), bone = q.bone }
  q.parent = parent_bone(q.mesh, q.bone)
  q.caps, q.kinds = {}, {}
  if cfg().caps ~= false then
    q.caps[1], q.kinds[1] = cap(q.pawn, q.mesh, opening(q.c.result, "b"), q.parent or q.bone)
    q.caps[2], q.kinds[2] = cap(q.pawn, q.mesh, opening(q.c.result, "l"), q.bone)
  end
  return true
end

-- stage 2, once those weights are in use: collapse the seam, let the limb go, show the caps, bleed
local function stage_open(q)
  local g = cfg()
  local k = command("k")
  -- on a living Eve the mesh has no physics collision with the world, so the piece would fall through the floor:
  -- give it the death ragdoll's profile until she recovers (her own bodies stay kinematic)
  local world = ""
  if not collision_saved and try(function() return q.mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end) ~= true then
    local c = { mesh = q.mesh, resp = {} }
    c.obj = try(function() return q.mesh:GetCollisionObjectType() end)
    c.enabled = try(function() return q.mesh:GetCollisionEnabled() end)
    c.profile = try(function() return q.mesh:GetCollisionProfileName():ToString() end)
    for ch = 0, 31 do c.resp[ch] = try(function() return q.mesh:GetCollisionResponseToChannel(ch) end) end
    try(function() q.mesh:SetCollisionProfileName(FName("Ragdoll"), true) end)
    collision_saved = c
    world = string.format(", world collision on (was %s, enabled %s)", tostring(c.profile), tostring(c.enabled))
  end
  -- off it goes: the constraint at the limb's root breaks (its bodies start simulating if she was alive)
  local broke = try(function() q.mesh:BreakConstraint(vec(0, 0, 0), q.c.at, FName(q.bone)); return true end)
  local throw = g.throw or 250
  if throw > 0 then
    local v = norm(add(q.c.n, vec((math.random() - 0.5) * 0.6, (math.random() - 0.5) * 0.6, 0.4))) or q.c.n
    try(function() q.mesh:AddImpulse(scale(v, throw), FName(q.bone), true) end)
  end
  for _, a in pairs(q.caps) do if valid(a) then try(function() a:SetActorHiddenInGame(false) end) end end
  if g.blood ~= false then
    if g.sliceFx == true then niagara(FX.slice, q.pawn, nil, q.c.at, false) end
    niagara(FX.splat, q.pawn, nil, q.c.at, false)
    -- bleed from both sides of the wound, for a while
    local left = math.floor((g.bleedTime or 2.5) / TICK_S + 0.5)
    local function bleed(bone)
      local c = niagara(FX.bleed, q.mesh, bone, nil, true)
      if c and left > 0 then bleeds[#bleeds + 1] = { comp = c, left = left } end
    end
    if q.parent then bleed(q.parent) end
    bleed(CHILD[q.bone])
  end
  log(string.format("%s off (%s): %s, constraint broken=%s, caps %s / %s%s", q.bone, q.why, k, tostring(broke == true),
    tostring(q.kinds[1]), tostring(q.kinds[2]), world))
end

-- a cut runs in stages a few ticks apart, so no frame shows a half-made cut: LOD0 forced (the cut is made in
-- LOD0's weights; bones LOD0 adds aren't posed until the switch went through), then the new weights (uploaded to
-- the GPU by the render thread), then the collapse that opens the seam (on the game thread, immediately)
function M.slice(pawn, mesh, hit, why)
  local g = cfg()
  if g.enabled == false then return false end
  if native.state ~= "ready" then log("cut skipped (" .. why .. "): sbslice.dll is " .. native.state); return false end
  if pending then log("cut skipped (" .. why .. "): another cut is still opening"); return false end
  local a = addr(mesh)
  pending = { stage = "cut", wait = forced[a] and 0 or 2, pawn = pawn, mesh = mesh, hit = hit, why = why }
  if not forced[a] then try(function() mesh:SetForcedLOD(1) end); forced[a] = true end
  M.tick(pawn)
  return true
end

function M.tick(pawn)
  if cfg().enabled == false then return end
  native_tick()
  for i = #bleeds, 1, -1 do
    local b = bleeds[i]
    b.left = b.left - 1
    if b.left <= 0 or not valid(b.comp) then
      -- Deactivate lets the drops already in the air finish
      if valid(b.comp) then try(function() b.comp:Deactivate() end) end
      table.remove(bleeds, i)
    end
  end
  local q = pending
  if not q then return end
  if not valid(q.mesh) then pending = nil; return end
  if q.wait > 0 then q.wait = q.wait - 1; return end
  if q.stage == "cut" then
    if stage_cut(q) then q.stage = "open"; q.wait = 2; return end
    pending = nil
    -- nothing came off: give the LOD back unless an earlier cut still needs it
    local a = addr(q.mesh)
    for _, c in ipairs(cuts) do if c.addr == a then return end end
    forced[a] = nil
    try(function() q.mesh:SetForcedLOD(0) end)
  else
    pending = nil
    stage_open(q)
  end
end

function M.on_hit(pawn, mesh, at)
  if cfg().enabled == false or cfg().blood == false then return end
  niagara(FX.hit, pawn, nil, at, false)
  if cfg().hitSplat ~= false then niagara(FX.splat, pawn, nil, at, false) end
end

-- once the body has settled, leave a pool under it
function M.on_settled(pawn, mesh)
  if cfg().enabled == false or cfg().pool == false then return end
  local p = bone_loc(mesh, "Bip001-Pelvis")
  if p then niagara(FX.pool, pawn, nil, add(p, vec(0, 0, -15)), false) end
end

-- undo everything before she is reused (respawn / sandbox recover)
function M.cleanup(pawn, mesh)
  pending = nil
  bleeds = {}
  local n, k = 0, 0
  for _, c in ipairs(spawned) do
    if valid(c) then
      try(function() c:Deactivate() end)
      try(function() c:K2_DestroyComponent(c) end)
      n = n + 1
    end
  end
  spawned = {}
  for _, a in ipairs(caps) do
    if valid(a) then try(function() a:K2_DestroyActor() end); k = k + 1 end
  end
  caps = {}
  if #cuts == 0 then
    if n > 0 then log(string.format("removed %d blood effects", n)) end
    return
  end
  local steps = {}
  local function step(label, fn) steps[#steps + 1] = label .. (try(function() fn(); return true end) and "" or "!") end
  local bones, done = {}, {}
  for _, c in ipairs(cuts) do
    bones[#bones + 1] = c.bone
    if valid(c.mesh) and addr(c.mesh) == c.addr and not done[c.addr] then
      done[c.addr] = true
      steps[#steps + 1] = "weights(" .. command(string.format("x%x,0", c.mesh:GetAddress())) .. ")"
    end
  end
  -- the collapsed helper bones live on the mesh asset, which outlives a destroyed component
  steps[#steps + 1] = "sinks(" .. command("r") .. ")"
  cuts = {}
  forced = {}
  local c = collision_saved
  collision_saved = nil
  if c and valid(c.mesh) then
    step("collision", function()
      c.mesh:SetCollisionObjectType(c.obj)
      for ch, r in pairs(c.resp) do c.mesh:SetCollisionResponseToChannel(ch, r) end
      c.mesh:SetCollisionEnabled(c.enabled)
    end)
  end
  if valid(mesh) then
    step("lod", function() mesh:SetForcedLOD(0) end)
    -- recreating the physics state brings back the broken constraint; a body still simulating then keeps
    -- simulating on its own after recovery (a leg left lying on the floor), so stop simulation first
    step("physics", function()
      mesh:SetAllBodiesSimulatePhysics(false)
      mesh:SetSimulatePhysics(false)
      local pa = mesh.SkeletalMesh.PhysicsAsset
      mesh:SetPhysicsAsset(pa, true)
    end)
  end
  log(string.format("undid cut of %s: %d caps, %d effects, %s", table.concat(bones, ","), k, n, table.concat(steps, " ")))
end

-- clear SB's hidden "parent update blocked" counter on a scene component (sbslice.dll, see unpin there);
-- without it Eve's mesh stays where she died after the respawn
local UNPIN = "ue4ss/Mods/EveRagdollProbe/sbslice.unpin"
function M.unpin(comp)
  if native.state ~= "ready" then return "sbslice " .. native.state end
  os.remove(UNPIN)
  local cdo = load_obj(CHEAT_CDO)
  local ok, err = pcall(function()
    cdo:SBRewardGroupDropFormationPathLocation(FName("None"), 0, 0, 0, string.format("u%x", comp:GetAddress()), 0, 0, 0)
  end)
  if not ok then return tostring(err) end
  return read_file(UNPIN) or "no answer"
end

function M.state() return native.state end

return M
