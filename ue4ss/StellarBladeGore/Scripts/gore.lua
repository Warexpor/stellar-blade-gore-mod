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
-- Blood: the game's own Niagara systems, spawned on hits, on the cut (a pulsed bleed out of each opening) and as
-- floor drips and pools; the game's gore sounds play on cuts and wounds. Caps and lids use the game's meat material.
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
-- whole (MODE_WHOLE) and the outfit is cut mid-neck by position (MODE_PLANE: what is above the plane within the
-- radius leaves or vanishes into the stump)
local MODE = { cut = 0, whole = 1, plane = 2, hole = 3, side = 4, dent = 5, rupture = 6 }
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
  -- 4.1 cm up the 5.9 cm neck (0.5 sat by the shoulders; 0.3 was 1.8 cm over its joint); the face (down to 1.2 cm
  -- under the head's joint) goes whole with the head, so the plane stays under it
  ["Bip001-Head"] = { from = "Bip001-Neck", to = "Bip001-Head", at = 0.7, kind = "head", mode = MODE.plane, radius = 8.5 },
}
-- arms and legs come off well down the upper arm or thigh (0.15 left a stub at the shoulder or hip)
local CUT_AT_DEFAULT = 0.4
-- a blade's cut never lands closer to the limb's root than this
local BLADE_AT_MIN = 0.3
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
-- blow bursts the skin open (tune.gore.ruptureWidth / ruptureDepth: a crater under a torn flesh lid; bluntWound "dent"
-- presses it in smoothly instead), a stab is a pit 2.5 cm wide and 0.6 r deep (at most 4)
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
  -- the bleed: the flesh-slice effect without its meat stub (red, a cone in the effect's own space), fired again in
  -- pulses (tune.gore.bleedPulse). NS_Blood_Flooded_Attached, the bleed before, locks its emission to a fixed axis
  -- (SBLockAxis) whatever it is turned to: every spurt went the same wrong way
  bleed = "/Game/Art/FX/Char/Common/Hit/Flesh/NS_Hit_Flesh_Slice_BloodOnly.NS_Hit_Flesh_Slice_BloodOnly",
  -- red blood: the monster hit and its decal (NS_HitBlood_Monster_01_*, NS_HitBlood_SpawnDecal_L) are the Naytiba's
  -- glowing orange liquid (MI_A_EmissiveLiquid, EnemyCommon/MI_ParBloodDecal); Eve's own hit blood and the flesh
  -- decal use MI_A_DefaultBlood and the common decal, like the bleed
  hit = "/Game/Art/FX/Char/Common/Hit/PC/NS_HitBlood_PC_01.NS_HitBlood_PC_01",
  splat = "/Game/Art/FX/Char/Common/Hit/Flesh/NS_Hit_Flesh_Decal_Strong_01.NS_Hit_Flesh_Decal_Strong_01",
}
-- the game's own gore sounds (sound cues, played where it happens): the slice of a Naytiba's limb, the gore splash of
-- a boss finisher, a power hit's blood and the flesh impact, a finisher's stab
local function cue(p) return "/Game/Sound/Character/" .. p .. "." .. p:match("([^/]+)$") end
local SFX = {
  cut = { cue("Hit/Slice/Mon_slice_Big_Cue") },
  big = { cue("Hit/Slice/Mon_slice_Big_Cue"), cue("Skill/Link/Boss/PC_LinkAttack_Boss_Gore_Splash_Cue") },
  rupture = { cue("Hit/hit_common_blood_power_00_Cue"), cue("Hit/CPS_LinkAttack_Flesh_Impact_FX_Cue") },
  stab = { cue("Skill/Link/Boss/PC_LinkAttack_Boss_Flesh_Stab1_Cue") },
}
-- the cap: the engine's sphere (radius 50) flattened onto the opening, with the game's cut-flesh material
local CAP_MESH = "/Engine/BasicShapes/Sphere.Sphere"
-- the game's meat (lit, its own colour, normal and ORM maps on UV0), as on the Nest's flesh. MI_CutDamage, the cap
-- before, is a monster-damage dissolve material (MA_CH_DamageGore: masked by distance from the actor) that read as a
-- glossy, broken texture on a lid
local CAP_MATERIAL = "/Game/Art/FX/MA/Enviroment/MI_A_Meat_01_1.MI_A_Meat_01_1"
-- the bone in a stump: the game's generic snapped-bone mesh (Naytiba damage bone textures), unused by anything
-- in the shipped levels as far as the asset list shows
local STUB_MESH = "/Game/Art/Character/Generic/GenericAsset/GM_Brokenbone.GM_Brokenbone"
-- Eve's skin master (MA_Skin_EVE, MF_SkinBloodFX) reads her blood layer from this collection: BloodFactor,
-- BloodOffset (and DirtFactor, DirtOffset), shared by every PC material
local MPC_DIRTY = "/Game/Art/FX/MPC/MPC_PCDirtyOffset.MPC_PCDirtyOffset"

