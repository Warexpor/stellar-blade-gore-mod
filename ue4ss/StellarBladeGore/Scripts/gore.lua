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
-- A vertical split clones her body and face; each copy keeps one side of a plane through the spine and the copy
-- becomes its own ragdoll (see "vertical split" below).
-- Blood: the game's own Niagara systems, spawned on hits, on the cut and as a pool under the body.
-- Everything here is undone when she recovers (skin weights, the collapsed helper bones on the shared mesh
-- asset, caps, effects, broken constraints, forced LOD).

local M = {}
local ctx -- log, try, valid, v3, tune (set by M.init)

local UFUNC = "/Script/SB.SBCheatManager:SBRewardGroupDropFormationPathLocation"
local CHEAT_CDO = "/Script/SB.Default__SBCheatManager"
local REQ = "ue4ss/Mods/StellarBladeGore/sbslice.req"
local OK = "ue4ss/Mods/StellarBladeGore/sbslice.ok"
local ERR = "ue4ss/Mods/StellarBladeGore/sbslice.err"
local RESULT = "ue4ss/Mods/StellarBladeGore/sbslice.cut"
-- what can come off: the bone whose subtree leaves, the axis the cut plane is square to (from, default the bone
-- itself, to the next joint) and where along it (0 = from, 1 = to; "auto" cuts close to the joint, so the stump
-- that now follows the body rigidly stays short). mode / radius: sbslice.dll's cut mode (see skin_cut there).
-- The head: Eve's face is its own mesh, weighted to the head and the neck. The head's subtree is the head alone
-- (the clavicles hang off the neck) and her outfit skin has no head bone near the neck, so the face goes along
-- whole (MODE_WHOLE) and the outfit is cut just under the face's lower edge, ~2.3 cm below the neck joint, by
-- position (MODE_PLANE: what is above the plane within the radius leaves or vanishes into the stump)
local MODE = { cut = 0, whole = 1, plane = 2, hole = 3, side = 4, dent = 5 }
local PARTS = {
  ["Bip001-L-UpperArm"] = { to = "Bip001-L-Forearm", kind = "limb" },
  ["Bip001-R-UpperArm"] = { to = "Bip001-R-Forearm", kind = "limb" },
  ["Bip001-L-Forearm"] = { to = "Bip001-L-Hand", kind = "limb" },
  ["Bip001-R-Forearm"] = { to = "Bip001-R-Hand", kind = "limb" },
  ["Bip001-L-Thigh"] = { to = "Bip001-L-Calf", kind = "limb" },
  ["Bip001-R-Thigh"] = { to = "Bip001-R-Calf", kind = "limb" },
  ["Bip001-L-Calf"] = { to = "Bip001-L-Foot", kind = "limb" },
  ["Bip001-R-Calf"] = { to = "Bip001-R-Foot", kind = "limb" },
  ["Bip001-Spine1"] = { to = "Bip001-Spine2", at = 0.5, kind = "torso" },
  ["Bip001-Head"] = { from = "Bip001-Neck", to = "Bip001-Head", at = -0.5, kind = "head", mode = MODE.plane, radius = 8.5 },
}
local CUT_AT_DEFAULT = 0.15
-- a vertical split: the body and face are cloned, each copy keeps one side of a plane through the spine (MODE_SIDE)
-- and the copy becomes its own ragdoll. The face's eyes, teeth and brows only know the head bone, so its vanished
-- side collapses onto a borrowed bone no face vertex uses (Spine1), made to follow the head
local SPLIT_SINK = "Bip001-Spine1"
local SPLIT_RIDE = { "Bip001-Head", "Bip001-Neck", "Bip001-Spine2", "Bip001-Spine1", "Bip001-Spine", "Bip001-Pelvis" }
local LIMB_ROOTS = { "Bip001-L-UpperArm", "Bip001-R-UpperArm", "Bip001-L-Thigh", "Bip001-R-Thigh" }
-- what each kind of cut picks from, nearest to the hit (no lower limbs: a whole limb reads better)
local POOL = {
  limb = { "Bip001-L-UpperArm", "Bip001-R-UpperArm", "Bip001-L-Thigh", "Bip001-R-Thigh" },
  head = { "Bip001-Head" },
  torso = { "Bip001-Spine1" },
}
-- where a wound can land: a bone segment (bone to next joint) and r, about half the limb's thickness in cm. A blunt
-- blow presses in a dent 1.4 r wide and 0.45 r deep, a stab one 2.5 cm wide and 0.6 r deep (at most 4)
local WOUND = {
  { bone = "Bip001-Spine2", to = "Bip001-Neck", r = 6.5 },
  { bone = "Bip001-Spine1", to = "Bip001-Spine2", r = 6.5 },
  { bone = "Bip001-Spine", to = "Bip001-Spine1", r = 6 },
  { bone = "Bip001-Pelvis", to = "Bip001-Spine", r = 6 },
  { bone = "Bip001-L-Thigh", to = "Bip001-L-Calf", r = 5 },
  { bone = "Bip001-R-Thigh", to = "Bip001-R-Calf", r = 5 },
  { bone = "Bip001-L-Calf", to = "Bip001-L-Foot", r = 3.5 },
  { bone = "Bip001-R-Calf", to = "Bip001-R-Foot", r = 3.5 },
  { bone = "Bip001-L-UpperArm", to = "Bip001-L-Forearm", r = 3.5 },
  { bone = "Bip001-R-UpperArm", to = "Bip001-R-Forearm", r = 3.5 },
}
local FX = {
  slice = "/Game/Art/FX/Char/Common/Hit/Flesh/NS_Hit_Flesh_Slice_Big.NS_Hit_Flesh_Slice_Big",
  bleed = "/Game/Art/FX/Char/Common/Hit/Link/NS_Blood_Flooded_Attached.NS_Blood_Flooded_Attached",
  -- red blood: the monster hit and its decal (NS_HitBlood_Monster_01_*, NS_HitBlood_SpawnDecal_L) are the Naytiba's
  -- glowing orange liquid (MI_A_EmissiveLiquid, EnemyCommon/MI_ParBloodDecal); Eve's own hit blood and the flesh
  -- decal use MI_A_DefaultBlood and the common decal, like the bleed and the pool
  hit = "/Game/Art/FX/Char/Common/Hit/PC/NS_HitBlood_PC_01.NS_HitBlood_PC_01",
  splat = "/Game/Art/FX/Char/Common/Hit/Flesh/NS_Hit_Flesh_Decal_Strong_01.NS_Hit_Flesh_Decal_Strong_01",
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
local forced = {}   -- address -> component this script forced to LOD0
local clones = {}   -- components made for a split (the other half's body, face and hair), destroyed on cleanup
local rehaired = {} -- { comp, parent, socket, loc, rot }: her hair, posed by her body while it is split
local copy_watch = nil -- { comp, n }: a split's copy, its ragdoll logged for a couple of seconds
-- the cut in progress, in stages a few ticks apart (see M.slice): { stage, wait, pawn, mesh, hit, why, ... }
local pending = nil
local collision_saved = nil -- the living mesh's collision setup, while a cut piece needs world collision
local self_saved = nil      -- { mesh, resp }: her PhysicsBody response before a cut turned self-collision off
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

-- attached: follow comp (at bone, or at world loc / rot when given: KeepWorldPosition), else a one-off at loc
local function niagara(sys_path, comp, bone, loc, attached, rot)
  local sys = load_obj(sys_path)
  local lib = load_obj("/Script/Niagara.Default__NiagaraFunctionLibrary")
  if not (sys and lib) then return nil end
  local c
  if attached then
    -- EAttachLocation::KeepWorldPosition = 1, SnapToTarget = 2; ENCPoolMethod::None = 0
    c = try(function() return lib:SpawnSystemAttached(sys, comp, FName(bone or "None"), loc or vec(0, 0, 0),
      rot or { Pitch = 0, Yaw = 0, Roll = 0 }, loc and 1 or 2, false, true, 0, false) end)
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
-- the mesh asset's name, or nil: a component without a mesh hands Lua a null object, and UE4SS's GetFName on one
-- crashes the game (pcall can't catch an access violation), so check it first
local function mesh_name(comp)
  local m = valid(comp) and try(function() return comp.SkeletalMesh end)
  return valid(m) and try(function() return m:GetFName():ToString() end) or nil
end
local function name_of(comp) return mesh_name(comp) or "?" end
local function already_cut(mesh, bone)
  local a = addr(mesh)
  for _, c in ipairs(cuts) do if c.addr == a and c.bone == bone then return true end end
  return false
end

-- the parts to try, closest to the hit first; only the one tune names, if it names one
local function rank_bones(mesh, hit, kind)
  local want = cfg().bone or "auto"
  if PARTS[want] then return already_cut(mesh, want) and {} or { want } end
  local list = {}
  for _, bone in ipairs(POOL[kind or "limb"] or POOL.limb) do
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
  -- the lid bulges out a little
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

-- bones that may never be a sink (see nosink in sbslice.c): a sink gives up its weights everywhere and collapses, so
-- not the main skeleton (Bip001-*: the pelvis, a clavicle, the head had been picked), nor hair, capes, breasts (they
-- swing, and the seam swung with them), nor accessory bones (Ab_*: a neck chain 26 cm off the cut). Per mesh asset,
-- sent before every cut on a component
local NOSINK_PREFIX = { "Bip001", "SC_", "Ab_" }
local NOSINK_PART = { "Hair", "Cape", "Breast", "Prop" }
local nosink_cache = {}
local function nosink_list(comp)
  local sm = try(function() return comp.SkeletalMesh end)
  local key = valid(sm) and addr(sm)
  if key and nosink_cache[key] then return nosink_cache[key] end
  local n = try(function() return comp:GetNumBones() end) or 0
  local list = {}
  for i = 0, n - 1 do
    local nm = try(function() return comp:GetBoneName(i):ToString() end) or "None"
    local bad = nm == "Root" or nm == "None"
    for _, pre in ipairs(NOSINK_PREFIX) do if nm:sub(1, #pre) == pre then bad = true end end
    for _, part in ipairs(NOSINK_PART) do if nm:find(part, 1, true) then bad = true end end
    if bad then list[#list + 1] = string.format("%x", i) end
  end
  local s = table.concat(list, ",")
  if key and n > 0 then nosink_cache[key] = s end
  return s
end
local function send_nosink(comp)
  local r = command(string.format("n%x,%s", comp:GetAddress(), nosink_list(comp)))
  if r:sub(1, 2) ~= "ok" then log("nosink list refused: " .. r) end
end

-- one sbslice.dll cut on a component: "c<comp>,<lod>,<bone>,<mode>,<radius in mm>[,<depth in mm>]", all hex
local function cut_command(comp, index, mode, radius, at, n, depth)
  send_nosink(comp)
  local s = string.format("c%x,0,%x,%x,%x", comp:GetAddress(), index, mode or 0, math.floor((radius or 0) * 10 + 0.5))
  if depth then s = s .. string.format(",%x", math.floor(depth * 10 + 0.5)) end
  return command(s, at, n)
end

local function ok_cut(r) return r:sub(1, 2) == "ok" and (num(r, "seam") or 0) + (num(r, "limb") or 0) > 0 end

-- Eve's face: the component in her face slot (MeshInfoList, ESBMesh_Face = 1), else a skeletal mesh child of
-- the body whose asset is named like a face
local function face_of(pawn, mesh)
  local face
  try(function()
    pawn.MeshInfoList:ForEach(function(_, e)
      local info = e:get()
      if not face and info.MeshSlot == 1 and mesh_name(info.MeshComponent) then face = info.MeshComponent end
    end)
  end)
  if face then return face end
  try(function()
    mesh.AttachChildren:ForEach(function(_, e)
      local c = e:get()
      local n = mesh_name(c)
      if not face and n and n:find("Face") then face = c end
    end)
  end)
  return face
end

-- her hair (mesh slots Hair1, Ponytail, PonytailShort) that is showing
local HAIR_SLOTS = { [2] = true, [3] = true, [4] = true }
local HAIR_SINKS = { "Bip001-Spine1", "Bip001-Spine2", "Bip001-Spine", "Bip001-Pelvis", "Bip001-Neck", "Bip001" }
local function hair_of(pawn)
  local out = {}
  try(function()
    pawn.MeshInfoList:ForEach(function(_, e)
      local info = e:get()
      local c = info.MeshComponent
      if HAIR_SLOTS[info.MeshSlot] and mesh_name(c) and try(function() return c:IsVisible() end) == true then
        out[#out + 1] = c
      end
    end)
  end)
  return out
end

-- her hair back on its own animation, where it was attached
local function restore_hair()
  for _, r in ipairs(rehaired) do
    local h = r.comp
    if valid(h) then
      try(function() h:SetMasterPoseComponent(nil, true) end)
      if valid(r.parent) then try(function() h:K2_AttachToComponent(r.parent, r.socket or FName("None"), 2, 2, 2, false) end) end
      if r.loc and r.rot then try(function() h:K2_SetRelativeLocationAndRotation(r.loc, r.rot, false, {}, true) end) end
    end
  end
  rehaired = {}
end

local function force_lod(comp)
  local a = addr(comp)
  if a and not forced[a] then try(function() comp:SetForcedLOD(1) end); forced[a] = comp; return true end
  return false
end

-- give the forced LOD back on every component no cut still needs
local function release_lods()
  for a, comp in pairs(forced) do
    local used = false
    for _, c in ipairs(cuts) do if c.addr == a then used = true end end
    if not used then
      if valid(comp) then try(function() comp:SetForcedLOD(0) end) end
      forced[a] = nil
    end
  end
end

-- blade: { t, n } where the blade's plane crosses this limb (t along it) and its normal: the cut goes there, leaning
-- with the blade at most sliceTilt degrees off square
local function cut_limb(pawn, mesh, bone, why, blow, face, blade)
  local g = cfg()
  local part = PARTS[bone]
  local a, b = bone_loc(mesh, part.from or bone), bone_loc(mesh, part.to)
  if not (a and b) then log("cut skipped: no bone transform for " .. tostring(bone)); return nil end
  local axis = norm(sub(b, a))
  if not axis then return nil end
  local t = tonumber(g.cutAt) or part.at or CUT_AT_DEFAULT
  if blade then t = math.max(0.08, math.min(0.9, blade.t)) end
  local at = add(a, scale(sub(b, a), t))
  local n = axis
  -- along the blow: the plane leans until it contains the blow's direction (the normal loses its component along
  -- it), at most blowTilt degrees off square so the stump stays clean; a blow along the limb leaves it square
  local d = blow and norm(blow)
  local lean = ""
  if blade then
    local bn = dot(blade.n, axis) < 0 and scale(blade.n, -1) or blade.n
    local ang = math.acos(math.max(-1, math.min(1, dot(bn, axis))))
    local max = math.rad(g.sliceTilt or 50)
    local k = ang > max and max / ang or 1
    n = norm(add(scale(axis, 1 - k), scale(bn, k))) or axis
    lean = string.format(" along the blade (%.0f deg)", math.deg(math.acos(math.min(1, dot(n, axis)))))
    d = nil
  end
  if d and (g.blowTilt or 35) > 0 then
    local p = norm(sub(axis, scale(d, dot(axis, d))))
    if p and dot(p, axis) > 0.2 then
      local max = math.rad(g.blowTilt or 35)
      local ang = math.acos(math.min(1, dot(p, axis)))
      local k = ang > max and max / ang or 1
      n = norm(add(scale(axis, 1 - k), scale(p, k))) or axis
      lean = string.format(" along the blow (%.0f deg)", math.deg(math.acos(math.min(1, dot(n, axis)))))
    end
  end
  -- tilted a little so it doesn't look machined (a blade's own angle is enough)
  local tilt = blade and 0 or (g.tilt or 0.25)
  n = norm(add(n, vec((math.random() - 0.5) * tilt, (math.random() - 0.5) * tilt, (math.random() - 0.5) * tilt))) or n
  local index = try(function() return mesh:GetBoneIndex(FName(bone)) end)
  if not index or index < 0 then log("cut skipped: no bone " .. bone); return nil end
  -- a head takes the whole face along first; without that its neck would stretch from the body to the head
  local fr
  if part.kind == "head" then
    local fi = valid(face) and try(function() return face:GetBoneIndex(FName(bone)) end)
    if not fi or fi < 0 then log("head skipped: no face mesh with " .. bone); return nil end
    fr = cut_command(face, fi, MODE.whole, part.radius, at, n)
    log(string.format("face %s: %s", name_of(face), fr))
    if not ok_cut(fr) then log("head skipped: the face can't be cut (no LOD0 CPU access on its mesh?)"); return nil end
  end
  local r = cut_command(mesh, index, part.mode, part.radius, at, n)
  log(string.format("cut %s (%s) at %.2f %s normal %s%s: %s", bone, why, t, v3(at), v3(n), lean, r))
  if r:sub(1, 2) ~= "ok" or (num(r, "seam") or 0) == 0 or (part.kind ~= "head" and (num(r, "limb") or 0) == 0) then
    if fr then log("face put back: " .. command(string.format("x%x,0", face:GetAddress()))) end
    return nil
  end
  return { at = at, n = n, result = r, face = fr and face, face_result = fr }
end

-- stage 1: new weights on the GPU, caps placed (hidden); nothing visible changes yet
local function stage_cut(q)
  -- a death cut follows the killing blow (the death key's impulse, set by now)
  -- (a blade's beheading: its swing)
  local blow = q.out or (q.why == "death" and try(function() local v = q.pawn.RagdollInfo.ImpulseValue; return vec(v.X, v.Y, v.Z) end)) or nil
  for _, b in ipairs(q.blade and { q.blade.bone } or rank_bones(q.mesh, q.hit, q.kind)) do
    q.c = cut_limb(q.pawn, q.mesh, b, q.why, blow, q.face, q.blade)
    if q.c then q.bone = b; break end
  end
  if not q.bone then log("nothing cut (" .. q.why .. ")"); return false end
  cuts[#cuts + 1] = { mesh = q.mesh, addr = addr(q.mesh), bone = q.bone }
  if q.c.face then cuts[#cuts + 1] = { mesh = q.c.face, addr = addr(q.c.face), bone = "face" } end
  q.parent = parent_bone(q.mesh, q.bone)
  -- a head's own opening is the bottom of the face's neck
  q.ob, q.ol = opening(q.c.result, "b"), q.c.face_result and opening(q.c.face_result, "l") or opening(q.c.result, "l")
  q.caps, q.kinds = {}, {}
  if cfg().caps ~= false then
    q.caps[1], q.kinds[1] = cap(q.pawn, q.mesh, q.ob, q.parent or q.bone)
    q.caps[2], q.kinds[2] = cap(q.pawn, q.mesh, q.ol, q.bone)
  end
  return true
end

-- a blunt blow or a stab: a ray from inside the bone segment out towards where it came from; the DLL presses the
-- skin around where the ray leaves the body in, smoothly (deepest at the centre, fading out to the rim), onto a
-- plane under it. No opening, no lid: a blunt blow leaves a wide shallow squash, a stab a narrow deep pit
local function stage_wound(q)
  local g = cfg()
  local nwounds = 0
  for _, c in ipairs(cuts) do if c.bone:sub(1, 6) == "wound:" then nwounds = nwounds + 1 end end
  if nwounds >= (g.maxWounds or 6) then log("wound skipped: already " .. nwounds); return false end
  -- the segment nearest the hit, else a random one
  local best, bd, ba, bb
  for _, w in ipairs(WOUND) do
    local a, b = bone_loc(q.mesh, w.bone), bone_loc(q.mesh, w.to)
    if a and b then
      local d = math.random()
      if q.hit then
        local ab = sub(b, a)
        local t = math.max(0, math.min(1, dot(sub(q.hit, a), ab) / math.max(dot(ab, ab), 1e-4)))
        local c = add(a, scale(ab, t))
        d = math.sqrt(dot(sub(q.hit, c), sub(q.hit, c)))
      end
      if not bd or d < bd then best, bd, ba, bb = w, d, a, b end
    end
  end
  if not best then log("wound skipped: no bone transforms"); return false end
  local ab = sub(bb, ba)
  local t = 0.25 + math.random() * 0.5
  if q.hit and bd < 40 then t = math.max(0.1, math.min(0.9, dot(sub(q.hit, ba), ab) / math.max(dot(ab, ab), 1e-4))) end
  local at = add(ba, scale(ab, t))
  -- out of the body towards the attacker: against the blow, else away from the hit's side of the bone, else
  -- towards the camera (F10)
  local out = q.out and norm(q.out)
  if not out and q.hit and bd < 40 then out = norm(sub(q.hit, at)) end
  if not out then
    local cam = try(function()
      local gs = load_obj("/Script/Engine.Default__GameplayStatics")
      local l = gs:GetPlayerCameraManager(q.pawn, 0):GetCameraLocation()
      return vec(l.X, l.Y, l.Z)
    end)
    out = cam and norm(sub(cam, at))
  end
  out = out or vec(1, 0, 0)
  -- off the bone's axis (a ray along the limb would come out at a joint), with some scatter
  local axis = norm(ab)
  if axis then out = norm(sub(out, scale(axis, dot(out, axis) * 0.8))) or out end
  out = norm(add(out, vec((math.random() - 0.5) * 0.5, (math.random() - 0.5) * 0.5, (math.random() - 0.5) * 0.3))) or out
  local index = try(function() return q.mesh:GetBoneIndex(FName(best.bone)) end)
  if not index or index < 0 then log("wound skipped: no bone " .. best.bone); return false end
  local s = g.woundScale or 1.0
  local radius, depth
  if q.style == "stab" then
    radius, depth = (g.stabWidth or 2.5) * s, math.min(best.r * (g.stabDepth or 0.6), 4) * s
  else
    radius, depth = best.r * (g.bluntWidth or 1.4) * s, best.r * (g.bluntDepth or 0.45) * s
  end
  local r = cut_command(q.mesh, index, MODE.dent, radius, at, out, depth)
  log(string.format("%s on %s (%s) r %.1f depth %.1f from %s out %s: %s", q.style, best.bone, q.why, radius, depth,
    v3(at), v3(out), r))
  if r:sub(1, 2) ~= "ok" or (num(r, "dented") or 0) == 0 then return false end
  local wb = num(r, "wb")
  local ride = wb and wb >= 0 and try(function() return q.mesh:GetBoneName(wb):ToString() end) or best.bone
  if ride == "None" then ride = best.bone end
  q.bone = "wound:" .. (nwounds + 1)
  cuts[#cuts + 1] = { mesh = q.mesh, addr = addr(q.mesh), bone = q.bone }
  q.ride, q.c = ride, { at = triple(r, "hit", 1) or at, n = out, result = r }
  return true
end

-- the rotation that points the bleed's emit axis (tune.gore.bleedAxis: the effect's cone axis, local Z) along out
local function emit_rot(out)
  local km = load_obj("/Script/Engine.Default__KismetMathLibrary")
  local ax = cfg().bleedAxis or "z"
  local d = ax:sub(1, 1) == "-" and scale(out, -1) or out
  local r = km and try(function()
    if ax:sub(-1) == "x" then return km:MakeRotFromX(d) end
    return km:MakeRotFromZ(d)
  end)
  return r and { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll }
end

-- bleed out of an opening: along its outward normal (o.z, or out), riding its cap, else the bone. The bone's own
-- rotation pointed the effect sideways or into the limb
local function bleed_from(q, cap_actor, o, bone, left, out)
  local dir = out or (o and o.z)
  local rot = dir and emit_rot(dir)
    or try(function() local r = q.mesh:GetSocketRotation(FName(bone)); return { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end)
  local root = valid(cap_actor) and try(function() return cap_actor:K2_GetRootComponent() end)
  local at = valid(root) and try(function() local l = root:K2_GetComponentLocation(); return vec(l.X, l.Y, l.Z) end)
  local c
  if at then c = niagara(FX.bleed, root, nil, at, true, rot)
  elseif o then c = niagara(FX.bleed, q.mesh, bone, o.c, true, rot)
  else c = niagara(FX.bleed, q.mesh, bone, nil, true, rot) end
  if c and left > 0 then bleeds[#bleeds + 1] = { comp = c, left = left } end
end

-- the dent goes in: the sink moves, blood. A stab bleeds from the pit (riding the bone that moves it most), a blunt
-- blow only bursts
local function stage_wound_open(q)
  local g = cfg()
  local k = command("k")
  if g.blood ~= false then
    niagara(FX.hit, q.pawn, nil, q.c.at, false)
    niagara(FX.splat, q.pawn, nil, q.c.at, false)
    if q.style == "stab" then
      bleed_from(q, nil, { c = q.c.at }, q.ride, math.floor((g.bleedTime or 2.5) / TICK_S + 0.5), q.c.n)
    end
  end
  log(string.format("%s in on %s (%s): %s", q.bone, q.ride, q.why, k))
end

-- a broken constraint takes its "don't collide" pair with it, and the two bodies overlap at the joint: the piece got
-- shoved out of the stump every frame (an upper body cut off a standing Eve spun wildly against her kinematic hips).
-- So after a cut her bodies stop colliding with each other (PhysicsBody = 5), until she recovers
local function no_self_collision(mesh)
  if not self_saved then
    self_saved = { mesh = mesh, resp = try(function() return mesh:GetCollisionResponseToChannel(5) end) }
  end
  try(function() mesh:SetCollisionResponseToChannel(5, 0) end)
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
    -- the piece weighs what a body part weighs, not the outfit's 100 kg chest and 80 kg cape links (active.lua does
    -- this for ragdolls)
    if ctx.on_piece then
      local m = try(function() return ctx.on_piece(q.pawn, q.mesh) end)
      if m then world = world .. ", " .. m end
    end
  end
  no_self_collision(q.mesh)
  -- off it goes: the constraint at the limb's root breaks (its bodies start simulating if she was alive)
  local broke = try(function() q.mesh:BreakConstraint(vec(0, 0, 0), q.c.at, FName(q.bone)); return true end)
  if ctx.on_cut then try(function() ctx.on_cut(q.mesh, q.bone) end) end
  local throw = g.throw or 250
  if throw > 0 then
    local v = norm(add(q.c.n, vec((math.random() - 0.5) * 0.6, (math.random() - 0.5) * 0.6, 0.4))) or q.c.n
    try(function() q.mesh:AddImpulse(scale(v, throw), FName(q.bone), true) end)
  end
  for _, a in pairs(q.caps) do if valid(a) then try(function() a:SetActorHiddenInGame(false) end) end end
  if g.blood ~= false then
    if g.sliceFx == true then niagara(FX.slice, q.pawn, nil, q.c.at, false) end
    niagara(FX.splat, q.pawn, nil, q.c.at, false)
    -- bleed from both openings, for a while: from the cap, which rides on that side's bone, else from the
    -- opening's centre on the bone; oriented like that bone (the effect was made for bone attachment)
    local left = math.floor((g.bleedTime or 2.5) / TICK_S + 0.5)
    if q.parent then bleed_from(q, q.caps[1], q.ob, q.parent, left) end
    bleed_from(q, q.caps[2], q.ol, q.bone, left)
  end
  log(string.format("%s off (%s): %s, constraint broken=%s, caps %s / %s%s", q.bone, q.why, k, tostring(broke == true),
    tostring(q.kinds[1]), tostring(q.kinds[2]), world))
end

-- ---- vertical split ----

local function place_like(c, src)
  local tm = try(function() return src:K2_GetComponentToWorld() end)
  if tm then try(function() c:K2_SetWorldTransform(tm, false, {}, true) end) end
end

-- a copy of src on the pawn: same mesh, materials and transform, hidden, LOD0, not ticking (so nothing replaces the
-- pose copied onto it) until the split opens; master: a face, posed by that body
local function clone_of(pawn, src, master)
  local cls = load_obj("/Script/Engine.SkeletalMeshComponent")
  if not cls then return nil end
  local id = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }
  local c = try(function() return pawn:AddComponentByClass(cls, true, id, false) end)
  if not valid(c) then return nil end
  clones[#clones + 1] = c
  try(function() c:SetCollisionEnabled(0) end)
  try(function() c:SetHiddenInGame(true, false) end)
  try(function() c:SetSkeletalMesh(src.SkeletalMesh, true) end)
  local nm = try(function() return src:GetNumMaterials() end) or 0
  for i = 0, nm - 1 do
    local m = try(function() return src:GetMaterial(i) end)
    if m then try(function() c:SetMaterial(i, m) end) end
  end
  place_like(c, src)
  force_lod(c)
  if master then
    -- EAttachmentRule::SnapToTarget = 2
    try(function() c:K2_AttachToComponent(master, FName("None"), 2, 2, 2, false) end)
    try(function() c:SetMasterPoseComponent(master, true) end)
  else
    try(function() c:SetComponentTickEnabled(false) end)
  end
  return c
end

local function side_cut(comp, bone, at, n, sink, remap)
  local index = try(function() return comp:GetBoneIndex(FName(bone)) end)
  if not index or index < 0 then return "err no bone " .. bone end
  send_nosink(comp)
  local s = string.format("c%x,0,%x,%x,0", comp:GetAddress(), index, MODE.side)
  if sink then s = s .. string.format(",%x,%x", sink, remap) end
  return command(s, at, n)
end

local function nearest_bone(comp, p, list)
  local best, bd = list[1], nil
  for _, b in ipairs(list) do
    local l = bone_loc(comp, b)
    if l then
      local d = dot(sub(l, p), sub(l, p))
      if not bd or d < bd then best, bd = b, d end
    end
  end
  return best
end

-- which limbs stay with the half in front of the plane (at, n) and which go with the other: by the middle of the limb's
-- first segment, so a limb is never split lengthwise
local function limb_sides(comp, at, n)
  local gone, keep = {}, {}
  for _, b in ipairs(LIMB_ROOTS) do
    local l1, l2 = bone_loc(comp, b), bone_loc(comp, PARTS[b].to)
    local l = l1 and l2 and scale(add(l1, l2), 0.5)
    if l then
      if dot(sub(l, at), n) < 0 then gone[#gone + 1] = b else keep[#keep + 1] = b end
    end
  end
  return gone, keep
end

-- tell the DLL a half's limbs for its next split cut: "g<comp>,<gone roots>,0,<kept roots>"
local function send_limbs(comp, gone, keep)
  local f = {}
  for _, b in ipairs(gone) do
    local i = try(function() return comp:GetBoneIndex(FName(b)) end)
    if i and i > 0 then f[#f + 1] = string.format("%x", i) end
  end
  f[#f + 1] = "0"
  for _, b in ipairs(keep) do
    local i = try(function() return comp:GetBoneIndex(FName(b)) end)
    if i and i > 0 then f[#f + 1] = string.format("%x", i) end
  end
  return command(string.format("g%x,%s", comp:GetAddress(), table.concat(f, ",")))
end

-- one half's caps: a lid per band of the opening (the DLL fits them along its length), riding the spine bone
-- nearest to it
local function split_caps(q, comp, r, list)
  if cfg().caps == false then return end
  for k = 0, 3 do
    local o = opening(r, "s" .. k)
    if o then
      local ride = nearest_bone(comp, o.c, SPLIT_RIDE)
      local a, kind = cap(q.pawn, comp, o, ride)
      if a then list[#list + 1] = { actor = a, o = o, ride = ride, comp = comp, kind = kind } end
    end
  end
end

-- the plane: through the spine, its normal square to the spine (from the swing, else her right)
local function split_plane(q)
  local pel, head = bone_loc(q.mesh, "Bip001-Pelvis"), bone_loc(q.mesh, "Bip001-Head")
  local at = bone_loc(q.mesh, "Bip001-Spine1")
  if not (pel and head and at) then return nil end
  local axis = norm(sub(head, pel)) or vec(0, 0, 1)
  local function square(v) return v and norm(sub(v, scale(axis, dot(v, axis)))) end
  local n = square(q.out)
  local from = "swing"
  if not n then
    from = "her right"
    n = square(try(function() local v = q.pawn:GetActorRightVector(); return vec(v.X, v.Y, v.Z) end)) or vec(0, 1, 0)
  end
  local tilt = (cfg().tilt or 0.25) * 0.3
  n = square(add(n, vec((math.random() - 0.5) * tilt, (math.random() - 0.5) * tilt, (math.random() - 0.5) * tilt))) or n
  return at, n, from
end

local function stage_split_prep(q)
  for _, c in ipairs(cuts) do
    if c.addr == addr(q.mesh) then log("split skipped (" .. q.why .. "): she has been cut already"); return false end
  end
  q.face = face_of(q.pawn, q.mesh)
  q.body2 = clone_of(q.pawn, q.mesh)
  if not q.body2 then log("split skipped: could not clone the body"); return false end
  -- a blade's plane well off her head leaves the face whole, on the half with the head (the original: see
  -- stage_split_cut), so no copy of it
  local head = q.plane and bone_loc(q.mesh, "Bip001-Head")
  q.face_whole = head and math.abs(dot(sub(head, q.plane.at), q.plane.n)) > (cfg().faceSplitCm or 10)
  if valid(q.face) and not q.face_whole then
    force_lod(q.face)
    q.face2 = clone_of(q.pawn, q.face, q.body2)
  end
  -- a split head splits her hair too, or the copy's half of the head is bald: her hair stops running its own
  -- animation and is posed by her body (master pose needs it on the body's root, not the head socket), and the copy
  -- gets its own, posed by the copy; both are cut like the face
  q.hairs = {}
  if not q.face_whole then
    for _, h in ipairs(hair_of(q.pawn)) do
      -- the borrowed sink: a body bone the hair's skeleton has (its weights only use the head and hair bones; Eve's
      -- hair has no Spine1). A hair with none of them, or no head bone, can't follow her body: it stays on its head
      -- socket, whole, on her half (moved to her body's root and master pose first, CH_P_EVE_Hair02 lost every bone
      -- and she was bald)
      local sink, sname
      for _, b in ipairs(HAIR_SINKS) do
        local i = try(function() return h:GetBoneIndex(FName(b)) end)
        if i and i > 0 then sink, sname = i, b; break end
      end
      local hh = try(function() return h:GetBoneIndex(FName("Bip001-Head")) end)
      if not (sink and hh and hh >= 0) then
        log(string.format("split: hair %s stays whole on her half (no %s in its skeleton)", name_of(h),
          sink and "Bip001-Head" or table.concat(HAIR_SINKS, ", ")))
        goto next_hair
      end
      rehaired[#rehaired + 1] = { comp = h, parent = try(function() return h:GetAttachParent() end),
        socket = try(function() return h:GetAttachSocketName() end),
        loc = try(function() local v = h.RelativeLocation; return vec(v.X, v.Y, v.Z) end),
        rot = try(function() local r = h.RelativeRotation; return { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end) }
      try(function() h:K2_AttachToComponent(q.mesh, FName("None"), 2, 2, 2, false) end)
      try(function() h:SetMasterPoseComponent(q.mesh, true) end)
      force_lod(h)
      q.hairs[#q.hairs + 1] = { orig = h, copy = clone_of(q.pawn, h, q.body2), sink = sink, sname = sname }
      ::next_hair::
    end
  end
  return true
end

-- the spine bone just past a blade's plane on the head's side (the original keeps the head): each half's ragdoll
-- breaks there, so the piece without the spine's other end isn't held on by invisible bodies; nil when the plane
-- runs along the spine or misses it
local SPINE_CHAIN = { "Bip001-Pelvis", "Bip001-Spine", "Bip001-Spine1", "Bip001-Spine2", "Bip001-Neck", "Bip001-Head" }
local SPINE_TOL = 4
local function spine_break(mesh, at, n)
  local hs = {}
  for i, b in ipairs(SPINE_CHAIN) do
    local l = bone_loc(mesh, b)
    if not l then return nil end
    hs[i] = dot(sub(l, at), n)
  end
  if hs[1] >= -SPINE_TOL then return nil end
  for i = 2, #SPINE_CHAIN do
    local above = true
    for j = i, #SPINE_CHAIN do if hs[j] < -SPINE_TOL then above = false end end
    if above then return SPINE_CHAIN[i] end
  end
  return nil
end

local function stage_split_cut(q)
  local at, n, from
  if q.plane then
    at, n, from = q.plane.at, q.plane.n, "blade"
    local head = bone_loc(q.mesh, "Bip001-Head")
    if head and dot(sub(head, at), n) < 0 then n = scale(n, -1) end
    q.spine = spine_break(q.mesh, at, n)
  else
    at, n, from = split_plane(q)
  end
  if not at then log("split skipped: no bone transforms"); return false end
  q.c = { at = at, n = n }
  place_like(q.body2, q.mesh)
  local p = command(string.format("p%x,%x", q.mesh:GetAddress(), q.body2:GetAddress()))
  local neg = scale(n, -1)
  -- recorded before they are checked, so a failed half is undone with the rest
  cuts[#cuts + 1] = { mesh = q.mesh, addr = addr(q.mesh), bone = "split" }
  cuts[#cuts + 1] = { mesh = q.body2, addr = addr(q.body2), bone = "split copy" }
  -- each half keeps the limbs on its side whole and lets the others go; the halves share the mesh's sinks, and each
  -- half's skin lets go of every helper past the plane, so the other half's sinks never pull on it
  q.gone1, q.gone2 = limb_sides(q.mesh, at, n)
  send_limbs(q.mesh, q.gone1, q.gone2)
  local r1 = side_cut(q.mesh, SPLIT_SINK, at, n)
  send_limbs(q.body2, q.gone2, q.gone1)
  local r2 = side_cut(q.body2, SPLIT_SINK, at, neg)
  log(string.format("split (%s) at %s normal %s (%s), pose %s, limbs %s | %s, spine breaks at %s, face %s", q.why,
    v3(at), v3(n), from, p, table.concat(q.gone2, ","), table.concat(q.gone1, ","), tostring(q.spine),
    q.face_whole and "whole" or "split"))
  log("split body: " .. r1)
  log("split body copy: " .. r2)
  if not (ok_cut(r1) and ok_cut(r2)) then return false end
  q.caps = {}
  split_caps(q, q.mesh, r1, q.caps)
  split_caps(q, q.body2, r2, q.caps)
  -- the copies of the face and hair are posed by the copy (the DLL matches their bones to it by name); their own
  -- pose buffers get the originals' too, for anything that reads them before the copy ticks
  local function pose_like(src, dst)
    if valid(src) and valid(dst) then command(string.format("p%x,%x", src:GetAddress(), dst:GetAddress())) end
  end
  pose_like(q.face, q.face2)
  for _, hp in ipairs(q.hairs or {}) do pose_like(hp.orig, hp.copy) end
  if valid(q.face) and valid(q.face2) then
    local sink = try(function() return q.face:GetBoneIndex(FName(SPLIT_SINK)) end)
    local head = try(function() return q.mesh:GetBoneIndex(FName("Bip001-Head")) end)
    if sink and sink > 0 and head and head >= 0 then
      cuts[#cuts + 1] = { mesh = q.face, addr = addr(q.face), bone = "face" }
      cuts[#cuts + 1] = { mesh = q.face2, addr = addr(q.face2), bone = "face copy" }
      local f1 = side_cut(q.face, "Bip001-Head", at, n, sink, head)
      local f2 = side_cut(q.face2, "Bip001-Head", at, neg, sink, head)
      log("split face: " .. f1)
      log("split face copy: " .. f2)
      if ok_cut(f1) and ok_cut(f2) then
        split_caps(q, q.mesh, f1, q.caps)
        split_caps(q, q.body2, f2, q.caps)
      else
        -- half a face on one side and a whole one on the other reads worse than two whole ones
        command(string.format("x%x,0", q.face:GetAddress()))
        command(string.format("x%x,0", q.face2:GetAddress()))
        log("split: the face stays whole on both halves")
      end
    else
      log("split: the face has no " .. SPLIT_SINK .. ", it stays whole on this half")
    end
  end
  local head = try(function() return q.mesh:GetBoneIndex(FName("Bip001-Head")) end)
  for _, hp in ipairs(q.hairs or {}) do
    local h, h2 = hp.orig, hp.copy
    local sink, sname = valid(h2) and hp.sink, hp.sname
    local done = false
    if sink and sink > 0 and head and head >= 0 then
      cuts[#cuts + 1] = { mesh = h, addr = addr(h), bone = "hair" }
      cuts[#cuts + 1] = { mesh = h2, addr = addr(h2), bone = "hair copy" }
      local r1 = side_cut(h, "Bip001-Head", at, n, sink, head)
      local r2 = side_cut(h2, "Bip001-Head", at, neg, sink, head)
      log(string.format("split hair %s (sink %s): %s", name_of(h), sname, r1))
      log(string.format("split hair copy %s: %s", name_of(h2), r2))
      done = ok_cut(r1) and ok_cut(r2)
      if not done then
        command(string.format("x%x,0", h:GetAddress()))
        command(string.format("x%x,0", h2:GetAddress()))
      end
    end
    if not done then
      -- whole on her half, none on the copy
      if valid(h2) then try(function() h2:SetHiddenInGame(true, false) end) end
      hp.copy = nil
      log(string.format("split: hair %s stays whole on her half (%s)", name_of(h), sink and "the cut failed" or "no copy"))
    end
  end
  return true
end

local function set_mass(comp, bone, k)
  local m = try(function() return comp:GetBoneMass(FName(bone), true) end)
  if m and m > 0 then try(function() comp:SetMassOverrideInKg(FName(bone), m * k, true) end) end
end

-- one half's ragdoll: the limbs that went with the other half (gone, as its skin was cut) come off and weigh nothing,
-- the spine weighs half, a push away from the other half
-- spine, upper: where a blade went through the spine, and whether this half keeps what is above it (the head's end)
local function settle_half(comp, at, n, push, gone, spine, upper)
  local broke = {}
  for _, b in ipairs(gone or {}) do
    local l = bone_loc(comp, b) or at
    try(function() comp:BreakConstraint(vec(0, 0, 0), l, FName(b)) end)
    broke[#broke + 1] = b
  end
  if spine then
    try(function() comp:BreakConstraint(vec(0, 0, 0), bone_loc(comp, spine) or at, FName(spine)) end)
    if not upper then broke[#broke + 1] = spine end
  end
  local pa = try(function() return comp:GetPhysicsAsset() end) or try(function() return comp.SkeletalMesh.PhysicsAsset end)
  local names = {}
  if valid(pa) then
    try(function() pa.SkeletalBodySetups:ForEach(function(_, e) local bs = e:get(); if valid(bs) then names[#names + 1] = bs.BoneName:ToString() end end) end)
  end
  for _, bn in ipairs(names) do
    local off = false
    for _, b in ipairs(broke) do
      if bn == b or try(function() return comp:BoneIsChildOf(FName(bn), FName(b)) end) == true then off = true end
    end
    -- the half above a spine cut lets go of everything below it
    if spine and upper and not (bn == spine or try(function() return comp:BoneIsChildOf(FName(bn), FName(spine)) end) == true) then
      off = true
    end
    local l = bone_loc(comp, bn)
    local h = l and dot(sub(l, at), n) or 0
    if off then set_mass(comp, bn, 0.02)
    elseif math.abs(h) < 4 then set_mass(comp, bn, 0.5) end
  end
  if push > 0 then try(function() comp:AddImpulseToAllBodiesBelow(scale(n, push), FName("Bip001-Pelvis"), true, true) end) end
  return broke
end

local function stage_split_open(q)
  local g = cfg()
  local k = command("k")
  local b2 = q.body2
  -- the copy takes over the pose she is in now and becomes a ragdoll of its own
  place_like(b2, q.mesh)
  local p = command(string.format("p%x,%x", q.mesh:GetAddress(), b2:GetAddress()))
  local pa = try(function() return q.mesh:GetPhysicsAsset() end) or try(function() return q.mesh.SkeletalMesh.PhysicsAsset end)
  -- the copy was made without collision, so it has no physics bodies: a profile change doesn't create them (only
  -- SetCollisionEnabled does), and SetSimulatePhysics then did nothing. The copy stood frozen where she was cut
  try(function() b2:SetCollisionEnabled(3) end)
  try(function() b2:SetCollisionProfileName(FName("Ragdoll"), true) end)
  -- PhysicsBody = 5: the halves don't collide with each other (or themselves, like her ragdoll)
  try(function() b2:SetCollisionResponseToChannel(5, 0) end)
  try(function() b2:SetComponentTickEnabled(true) end)
  if pa then try(function() b2:SetPhysicsAsset(pa, true) end) end
  try(function() b2:SetSimulatePhysics(true) end)
  local v = try(function() local x = q.mesh:GetPhysicsLinearVelocity(FName("Bip001-Pelvis")); return vec(x.X, x.Y, x.Z) end)
  if v then try(function() b2:SetAllPhysicsLinearVelocity(v, false) end) end
  local sim = try(function() return b2:IsSimulatingPhysics(FName("Bip001-Pelvis")) end) == true
  if not sim then
    try(function() b2:SetAllBodiesSimulatePhysics(true) end)
    try(function() b2:WakeAllRigidBodies() end)
  end
  local sim2 = try(function() return b2:IsSimulatingPhysics(FName("Bip001-Pelvis")) end) == true
  try(function() b2:SetHiddenInGame(false, false) end)
  if valid(q.face2) then try(function() q.face2:SetHiddenInGame(false, false) end) end
  for _, hp in ipairs(q.hairs or {}) do
    if valid(hp.copy) then try(function() hp.copy:SetHiddenInGame(false, false) end) end
  end
  copy_watch = { comp = b2, n = 0 }
  if ctx.on_copy then try(function() ctx.on_copy(b2) end) end
  -- she stood still while it was cut; now both halves fall, before they get pushed apart
  if ctx.on_release then try(function() ctx.on_release() end) end
  log(string.format("split copy ragdoll: simulating %s%s, collision %s", tostring(sim2), sim and "" or " (second try)",
    tostring(try(function() return b2:GetCollisionEnabled() end))))
  local push = g.splitPush or 120
  local at, n = q.c.at, q.c.n
  no_self_collision(q.mesh)
  local b1 = settle_half(q.mesh, at, n, push, q.gone1, q.spine, true)
  local b2l = settle_half(b2, at, scale(n, -1), push, q.gone2, q.spine, false)
  if ctx.on_cut then for _, b in ipairs(b1) do try(function() ctx.on_cut(q.mesh, b) end) end end
  if ctx.on_broken and q.spine then try(function() ctx.on_broken(q.mesh, q.spine) end) end
  local kinds = {}
  for _, c in ipairs(q.caps) do
    if valid(c.actor) then try(function() c.actor:SetActorHiddenInGame(false) end) end
    kinds[#kinds + 1] = tostring(c.kind)
  end
  if g.blood ~= false then
    niagara(FX.hit, q.pawn, nil, q.hit or at, false)
    niagara(FX.splat, q.pawn, nil, at, false)
    -- bleeding along the seam: from the chest and neck lids of each half
    local left = math.floor((g.bleedTime or 2.5) / TICK_S + 0.5)
    for _, c in ipairs(q.caps) do
      if q.plane or c.ride == "Bip001-Spine2" or c.ride == "Bip001-Neck" or c.ride == "Bip001-Spine" then
        local qq = { mesh = c.comp }
        bleed_from(qq, c.actor, c.o, c.ride, left)
      end
    end
  end
  log(string.format("split open (%s): %s, copy pose %s, limbs off %s | %s, caps %s", q.why, k, p,
    table.concat(b1, ","), table.concat(b2l, ","), table.concat(kinds, " ")))
end

local function split_tick(q)
  if q.stage == "cut" then
    if stage_split_prep(q) then q.stage = "cut2"; q.wait = 2; return end
  elseif q.stage == "cut2" then
    if stage_split_cut(q) then q.stage = "open"; q.wait = 2; return end
  else
    pending = nil
    stage_split_open(q)
    return
  end
  -- it didn't happen: nothing of it stays, and she falls whole
  pending = nil
  M.undo_split()
  if ctx.on_release then try(function() ctx.on_release() end) end
end

-- a cut runs in stages a few ticks apart, so no frame shows a half-made cut: LOD0 forced (the cut is made in
-- LOD0's weights; bones LOD0 adds aren't posed until the switch went through), then the new weights (uploaded to
-- the GPU by the render thread), then the collapse that opens the seam (on the game thread, immediately)
-- kind: "limb" (arm or thigh nearest the hit), "head" or "torso"; tune.gore.bone, when it names a part, wins
local function start(pawn, mesh, hit, why, kind, out, plane, blade, style)
  local g = cfg()
  if g.enabled == false then return false end
  if native.state ~= "ready" then log(kind .. " skipped (" .. why .. "): sbslice.dll is " .. native.state); return false end
  if pending then log(kind .. " skipped (" .. why .. "): another cut is still opening"); return false end
  local face = kind == "head" or (kind ~= "split" and not blade and (PARTS[g.bone or ""] or {}).kind == "head")
  face = face and face_of(pawn, mesh) or nil
  local waited = force_lod(mesh)
  if face then waited = force_lod(face) or waited end
  pending = { stage = "cut", wait = waited and 2 or 0, pawn = pawn, mesh = mesh, hit = hit, why = why, kind = kind,
    face = face, out = out, plane = plane, blade = blade, style = style }
  -- a split comes first, then the fall: she is held where she is until it opens
  if kind == "split" and ctx.on_hold then try(function() ctx.on_hold(mesh) end) end
  M.tick(pawn)
  return true
end

function M.slice(pawn, mesh, hit, why, kind) return start(pawn, mesh, hit, why, kind or "limb") end
-- normal: the split plane's normal (made square to her spine, the plane goes through it), or nil for her left/right
function M.split(pawn, mesh, hit, normal, why) return start(pawn, mesh, hit, why, "split", normal) end
-- out: the direction the blow came from (out of the body), or nil; style "blunt" (default) or "stab"
function M.wound(pawn, mesh, hit, out, why, style)
  return start(pawn, mesh, hit, why, "wound", out, nil, nil, style == "stab" and "stab" or "blunt")
end

-- ---- the killing blow as a blade ----
-- The game's hit (main.lua) gives the swing's direction and the attacker's forward: the blade moved in the plane
-- holding both, through where it hit. What that plane goes through decides the cut: the neck alone (the head's end
-- of the spine on one side, the chest on the other) is a beheading, the rest of the spine the body in two along the
-- plane (any angle: down the middle, across the waist, shoulder to hip), past the spine the arm or leg it crosses
-- nearest the hit, cut along the blade.
local LIMB_SEGS = {
  { "Bip001-L-UpperArm", "Bip001-L-Forearm" }, { "Bip001-L-Forearm", "Bip001-L-Hand" },
  { "Bip001-R-UpperArm", "Bip001-R-Forearm" }, { "Bip001-R-Forearm", "Bip001-R-Hand" },
  { "Bip001-L-Thigh", "Bip001-L-Calf" }, { "Bip001-L-Calf", "Bip001-L-Foot" },
  { "Bip001-R-Thigh", "Bip001-R-Calf" }, { "Bip001-R-Calf", "Bip001-R-Foot" },
}
local function blade_plane(h)
  local d, f = h.dir and norm(h.dir), h.fwd and norm(h.fwd)
  if d and f then
    local c = cross(d, f)
    if dot(c, c) > 0.09 then return norm(c), "swing x forward" end
  end
  -- no usable pair: by the game's attack direction, about the attacker's forward (or the swing's) on the level
  local fl = (f and norm(vec(f.X, f.Y, 0))) or (d and norm(vec(d.X, d.Y, 0)))
  if not fl then return nil end
  local right = vec(-fl.Y, fl.X, 0)
  if h.attack_dir == 1 or h.attack_dir == 2 then
    -- sideways: level, slanting a little along the swing
    return norm(add(vec(0, 0, 1), scale(right, (math.random() - 0.5) * 0.7))), "sideways"
  elseif h.attack_dir == 3 then
    -- from the front: upright, along the attacker's forward
    return right, "front"
  end
  return nil
end

function M.blow(pawn, mesh, h, why)
  local n, how = blade_plane(h)
  local at = h.loc
  local function vs(v) return v and string.format("(%.2f %.2f %.2f)", v.X, v.Y, v.Z) or "?" end
  if not (n and at) then
    log(string.format("blade (%s): no plane from dir %s fwd %s attack %s", why, vs(h.dir), vs(h.fwd), tostring(h.attack_dir)))
    return false
  end
  local hs = {}
  for i, b in ipairs(SPINE_CHAIN) do
    local l = bone_loc(mesh, b)
    if not l then return false end
    hs[i] = dot(sub(l, at), n)
  end
  local pos, neg = false, false
  for _, x in ipairs(hs) do
    if x > SPINE_TOL then pos = true elseif x < -SPINE_TOL then neg = true end
  end
  local spine = {}
  for i, x in ipairs(hs) do spine[i] = string.format("%.0f", x) end
  local head_s = hs[#hs] >= 0 and 1 or -1
  -- the arm or leg the plane crosses nearest the hit, not along it (a blade running down a limb leaves nothing to cut)
  local best
  for _, sg in ipairs(LIMB_SEGS) do
    local a, b = bone_loc(mesh, sg[1]), bone_loc(mesh, sg[2])
    local ax = a and b and norm(sub(b, a))
    if ax and math.abs(dot(ax, n)) > 0.3 and not already_cut(mesh, sg[1]) then
      local ha, hb = dot(sub(a, at), n), dot(sub(b, at), n)
      if (ha < 0) ~= (hb < 0) then
        local t = ha / (ha - hb)
        local x = add(a, scale(sub(b, a), t))
        local dd = math.sqrt(dot(sub(x, at), sub(x, at)))
        if not best or dd < best.d then best = { bone = sg[1], t = t, d = dd, n = n } end
      end
    end
  end
  -- how far the hit is from the spine (the nearest point of its segments)
  local off = 1e9
  for i = 1, #SPINE_CHAIN - 1 do
    local a, b = bone_loc(mesh, SPINE_CHAIN[i]), bone_loc(mesh, SPINE_CHAIN[i + 1])
    local ab = sub(b, a)
    local t = math.max(0, math.min(1, dot(sub(at, a), ab) / math.max(dot(ab, ab), 1e-4)))
    local x = add(a, scale(ab, t))
    off = math.min(off, math.sqrt(dot(sub(at, x), sub(at, x))))
  end
  local what
  if best and best.d < (cfg().limbReach or 12) and off > (cfg().spineReach or 15) then
    what = "limb" -- the blade met an arm or leg away from the body: that limb, whatever the plane does further on
  elseif pos and neg then
    -- through the spine: the neck (the chest clearly on the other side from the head) is a beheading
    what = hs[4] * head_s < -SPINE_TOL and "head" or "slice"
  elseif not pos and not neg then
    what = "slice" -- along the spine
  else
    what = "limb"
  end
  local blade = what == "limb" and best or nil
  log(string.format("blade (%s): %s plane at %s normal %s, dir %s fwd %s attack %s, spine %s cm off it -> %s%s",
    why, how, v3(at), vs(n), vs(h.dir), vs(h.fwd), tostring(h.attack_dir), table.concat(spine, "/"), what,
    blade and (" " .. blade.bone .. string.format(" at %.2f", blade.t)) or ""))
  if what == "limb" then
    if not blade then return false end
    return start(pawn, mesh, at, why, "limb", nil, nil, blade)
  elseif what == "head" then
    return start(pawn, mesh, at, why, "head", h.dir)
  end
  return start(pawn, mesh, at, why, "split", n, { at = at, n = n })
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
  if copy_watch then
    local w = copy_watch
    w.n = w.n + 1
    if w.n == 15 or w.n == 60 then
      if not valid(w.comp) then copy_watch = nil
      else
        log(string.format("split copy at %.1f s: pelvis %s simulating %s visible %s", w.n * TICK_S,
          v3(bone_loc(w.comp, "Bip001-Pelvis")), tostring(try(function() return w.comp:IsSimulatingPhysics(FName("Bip001-Pelvis")) end)),
          tostring(try(function() return w.comp:IsVisible() end))))
        if w.n == 60 then copy_watch = nil end
      end
    end
  end
  local q = pending
  if not q then return end
  if not valid(q.mesh) then pending = nil; return end
  if q.wait > 0 then q.wait = q.wait - 1; return end
  if q.kind == "split" then return split_tick(q) end
  if q.stage == "cut" then
    if (q.kind == "wound" and stage_wound or stage_cut)(q) then q.stage = "open"; q.wait = 2; return end
    pending = nil
    -- nothing came off: give the LOD back unless an earlier cut still needs it
    release_lods()
  else
    pending = nil
    if q.kind == "wound" then stage_wound_open(q) else stage_open(q) end
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

-- a split that didn't come off: its weights, copies and caps go, the earlier cuts stay
function M.undo_split()
  local keep = {}
  for _, c in ipairs(cuts) do
    if c.bone == "split" or c.bone == "split copy" or c.bone == "face" or c.bone == "face copy" or c.bone == "hair"
      or c.bone == "hair copy" then
      if valid(c.mesh) and addr(c.mesh) == c.addr then command(string.format("x%x,0", c.mesh:GetAddress())) end
    else keep[#keep + 1] = c end
  end
  cuts = keep
  for _, c in ipairs(clones) do
    local a = addr(c)
    if a then forced[a] = nil end
    if valid(c) then try(function() c:K2_DestroyComponent(c) end) end
  end
  clones = {}
  copy_watch = nil
  restore_hair()
  if #cuts == 0 then command("r") end
  release_lods()
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
  -- a split's other half goes (after its weights, which the DLL tracks by component)
  local nc = 0
  for _, c in ipairs(clones) do
    local a = addr(c)
    if a then forced[a] = nil end
    if valid(c) then try(function() c:K2_DestroyComponent(c) end); nc = nc + 1 end
  end
  clones = {}
  copy_watch = nil
  if #rehaired > 0 then steps[#steps + 1] = string.format("hair(%d)", #rehaired) end
  restore_hair()
  if nc > 0 then steps[#steps + 1] = string.format("copies(%d)", nc) end
  -- the collapsed helper bones live on the mesh asset, which outlives a destroyed component
  steps[#steps + 1] = "sinks(" .. command("r") .. ")"
  cuts = {}
  -- the face, when a head came off
  for _, comp in pairs(forced) do if valid(comp) and comp ~= mesh then try(function() comp:SetForcedLOD(0) end) end end
  forced = {}
  local sc = self_saved
  self_saved = nil
  if sc and valid(sc.mesh) and sc.resp then step("self", function() sc.mesh:SetCollisionResponseToChannel(5, sc.resp) end) end
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
local UNPIN = "ue4ss/Mods/StellarBladeGore/sbslice.unpin"
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

-- a new Eve (the level reloaded after a death): drop every object held from the old one without touching it. Its
-- memory may be gone, and UE4SS's IsValid reads it: the first tick after the reload crashed the game
function M.forget()
  spawned, bleeds, caps, cuts, forced, clones, rehaired = {}, {}, {}, {}, {}, {}, {}
  pending, collision_saved, self_saved, copy_watch = nil, nil, nil, nil
  cache, nosink_cache = {}, {}
end

return M