local native = { state = "init", waited = 0 }
local spawned = {}  -- Niagara components to remove on recovery
local bleeds = {}   -- { comp, left, every, n } bleed effects, fired again every `every` ticks until `left` runs out
local later = {}    -- { n, fn }: run fn in n ticks (a split's blood, once the halves have come apart)
local caps = {}     -- cap actors (and bone stubs)
local hung = {}     -- PhysicsConstraintComponents holding an accessory chain a limb cut kept on the body
local trackers = {} -- bleeding openings leaving drips and pools on the floor (see pools below)
local decals = {}   -- floor blood decal components, removed on recovery
local no_decals = {} -- { comp, addr, was }: her meshes kept from receiving the floor blood while it is down
local body_blood = nil -- { from = {name = value}, to, t, time, pawn }: her skin's blood layer while it is raised
local cuts = {}     -- { mesh, addr, bone } per cut, in order
local forced = {}   -- address -> component this script forced to LOD0
local clones = {}   -- components made for a split (the other half's body), destroyed on cleanup
local rehomed = {}  -- { comp, parent, socket, master }: gloves, suit pieces, accessories moved onto a split's copy
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
local function len(a) return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z) end
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

-- sbslice's stretch probe on comp's LOD0, its bone indices named
local function stretch_report(comp)
  local r = command(string.format("s%x,0", comp:GetAddress()))
  return (r:gsub("(%d+):(%d+):([%d%.]+)", function(i, n, far)
    local name = try(function() return comp:GetBoneName(tonumber(i)):ToString() end) or i
    return string.format("%s x%s (%s cm off it)", name, n, far)
  end))
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
-- a gore sound where it happened (tune.gore.sounds, soundVolume). Every parameter is passed: UE4SS leaves the
-- missing ones at zero, which is a silent volume
local function sfx(kind, pawn, at)
  local g = cfg()
  if g.sounds == false or not at then return end
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  if not gs then return end
  for _, path in ipairs(SFX[kind] or {}) do
    local snd = load_obj(path)
    if snd then
      local ok, err = pcall(function()
        gs:PlaySoundAtLocation(pawn, snd, vec(at.X, at.Y, at.Z), { Pitch = 0, Yaw = 0, Roll = 0 }, g.soundVolume or 1.0,
          0.95 + math.random() * 0.1, 0.0, nil, nil, pawn)
      end)
      if not ok then log("sound " .. path .. ": " .. tostring(err)) end
    end
  end
end

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
  local verts, normals, uvs, tris, tangents, colors = {}, {}, {}, {}, {}, {}
  -- tangents along the texture's U and white vertex colours: without them the material's normal map lit the flesh
  -- from a made-up direction (a glossy, broken look)
  local function vert(pos, nrm)
    verts[#verts + 1] = pos
    normals[#normals + 1] = nrm
    uvs[#uvs + 1] = { X = dot(pos, u) / 12 + 0.5, Y = dot(pos, w) / 12 + 0.5 }
    tangents[#tangents + 1] = { TangentX = u, bFlipTangentY = dot(nrm, z) < 0 }
    colors[#colors + 1] = { R = 1, G = 1, B = 1, A = 1 }
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
  return c, verts, tris, normals, uvs, tangents, colors
end

-- the flesh on a cap: MI_A_Meat_01_1 is an effect material whose BloodColor glows (emissive 10, 2.4, 0: bright orange
-- on her stumps), so each cap gets its own instance with tune.gore.capBloodColor
local cap_mid_logged = false
local function set_cap_material(comp, mat)
  if not mat then return end
  local c = cfg().capBloodColor
  local mid = c and try(function() return comp:CreateDynamicMaterialInstance(0, mat, FName("None")) end)
  if valid(mid) then
    local ok = try(function()
      mid:SetVectorParameterValue(FName("BloodColor"), { R = c[1] or 0, G = c[2] or 0, B = c[3] or 0, A = 1 })
      return true
    end)
    if not cap_mid_logged then
      cap_mid_logged = true
      log(string.format("cap material: own instance, BloodColor (%s, %s, %s) %s", tostring(c[1]), tostring(c[2]),
        tostring(c[3]), ok and "set" or "NOT set"))
    end
  else
    try(function() comp:SetMaterial(0, mat) end)
    if not cap_mid_logged then cap_mid_logged = true; log("cap material: no instance, the material as it is") end
  end
end

-- one cap over an opening, riding on the bone that carries that side: the lid mesh when the DLL sent an
-- outline and the procedural mesh takes it, else a flattened sphere fitted to the opening
-- built: a lid made already (centre, verts, tris, normals, uvs, tangents, colors), in place of lid_mesh's
local function cap(pawn, mesh, o, bone, built)
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
    local c, verts, tris, normals, uvs, tangents, colors
    if built then c, verts, tris, normals, uvs, tangents, colors = table.unpack(built)
    else c, verts, tris, normals, uvs, tangents, colors = lid_mesh(o, g.capScale or 1.05) end
    a, root = spawn_at(c)
    if not a then log("cap: spawn failed"); return end
    local pmc = try(function()
      return a:AddComponentByClass(pmc_cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }, false)
    end)
    if valid(pmc) then
      -- 4.27 takes UV0..UV3; older builds only UV0
      local made = try(function() pmc:CreateMeshSection_LinearColor(0, verts, tris, normals, uvs, {}, {}, {}, colors, tangents, false); return true end)
        or try(function() pmc:CreateMeshSection_LinearColor(0, verts, tris, normals, uvs, colors, tangents, false); return true end)
      local sections = made and try(function() return pmc:GetNumSections() end) or 0
      if sections > 0 then
        set_cap_material(pmc, mat)
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
      set_cap_material(root, mat)
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

-- a snapped bone in a stump: GM_Brokenbone, its long axis along the opening's normal (out of that side), as thick as
-- stubBone of the opening's narrow radius, sticking out stubOut of it (scaled by that radius), riding the cap's bone.
-- Its own axes are read from its bounds (the longest one is the bone), so the asset's orientation doesn't matter
local stub_dims = nil
-- her back on a plane with normal z: square to her spine, away from her front (her right is from the left hip and
-- shoulder to the right ones, forward is right x up in UE's axes)
local function back_on(mesh, z)
  local pel, neck = bone_loc(mesh, "Bip001-Pelvis"), bone_loc(mesh, "Bip001-Neck")
  local right = vec(0, 0, 0)
  for _, pr in ipairs({ { "Bip001-L-Thigh", "Bip001-R-Thigh" }, { "Bip001-L-UpperArm", "Bip001-R-UpperArm" } }) do
    local l, r = bone_loc(mesh, pr[1]), bone_loc(mesh, pr[2])
    if l and r then right = add(right, norm(sub(r, l)) or vec(0, 0, 0)) end
  end
  local up = pel and neck and norm(sub(neck, pel))
  right = norm(right)
  if not (up and right) then return nil end
  local back = scale(cross(right, up), -1)
  return norm(sub(back, scale(z, dot(back, z))))
end

-- the middle of an opening as it shows: the area centroid of its outline in the plane (o.c, the rim's mean, sat
-- off to the side where the rim has more vertices: the stumps' bones were off centre). Nil without an outline
local function outline_centre(o)
  local z = o.p and norm(o.z)
  local x = z and o.x and norm(sub(o.x, scale(z, dot(o.x, z))))
  if not x then return nil end
  local y = cross(z, x)
  local a, cx, cy = 0, 0, 0
  for i = 1, #o.p do
    local p, q = sub(o.p[i], o.c), sub(o.p[i % #o.p + 1], o.c)
    local px, py, qx, qy = dot(p, x), dot(p, y), dot(q, x), dot(q, y)
    local w = px * qy - qx * py
    a, cx, cy = a + w, cx + (px + qx) * w, cy + (py + qy) * w
  end
  if math.abs(a) < 1e-3 then return nil end
  return add(o.c, add(scale(x, cx / (3 * a)), scale(y, cy / (3 * a))))
end

-- the spine runs near her back, not through the middle of the opening: a stub on a spine or neck bone moves from
-- the opening's centre towards her back, this share of the opening's half depth that way
local SPINE_BACK = 0.55
local function stub(pawn, mesh, o, bone)
  local g = cfg()
  if g.boneStubs == false or not (o and o.z and o.e) then return nil end
  local sm = load_obj(g.stubMesh or STUB_MESH)
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  local km = load_obj("/Script/Engine.Default__KismetMathLibrary")
  local cls = load_obj("/Script/Engine.StaticMeshActor")
  if not (sm and gs and km and cls) then log("bone stub: " .. (sm and "no spawner" or "no mesh " .. tostring(g.stubMesh or STUB_MESH))); return nil end
  if not stub_dims then
    local b = try(function() local x = sm:GetBounds(); return { o = vec(x.Origin.X, x.Origin.Y, x.Origin.Z), e = vec(x.BoxExtent.X, x.BoxExtent.Y, x.BoxExtent.Z) } end)
    if not b then log("bone stub: no bounds"); return nil end
    local long = (b.e.X >= b.e.Y and b.e.X >= b.e.Z) and "X" or (b.e.Y >= b.e.Z and "Y" or "Z")
    stub_dims = { o = b.o, e = b.e, long = long }
    log(string.format("bone stub mesh: extents %.1f x %.1f x %.1f cm, long axis %s", b.e.X * 2, b.e.Y * 2, b.e.Z * 2, long))
  end
  local d = stub_dims
  local radius = math.min(o.e.X, o.e.Y)
  local thick = math.max(radius * 2 * (g.stubBone or 0.3), 0.6)
  local out = radius * (g.stubOut or 0.5)
  local len = out * 2 + 1
  local z = norm(o.z)
  if not z then return nil end
  local sc, rot = {}, nil
  for _, ax in ipairs({ "X", "Y", "Z" }) do
    sc[ax] = (ax == d.long and len or thick) / math.max(d.e[ax] * 2, 0.01)
  end
  if d.long == "X" then rot = try(function() return km:MakeRotFromX(z) end)
  elseif d.long == "Y" then rot = try(function() return km:MakeRotFromY(z) end)
  else rot = try(function() return km:MakeRotFromZ(z) end) end
  local c = outline_centre(o) or o.c
  if bone and (bone:find("Spine") or bone:find("Neck") or bone:find("Head") or bone:find("Pelvis")) then
    local back = back_on(mesh, z)
    if back and o.x then
      local x = norm(sub(o.x, scale(z, dot(o.x, z))))
      local y = x and cross(z, x)
      if x and y then
        -- how far the opening reaches that way: its outline when it has one, else its fitted ellipse
        local half = math.sqrt((o.e.X * dot(back, x)) ^ 2 + (o.e.Y * dot(back, y)) ^ 2)
        if o.p then
          half = 0
          for _, pt in ipairs(o.p) do half = math.max(half, dot(sub(pt, o.c), back)) end
        end
        c = add(c, scale(back, half * SPINE_BACK))
      end
    end
  end
  -- the stub's middle sits 1 cm under the opening, so `out` of it shows
  local mid = add(c, scale(z, out - len / 2 + 0.5))
  local tm = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = mid, Scale3D = vec(1, 1, 1) }
  local a = try(function()
    local x = gs:BeginDeferredActorSpawnFromClass(pawn, cls, tm, 1, nil)
    return gs:FinishSpawningActor(x, tm)
  end)
  if not valid(a) then log("bone stub: spawn failed"); return nil end
  caps[#caps + 1] = a
  try(function() a:SetActorHiddenInGame(true) end)
  local root = try(function() return a.StaticMeshComponent end)
  if valid(root) then
    try(function() root:SetMobility(2) end)
    try(function() root:SetCollisionEnabled(0) end)
    try(function() root:SetStaticMesh(sm) end)
    try(function() root:SetCastShadow(false) end)
  end
  if rot then try(function() a:K2_SetActorRotation(rot, false) end) end
  try(function() a:SetActorScale3D(vec(sc.X, sc.Y, sc.Z)) end)
  -- the mesh's bounds may not be centred on its pivot: shift by its scaled, rotated origin
  local fwd = try(function() local v = a:GetActorForwardVector(); return vec(v.X, v.Y, v.Z) end)
  local right = try(function() local v = a:GetActorRightVector(); return vec(v.X, v.Y, v.Z) end)
  local up = try(function() local v = a:GetActorUpVector(); return vec(v.X, v.Y, v.Z) end)
  if fwd and right and up then
    local off = add(add(scale(fwd, d.o.X * sc.X), scale(right, d.o.Y * sc.Y)), scale(up, d.o.Z * sc.Z))
    try(function() a:K2_SetActorLocation(sub(mid, off), false, {}, false) end)
  end
  try(function() a:K2_AttachToComponent(mesh, FName(bone), 1, 1, 1, false) end)
  return a
end

-- a split down her length cuts the spine in half along it: on each half's lid, one bone piece per spine segment
-- (GM_Brokenbone, as for the stumps) lying flat in the plane from joint to joint, towards her back (SPINE_BACK of the
-- way from the joint to the outline behind it), riding the segment's lower bone like the lid piece under it
local SPINE_SEGS = { { "Bip001-Pelvis", "Bip001-Spine" }, { "Bip001-Spine", "Bip001-Spine1" },
  { "Bip001-Spine1", "Bip001-Spine2" }, { "Bip001-Spine2", "Bip001-Neck" } }
local function spine_halves(q, comp, o, list)
  local g = cfg()
  if g.boneStubs == false or g.splitSpine == false or not (o and o.z and o.p) then return 0 end
  local sm = load_obj(g.stubMesh or STUB_MESH)
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  local km = load_obj("/Script/Engine.Default__KismetMathLibrary")
  local cls = load_obj("/Script/Engine.StaticMeshActor")
  if not (sm and gs and km and cls) then return 0 end
  if not stub_dims then
    local b = try(function() local x = sm:GetBounds(); return { o = vec(x.Origin.X, x.Origin.Y, x.Origin.Z), e = vec(x.BoxExtent.X, x.BoxExtent.Y, x.BoxExtent.Z) } end)
    if not b then return 0 end
    local long = (b.e.X >= b.e.Y and b.e.X >= b.e.Z) and "X" or (b.e.Y >= b.e.Z and "Y" or "Z")
    stub_dims = { o = b.o, e = b.e, long = long }
  end
  local d = stub_dims
  local z = norm(o.z)
  local back = z and back_on(comp, z)
  if not back then return 0 end
  local width, flat = g.splitSpineWidth or 3.0, g.splitSpineFlat or 1.2
  local lift = (g.splitLidPush or 0.2) + flat * 0.25
  local made = 0
  for _, sg in ipairs(SPINE_SEGS) do
    local a0, b0 = bone_loc(comp, sg[1]), bone_loc(comp, sg[2])
    -- only where the plane runs along the spine (a cut across it has no spine to show lengthwise)
    if a0 and b0 and math.abs(dot(sub(a0, o.c), z)) < 6 and math.abs(dot(sub(b0, o.c), z)) < 6 then
      local function on_plane(v) return sub(v, scale(z, dot(sub(v, o.c), z))) end
      local a, b = on_plane(a0), on_plane(b0)
      local dir = norm(sub(b, a))
      local mid = scale(add(a, b), 0.5)
      -- how far the opening reaches behind this segment
      local reach = 0
      local seg = math.sqrt(dot(sub(b, a), sub(b, a)))
      for _, pt in ipairs(o.p) do
        local t = dot(sub(pt, mid), dir or vec(0, 0, 0))
        if math.abs(t) < seg * 0.6 + 3 then reach = math.max(reach, dot(sub(pt, mid), back)) end
      end
      if dir and reach > width then
        mid = add(add(mid, scale(back, (reach - width * 0.5) * SPINE_BACK)), scale(z, lift))
        local len = seg + 1
        local sc, rot = {}, nil
        if d.long == "X" then
          rot = try(function() return km:MakeRotFromXZ(dir, z) end)
          sc = { X = len, Y = width, Z = flat }
        elseif d.long == "Y" then
          rot = try(function() return km:MakeRotFromYZ(dir, z) end)
          sc = { X = width, Y = len, Z = flat }
        else
          rot = try(function() return km:MakeRotFromZX(dir, z) end)
          sc = { X = flat, Y = width, Z = len }
        end
        for _, ax in ipairs({ "X", "Y", "Z" }) do sc[ax] = sc[ax] / math.max(d.e[ax] * 2, 0.01) end
        local tm = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = mid, Scale3D = vec(1, 1, 1) }
        local act = try(function()
          local x = gs:BeginDeferredActorSpawnFromClass(q.pawn, cls, tm, 1, nil)
          return gs:FinishSpawningActor(x, tm)
        end)
        if valid(act) and rot then
          caps[#caps + 1] = act
          try(function() act:SetActorHiddenInGame(true) end)
          local root = try(function() return act.StaticMeshComponent end)
          if valid(root) then
            try(function() root:SetMobility(2) end)
            try(function() root:SetCollisionEnabled(0) end)
            try(function() root:SetStaticMesh(sm) end)
            try(function() root:SetCastShadow(false) end)
          end
          try(function() act:K2_SetActorRotation(rot, false) end)
          try(function() act:SetActorScale3D(vec(sc.X, sc.Y, sc.Z)) end)
          local fwd = try(function() local v = act:GetActorForwardVector(); return vec(v.X, v.Y, v.Z) end)
          local right = try(function() local v = act:GetActorRightVector(); return vec(v.X, v.Y, v.Z) end)
          local up = try(function() local v = act:GetActorUpVector(); return vec(v.X, v.Y, v.Z) end)
          if fwd and right and up then
            local off = add(add(scale(fwd, d.o.X * sc.X), scale(right, d.o.Y * sc.Y)), scale(up, d.o.Z * sc.Z))
            try(function() act:K2_SetActorLocation(sub(mid, off), false, {}, false) end)
          end
          try(function() act:K2_AttachToComponent(comp, FName(sg[1]), 1, 1, 1, false) end)
          list[#list + 1] = { actor = act, o = o, ride = sg[1], comp = comp, kind = "spine" }
          made = made + 1
        end
      end
    end
  end
  return made
end

-- her skin's own blood layer (MPC_PCDirtyOffset): raised over tune.gore.bodyBlood.time on a death cut, put back
-- on recovery. The collection is global, so this is all of her at once, not around the wound
local function mpc_get(pawn, mpc, name)
  local kml = load_obj("/Script/Engine.Default__KismetMaterialLibrary")
  return kml and try(function() return kml:GetScalarParameterValue(pawn, mpc, FName(name)) end)
end
local function mpc_set(pawn, mpc, name, v)
  local kml = load_obj("/Script/Engine.Default__KismetMaterialLibrary")
  return kml and try(function() kml:SetScalarParameterValue(pawn, mpc, FName(name), v); return true end)
end
local function blood_up(pawn)
  local bb = cfg().bodyBlood
  if bb == false or type(bb) ~= "table" or bb.enabled == false then return end
  local mpc = load_obj(MPC_DIRTY)
  if not mpc then log("body blood: no " .. MPC_DIRTY); return end
  if body_blood then return end
  local from, to = {}, {}
  for _, k in ipairs({ "BloodFactor", "BloodOffset" }) do
    from[k] = mpc_get(pawn, mpc, k)
    local want = k == "BloodFactor" and bb.factor or bb.offset
    if from[k] and want then to[k] = want end
  end
  body_blood = { from = from, to = to, t = 0, time = math.max(bb.time or 1.5, TICK_S), pawn = pawn, mpc = mpc }
  log(string.format("body blood: BloodFactor %s -> %s, BloodOffset %s -> %s over %.1f s", tostring(from.BloodFactor),
    tostring(to.BloodFactor), tostring(from.BloodOffset), tostring(to.BloodOffset), body_blood.time))
end
local function blood_tick()
  local b = body_blood
  if not b or b.done then return end
  b.t = b.t + TICK_S
  local x = math.min(b.t / b.time, 1)
  for k, v in pairs(b.to) do mpc_set(b.pawn, b.mpc, k, b.from[k] + (v - b.from[k]) * x) end
  if x >= 1 then
    b.done = true
    -- the game may drive these itself: read them back once
    log(string.format("body blood: now BloodFactor %s, BloodOffset %s", tostring(mpc_get(b.pawn, b.mpc, "BloodFactor")),
      tostring(mpc_get(b.pawn, b.mpc, "BloodOffset"))))
  end
end
local function blood_down()
  local b = body_blood
  body_blood = nil
  if not b then return end
  for k, v in pairs(b.from) do if v then mpc_set(b.pawn, b.mpc, k, v) end end
  log("body blood: put back")
end

-- ---- floor blood: drips and growing pools ----
-- Every bleeding opening of a death cut is followed for poolTime: while it moves (falling, the piece flying) it drips
-- small splats every dripEvery cm, and where it comes to rest a pool spreads under it, fast at first and slowing
-- down (poolGrow s to most of its size), as large as the part it came from bleeds (POOL_R). The decals are the
-- game's own floor blood from the cinematics (deferred decals on MA_A_BloodDecal_01), traced down onto whatever is
-- under the opening and turned to the floor's slope. They don't flow: on a slope a pool is still a round stain.
-- pools: one solid puddle each (the parking lot cinematic's, MA_D_NoiseBloodDecal_01 on T_D_LiquidDecal_01 and
-- T_C_LiquidDecal_03). The Raven cinematic's (MA_A_BloodDecal_01) are a 2x2 sheet of splats masked by a starburst
-- (T_A_LiquidShape_03) and read as smeared streaks, not a pool
local POOL_DECALS = {
  "/Game/Art/FX/Enviroment/WaterFloodedCity/Cinematic/MV_DED01_Parkinglot_AfterBattle/MA/MI_D_NoiseBloodDecal_03.MI_D_NoiseBloodDecal_03",
  "/Game/Art/FX/Enviroment/WaterFloodedCity/Cinematic/MV_DED01_Parkinglot_AfterBattle/MA/MI_D_NoiseBloodDecal_04.MI_D_NoiseBloodDecal_04",
}
local DRIP_DECALS = {
  "/Game/Art/FX/Enviroment/WasteLand/Cinematic/MV_Nest_RavenBattle_After_QTE_success/MI_FloorBloodDecal_5.MI_FloorBloodDecal_5",
  "/Game/Art/FX/Enviroment/WaterFloodedCity/Cinematic/MV_DED01_Parkinglot_AfterBattle/MA/MI_D_NoiseBloodDecal_03.MI_D_NoiseBloodDecal_03",
}
-- the pool's final radius in cm by the cut bone (first match)
local POOL_R = { { "wound", 22 }, { "Neck", 55 }, { "Head", 55 }, { "Spine", 80 }, { "Pelvis", 80 }, { "Thigh", 60 }, { "UpperArm", 40 },
  { "Calf", 38 }, { "Forearm", 30 }, { "split", 90 } }
local function pool_radius(bone)
  for _, e in ipairs(POOL_R) do if tostring(bone):find(e[1], 1, true) then return e[2] end end
  return 45
end
local function pick(list) return list[math.random(#list)] end

local trace_logged = false
-- the floor under p: trace down (visibility, her own actor ignored), else 5 cm under p, flat
local function floor_at(pawn, p)
  local ks = load_obj("/Script/Engine.Default__KismetSystemLibrary")
  if ks then
    local hit = {}
    local ok = try(function()
      return ks:LineTraceSingle(pawn, add(p, vec(0, 0, 20)), add(p, vec(0, 0, -400)), 0, false, { pawn }, 0, hit, true,
        { R = 1, G = 0, B = 0, A = 1 }, { R = 0, G = 1, B = 0, A = 1 }, 0)
    end)
    local at = ok and try(function() local l = hit.ImpactPoint or hit.Location; return vec(l.X, l.Y, l.Z) end)
    local n = at and try(function() local l = hit.ImpactNormal or hit.Normal; return vec(l.X, l.Y, l.Z) end)
    if not trace_logged then
      trace_logged = true
      log(string.format("floor blood: trace %s%s", tostring(ok), at and string.format(", hit %.0f cm under", p.Z - at.Z) or ", no hit (using the opening's height)"))
    end
    if at then return at, norm(n or vec(0, 0, 1)) or vec(0, 0, 1) end
  end
  return add(p, vec(0, 0, -5)), vec(0, 0, 1)
end

-- one decal on the floor under p, r cm across (radius); its box reaches 20 cm into and out of the floor
local function floor_decal(pawn, p, r, list)
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  local km = load_obj("/Script/Engine.Default__KismetMathLibrary")
  local mat = load_obj(pick(list))
  if not (gs and km and mat) then return nil end
  local at, n = floor_at(pawn, p)
  -- the decal projects along its X: into the floor, turned at random about it
  local rot = try(function() return km:MakeRotFromX(scale(n, -1)) end)
  rot = rot and { Pitch = rot.Pitch, Yaw = rot.Yaw, Roll = math.random() * 360 } or { Pitch = -90, Yaw = 0, Roll = math.random() * 360 }
  local d = try(function() return gs:SpawnDecalAtLocation(pawn, mat, vec(20, 1, 1), at, rot, 0) end)
  if not valid(d) then return nil end
  decals[#decals + 1] = d
  try(function() d:SetWorldScale3D(vec(1, r, r)) end)
  return { d = d, at = at, r = r }
end

-- a pool under her would stain her skin: her meshes take no decals while it is down
local function shield(comp)
  if not valid(comp) then return end
  local a = addr(comp)
  for _, e in ipairs(no_decals) do if e.addr == a then return end end
  local was = try(function() return comp.bReceivesDecals end)
  if was == false then return end
  no_decals[#no_decals + 1] = { comp = comp, addr = a, was = was }
  try(function() comp:SetReceivesDecals(false) end)
end

-- follow one opening: where(t) gives its live position (nil once it is gone)
local function track(pawn, where, bone, comp)
  local g = cfg()
  if g.blood == false or g.pool == false then return end
  shield(comp)
  trackers[#trackers + 1] = { pawn = pawn, where = where, rmax = pool_radius(bone) * (g.poolScale or 1), t = 0,
    still = 0, bone = tostring(bone) }
end
local function track_opening(q, cap_actor, o, comp, bone)
  local root = valid(cap_actor) and try(function() return cap_actor:K2_GetRootComponent() end)
  track(q.pawn, function()
    if valid(root) then return try(function() local l = root:K2_GetComponentLocation(); return vec(l.X, l.Y, l.Z) end) end
    local l = valid(comp) and bone_loc(comp, bone)
    return l and vec(l.X, l.Y, l.Z) or nil
  end, bone, comp)
end

local POOL_EVERY = 3 -- ticks between updates (0.1 s)
local pool_n = 0
local function pools_tick()
  if #trackers == 0 then return end
  pool_n = pool_n + 1
  if pool_n % POOL_EVERY ~= 0 then return end
  local g = cfg()
  local dt = TICK_S * POOL_EVERY
  local life, grow, every = g.poolTime or 12, g.poolGrow or 5, g.dripEvery or 18
  local maxDecals = g.maxDecals or 60
  for i = #trackers, 1, -1 do
    local k = trackers[i]
    k.t = k.t + dt
    local p = k.where()
    if not p or k.t > life then table.remove(trackers, i)
    else
      local moved = k.last and len(sub(p, k.last)) or 0
      k.last = p
      local speed = moved / dt
      if speed < 25 then k.still = k.still + dt else k.still = 0 end
      if k.pool then
        local off = len(vec(p.X - k.pool.at.X, p.Y - k.pool.at.Y, 0))
        if off > math.max(k.pool.r * 0.6, 15) then k.pool = nil end
      end
      if not k.pool and k.still >= 0.3 and #decals < maxDecals then
        -- it came to rest: a pool starts under it
        k.pool = floor_decal(k.pawn, p, 4, POOL_DECALS)
        if k.pool then k.pool.age = 0; k.pools = (k.pools or 0) + 1 end
      elseif not k.pool and speed >= 25 and #decals < maxDecals then
        -- on the move: drips every so often
        if not k.drop or len(sub(p, k.drop)) >= every then
          k.drop = p
          floor_decal(k.pawn, p, 2.5 + math.random() * 4, DRIP_DECALS)
          k.drips = (k.drips or 0) + 1
        end
      end
      if k.pool and valid(k.pool.d) then
        k.pool.age = k.pool.age + dt
        -- fast at first, slowing down: 63 % of the way after poolGrow s
        local r = 4 + (k.rmax - 4) * (1 - math.exp(-k.pool.age / grow))
        if r - k.pool.r > 0.2 then
          k.pool.r = r
          try(function() k.pool.d:SetWorldScale3D(vec(1, r, r)) end)
        end
      end
      if k.t + dt > life then
        log(string.format("floor blood from %s: %d drips, %d pools, last %.0f cm across", k.bone, k.drips or 0,
          k.pools or 0, k.pool and k.pool.r * 2 or 0))
      end
    end
  end
end

local function pools_clear()
  local n = 0
  for _, d in ipairs(decals) do if valid(d) then try(function() d:K2_DestroyComponent(d) end); n = n + 1 end end
  decals, trackers = {}, {}
  for _, e in ipairs(no_decals) do
    if valid(e.comp) and addr(e.comp) == e.addr then try(function() e.comp:SetReceivesDecals(e.was ~= false) end) end
  end
  no_decals = {}
  return n
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

-- a split's other pieces: whatever else her body poses (outfit parts on master pose: gloves, boots, suit pieces) or
-- carries on a socket (accessories) stayed on her half and followed its dropped limbs, which keep flopping unseen:
-- they floated where she was cut. Each goes to the half it lies on (its socket, else the middle of its bounds),
-- except what the head carries (face, hair, earrings, hairpins): her half keeps the head whole
local function rehome(q, b2, at, n)
  local skip = {}
  for _, c in ipairs({ q.mesh, b2, q.face }) do local a = addr(c); if a then skip[a] = true end end
  for _, c in ipairs(clones) do local a = addr(c); if a then skip[a] = true end end
  for _, c in ipairs(hair_of(q.pawn)) do local a = addr(c); if a then skip[a] = true end end
  local me = addr(q.mesh)
  local ks = load_obj("/Script/Engine.Default__KismetSystemLibrary")
  local kids = {}
  try(function() q.mesh.AttachChildren:ForEach(function(_, e) kids[#kids + 1] = e:get() end) end)
  local moved, kept = {}, 0
  for _, c in ipairs(kids) do
    local a = addr(c)
    if valid(c) and a and not skip[a] and try(function() return c:IsVisible() end) == true then
      local master = try(function() return c.MasterPoseComponent:Get() end)
      local mastered = master and addr(master) == me
      local socket = try(function() return c:GetAttachSocketName() end)
      local sname = socket and try(function() return socket:ToString() end)
      -- (CH_ACC_HairPin rides SC_HairACC, which isn't under the head bone)
      local on_head = sname and sname ~= "None" and (sname == "Bip001-Head" or sname:find("Hair") or sname:find("Head")
        or sname:find("Face") or sname:find("Ear")
        or try(function() return q.mesh:BoneIsChildOf(socket, FName("Bip001-Head")) end) == true)
      local p
      if sname and sname ~= "None" and not mastered then
        p = try(function() local l = c:K2_GetComponentLocation(); return vec(l.X, l.Y, l.Z) end)
      else
        -- Bounds isn't reflected: reading it gave an invalid UObject whose X was another one (the split's opening
        -- stage threw on every tick, the cut never opened and nothing else could cut)
        p = ks and try(function()
          local o, e, r = {}, {}, {}
          ks:GetComponentBounds(c, o, e, r)
          return type(o.X) == "number" and vec(o.X, o.Y, o.Z) or nil
        end)
      end
      if p and not on_head and (mastered or (sname and sname ~= "None")) and dot(sub(p, at), n) < 0 then
        rehomed[#rehomed + 1] = { comp = c, parent = q.mesh, socket = socket, master = mastered }
        if mastered then
          try(function() c:K2_AttachToComponent(b2, FName("None"), 2, 2, 2, false) end)
          try(function() c:SetMasterPoseComponent(b2, true) end)
        else
          -- KeepWorld = 1: it stays where it is, now on the copy's bone
          try(function() c:K2_AttachToComponent(b2, socket, 1, 1, 1, false) end)
        end
        moved[#moved + 1] = name_of(c) .. (mastered and "" or "@" .. sname)
      else
        kept = kept + 1
      end
    end
  end
  log(string.format("split: %d pieces moved to the copy (%s), %d stay on her half", #moved,
    #moved > 0 and table.concat(moved, ", ") or "none", kept))
end

local function restore_rehomed()
  for _, r in ipairs(rehomed) do
    local c = r.comp
    if valid(c) and valid(r.parent) then
      if r.master then
        try(function() c:K2_AttachToComponent(r.parent, FName("None"), 2, 2, 2, false) end)
        try(function() c:SetMasterPoseComponent(r.parent, true) end)
      else
        try(function() c:K2_AttachToComponent(r.parent, r.socket or FName("None"), 2, 2, 2, false) end)
      end
    end
  end
  local n = #rehomed
  rehomed = {}
  return n
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

-- her body's own frame (pelvis, up the spine to the neck, across the hips): a blade's plane is kept in it from the
-- blow to the cut, so it goes where it hit her though she moved on meanwhile (a real death's ragdoll kicks her 20 cm in
-- the two ticks a cut waits, and the plane only grazed her: 82147 of 85629 vertices on one side)
local function body_frame(mesh)
  local o, top = bone_loc(mesh, "Bip001-Pelvis"), bone_loc(mesh, "Bip001-Neck")
  local l, r = bone_loc(mesh, "Bip001-L-Thigh"), bone_loc(mesh, "Bip001-R-Thigh")
  if not (o and top and l and r) then return nil end
  local z = norm(sub(top, o))
  if not z then return nil end
  local s = sub(l, r)
  local x = norm(sub(s, scale(z, dot(s, z))))
  if not x then return nil end
  return { o = o, x = x, y = cross(z, x), z = z }
end
local function to_body(f, v) return vec(dot(v, f.x), dot(v, f.y), dot(v, f.z)) end
local function from_body(f, v) return add(add(scale(f.x, v.X), scale(f.y, v.Y)), scale(f.z, v.Z)) end

-- accessory chains hanging off a limb's root bone that stay on the body when it comes off: a body of their own (not
-- Bip001), anchored on that bone (no Bip001 bone between), at least CHAIN_BODIES bodies long, and its joint over
-- CHAIN_OFF cm off the bone (twist bones lie on it). CH_P_EVE_09's cape hangs off the upper arm's twist bone, half way
-- down the arm, and went off with the arm (sbslice keeps their skin on the body: "g" before the cut)
local CHAIN_BODIES, CHAIN_OFF = 3, 3
local function kept_chains(mesh, bone, a, b)
  local pa = try(function() return mesh:GetPhysicsAsset() end) or try(function() return mesh.SkeletalMesh.PhysicsAsset end)
  if not valid(pa) then return {} end
  local list, has = {}, {}
  try(function() pa.SkeletalBodySetups:ForEach(function(_, e) local bs = e:get(); if valid(bs) then local n = bs.BoneName:ToString(); list[#list + 1] = n; has[n] = true end end) end)
  local axis = norm(sub(b, a))
  local function under(x, y) return try(function() return mesh:BoneIsChildOf(FName(x), FName(y)) end) == true end
  local out = {}
  for _, c in ipairs(list) do
    if not c:find("^Bip001") and under(c, bone) then
      local p, anchor = parent_bone(mesh, c), nil
      while p and not anchor do
        if p:find("^Bip001") then anchor = p else p = parent_bone(mesh, p) end
      end
      local n = 0
      for _, d in ipairs(list) do if d == c or under(d, c) then n = n + 1 end end
      local l = bone_loc(mesh, c)
      local off = 0
      if l and axis then local v = sub(l, a); off = len(sub(v, scale(axis, dot(v, axis)))) end
      if anchor == bone and n >= CHAIN_BODIES and off > CHAIN_OFF then out[#out + 1] = c end
    end
  end
  -- only the top of each chain
  local tops = {}
  for _, c in ipairs(out) do
    local inner = false
    for _, d in ipairs(out) do if d ~= c and under(c, d) then inner = true end end
    if not inner then tops[#tops + 1] = c end
  end
  return tops
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
  if blade then t = math.max(BLADE_AT_MIN, math.min(0.9, blade.t)) end
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
  -- a head takes the whole face along first; without that its neck would stretch from the body to the head. Cut on
  -- the neck's plane instead (MODE_PLANE), 8300 face vertices vanished into the stump and the head flew off faceless
  local fr
  if part.kind == "head" then
    local fi = valid(face) and try(function() return face:GetBoneIndex(FName(bone)) end)
    if not fi or fi < 0 then log("head skipped: no face mesh with " .. bone); return nil end
    fr = cut_command(face, fi, MODE.whole, part.radius, at, n)
    log(string.format("face %s: %s", name_of(face), fr))
    if not ok_cut(fr) then log("head skipped: the face can't be cut (no LOD0 CPU access on its mesh?)"); return nil end
  end
  -- the chains that stay on the body ("g": no gone roots, then them); always sent, so an earlier split's limbs aren't
  -- taken for them
  local kept = {}
  if part.kind == "limb" and (part.mode == nil or part.mode == MODE.cut) then
    kept = kept_chains(mesh, bone, a, b)
    local f = { string.format("g%x", mesh:GetAddress()) }
    if #kept > 0 then
      f[#f + 1] = "0"
      for _, c in ipairs(kept) do
        local i = try(function() return mesh:GetBoneIndex(FName(c)) end)
        if i and i > 0 then f[#f + 1] = string.format("%x", i) end
      end
    end
    command(table.concat(f, ","))
  end
  local r = cut_command(mesh, index, part.mode, part.radius, at, n)
  log(string.format("cut %s (%s) at %.2f %s normal %s%s: %s", bone, why, t, v3(at), v3(n), lean, r))
  if r:sub(1, 2) ~= "ok" or (num(r, "seam") or 0) == 0 or (part.kind ~= "head" and (num(r, "limb") or 0) == 0) then
    if fr then log("face put back: " .. command(string.format("x%x,0", face:GetAddress()))) end
    return nil
  end
  return { at = at, n = n, result = r, face = fr and face, face_result = fr, kept = kept }
end

-- stage 1: new weights on the GPU, caps placed (hidden); nothing visible changes yet
local function stage_cut(q)
  local f = (q.blade and q.blade.rel or q.out_rel) and body_frame(q.mesh)
  if f then
    if q.blade and q.blade.rel then q.blade.n = norm(from_body(f, q.blade.rel)) or q.blade.n end
    if q.out_rel then q.out = from_body(f, q.out_rel) end
  end
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
  -- a bone in both stumps (the head's: the neck's spine)
  q.stubs = {}
  if cfg().caps ~= false then
    q.stubs[#q.stubs + 1] = stub(q.pawn, q.mesh, q.ob, q.parent or q.bone)
    q.stubs[#q.stubs + 1] = stub(q.pawn, q.mesh, q.ol, q.bone)
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
  q.burst = q.style ~= "stab" and g.bluntWound ~= "dent"
  if q.style == "stab" then
    radius, depth = (g.stabWidth or 2.5) * s, math.min(best.r * (g.stabDepth or 0.6), 4) * s
  elseif q.burst then
    radius, depth = best.r * (g.ruptureWidth or 0.9) * s, best.r * (g.ruptureDepth or 0.5) * s
  else
    radius, depth = best.r * (g.bluntWidth or 1.4) * s, best.r * (g.bluntDepth or 0.45) * s
  end
  local r = cut_command(q.mesh, index, q.burst and MODE.rupture or MODE.dent, radius, at, out, depth)
  log(string.format("%s%s on %s (%s) r %.1f depth %.1f from %s out %s: %s", q.style, q.burst and " (rupture)" or "",
    best.bone, q.why, radius, depth, v3(at), v3(out), r))
  if r:sub(1, 2) ~= "ok" or (num(r, "dented") or 0) == 0 then return false end
  local wb = num(r, "wb")
  local ride = wb and wb >= 0 and try(function() return q.mesh:GetBoneName(wb):ToString() end) or best.bone
  if ride == "None" then ride = best.bone end
  q.bone = "wound:" .. (nwounds + 1)
  cuts[#cuts + 1] = { mesh = q.mesh, addr = addr(q.mesh), bone = q.bone }
  q.ride, q.c = ride, { at = triple(r, "hit", 1) or at, n = out, result = r }
  -- torn flesh at the bottom of the dent: the cut-flesh material on a flattened dome sitting on the pressed-in skin
  -- (the skin goes onto a plane depth under where the ray left the body), hidden until it opens
  if q.burst and g.caps ~= false then
    -- a rupture: torn flesh over the crater, on the skin where it burst, its edge ragged (12 points, each 70-125 %
    -- of the radius out) and a little longer one way
    local side = math.abs(out.Z) < 0.9 and vec(0, 0, 1) or vec(1, 0, 0)
    local x = norm(cross(out, side)) or vec(1, 0, 0)
    local y = cross(out, x)
    local stretch = 1 + math.random() * 0.35
    local pts = {}
    for i = 0, 11 do
      local a = i / 12 * 2 * math.pi
      local k = radius * (0.7 + math.random() * 0.55)
      pts[#pts + 1] = add(q.c.at, add(scale(x, math.cos(a) * k * stretch), scale(y, math.sin(a) * k)))
    end
    q.flesh = cap(q.pawn, q.mesh, { p = pts, c = q.c.at, x = x, z = out, e = vec(radius, radius, 1) }, ride)
  elseif g.woundFlesh ~= false and g.caps ~= false then
    local side = math.abs(out.Z) < 0.9 and vec(0, 0, 1) or vec(1, 0, 0)
    local x = norm(cross(out, side)) or vec(1, 0, 0)
    local k = q.style == "stab" and 0.9 or (g.woundFleshShare or 0.55)
    local o = { c = add(q.c.at, scale(out, -(depth - 0.3))), x = x, z = out,
      e = vec(radius * k, radius * k * (0.6 + math.random() * 0.3), 1) }
    q.flesh = cap(q.pawn, q.mesh, o, ride)
  end
  q.depth, q.radius = depth, radius
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
local bleed_logged = false
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
  local size = cfg().bleedSize or 1.0
  if c and size ~= 1.0 then try(function() c:SetWorldScale3D(vec(size, size, size)) end) end
  if c and left > 0 then
    local every = math.max(1, math.floor((cfg().bleedPulse or 0.35) / TICK_S + 0.5))
    bleeds[#bleeds + 1] = { comp = c, left = left, every = every, n = 0 }
  end
  -- which way it really points (the effect's Z, the axis bleedAxis names, against where the opening faces)
  if c and dir and not bleed_logged then
    bleed_logged = true
    local up = try(function() local v = c:GetUpVector(); return vec(v.X, v.Y, v.Z) end)
    local fw = try(function() local v = c:GetForwardVector(); return vec(v.X, v.Y, v.Z) end)
    log(string.format("bleed: opening faces %s, effect Z %s X %s", v3(scale(dir, 100)), v3(up and scale(up, 100)),
      v3(fw and scale(fw, 100))))
  end
end

-- the dent goes in: the sink moves, blood. A stab bleeds from the pit (riding the bone that moves it most), a blunt
-- blow only bursts
local function stage_wound_open(q)
  local g = cfg()
  local k = command("k")
  if g.blood ~= false then blood_up(q.pawn) end
  sfx(q.style == "stab" and "stab" or "rupture", q.pawn, q.c.at)
  if g.blood ~= false then
    niagara(FX.hit, q.pawn, nil, q.c.at, false)
    niagara(FX.splat, q.pawn, nil, q.c.at, false)
    -- a stab or a rupture bleeds for bleedTime, a dent for woundBleed of it
    local share = (q.style == "stab" or q.burst) and 1 or (g.woundBleed or 0.6)
    if share > 0 then
      bleed_from(q, q.flesh, { c = q.c.at }, q.ride, math.floor((g.bleedTime or 2.5) * share / TICK_S + 0.5), q.c.n)
      local at = q.c.at
      local comp, ride = q.mesh, q.ride
      -- where it rides: the dent moves with that bone, at its offset when the blow landed
      local b0 = bone_loc(comp, ride)
      local off = b0 and sub(vec(at.X, at.Y, at.Z), vec(b0.X, b0.Y, b0.Z))
      track(q.pawn, function()
        local root = valid(q.flesh) and try(function() return q.flesh:K2_GetRootComponent() end)
        if valid(root) then return try(function() local l = root:K2_GetComponentLocation(); return vec(l.X, l.Y, l.Z) end) end
        local b = valid(comp) and bone_loc(comp, ride)
        return b and off and vec(b.X + off.X, b.Y + off.Y, b.Z + off.Z) or nil
      end, "wound", comp)
    end
  end
  if valid(q.flesh) then try(function() q.flesh:SetActorHiddenInGame(false) end) end
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
-- the chains a limb cut kept on the body (q.c.kept) let go of the limb and hang off the body next to it instead: a
-- ball joint where the chain starts, to the nearest body above the limb (the clavicle, the pelvis), swinging at most
-- CHAIN_SWING degrees
local CHAIN_SWING, CHAIN_TWIST = 40, 20
local function hang_chains(q)
  local kept = q.c and q.c.kept or {}
  if #kept == 0 then return "" end
  local cls = try(function() return StaticFindObject("/Script/Engine.PhysicsConstraintComponent") end)
  if not valid(cls) then return "chains: no PhysicsConstraintComponent class" end
  local pa = try(function() return q.mesh:GetPhysicsAsset() end) or try(function() return q.mesh.SkeletalMesh.PhysicsAsset end)
  local has = {}
  if valid(pa) then
    try(function() pa.SkeletalBodySetups:ForEach(function(_, e) local bs = e:get(); if valid(bs) then has[bs.BoneName:ToString()] = true end end) end)
  end
  local anchor = parent_bone(q.mesh, q.bone)
  while anchor and not has[anchor] do anchor = parent_bone(q.mesh, anchor) end
  if not anchor then return "chains: no body above " .. q.bone end
  local done = {}
  for _, c in ipairs(kept) do
    local at = bone_loc(q.mesh, c)
    local pc = at and try(function()
      return q.pawn:AddComponentByClass(cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }, false)
    end)
    if valid(pc) then
      hung[#hung + 1] = pc
      -- the joint sits where the chain starts now: the constraint takes its frame from the component when it's made
      try(function() pc:K2_SetWorldLocation(at, false, {}, true) end)
      try(function() pc:SetAngularSwing1Limit(1, CHAIN_SWING) end)
      try(function() pc:SetAngularSwing2Limit(1, CHAIN_SWING) end)
      try(function() pc:SetAngularTwistLimit(1, CHAIN_TWIST) end)
      try(function() q.mesh:BreakConstraint(vec(0, 0, 0), at, FName(c)) end)
      if try(function() pc:SetConstrainedComponents(q.mesh, FName(anchor), q.mesh, FName(c)); return true end) then
        done[#done + 1] = c
      end
    end
  end
  return string.format("%s kept on %s", #done > 0 and table.concat(done, ",") or "no chain", anchor)
end

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
  local nh = hang_chains(q)
  if nh ~= "" then world = world .. ", " .. nh end
  -- a killing blow sends the piece flying the way it hit her (q.fly), else it drops off away from the body; every
  -- body of the piece gets the speed (the root's alone dragged the rest, a small push)
  local throw = q.fly and (g.deathThrow or 650) or (g.throw or 250)
  if throw > 0 then
    local v = q.fly and norm(add(add(q.fly, scale(q.c.n, 0.35)), vec((math.random() - 0.5) * 0.3, (math.random() - 0.5) * 0.3, 0.45)))
      or norm(add(q.c.n, vec((math.random() - 0.5) * 0.6, (math.random() - 0.5) * 0.6, 0.4)))
    v = v or q.c.n
    try(function() q.mesh:AddImpulseToAllBodiesBelow(scale(v, throw), FName(q.bone), true, true) end)
    if q.fly then log(string.format("piece flies with the blow: %s at %.0f cm/s", v3(v), throw)) end
  end
  for _, a in pairs(q.caps) do if valid(a) then try(function() a:SetActorHiddenInGame(false) end) end end
  for _, a in pairs(q.stubs or {}) do if valid(a) then try(function() a:SetActorHiddenInGame(false) end) end end
  if g.blood ~= false then
    blood_up(q.pawn)
    if q.parent then track_opening(q, q.caps[1], q.ob, q.mesh, q.parent) end
    track_opening(q, q.caps[2], q.ol, q.mesh, q.bone)
  end
  if g.blood ~= false then
    if g.sliceFx == true then niagara(FX.slice, q.pawn, nil, q.c.at, false) end
    niagara(FX.splat, q.pawn, nil, q.c.at, false)
  end
  sfx((q.bone == "Bip001-Head" or q.bone == "Bip001-Spine1") and "big" or "cut", q.pawn, q.c.at)
  if g.blood ~= false then
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
-- pose copied onto it) until the split opens
local function clone_of(pawn, src)
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
  try(function() c:SetComponentTickEnabled(false) end)
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

-- which limbs stay with the half in front of the plane (at, n) and which go with the other: by the joint the limb hangs
-- from (shoulder, hip), so a limb is never split lengthwise and a slash across the stomach takes no arm: by the
-- middle of the upper arm, an arm hanging down past the waist went with the legs and was cut off at the shoulder
local function limb_sides(comp, at, n)
  local gone, keep = {}, {}
  for _, b in ipairs(LIMB_ROOTS) do
    local l = bone_loc(comp, b)
    if l then
      if dot(sub(l, at), n) < 0 then gone[#gone + 1] = b else keep[#keep + 1] = b end
    end
  end
  return gone, keep
end

-- tell the DLL a half's limbs for its next split cut, and the bones its lid pieces ride (the flattened skin behind
-- the lid bands by them): "g<comp>,<gone roots>,0,<kept roots>,0,<ride bones>"
local function send_limbs(comp, gone, keep)
  local f = {}
  local function add_bones(list)
    for _, b in ipairs(list) do
      local i = try(function() return comp:GetBoneIndex(FName(b)) end)
      if i and i > 0 then f[#f + 1] = string.format("%x", i) end
    end
  end
  add_bones(gone)
  f[#f + 1] = "0"
  add_bones(keep)
  f[#f + 1] = "0"
  add_bones(SPLIT_RIDE)
  return command(string.format("g%x,%s", comp:GetAddress(), table.concat(f, ",")))
end

-- a split's lid: the opening's outline (hips, waist, ribs, shoulder, neck: concave) flat on the plane, ear-clipped,
-- with a skirt round it reaching grow cm past the skin, pushed push cm out of the half, both faces. One rigid lid would stick out of a
-- bending ragdoll, so it comes in pieces, each triangle on the spine bone nearest to it, each piece riding that bone
local function flat_lid(o, comp, grow, push)
  local n = #o.p
  local z = o.z
  local c = vec(0, 0, 0)
  for _, p in ipairs(o.p) do c = add(c, p) end
  c = scale(c, 1 / n)
  local u = norm(sub(o.x, scale(z, dot(o.x, z))))
  if not u then return nil end
  local w = cross(z, u)
  -- 2D, counter-clockwise seen from +z (u, w, z are right handed)
  local px, py = {}, {}
  for i, p in ipairs(o.p) do local d = sub(p, c); px[i], py[i] = dot(d, u), dot(d, w) end
  local area = 0
  for i = 1, n do local j = i % n + 1; area = area + px[i] * py[j] - px[j] * py[i] end
  if area < 0 then
    for i = 1, n // 2 do px[i], px[n + 1 - i] = px[n + 1 - i], px[i]; py[i], py[n + 1 - i] = py[n + 1 - i], py[i] end
  end
  -- the skirt's outer edge: each point out along its corners' bisector, at most twice grow at a sharp corner. Indices
  -- n + 1 .. 2n; growing the outline itself turned the ear clipping's thin triangles inside out at the notches
  local gx, gy = {}, {}
  for i = 1, n do gx[i], gy[i] = px[i], py[i] end
  for i = 1, n do
    local a, b = (i - 2) % n + 1, i % n + 1
    local e1x, e1y = px[i] - px[a], py[i] - py[a]
    local e2x, e2y = px[b] - px[i], py[b] - py[i]
    local l1, l2 = math.sqrt(e1x * e1x + e1y * e1y), math.sqrt(e2x * e2x + e2y * e2y)
    local nx, ny = 0, 0
    if l1 > 1e-4 then nx, ny = nx + e1y / l1, ny - e1x / l1 end
    if l2 > 1e-4 then nx, ny = nx + e2y / l2, ny - e2x / l2 end
    local l = math.sqrt(nx * nx + ny * ny)
    local k = 0
    if l > 1e-4 then
      nx, ny = nx / l, ny / l
      local cosh = l / 2
      k = math.min(grow / math.max(cosh, 0.5), grow * 2)
    end
    gx[n + i], gy[n + i] = px[i] + nx * k, py[i] + ny * k
  end
  -- ear clipping
  local idx = {}
  for i = 1, n do idx[i] = i end
  local tris = {}
  local function cross2(a, b, c2) return (px[b] - px[a]) * (py[c2] - py[a]) - (py[b] - py[a]) * (px[c2] - px[a]) end
  local function inside(p, a, b, c2)
    return cross2(a, b, p) > 0 and cross2(b, c2, p) > 0 and cross2(c2, a, p) > 0
  end
  local guard = 0
  while #idx > 3 and guard < n * n do
    guard = guard + 1
    local m, cut = #idx, nil
    for k = 1, m do
      local a, b, c2 = idx[(k - 2) % m + 1], idx[k], idx[k % m + 1]
      if cross2(a, b, c2) > 1e-6 then
        local ear = true
        for _, p in ipairs(idx) do
          if p ~= a and p ~= b and p ~= c2 and inside(p, a, b, c2) then ear = false; break end
        end
        if ear then cut = k; break end
      end
    end
    -- none (a degenerate run of points): the flattest corner goes
    if not cut then
      local best = nil
      for k = 1, m do
        local cr = cross2(idx[(k - 2) % m + 1], idx[k], idx[k % m + 1])
        if not best or cr > best then best, cut = cr, k end
      end
    end
    tris[#tris + 1] = { idx[(cut - 2) % m + 1], idx[cut], idx[cut % m + 1] }
    table.remove(idx, cut)
  end
  if #idx == 3 then tris[#tris + 1] = { idx[1], idx[2], idx[3] } end
  local core = #tris
  if grow > 0 then
    for i = 1, n do
      local j = i % n + 1
      tris[#tris + 1] = { i, n + i, n + j }
      tris[#tris + 1] = { i, n + j, j }
    end
  end
  -- pieces by the nearest spine bone
  local bones = {}
  for _, b in ipairs(SPLIT_RIDE) do
    local l = bone_loc(comp, b)
    if l then bones[#bones + 1] = { name = b, at = vec(l.X, l.Y, l.Z) } end
  end
  if #bones == 0 then return nil end
  local function world(i) return add(add(c, add(scale(u, gx[i]), scale(w, gy[i]))), scale(z, push)) end
  local pieces, order = {}, {}
  for _, t in ipairs(tris) do
    local m = scale(add(add(world(t[1]), world(t[2])), world(t[3])), 1 / 3)
    local best, bd = nil, nil
    for _, b in ipairs(bones) do
      local d = sub(m, b.at)
      d = dot(d, d)
      if not bd or d < bd then best, bd = b, d end
    end
    local pc = pieces[best.name]
    if not pc then pc = { bone = best.name, tris = {} }; pieces[best.name] = pc; order[#order + 1] = pc end
    pc.tris[#pc.tris + 1] = t
  end
  local white = { R = 1, G = 1, B = 1, A = 1 }
  for _, pc in ipairs(order) do
    local used, list = {}, {}
    for _, t in ipairs(pc.tris) do for _, i in ipairs(t) do if not used[i] then used[i] = true; list[#list + 1] = i end end end
    local mid = vec(0, 0, 0)
    for _, i in ipairs(list) do mid = add(mid, world(i)) end
    mid = scale(mid, 1 / #list)
    local verts, normals, uvs, tangents, colors, out = {}, {}, {}, {}, {}, {}
    for side = 1, 2 do
      local nz = side == 1 and z or scale(z, -1)
      local at = {}
      for _, i in ipairs(list) do
        verts[#verts + 1] = sub(world(i), mid)
        normals[#normals + 1] = nz
        -- the lid's own plane coordinates: the texture runs on from one piece to the next
        uvs[#uvs + 1] = { X = gx[i] / 12 + 0.5, Y = gy[i] / 12 + 0.5 }
        tangents[#tangents + 1] = { TangentX = u, bFlipTangentY = side == 2 }
        colors[#colors + 1] = white
        at[i] = #verts - 1
      end
      -- counter-clockwise from +z; UE's front faces are clockwise (see lid_mesh)
      for _, t in ipairs(pc.tris) do
        if side == 1 then out[#out + 1] = at[t[3]]; out[#out + 1] = at[t[2]]; out[#out + 1] = at[t[1]]
        else out[#out + 1] = at[t[1]]; out[#out + 1] = at[t[2]]; out[#out + 1] = at[t[3]] end
      end
    end
    pc.built = { mid, verts, out, normals, uvs, tangents, colors }
  end
  return order, core
end

-- one half's caps: the lid over the opening along the spine, in pieces riding the spine bones, and a domed one over
-- the neck where the head stayed on the other half (the DLL traces both: s0, n)
local function split_caps(q, comp, r, list)
  if cfg().caps == false then return end
  local g = cfg()
  local o = opening(r, "s0")
  if o and o.p then
    local pieces, nt = flat_lid(o, comp, g.splitLidGrow or 0.4, g.splitLidPush or 0.2)
    local made = 0
    for _, pc in ipairs(pieces or {}) do
      local a, kind = cap(q.pawn, comp, o, pc.bone, pc.built)
      if a then
        made = made + 1
        list[#list + 1] = { actor = a, o = o, ride = pc.bone, comp = comp, kind = kind }
      end
    end
    local ns = spine_halves(q, comp, o, list)
    log(string.format("split lid on %s: %d points, %d triangles, %d pieces, %d spine pieces", name_of(comp), #o.p, nt or 0, made, ns))
  elseif o then
    local ride = nearest_bone(comp, o.c, SPLIT_RIDE)
    local a, kind = cap(q.pawn, comp, o, ride)
    if a then list[#list + 1] = { actor = a, o = o, ride = ride, comp = comp, kind = kind } end
  end
  local nk = opening(r, "n")
  if nk then
    local a, kind = cap(q.pawn, comp, nk, "Bip001-Neck")
    if a then list[#list + 1] = { actor = a, o = nk, ride = "Bip001-Neck", comp = comp, kind = kind } end
  end
end

-- the neck plane for a half's next split cut: across the neck, halfway up it, facing the head. The half that keeps
-- the head (mode 1) keeps all of it, the other (2) closes over the neck: Eve's hair (CH_P_EVE_Hair02) has no body
-- bone to collapse a half of it onto, so a head is never halved
local function send_neck(comp, mode)
  local neck, head = bone_loc(comp, "Bip001-Neck"), bone_loc(comp, "Bip001-Head")
  local hi = try(function() return comp:GetBoneIndex(FName("Bip001-Head")) end)
  if not (neck and head and hi and hi > 0) then return "no neck" end
  local up = norm(sub(head, neck))
  if not up then return "no neck" end
  local at = scale(add(neck, head), 0.5)
  return command(string.format("h%x,%x,%x", comp:GetAddress(), mode, hi), at, up)
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
    local f = q.plane.rel and body_frame(q.mesh)
    if f then
      at, n = add(f.o, from_body(f, q.plane.rel.at)), norm(from_body(f, q.plane.rel.n)) or n
      from = string.format("blade, followed her %.0f cm", len(sub(at, q.plane.at)))
    end
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
  -- her half keeps the head, face and hair whole, on their own animation; the copy's neck closes. The DLL holds one
  -- neck plane, for the next split cut of that component
  send_limbs(q.mesh, q.gone1, q.gone2)
  local h1 = send_neck(q.mesh, 1)
  local r1 = side_cut(q.mesh, SPLIT_SINK, at, n)
  send_limbs(q.body2, q.gone2, q.gone1)
  local h2 = send_neck(q.body2, 2)
  local r2 = side_cut(q.body2, SPLIT_SINK, at, neg)
  log(string.format("split (%s) at %s normal %s (%s), pose %s, limbs %s | %s, spine breaks at %s, neck %s | %s", q.why,
    v3(at), v3(n), from, p, table.concat(q.gone2, ","), table.concat(q.gone1, ","), tostring(q.spine), h1, h2))
  log("split body: " .. r1)
  log("split body copy: " .. r2)
  if not (ok_cut(r1) and ok_cut(r2)) then return false end
  -- each half must keep a real share of her, all sunk: a plane that grazed her left one half a sliver and the other
  -- a whole body nothing could sink (85506 vertices unsunk), standing over her as if nothing was cut
  local nv = num(r1, "verts") or 0
  local k1, k2 = nv - (num(r1, "vanished") or 0), nv - (num(r2, "vanished") or 0)
  local un = (num(r1, "unsunk") or 0) + (num(r2, "unsunk") or 0)
  local least = cfg().splitMinShare or 0.12
  if nv > 0 and (math.min(k1, k2) < nv * least or un > nv * 0.02) then
    log(string.format("split (%s) degenerate: halves keep %d and %d of %d vertices, %d unsunk: a waist cut instead",
      q.why, k1, k2, nv, un))
    q.degenerate = true
    return false
  end
  q.caps = {}
  split_caps(q, q.mesh, r1, q.caps)
  split_caps(q, q.body2, r2, q.caps)
  return true
end

local function set_mass(comp, bone, k)
  local m = try(function() return comp:GetBoneMass(FName(bone), true) end)
  if m and m > 0 then try(function() comp:SetMassOverrideInKg(FName(bone), m * k, true) end) end
end

-- one half's ragdoll: the limbs that went with the other half (gone, as its skin was cut) come off and fall free,
-- the spine weighs half, a push away from the other half and a tip that topples the halves apart. Hiding them with
-- their bodies (HideBoneByName, PBO_Term) stopped her ragdoll the tick the split opened, and her mesh never
-- simulated again until the level reloaded (twelfth playtest)
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
    -- what the half lets go of falls free, invisible, at its own mass: at 0.02 kg the chains shook and went through
    -- the floor, and kinematic they froze in the air where she was cut, with whatever still rode them (a floating
    -- piece of the outfit)
    if off then
      if ctx.on_free then try(function() ctx.on_free(comp, bn) end) end
    elseif math.abs(h) < 4 then set_mass(comp, bn, 0.5) end
  end
  if push > 0 then try(function() comp:AddImpulseToAllBodiesBelow(scale(n, push), FName("Bip001-Pelvis"), true, true) end) end
  -- a cut down her length: the upper body leans out more than the hips, so the halves fall open like a split log
  local tip = cfg().splitTip or 0
  if tip > 0 and math.abs(n.Z) < 0.6 and not (spine and upper) then
    try(function() comp:AddImpulseToAllBodiesBelow(scale(n, tip), FName("Bip001-Spine2"), true, true) end)
  end
  return broke
end

-- the copy becomes a ragdoll of its own and the halves come apart (vel: per bone velocities to start them with, from
-- an animated split's last frames; else they keep what her ragdoll had)
local function split_physics(q, vel)
  local g = cfg()
  local b2 = q.body2
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
  rehome(q, b2, q.c.at, q.c.n)
  copy_watch = { comp = b2, her = q.mesh, n = 0 }
  if ctx.on_copy then try(function() ctx.on_copy(b2) end) end
  -- she stood still while it was cut; now both halves fall, before they get pushed apart
  if ctx.on_release then try(function() ctx.on_release() end) end
  log(string.format("split copy ragdoll: simulating %s%s, collision %s", tostring(sim2), sim and "" or " (second try)",
    tostring(try(function() return b2:GetCollisionEnabled() end))))
  local at, n = q.c.at, q.c.n
  local push = g.splitPush or 120
  no_self_collision(q.mesh)
  local b1 = settle_half(q.mesh, at, n, push, q.gone1, q.spine, true)
  -- the copy's head is closed over: its body comes off and weighs nothing, like a gone limb's
  local gone2 = { table.unpack(q.gone2 or {}) }
  if not (q.spine and q.spine ~= "Bip001-Head") then gone2[#gone2 + 1] = "Bip001-Head" end
  local b2l = settle_half(b2, at, scale(n, -1), push, gone2, q.spine, false)
  if ctx.on_cut then for _, b in ipairs(b1) do try(function() ctx.on_cut(q.mesh, b) end) end end
  if ctx.on_broken and q.spine then try(function() ctx.on_broken(q.mesh, q.spine) end) end
  if vel then
    local nv = 0
    for _, comp in ipairs({ q.mesh, b2 }) do
      for b, v in pairs(vel) do try(function() comp:SetPhysicsLinearVelocity(v, false, FName(b)) end); nv = nv + 1 end
      try(function() comp:WakeAllRigidBodies() end)
    end
    log(string.format("split: the halves fall on from the animation (%d body velocities)", nv))
  end
  -- a killing blow sends the cut off half flying the way it hit her
  local fly = q.fly and (g.splitFly or 350) or 0
  if fly > 0 then
    local v = norm(add(q.fly, vec(0, 0, 0.3))) or q.fly
    try(function() b2:AddImpulseToAllBodiesBelow(scale(v, fly), FName("Bip001-Pelvis"), true, true) end)
    log(string.format("split: the cut off half flies with the blow, %s at %.0f cm/s", v3(v), fly))
  end
  log(string.format("split falls apart (%s): limbs off %s | %s", q.why, table.concat(b1, ","), table.concat(b2l, ",")))
end

local function stage_split_open(q)
  local g = cfg()
  local k = command("k")
  local b2 = q.body2
  -- the copy takes over the pose she is in now
  place_like(b2, q.mesh)
  local p = command(string.format("p%x,%x", q.mesh:GetAddress(), b2:GetAddress()))
  try(function() b2:SetHiddenInGame(false, false) end)
  if q.anim then
    -- an animated split: the copy is posed by her body while her fall plays on, both halves one body yet;
    -- split_tick lets them fall apart after tune.gore.splitAnim seconds
    try(function() b2:SetMasterPoseComponent(q.mesh, true) end)
  else
    split_physics(q)
  end
  local at = q.c.at
  local kinds = {}
  for _, c in ipairs(q.caps) do
    if valid(c.actor) then try(function() c.actor:SetActorHiddenInGame(false) end) end
    kinds[#kinds + 1] = tostring(c.kind)
  end
  sfx("big", q.pawn, q.hit or at)
  -- she comes apart first, then bleeds (tune.gore.splitBleedDelay): blood on the same tick read as blood, then a split
  local function bleed()
    if g.blood == false or not valid(q.mesh) then return end
    blood_up(q.pawn)
    niagara(FX.hit, q.pawn, nil, q.hit or at, false)
    niagara(FX.splat, q.pawn, nil, at, false)
    -- bleeding along the seam: from the chest and neck lids of each half
    local left = math.floor((g.bleedTime or 2.5) / TICK_S + 0.5)
    for _, c in ipairs(q.caps) do
      if valid(c.actor) and c.kind ~= "spine" and (q.plane or c.ride == "Bip001-Spine2" or c.ride == "Bip001-Neck" or c.ride == "Bip001-Spine") then
        local qq = { mesh = c.comp }
        bleed_from(qq, c.actor, c.o, c.ride, left)
      end
    end
    for _, comp in ipairs({ q.mesh, q.body2 }) do
      track(q.pawn, function()
        local l = valid(comp) and bone_loc(comp, "Bip001-Spine1")
        return l and vec(l.X, l.Y, l.Z) or nil
      end, "split", comp)
    end
  end
  local wait = math.floor((g.splitBleedDelay or 0.3) / TICK_S + 0.5)
  if wait > 0 then later[#later + 1] = { n = wait, fn = bleed } else bleed() end
  log(string.format("split open (%s): %s, copy pose %s, caps %s%s", q.why, k, p, table.concat(kinds, " "),
    q.anim and string.format(", her fall plays on for %.1f s", q.anim) or ""))
end

local start -- below; a degenerate split falls back to a waist cut through it
local aimed -- M.aim: the next cut's flying direction
local function split_tick(q)
  if q.stage == "cut" then
    if stage_split_prep(q) then q.stage = "cut2"; q.wait = 2; return end
  elseif q.stage == "cut2" then
    if stage_split_cut(q) then q.stage = "open"; q.wait = 2; return end
  elseif q.stage == "open" then
    stage_split_open(q)
    if q.anim then q.stage, q.t, q.seen = "anim", 0, nil; return end
    pending = nil
    return
  else
    -- her fall plays on with both halves: each body's speed from the last two frames, then they fall apart
    q.t = q.t + TICK_S
    local now = {}
    for _, b in ipairs(q.bodies or {}) do now[b] = bone_loc(q.mesh, b) end
    local vel = nil
    if q.seen then
      vel = {}
      for b, l in pairs(now) do
        local o = q.seen[b]
        if o then vel[b] = scale(sub(vec(l.X, l.Y, l.Z), vec(o.X, o.Y, o.Z)), 1 / TICK_S) end
      end
    end
    q.seen = now
    if q.t < q.anim then return end
    pending = nil
    if valid(q.body2) then try(function() q.body2:SetMasterPoseComponent(nil, true) end) end
    command(string.format("p%x,%x", q.mesh:GetAddress(), q.body2:GetAddress()))
    if ctx.on_need_ragdoll then try(function() ctx.on_need_ragdoll("split") end) end
    split_physics(q, vel)
    return
  end
  -- it didn't happen: nothing of it stays, and she falls whole (a degenerate one: cut across the waist instead)
  pending = nil
  M.undo_split()
  if ctx.on_release then try(function() ctx.on_release() end) end
  if q.degenerate then start(q.pawn, q.mesh, q.hit, q.why, "torso") end
end

-- a cut runs in stages a few ticks apart, so no frame shows a half-made cut: LOD0 forced (the cut is made in
-- LOD0's weights; bones LOD0 adds aren't posed until the switch went through), then the new weights (uploaded to
-- the GPU by the render thread), then the collapse that opens the seam (on the game thread, immediately)
-- kind: "limb" (arm or thigh nearest the hit), "head" or "torso"; tune.gore.bone, when it names a part, wins
function start(pawn, mesh, hit, why, kind, out, plane, blade, style)
  local g = cfg()
  if g.enabled == false then return false end
  if native.state ~= "ready" then log(kind .. " skipped (" .. why .. "): sbslice.dll is " .. native.state); return false end
  if pending then log(kind .. " skipped (" .. why .. "): another cut is still opening"); return false end
  local face = kind == "head" or (kind ~= "split" and not blade and (PARTS[g.bone or ""] or {}).kind == "head")
  face = face and face_of(pawn, mesh) or nil
  local waited = force_lod(mesh)
  if face then waited = force_lod(face) or waited end
  pending = { stage = "cut", wait = waited and 2 or 0, pawn = pawn, mesh = mesh, hit = hit, why = why, kind = kind,
    face = face, out = out, plane = plane, blade = blade, style = style,
    fly = aimed and os.clock() - aimed.t < 1 and aimed.d or nil }
  aimed = nil
  -- the blade's plane and directions in her own frame, so they move with her until the cut is made
  local f = (plane or blade or out) and body_frame(mesh)
  if f then
    if plane then plane.rel = { at = to_body(f, sub(plane.at, f.o)), n = to_body(f, plane.n) } end
    if blade then blade.rel = to_body(f, blade.n) end
    if out then pending.out_rel = to_body(f, out) end
  end
  -- an animated death (main.lua) plays her own fall; cutting her in two needs the ragdoll
  local halves = kind == "split" or kind == "torso"
    or (kind ~= "wound" and not blade and (PARTS[g.bone or ""] or {}).kind == "torso")
  -- unless it is a split and she is playing her fall: then both halves play on with it for tune.gore.splitAnim
  -- seconds before they come apart (split_tick)
  local anim = why == "death" and kind == "split" and (g.splitAnim or 0.7) > 0 and ctx.animated and ctx.animated()
  if anim then
    pending.anim = g.splitAnim or 0.7
    local pa = try(function() return mesh:GetPhysicsAsset() end) or try(function() return mesh.SkeletalMesh.PhysicsAsset end)
    pending.bodies = {}
    if valid(pa) then
      try(function() pa.SkeletalBodySetups:ForEach(function(_, e) local bs = e:get(); if valid(bs) then pending.bodies[#pending.bodies + 1] = bs.BoneName:ToString() end end) end)
    end
  elseif why == "death" and halves and ctx.on_need_ragdoll then
    try(function() ctx.on_need_ragdoll(kind) end)
  end
  -- a split comes first, then the fall: she is held where she is until it opens
  if kind == "split" and not anim and ctx.on_hold then try(function() ctx.on_hold(mesh) end) end
  M.tick(pawn)
  return true
end

-- the direction the killing blow travelled (world), for the next cut's pieces to fly along (nil: they drop off)
function M.aim(dir)
  local d = dir and norm(vec(dir.X, dir.Y, dir.Z))
  -- only for a cut made right after (a blow that cut nothing leaves it for no later cut)
  aimed = d and d.X == d.X and { d = d, t = os.clock() } or nil
end

-- a split is on its way (it brings its own blood once it opens)
function M.splitting() return pending ~= nil and pending.kind == "split" end

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
  local best, struck
  for _, sg in ipairs(LIMB_SEGS) do
    local a, b = bone_loc(mesh, sg[1]), bone_loc(mesh, sg[2])
    local ax = a and b and norm(sub(b, a))
    if ax and math.abs(dot(ax, n)) > 0.3 and not already_cut(mesh, sg[1]) then
      local ha, hb = dot(sub(a, at), n), dot(sub(b, at), n)
      if (ha < 0) ~= (hb < 0) then
        local t = ha / (ha - hb)
        local x = add(a, scale(sub(b, a), t))
        local dd = math.sqrt(dot(sub(x, at), sub(x, at)))
        local c = { bone = sg[1], t = t, d = dd, n = n }
        if not best or dd < best.d then best = c end
        if h.bone == sg[1] then struck = c end
      end
    end
  end
  -- the limb the blow was aimed at (h.bone), when the plane crosses it, over whatever else it crosses nearer
  if struck then best = struck end
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
  -- a plane past the spine that only takes a thigh at its hip joint (or a calf right at the knee from a blow aimed at
  -- the body) cut the hips: across the waist instead, square to the spine
  local hip = what == "limb" and best and best.bone:find("Thigh") and best.t < 0.25
  -- a blade through her body splits her only bladeSplit of the time; else the death's odds are rolled (main.lua)
  local splits = what == "slice" or hip or (what == "limb" and best and off < (cfg().spineReach or 15) and best.bone:find("Calf"))
  if splits and math.random() > (cfg().bladeSplit or 0.2) then
    log(string.format("blade (%s): %s plane through her body, no split this time (bladeSplit %.2f)", why, how, cfg().bladeSplit or 0.2))
    return false
  end
  if hip or (what == "limb" and best and off < (cfg().spineReach or 15) and best.bone:find("Calf")) then
    local a, b = bone_loc(mesh, "Bip001-Spine"), bone_loc(mesh, "Bip001-Spine1")
    if a and b then
      at = add(a, scale(sub(b, a), 0.4))
      log(string.format("blade (%s): it only met %s at %.2f, cut across the waist at %s instead", why, best.bone,
        best.t, v3(at)))
      return start(pawn, mesh, at, why, "split", norm(sub(b, a)), { at = at, n = norm(sub(b, a)) })
    end
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
  -- a plane along her that has every arm and leg on one side only grazes her: the other half was a sliver of skin
  -- and its copy stayed whole over her (a 45 degree blade on an animated death). Across the waist instead
  if not (pos and neg) then
    local front, back = 0, 0
    for _, b in ipairs(LIMB_ROOTS) do
      local l = bone_loc(mesh, b)
      if l then if dot(sub(l, at), n) < 0 then back = back + 1 else front = front + 1 end end
    end
    if front == 0 or back == 0 then
      local a, b = bone_loc(mesh, "Bip001-Spine"), bone_loc(mesh, "Bip001-Spine1")
      if a and b then
        at = add(a, scale(sub(b, a), 0.4))
        log(string.format("blade (%s): it ran along her with every limb on one side, cut across the waist at %s instead",
          why, v3(at)))
        return start(pawn, mesh, at, why, "split", norm(sub(b, a)), { at = at, n = norm(sub(b, a)) })
      end
    end
  end
  -- a plane across her that meets the spine only between the pelvis and the first spine bone goes through her hips:
  -- the legs stayed on her half and the crotch went with the other, both flattened into the cut. Such a cut goes
  -- across the stomach instead, 40 % of the way from Spine to Spine1, at the same angle
  if pos and neg and (hs[1] < 0) ~= (hs[2] < 0) and (hs[2] < 0) == (hs[3] < 0) then
    local a, b = bone_loc(mesh, "Bip001-Spine"), bone_loc(mesh, "Bip001-Spine1")
    if a and b then
      at = add(a, scale(sub(b, a), 0.4))
      log(string.format("blade (%s): it crossed the hips, moved up to the stomach at %s", why, v3(at)))
    end
  end
  return start(pawn, mesh, at, why, "split", n, { at = at, n = n })
end

local function stage_tick(q)
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

function M.tick(pawn)
  if cfg().enabled == false then return end
  native_tick()
  blood_tick()
  pools_tick()
  for i = #later, 1, -1 do
    local l = later[i]
    l.n = l.n - 1
    if l.n <= 0 then
      table.remove(later, i)
      local ok, err = pcall(l.fn)
      if not ok then log("delayed step failed: " .. tostring(err)) end
    end
  end
  for i = #bleeds, 1, -1 do
    local b = bleeds[i]
    b.left = b.left - 1
    b.n = (b.n or 0) + 1
    -- the next spurt, from the same place on the stump, pointing the way the stump does now
    if b.every and b.n % b.every == 0 and b.left > 0 and valid(b.comp) then
      try(function() b.comp:ResetSystem() end)
    end
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
        -- where each half's skin stretches (sbslice "s"): stretched triangles and the bones they hang on
        for _, h in ipairs({ { "her half", w.her }, { "copy", w.comp } }) do
          if valid(h[2]) then log(string.format("split stretch, %s at %.1f s: %s", h[1], w.n * TICK_S, stretch_report(h[2]))) end
        end
        if w.n == 60 then copy_watch = nil end
      end
    end
  end
  local q = pending
  if not q then return end
  if not valid(q.mesh) then pending = nil; return end
  if q.wait > 0 then q.wait = q.wait - 1; return end
  -- a stage that throws would run again on every tick and block every later cut: it ends the cut instead
  local ok, err = xpcall(stage_tick, debug and debug.traceback or tostring, q)
  if not ok then
    if pending == q then pending = nil end
    log(string.format("%s (%s) failed at stage %s, dropped: %s", q.kind, q.why, tostring(q.stage), tostring(err)))
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
  -- a cut's openings already pool where they lie
  if #decals > 0 or #trackers > 0 then return end
  -- a pool of the same decals spreading from under her pelvis (the game's looping floor effect read as stretched
  -- particles)
  if not bone_loc(mesh, "Bip001-Pelvis") then return end
  track(pawn, function()
    local l = valid(mesh) and bone_loc(mesh, "Bip001-Pelvis")
    return l and vec(l.X, l.Y, l.Z) or nil
  end, "body", mesh)
end

-- a split that didn't come off: its weights, copies and caps go, the earlier cuts stay
function M.undo_split()
  local keep = {}
  for _, c in ipairs(cuts) do
    if c.bone == "split" or c.bone == "split copy" then
      if valid(c.mesh) and addr(c.mesh) == c.addr then command(string.format("x%x,0", c.mesh:GetAddress())) end
    else keep[#keep + 1] = c end
  end
  cuts = keep
  restore_rehomed()
  for _, c in ipairs(clones) do
    local a = addr(c)
    if a then forced[a] = nil end
    if valid(c) then try(function() c:K2_DestroyComponent(c) end) end
  end
  clones = {}
  copy_watch = nil
  if #cuts == 0 then command("r") end
  release_lods()
end

-- undo everything before she is reused (respawn / sandbox recover)
function M.cleanup(pawn, mesh)
  blood_down()
  local nd = pools_clear()
  if nd > 0 then log(string.format("removed %d floor blood decals", nd)) end
  pending = nil
  bleeds = {}
  bleed_logged = false
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
  local nh = 0
  for _, pc in ipairs(hung) do
    if valid(pc) then try(function() pc:BreakConstraint() end); try(function() pc:K2_DestroyComponent(pc) end); nh = nh + 1 end
  end
  hung = {}
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
  -- a split's other half goes (after its weights, which the DLL tracks by component), its pieces back on her first
  local nr = restore_rehomed()
  if nr > 0 then steps[#steps + 1] = string.format("pieces(%d)", nr) end
  local nc = 0
  for _, c in ipairs(clones) do
    local a = addr(c)
    if a then forced[a] = nil end
    if valid(c) then try(function() c:K2_DestroyComponent(c) end); nc = nc + 1 end
  end
  clones = {}
  copy_watch = nil
  if nc > 0 then steps[#steps + 1] = string.format("copies(%d)", nc) end
  if nh > 0 then steps[#steps + 1] = string.format("chains(%d)", nh) end
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
  later = {}
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
  spawned, bleeds, caps, cuts, forced, clones, rehomed = {}, {}, {}, {}, {}, {}, {}
  later, hung = {}, {}
  bleed_logged = false
  pending, collision_saved, self_saved, copy_watch = nil, nil, nil, nil
  cache, nosink_cache = {}, {}
  -- a collection's values live in the old world, which is gone with them
  body_blood, stub_dims = nil, nil
  decals, trackers, no_decals = {}, {}, {}
end

return M
