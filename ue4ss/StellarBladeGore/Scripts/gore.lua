-- gore.lua: dismemberment and blood for Eve.
--
-- Cutting (sbslice.dll, see "skin cut" in native/sbslice/sbslice.c): the DLL splits her skin weights at a plane
-- through a limb, so the limb side follows only limb bones and the body side only body bones, collapses the
-- triangles across the cut onto helper bones next to the joint, and reports where both openings are. This
-- script then breaks the ragdoll constraint at that limb (its bodies carry the piece away), covers both
-- openings with a flesh cap and adds blood. The game's own slicer can't do this on Eve: it hides the cut region
-- through a material parameter only its gore master has. The DLL reads LOD0's CPU copy, which it makes the
-- engine keep for every skeletal mesh as it loads (outfits, faces, enemies: nothing of theirs is in the data mod).
-- The DLL is reached through the unused cheat SBRewardGroupDropFormationPathLocation, which it repoints.
-- A vertical split clones her body and face; each copy keeps one side of a plane through the spine and the copy
-- becomes its own ragdoll (see "vertical split" below).
-- Blood: the game's own Niagara systems, spawned on hits, on the cut (pulses out of each opening) and as
-- floor drips and pools; the game's gore sounds play on cuts; a hit she lives through leaves a mark (hit_mark). Caps and lids use the game's meat material.
-- Everything here is undone when she recovers (skin weights, the collapsed helper bones on the shared mesh
-- asset, caps, effects, broken constraints, forced LOD).

local M = {}
M.niagaraBlood = true
local ctx -- log, try, valid, v3, tune (set by M.init)

local CHEAT_CDO = "/Script/SB.Default__SBCheatManager"
-- what can come off: the bone whose subtree leaves, the axis the cut plane is square to (from, default the bone
-- itself, to the next joint) and where along it (0 = from, 1 = to; "auto" cuts close to the joint, so the stump
-- that now follows the body rigidly stays short). mode / radius: sbslice.dll's cut mode (see skin_cut there).
-- The head: Eve's face is its own mesh, weighted to the head and the neck. The head's subtree is the head alone
-- (the clavicles hang off the neck) and her outfit skin has no head bone near the neck, so the face goes along
-- whole (MODE_WHOLE) and the outfit is cut mid-neck by position (MODE_PLANE: what is above the plane within the
-- radius leaves or vanishes into the stump)
local MODE = { cut = 0, whole = 1, plane = 2, hole = 3, side = 4 }
local PARTS = {
  ["Bip001-L-UpperArm"] = { to = "Bip001-L-Forearm", kind = "limb" },
  ["Bip001-R-UpperArm"] = { to = "Bip001-R-Forearm", kind = "limb" },
  ["Bip001-L-Forearm"] = { to = "Bip001-L-Hand", kind = "limb" },
  ["Bip001-R-Forearm"] = { to = "Bip001-R-Hand", kind = "limb" },
  ["Bip001-L-Thigh"] = { to = "Bip001-L-Calf", kind = "limb" },
  ["Bip001-R-Thigh"] = { to = "Bip001-R-Calf", kind = "limb" },
  ["Bip001-L-Calf"] = { to = "Bip001-L-Foot", kind = "limb" },
  ["Bip001-R-Calf"] = { to = "Bip001-R-Foot", kind = "limb" },
  -- under her bust: its lowest skin is 126 cm up in her bind pose, Spine1 120, Spine2 128.5, so 0.3 is 122.4 and a
  -- cut leaned bodyTilt (15 degrees) still passes under it at her front, 13 cm out. A body cut is made here
  -- whatever height the blade crossed her at (at 0.5-0.9 it ran through a breast)
  ["Bip001-Spine1"] = { to = "Bip001-Spine2", at = 0.3, kind = "torso" },
  -- 4.1 cm up the 5.9 cm neck (0.5 sat by the shoulders; 0.3 was 1.8 cm over its joint); the face (down to 1.2 cm
  -- under the head's joint) goes whole with the head, so the plane stays under it
  ["Bip001-Head"] = { from = "Bip001-Neck", to = "Bip001-Head", at = 0.7, kind = "head", mode = MODE.plane, radius = 8.5 },
}
-- arms and legs come off well down the upper arm or thigh (0.15 left a stub at the shoulder or hip)
local CUT_AT_DEFAULT = 0.4
-- a blade's cut never lands closer to the limb's root than this
local BLADE_AT_MIN = 0.3
-- an enemy's limb cut that takes fewer vertices than this off it took no limb: its mesh has none there (the Tachy
-- boss's body has no left arm, her wing mesh is it: a cut there took 41 shoulder plate vertices and left a cap
-- floating where an arm would be, the Play As slice sweep). The next nearest part is tried instead
M.ENEMY_LIMB_MIN = 150
-- a vertical split: the body and face are cloned, each copy keeps one side of a plane through the spine (MODE_SIDE)
-- and the copy becomes its own ragdoll. The face's eyes, teeth and brows only know the head bone, so its vanished
-- side collapses onto a borrowed bone no face vertex uses (Spine1), made to follow the head
local SPLIT_SINK = "Bip001-Spine1"
local SPLIT_RIDE = dofile("ue4ss/Mods/StellarBladeGore/Scripts/split_rides.lua")
-- the joints a split sorts the arms and legs by (shoulder, hip). Not LIMB_ROOTS' clavicles: those sit by the neck, and
-- a split leaned beside it gave both arms to the half with the head, one cut through at the shoulder
local SPLIT_LIMBS = { "Bip001-L-UpperArm", "Bip001-R-UpperArm", "Bip001-L-Thigh", "Bip001-R-Thigh" }
-- what each kind of cut picks from, nearest to the hit (no lower limbs: a whole limb reads better)
local POOL = {
  limb = { "Bip001-L-UpperArm", "Bip001-R-UpperArm", "Bip001-L-Thigh", "Bip001-R-Thigh" },
  head = { "Bip001-Head" },
  torso = { "Bip001-Spine1" },
}
-- where a living hit's mark can land (M.hit_mark): a bone segment (bone to next joint) and r, about half the part's
-- thickness in cm
local MARK_AT = {
  { bone = "Bip001-Neck", to = "Bip001-Head", r = 4.5 },
  { bone = "Bip001-L-Forearm", to = "Bip001-L-Hand", r = 2.8 },
  { bone = "Bip001-R-Forearm", to = "Bip001-R-Hand", r = 2.8 },
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
  -- red blood: the monster hit and its decal (NS_HitBlood_Monster_01_*, NS_HitBlood_SpawnDecal_L) are the Naytiba's
  -- glowing orange liquid (MI_A_EmissiveLiquid, EnemyCommon/MI_ParBloodDecal); Eve's own hit blood and the flesh
  -- decal use MI_A_DefaultBlood and the common decal, like the bleed
  hit = "/Game/Art/FX/Char/Common/Hit/PC/NS_HitBlood_PC_01.NS_HitBlood_PC_01",
}
local SFX -- cue catalog, installed with the audio module after its dependencies are ready
-- the cap: the engine's sphere (radius 50) flattened onto the opening, with the game's cut-flesh material
local CAP_MESH = "/Engine/BasicShapes/Sphere.Sphere"
-- the game's meat (lit, its own colour, normal and ORM maps on UV0), as on the Nest's flesh. MI_CutDamage, the cap
-- before, is a monster-damage dissolve material (MA_CH_DamageGore: masked by distance from the actor) that read as a
-- glossy, broken texture on a lid
local CAP_MATERIAL = "/Game/Art/FX/MA/Enviroment/MI_A_Meat_01_1.MI_A_Meat_01_1"
-- matte caps (capMatte): the game's character gore master with the meat's own textures, its roughness held up
M.matte = { checked = false, ok = nil, master = "/Game/Art/Character/Generic/GlobalMasterMaterials/MA_CH_Standard_Gore.MA_CH_Standard_Gore", tex = {
  Basecolor = "/Game/Art/FX/Tex/Enviroments/T_A_Meat_01_A.T_A_Meat_01_A",
  ORM = "/Game/Art/FX/Tex/Enviroments/T_A_Meat_01_ORM.T_A_Meat_01_ORM",
  ["Baked NormalMap"] = "/Game/Art/FX/Tex/Enviroments/T_A_Meat_01_N.T_A_Meat_01_N",
} }
-- the bone in a stump: the game's generic snapped-bone mesh (Naytiba damage bone textures), unused by anything
-- in the shipped levels as far as the asset list shows
local STUB_MESH = "/Game/Art/Character/Generic/GenericAsset/GM_Brokenbone.GM_Brokenbone"
-- Eve's skin master (MA_Skin_EVE, MF_SkinBloodFX) reads her blood layer from this collection: BloodFactor,
-- BloodOffset (and DirtFactor, DirtOffset), shared by every PC material
local MPC_DIRTY = "/Game/Art/FX/MPC/MPC_PCDirtyOffset.MPC_PCDirtyOffset"

local native = { state = "init", waited = 0 }
local spawned = {}  -- Niagara components to remove on recovery
local bleeds = {}   -- looping blood and separately pulsed stump spurts, stopped after `left` ticks
local later = {}    -- { n, fn }: run fn in n ticks (a split's blood, once the halves have come apart)
M.impactSteps = { ["cut sound"] = true, ["smash blood burst"] = true,
  ["smash mesh load"] = true, ["smash chunks"] = true, ["smash hit blood"] = true,
  ["smash splat"] = true, ["cut splat"] = true, ["body stump bleed"] = true,
  ["piece stump bleed"] = true, ["stump spurt"] = true, ["burst ground spot"] = true, ["hit splat"] = true }
local caps = {}     -- cap actors (and bone stubs)
local hung = {}     -- PhysicsConstraintComponents holding an accessory chain a limb cut kept on the body
local trackers = {} -- bleeding openings leaving drips and pools on the floor (see pools below)
local decals = {}   -- floor blood decal components, removed on recovery
M.drips = {}        -- those of them that are drips (first to go at the cap)
M.burstDots = setmetatable({}, { __mode = "k" }) -- burst spots persist even when the decal budget is full
local no_decals = {} -- { comp, addr, was }: her meshes kept from receiving the floor blood while it is down
local cuts = {}     -- { mesh, addr, bone } per cut, in order
local forced = {}   -- address -> component this script forced to LOD0
local clones = {}   -- components made for a split (the other half's body), destroyed on cleanup
local rehomed = {}  -- { comp, parent, socket, master }: gloves, suit pieces, accessories moved onto a split's copy
local copy_watch = nil -- { comp, n }: a split's copy, its ragdoll logged for a couple of seconds
local limb_watch = nil -- { mesh, bone, kept, anchor, n }: a limb cut's stretched skin and hanging chains, logged at 1 and 5 s
local skinned = {}      -- split lids that bend with her spine: { actor, pmc, comp, bones, v = per vertex skin, n }
-- the cut in progress, in stages a few ticks apart (see M.slice): { stage, wait, pawn, mesh, hit, why, ... }
local pending = nil
-- a blunt kill's piece to meat (see smash below): bones hidden, components made invisible ({ c, b }; c)
M.smashed = { bones = {}, shown = {} }
local queued = {}   -- more cuts from the same killing blow (multiCut), each started once the one before it is done
local collision_saved = nil -- the living mesh's collision setup, while a cut piece needs world collision
local self_saved = nil      -- { mesh, resp }: her PhysicsBody response before a cut turned self-collision off
-- enemies (enemies.lua): the same cuts on a generic humanoid enemy's corpse. Everything a cut leaves (caps, effects,
-- bleeds, pools, delayed steps, the cut records) is tagged with the enemy it was made for (owned: item -> its
-- address; Eve's are untagged or false), so a corpse going away takes only its own, and her recovery leaves theirs.
-- cur: the enemy the code running now cuts (nil: Eve). Their mesh assets are shared by every enemy of the kind, so
-- their sinks are put back once the last cut corpse of a kind is gone (see M.enemy_gone). faced: enemies built like
-- Eve (the Airborne Squad: her skeleton, a separate face mesh), cut with her rules: the face goes with the head
local enemy = { owned = setmetatable({}, { __mode = "k" }), kept = setmetatable({}, { __mode = "k" }), cur = nil, faced = {},
  shrink = {}, -- { a, s, t0, over }: a dissolving corpse's caps shrinking away (M.enemy_fading)
  faded = {} }
local TICK_S = 0.033 -- main.lua polls every 33 ms
-- the main bodies of a cut-off piece, below its root bone (side left out)
local PIECE_CHAIN = { Thigh = { "Thigh", "Calf", "Foot" }, Calf = { "Calf", "Foot" }, UpperArm = { "UpperArm", "Forearm", "Hand" },
  Forearm = { "Forearm", "Hand" }, ["Bip001-Head"] = { "Head" }, ["Bip001-Spine1"] = { "Spine1", "Spine2", "Neck", "Head" } }
M.guardedAssets = {}

local function cfg() return ctx.tune.gore or {} end
local function log(s) ctx.log("gore: " .. s) end
local try, valid, v3 = nil, nil, nil

local function read_file(p) local f = io.open(p, "r"); if not f then return nil end; local s = f:read("a"); f:close(); return s end

-- Asset wrappers and cache invalidation share the native rooted-object state.
M.assets = dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore_assets.lua")(M, native,
  function() return ctx end, function() return try, valid end, log)
local load_obj = M.assets.load

-- the stumps as the game made Tachy's (tachy_core.lua): her damage material on the caps,
-- their flesh mapped onto its disc, and her metal bone and tubes in place of GM_Brokenbone. The material and its
-- textures are the game's own (loaded from its paks, nothing shipped)
M.TACHY_MAT = "/Game/Art/Character/NPC/CH_NPC_TachyNPC/Materials/MI_CH_NPC_TachyNPC_Destroyed.MI_CH_NPC_TachyNPC_Destroyed"
function M.tachy()
  if M.tachy_data == nil then
    local ok, t = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/tachy_core.lua")
    M.tachy_data = ok and type(t) == "table" and t.disc and t.verts and t.tris and t or false
    if not M.tachy_data then log("tachy stumps: tachy_core.lua NOT read (" .. tostring(t) .. "), the meat as before") end
  end
  return M.tachy_data or nil
end
-- the cap's material: Tachy's on a lid mapped onto her disc (tachyLids; not a split's lid pieces, built: theirs tile
-- the meat). Off by default: on the caps' procedural mesh her flesh read pale and washed out whatever its parameters
-- (playtest), so lids keep 0.3.0's meat and only the bone and tubes are hers
function M.cap_mat(built)
  if not built and M.tachy() and cfg().tachyLids then return M.TACHY_MAT end
  return cfg().capMaterial or CAP_MATERIAL
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

-- a cut stage's time, step by step (mark), logged by stage_tick when the stage shows as a stutter: the cuts
-- hitched with no sbslice command over 15 ms (twenty-fifth playtest)
local prof
local function mark(what)
  if not prof then return end
  local t = os.clock()
  local ms = (t - prof.t) * 1000
  if ms >= 1 then prof[#prof + 1] = string.format("%s %.0f", what, ms) end
  prof.t = t
end

-- Native bridge retains live access to guards, context and cuts across startup and world cleanup.
local command, native_tick = dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore_native.lua")(M, native, cfg, load_obj,
  vec, mark, log, read_file, CHEAT_CDO, function() return ctx end, function() return try, valid end,
  function() return cuts end)
function M.native_ready() return native.state == "ready" end
-- main.lua's death cut timed step by step as a stage is: it was one 81 ms frame with nothing to say where (playtest)
function M.prof_begin() prof = { t = os.clock() } end
function M.prof_end() local p = prof; prof = nil; return p and table.concat(p, ", ") or "" end
M.mark = mark
M.command = command -- (active.lua: her sword's split)

-- sbslice's stretch probe on comp's LOD0, its bone indices named
-- dump: also writes the skin as posed to probe<dump>.obj (sbslice; tune.probes)
local function stretch_report(comp, dump)
  local r = command(string.format("s%x,0%s", comp:GetAddress(), dump and string.format(",%x", dump) or ""))
  local function nm(i) return try(function() return comp:GetBoneName(tonumber(i)):ToString() end) or i end
  local head, shown = r:match("^(.-) shown=(.*)$")
  head = (head or r):gsub("(%d+):(%d+):([%d%.]+)", function(i, n, far) return string.format("%s x%s (%s cm off it)", nm(i), n, far) end)
  if not shown then return head end
  -- the triangles that show (not wholly on sinks), by bone
  shown = shown:gsub("(%d+):(%d+)", function(i, n) return string.format("%s x%s", nm(i), n) end)
  return head .. " shown=" .. shown
end

function M.init(c)
  ctx = c
  try, valid, v3 = c.try, c.valid, c.v3
end

-- Sound cue choices and throttling are shared with the asset preload queue.
local sfx
SFX, sfx = dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore_audio.lua")(cfg, load_obj,
  function(o) return valid(o) end, log, vec, function() return ctx end)
M.sfx = sfx

-- Voice state is shared with cut cleanup and the preload queue.
local vox = dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore_voice.lua")(M, cfg, load_obj,
  function(...) return try(...) end, function(o) return valid(o) end, log, vec, function() return cuts end,
  function() return ctx end)

-- Eve's blood effects (the bleed, her hit blood: MA_A_DefaultBlood_01, MA_A_GpuBlood_01) take their colour from
-- MPC_BloodParameters (DefaultBlood 0.15, 0, 0; DefaultBlood2 0.23, 0.05, 0; EmissiveBloodMinValue 0.15, read out of
-- the asset), and sprayed bright red, not the crimson of her pools (playtest). The collection is global and each
-- level gets its own copy, so it is set again at every spawn (tune.gore.bloodTint)
local niagara
do -- (a block: the main chunk is at Lua's 200 locals)
local tinted = nil -- the game's values, logged once
local function blood_tint(comp)
  local t = cfg().bloodTint
  if type(t) ~= "table" then M.bloodTintApplied = nil; return end
  local parts = {}
  for k, v in pairs(t) do
    if type(v) == "table" then
      parts[#parts + 1] = tostring(k) .. "=" .. table.concat({ tostring(v[1]), tostring(v[2]), tostring(v[3]), tostring(v[4]) }, ",")
    else parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
  end
  table.sort(parts)
  local sig = table.concat(parts, ";")
  if M.bloodTintApplied and M.bloodTintApplied.sig == sig and os.clock() - M.bloodTintApplied.at < 1 then return end
  local mpc = load_obj("/Game/Art/FX/MPC/MPC_BloodParameters.MPC_BloodParameters")
  local kml = mpc and load_obj("/Script/Engine.Default__KismetMaterialLibrary")
  if not kml then return end
  if not tinted then
    tinted = {}
    for k, v in pairs(t) do
      local was = try(function()
        if type(v) == "table" then
          local c = kml:GetVectorParameterValue(comp, mpc, FName(k))
          return string.format("%.3f, %.3f, %.3f", c.R, c.G, c.B)
        end
        return string.format("%.3f", kml:GetScalarParameterValue(comp, mpc, FName(k)))
      end)
      tinted[#tinted + 1] = k .. " was " .. tostring(was)
    end
    log("blood tint: " .. table.concat(tinted, ", "))
  end
  local ok = true
  for k, v in pairs(t) do
    if not try(function()
      if type(v) == "table" then
        kml:SetVectorParameterValue(comp, mpc, FName(k), { R = v[1] or 0, G = v[2] or 0, B = v[3] or 0, A = v[4] or 1 })
      else kml:SetScalarParameterValue(comp, mpc, FName(k), v) end
      return true
    end) then ok = false end
  end
  if ok then M.bloodTintApplied = { sig = sig, at = os.clock() } end
end

function niagara(sys_path, comp, bone, loc, attached, rot, worldScale, stump)
  if sys_path == FX.hit or sys_path == M.SMASH_BLOOD then blood_tint(comp) end
  local sys = M.guarded_asset(sys_path)
  local lib = load_obj("/Script/Niagara.Default__NiagaraFunctionLibrary")
  if not (sys and lib) then return nil end
  local c
  if attached then
    -- EAttachLocation::KeepWorldPosition = 1, SnapToTarget = 2; ENCPoolMethod::None = 0
    c = try(function() return lib:SpawnSystemAttached(sys, comp, FName(bone or "None"), loc or vec(0, 0, 0),
      rot or { Pitch = 0, Yaw = 0, Roll = 0 }, loc and 1 or 2, false, true, 0, false) end)
  else
    c = try(function() return lib:SpawnSystemAtLocation(comp, sys, loc, { Pitch = 0, Yaw = 0, Roll = 0 },
      worldScale or vec(1, 1, 1), false, true, 0, false) end)
  end
  if valid(c) then spawned[#spawned + 1] = c end
  return c
end
end

local function bone_loc(mesh, b) return try(function() return mesh:GetSocketLocation(FName(b)) end) end
local function parent_bone(mesh, b)
  local p = try(function() return mesh:GetParentBone(FName(b)):ToString() end)
  return p ~= "None" and p or nil
end
local function addr(o) return try(function() return o:GetAddress() end) end
-- Simulated cloth can bypass cut skin weights; use the skinned form for this outfit until recovery.
M.weddingCloth = {}
function M.wedding_cloth(mesh)
  local full = try(function() return mesh.SkeletalMesh:GetFullName() end) or ""
  if not full:lower():find("/game/cnsrepacked/5a2518e03d16a0cd/", 1, true) then return end
  local a = addr(mesh)
  if not a or M.weddingCloth[a] then return end
  local v = try(function() return mesh.ClothBlendWeight end)
  if type(v) ~= "number" then log("wedding cloth: blend weight unreadable"); return end
  if try(function() mesh.ClothBlendWeight = 0; return true end) then
    M.weddingCloth[a] = { mesh = mesh, old = v, asset = addr(try(function() return mesh.SkeletalMesh end)) }
    log("wedding cloth: using skinned clothing after cut")
  end
end
-- the mesh asset's name, or nil: a component without a mesh hands Lua a null object, and UE4SS's GetFName on one
-- crashes the game (pcall can't catch an access violation), so check it first
local function mesh_name(comp)
  local m = valid(comp) and try(function() return comp.SkeletalMesh end)
  return valid(m) and try(function() return m:GetFName():ToString() end) or nil
end
local function name_of(comp) return mesh_name(comp) or "?" end
-- a component's mesh asset (its address): an enemy's sinks are put back per asset
function enemy.asset(comp) local m = valid(comp) and try(function() return comp.SkeletalMesh end); return valid(m) and addr(m) or nil end
local function already_cut(mesh, bone)
  local a = addr(mesh)
  for _, c in ipairs(cuts) do
    if c.addr == a and c.fullSmash then return true end
    if c.addr == a and c.bone == bone then return true end
    -- (or gone with a smashed part: an arm under her smashed upper body, a forearm under its smashed upper arm)
    if c.addr == a and c.smashed and try(function() return mesh:BoneIsChildOf(FName(bone), FName(c.bone)) end) == true then
      return true
    end
  end
  return false
end
-- a limb's next joint, for its segment (a cut's plane, the blade's pick of a limb): one cut off before lies wherever its
-- piece went. Raven's calf flew off at 1210 cm/s, and the thigh's plane, 38% of the way to it, lay 100 cm off her body,
-- met no skin and changed her weights for nothing: her stumps and pieces drawn in the wrong places (playtest). It is
-- put where it was on its parent as it came off (M.stub_note, at the cut), turned with the parent now
M.already_cut = already_cut
M.stubs = {}  -- mesh address -> bone -> { up (its parent), off (in the parent's frame, unscaled) }
function M.qturn(q, v)
  local tx, ty, tz = 2 * (q.Y * v.Z - q.Z * v.Y), 2 * (q.Z * v.X - q.X * v.Z), 2 * (q.X * v.Y - q.Y * v.X)
  return vec(v.X + q.W * tx + q.Y * tz - q.Z * ty, v.Y + q.W * ty + q.Z * tx - q.X * tz, v.Z + q.W * tz + q.X * ty - q.Y * tx)
end
function M.bone_xf(mesh, b)
  return try(function()
    local x = mesh:GetSocketTransform(FName(b), 0) -- RTS_World
    local t, r, sc = x.Translation, x.Rotation, x.Scale3D
    return { t = vec(t.X, t.Y, t.Z), q = { X = r.X, Y = r.Y, Z = r.Z, W = r.W },
      s = sc and vec(sc.X ~= 0 and sc.X or 1, sc.Y ~= 0 and sc.Y or 1, sc.Z ~= 0 and sc.Z or 1) or vec(1, 1, 1) }
  end)
end
function M.stub_note(mesh, bone)
  local ma = addr(mesh)
  if not ma then return end
  local s = M.stubs[ma] or {}
  M.stubs[ma] = s
  -- (by its mesh asset too: the address can be another mesh's after a level change or an outfit's)
  local sm = try(function() return mesh.SkeletalMesh:GetAddress() end)
  if s[bone] and s[bone].sm == sm then return end
  local up = try(function() return mesh:GetParentBone(FName(bone)):ToString() end)
  local p, c = up and up ~= "None" and M.bone_xf(mesh, up), bone_loc(mesh, bone)
  if not (p and c) then return end
  local o = M.qturn({ X = -p.q.X, Y = -p.q.Y, Z = -p.q.Z, W = p.q.W }, vec(c.X - p.t.X, c.Y - p.t.Y, c.Z - p.t.Z))
  s[bone] = { up = up, off = vec(o.X / p.s.X, o.Y / p.s.Y, o.Z / p.s.Z), sm = sm }
end
function M.joint(mesh, b)
  local s = M.stubs[addr(mesh) or 0]
  local x = s and s[b]
  if x and x.sm == try(function() return mesh.SkeletalMesh:GetAddress() end) and M.already_cut(mesh, b) then
    local p = M.bone_xf(mesh, x.up)
    if p then
      local o = M.qturn(p.q, vec(x.off.X * p.s.X, x.off.Y * p.s.Y, x.off.Z * p.s.Z))
      return vec(p.t.X + o.X, p.t.Y + o.Y, p.t.Z + o.Z)
    end
  end
  return bone_loc(mesh, b)
end

-- the parts to try, closest to the hit first; only the one tune names, if it names one
local function rank_bones(mesh, hit, kind)
  local want = not enemy.cur and cfg().bone or "auto"
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

-- The native response format is isolated from the cut and split lifecycle.
local num, triple, opening
do
  local response = dofile("ue4ss/Mods/StellarBladeGore/Scripts/slice_response.lua")
  num, triple, opening = response.num, response.triple, response.opening
end

local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function cross(a, b) return vec(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end

-- Procedural cap geometry is independent of the actor and cut lifecycle.
local lid_mesh = dofile("ue4ss/Mods/StellarBladeGore/Scripts/cap_geometry.lua")(vec, add, scale, sub, dot, norm, cross)

-- Tachy opening frames and procedural flesh surfaces share the gore module settings.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/tachy_geometry.lua")(M, cfg, vec, add, scale, sub, dot, norm, cross)

-- the flesh on a cap: MI_A_Meat_01_1 is an effect material whose BloodColor glows (emissive 10, 2.4, 0: bright orange
-- on her stumps), so each cap gets its own instance with tune.gore.capBloodColor
local cap_mid_logged = false
-- the meat material has no roughness of its own (BloodColor, BaseColorDesaturation and UseEmissive only; its shine is
-- in its ORM texture): the stumps looked wet and mirrored the room (playtest). capMatte puts the same textures on
-- MA_CH_Standard_Gore, whose Roughness Min/Max hold it matte. Its colour textures must take (read back), else the
-- meat material as before: the master's own default is a UV grid
function M.matte_cap(comp)
  local matte = M.matte
  local m = cfg().capMatte
  if type(m) ~= "table" or m.enabled == false or matte.ok == false then return false end
  local master = load_obj(m.material or matte.master)
  if not master then matte.ok = false; return false end
  local mid = try(function() return comp:CreateDynamicMaterialInstance(0, master, FName("None")) end)
  if not valid(mid) then matte.ok = false; return false end
  local took, missed = {}, {}
  for name, path in pairs(matte.tex) do
    local tex = load_obj(path)
    local ok = tex and try(function()
      mid:SetTextureParameterValue(FName(name), tex)
      local back = mid:K2_GetTextureParameterValue(FName(name))
      return valid(back) and back:GetAddress() == tex:GetAddress()
    end)
    if ok then took[#took + 1] = name else missed[#missed + 1] = name end
  end
  local r = m.roughness or { 0.75, 1.0 }
  try(function()
    mid:SetScalarParameterValue(FName("Roughness Min"), r[1] or 0.75)
    mid:SetScalarParameterValue(FName("Roughness Max"), r[2] or 1.0)
    mid:SetScalarParameterValue(FName("Metallic"), 0)
    -- (the master dithers by this mask, DitherTemporalAA: a lid on it didn't look solid, playtest)
    mid:SetScalarParameterValue(FName("OpacityMask Intensity"), 1)
  end)
  if not matte.checked then
    matte.checked = true
    local rmin = try(function() return mid:K2_GetScalarParameterValue(FName("Roughness Min")) end)
    log(string.format("cap material: matte (%s), textures %s%s, roughness min reads %s", tostring(m.material or matte.master),
      #took > 0 and table.concat(took, ", ") or "none", #missed > 0 and (", NOT " .. table.concat(missed, ", ")) or "",
      tostring(rmin)))
  end
  local base = false
  for _, n in ipairs(took) do if n == "Basecolor" then base = true end end
  if not base then
    if matte.ok == nil then log("cap material: the matte master took no colour texture, the meat material as before") end
    matte.ok = false
    return false
  end
  matte.ok = true
  return true
end
-- Tachy's flesh as it showed on the caps: near black red (sRGB 35, 0, 0) and near mirror smooth (her texture's
-- roughness 0.05 over the instance's floor 0.3), so in game the room's reflections were all of it, grey (playtest).
-- Each cap gets its own instance of her material, brighter, tinted crimson and rougher (tune.gore.tachyFlesh); her
-- core keeps hers as it is. False when it wasn't made
function M.tachy_flesh(comp, mat)
  local f = cfg().tachyFlesh
  if type(f) ~= "table" or f.enabled == false then return false end
  local mid = try(function() return comp:CreateDynamicMaterialInstance(0, mat, FName("None")) end)
  if not valid(mid) then return false end
  M.flesh_params(mid, f)
  -- (its component kept for M.reflesh: the menu's flesh rows change the stumps already out. Kept by path, the
  -- instance and then the component were never found again, the rows changed nothing, playtest)
  M.fleshComps = M.fleshComps or {}
  local own = try(function() return comp:GetOwner() end)
  if valid(own) then
    local ca = try(function() return comp:GetAddress() end)
    for i = #M.fleshComps, 1, -1 do if M.fleshComps[i].addr == ca then table.remove(M.fleshComps, i) end end
    M.fleshComps[#M.fleshComps + 1] = { comp = comp, addr = ca, actor = try(function() return own:GetAddress() end) }
    if #M.fleshComps > 64 then table.remove(M.fleshComps, 1) end
  end
  if not M.fleshLogged then
    M.fleshLogged = true
    M.flesh_log(mid)
  end
  return true
end
-- what the mod has out in the world now, for a run of slow frames its own tick didn't cause (main.lua's fps dip)
function M.load_counts()
  local function n(t) local k = 0; for _ in pairs(t) do k = k + 1 end; return k end
  return string.format("caps %d, pool lids %d, floor decals %d, bleeding openings %d, bleed effects %d, effects %d, held chains %d, cuts %d, split pieces %d",
    #caps, #(M.pool.lid or {}), n(decals), n(trackers), n(bleeds), n(spawned), n(hung), #cuts, n(clones))
end
-- the menu changed a flesh setting: every stump's flesh out now takes it
function M.reflesh()
  local f = cfg().tachyFlesh
  if type(f) ~= "table" then return end
  local n, gone, other, last = 0, 0, 0, nil
  local tachy = M.TACHY_MAT and try(function() return StaticFindObject(M.TACHY_MAT) end)
  local ta = valid(tachy) and try(function() return tachy:GetAddress() end)
  -- alive: its actor still one of the cuts' caps or a pool lid (the mod destroys them only off those lists, so a
  -- freed one is never touched)
  -- (by address: each UE4SS call hands back its own Lua object for the same actor, never equal to the list's)
  local live = {}
  local function mark_live(a, ok) local ad = ok and try(function() return a:GetAddress() end); if ad then live[ad] = true end end
  -- (an enemy's caps by enemy.alive: valid() on one the game may have freed crashed UE4SS, 0.3.0)
  for _, x in ipairs(caps) do mark_live(x, enemy.alive(x)) end
  for _, kind in ipairs({ "lid", "core" }) do for _, e in ipairs(M.pool[kind] or {}) do mark_live(e.a, valid(e.a)) end end
  for i = #(M.fleshComps or {}), 1, -1 do
    local k = M.fleshComps[i]
    if k.actor and live[k.actor] and valid(k.comp) then
      -- (the instance it draws now: a pool lid may have gone to a core or the meat since)
      local m = try(function() return k.comp:GetMaterial(0) end)
      local par = valid(m) and try(function() return m.Parent end)
      local isMid = valid(m) and (try(function() return m:GetClass():GetFName():ToString() end) or ""):find("MaterialInstanceDynamic")
      if isMid and valid(par) and ta and try(function() return par:GetAddress() end) == ta then
        M.flesh_params(m, f); n = n + 1; last = m
      else other = other + 1 end
    else table.remove(M.fleshComps, i); gone = gone + 1 end
  end
  log(string.format("menu: flesh set on %d stump(s) out (%d gone, %d on another material)", n, gone, other))
  if last then M.flesh_log(last, n) end
end
function M.flesh_params(mid, f)
  local t = f.tint or {}
  try(function()
    mid:SetScalarParameterValue(FName("Brightness"), f.brightness or 1)
    mid:SetVectorParameterValue(FName("Base Color Tint"), { R = t[1] or 1, G = t[2] or 1, B = t[3] or 1, A = 1 })
    mid:SetScalarParameterValue(FName("Roughness Min"), f.roughness or 0.9)
    mid:SetScalarParameterValue(FName("Desaturation"), f.desaturation or 0)
    -- (partly metallic: its reflections take the flesh's red; on a dielectric they were white over a dark red, the
    -- flesh read pink-grey whatever its tint, playtest)
    mid:SetScalarParameterValue(FName("Metallic"), f.metallic or 1)
    if f.contrast then mid:SetScalarParameterValue(FName("Contrast"), f.contrast) end
  end)
  M.tachy_dull(mid, f)
  -- a glow of its own colour (her colour texture as the emissive one, tinted): lit only by the room, the flesh read
  -- grey-blue in the dark whatever its tint and shine (playtest). EmissivePower 0 turns it off
  local em = f.emissive or {}
  if (em.power or 0) > 0 then
    try(function()
      local base = mid:K2_GetTextureParameterValue(FName("Basecolor"))
      if valid(base) then
        -- (Emissive_CH is a channel mask, a vector: its R picks the Emissive texture's red as the glow)
        mid:SetTextureParameterValue(FName("Emissive"), base)
      end
      local c = em.color or {}
      mid:SetVectorParameterValue(FName("EmissiveColor"), { R = c[1] or 1, G = c[2] or 0.08, B = c[3] or 0.05, A = 1 })
      mid:SetScalarParameterValue(FName("EmissivePower"), em.power)
    end)
  else
    try(function() mid:SetScalarParameterValue(FName("EmissivePower"), 0) end)
  end
end
function M.flesh_log(mid, n)
  do
    local function sc(n) return tostring(try(function() return mid:K2_GetScalarParameterValue(FName(n)) end)) end
    local function vc(n) return tostring(try(function() local v = mid:K2_GetVectorParameterValue(FName(n)); return string.format("%.2f, %.2f, %.2f", v.R, v.G, v.B) end)) end
    local function tc(n) return tostring(try(function() local x = mid:K2_GetTextureParameterValue(FName(n)); return valid(x) and x:GetFName():ToString() or "none" end)) end
    log(string.format("cap material: Tachy's flesh%s, Brightness reads %s, Contrast %s, Roughness Min %s Max %s, Desaturation %s, Metallic %s, AOMultiply %s, AO Tint %s, Emissive %s, Emissive_CH %s, EmissiveColor %s, EmissivePower %s",
      n and string.format(" (%d stumps changed)", n) or "", sc("Brightness"), sc("Contrast"), sc("Roughness Min"), sc("Roughness Max"), sc("Desaturation"), sc("Metallic"), sc("AOMultiply"), vc("AO Tint"),
      tc("Emissive"), vc("Emissive_CH"), vc("EmissiveColor"), sc("EmissivePower")))
  end
end
-- what kept her flesh and bone grey in the dark: the room's reflections (indirect light), which the material's
-- ambient occlusion holds back. Roughness Max with Min, and AOMultiply / AO Tint down (tachyFlesh.ao, .aoTint),
-- on the caps' instance and the core's
function M.tachy_dull(mid, f)
  local a = f.aoTint or {}
  try(function()
    mid:SetScalarParameterValue(FName("Roughness Max"), math.max(f.roughness or 0.9, f.roughnessMax or 1))
    mid:SetScalarParameterValue(FName("AOMultiply"), f.ao or 0.5)
    mid:SetVectorParameterValue(FName("AO Tint"), { R = a[1] or 1, G = a[2] or 1, B = a[3] or 1, A = 1 })
  end)
end
-- the core on her material, a dark grey with a little of the flesh's red (tachyCoreLook: Brightness, Desaturation,
-- Base Color Tint; hers 1, 0, white): as it is near black in the dark, at Brightness 1.8 too light (playtest). Its
-- metal reads as metal only by the room's reflections (dulled with the flesh, AOMultiply down, it looked like pale
-- dirt). False: the caller sets hers
function M.tachy_core_mat(comp, mat)
  local l = cfg().tachyCoreLook
  if type(l) ~= "table" then return false end
  local mid = try(function() return comp:CreateDynamicMaterialInstance(0, mat, FName("None")) end)
  if not valid(mid) then return false end
  local t = l.tint or {}
  try(function()
    mid:SetScalarParameterValue(FName("Brightness"), l.brightness or 1)
    mid:SetScalarParameterValue(FName("Desaturation"), l.desaturation or 0)
    mid:SetVectorParameterValue(FName("Base Color Tint"), { R = t[1] or 1, G = t[2] or 1, B = t[3] or 1, A = 1 })
  end)
  return true
end
-- (Tachy's material: no matte, no BloodColor)
function M.tachy_mat_is(mat)
  local t = M.TACHY_MAT and StaticFindObject and try(function() return StaticFindObject(M.TACHY_MAT) end)
  return valid(t) and try(function() return t:GetAddress() == mat:GetAddress() end) or false
end
-- her textures at full detail on the caps: the streamer sizes a texture by the meshes it knows draw it, and a
-- procedural mesh tells it nothing, so with Tachy herself nowhere near they stayed at a low mip, her bone and core
-- blurry on Eve while sharp on her (playtest). Each texture of her material (its instances' parameters and the base
-- material's own) is flagged to stay fully loaded, once a session (the component's SetTextureForceResidentFlag
-- isn't callable in this build: NOT set, playtest)
M.sharp_done = false
function M.tachy_sharp()
  if M.sharp_done then return end
  M.sharp_done = true
  local m = M.TACHY_MAT and StaticFindObject and try(function() return StaticFindObject(M.TACHY_MAT) end)
  local seen, n, bad = {}, 0, 0
  local function hold(tex)
    if not valid(tex) then return end
    local a = try(function() return tex:GetAddress() end)
    if not a or seen[a] then return end
    seen[a] = true
    local ok = try(function() tex.bForceMiplevelsToBeResident = true; return tex.bForceMiplevelsToBeResident == true end)
    if ok then n = n + 1 else bad = bad + 1 end
  end
  for _ = 1, 8 do
    if not valid(m) then break end
    try(function() m.TextureParameterValues:ForEach(function(_, e) hold(e:get().ParameterValue) end) end)
    try(function() m.CachedExpressionData.ReferencedTextures:ForEach(function(_, e) hold(e:get()) end) end)
    m = try(function() return m.Parent end)
  end
  log(string.format("tachy stumps: %d of her textures held at full detail%s", n,
    bad > 0 and string.format(", %d NOT", bad) or ""))
end
local function set_cap_material(comp, mat, meat)
  if not mat then return end
  if M.tachy_mat_is(mat) then
    local made
    if meat == "core" then made = M.tachy_core_mat(comp, mat) else made = M.tachy_flesh(comp, mat) end
    if not made then try(function() comp:SetMaterial(0, mat) end) end
    M.tachy_sharp()
    return
  end
  if not meat and not cfg().debugCaps and M.matte_cap(comp) then return end
  -- debugCaps: every cap and lid glows green, to tell them apart from her skin in game
  local c = cfg().debugCaps and { 0, 8, 0 } or cfg().capBloodColor
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

-- cap and stub actors made ahead, while she plays (M.watch, one a look): made in the cut's own frames (an actor, its
-- procedural mesh, its material instance, each a handful of engine calls) they were most of the caps' and stubs'
-- 10-17 ms a stage, a stutter at every cut (playtest). The cut takes one and moves it where it goes; with none left
-- one is made there and then. lid: with its procedural mesh and material; plain: a static mesh actor (stubs, spheres)
M.pool = { lid = {}, core = {}, plain = {}, want = { lid = 6, core = 6, plain = 6 } }
function M.pool_make(pawn, kind)
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  local cls = load_obj("/Script/Engine.StaticMeshActor")
  local at = try(function() local v = pawn:K2_GetActorLocation(); return vec(v.X, v.Y, v.Z) end)
  if not (gs and cls and at) then return nil end
  local tm = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = at, Scale3D = vec(1, 1, 1) }
  local a = try(function()
    local d = gs:BeginDeferredActorSpawnFromClass(pawn, cls, tm, 1, nil)
    return gs:FinishSpawningActor(d, tm)
  end)
  if not valid(a) then return nil end
  try(function() a:SetActorHiddenInGame(true) end)
  local root = try(function() return a.StaticMeshComponent end)
  if valid(root) then
    -- a spawned StaticMeshActor is static: it can't take a mesh or follow a bone until it is movable
    try(function() root:SetMobility(2) end)
    try(function() root:SetCollisionEnabled(0) end)
    try(function() root:SetCastShadow(false) end)
  end
  local e = { a = a, root = root }
  if kind == "lid" or kind == "core" then
    local pmc_cls = load_obj("/Script/ProceduralMeshComponent.ProceduralMeshComponent")
    local pmc = pmc_cls and try(function()
      return a:AddComponentByClass(pmc_cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }, false)
    end)
    if not valid(pmc) then try(function() a:K2_DestroyActor() end); return nil end
    try(function() pmc:SetCollisionEnabled(0) end)
    try(function() pmc:SetCastShadow(false) end)
    e.mat = kind == "core" and "core" or M.cap_mat()
    set_cap_material(pmc, load_obj(kind == "core" and M.TACHY_MAT or e.mat), kind == "core" and "core" or nil)
    e.pmc = pmc
  end
  return e
end
-- one for a cut (kept in caps, which destroys it with the cut), at at
function M.pool_take(pawn, kind, at)
  local list, e = M.pool[kind], nil
  while #list > 0 and not e do
    local x = table.remove(list)
    if valid(x.a) and (kind == "plain" or valid(x.pmc)) then e = x end
  end
  e = e or M.pool_make(pawn, kind)
  if not e then return nil end
  caps[#caps + 1] = e.a
  if at then try(function() e.a:K2_SetActorLocation(at, false, {}, true) end) end
  return e
end
-- photo mode's own hide option hides her actor, and with it every part of her, but not her caps and stubs: actors of
-- their own, on her bones, they stayed floating where her stumps were (reported). Hidden along with her (on), and
-- what was hidden here shown again (off); an enemy's are left alone
M.photoHid = nil
function M.photo_hide(pawn, on)
  if on then
    if M.photoHid or not valid(pawn) then return 0 end
    local pa, hid = addr(pawn), {}
    for _, a in ipairs(caps) do
      if valid(a) and try(function() return a.bHidden end) == false
        and addr(try(function() return a:GetAttachParentActor() end)) == pa then
        try(function() a:SetActorHiddenInGame(true) end)
        hid[#hid + 1] = a
      end
    end
    M.photoHid = hid
    return #hid
  end
  local hid = M.photoHid
  M.photoHid = nil
  for _, a in ipairs(hid or {}) do if valid(a) then try(function() a:SetActorHiddenInGame(false) end) end end
  return hid and #hid or 0
end
-- one more made, while either pool is short (a level reload leaves them gone: dropped as they're found so)
function M.pool_fill(pawn)
  for _, kind in ipairs({ "lid", "core", "plain" }) do
    local list = M.pool[kind]
    for i = #list, 1, -1 do if not valid(list[i].a) then table.remove(list, i) end end
    if #list < M.pool.want[kind] then
      local e = M.pool_make(pawn, kind)
      if e then list[#list + 1] = e end
      return
    end
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
  local spawn_at = function(at, k)
    local e = M.pool_take(pawn, k, at)
    if not e then return nil end
    return e.a, e.root, e.pmc, e
  end
  local kind
  local a, root, lid
  local pmc_cls = o.p and load_obj("/Script/ProceduralMeshComponent.ProceduralMeshComponent")
  if pmc_cls then
    local c, verts, tris, normals, uvs, tangents, colors
    if built then c, verts, tris, normals, uvs, tangents, colors = table.unpack(built)
    elseif M.tachy() and g.tachyLids then c, verts, tris, normals, uvs, tangents, colors = M.tachy_lid(o, g.tachyCapScale or 1.0, M.tachy())
    else c, verts, tris, normals, uvs, tangents, colors = lid_mesh(o, g.capScale or 1.05) end
    mark("cap mesh")
    local pmc, e
    a, root, pmc, e = spawn_at(c, "lid")
    -- (a pool lid made under the other look, or the look changed in the menu since)
    local want = M.cap_mat(built)
    if e and valid(pmc) and e.mat ~= want then set_cap_material(pmc, load_obj(want)); e.mat = want end
    mark("cap actor")
    if not a then log("cap: spawn failed"); return end
    if valid(pmc) then
      -- 4.27 takes UV0..UV3; older builds only UV0
      local made = try(function() pmc:CreateMeshSection_LinearColor(0, verts, tris, normals, uvs, {}, {}, {}, colors, tangents, false); return true end)
        or try(function() pmc:CreateMeshSection_LinearColor(0, verts, tris, normals, uvs, colors, tangents, false); return true end)
      local sections = made and try(function() return pmc:GetNumSections() end) or 0
      mark("cap section")
      if sections > 0 then
        kind = string.format("lid %d points", #o.p)
        lid = pmc
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
      a, root = spawn_at(o.c, "plain")
      if not a then log("cap: spawn failed"); return end
    else
      -- A failed procedural lid was spawned at its outline mean, which can differ from the fitted ellipse centre.
      -- The fallback sphere is fitted around o.c, so move the reused actor there before attaching it.
      try(function() a:K2_SetActorLocation(o.c, false, {}, true) end)
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
  M.repose(a, mesh, bone)
  -- EAttachmentRule::KeepWorld = 1
  try(function() a:K2_AttachToComponent(mesh, FName(bone), 1, 1, 1, false) end)
  mark("cap place")
  return a, kind, lid
end

-- GM_Brokenbone's bounds, for a split's spine halves (splitSpine): its own axes read from them (the longest one is the
-- bone), so the asset's orientation doesn't matter
local stub_dims = nil
-- her back on a plane with normal z: square to her spine, away from her front. A Bip001 spine bone's own -Z points
-- to her back (within 15 degrees on every outfit's skeleton, pelvis to head), so it is read off the spine bone at
-- the cut (bone, else Spine1). It came from the hips and shoulders before (her right from the left thigh and upper
-- arm to the right ones), which were wherever her cut-off limbs lay by then: a waist cut after both arms and legs
-- put the spine stub off to her side (seventeenth playtest)
-- posed: the bone as noted at the cut (M.posed, the frame the opening is in). Read live a tick or two later, a flying
-- head had turned on by up to 120 degrees and its stub went off to the side, by the ear
local SPINE_BONES = { ["Bip001-Pelvis"] = 1, ["Bip001-Spine"] = 1, ["Bip001-Spine1"] = 1, ["Bip001-Spine2"] = 1, ["Bip001-Neck"] = 1, ["Bip001-Head"] = 1 }
local function back_on(mesh, z, bone, posed)
  local km = load_obj("/Script/Engine.Default__KismetMathLibrary")
  local b = SPINE_BONES[bone or ""] and bone or "Bip001-Spine1"
  local up = posed and M.posed_up(mesh, b)
  up = up or km and try(function()
    local r = mesh:GetSocketRotation(FName(b))
    local v = km:GetUpVector({ Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll })
    return vec(v.X, v.Y, v.Z)
  end)
  if up then
    local back = scale(up, -1)
    local back_z = norm(sub(back, scale(z, dot(back, z))))
    if back_z then return back_z end
  end
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
-- (a neck's: towards the nape, a little short of the waist's)
M.NECK_BACK = 0.5
-- spine: the cut goes through the spine or the neck (a thigh's parent is Bip001-Spine too, and by that bone's name its
-- hip stump's stub sat halfway to her back, sixteenth playtest)
function M.stub_centre(mesh, o, z, bone, spine)
  local c = outline_centre(o) or o.c
  if spine then
    local back = back_on(mesh, z, bone, true)
    if back and o.x then
      local x = norm(sub(o.x, scale(z, dot(o.x, z))))
      local y = x and cross(z, x)
      if x and y then
        -- how far the opening reaches that way: its outline when it has one, else its fitted ellipse. Across her
        -- (square to her back) the bone goes midway between the outline's sides: the centroid alone, then pushed
        -- back, left a neck's bone off to one side (playtest)
        local half = math.sqrt((o.e.X * dot(back, x)) ^ 2 + (o.e.Y * dot(back, y)) ^ 2)
        if o.p then
          local side = cross(z, back)
          local lo, hi
          half = 0
          for _, pt in ipairs(o.p) do
            local d = sub(pt, c)
            half = math.max(half, dot(d, back))
            local sd = dot(d, side)
            lo, hi = math.min(lo or sd, sd), math.max(hi or sd, sd)
          end
          if lo then c = add(c, scale(side, (lo + hi) / 2)) end
        end
        local neck = bone == "Bip001-Neck" or bone == "Bip001-Head"
        c = add(c, scale(back, half * (neck and M.NECK_BACK or SPINE_BACK)))
      end
    end
  end
  return c
end
-- Tachy's core (M.tachy): her bone and tubes as a procedural mesh on a pool lid, at the opening's middle, out along its
-- normal, scaled from her 4.1 cm disc to the opening's mean radius (at most tachyCoreMax cm), standing on the cap's
-- dome. A limb's only: an arm's bone and tubes in a waist read as mushrooms, not a spine (playtest), so a spine or
-- neck cut gets the snapped bone at her spine (stub)
-- spine: her bone alone (M.tachy_bone) at her spine, its shaft stubBone of the opening wide (at most spineBoneMax cm)
function M.core(pawn, mesh, o, bone, rides, t, spine)
  local g = cfg()
  local z = norm(o.z)
  local x, y, mirrored
  if z then x, y, mirrored = M.tachy_frame(o, z) end
  if not x then return nil end
  local r = 0
  if o.p then
    local m = vec(0, 0, 0)
    for _, q in ipairs(o.p) do m = add(m, q) end
    m = scale(m, 1 / #o.p)
    for _, q in ipairs(o.p) do local d = sub(q, m); r = r + math.sqrt(math.max(dot(d, d) - dot(d, z) ^ 2, 0)) end
    r = r / #o.p
  else
    r = (o.e.X + o.e.Y) / 2
  end
  -- (tachy_lid's dome: the core stands where the lid rises to, from the lid's own radius)
  -- (on the meat lids, lid_mesh's: its inner ring's height, where the core's base reaches; at her flat lid's it sank
  -- into the meat)
  local dome = g.tachyLids and M.tachy_dome(r) * 0.85 + 0.2 or math.min(math.max(r * 0.18, 0.4), 1.8) * 0.7 + 0.2
  -- (a leg's bone thicker: tachyCoreLeg times; at the arm's it looked thin in a thigh, playtest)
  -- (her bone leans, some 14 degrees off her disc's normal: it looked bent, playtest; the core sheared upright, its
  -- lean along x and y per unit of height)
  local bn = M.tachy_bone(t)
  local src, ox, oy, hs, lx, ly = t.tris, 0, 0, 1, bn.lx or 0, bn.ly or 0
  -- (a leg's without her gold socket: an arm's only, playtest)
  if o.leg and not spine then
    src = {}
    for i = 1, #t.tris, 3 do
      if not bn.gold[t.tris[i]] then for k = 0, 2 do src[#src + 1] = t.tris[i + k] end end
    end
  end
  -- (and along the limb or spine, not square to the cut: a slanted cut tipped the bone with it, playtest. Within 80
  -- degrees of the cut's normal; the frame's x and y squared to it. Within 50 a steep cut across a hanging arm left
  -- the bone standing along the cut's normal, straight down the stump, playtest)
  if o.axis and dot(o.axis, z) > 0.17 then
    local za = o.axis
    local xa = norm(sub(x, scale(za, dot(x, za))))
    if xa then
      local ya = cross(za, xa)
      if mirrored then ya = scale(ya, -1) end
      o.cz, z, x, y = z, za, xa, ya
    end
  end
  if spine then
    local narrow = math.min(o.e.X, o.e.Y)
    local thick = math.min(math.max(narrow * 2 * (g.stubBone or 0.3), 0.8), g.spineBoneMax or 3.5)
    src, ox, oy = bn.tris, bn.cx, bn.cy
    r = thick / (2 * bn.shaft)
    -- (a waist's wider by spineBoneWaist, no taller: thin in a waist, playtest)
    local wide = o.waist and (g.spineBoneWaist or 1.6) or 1
    r = r * wide
    -- (taller than her own: at its height, a third of its width, it barely showed above the flesh, playtest)
    hs = (g.spineBoneOut or 1.2) / wide
  else
    r = math.min(r * (g.capScale or 1.05), g.tachyCoreMax or 6) * (g.tachyCore or 1) * (o.leg and (g.tachyCoreLeg or 1) or 1)
  end
  -- (its foot where the cut's own normal puts it: on the lid)
  local zc = o.cz or z
  o.cz = nil
  local c = add(M.stub_centre(mesh, o, zc, bone, spine), scale(zc, dome))
  local v = t.verts
  local verts, normals, uvs, tangents, colors, tris = {}, {}, {}, {}, {}, {}
  -- This loop runs for every vertex of the detailed bone mesh. Avoid creating five
  -- intermediate vector tables for each transformed position, normal and tangent.
  local function to(a, b, h)
    return vec(x.X * a + y.X * b + z.X * h, x.Y * a + y.Y * b + z.Y * h, x.Z * a + y.Z * b + z.Z * h)
  end
  local top, foot = 0, 0
  for i = 1, #v, 11 do top = math.max(top, v[i + 2] * hs) end
  for i = 1, #v, 11 do
    local a, b, h = (v[i] - ox - lx * v[i + 2]) * r, (v[i + 1] - oy - ly * v[i + 2]) * r, v[i + 2] * hs * r
    verts[#verts + 1] = to(a, b, h)
    -- (its foot's width: what of it lies in its lowest quarter)
    if v[i + 2] * hs < 0.25 * top then
      local q = verts[#verts]
      foot = math.max(foot, math.sqrt(math.max(dot(q, q) - dot(q, z) ^ 2, 0)))
    end
    normals[#normals + 1] = norm(to(v[i + 3], v[i + 4], (v[i + 5] + lx * v[i + 3] + ly * v[i + 4]) / hs)) or z
    tangents[#tangents + 1] = { TangentX = to(v[i + 6] - lx * v[i + 8], v[i + 7] - ly * v[i + 8], v[i + 8]), bFlipTangentY = mirrored }
    uvs[#uvs + 1] = M.bone_uv(t, (i - 1) // 11, v[i + 9], v[i + 10])
    colors[#colors + 1] = { R = 1, G = 1, B = 1, A = 1 }
  end
  -- (mirrored, each triangle the other way round, or its front faces in)
  for i = 1, #src, 3 do
    if mirrored then tris[i], tris[i + 1], tris[i + 2] = src[i + 2], src[i + 1], src[i]
    else tris[i], tris[i + 1], tris[i + 2] = src[i], src[i + 1], src[i + 2] end
  end
  -- tipped along the limb on a slanted cut, its foot is square to the limb, not the cut: the side of it towards the
  -- cut's high side stood off the lid by its width x tan(tilt), and on a sharp slant the bone floated over the stump
  -- (playtest). Sunk into the meat by that much, at most its own width and a half
  local ct = math.min(math.max(dot(zc, z), 0.05), 1)
  if ct < 0.999 and foot > 0 then c = sub(c, scale(z, math.min(foot * math.sqrt(1 - ct * ct) / ct, foot * 1.5))) end
  mark("stub geometry")
  local e = M.pool_take(pawn, "core", c)
  mark("stub actor")
  if not (e and valid(e.a) and valid(e.pmc)) then log("tachy core: spawn failed"); return nil end
  local a, pmc = e.a, e.pmc
  try(function() a:K2_SetActorRotation({ Pitch = 0, Yaw = 0, Roll = 0 }, false) end)
  local made = try(function() pmc:CreateMeshSection_LinearColor(0, verts, tris, normals, uvs, {}, {}, {}, colors, tangents, false); return true end)
    or try(function() pmc:CreateMeshSection_LinearColor(0, verts, tris, normals, uvs, colors, tangents, false); return true end)
  mark("stub section")
  if not made then log("tachy core: no mesh section"); return nil end
  if e.mat ~= "core" then set_cap_material(pmc, load_obj(M.TACHY_MAT), "core"); e.mat = "core" end
  mark("stub material")
  M.repose(a, mesh, rides or bone)
  mark("stub repose")
  try(function() a:K2_AttachToComponent(mesh, FName(rides or bone), 1, 1, 1, false) end)
  mark("stub attach")
  return a
end
local function stub(pawn, mesh, o, bone, rides, spine)
  local g = cfg()
  if g.boneStubs == false or not (o and o.z and o.e) then return nil end
  -- (Tachy's core, or at the spine her bone alone: the game's GM_Brokenbone, a human bone, is gone from the stumps)
  if M.tachy() then return M.core(pawn, mesh, o, bone, rides, M.tachy(), spine) end
  return nil
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
  local made, rides = 0, {}
  for _, b in ipairs(SPLIT_RIDE.of(q, comp)) do rides[b] = true end
  for _, sg in ipairs(SPINE_SEGS) do
    local a0, b0 = rides[sg[1]] and bone_loc(comp, sg[1]), bone_loc(comp, sg[2])
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
        local e = rot and M.pool_take(q.pawn, "plain", mid)
        local act = e and e.a
        if valid(act) and rot then
          local root = e.root
          if valid(root) then try(function() root:SetStaticMesh(sm) end) end
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

-- Body blood owns its ramp state; world cleanup preserves only the values to restore.
M.bodyBlood = dofile("ue4ss/Mods/StellarBladeGore/Scripts/body_blood.lua")(M, cfg, load_obj,
  function() return ctx end, function() return try, valid end, log, MPC_DIRTY, TICK_S)

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
-- drips and splats: the pools' own (the Raven cinematic's splat, MI_FloorBloodDecal_5 on MA_A_BloodDecal_01, has no
-- BloodBright darkening and twice the specular: drips read bright red beside the dark pools, playtest)
local DRIP_DECALS = POOL_DECALS
-- the pool's final radius in cm by the cut bone (first match)
local POOL_R = { { "Neck", 55 }, { "Head", 55 }, { "Spine", 110 }, { "Pelvis", 110 }, { "Clavicle", 110 },
  { "body", 110 }, { "Thigh", 60 }, { "UpperArm", 40 },
  { "Calf", 38 }, { "Forearm", 30 }, { "split", 90 } }
local function pool_radius(bone)
  for _, e in ipairs(POOL_R) do if tostring(bone):find(e[1], 1, true) then return e[2] end end
  return 45
end
local function pick(list) return list[math.random(#list)] end

-- Floor traces and bounded geometry checks stay separate from pool ownership and scheduling.
local floor_at = dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore_floor.lua")(M, load_obj,
  function() return try end, log, vec, add, sub, scale, len, norm, dot, cross)

-- one decal on the floor under p, r cm across (radius); its box reaches 8 cm into and out of the floor (20 cm drew
-- the pools far up a wall beside them, playtest)
-- Rooted effects and floor materials have their cached identity checked by the native object guard.
-- Never trust an unguarded cached asset wrapper: freed objects can reuse its address.
function M.guarded_asset(path)
  return load_obj(path)
end
-- Pool work reads the current lists; player and enemy cleanup can replace them.
local shield, track, track_opening, pools_tick, pools_clear = dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore_pools.lua")(
  M, enemy, cfg, load_obj, function() return try, valid end,
  function() return later, trackers, decals, no_decals end,
  function(d, t) decals, trackers = d, t end, function(n) no_decals = n end,
  log, vec, add, sub, scale, len, pick, floor_at, pool_radius, addr, bone_loc, POOL_DECALS, DRIP_DECALS, TICK_S)

-- Per-mesh cut lists own their cached trees and are cleared with world state.
local bone_lists = dofile("ue4ss/Mods/StellarBladeGore/Scripts/bone_lists.lua")(M,
  function(...) return try(...) end, function(o) return valid(o) end, addr, enemy, function() return ctx end)
local LIMB_ROOTS, nosink_list, limbs_list, limb_root, bodies_of, nocarry_list =
  bone_lists.roots, bone_lists.nosink, bone_lists.limbs, bone_lists.root, bone_lists.bodies, bone_lists.nocarry

-- limbs: true (a torso cut: every limb, and the drivers), a bone name (a limb or head cut: every limb but the one it
-- is on), nil; driven: the drivers too (a split: its point sinks on driven helpers followed the limbs it lets go,
-- cones out of both halves, playtest); after: the drivers that follow the limbs a split half lets go (M.side_drivers)
-- the "n" command's list portion per mesh asset and cut shape: every input (nosink, limb, nocarry, bodies, driven,
-- after) is a per-asset property that never changes, so reassembling the deduped string on every cut is wasted Lua on
-- a cut frame (5 ms of it on a death's head cut, playtest). The component's own address stays in the command itself.
-- (on M: the chunk is at Lua's 200 locals)
M.nosink_cmd = M.nosink_cmd or {}
local function send_nosink(comp, limbs, driven, after)
  local sm = try(function() return comp.SkeletalMesh end)
  local key = valid(sm) and addr(sm)
    and (addr(sm) .. "|" .. tostring(limbs) .. "|" .. tostring(driven) .. "|" .. (enemy.cur and "e" or "h") .. "|" .. tostring(after))
  local suffix = key and M.nosink_cmd[key]
  if not suffix then
    local s = nosink_list(comp)
    if limbs then
      -- each bone once: the DLL reads at most as many fields as she has bones (and Bip001-* limb bones are in both)
      local seen, out = {}, {}
      local own = limbs ~= true and limb_root(comp, limbs) or nil
      for h in (s .. "," .. limbs_list(comp, own)):gmatch("[^,]+") do if not seen[h] then seen[h] = true; out[#out + 1] = h end end
      s = table.concat(out, ",")
    end
    mark("lua: nosink, limbs")
    local nc = nocarry_list(comp)
    -- her bodies only for a limb or the head (a cut through the torso keeps its sinks where they were)
    local bl = {}
    if limbs ~= true then for i in pairs(bodies_of(comp)) do bl[#bl + 1] = string.format("%x", i) end end
    local dr = (limbs == true or driven) and not enemy.cur and M.driven_list(comp) or ""
    mark("lua: nocarry, bodies, driven")
    -- (fffc's bones after fffd's: they are driven too, the later list wins)
    suffix = string.format("%s,ffff%s%s%s%s", s, nc ~= "" and ("," .. nc) or "",
      #bl > 0 and (",fffe," .. table.concat(bl, ",")) or "", dr ~= "" and (",fffd," .. dr) or "",
      after and after ~= "" and (",fffc," .. after) or "")
    if key and next(bodies_of(comp)) then M.nosink_cmd[key] = suffix end
  end
  local r = command(string.format("n%x,%s", comp:GetAddress(), suffix))
  if r:sub(1, 2) ~= "ok" then log("nosink list refused: " .. r) end
end

-- one sbslice.dll cut on a component: "c<comp>,<lod>,<bone>,<mode>,<radius in mm>[,<depth in mm>]", all hex
local function cut_command(comp, index, mode, radius, at, n, depth, limbs)
  -- a leg: the drivers that follow it (fffc), which the body's skin lets go of, and every driver a seam's bone of last
  -- resort (fffd): the animation points them after the flying leg, the hip skin that hung partly on a thigh's
  -- (Ab-L-AX2 under Dm-L-Thigh-point) made a spike out of her hips with both legs off, and each hip's seam had closed
  -- on Dm-*-Thigh-point itself (playtest). The cut's weights stay for the cuts after it. (Not an arm's: its drivers
  -- shape the shoulder its rim runs round, and a bent arm's cut lost half its opening in the test harness)
  local leg = type(limbs) == "string" and not enemy.cur and (limbs:find("Thigh") or limbs:find("Calf") or limbs:find("Foot"))
  local after = leg and M.side_drivers(comp, { limbs }) or nil
  mark("lua: side drivers")
  send_nosink(comp, limbs, leg and true or nil, after)
  local s = string.format("c%x,0,%x,%x,%x", comp:GetAddress(), index, mode or 0, math.floor((radius or 0) * 10 + 0.5))
  if depth then s = s .. string.format(",%x", math.floor(depth * 10 + 0.5)) end
  return command(s, at, n)
end

-- Native asset rooting and asynchronous requests share native state with the cut scheduler.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore_preload.lua")(native, command, cfg, function() return try, valid end, log)

local function ok_cut(r) return r:sub(1, 2) == "ok" and (num(r, "seam") or 0) + (num(r, "limb") or 0) > 0 end

-- Eve's face: the component in her face slot (MeshInfoList, ESBMesh_Face = 1), else a skeletal mesh child of
-- the body whose asset is named like a face (Face, or Facial: Raven's, CH_M_NA_53_Facial, as Stellar Blade Play As
-- puts it on Eve's face component)
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
      if not face and n and n:find("Fac[ei]") then face = c end
    end)
  end)
  return face
end

M.face_of = face_of

-- her hair (mesh slots Hair1, Ponytail, PonytailShort) that is showing, and any hair another mod put on her body's
-- pose or on her head (Play As's Raven: her own hair, a component of its own at Eve's head bone, its strands simulated)
local HAIR_SLOTS = { [2] = true, [3] = true, [4] = true }
local function hair_of(pawn)
  local out, seen = {}, {}
  try(function()
    pawn.MeshInfoList:ForEach(function(_, e)
      local info = e:get()
      local c = info.MeshComponent
      if HAIR_SLOTS[info.MeshSlot] and mesh_name(c) and try(function() return c:IsVisible() end) == true then
        out[#out + 1] = c
        seen[addr(c) or 0] = true
      end
    end)
  end)
  local body = try(function() return pawn.Mesh end)
  local me = valid(body) and addr(body)
  if me then
    try(function() body.AttachChildren:ForEach(function(_, e)
      local c = e:get()
      local n = mesh_name(c)
      local a = n and addr(c)
      if a and not seen[a] and n:find("Hair", 1, true) and try(function() return c:IsVisible() end) == true then
        local m = try(function() return c.MasterPoseComponent:Get() end)
        local sock = not m and try(function() return c.AttachSocketName end)
        local onHead = sock and (try(function() return sock:ToString() end) == "Bip001-Head"
          or try(function() return body:BoneIsChildOf(sock, FName("Bip001-Head")) end) == true)
        if m and addr(m) == me or onHead then out[#out + 1] = c; seen[a] = true end
      end
    end) end)
  end
  return out
end
M.hair_of = hair_of

-- who she looks like when another mod plays her as someone else (Stellar Blade Play As, or any mod putting that character's
-- meshes on Eve): "tachy" (Tachy's NPC body), "scarlet" (her DLC body), "raven" (Raven's own hair on her pose), else nil.
-- Nothing is asked of the other mod: her meshes say it
function M.looks_as(pawn, mesh)
  local b = mesh_name(mesh) or ""
  if b:find("TachyNPC", 1, true) then return "tachy" end
  if b:find("CH_M_NA_961", 1, true) then return "scarlet" end
  local raven = false
  try(function() mesh.AttachChildren:ForEach(function(_, e)
    local c = e:get()
    local n = mesh_name(c)
    if n and n:find("CH_M_NA_53_Hair", 1, true) and try(function() return c:IsVisible() end) == true then raven = true end
  end) end)
  return raven and "raven" or nil
end

-- a split's other pieces: whatever else her body poses (outfit parts on master pose: gloves, boots, suit pieces) or
-- carries on a socket (accessories) stayed on her half and followed its dropped limbs, which keep flopping unseen:
-- they floated where she was cut. Each goes to the half it lies on (its socket, else the middle of its bounds),
-- except what the head carries (face, hair, earrings, hairpins): her half keeps the head whole
local function rehome(q, b2, at, n)
  q.pieces = { her = {}, copy = {} }
  local skip = {}
  for _, c in ipairs({ q.mesh, b2, q.face }) do local a = addr(c); if a then skip[a] = true end end
  for _, c in ipairs(clones) do local a = addr(c); if a then skip[a] = true end end
  for _, c in ipairs(hair_of(q.pawn)) do local a = addr(c); if a then skip[a] = true end end
  -- nor another mod's copies of her mesh (M.copies): they take her half's weights, and the copy's half gets its own
  for _, c in ipairs(M.copies_find(q.mesh)) do local a = addr(c); if a then skip[a] = true end end
  -- nor our own caps: her lid and spine pieces stand out of her half, over the plane on the copy's side, so they
  -- went to the copy too and rode its bones; her half lay open and the copy carried both lids, the second one in
  -- flat shards off its body as the halves moved apart (eighteenth playtest)
  for _, act in ipairs(caps) do
    local root = enemy.alive(act) and try(function() return act:K2_GetRootComponent() end)
    local a = root and addr(root)
    if a then skip[a] = true end
  end
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
        if mastered then q.pieces.copy[#q.pieces.copy + 1] = c end
      else
        kept = kept + 1
        if mastered then q.pieces.her[#q.pieces.her + 1] = c end
      end
    end
  end
  log(string.format("split: %d pieces moved to the copy (%s), %d stay on her half", #moved,
    #moved > 0 and table.concat(moved, ", ") or "none", kept))
end

-- outfit pieces on a split half's pose (sleeves, gloves, a suit part over both arms) whose bones of the limbs that
-- went with the other half are hidden: the half's own skin there is gone, but a piece spanning both sides stayed
-- whole and followed the dropped limb's bones, which flop on unseen: a third arm on the half (eighteenth playtest).
-- PBO_None (0): only how they show; hiding with PBO_Term on her mesh stopped her ragdoll (playtest 13)
local hid = {} -- { comp, bone }
local function hide_gone(pieces, bones)
  local names, n = {}, 0
  for _, c in ipairs(pieces or {}) do
    local any = false
    for _, b in ipairs(bones or {}) do
      if b ~= "Bip001-Head" and valid(c) and try(function() return c:GetBoneIndex(FName(b)) end) ~= -1
        and try(function() c:HideBoneByName(FName(b), 0); return true end) then
        hid[#hid + 1] = { comp = c, bone = b }
        any = true
      end
    end
    if any then n = n + 1; names[#names + 1] = name_of(c) end
  end
  return n, table.concat(names, ",")
end

local function restore_rehomed()
  for _, h in ipairs(hid) do
    if valid(h.comp) then try(function() h.comp:UnHideBoneByName(FName(h.bone)) end) end
  end
  hid = {}
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

-- LOD0 forced on a component (on), or let go, its least LOD lowered to 0 with it: a forced LOD can't go under the
-- mesh's least LOD, and the cut's weights are made on LOD0 alone. With Character Detail on Medium every cut but the
-- head's left the skin on its old bones, stretched after the piece in a sheet, the cap floating over it (playtest;
-- the head's collapse moves bones, seen on every LOD)
function M.lod0(comp, on)
  try(function() comp.bOverrideMinLod = on and true or false end)
  if on then try(function() comp:SetMinLOD(0) end) end
  try(function() comp:SetForcedLOD(on and 1 or 0) end)
end

-- every forced one checked twice a second and forced again if anything took it off LOD0: a cut's weights are on LOD0
-- alone, and drawn at another LOD her cut limbs stretched from the body to the flying pieces (reported, a crowded
-- area). Logged once a component (on M: gore.lua is at Lua's 200 locals)
M.lodSeen = {}
function M.lod_guard()
  local now = os.clock()
  if now < (M.lodNext or 0) then return end
  M.lodNext = now + 0.5
  for a, comp in pairs(forced) do
    if valid(comp) then
      local f, o, m = try(function() return comp.ForcedLodModel end), try(function() return comp.bOverrideMinLod end),
        try(function() return comp.MinLodModel end)
      if (f and f ~= 1) or o == false or (m and m ~= 0) then
        M.lod0(comp, true)
        if not M.lodSeen[a] then
          M.lodSeen[a] = true
          log(string.format("LOD: %s taken off LOD0 (forced %s, min %s %s): forced again", mesh_name(comp) or "?",
            tostring(f), tostring(o), tostring(m)))
        end
      end
    end
  end
end
local function force_lod(comp)
  local a = addr(comp)
  if a and not forced[a] then M.lod0(comp, true); forced[a] = comp; return true end
  return false
end

-- give the forced LOD back on every component no cut still needs
local function release_lods()
  for a, comp in pairs(forced) do
    local used = false
    for _, c in ipairs(cuts) do if c.addr == a then used = true end end
    if not used then
      if valid(comp) then M.lod0(comp, false) end
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
-- A chain whose bodies all lie along the limb (none past the limb's end) is a strap on it, not a cape: it follows the
-- plane, whole (CH_P_EVE_14's leg straps hang off the hip 5 to 36% down the thigh; cut off as a piece of their own
-- they flew 2 m off and their skin tore off the leg, playtest screenshot)
local CHAIN_BODIES, CHAIN_OFF = 3, 3
-- how far the bodies of each chain a limb cut kept on the body hang from the bone they were hung on (cm), to tell a
-- stretched cape from stretched skin in the log
local function chain_reach(mesh, tops, anchor)
  local pa = ctx.physics_of(mesh)
  local from = valid(pa) and bone_loc(mesh, anchor)
  if not from then return "no physics" end
  local list = {}
  try(function() pa.SkeletalBodySetups:ForEach(function(_, e) local bs = e:get(); if valid(bs) then list[#list + 1] = bs.BoneName:ToString() end end) end)
  local out = {}
  for _, c in ipairs(tops) do
    local far, n, last = 0, 0, c
    for _, d in ipairs(list) do
      if d == c or try(function() return mesh:BoneIsChildOf(FName(d), FName(c)) end) == true then
        local l = bone_loc(mesh, d)
        if l then
          n = n + 1
          local r = len(sub(l, from))
          if r > far then far, last = r, d end
        end
      end
    end
    out[#out + 1] = string.format("%s: %d bodies, farthest %s %.0f cm from %s", c, n, last, far, anchor)
  end
  return table.concat(out, "; ")
end

-- returns the tops, and those of them that are straps above the plane (hung on the body, never cut off on their own)
-- (each physics asset's bodies and chains, which don't change with the pose, worked out once: walking every body,
-- its parents through the engine and every other body under it, each cut, was most of a cut's 13 ms of Lua before
-- sbslice.dll, playtest)
M.chainCache = {}
function M.chain_info(mesh, pa)
  local key = addr(pa)
  local t = M.bone_tree(mesh)
  local ci = key and M.chainCache[key]
  if ci and (ci.tree or not t) then return ci end
  local list = {}
  try(function() pa.SkeletalBodySetups:ForEach(function(_, e) local bs = e:get(); if valid(bs) then list[#list + 1] = bs.BoneName:ToString() end end) end)
  local function under(x, y)
    if t and t.index[x] then return x ~= y and M.under(t, t.index[x], y) end
    return try(function() return mesh:BoneIsChildOf(FName(x), FName(y)) end) == true
  end
  local function parent(x)
    if t and t.index[x] then local p = t.pname[t.index[x]]; return p ~= "None" and p or nil end
    return parent_bone(mesh, x)
  end
  ci = { list = list, chain = {}, tree = t ~= nil }
  for _, c in ipairs(list) do
    -- (nor a twist bone with a body of its own, CH_P_EVE_14's Ab-L-Thigh-Tw0: the off-axis test is the pose's, and
    -- with the leg turned it stood 3 cm off, the thigh's own skin and both straps under it kept on her, playtest)
    if not c:find("^Bip001") and not c:find("%-Tw%d+$") then
      local p, anchor = parent(c), nil
      while p and not anchor do
        if p:find("^Bip001") then anchor = p else p = parent(p) end
      end
      local below = {}
      for _, d in ipairs(list) do if d == c or under(d, c) then below[#below + 1] = d end end
      ci.chain[c] = { anchor = anchor, below = below }
    end
  end
  if key and t then M.chainCache[key] = ci end
  return ci
end
local function kept_chains(mesh, bone, a, b, at, n)
  local pa = ctx.physics_of(mesh)
  if not valid(pa) then return {}, {} end
  local ci = M.chain_info(mesh, pa)
  local list, t = ci.list, M.bone_tree(mesh)
  local function under(x, y)
    if t and t.index[x] then return x ~= y and M.under(t, t.index[x], y) end
    return try(function() return mesh:BoneIsChildOf(FName(x), FName(y)) end) == true
  end
  local axis = norm(sub(b, a))
  local out = {}
  for _, c in ipairs(list) do
    local ch = ci.chain[c]
    if ch and ch.anchor == bone and #ch.below >= CHAIN_BODIES then
      local l = bone_loc(mesh, c)
      local off = 0
      if l and axis then local v = sub(l, a); off = len(sub(v, scale(axis, dot(v, axis)))) end
      if off > CHAIN_OFF then out[#out + 1] = c end
    end
  end
  -- only the top of each chain
  local tops, stay = {}, {}
  local span = len(sub(b, a))
  for _, c in ipairs(out) do
    local inner = false
    for _, d in ipairs(out) do if d ~= c and under(c, d) then inner = true end end
    if not inner then
      -- a strap: on the body if its top is behind the plane, else it goes with the limb (not kept)
      -- (a chain reaching further from its top than the limb is long, or named a Cape, is never one: along the limb
      -- was read in the pose, and with her arm out or up CH_P_EVE_09's 80 cm cape hung across it, inside its length,
      -- and was taken for a strap: it went with the arm, its top band still on her shoulder's helpers, or stayed on her
      -- with its bones riding the arm, and stretched from her shoulder to the arm on the floor, playtest screenshot)
      local far, reach = 0, 0
      local top = bone_loc(mesh, c)
      for _, d in ipairs(ci.chain[c].below) do
        local l = bone_loc(mesh, d)
        if l and axis and span > 0 then far = math.max(far, dot(sub(l, a), axis) / span) end
        if l and top then reach = math.max(reach, len(sub(l, top))) end
      end
      if c:find("Cape") or reach > span then far = math.huge end
      if far <= 1 and top and at and n then
        if dot(sub(top, at), n) <= 0 then tops[#tops + 1] = c; stay[c] = true end
      else
        tops[#tops + 1] = c
      end
    end
  end
  return tops, stay
end
M.kept_chains = kept_chains -- (test/sim_cape.lua)

-- the "n" command's skip indices for cutting one chain (top) off its limb: the nosink bones, minus the chain's own
-- subtree (its top stays skipped), plus the limb's subtree. Read off the cached bone tree: walking every bone through
-- the engine here (GetBoneName + BoneIsChildOf per bone) was 19 ms of Lua on a limb cut's chains stage (playtest).
-- Falls back to the engine loop when the tree isn't built yet. (test/sim_cutlist.lua)
function M.chain_skip(mesh, top, limb)
  local skip = {}
  for h in nosink_list(mesh):gmatch("[^,]+") do skip[tonumber(h, 16)] = true end
  local t = M.bone_tree(mesh)
  local n = t and t.n or try(function() return mesh:GetNumBones() end) or 0
  if t and t.done then
    for i = 0, n - 1 do
      local nm = t.name[i] or "None"
      local chain = nm == top or M.under(t, i, top)
      if chain and nm ~= top then skip[i] = nil
      elseif not chain and (nm == limb or M.under(t, i, limb)) then skip[i] = true end
    end
  else
    local under = function(x, y) return try(function() return mesh:BoneIsChildOf(FName(x), FName(y)) end) == true end
    for i = 0, n - 1 do
      local nm = try(function() return mesh:GetBoneName(i):ToString() end) or "None"
      local chain = nm == top or under(nm, top)
      if chain and nm ~= top then skip[i] = nil
      elseif not chain and (nm == limb or under(nm, limb)) then skip[i] = true end
    end
  end
  local list = {}
  for i = 0, n - 1 do if skip[i] then list[#list + 1] = string.format("%x", i) end end
  return list
end

-- bone names to indices off the cached bone tree, falling back to the engine per bone: GetBoneIndex per kept/gone
-- bone on a cut frame is engine calls for what the cut already knows. (test/sim_cutlist.lua)
function M.bone_indices(mesh, names)
  local t = M.bone_tree(mesh)
  local out = {}
  for _, c in ipairs(names) do
    local i
    if t and t.done and t.index[c] ~= nil then i = t.index[c]
    else i = try(function() return mesh:GetBoneIndex(FName(c)) end) end
    if i and i > 0 then out[#out + 1] = i end
  end
  return out
end

-- a skirt's chains with no physics body anywhere on them (their tops: a Skirt bone whose parent isn't one), by bone
-- index. CH_P_EVE_37 (Black Rose) hangs its front and side panels off the thighs' twist bones, animated only: a thigh
-- cut took them off with the leg, and the skirt stretched from her hips to it (Nexus report). A thigh cut keeps them
-- on her rigidly ("g", KEEP_RIGID): their skin stays on the body where it hangs, the ones on her other leg and her
-- pelvis with it (skin partly on the cut thigh went with the leg). Per mesh asset
M.skirtCache = {}
function M.skirt_chains(mesh)
  local sm = try(function() return mesh.SkeletalMesh end)
  local key = valid(sm) and addr(sm)
  if key and M.skirtCache[key] then return M.skirtCache[key] end
  local t = M.bone_tree(mesh)
  if not t then return {} end
  local body = bodies_of(mesh)
  local tops, out = {}, {}
  for i = 0, t.n - 1 do
    local nm = t.name[i] or ""
    if nm:find("Skirt") and not (t.pname[i] or ""):find("Skirt") then tops[#tops + 1] = i end
  end
  for _, i in ipairs(tops) do
    local has = false
    for j = 0, t.n - 1 do if body[j] and M.under(t, j, t.name[i]) then has = true; break end end
    if not has then out[#out + 1] = i end
  end
  if key then M.skirtCache[key] = out end
  return out
end

-- a chain a limb cut kept on the body (the cape off the upper arm's twist bone), cut off at the joint it hangs from as
-- a piece of its own (tune.gore.chains "detach"): the plane through that parent joint, facing down the chain, so all
-- of it is in front. Its own bones may be its sinks this once (they never are: they swing, and the seam swung with
-- them; here the seam is the chain's own top); the limb's bones may not be the body side's sink, the limb is gone
-- (an earlier cut's biceps sink pulled the cape's seam off with the arm). Kept on the body instead, the arm's 80 cm
-- cape hung straight down from the shoulder (sixteenth playtest)
local function detach_cut(mesh, top, limb)
  local index = try(function() return mesh:GetBoneIndex(FName(top)) end)
  local parent = parent_bone(mesh, top)
  local a, b = parent and bone_loc(mesh, parent), bone_loc(mesh, top)
  local n = a and b and norm(sub(b, a))
  if not (index and index >= 0 and n) then return "err no chain " .. top end
  local list = M.chain_skip(mesh, top, limb)
  local nc = nocarry_list(mesh)
  local r = command(string.format("n%x,%s,ffff%s", mesh:GetAddress(), table.concat(list, ","), nc ~= "" and ("," .. nc) or ""))
  if r:sub(1, 2) ~= "ok" then return "err nosink " .. r end
  command(string.format("g%x", mesh:GetAddress()))
  return command(string.format("c%x,0,%x,%x,0", mesh:GetAddress(), index, MODE.cut), a, n)
end

-- her jaw, in the head bone's space: the lowest vertices only the head moves (Face_Jali3) for any plane within 60
-- degrees of the neck, and the neck's direction there. The head bone sits right under her chin (its underside 1-3 mm
-- above a plane at the bone, at bind)
do
local JAW = { {0.0, -6.8, -6.6}, {0.0, -3.0, -4.0}, {2.9, -3.1, -3.1}, {-2.9, -3.1, -3.1}, {-1.2, 0.3, 8.4},
  {-1.0, 0.6, 8.3}, {-0.8, 0.7, 8.0}, {0.0, 0.7, 5.4}, {-1.5, 0.3, 5.1}, {0.0, 0.8, 8.4}, {0.0, 0.6, 8.7},
  {0.0, 0.4, 8.9}, {0.8, 0.7, 8.0}, {1.1, 0.5, 8.3}, {1.3, 0.3, 8.4}, {1.6, 0.3, 5.1}, {-7.7, -5.2, -1.1},
  {-6.7, -3.5, 0.1}, {-7.5, -4.6, -0.7}, {7.7, -5.2, -1.1}, {7.5, -4.6, -0.7}, {6.8, -3.5, 0.1} }
local JAW_AXIS = { 0.0, -0.9907, 0.136 }

-- a beheading's plane kept under her jaw: a nod or a leaning blow put her chin under the plane at the head bone, and
-- the cut took a slice of it with the neck (playtest 39). The plane goes down its normal until every JAW point is
-- jawClear cm above it; when that's more than jawDrop cm, it leans back toward the head's own axis first (straight
-- along it, 0.5 cm does). -> at, n, note
function M.clear_jaw(face, bone, at, n, g) -- (on M: gore.lua is at Lua's 200 locals)
  local q = try(function() local r = face:GetSocketTransform(FName(bone), 0).Rotation; return { r.X, r.Y, r.Z, r.W } end)
  if not q then return at, n, "" end
  local function rot(v)
    local tx, ty, tz = 2 * (q[2] * v[3] - q[3] * v[2]), 2 * (q[3] * v[1] - q[1] * v[3]), 2 * (q[1] * v[2] - q[2] * v[1])
    return vec(v[1] + q[4] * tx + q[2] * tz - q[3] * ty, v[2] + q[4] * ty + q[3] * tx - q[1] * tz, v[3] + q[4] * tz + q[1] * ty - q[2] * tx)
  end
  local head = bone_loc(face, bone)
  if not head then return at, n, "" end
  local pts = {}
  for i, j in ipairs(JAW) do pts[i] = add(head, rot(j)) end
  local own = rot(JAW_AXIS)
  local clear, most = g.jawClear or 0.5, g.jawDrop or 3
  local m, drop
  for k = 0, 4 do
    local nn = k == 0 and n or norm(add(scale(n, 1 - k / 4), scale(own, k / 4))) or n
    m = math.huge
    for _, p in ipairs(pts) do m = math.min(m, dot(sub(p, at), nn)) end
    drop = math.max(0, clear - m)
    if drop <= most or k == 4 then
      if drop == 0 and k == 0 then return at, n, "" end
      return sub(at, scale(nn, drop)), nn, string.format(", %.1f cm down for her jaw%s", drop, k > 0 and string.format(" (leaned %d%% back to her head)", k * 25) or "")
    end
  end
end
end

-- blade: { t, n } where the blade's plane crosses this limb (t along it) and its normal: the cut goes there, leaning
-- with the blade at most sliceTilt degrees off square (her body: at its own height, bodyTilt)
local function cut_limb(pawn, mesh, bone, why, blow, face, blade)
  local g = cfg()
  local part = PARTS[bone]
  local a, b = bone_loc(mesh, part.from or bone), M.joint(mesh, part.to)
  if not (a and b) then log("cut skipped: no bone transform for " .. tostring(bone)); return nil end
  -- (where it is on its parent, for a later cut of the parent: M.joint)
  if part.kind == "limb" then M.stub_note(mesh, bone) end
  local axis = norm(sub(b, a))
  if not axis then return nil end
  -- (Eve's head: higher once her face is cut with it, see below)
  local faced = part.kind == "head" and not (enemy.cur and not face)
  local facecut = faced and g.faceCut ~= false
  local t = tonumber(g.cutAt) or (facecut and tonumber(g.headAt)) or part.at or CUT_AT_DEFAULT
  if blade and part.kind ~= "torso" then t = math.max(BLADE_AT_MIN, math.min(0.9, blade.t)) end
  local at = add(a, scale(sub(b, a), t))
  local n = axis
  -- along the blow: the plane leans until it contains the blow's direction (the normal loses its component along
  -- it), at most blowTilt degrees off square so the stump stays clean; a blow along the limb leaves it square
  local d = blow and norm(blow)
  local lean = ""
  if blade then
    local bn = dot(blade.n, axis) < 0 and scale(blade.n, -1) or blade.n
    local ang = math.acos(math.max(-1, math.min(1, dot(bn, axis))))
    local max = math.rad(g.sliceTilt or 45)
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
  -- across her body: everything above together at most bodyTilt off square, so it stays under her bust
  if part.kind == "torso" then
    local max = math.rad(g.bodyTilt or 15)
    local ang = math.acos(math.max(-1, math.min(1, dot(n, axis))))
    if ang > max then
      local p = norm(sub(n, scale(axis, dot(n, axis))))
      n = p and norm(add(scale(axis, math.cos(max)), scale(p, math.sin(max)))) or axis
      lean = lean .. string.format(" (held to %.0f deg)", math.deg(max))
    end
    -- a waist cut with no blade's angle of its own (rolled, or squared off a blade down her length) leans at random:
    -- up to bodyLeanSide degrees to either side and bodyLeanFront with her front lower (higher, it ran into her bust).
    -- Square every time, every waist cut looked the same (playtest)
    local f = (not blade or blade.square) and body_frame(mesh)
    local side, front = math.rad(g.bodyLeanSide or 20), math.rad(g.bodyLeanFront or 10)
    if f and (side > 0 or front > 0) then
      local sx, fy = (math.random() * 2 - 1) * side, math.random() * front
      local x = norm(sub(f.x, scale(axis, dot(f.x, axis))))
      local y = x and norm(cross(axis, x))
      if y and dot(y, f.y) < 0 then y = scale(y, -1) end
      if y then
        n = norm(add(add(axis, scale(x, math.tan(sx))), scale(y, math.tan(fy)))) or n
        lean = lean .. string.format(" (leaned %.0f deg, her %s side lower, %.0f front down)", math.abs(math.deg(sx)), sx > 0 and "left" or "right", math.deg(fy))
      end
    end
  end
  if facecut and valid(face) and g.jawClear ~= false then
    local note
    at, n, note = M.clear_jaw(face, bone, at, n, g)
    lean = lean .. note
  end
  local index = try(function() return mesh:GetBoneIndex(FName(bone)) end)
  if not index or index < 0 then log("cut skipped: no bone " .. bone); return nil end
  mark("lua: plane")
  -- a head takes the face along first; without that its neck would stretch from the body to the head. Cut on the
  -- neck's plane instead (MODE_PLANE), 8300 face vertices vanished into the stump and the head flew off faceless.
  -- Cut like a limb (faceCut), the face's neck stays on her: its eyes, teeth and brows know only the head bone, so
  -- the head side's seam closes on a bone no face vertex uses (Spine1, SPLIT_SINK), made to follow her head. Whole,
  -- the head took the face's whole neck along, down to her collar
  local fr
  -- (an enemy's head is on its body mesh: the neck's plane cut alone)
  if faced then
    local fi = valid(face) and try(function() return face:GetBoneIndex(FName(bone)) end)
    if not fi or fi < 0 then log("head skipped: no face mesh with " .. bone); return nil end
    local fs = facecut and try(function() return face:GetBoneIndex(FName(SPLIT_SINK)) end)
    local hm = facecut and try(function() return mesh:GetBoneIndex(FName(bone)) end)
    if fs and fs > 0 and hm and hm >= 0 then
      send_nosink(face)
      fr = command(string.format("c%x,0,%x,%x,%x,%x,%x", face:GetAddress(), fi, MODE.cut,
        math.floor((part.radius or 0) * 10 + 0.5), fs, hm), at, n)
    else
      if facecut then log("face: no " .. SPLIT_SINK .. " to close the head's side on, cut whole") end
      facecut = false
      fr = cut_command(face, fi, MODE.whole, part.radius, at, n)
    end
    local report = fr:gsub(" bp=[^ ]+", " bp=<outline>"):gsub(" lp=[^ ]+", " lp=<outline>")
    log(string.format("face %s: %s", name_of(face), report))
    if not ok_cut(fr) then log("head skipped: the face can't be cut (no LOD0 CPU copy: loaded before sbslice.dll?)"); return nil end
  end
  -- the chains that stay on the body ("g": no gone roots, then them); always sent, so an earlier split's limbs aren't
  -- taken for them
  -- and the limbs an earlier cut took off that hang under this one (drop roots): their skin goes with this piece
  -- wherever it lies. Playtest 41: an arm, then the chest along the same blade; the flying arm lay across the chest's
  -- plane, the half on her side lost its weights to her spine and long sheets ran from her to the hand
  local kept, gone, stay = {}, {}, {}
  if (part.kind == "limb" or part.kind == "torso") and (part.mode == nil or part.mode == MODE.cut) then
    if part.kind == "limb" then kept, stay = kept_chains(mesh, bone, a, b, at, n) end
    mark("lua: kept chains")
    local tree, ma = M.bone_tree(mesh), addr(mesh)
    for _, c in ipairs(cuts) do
      if c.addr == ma and c.bone ~= bone and PARTS[c.bone] then
        local inside = tree and tree.index[c.bone] and M.under(tree, tree.index[c.bone], bone)
        if inside == nil then inside = try(function() return mesh:BoneIsChildOf(FName(c.bone), FName(bone)) end) == true end
        if inside then gone[#gone + 1] = c.bone end
      end
    end
    local rigid = part.kind == "limb" and bone:find("Thigh") and M.skirt_chains(mesh) or {}
    mark("lua: gone, skirts")
    local f = { string.format("g%x", mesh:GetAddress()) }
    if #kept > 0 or #gone > 0 or #rigid > 0 then
      f[#f + 1] = "0"
      for _, i in ipairs(M.bone_indices(mesh, kept)) do f[#f + 1] = string.format("%x", i) end
      -- (KEEP_RIGID, 0x8000 on the index)
      for _, i in ipairs(rigid) do f[#f + 1] = string.format("%x", i + 0x8000) end
      if #rigid > 0 then log(string.format("cut %s: %d skirt chain(s) with no body kept on her", bone, #rigid)) end
    end
    if #gone > 0 then
      f[#f + 1] = "0"
      f[#f + 1] = "0"
      for _, i in ipairs(M.bone_indices(mesh, gone)) do f[#f + 1] = string.format("%x", i) end
      log(string.format("cut %s: goes with %s, cut off before, wherever it lies", bone, table.concat(gone, ", ")))
    end
    command(table.concat(f, ","))
  end
  -- an enemy's head is cut like a limb: the plane's mode makes what is past it vanish (Eve's goes on her face mesh)
  local mode = (part.kind == "head" and enemy.cur and not face) and MODE.cut or part.mode
  local r = cut_command(mesh, index, mode, part.radius, at, n, nil, part.kind == "torso" or bone)
  -- The outline is consumed below, but writing hundreds of coordinates to disk cost 5–6 ms per cut.
  local report = r:gsub(" bp=[^ ]+", " bp=<outline>"):gsub(" lp=[^ ]+", " lp=<outline>")
  log(string.format("cut %s (%s) at %.2f %s normal %s%s: %s", bone, why, t, v3(at), v3(n), lean, report))
  -- a body whose neck ends under the plane (a nude mod's body: its neck stops low and the face's own neck goes on up
  -- from there) has nothing to cut at the head's height: lower down the neck until it has (fifteenth playtest: the
  -- head never came off on Eve with no Clothes on), when the face goes whole. A cut face closes the neck itself
  if part.kind == "head" and not facecut and r:sub(1, 2) == "ok" and (num(r, "seam") or 0) == 0 then
    for _, lower in ipairs({ 0.5, 0.3, 0.12, 0 }) do
      if lower < t then
        -- (the empty cut changed no weight: nothing to undo, and "x" would undo her earlier cuts too)
        t, at = lower, add(a, scale(sub(b, a), lower))
        r = cut_command(mesh, index, mode, part.radius, at, n, nil, bone)
        log(string.format("cut %s lower down the neck at %.2f %s: %s", bone, t, v3(at), r))
        if r:sub(1, 2) ~= "ok" or (num(r, "seam") or 0) > 0 then break end
      end
    end
  end
  local faceneck = facecut and (num(fr, "seam") or 0) > 0
  if r:sub(1, 2) ~= "ok" or ((num(r, "seam") or 0) == 0 and not faceneck)
    or ((part.kind ~= "head" or (enemy.cur and not fr)) and (num(r, "limb") or 0) == 0)
    or (enemy.cur and part.kind == "limb" and (num(r, "limb") or 0) < M.ENEMY_LIMB_MIN) then
    if enemy.cur and part.kind == "limb" and r:sub(1, 2) == "ok" and (num(r, "limb") or 0) > 0 then
      log(string.format("cut %s: only %d vertices on it, no limb there on this mesh: the next part instead", bone, num(r, "limb")))
    end
    if fr then log("face put back: " .. command(string.format("x%x,0", face:GetAddress()))) end
    -- an enemy cut that changed weights but took nothing off (what was past the plane had nothing to close on and
    -- vanished): its weights off again when nothing else was cut on it, and kept on record, so its sinks go back
    -- with the corpse's
    if enemy.cur and r:sub(1, 2) == "ok" and (num(r, "seam") or 0) > 0 then
      local ma, earlier = addr(mesh), false
      for _, c in ipairs(cuts) do if c.addr == ma then earlier = true end end
      if not earlier then log("cut undone: " .. command(string.format("x%x,0,1", ma))) end
      cuts[#cuts + 1] = { mesh = mesh, addr = ma, bone = "failed:" .. bone, sm = enemy.asset(mesh) }
    end
    return nil
  end
  -- the chains kept off the limb (a cape) are cut off their roots a frame later each (M.stage_chains): in the limb's
  -- own frame the two cuts were a 50 ms stutter (playtest)
  local chains = {}
  if #kept > 0 and g.chains ~= "body" then
    for _, c in ipairs(kept) do
      if stay[c] then
        log(string.format("cut %s: %s, a strap over the plane, stays on her", bone, c))
      else
        chains[#chains + 1] = c
      end
    end
  end
  return { at = at, n = n, result = r, face = fr and face, face_result = fr, facecut = facecut, kept = kept, detached = {}, chains = chains }
end
function M.stage_chains(q)
  local c = table.remove(q.c.chains, 1)
  if not c then return end
  local dr = detach_cut(q.mesh, c, q.bone)
  log(string.format("cut %s off %s: %s", c, q.bone, dr))
  if ok_cut(dr) then q.c.detached[#q.c.detached + 1] = c end
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
  for _, b in ipairs(q.bone and { q.bone } or q.blade and { q.blade.bone } or rank_bones(q.mesh, q.hit, q.kind)) do
    -- her own fall can't stand on a leg that's gone (both thighs off, and she still played it, eighteenth playtest),
    -- and a headless body playing it on read as no ragdoll at all, only the head falling (reported): legRagdoll,
    -- headRagdoll, armRagdoll switch an animated death to the ragdoll before the cut
    local leg, head = b:find("Thigh") or b:find("Calf") or b:find("Foot"), b:find("Head") or b:find("Neck")
    -- (an arm or the head: always with armRagdoll / headRagdoll on, else armRagdollChance / headRagdollChance of the
    -- time; each arm rolled: both off, likelier)
    local arm = b:find("Arm") or b:find("Hand") or b:find("Clavicle")
    local function chance(on, k) return on == true or math.random() < (tonumber(k) or 0) end
    local rule = leg and cfg().legRagdoll ~= false or head and chance(cfg().headRagdoll, cfg().headRagdollChance)
      or arm and chance(cfg().armRagdoll, cfg().armRagdollChance)
    -- (the switch on a frame of its own, the cut the next: together they were one 50 ms frame, the ragdoll's 35,
    -- playtest)
    if (q.why == "death" or q.why == "after") and rule and ctx.animated and ctx.animated() and ctx.on_need_ragdoll then
      try(function() ctx.on_need_ragdoll(leg and "a leg off" or head and "beheaded" or "an arm off") end)
      if not q.ragged then q.ragged = true; return "again" end
    end
    q.c = cut_limb(q.pawn, q.mesh, b, q.why, blow, q.face, q.blade)
    mark("cut " .. b)
    if q.c then q.bone = b; break end
  end
  if not q.c then log("nothing cut (" .. q.why .. ")"); return false end
  M.wedding_cloth(q.mesh)
  -- Snapshot remaining flesh before this cut itself enters the gone-part list.
  if q.smash then
    q.smashProfile = M.smashed.profile(q.mesh, q.bone)
    if q.fullSmash then
      for _, bone in ipairs({ "Bip001-L-Thigh", "Bip001-R-Thigh" }) do
        local leg = M.smashed.profile(q.mesh, bone)
        q.smashProfile.count = math.min(64, q.smashProfile.count + leg.count)
        q.smashProfile.blood = q.smashProfile.blood + leg.blood
      end
    end
  end
  q.entry = { mesh = q.mesh, addr = addr(q.mesh), bone = q.bone, sm = enemy.asset(q.mesh), riders = {}, quiet = q.quiet }
  cuts[#cuts + 1] = q.entry
  -- (each with its mesh asset: the face's sinks are its own asset's, put back with it, cleanup_eve)
  if q.c.face then cuts[#cuts + 1] = { mesh = q.c.face, addr = addr(q.c.face), bone = "face", sm = enemy.asset(q.c.face) } end
  mark("lua: entry")
  q.parent = parent_bone(q.mesh, q.bone)
  -- a head's own opening is the bottom of the face's neck
  q.ob = opening(q.c.result, "b")
  -- A smash hides the entire detached side: no cap, stump, or bleed ever uses that side's outline.
  -- Parsing its many points on the cut frame cost part of the logged 10 ms opening/ride work.
  if not q.smash then
    q.ol = q.c.face_result and opening(q.c.face_result, "l") or opening(q.c.result, "l")
  end
  -- a cut face's neck closes the stump too: the face's rim, unless the body's goes all round her neck and is wider
  -- (a high collar, CH_P_EVE_10). On CH_P_EVE_30 the body ends under the plane, on CH_P_EVE_29 its collar only
  -- reaches round the back (10 of 16 directions)
  local fb = q.c.facecut and opening(q.c.face_result, "b")
  local function wide(o) return o and math.max(o.e.X, o.e.Y) or 0 end
  local function round(r)
    local most = 0
    for d in (r:match(" bsec=([%d/;.]+)") or ""):gmatch("%d+/%d+/(%d+)") do most = math.max(most, tonumber(d)) end
    return most
  end
  if fb and not (q.ob and round(q.c.result) >= 14 and wide(q.ob) > wide(fb)) then q.ob, q.obFace = fb, true end
  -- the caps and stubs ride the bone each opening's rim rides (the DLL's bb / lb): a thigh's stump follows the hip's
  -- twist helpers, not the pelvis, and a stub on the pelvis slid off to the stump's edge as she moved
  local function ride(key, fallback)
    local i = num(q.c.result, key)
    local nm = i and i >= 0 and try(function() return q.mesh:GetBoneName(i):ToString() end)
    return (nm and nm ~= "None") and nm or fallback
  end
  q.rideB = ride("bb", q.parent or q.bone)
  if q.obFace then
    local i = num(q.c.face_result, "bb")
    local nm = i and i >= 0 and try(function() return q.c.face:GetBoneName(i):ToString() end)
    q.rideB = (nm and nm ~= "None") and nm or q.parent or q.bone
  end
  q.rideL = q.c.face_result and q.bone or ride("lb", q.bone)
  mark("lua: openings, ride bones")
  -- (and the spine bones the stubs look for her back on: back_on, and the cut bone's far end: the stump bone's axis)
  local far = PARTS[q.bone] and PARTS[q.bone].to
  q.posed = M.snap({ { q.mesh, { q.rideB, q.rideL, q.parent or q.bone, q.bone, M.back_bone(q.bone), far } } })
  mark("lua: snap")
  -- (the openings' shared frame from her back as posed at the cut, the snap's Spine1 or the spine bone cut)
  M.posed = q.posed
  local back = q.ob and q.ob.z and norm(q.ob.z) and back_on(q.mesh, norm(q.ob.z), M.back_bone(q.bone), true)
  M.posed = nil
  M.pair(q.ob, q.ol, back, M.side_of(q.bone))
  mark("lua: back, pair")
  q.caps, q.kinds, q.stubs = {}, {}, {}
  return true
end

-- stage 1b, the next tick: the caps and stubs (hidden till the opening). In the cut's own tick they made its frame
-- 20 ms longer, and a killing blow's two or three cuts stuttered one after another (twenty-ninth playtest)
-- (and the caps and the stubs a tick each: together they were 23-29 ms, playtest 41)
-- (a cut's caps and stubs and the bones they ride, on its cuts entry: a split after an arm cut moves the arm's to the
-- copy, M.arms_to_copy)
function M.riders(q, a, bone)
  if q.entry and q.entry.riders and valid(a) then q.entry.riders[#q.entry.riders + 1] = { a = a, bone = bone } end
end
-- an outline's points well off its plane are another layer's (a harness strap counted as going round an arm, 3-5 cm
-- up it and 8-9 cm out): the cap spanned them and was drawn down the arm as a kite (playtest). Left out, when enough stay
function M.flat_outline(o, what)
  if not (o and o.p and o.z and #o.p >= 6) then return end
  local z = norm(o.z)
  if not z then return end
  local hs, rs = {}, {}
  for i, q in ipairs(o.p) do
    local d = sub(q, o.c)
    hs[i] = dot(d, z)
    rs[#rs + 1] = math.sqrt(math.max(dot(d, d) - hs[i] ^ 2, 0))
  end
  table.sort(rs)
  local lim = math.max(2, 0.35 * rs[(#rs + 1) // 2])
  local kept = {}
  for i, q in ipairs(o.p) do if math.abs(hs[i]) <= lim then kept[#kept + 1] = q end end
  if #kept < #o.p and #kept >= 5 then
    log(string.format("cap %s: %d of %d outline points over %.1f cm off the cut left out", what, #o.p - #kept, #o.p, lim))
    o.p = kept
  end
end
-- side 1: the body's cap (and what both need), 2: the piece's. A tick each: the two together were 21-27 ms, a hitch on
-- every cut (playtest)
function M.stage_caps(q, side)
  if q.smash and side == 2 then return end -- there is no severed piece to cap
  M.posed = q.posed
  if cfg().caps ~= false and side == 2 then
    q.caps[2], q.kinds[2] = cap(q.pawn, q.mesh, q.ol, q.rideL)
    M.riders(q, q.caps[2], q.rideL)
    mark("caps")
  elseif cfg().caps ~= false then
    -- (her flesh lids only: on 0.3.0's meat lids it left out up to half an arm's rim, 9 of 18 points on a shoulder,
    -- and the lids no longer reached the skin, playtest)
    if cfg().tachyLids then
      M.flat_outline(q.ob, "body side")
      M.flat_outline(q.ol, "piece side")
    end
    -- (a limb's caps get Tachy's core over their middle: M.tachy_lid maps them onto all of her disc)
    local core = cfg().boneStubs ~= false and PARTS[q.bone] and PARTS[q.bone].kind == "limb" or false
    local leg = core and (q.bone:find("Thigh") or q.bone:find("Calf") or q.bone:find("Foot")) and true or false
    -- (at the spine: where her bone will stand, kept clear of the torn relief, which buried it)
    if not core then
      if q.ob and q.ob.z then q.ob.boneAt = M.stub_centre(q.mesh, q.ob, norm(q.ob.z), q.parent or q.bone, true) end
      if q.ol and q.ol.z then q.ol.boneAt = M.stub_centre(q.mesh, q.ol, norm(q.ol.z), q.bone, true) end
    end
    -- (the cut bone's own direction, for the bone in the stump: out of each opening. As noted at the cut, where the
    -- openings are: read live a tick later, a falling arm had moved on)
    local part = PARTS[q.bone]
    local ps = q.posed and q.posed[addr(q.mesh)] or {}
    local function at(b) return b and (ps[b] and ps[b].t or bone_loc(q.mesh, b)) end
    local ja, jb = part and at(part.from or q.bone), part and at(part.to)
    local axis = ja and jb and norm(vec(jb.X - ja.X, jb.Y - ja.Y, jb.Z - ja.Z))
    for _, o in ipairs({ q.ob or false, q.ol or false }) do
      if o and o.z and axis then
        local oz = norm(o.z)
        o.axis = oz and (dot(axis, oz) < 0 and scale(axis, -1) or axis) or nil
      end
    end
    local waist = PARTS[q.bone] and PARTS[q.bone].kind == "torso" or false
    if q.ob then q.ob.waist = waist end
    if q.ol then q.ol.waist = waist end
    if q.ob then q.ob.core, q.ob.leg = core, leg end
    if q.ol then q.ol.core, q.ol.leg = core, leg end
    q.caps[1], q.kinds[1], q.seam = cap(q.pawn, q.mesh, q.ob, q.rideB)
    M.riders(q, q.caps[1], q.rideB)
    mark("caps")
  end
  M.posed = nil
end
-- side 1: the body's stub, 2: the piece's. A tick each: the two together were 31-55 ms, the worst hitch of a cut
-- (playtest)
function M.stage_stubs(q, side)
  if q.smash and side == 2 then return end
  M.posed = q.posed
  -- a bone in both stumps (the head's: the neck's spine); its look (spine or limb bone) goes by the cut's bones
  if cfg().caps ~= false then
    local spine = not (PARTS[q.bone] and PARTS[q.bone].kind == "limb")
    if side == 1 then
      q.stubs[#q.stubs + 1] = stub(q.pawn, q.mesh, q.ob, q.parent or q.bone, q.rideB, spine)
      M.riders(q, q.stubs[#q.stubs], q.rideB)
    else
      q.pieceStub = stub(q.pawn, q.mesh, q.ol, q.bone, q.rideL, spine)
      q.stubs[#q.stubs + 1] = q.pieceStub
      M.riders(q, q.pieceStub, q.rideL)
    end
    mark("stubs")
  end
  M.posed = nil
end

-- the rotation that points the bleed's emit axis (tune.gore.bleedAxis: the effect's cone axis, local Z) along out
local function emit_rot(out, axis)
  local km = load_obj("/Script/Engine.Default__KismetMathLibrary")
  local ax = axis or cfg().bleedAxis or "z"
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
function M.bleed_scale(o, size)
  local ex = o and o.e and tonumber(o.e.X)
  local ey = o and o.e and tonumber(o.e.Y)
  local sx = ex and math.max(0.75, math.min(ex / 3, 5)) or 1
  local sy = ey and math.max(0.75, math.min(ey / 3, 5)) or 1
  return vec(size * sx, size * sy, size)
end
function M.bleed_offset(o)
  if not (o and o.e and o.x and o.z) then return nil end
  local x, z = norm(o.x), norm(o.z)
  local y = x and z and norm(cross(z, x))
  local ex, ey = tonumber(o.e.X), tonumber(o.e.Y)
  if not (x and y and ex and ey) then return nil end
  local axis, radius = ex >= ey and x or y, math.max(ex, ey)
  return radius > 0 and scale(axis, math.min(radius * 0.65, 12)) or nil
end
-- The 0.5.5 blood-only effect follows each opening and is restarted on its original cadence.
-- Spawn and restart work is spread across frames; the Niagara system itself is unchanged.
local function bleed_from(q, cap_actor, o, bone, left, out)
  if not valid(q.mesh) or cfg().blood == false then return end
  local dir = out or (o and o.z)
  local rot = dir and emit_rot(dir)
    or try(function() local r = q.mesh:GetSocketRotation(FName(bone)); return { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end)
  local root = valid(cap_actor) and try(function() return cap_actor:K2_GetRootComponent() end)
  local at = valid(root) and try(function() local p = root:K2_GetComponentLocation(); return vec(p.X, p.Y, p.Z) end)
  local c
  if at then c = niagara(M.SMASH_BLOOD, root, nil, at, true, rot, nil, true)
  elseif o then c = niagara(M.SMASH_BLOOD, q.mesh, bone, o.c, true, rot, nil, true)
  else c = niagara(M.SMASH_BLOOD, q.mesh, bone, nil, true, rot, nil, true) end
  if not valid(c) then log("stump bleed: 0.5.5 blood-only effect unavailable"); return end
  local size = cfg().bleedSize or 0.6
  if size ~= 1 then try(function() c:SetWorldScale3D(vec(size, size, size)) end) end
  local every = math.max(1, math.floor((cfg().bleedPulse or 0.35) / TICK_S + 0.5))
  bleeds[#bleeds + 1] = { comp = c, left = left > 0 and left or nil, every = every,
    n = (#bleeds * 3) % every, ready = 0 }
end

-- a broken constraint takes its "don't collide" pair with it, and the two bodies overlap at the joint: the piece got
-- shoved out of the stump every frame (an upper body cut off a standing Eve spun wildly against her kinematic hips).
-- So after a cut her bodies stop colliding with each other (PhysicsBody = 5), until she recovers. Not while her arms
-- collide with her chest (ctx.arm_pairs, main.lua): the collision table keeps every other pair apart, a broken
-- joint's too, so only the arms and chest go on colliding; keep false (a split that leaves one of those bodies on the
-- other half, invisible on hers) turns that off too
local function no_self_collision(mesh, keep)
  if keep and ctx.arm_pairs then return end
  if ctx.table_filled and try(function() return ctx.table_filled(mesh) end) == true then return end
  -- (an enemy's corpse never gets up: nothing to put back)
  if not self_saved and not enemy.cur then
    self_saved = { mesh = mesh, resp = try(function() return mesh:GetCollisionResponseToChannel(5) end) }
  end
  try(function() mesh:SetCollisionResponseToChannel(5, 0) end)
end

-- a limb's root joint breaks; when the limb bone has no body of its own (CH_P_EVE_21 has no thigh bodies: the calves
-- and the thigh twist are jointed straight to Bip001-Spine) the joints from its top bodies to the body outside it
-- break instead, else the cut leg hung on and was never thrown (0 cm/s, playtest). skip: bones left to the caller
-- (the chains kept on the body). Returns those extra joints broken
function M.break_limb(comp, b, at, skip)
  try(function() comp:BreakConstraint(vec(0, 0, 0), at, FName(b)) end)
  local pa = ctx.physics_of and ctx.physics_of(comp)
  if not valid(pa) then return {} end
  local has = false
  try(function() pa.SkeletalBodySetups:ForEach(function(_, e) local bs = e:get(); if valid(bs) and bs.BoneName:ToString() == b then has = true end end) end)
  if has then return {} end
  local function inside(x) return x == b or try(function() return comp:BoneIsChildOf(FName(x), FName(b)) end) == true end
  local tops = {}
  try(function()
    pa.ConstraintSetup:ForEach(function(_, e)
      local t = e:get()
      if not valid(t) then return end
      local c = t.DefaultInstance.ConstraintBone1:ToString()
      local p = t.DefaultInstance.ConstraintBone2:ToString()
      if not (skip and skip[c]) and inside(c) and not inside(p) then tops[#tops + 1] = c end
    end)
  end)
  for _, c in ipairs(tops) do try(function() comp:BreakConstraint(vec(0, 0, 0), bone_loc(comp, c) or at, FName(c)) end) end
  return tops
end

-- stage 2, once those weights are in use: collapse the seam, let the limb go, show the caps, bleed
-- the chains a limb cut kept on the body (q.c.kept) let go of the limb and hang off the body next to it instead: a
-- ball joint where the chain starts, to the nearest body above the limb (the clavicle, the pelvis), swinging at most
-- CHAIN_SWING degrees
local CHAIN_SWING, CHAIN_TWIST = 40, 20
local function hang_chains(q)
  local kept = q.c and q.c.kept or {}
  if #kept == 0 then return "" end
  -- cut off on their own: their joint to the limb breaks and they fall where they are
  local det = q.c.detached or {}
  if #det > 0 then
    for _, c in ipairs(det) do
      local at = bone_loc(q.mesh, c)
      try(function() q.mesh:BreakConstraint(vec(0, 0, 0), at or q.c.at, FName(c)) end)
      try(function() q.mesh:SetAllBodiesBelowSimulatePhysics(FName(c), true, true) end)
      -- (a piece of its own: her ragdoll's cape hang leaves it be)
      if ctx.on_broken then try(function() ctx.on_broken(q.mesh, c) end) end
    end
    local free = {}
    for _, c in ipairs(kept) do
      local d = false
      for _, x in ipairs(det) do if x == c then d = true end end
      if not d then free[#free + 1] = c end
    end
    if #free == 0 then return table.concat(det, ",") .. " cut off on its own" end
    kept = free
  end
  local cls = try(function() return StaticFindObject("/Script/Engine.PhysicsConstraintComponent") end)
  if not valid(cls) then return "chains: no PhysicsConstraintComponent class" end
  local pa = ctx.physics_of(q.mesh)
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
        -- (hung here already: her ragdoll's cape hang leaves it be)
        if ctx.on_broken then try(function() ctx.on_broken(q.mesh, c) end) end
      end
    end
  end
  return string.format("%s kept on %s", #done > 0 and table.concat(done, ",") or "no chain", anchor)
end

-- the joints holding a cut piece on while it opens (gradual open); in hung too, so a reset takes them
function M.hold_open(q, roots, done)
  local g = cfg()
  local secs = g.openTime or 0
  if secs <= 0 then return "" end
  local cls = try(function() return StaticFindObject("/Script/Engine.PhysicsConstraintComponent") end)
  if not valid(cls) then return "" end
  local has = {}
  local pa = ctx.physics_of and ctx.physics_of(q.mesh)
  if valid(pa) then
    try(function() pa.SkeletalBodySetups:ForEach(function(_, e) local bs = e:get(); if valid(bs) then has[bs.BoneName:ToString()] = true end end) end)
  end
  local anchor = parent_bone(q.mesh, q.bone)
  while anchor and not has[anchor] do anchor = parent_bone(q.mesh, anchor) end
  if not anchor then return "" end
  local gap, swing = g.openGap or 8, g.openSwing or 35
  local pcs = {}
  local function limits(pc, f)
    local lin = math.max(0.5, gap * f)
    try(function() pc:SetLinearXLimit(1, lin) end)
    try(function() pc:SetLinearYLimit(1, lin) end)
    try(function() pc:SetLinearZLimit(1, lin) end)
    try(function() pc:SetAngularSwing1Limit(1, math.max(2, swing * f)) end)
    try(function() pc:SetAngularSwing2Limit(1, math.max(2, swing * f)) end)
    try(function() pc:SetAngularTwistLimit(1, math.max(2, swing * f * 0.5)) end)
  end
  for _, r in ipairs(roots) do
    local at = bone_loc(q.mesh, r)
    local pc = at and try(function()
      return q.pawn:AddComponentByClass(cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }, false)
    end)
    if valid(pc) then
      hung[#hung + 1] = pc
      try(function() pc:K2_SetWorldLocation(at, false, {}, true) end)
      limits(pc, 0)
      if try(function() pc:SetConstrainedComponents(q.mesh, FName(anchor), q.mesh, FName(r)); return true end) then
        pcs[#pcs + 1] = pc
      else
        try(function() pc:K2_DestroyComponent(pc) end)
      end
    end
  end
  if #pcs == 0 then return "" end
  -- a nudge out along the cut, so it starts to come apart and doesn't only sag
  local push = g.openPush or 40
  if push > 0 and q.c.n then
    try(function() q.mesh:AddImpulseToAllBodiesBelow(scale(q.c.n, push), FName(q.bone), true, true) end)
  end
  local n = math.max(1, math.floor(secs / TICK_S + 0.5))
  for k = 1, n do
    later[#later + 1] = { n = k, fn = function()
      if k < n then
        for _, pc in ipairs(pcs) do if valid(pc) then limits(pc, k / n) end end
        return
      end
      for _, pc in ipairs(pcs) do
        if valid(pc) then try(function() pc:BreakConstraint() end); try(function() pc:K2_DestroyComponent(pc) end) end
      end
      if valid(q.mesh) then done() end
      log(string.format("%s let go after opening %.2f s", q.bone, secs))
    end }
  end
  return string.format("opening over %.2f s on %s", secs, anchor)
end

local function stage_open(q)
  local g = cfg()
  local k = command("k")
  mark("collapse seam")
  -- carried over a level change (main.lua's hm.carry_tick): the part came off her in the old level and lies there. On
  -- the new Eve only her stump: the piece's bones hidden (as a smash's), no piece falling, no sound, no blood
  if q.quiet then
    local nb, nv = M.smashed.hide(q)
    for i, a in pairs(q.caps) do if valid(a) and i ~= 2 then try(function() a:SetActorHiddenInGame(false) end) end end
    for _, a in pairs(q.stubs or {}) do
      if valid(a) and a ~= q.pieceStub then try(function() a:SetActorHiddenInGame(false) end) end
    end
    log(string.format("%s off (%s): %s, the piece hidden (%d bone(s), %d rider(s)), no sound, no blood", q.bone, q.why,
      k, nb, nv))
    return
  end
  -- on a living Eve the mesh has no physics collision with the world, so the piece would fall through the floor:
  -- give it the death ragdoll's profile until she recovers (her own bodies stay kinematic)
  local world = ""
  local still = try(function() return q.mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end) ~= true
  if still and enemy.cur then
    -- an enemy's corpse not simulating (yet): the ragdoll's profile, nothing to put back
    try(function() q.mesh:SetCollisionProfileName(FName("Ragdoll"), true) end)
    try(function() q.mesh:SetCollisionResponseToChannel(2, 0) end)
    world = ", world collision on"
  elseif still and not collision_saved then
    local c = { mesh = q.mesh, resp = {} }
    c.obj = try(function() return q.mesh:GetCollisionObjectType() end)
    c.enabled = try(function() return q.mesh:GetCollisionEnabled() end)
    c.profile = try(function() return q.mesh:GetCollisionProfileName():ToString() end)
    for ch = 0, 31 do c.resp[ch] = try(function() return q.mesh:GetCollisionResponseToChannel(ch) end) end
    try(function() q.mesh:SetCollisionProfileName(FName("Ragdoll"), true) end)
    -- and none with her own capsule, which blocks physics bodies: the upper body of a waist cut fell inside it and
    -- jiggled on the floor as the capsule shoved it every frame (sixteenth playtest; arms and legs flew clear of it)
    try(function() q.mesh:SetCollisionResponseToChannel(2, 0) end) -- ECC_Pawn
    local cap = try(function() return q.pawn.CapsuleComponent end)
    if valid(cap) then
      c.cap, c.capResp = cap, try(function() return cap:GetCollisionResponseToChannel(5) end) -- ECC_PhysicsBody
      try(function() cap:SetCollisionResponseToChannel(5, 0) end)
    end
    -- and none with her hair (SBHair blocks PhysicsBody, her mesh's type now): it caught on her own bodies and the
    -- arm on the floor and hung there in the air till her death turned its collision off (playtest)
    local hair = c.obj ~= 5 and try(function() return q.pawn.SBHair end)
    if valid(hair) then
      c.hair, c.hairResp = hair, try(function() return hair:GetCollisionResponseToChannel(5) end)
      try(function() hair:SetCollisionResponseToChannel(5, 0) end)
    end
    collision_saved = c
    world = string.format(", world collision on (was %s, enabled %s)%s%s", tostring(c.profile), tostring(c.enabled),
      c.cap and string.format(", her capsule ignores it (was %s)", tostring(c.capResp)) or "",
      c.hair and string.format(", her hair ignores it (was %s)", tostring(c.hairResp)) or "")
    -- the piece weighs what a body part weighs, not the outfit's 100 kg chest and 80 kg cape links (active.lua does
    -- this for ragdolls)
    if ctx.on_piece then
      local m = try(function() return ctx.on_piece(q.pawn, q.mesh, q.bone) end)
      if m then world = world .. ", " .. m end
    end
  end
  mark("collision")
  no_self_collision(q.mesh, true)
  mark("self collision")
  -- Her legs keep the animated pose, but the detached upper body can no longer carry the animated weapon.
  if q.torsoLegs and q.bone == "Bip001-Spine1" and ctx.rag and ctx.rag.smash_drop then
    try(function() ctx.rag.smash_drop(q.pawn, q.mesh, q.bone, "waist cut") end)
  end
  -- off it goes: the constraint at the limb's root breaks (its bodies start simulating if she was alive)
  local skip = {}
  for _, c in ipairs(q.c.kept or {}) do skip[c] = true end
  local tops = M.break_limb(q.mesh, q.bone, q.c.at, skip)
  q.entry.opened, q.entry.kept = true, q.c.kept
  if not enemy.cur and PARTS[q.bone] and (PARTS[q.bone].kind == "head"
    or q.smash and PARTS[q.bone].kind == "torso") then vox.cut() end
  local broke = true
  if #tops > 0 then world = world .. ", no body on " .. q.bone .. ": broke " .. table.concat(tops, ",") end
  mark("break")
  -- the piece collides with the rest of her from here on (main.lua, physfix.piece_collision), in her ragdoll only:
  -- standing, the rest of her is kinematic and the animation drives it, and her thigh, moving with the idle, threw
  -- her hand that hung beside it off at 2500 cm/s, the upper body with it (playtest)
  if not q.smash and ctx.piece_collision and not enemy.cur and not still then try(function() ctx.piece_collision(q.mesh, { q.bone }) end) end
  if ctx.on_cut and not enemy.cur then
    try(function() ctx.on_cut(q.mesh, q.bone) end)
    for _, c in ipairs(tops) do try(function() ctx.on_cut(q.mesh, c) end) end
  end
  mark("on_cut")
  local nh = hang_chains(q)
  mark("chains")
  if nh ~= "" then world = world .. ", " .. nh end
  -- the cut opens over openTime s (gradual open): the piece hangs on by a joint at its root to the body above it, whose
  -- limits widen every tick from openGap's first step to openGap cm and openSwing degrees, so it sags and slides along
  -- the cut, the caps showing through the gap, before it lets go and flies. Else it goes at once
  local function fling()
    -- A smashed piece is hidden, not thrown: steering its invisible bodies into the surviving ragdoll can still
    -- feed the solver impulses. Only the spawned meat flies; no gradual-opening joint or float/throw callbacks.
    if q.smash then return end
    -- a killing blow sends the piece flying the way it hit her (q.fly), else it drops off away from the body; every
    -- body of the piece gets the speed (the root's alone dragged the rest, a small push)
    local throw = q.fly and (g.deathThrow or 650) or (g.throw or 250)
    -- a hit after her death: harder (deathThrow, a killing blow's, was hardly a push on her lying body, playtest)
    if q.why == "after" then throw = g.afterThrow or 500 end
    -- a leg is the big piece: dropping off it gets more (legThrow), or it dropped at her feet
    local leg = q.bone:find("Thigh") or q.bone:find("Calf")
    if leg and not q.fly then throw = throw * (g.legThrow or 1.4) end
    if throw > 0 then
      local v = q.fly and norm(add(add(q.fly, scale(q.c.n, 0.35)), vec((math.random() - 0.5) * 0.3, (math.random() - 0.5) * 0.3, 0.45)))
        or norm(add(q.c.n, vec((math.random() - 0.5) * 0.6, (math.random() - 0.5) * 0.6, 0.4)))
      v = v or q.c.n
      if leg then v = norm(add(v, vec(0, 0, g.legLift or 0.35))) or v end
      -- no steeper than throwUp (the sine of its climb): pieces went up at 45 degrees and looped over her (playtest)
      local up = g.throwUp or 0.25
      local hz = math.sqrt(v.X * v.X + v.Y * v.Y)
      if v.Z > up and hz > 1e-3 then
        local k = math.sqrt(1 - up * up) / hz
        v = vec(v.X * k, v.Y * k, up)
      end
      try(function() q.mesh:AddImpulseToAllBodiesBelow(scale(v, throw), FName(q.bone), true, true) end)
      if q.fly then log(string.format("piece flies with the blow: %s at %.0f cm/s", v3(v), throw)) end
      -- the throw went in the tick the piece's bodies were set simulating (a leg cut switches her fall to the ragdoll
      -- that same tick) and was mostly lost: cut-off legs dropped at her feet as if too heavy (twentieth playtest). For
      -- the next few ticks every main body of the piece is kept at least that fast along the throw
      local chain = PIECE_CHAIN[q.bone:gsub("^Bip001%-%a%-", "")] or {}
      -- the head and the torso have no side: they kept none of it, the head fell at 123 of 250 (thirty-fifth playtest)
      local side = q.bone:match("^Bip001%-(%a)%-")
      local mesh = q.mesh
      for k = 1, (g.throwTicks or 3) do
        later[#later + 1] = { n = k, fn = function()
          if not valid(mesh) then return end
          local slow = 0
          for _, part in ipairs(chain) do
            local b = FName(side and ("Bip001-" .. side .. "-" .. part) or ("Bip001-" .. part))
            local cur = try(function() local x = mesh:GetPhysicsLinearVelocity(b); return vec(x.X, x.Y, x.Z) end)
            local along = cur and dot(cur, v)
            if along and along < throw then
              local nv = add(cur, scale(v, throw - along))
              if try(function() mesh:SetPhysicsLinearVelocity(nv, false, b); return true end) then slow = slow + 1 end
            end
          end
          if k == (g.throwTicks or 3) then
            local root = try(function() local x = mesh:GetPhysicsLinearVelocity(FName(q.bone)); return vec(x.X, x.Y, x.Z) end)
            log(string.format("piece %s: %.0f cm/s along the throw after %d ticks (%d bodies sped up on the last)", q.bone,
              root and dot(root, v) or -1, k, slow))
          end
        end }
      end
    end
    -- a cut-off arm or leg falls at pieceGravity of gravity for pieceFloat s: at full gravity it dropped like a stone
    -- (its bodies' damping is the data mod's 0.2). Topped up every tick as a speed change on all its bodies
    local pg = g.pieceGravity or 1
    if pg < 1 and q.bone ~= "Bip001-Head" and q.bone ~= "Bip001-Spine1" then
      local mesh, root, t0 = q.mesh, FName(q.bone), os.clock()
      local last = t0
      local function float()
        if not valid(mesh) then return end
        local now = os.clock()
        local up = 980 * (1 - pg) * math.min(now - last, 0.1)
        last = now
        try(function() mesh:AddImpulseToAllBodiesBelow(vec(0, 0, up), root, true, true) end)
        -- every third tick (the time since the last one's worth): every tick, it showed as 11 ms of each tick for its
        -- 3 s (twenty-ninth playtest)
        if now - t0 < (g.pieceFloat or 3) then later[#later + 1] = { n = 3, fn = float } end
      end
      later[#later + 1] = { n = 1, fn = float }
    end
  end
  local held = not q.smash and M.hold_open(q, #tops > 0 and tops or { q.bone }, fling) or ""
  if held ~= "" then world = world .. ", " .. held else fling() end
  mark("throw")
  -- (a smash's piece is gone: its cap and stub stay hidden, it neither drips nor bleeds)
  for i, a in pairs(q.caps) do if valid(a) and not q.fullSmash and not (q.smash and i == 2) then try(function() a:SetActorHiddenInGame(false) end) end end
  for _, a in pairs(q.stubs or {}) do
    if valid(a) and not q.fullSmash and not (q.smash and a == q.pieceStub) then try(function() a:SetActorHiddenInGame(false) end) end
  end
  mark("show caps")
  if q.smash then
    q.entry.smashed = true
    q.entry.fullSmash = q.fullSmash
    local ok, err = pcall(M.smashed.out, q)
    if not ok then log("smash failed: " .. tostring(err)) end
    mark("smash")
  end
  if g.blood ~= false then
    if not enemy.cur then M.bodyBlood.up(q.pawn) end
    if q.parent and not q.fullSmash then track_opening(q, q.caps[1], q.ob, q.mesh, q.rideB or q.parent) end
    if not q.smash then track_opening(q, q.caps[2], q.ol, q.mesh, q.rideL or q.bone) end
  end
  mark("blood")
  -- the splat and the sound the next tick, the bleeds the one after: each its own frame (the opening's was 25-43 ms
  -- with them, a visible stutter at every cut, playtest)
  local at = q.c.at
  q.open_t = os.clock()
  local open_t, open_bone, open_why = q.open_t, q.bone, q.why
  later[#later + 1] = { n = 0, label = "cut sound", fn = function()
    if not valid(q.pawn) then return end
    local dt = (os.clock() - open_t) * 1000
    log(string.format("cut sound %s (%s): attempting playback %.0f ms after opening", open_bone, open_why, dt))
    if q.smash then sfx("smash", q.pawn, at, true); return end
    sfx((open_why == "after" or open_bone == "Bip001-Head" or open_bone == "Bip001-Spine1" or open_bone:find("Thigh") or open_bone:find("Calf"))
      and "big" or "cut", q.pawn, at, true)
  end }
  if g.blood ~= false and not q.fullSmash then
    later[#later + 1] = { n = 2, label = "cut splat", fn = function()
      if not valid(q.pawn) then return end
      if g.sliceFx == true then niagara(FX.slice, q.pawn, nil, at, false) end
      M.splat(q.pawn, at)
    end }
  end
  if g.blood ~= false then
    -- bleed from both openings, for a while: from the cap, which rides on that side's bone, else from the
    -- opening's centre on the bone; oriented like that bone (the effect was made for bone attachment). Out of the
    -- opening's frame: it was 10-15 ms of it (playtest 41).
    local duration = g.bleedTime or 2.5
    local left = math.floor(duration / TICK_S + 0.5)
    if q.parent and not q.fullSmash then
      later[#later + 1] = { n = 3, label = "body stump bleed", fn = function()
        if valid(q.mesh) then bleed_from(q, q.caps[1], q.ob, q.rideB or q.parent, left, nil) end
      end }
    end
    if not q.smash then
      later[#later + 1] = { n = 4, label = "piece stump bleed", fn = function()
        if valid(q.mesh) then bleed_from(q, q.caps[2], q.ol, q.rideL or q.bone, left, nil) end
      end }
    end
  end
  mark("sound, bleed")
  log(string.format("%s off (%s): %s, constraint broken=%s, caps %s / %s%s", q.bone, q.why, k, tostring(broke == true),
    tostring(q.kinds[1]), tostring(q.kinds[2]), world))
  -- This inventory only feeds a diagnostic log. Enumerating every attachment on the cut's opening frame can
  -- compound the physics and cap work; keep it available when verbose logging or stretch probes are requested.
  if ctx.tune.verboseLog == true or g.probes == true then M.attached_report(q) end
  -- (diagnostics: the stretch probe skins every vertex on the CPU, a stutter of its own; tune.gore.probes)
  if PARTS[q.bone] and PARTS[q.bone].kind ~= "head" and cfg().probes then
    local anchor = parent_bone(q.mesh, q.bone)
    local pa = ctx.physics_of(q.mesh)
    local has = {}
    if valid(pa) then
      try(function() pa.SkeletalBodySetups:ForEach(function(_, e) local bs = e:get(); if valid(bs) then has[bs.BoneName:ToString()] = true end end) end)
    end
    while anchor and not has[anchor] do anchor = parent_bone(q.mesh, anchor) end
    limb_watch = { mesh = q.mesh, bone = q.bone, kept = q.c.kept or {}, anchor = anchor, n = 0 }
  elseif PARTS[q.bone] and PARTS[q.bone].kind == "head" and cfg().probes and valid(q.c.face) then
    -- a beheading's neck is on her face mesh (the body ends under it): where the face stretches
    limb_watch = { mesh = q.c.face, bone = q.bone .. " (face)", kept = {}, n = 0 }
  end
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
  -- (no post-process AnimBP of its mesh's made on it: it never ticks, so it never moved anything, and Play As's Scarlet
  -- (the NIKKE outfit's KawaiiPhysics AnimBP on her body's mesh) froze the game as her cut-off head went onto it in
  -- photo mode, playtest. Off before the mesh goes on, so it isn't made at all)
  if not try(function() c:SetDisablePostProcessBlueprint(true); return true end) then
    try(function() c.bDisablePostProcessBlueprint = true end)
  end
  try(function() c:SetSkeletalMesh(src.SkeletalMesh, true) end)
  local nm = try(function() return src:GetNumMaterials() end) or 0
  local lods = math.max(1, try(function() return src:GetNumLODs() end) or 1)
  for i = 0, nm - 1 do
    local m = try(function() return src:GetMaterial(i) end)
    if m then try(function() c:SetMaterial(i, m) end) end
    -- Play As hides Scarlet's embedded hair by material section. SetSkeletalMesh and SetMaterial do not copy that
    -- visibility state, so a new half (or a photo/regrow copy) must inherit it explicitly.
    for lod = 0, lods - 1 do
      if try(function() return src:IsMaterialSectionShown(i, lod) end) == false then
        try(function() c:ShowMaterialSection(i, i, false, lod) end)
        if try(function() return c:IsMaterialSectionShown(i, lod) end) ~= false then
          try(function() c:ShowMaterialSection(i, false, lod) end)
        end
      end
    end
  end
  place_like(c, src)
  force_lod(c)
  try(function() c:SetComponentTickEnabled(false) end)
  return c
end

-- what rides her mesh and face at a cut, by class (the game's hit effects, other mods' copies and effects, ours): to
-- tell what stretched with a cut-off head with Ultra Violence on (playtest). Once per cut, on the cut's "off" line
function M.attached_report(q)
  local out = {}
  for _, m in ipairs({ q.mesh, q.c and q.c.face }) do
    if valid(m) then
      local by = {}
      try(function() m.AttachChildren:ForEach(function(_, e)
        local c = e:get()
        if not valid(c) then return end
        local cls = try(function() return c:GetClass():GetFName():ToString() end) or "?"
        if cls:find("Cap") or cls == "StaticMeshComponent" then cls = "StaticMesh" end
        local what = cls
        if cls:find("Niagara") then
          local a = try(function() return c.Asset end)
          what = what .. ":" .. (valid(a) and (try(function() return a:GetFName():ToString() end) or "?") or "?")
        elseif cls:find("SkeletalMesh") then
          local mp = try(function() return c.MasterPoseComponent:Get() end)
          local lm = try(function() local x = m.MasterPoseComponent:Get(); return x and addr(x) end)
          what = what .. ":" .. name_of(c) .. (mp and addr(mp) == addr(m) and " (on its pose)" or mp and lm and addr(mp) == lm and " (on its master's pose)" or "")
        end
        local sock = try(function() return c.AttachSocketName:ToString() end)
        if sock and sock ~= "None" then what = what .. "@" .. sock end
        if try(function() return c:IsVisible() end) == false then what = what .. " hidden" end
        by[what] = (by[what] or 0) + 1
      end) end)
      local l = {}
      for w, n in pairs(by) do l[#l + 1] = n > 1 and string.format("%s x%d", w, n) or w end
      table.sort(l)
      out[#out + 1] = name_of(m) .. ": " .. (#l > 0 and table.concat(l, ", ") or "none")
    end
  end
  log(string.format("%s off: attached %s", q.bone, table.concat(out, "; ")))
end

-- Other mods' mesh copies follow cut weights and must release them during recovery.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore_copies.lua")(M, {
  addr = addr, mesh_name = mesh_name, name_of = name_of, command = command, clone_of = clone_of, log = log,
  clones = function() return clones end, cuts = function() return cuts end, guards = function() return try, valid end,
})

local function side_cut(comp, bone, at, n, gone)
  local index = try(function() return comp:GetBoneIndex(FName(bone)) end)
  if not index or index < 0 then return "err no bone " .. bone end
  send_nosink(comp, nil, true, not enemy.cur and M.side_drivers(comp, gone) or nil)
  -- Ignore hidden material slots when judging a split; Play As keeps its separate hair copy visible.
  local hidden = 0
  local nm = math.min(64, try(function() return comp:GetNumMaterials() end) or 0)
  for i = 0, nm - 1 do
    if try(function() return comp:IsMaterialSectionShown(i, 0) end) == false then hidden = hidden | (1 << i) end
  end
  return command(string.format("c%x,0,%x,%x,0,0,ffffffff,%x", comp:GetAddress(), index, MODE.side, hidden), at, n)
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
  for _, b in ipairs(SPLIT_LIMBS) do
    local l = bone_loc(comp, b)
    -- an arm cut off before (an arm raised to block, then the split, M.blow) by its clavicle: the arm has flown
    if l and already_cut(comp, b) then l = bone_loc(comp, parent_bone(comp, b) or b) or l end
    if l then
      if dot(sub(l, at), n) < 0 then gone[#gone + 1] = b else keep[#keep + 1] = b end
    end
  end
  return gone, keep
end

-- a waist plane (normal towards the head) with both upper arms over it and both thighs under it, by 2 cm
function M.waist_sides(comp, at, n)
  for _, b in ipairs(SPLIT_LIMBS) do
    local l = bone_loc(comp, b)
    if not l then return false end
    local h = dot(sub(l, at), n)
    if (b:find("Thigh") and h > -2) or (b:find("Arm") and h < 2) then return false end
  end
  return true
end

-- a split's accessory chains: the top of each chain of physics bodies (not Bip001) hanging off the torso or neck, not
-- off a limb (those go with it) or the head (kept whole by the half that keeps it), on the side of the plane where
-- its bodies lie on average. Each half keeps the chains on its side whole and drops the others whole: halved, the
-- neck chain's swinging half stretched to the flattened sheet across the opening (fifteenth playtest)
-- A chain hanging off a Dm- driver of an arm's or leg's side goes with the half that keeps that limb (back: the limbs
-- behind the plane), whichever side it lies: the driver follows the limb. A diagonal over her shoulder left the
-- shoulder's gear (under Dm-R-Trape) on her half and the arm on the copy's: it flew off with the arm (harness)
function M.limb_keys(list)
  local t = {}
  for _, b in ipairs(list or {}) do
    local sd, part = b:match("^Bip001%-([LR])%-(%a+)")
    if sd then t[sd .. ((part == "Thigh" or part == "Calf") and "leg" or "arm")] = true end
  end
  return t
end
local function split_chains(comp, at, n, back_limbs)
  local pa = ctx.physics_of(comp)
  if not valid(pa) then return {}, {} end
  local list, has = {}, {}
  try(function() pa.SkeletalBodySetups:ForEach(function(_, e) local bs = e:get(); if valid(bs) then local nm = bs.BoneName:ToString(); list[#list + 1] = nm; has[nm] = true end end) end)
  local function under(x, y) return try(function() return comp:BoneIsChildOf(FName(x), FName(y)) end) == true end
  local front, back = {}, {}
  for _, c in ipairs(list) do
    local p = parent_bone(comp, c)
    -- a top: its parent has no body of its own outside Bip001
    local top = not c:find("^Bip001")
    local q, drv = p, nil
    while top and q and not q:find("^Bip001") do
      if has[q] then top = false end
      if q:sub(1, 3) == "Dm-" or q:sub(1, 3) == "Dm_" then drv = q end
      q = parent_bone(comp, q)
    end
    local anchored = top and q and q ~= "Bip001-Head"
    if anchored then for _, l in ipairs(SPLIT_LIMBS) do if q == l or under(q, l) then anchored = false end end end
    if anchored then
      local sum, k = 0, 0
      for _, d in ipairs(list) do
        if d == c or under(d, c) then
          local l = bone_loc(comp, d)
          if l then sum = sum + dot(sub(l, at), n); k = k + 1 end
        end
      end
      local dk = drv and M.driver_limb(drv)
      if dk and back_limbs then sum = M.limb_keys(back_limbs)[dk] and -1 or 1 end
      if k >= 2 then
        if sum >= 0 then front[#front + 1] = c else back[#back + 1] = c end
      end
    end
  end
  return front, back
end

-- tell the DLL a half's limbs for its next split cut, the bones its lid pieces ride (the flattened skin behind the
-- lid bands by them) and the accessory chains it drops: "g<comp>,<gone roots>,0,<kept roots>,0,<ride bones>,0,<drop>"
-- spine, upper: where the split breaks her spine and whether this is the half above it (settle_half lets the other
-- side of the break go, so the DLL takes this half's skin off it)
local function send_limbs(comp, gone, keep, drop, ride, spine, upper)
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
  add_bones(ride or SPLIT_RIDE)
  local si = spine and try(function() return comp:GetBoneIndex(FName(spine)) end)
  if (drop and #drop > 0) or (si and si > 0) then
    f[#f + 1] = "0"
    add_bones(drop or {})
  end
  if si and si > 0 then
    f[#f + 1] = "0"
    f[#f + 1] = string.format("%x", si)
    f[#f + 1] = upper and "1" or "2"
  end
  return command(string.format("g%x,%s", comp:GetAddress(), table.concat(f, ",")))
end

-- a split's lid: the opening's outline (hips, waist, ribs, shoulder, neck: concave) flat on the plane, ear-clipped,
-- with a skirt round it reaching grow cm past the skin, pushed push cm out of the half, both faces. One rigid lid would stick out of a
-- bending ragdoll, so it comes in pieces, each triangle on the spine bone nearest to it, each piece riding that bone
local function flat_lid(o, comp, grow, push, ride)
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
  -- pieces by the nearest spine bone, or (splitLidSkin) one piece that bends with the spine (skin_lid)
  local one = cfg().splitLidSkin ~= false
  local bones = {}
  for _, b in ipairs(ride) do
    local l = bone_loc(comp, b)
    if l then bones[#bones + 1] = { name = b, at = vec(l.X, l.Y, l.Z) } end
  end
  if #bones == 0 then return nil end
  local points = {}
  for i = 1, #gx do points[i] = add(add(c, add(scale(u, gx[i]), scale(w, gy[i]))), scale(z, push)) end
  local function world(i) return points[i] end
  local pieces, order, single = {}, {}, nil
  for _, t in ipairs(tris) do
    local m = one and c or scale(add(add(world(t[1]), world(t[2])), world(t[3])), 1 / 3)
    local best, bd = single, nil
    if not best then
      for _, b in ipairs(bones) do
        local d = sub(m, b.at)
        d = dot(d, d)
        if not bd or d < bd then best, bd = b, d end
      end
      if one then single = best end
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
    pc.wv, pc.wn = {}, {}
    for side = 1, 2 do
      local nz = side == 1 and z or scale(z, -1)
      local at = {}
      for _, i in ipairs(list) do
        verts[#verts + 1] = sub(world(i), mid)
        pc.wv[#verts], pc.wn[#verts] = world(i), nz
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
    pc.skin = one
  end
  return order, core
end

-- quaternions as UE4SS hands them ({ X, Y, Z, W }): v turned by q, and by q's inverse
local function qrot(q, v)
  local tx, ty, tz = 2 * (q.Y * v.Z - q.Z * v.Y), 2 * (q.Z * v.X - q.X * v.Z), 2 * (q.X * v.Y - q.Y * v.X)
  return vec(v.X + q.W * tx + q.Y * tz - q.Z * ty, v.Y + q.W * ty + q.Z * tx - q.X * tz, v.Z + q.W * tz + q.X * ty - q.Y * tx)
end
local function qinv(q) return { X = -q.X, Y = -q.Y, Z = -q.Z, W = q.W } end
-- a bone's up (its own Z) as noted at the cut (M.snap), nil if it wasn't
function M.posed_up(comp, b)
  local s = M.posed and M.posed[addr(comp)]
  local t = s and s[b]
  return t and qrot(t.q, vec(0, 0, 1))
end
local function bone_tm(comp, b)
  return try(function()
    local x = comp:GetSocketTransform(FName(b), 0) -- RTS_World
    return { t = vec(x.Translation.X, x.Translation.Y, x.Translation.Z), q = { X = x.Rotation.X, Y = x.Rotation.Y, Z = x.Rotation.Z, W = x.Rotation.W } }
  end)
end

-- the caps and stubs are placed a tick after the cut (stage_caps), from where the openings were at the cut: in a fall
-- her arm had moved on by then and the stub's cap was attached far off its end (thirty-second playtest). So the
-- bones they ride are noted at the cut (snap: { { comp, bones }, ... }) and each one is moved along with its bone
-- since then (repose, while M.posed holds that note)
function M.snap(list)
  local s = {}
  for _, e in ipairs(list) do
    local a = addr(e[1])
    if a then
      s[a] = s[a] or {}
      for _, b in ipairs(e[2]) do s[a][b] = s[a][b] or bone_tm(e[1], b) end
    end
  end
  return s
end
function M.repose(a, comp, bone)
  local s = M.posed and M.posed[addr(comp)]
  local t0 = s and s[bone]
  local t1 = t0 and bone_tm(comp, bone)
  if not (t1 and valid(a)) then return end
  local function move(v) return qrot(t1.q, qrot(qinv(t0.q), v)) end
  local fwd = try(function() local v = a:GetActorForwardVector(); return vec(v.X, v.Y, v.Z) end)
  local up = try(function() local v = a:GetActorUpVector(); return vec(v.X, v.Y, v.Z) end)
  local l = try(function() local v = a:K2_GetActorLocation(); return vec(v.X, v.Y, v.Z) end)
  local km = load_obj("/Script/Engine.Default__KismetMathLibrary")
  if not (fwd and up and l and km) then return end
  local rot = try(function() return km:MakeRotFromXZ(move(fwd), move(up)) end)
  if rot then try(function() a:K2_SetActorRotation(rot, false) end) end
  local at = add(move(sub(l, t0.t)), t1.t)
  try(function() a:K2_SetActorLocation(at, false, {}, false) end)
end

-- a split lid in one piece that bends with her spine, as the flattened skin behind it does: each vertex rides the
-- two spine bones it lies between (SPLIT_RIDE, head to pelvis), blended by where along them it is, and lids_tick
-- moves the vertices every tick. Riding a bone a piece, the lid cracked into shards as she bent (eighteenth playtest)
local lid_ms = { n = 0, sum = 0, top = 0 }
local function skin_lid(comp, actor, pmc, pc, ride)
  local chain = {}
  -- (the bones as noted at the cut, M.posed: the lid's points are where the opening was then)
  local posed = M.posed and M.posed[addr(comp)] or {}
  for _, b in ipairs(ride) do
    local tm = posed[b] or bone_tm(comp, b)
    if tm then chain[#chain + 1] = { name = b, tm = tm, inv = qinv(tm.q) } end
  end
  if #chain == 0 or not pc.wv then return false end
  -- Cache the spine segments once. Both faces share the same weights and positions, so only the front
  -- needs a nearest-segment search; the back reuses it with reversed normals.
  local segments = {}
  for j = 1, math.max(#chain - 1, 1) do
    local a, b = chain[j].tm.t, chain[math.min(j + 1, #chain)].tm.t
    local x, y, z = b.X - a.X, b.Y - a.Y, b.Z - a.Z
    segments[j] = { a = a, x = x, y = y, z = z, l2 = x*x + y*y + z*z }
  end
  local v, half = {}, #pc.wv / 2
  for k = 1, half do
    local p = pc.wv[k]
    local ja, jb, t, bd = 1, 1, 0, nil
    for j, seg in ipairs(segments) do
      local x, y, z = p.X - seg.a.X, p.Y - seg.a.Y, p.Z - seg.a.Z
      local u = seg.l2 > 1e-6 and math.min(math.max((x*seg.x + y*seg.y + z*seg.z) / seg.l2, 0), 1) or 0
      x, y, z = x - seg.x*u, y - seg.y*u, z - seg.z*u
      local d = x*x + y*y + z*z
      if not bd or d < bd then ja, jb, t, bd = j, math.min(j + 1, #chain), u, d end
    end
    local qa, qb = chain[ja].inv, chain[jb].inv
    local w = { a = ja, b = jb, t = t, la = qrot(qa, sub(p, chain[ja].tm.t)), lb = qrot(qb, sub(p, chain[jb].tm.t)),
      na = qrot(qa, pc.wn[k]), nb = qrot(qb, pc.wn[k]) }
    v[k] = w
    v[k + half] = w
  end
  local names = {}
  for j, c2 in ipairs(chain) do names[j] = c2.name end
  skinned[#skinned + 1] = { actor = actor, pmc = pmc, comp = comp, bones = names, v = v, n = 0, half = #pc.wv / 2 }
  lid_ms.idle = 0
  return true
end

local lids_step
local function lids_tick()
  if #skinned == 0 then
    if lid_ms.n > 0 then
      log(string.format("split lids followed her for %d ticks%s: %.1f ms a tick, %.1f at most", lid_ms.n,
        lid_ms.skip and string.format(" (%d skipped still)", lid_ms.skip) or "", lid_ms.sum / lid_ms.n, lid_ms.top))
      lid_ms = { n = 0, sum = 0, top = 0 }
    end
    return
  end
  -- (idle state kept on lid_ms, which is reset above: this chunk is at Lua's 200-local limit)
  lid_ms.tick = (lid_ms.tick or 0) + 1
  -- A settled split keeps every lid's bones and actor transform read each tick for 4-6 ms (playtest), hundreds of
  -- ticks past anything moving. After 30 still ticks in a row, check every fourth tick instead, like settle's
  -- asleep cadence; any motion goes back to every tick at once, and the lids' follow window still counts in ticks.
  if (lid_ms.idle or 0) >= 30 and lid_ms.tick % 4 ~= 0 then
    for _, s in ipairs(skinned) do s.n = s.n + 1 end
    lid_ms.skip = (lid_ms.skip or 0) + 1
    return
  end
  local t0 = os.clock()
  local moved = lids_step()
  local ms = (os.clock() - t0) * 1000
  lid_ms.n, lid_ms.sum, lid_ms.top = lid_ms.n + 1, lid_ms.sum + ms, math.max(lid_ms.top, ms)
  lid_ms.idle = (moved and moved > 0) and 0 or (lid_ms.idle or 0) + 1
end
lids_step = function()
  local moved = 0
  -- qrot on plain numbers (no tables: this runs every tick; a local here, the file is at Lua's 200 locals)
  local function qrot3(q, x, y, z)
    local qx, qy, qz, qw = q.X, q.Y, q.Z, q.W
    local tx, ty, tz = 2 * (qy * z - qz * y), 2 * (qz * x - qx * z), 2 * (qx * y - qy * x)
    return x + qw * tx + qy * tz - qz * ty, y + qw * ty + qz * tx - qx * tz, z + qw * tz + qx * ty - qy * tx
  end
  local follow = tonumber(cfg().splitLidFollow) or 0
  local limit = follow > 0 and follow / TICK_S or math.huge
  for i = #skinned, 1, -1 do
    local s = skinned[i]
    s.n = s.n + 1
    local at = s.n <= limit and valid(s.pmc) and valid(s.comp) and valid(s.actor) and try(function()
      local x = s.actor:GetTransform()
      return { t = vec(x.Translation.X, x.Translation.Y, x.Translation.Z), q = qinv({ X = x.Rotation.X, Y = x.Rotation.Y, Z = x.Rotation.Z, W = x.Rotation.W }) }
    end)
    local tms = {}
    if at then
      for j, b in ipairs(s.bones) do
        tms[j] = bone_tm(s.comp, b)
        if not tms[j] then at = nil; break end
      end
    end
    local ok = false
    if at then
      -- nothing moved against the lid's actor since the last update (she lies still): no update. 14 ms a tick for
      -- the whole 12 s, most of it after she had settled (twenty-ninth playtest)
      local sig = {}
      for j, m in ipairs(tms) do
        local d = qrot(at.q, sub(m.t, at.t))
        sig[#sig + 1] = d.X; sig[#sig + 1] = d.Y; sig[#sig + 1] = d.Z
        local a, b = at.q, m.q
        sig[#sig + 1] = a.W*b.X + a.X*b.W + a.Y*b.Z - a.Z*b.Y
        sig[#sig + 1] = a.W*b.Y - a.X*b.Z + a.Y*b.W + a.Z*b.X
        sig[#sig + 1] = a.W*b.Z + a.X*b.Y - a.Y*b.X + a.Z*b.W
        sig[#sig + 1] = a.W*b.W - a.X*b.X - a.Y*b.Y - a.Z*b.Z
      end
      local still = s.sig ~= nil
      for k = 1, #sig do if still and math.abs(sig[k] - s.sig[k]) > (k % 7 >= 1 and k % 7 <= 3 and 0.05 or 0.0003) then still = false end end
      if still then ok = true
      else
        moved = moved + 1
        s.sig = sig
        -- (the same tables every update, the rotations in plain numbers: a fresh table per vertex and per step made
        -- thousands a tick, and the ticks the garbage was collected in took 43-50 ms, playtest)
        s.verts, s.normals = s.verts or {}, s.normals or {}
        local verts, normals = s.verts, s.normals
        local half = s.half or 0
        -- (the back side's vertices are the front's, its normals turned round)
        local tx, ty, tz, iq = at.t.X, at.t.Y, at.t.Z, at.q
        for k, w in ipairs(s.v) do
          local vk, nk = verts[k], normals[k]
          if not vk then vk, nk = vec(0, 0, 0), vec(0, 0, 0); verts[k], normals[k] = vk, nk end
          if half > 0 and k > half then
            local p, n = verts[k - half], normals[k - half]
            vk.X, vk.Y, vk.Z = p.X, p.Y, p.Z
            nk.X, nk.Y, nk.Z = -n.X, -n.Y, -n.Z
          else
            local A, B = tms[w.a], tms[w.b]
            local u, iu = w.t, 1 - w.t
            local ax, ay, az = qrot3(A.q, w.la.X, w.la.Y, w.la.Z)
            local bx, by, bz = qrot3(B.q, w.lb.X, w.lb.Y, w.lb.Z)
            vk.X, vk.Y, vk.Z = qrot3(iq, (A.t.X + ax) * iu + (B.t.X + bx) * u - tx,
              (A.t.Y + ay) * iu + (B.t.Y + by) * u - ty, (A.t.Z + az) * iu + (B.t.Z + bz) * u - tz)
            local nax, nay, naz = qrot3(A.q, w.na.X, w.na.Y, w.na.Z)
            local nbx, nby, nbz = qrot3(B.q, w.nb.X, w.nb.Y, w.nb.Z)
            local nx, ny, nz = nax * iu + nbx * u, nay * iu + nby * u, naz * iu + nbz * u
            local l = math.sqrt(nx * nx + ny * ny + nz * nz)
            if l > 1e-4 then nx, ny, nz = nx / l, ny / l, nz / l else nx, ny, nz = nax, nay, naz end
            nk.X, nk.Y, nk.Z = qrot3(iq, nx, ny, nz)
          end
        end
        ok = try(function() s.pmc:UpdateMeshSection_LinearColor(0, verts, normals, {}, {}, {}, {}, {}, {}); return true end)
          or try(function() s.pmc:UpdateMeshSection_LinearColor(0, verts, normals, {}, {}, {}); return true end)
        if not ok then log("split lid: the procedural mesh didn't take the update, it stays rigid") end
      end
    end
    if not ok then table.remove(skinned, i) end
  end
  return moved
end

-- one half's caps: the lid over the opening along the spine, in pieces riding the spine bones, and a domed one over
-- the neck where the head stayed on the other half (the DLL traces both: s0, n)
local function split_caps(q, comp, r, list)
  if cfg().caps == false then return true end
  local g = cfg()
  local w = q.capwork
  if not w then
    w = { ride = SPLIT_RIDE.of(q, comp), o = opening(r, "s0"), made = 0, bent = 0, i = 1, phase = "pieces" }
    q.capwork = w
    if w.o and w.o.p then
      w.pieces, w.nt = flat_lid(w.o, comp, g.splitLidGrow or 0.4, g.splitLidPush or 0.2, w.ride)
      w.lid_ride = SPLIT_RIDE.lid(q, comp)
      mark("lid shape")
      return false
    end
    w.phase = "fallback"
  end
  if w.phase == "skin" then
    local pc = w.pieces[w.i]
    if skin_lid(comp, w.actor, w.pmc, pc, w.lid_ride) then w.bent = w.bent + 1 end
    w.actor, w.pmc = nil, nil
    w.i, w.phase = w.i + 1, "pieces"
    mark("lid skin")
    return false
  end
  if w.phase == "pieces" then
    local pc = (w.pieces or {})[w.i]
    if pc then
      local a, kind, pmc = cap(q.pawn, comp, w.o, pc.bone, pc.built)
      if valid(pmc) and type(g.capMatte) == "table" and g.capMatte.splitLids == false then
        set_cap_material(pmc, load_obj(g.capMaterial or CAP_MATERIAL), true)
      end
      if a then
        w.made = w.made + 1
        list[#list + 1] = { actor = a, o = w.o, ride = pc.bone, comp = comp, kind = kind, whole = pc.skin }
      end
      if a and pmc and pc.skin then w.actor, w.pmc, w.phase = a, pmc, "skin"
      else w.i = w.i + 1 end
      mark("lid piece")
      return false
    end
    local ns = spine_halves(q, comp, w.o, list)
    mark("spine pieces")
    log(string.format("split lid on %s: %d points, %d triangles, %d pieces (%d bending with the spine), %d spine pieces", name_of(comp),
      #w.o.p, w.nt or 0, w.made, w.bent, ns))
    w.phase = "neck"
    return false
  elseif w.phase == "fallback" then
    if w.o then
      local at = nearest_bone(comp, w.o.c, w.ride)
      local a, kind = cap(q.pawn, comp, w.o, at)
      if a then list[#list + 1] = { actor = a, o = w.o, ride = at, comp = comp, kind = kind } end
    end
    w.phase = "neck"
    return false
  end
  local nk = opening(r, "n")
  if nk then
    local nb = "Bip001-Neck"
    for _, b in ipairs(w.ride) do if b == nb then nb = nil; break end end
    nb = nb and nearest_bone(comp, nk.c, w.ride) or "Bip001-Neck"
    local a, kind = cap(q.pawn, comp, nk, nb)
    if a then list[#list + 1] = { actor = a, o = nk, ride = nb, comp = comp, kind = kind } end
  end
  q.capwork = nil
  return true
end

-- the neck plane for a half's next split cut: across the neck at its base, facing the head. The half that keeps the
-- head (mode 1) keeps all of it and the neck, the other (2) closes over the neck: Eve's hair (CH_P_EVE_Hair02) has no
-- body bone to collapse a half of it onto, so a head is never halved. Halfway up the neck, a split leaned 2 cm beside
-- it took the far side's lower neck (the DLL keeps only the neck's width under halfway, NECK_BASE_R)
local function send_neck(comp, mode)
  local neck, head = bone_loc(comp, "Bip001-Neck"), bone_loc(comp, "Bip001-Head")
  local hi = try(function() return comp:GetBoneIndex(FName("Bip001-Head")) end)
  if not (neck and head and hi and hi > 0) then return "no neck" end
  local up = norm(sub(head, neck))
  if not up then return "no neck" end
  return command(string.format("h%x,%x,%x", comp:GetAddress(), mode, hi), neck, up)
end

-- Split-plane geometry is shared with hit-side and blade classification.
local split_plane = dofile("ue4ss/Mods/StellarBladeGore/Scripts/split_plane.lua")(M, cfg, bone_loc,
  vec, sub, add, scale, norm, dot, cross, function() return try end)

-- Outfit animation state is restored on recovery and discarded on world changes.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/outfit_animation.lua")(M, function() return try, valid end)

-- arm cuts before it (a blade through her arm raised to block, then down her length: M.blow) are kept; any other
-- cut and she isn't split
M.ARM_CUTS = { ["Bip001-L-UpperArm"] = true, ["Bip001-L-Forearm"] = true, ["Bip001-R-UpperArm"] = true, ["Bip001-R-Forearm"] = true }
-- the spine bone just past a blade's plane on the head's side (the original keeps the head): each half's ragdoll
-- breaks there, so the piece without the spine's other end isn't held on by invisible bodies; nil when the plane
-- runs along the spine or misses it
local SPINE_CHAIN = { "Bip001-Pelvis", "Bip001-Spine", "Bip001-Spine1", "Bip001-Spine2", "Bip001-Neck", "Bip001-Head" }
local SPINE_TOL = 4
local spine_break = dofile("ue4ss/Mods/StellarBladeGore/Scripts/split_break.lua")(M, SPINE_CHAIN, SPINE_TOL,
  bone_loc, sub, dot, function() return try end)

local stage_split_prep, stage_split_cut = dofile("ue4ss/Mods/StellarBladeGore/Scripts/split_cut.lua")(M, {
  cfg = cfg, addr = addr, face_of = face_of, clone_of = clone_of, log = log,
  bone_loc = bone_loc, spine_break = spine_break, split_plane = split_plane, body_frame = body_frame, from_body = from_body,
  add = add, sub = sub, scale = scale, norm = norm, len = len, dot = dot,
  limb_sides = limb_sides, place_like = place_like, command = command, enemy = enemy, split_chains = split_chains,
  send_limbs = send_limbs, send_neck = send_neck, side_cut = side_cut, SPLIT_RIDE = SPLIT_RIDE, SPLIT_SINK = SPLIT_SINK,
  ok_cut = ok_cut, num = num, v3 = function() return v3 end, cuts = function() return cuts end,
  add_cut = function(c) cuts[#cuts + 1] = c end,
})

local function set_mass(comp, bone, k)
  local m = try(function() return comp:GetBoneMass(FName(bone), true) end)
  if m and m > 0 then try(function() comp:SetMassOverrideInKg(FName(bone), m * k, true) end) end
end

-- the torso's helper bones (the split's flattening sinks are picked among them) in their parents' space: a helper the
-- animation drives (an aim or corrective bone) moves off its parent while the half lies still, and the skin
-- flattened onto it stretches out of the lid (eighteenth playtest's flat shards on Ab-*-Shoulder0, Pectro0, AX1)
local HELPER_PARENTS = { ["Bip001-Pelvis"] = true, ["Bip001-Spine"] = true, ["Bip001-Spine1"] = true, ["Bip001-Spine2"] = true, ["Bip001-Neck"] = true }
local function helper_pose(comp)
  local out = {}
  local nb = try(function() return comp:GetNumBones() end) or 0
  for i = 0, nb - 1 do
    local nm = try(function() return comp:GetBoneName(i):ToString() end)
    local par = nm and (nm:sub(1, 3) == "Ab-" or nm:sub(1, 3) == "Dm-") and parent_bone(comp, nm)
    -- a Dm- helper's own children too (Ab-R-AX1 under Dm-R-Trape under Dm-R-Trape-Cnt)
    local top = par
    while top and top:sub(1, 3) == "Dm-" do top = parent_bone(comp, top) end
    if top and HELPER_PARENTS[top] then
      local t = try(function()
        local x = comp:GetSocketTransform(FName(nm), 3) -- RTS_ParentBoneSpace
        return { p = vec(x.Translation.X, x.Translation.Y, x.Translation.Z), q = { x.Rotation.X, x.Rotation.Y, x.Rotation.Z, x.Rotation.W } }
      end)
      if t then out[nm] = t end
    end
  end
  return out
end
local function helper_drift(comp, base)
  if not (valid(comp) and base) then return "?" end
  local list = {}
  for nm, b in pairs(base) do
    local t = try(function()
      local x = comp:GetSocketTransform(FName(nm), 3)
      return { p = vec(x.Translation.X, x.Translation.Y, x.Translation.Z), q = { x.Rotation.X, x.Rotation.Y, x.Rotation.Z, x.Rotation.W } }
    end)
    if t then
      local d = len(sub(t.p, b.p))
      local c = math.abs(t.q[1] * b.q[1] + t.q[2] * b.q[2] + t.q[3] * b.q[3] + t.q[4] * b.q[4])
      local deg = math.deg(2 * math.acos(math.min(c, 1)))
      if d > 0.5 or deg > 5 then list[#list + 1] = { nm = nm, d = d, deg = deg } end
    end
  end
  table.sort(list, function(x, y) return x.d + x.deg / 10 > y.d + y.deg / 10 end)
  local parts = {}
  for i = 1, math.min(8, #list) do parts[#parts + 1] = string.format("%s %.1f cm %.0f deg", list[i].nm, list[i].d, list[i].deg) end
  return #parts > 0 and table.concat(parts, ", ") or "none"
end

-- one half's ragdoll: the limbs that went with the other half (gone, as its skin was cut) come off and fall free,
-- the spine weighs half, a push away from the other half and a tip that topples the halves apart. Hiding them with
-- their bodies (HideBoneByName, PBO_Term) stopped her ragdoll the tick the split opened, and her mesh never
-- simulated again until the level reloaded (twelfth playtest)
-- spine, upper: where a blade went through the spine, and whether this half keeps what is above it (the head's end)
-- Bone ancestry and body inventories are immutable during a split. Resolve them before the opening,
-- leaving that frame to change physics rather than repeatedly crossing the engine bridge for every limb/body.
function M.split_layout(comp, gone, spine, upper)
  local pa = ctx.physics_of(comp)
  local plan = { names = {}, bodies = {}, off = {} }
  if valid(pa) then
    try(function() pa.SkeletalBodySetups:ForEach(function(_, e)
      local bs = e:get()
      if valid(bs) then
        local b = bs.BoneName:ToString()
        plan.names[#plan.names + 1], plan.bodies[b] = b, true
      end
    end) end)
  end
  for _, bn in ipairs(plan.names) do
    local off = false
    for _, b in ipairs(gone or {}) do
      if bn == b or M.hangs_off(comp, bn, b) then off = true; break end
    end
    if spine then
      local above = bn == spine or M.hangs_off(comp, bn, spine)
      if (upper and not above) or (not upper and above) then off = true end
    end
    plan.off[bn] = off
  end
  return plan
end

local function settle_half(comp, at, n, push, gone, spine, upper, plan)
  plan = plan or M.split_layout(comp, gone, spine, upper)
  local broke = {}
  for _, b in ipairs(gone or {}) do
    if plan.bodies[b] then
      try(function() comp:BreakConstraint(vec(0, 0, 0), bone_loc(comp, b) or at, FName(b)) end)
    else
      M.break_limb(comp, b, bone_loc(comp, b) or at)
    end
    broke[#broke + 1] = b
  end
  if spine then
    try(function() comp:BreakConstraint(vec(0, 0, 0), bone_loc(comp, spine) or at, FName(spine)) end)
    if not upper then broke[#broke + 1] = spine end
  end
  for _, bn in ipairs(plan.names) do
    -- Gone bodies fall freely at their own mass. Only bodies still on the half need a live position.
    if plan.off[bn] then
      if ctx.on_free then try(function() ctx.on_free(comp, bn) end) end
    elseif bn ~= "Bip001-Neck" and bn ~= "Bip001-Head" then
      local l = bone_loc(comp, bn)
      local h = l and dot(sub(l, at), n) or 0
      if math.abs(h) < 4 then set_mass(comp, bn, 0.5) end
    end
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
-- the copy's physics bodies, kinematic in her pose till split_physics: a tick before the opening (made in the
-- opening's own tick, with the rest of it, that frame was 55-70 ms, playtest 41)
function M.split_bodies(q)
  if q.bodied then return end
  q.bodied = true
  local b2 = q.body2
  local pa = ctx.physics_of(q.mesh)
  -- the copy was made without collision, so it has no physics bodies: a profile change doesn't create them (only
  -- SetCollisionEnabled does), and SetSimulatePhysics then did nothing. The copy stood frozen where she was cut
  try(function() b2:SetCollisionEnabled(3) end)
  try(function() b2:SetCollisionProfileName(FName("Ragdoll"), true) end)
  -- PhysicsBody = 5: the halves don't collide with each other (or themselves, like her ragdoll)
  try(function() b2:SetCollisionResponseToChannel(5, 0) end)
  if pa then try(function() b2:SetPhysicsAsset(pa, true) end) end
  mark("copy bodies")
end
-- the arms cut off before the split (M.blow: a blade through her arm raised to block, then down her length): one whose
-- shoulder went with the copy is the copy's now, its stump and the flying piece both (its weights came with hers,
-- "y", and her half let go of it). The piece comes off the copy's body as it flies on, and the cut's caps and stubs
-- ride the copy's bones, keeping their place on the bone (KeepRelative: the copy's bones aren't posed yet in the tick
-- it starts to simulate, and kept where they were in the world they sat far off the hand, playtest)
function M.arms_to_copy(q)
  local b2, moved = q.body2, {}
  for _, c in ipairs(q.armcuts or {}) do
    local root = c.bone:gsub("Forearm", "UpperArm")
    local theirs = false
    for _, b in ipairs(q.gone1 or {}) do if b == root then theirs = true end end
    if theirs and valid(b2) then
      M.break_limb(b2, c.bone, bone_loc(b2, c.bone) or q.c.at)
      local v = try(function() local x = q.mesh:GetPhysicsLinearVelocity(FName(c.bone)); return vec(x.X, x.Y, x.Z) end)
      if v then try(function() b2:SetAllBodiesBelowLinearVelocity(FName(c.bone), v, true) end) end
      local k = 0
      for _, r in ipairs(c.riders or {}) do
        if valid(r.a) and try(function() r.a:K2_AttachToComponent(b2, FName(r.bone), 0, 0, 0, false); return true end) then k = k + 1 end
      end
      moved[#moved + 1] = string.format("%s (%d caps and stubs)", c.bone, k)
    end
  end
  if #moved > 0 then log("split: the copy takes the arm cut off before: " .. table.concat(moved, ", ")) end
end
local function split_physics(q, vel)
  local g = cfg()
  local b2 = q.body2
  M.split_bodies(q)
  try(function() b2:SetComponentTickEnabled(true) end)
  try(function() b2:SetSimulatePhysics(true) end)
  local v = try(function() local x = q.mesh:GetPhysicsLinearVelocity(FName("Bip001-Pelvis")); return vec(x.X, x.Y, x.Z) end)
  if v then try(function() b2:SetAllPhysicsLinearVelocity(v, false) end) end
  local sim = try(function() return b2:IsSimulatingPhysics(FName("Bip001-Pelvis")) end) == true
  if not sim then
    try(function() b2:SetAllBodiesSimulatePhysics(true) end)
    try(function() b2:WakeAllRigidBodies() end)
  end
  local sim2 = try(function() return b2:IsSimulatingPhysics(FName("Bip001-Pelvis")) end) == true
  mark("copy simulates")
  if not q.rehomed then rehome(q, b2, q.c.at, q.c.n) end
  mark("rehome")
  if cfg().probes then copy_watch = { comp = b2, her = q.mesh, n = 0, helpers = { her = helper_pose(q.mesh), copy = helper_pose(b2) } } end
  if ctx.on_copy and not q.massed then try(function() ctx.on_copy(b2) end) end
  mark("copy masses")
  -- she stood still while it was cut; now both halves fall, before they get pushed apart
  if ctx.on_release then try(function() ctx.on_release() end) end
  mark("release")
  log(string.format("split copy ragdoll: simulating %s%s, collision %s", tostring(sim2), sim and "" or " (second try)",
    tostring(try(function() return b2:GetCollisionEnabled() end))))
  local at, n = q.c.at, q.c.n
  local push = g.splitPush or 120
  -- her arms keep colliding with her body where her half has both bodies of a pair (across her waist: her chest,
  -- not her hips); the table is written again with only those, the pairs with a body on the other half (invisible on
  -- hers) apart again. None left, or the table not written: her bodies stop colliding with each other
  local keep = false
  if ctx.arm_pairs then
    local kept = {}
    for _, p in ipairs(ctx.arm_pairs) do
      local whole = true
      for _, b in ipairs(p) do
        local l = bone_loc(q.mesh, b)
        if not l or dot(sub(l, at), n) <= 0 then whole = false end
      end
      if whole then kept[#kept + 1] = p end
    end
    local r = #kept == #ctx.arm_pairs and "ok all" or #kept > 0 and ctx.arm_table and try(function() return ctx.arm_table(q.mesh, kept) end) or "none"
    keep = #kept > 0 and r:sub(1, 3) == "ok "
    if keep and #kept < #ctx.arm_pairs then
      -- switched off and on, so the engine filters her body pairs again by the new table (main.lua's start does so)
      try(function() q.mesh:SetCollisionResponseToChannel(5, 0) end)
      try(function() q.mesh:SetCollisionResponseToChannel(5, 2) end)
    end
    if keep then ctx.arm_pairs = kept end
    log(string.format("split: her arms %s (%d of the pairs on her half: %s)", keep and "go on colliding with her body"
      or "stop colliding with her body", #kept, r))
  end
  no_self_collision(q.mesh, keep)
  local b1 = settle_half(q.mesh, at, n, push, q.gone1, q.spine, true, q.layout1)
  -- the copy's head is closed over: its body comes off and weighs nothing, like a gone limb's
  local gone2 = { table.unpack(q.gone2 or {}) }
  if not (q.spine and q.spine ~= "Bip001-Head") then gone2[#gone2 + 1] = "Bip001-Head" end
  local b2l = settle_half(b2, at, scale(n, -1), push, gone2, q.spine2, false, q.layout2)
  M.arms_to_copy(q)
  mark("halves")
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
  -- a killing blow sends both halves flying the way it hit her (her half stayed put while the cut off one flew)
  -- (across the waist the upper body flies faster, splitFlyUpper: at 200 it dropped at her feet, playtest 41; it is
  -- her half, which keeps the head's end)
  local fly = q.fly and (g.splitFly or 350) or 0
  if fly > 0 then
    local v = norm(add(q.fly, vec(0, 0, 0.3))) or q.fly
    local p0, p1 = bone_loc(q.mesh, "Bip001-Pelvis"), bone_loc(q.mesh, "Bip001-Neck")
    local axis = p0 and p1 and norm(sub(p1, p0))
    local up = axis and math.abs(dot(axis, n)) >= 0.6 and q.mesh or nil
    local upper = math.max(fly, g.splitFlyUpper or fly)
    for _, comp in ipairs({ q.mesh, b2 }) do
      local f = comp == up and upper or fly
      try(function() comp:AddImpulseToAllBodiesBelow(scale(v, f), FName("Bip001-Pelvis"), true, true) end)
    end
    log(string.format("split: both halves fly with the blow, %s at %.0f cm/s%s", v3(v), fly,
      up and string.format(", the upper body at %.0f", upper) or ""))
  end
  mark("fly")
  log(string.format("split falls apart (%s): limbs off %s | %s", q.why, table.concat(b1, ","), table.concat(b2l, ",")))
  local p = q.pieces or {}
  local n1, w1 = hide_gone(p.her, b1)
  local n2, w2 = hide_gone(p.copy, b2l)
  log(string.format("split: outfit pieces with the other half's limbs hidden: %d of %d on her half (%s), %d of %d on the copy (%s)",
    n1, #(p.her or {}), w1, n2, #(p.copy or {}), w2))
end

local function stage_split_open(q)
  local g = cfg()
  local k = command("k")
  if #(q.armcuts or {}) > 0 then command(string.format("S%x,0,1", q.mesh:GetAddress())) end
  local b2 = q.body2
  -- the copy takes over the pose she is in now
  place_like(b2, q.mesh)
  local p = command(string.format("p%x,%x", q.mesh:GetAddress(), b2:GetAddress()))
  try(function() b2:SetHiddenInGame(false, false) end)
  mark("copy shown")
  M.copies_split(q)
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
    M.bodyBlood.up(q.pawn)
    niagara(FX.hit, q.pawn, nil, q.hit or at, false)
    M.splat(q.pawn, at)
    -- bleeding along the seam: from the chest and neck lids of each half
    local left = math.floor((g.bleedTime or 2.5) / TICK_S + 0.5)
    for _, c in ipairs(q.caps) do
      if valid(c.actor) and c.kind ~= "spine" and (q.plane or c.whole or c.ride == "Bip001-Spine2" or c.ride == "Bip001-Neck" or c.ride == "Bip001-Spine") then
        local qq, cap = { pawn = q.pawn, mesh = c.comp }, c
        later[#later + 1] = { n = 1, label = "stump spurt", fn = function()
          if valid(qq.mesh) then bleed_from(qq, cap.actor, cap.o, cap.ride, left) end
        end }
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
    q.anim and (q.anim > 0 and string.format(", her fall plays on for %.1f s", q.anim) or ", she ragdolls now") or ""))
end

-- An exclusive split setting is an explicit request not to substitute another death cut.
function M.only_split()
  local g, w = cfg(), cfg().death or {}
  if g.noSplits == true or g.deathSplit == false or (tonumber(w.split) or 0) <= 0 then return false end
  for _, key in ipairs({"limb", "head", "torso"}) do
    if (tonumber(w[key]) or 0) > 0 then return false end
  end
  if (g.diagonal or {}).enabled ~= false and (tonumber(w.diagonal) or 0) > 0 then return false end
  return true
end
local start -- below; a degenerate split falls back to a waist cut through it
local aimed -- M.aim: the next cut's flying direction
local split_stage
local function split_tick(q) split_stage(q) end
split_stage = function(q)
  if q.stage == "cut" then
    if stage_split_prep(q) then q.stage = "cut2"; q.wait = 3; return end -- (frames: the copy posed first)
  elseif q.stage == "cut2" then
    if stage_split_cut(q) then q.stage = "cut3"; q.wait = 0; return end
  elseif q.stage == "cut3" then
    if M.stage_split_copy(q) then
      local function rides(c) local l = { "Bip001-Neck" }; for _, b in ipairs(SPLIT_RIDE.of(q, c) or {}) do l[#l + 1] = b end; return l end
      q.posed = M.snap({ { q.mesh, rides(q.mesh) }, { q.body2, rides(q.body2) } })
      for a, t in pairs(q.posed1 or {}) do q.posed[a] = t end
      q.stage = "caps"; q.wait = 0; return
    end
  elseif q.stage == "caps" then
    -- Shape, each mesh, skin weights, spine and neck run in separate frames, using the saved cut pose.
    M.posed = q.posed
    local done = split_caps(q, q.mesh, q.r1, q.caps)
    M.posed = nil
    if done then q.stage = "caps2" end
    q.wait = 0
    return
  elseif q.stage == "caps2" then
    M.posed = q.posed
    local done = split_caps(q, q.body2, q.r2, q.caps)
    M.posed = nil
    if not done then q.wait = 0; return end
    mark("lids")
    q.stage, q.wait = "bodies", 0
    return
  elseif q.stage == "bodies" then
    M.split_bodies(q)
    q.stage, q.wait = "layout", 0
    return
  elseif q.stage == "layout" then
    q.layout1 = M.split_layout(q.mesh, q.gone1, q.spine, true)
    mark("her body layout")
    q.stage, q.wait = "layout2", 0
    return
  elseif q.stage == "layout2" then
    local gone = { table.unpack(q.gone2 or {}) }
    if not (q.spine and q.spine ~= "Bip001-Head") then gone[#gone + 1] = "Bip001-Head" end
    q.layout2 = M.split_layout(q.body2, gone, q.spine2, false)
    mark("copy body layout")
    q.stage, q.wait = "rehome", 0
    return
  elseif q.stage == "rehome" then
    -- A held ragdoll has a stable pose, so its outfit riders can move before the opening. An animated
    -- fall keeps them on her live pose until split_physics, after the copy has become a ragdoll.
    if not q.anim then
      place_like(q.body2, q.mesh)
      command(string.format("p%x,%x", q.mesh:GetAddress(), q.body2:GetAddress()))
      rehome(q, q.body2, q.c.at, q.c.n)
      q.rehomed = true
      mark("rehome")
    end
    q.stage, q.wait = "masses", 0
    return
  elseif q.stage == "masses" then
    -- the copy's masses and spin caps (active.lua) a frame of their own: in the opening's frame they were 36 of its
    -- 64 ms (playtest)
    if ctx.on_copy and valid(q.body2) then try(function() ctx.on_copy(q.body2) end) end
    q.massed = true
    mark("copy masses")
    q.stage, q.wait = "open", 0
    return
  elseif q.stage == "open" then
    stage_split_open(q)
    if q.anim then
      q.stage, q.t, q.seen = "anim", 0, nil
      -- (her bones read now: the next frame has their speed and her ragdoll, the one after the halves apart, as many
      -- frames as before her ragdoll had one of its own)
      local now = {}
      for _, b in ipairs(q.bodies or {}) do now[b] = bone_loc(q.mesh, b) end
      q.seen, q.tl = now, os.clock()
      return
    end
    pending = nil
    return
  else
    -- her fall plays on with both halves: each body's speed from the last two frames, then they fall apart
    -- (in real time: the stages run a frame each)
    local clk = os.clock()
    local dt = q.tl and math.max(clk - q.tl, 1e-3) or TICK_S
    q.tl = clk
    q.t = q.t + dt
    local now = {}
    for _, b in ipairs(q.bodies or {}) do now[b] = bone_loc(q.mesh, b) end
    local vel = nil
    if q.seen then
      vel = {}
      for b, l in pairs(now) do
        local o = q.seen[b]
        if o then vel[b] = scale(sub(vec(l.X, l.Y, l.Z), vec(o.X, o.Y, o.Z)), 1 / dt) end
      end
    end
    q.seen = now
    -- (her ragdoll a frame before the halves come apart, the copy still on her pose for it; the copy's bodies and
    -- masses before the opening, "masses": all in the one frame they were 70 ms, playtest)
    -- (two frames at least: the halves fall on at the speed the animation gave each body)
    if not q.vel and (q.t < q.anim or not vel) then return end
    if not q.vel then
      q.vel = vel
      if ctx.on_need_ragdoll then try(function() ctx.on_need_ragdoll("split") end) end
      mark("her ragdoll")
      return
    end
    pending = nil
    if valid(q.body2) then try(function() q.body2:SetMasterPoseComponent(nil, true) end) end
    for _, c in ipairs(q.copies2 or {}) do if valid(c) then try(function() c:SetMasterPoseComponent(q.body2, true) end) end end
    command(string.format("p%x,%x", q.mesh:GetAddress(), q.body2:GetAddress()))
    mark("copy pose")
    split_physics(q, q.vel)
    return
  end
  -- it didn't happen: nothing of it stays, and she falls whole (a degenerate one: cut across the waist instead)
  pending = nil
  M.undo_split()
  if ctx.on_release then try(function() ctx.on_release() end) end
  -- a degenerate split is tried once more straight down her middle (no blade's turn, tilt or hip shift) before the
  -- waist cut: a vertical split rolled at 100 came out a waist cut, the copy's half leaving 2882 vertices unsunk on a
  -- plane 15 deg off her middle (playtest, CH_P_EVE_30)
  -- (after a cut this death, an arm off before the split, it stops there: the retry and the waist cut on top of the
  -- arm made one slash an arm, two undone splits and a waist cut, in pieces with holes and stretched skin, playtest)
  local before = false
  if q.degenerate then
    local a = addr(q.mesh)
    for _, c in ipairs(cuts) do if c.addr == a then before = true end end
    if before then log("split (" .. q.why .. "): her earlier cut stays, no waist cut on top of it") end
  end
  if q.degenerate and not before then
    if q.kind == "split" and not q.middle and not (q.plane and q.plane.diag) then
      log("split (" .. q.why .. "): once more, straight down her middle")
      M.splitMiddle = true
      local ok = start(q.pawn, q.mesh, q.hit, q.why, "split")
      M.splitMiddle = nil
      if ok then return end
    end
    if q.kind == "split" and q.why == "death" and M.only_split() then
      log("split (death): both planes failed; split-only setting leaves her uncut instead of a waist cut")
    else
      start(q.pawn, q.mesh, q.hit, q.why, "torso")
    end
  end
end

-- a cut runs in stages a few ticks apart, so no frame shows a half-made cut: LOD0 forced (the cut is made in
-- LOD0's weights; bones LOD0 adds aren't posed until the switch went through), then the new weights (uploaded to
-- the GPU by the render thread), then the collapse that opens the seam (on the game thread, immediately)
-- kind: "limb" (arm or thigh nearest the hit), "head" or "torso"; tune.gore.bone, when it names a part, wins
function start(pawn, mesh, hit, why, kind, out, plane, blade)
  local g = cfg()
  if g.enabled == false then return false end
  if native.state ~= "ready" then log(kind .. " skipped (" .. why .. "): sbslice.dll is " .. native.state); return false end
  if pending then log(kind .. " skipped (" .. why .. "): another cut is still opening"); return false end
  -- an enemy is never split (a split rebuilds Eve's outfit pieces and needs her whole), and has no face of its own
  if enemy.cur and kind == "split" then log("split skipped (" .. why .. "): not on an enemy"); return false end
  -- vertical splits off altogether (noSplits): only the test keys still split (a diagonal is not one)
  if kind == "split" and g.noSplits == true and not (plane and plane.diag) and why ~= "F11" and why ~= "F5" then
    log("split skipped (" .. why .. "): vertical splits are off (noSplits)"); return false
  end
  local tb = not enemy.cur and PARTS[g.bone or ""] or {}
  local face = not enemy.cur and (kind == "head" or (kind ~= "split" and not blade and tb.kind == "head"))
  -- (an enemy built like her: its face whenever the cut may take the head)
  if enemy.cur and enemy.faced[enemy.cur] then face = kind == "head" or (blade ~= nil and kind ~= "split") end
  face = face and face_of(pawn, mesh) or nil
  mark("start: checks")
  local waited = force_lod(mesh)
  if face then waited = force_lod(face) or waited end
  mark("start: lod")
  pending = { stage = "cut", wait = waited and 2 or 0, t0 = os.clock(), pawn = pawn, mesh = mesh, hit = hit, why = why, kind = kind,
    face = face, out = out, plane = plane, blade = blade, owner = enemy.cur, bone = M.bone_once, middle = M.splitMiddle,
    smash = M.smash_once and not enemy.cur or nil, fullSmash = M.full_smash_once and not enemy.cur or nil,
    fly = aimed and os.clock() - aimed.t < 1 and aimed.d or nil,
    quiet = why == "carried" or nil }
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
    or (not blade and tb.kind == "torso")
  -- unless it is a split and she is playing her fall: then her fall plays on while it is cut, and both halves with
  -- it for tune.gore.splitAnim seconds once it opens, before they come apart (split_tick). (Switched to the ragdoll
  -- at the roll, she hung frozen in it for the ~0.4 s the cut took, then fell apart: the ragdoll came before the cut)
  local anim = why == "death" and kind == "split" and ctx.animated and ctx.animated()
  -- or a cut across her waist in her fall that keeps her legs in it (torsoLegs): the upper body breaks off into the
  -- ragdoll as a cut limb does (its joint broken, flung with the blow), her legs and hips play the fall on
  local legs = why == "death" and kind == "torso" and not anim and ctx.animated and ctx.animated() and M.torso_legs(blade)
  if legs then
    pending.torsoLegs = true
    log("waist cut: her legs play the fall on, the upper body flies off (" .. legs .. ")")
  elseif anim then
    pending.anim = math.max(tonumber(g.splitAnim) or 0, 0)
    local pa = ctx.physics_of(mesh)
    pending.bodies = {}
    if valid(pa) then
      try(function() pa.SkeletalBodySetups:ForEach(function(_, e) local bs = e:get(); if valid(bs) then pending.bodies[#pending.bodies + 1] = bs.BoneName:ToString() end end) end)
    end
  elseif (why == "death" or why == "after") and halves and ctx.on_need_ragdoll then
    -- (the cut a frame after the switch, not in its frame: stage_cut's own rule)
    local was = ctx.animated and ctx.animated()
    try(function() ctx.on_need_ragdoll(kind) end)
    if was then pending.wait = math.max(pending.wait, 1) end
  end
  -- a split comes first, then the fall: she is held where she is until it opens
  if kind == "split" and not anim and ctx.on_hold then try(function() ctx.on_hold(mesh) end) end
  mark("start: ragdoll, hold")
  -- its first stage now, in this frame, when nothing waits
  M.pump()
  mark("start: first stage")
  return true
end

-- that part (a PARTS bone) cut off, whatever tune.gore.bone says (glass.lua: where the hit landed)
function M.slice_bone(pawn, mesh, bone, hit, why)
  if not PARTS[bone] or already_cut(mesh, bone) then return false end
  M.bone_once = bone
  local ok, result = pcall(start, pawn, mesh, hit, why, PARTS[bone].kind)
  M.bone_once = nil
  if not ok then error(result, 0) end
  return result
end
-- these bones cut in turn (main.lua's F6 struggle tests): the first now, the rest queued a cut apart as a swing's
-- further cuts are. How many were started or queued
function M.slice_bones(pawn, mesh, bones, why)
  local n = 0
  for i, bone in ipairs(bones) do
    if PARTS[bone] then
      if i == 1 or n == 0 then
        if M.slice_bone(pawn, mesh, bone, nil, why) then n = n + 1 end
      else
        queued[#queued + 1] = function() return valid(mesh) and M.slice_bone(pawn, mesh, bone, nil, why) end
        n = n + 1
      end
    end
  end
  if n > 1 then M.queue_gap = cfg().queueGap or 1 end
  return n
end
function M.has_cut(mesh, bone) return already_cut(mesh, bone) end
-- the parts cut off her whose mesh wears another asset now: an outfit put on her over the cut (Nexus 672, ESE: her
-- shield broken, her suit torn or gone to the inner suit) is a new asset on the same component, its weights uncut, and
-- the arm cut off her was back on her (reported). forget: their records dropped, the old asset's sinks put back
-- (nothing else of hers wears it now), the caps and bleeds left riding their bones, so they can be cut again; not her
-- body's (a waist cut: its split's copy holds the other half, and a second split made a second one), returned second
function M.swapped(mesh, forget)
  local a, out, olds, kept, quiet = addr(mesh), {}, {}, {}, {}
  local wc = a and M.weddingCloth[a]
  if wc and wc.asset ~= addr(try(function() return mesh.SkeletalMesh end)) then
    try(function() mesh.ClothBlendWeight = wc.old end)
    M.weddingCloth[a] = nil
  end
  for i = #cuts, 1, -1 do
    local c = cuts[i]
    if c.addr == a and PARTS[c.bone] and not c.smashed and not enemy.owned[c] and c.sm and enemy.asset(mesh) ~= c.sm then
      if forget and PARTS[c.bone].kind == "torso" then
        kept[#kept + 1] = c.bone
        c.sm = enemy.asset(mesh)
      else
        out[#out + 1] = c.bone
        if c.quiet then quiet[c.bone] = true end
        if forget then olds[c.sm] = true; table.remove(cuts, i) end
      end
    end
  end
  for sm in pairs(olds) do
    local shared = false
    for _, c in ipairs(cuts) do if c.sm == sm then shared = true end end
    if not shared then log("cut redone on another asset: the old one's sinks " .. command(string.format("r%x", sm))) end
  end
  return out, kept, quiet
end

-- ---- smash (tune.gore.smash, experimental) ----
-- A blunt killing blow (main.lua's blunt_of: a hammer, a fist, a stomp) smashes the part it landed on instead of
-- cutting it clean: the part comes off as any cut does (its stump keeps its cap, bone and bleed), but the piece itself
-- vanishes (its bones hidden on every part of her that has them, a head's hair and what rides it too) and the game's
-- own meat chunks (SM_meat_01-04, its effects' meshes) burst out where it was, with blood; a few drip and pool where
-- they land. Each chunk is a static mesh riding an invisible simulated box (its mesh may have no collision)
M.SMASH_MESHES = {
  "/Game/Art/FX/SM/SM_meat_01.SM_meat_01", "/Game/Art/FX/SM/SM_meat_02.SM_meat_02",
  "/Game/Art/FX/SM/SM_meat_03.SM_meat_03", "/Game/Art/FX/SM/SM_meat_04.SM_meat_04",
}
M.SMASH_FX = "/Game/Art/FX/Enviroment/Matrix_XI/Cinematic/ME05_02_EliteNative_Finish/NS_A_MeatSplash.NS_A_MeatSplash"
-- The flesh blood effect accepts scale, unlike the grinder's world-space GPU droplets.
M.SMASH_BLOOD = "/Game/Art/FX/Char/Common/Hit/Flesh/NS_Hit_Flesh_Slice_BloodOnly.NS_Hit_Flesh_Slice_BloodOnly"
M.SMASH_GRINDER = "/Game/Art/FX/Enviroment/Matrix_XI/Cinematic/Grinder_Dead/NS_A_BloodExplosive.NS_A_BloodExplosive"
-- count key, whole-part count, flesh contributed by this segment alone, meat size.
M.SMASH_PARTS = {
  ["Bip001-L-UpperArm"] = { "chunks", 10, 4, 1 },
  ["Bip001-R-UpperArm"] = { "chunks", 10, 4, 1 },
  ["Bip001-L-Forearm"] = { "chunksForearm", 6, 6, 0.9 },
  ["Bip001-R-Forearm"] = { "chunksForearm", 6, 6, 0.9 },
  ["Bip001-L-Thigh"] = { "chunksLeg", 16, 6, 1.15 },
  ["Bip001-R-Thigh"] = { "chunksLeg", 16, 6, 1.15 },
  ["Bip001-L-Calf"] = { "chunksCalf", 10, 10, 1.05 },
  ["Bip001-R-Calf"] = { "chunksCalf", 10, 10, 1.05 },
  ["Bip001-Head"] = { "chunksHead", 8, 8, 1 },
  ["Bip001-Spine1"] = { "chunksBody", 36, 8, 1.25, 44 },
}
-- Selection and geometric coverage are separate from smash effects and lifecycle.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore_smash_select.lua")(M, PARTS, cfg,
  function() return try, valid end, function() return cuts end, addr, already_cut, pick, bone_loc,
  vec, add, sub, scale, len, dot)

-- Smash effects use the current cleanup queues because recovery can replace them.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore_smash.lua")(M, {
  PARTS = PARTS, FX = FX, enemy = enemy, cfg = cfg, addr = addr, already_cut = already_cut, log = log,
  hair_of = hair_of, niagara = niagara, vec = vec, bone_loc = bone_loc, norm = norm, add = add, sub = sub,
  scale = scale, len = len, load_obj = load_obj, set_cap_material = set_cap_material, mark = mark, pick = pick, track = track,
  guards = function() return try, valid end, v3 = function() return v3 end, ctx = function() return ctx end,
  later = function() return later end, caps = function() return caps end,
})
-- a command to sbslice.dll and its answer; quiet: no answer (one a tick, glass.lua's stats tick)
M.command = command
-- "init", "waiting", "ready" or "failed" (physfix.lua waits for it)
function M.native_state() return native.state end
function M.quiet(s)
  local cdo = load_obj(CHEAT_CDO)
  if not cdo then return false end
  return pcall(function() cdo:SBRewardGroupDropFormationPathLocation(FName("None"), 0, 0, 0, s, 0, 0, 0) end)
end

-- the direction the killing blow travelled (world), for the next cut's pieces to fly along (nil: they drop off)
function M.aim(dir)
  local d = dir and norm(vec(dir.X, dir.Y, dir.Z))
  -- only for a cut made right after (a blow that cut nothing leaves it for no later cut)
  aimed = d and d.X == d.X and { d = d, t = os.clock() } or nil
end

-- a split is on its way (it brings its own blood once it opens)
function M.splitting() return pending ~= nil and pending.kind == "split" end
-- a cut is opening or queued (a new one now would be skipped)
function M.busy() return pending ~= nil or #queued > 0 end
-- the cuts made on this mesh so far, and whether one of them split her
function M.cuts_on(mesh)
  local a, n, split = addr(mesh), 0, false
  for _, c in ipairs(cuts) do
    if c.addr == a then n = n + 1; split = split or c.bone == "split" or c.bone == "split copy" end
  end
  return n, split
end

-- Accepted split work blocks death movements before its first cut; completed halves stay blocked.
function M.split_on(mesh)
  local a = addr(mesh)
  if not a then return false end
  if pending and pending.kind == "split" and (addr(pending.mesh) == a or addr(pending.body2) == a) then return true end
  return select(2, M.cuts_on(mesh))
end

-- the parts cut off this mesh so far (a limb, the head, her upper body), by their root bone. lying: only the ones
-- that lie somewhere as a piece (not one carried over a level change, hidden on her: its piece stayed in the old one)
function M.cut_parts(mesh, lying)
  local a, out = addr(mesh), {}
  for _, c in ipairs(cuts) do
    if c.addr == a and PARTS[c.bone] and not c.smashed and not (lying and c.quiet) then out[#out + 1] = c.bone end
  end
  return out
end

function M.rebreak_cuts(mesh)
  local a, done = addr(mesh), {}
  for _, c in ipairs(cuts) do
    if c.addr == a and c.opened and PARTS[c.bone] and not c.quiet then
      local at = bone_loc(mesh, c.bone)
      if at then
        local skip = {}
        for _, b in ipairs(c.kept or {}) do skip[b] = true end
        M.break_limb(mesh, c.bone, at, skip)
        done[#done + 1] = c.bone
      end
    end
  end
  if #done > 0 then log("re-broke cuts after physics asset setup: " .. table.concat(done, ", ")) end
  return #done
end
-- photo mode with a piece off her alive: her mesh used to stop ticking (its animation pulled the piece back onto her,
-- physics being paused), and photo mode's poses and expressions never showed (reported). Now the piece goes onto a
-- copy of her mesh as photo mode opens: her cut weights ("y"), her pose with every bone but the piece's scaled to
-- nothing ("P"), not ticking or simulating, so it lies where it fell. On her the piece's bones are hidden (her face's
-- too with a head), and what rides them (caps, stubs, bleeds, accessories on their sockets) moves onto the copy's same
-- bone, where it sits as it did. Her mesh poses on. As photo mode closes it all goes back and the copy is destroyed.
-- Returns how many pieces went onto the copy, and what rode them.
-- bake: the same while she plays, once a limb cut off her has settled (main.lua's hm.piece_watch): kept till a
-- cut, a regrow, her death or an undo needs the piece on her mesh again (h.baked; photo mode leaves it so)
M.pieceHid = nil
function M.hide_pieces(pawn, mesh, on, bake)
  local h = M.pieceHid
  local tag = bake and "piece settled" or "photo mode"
  if not on then
    M.pieceHid = nil
    if not h then return 0, 0 end
    for _, r in ipairs(h.riders) do
      if valid(r.c) and valid(h.mesh) then try(function() r.c:K2_AttachToComponent(h.mesh, r.socket, 0, 0, 0, false) end) end
    end
    if valid(h.face) and valid(h.mesh) then
      try(function() h.face:SetMasterPoseComponent(h.mesh, true) end)
      command(string.format("Q%x", addr(h.face)))
    end
    for _, k in ipairs(h.posed or {}) do
      if valid(k) and valid(h.mesh) then try(function() k:SetMasterPoseComponent(h.mesh, true) end) end
    end
    for _, e in ipairs(h.bones) do if valid(e.c) then try(function() e.c:UnHideBoneByName(FName(e.b)) end) end end
    for _, c in ipairs(h.hidden) do if valid(c) then try(function() c:SetVisibility(true, false) end) end end
    for _, e in ipairs(h.blur or {}) do if valid(e.c) then try(function() e.c.bPerBoneMotionBlur = e.was end) end end
    for _, c in ipairs(h.copies) do
      local a = addr(c)
      for i = #clones, 1, -1 do if addr(clones[i]) == a then table.remove(clones, i) end end
      if a then forced[a] = nil end
      -- (its weights let go and sbslice told it is gone, her sinks kept: "y" made it a co-owner of them)
      if valid(c) then command(string.format("x%x,0,1", a)) end
      if valid(c) then try(function() c:K2_DestroyComponent(c) end) end
    end
    return #h.roots, #h.riders
  end
  if h then return #h.roots, #h.riders end
  local roots = M.cut_parts(mesh, true)
  if #roots == 0 then return 0, 0 end
  local idx = {}
  for _, b in ipairs(roots) do
    local i = try(function() return mesh:GetBoneIndex(FName(b)) end)
    if i and i >= 0 then idx[#idx + 1] = string.format("%x", i) end
  end
  if #idx == 0 then return 0, 0 end
  local c = clone_of(pawn, mesh)
  if not c then log(tag .. ": no copy for the piece cut off her"); return 0, 0 end
  h = { mesh = mesh, roots = roots, copies = { c }, bones = {}, riders = {}, hidden = {}, baked = bake or nil }
  M.pieceHid = h
  try(function() c.bNoSkeletonUpdate = true end)
  place_like(c, mesh)
  -- (off her capsule, where clone_of put it: kept while she plays, it went along with her)
  try(function() c:K2_DetachFromComponent(1, 1, 1, false) end)
  local y = command(string.format("y%x,0,%x", addr(mesh), addr(c)))
  local p = command(string.format("P%x,%x,%s", addr(mesh), addr(c), table.concat(idx, ",")))
  if y:sub(1, 9) ~= "ok copied" or p:sub(1, 8) ~= "ok piece" then
    log(string.format(tag .. ": the piece's copy failed (weights %s, pose %s): her mesh poses with the piece hidden", y, p))
    for i = #clones, 1, -1 do if addr(clones[i]) == addr(c) then table.remove(clones, i) end end
    -- y may have succeeded before the pose failed: release the copy's override before destruction.
    if valid(c) and addr(c) then command(string.format("x%x,0,1", addr(c))) end
    try(function() c:K2_DestroyComponent(c) end)
    h.copies = {}
    c = nil
  else
    try(function() c:SetHiddenInGame(false, false) end)
  end
  local face = face_of(pawn, mesh)
  local head = false
  for _, b in ipairs(roots) do head = head or b == "Bip001-Head" end
  -- a head takes her own face along, posed by the copy (a copy of the face lost her face's look and expression and
  -- its borrowed neck bone, playtest): its bones follow the copy's by name, the borrowed ones made to again ("Q")
  local fq
  if head and c and valid(face) and try(function() face:SetMasterPoseComponent(c, true); return true end) then
    h.face = face
    fq = command(string.format("Q%x", addr(face)))
  end
  -- (and on another mod's copies of her mesh on her pose, which carry her cut weights: M.copies)
  local hide_on = { mesh }
  if not h.face and valid(face) then hide_on[#hide_on + 1] = face end
  for _, k in pairs(M.copies.of[addr(mesh)] or {}) do if valid(k) then hide_on[#hide_on + 1] = k end end
  for _, b in ipairs(roots) do
    for _, m in ipairs(hide_on) do
      if valid(m) and try(function() return m:GetBoneIndex(FName(b)) end) ~= -1
        and try(function() m:HideBoneByName(FName(b), 0); return true end) then
        h.bones[#h.bones + 1] = { c = m, b = b }
      end
    end
  end
  local function under(s)
    if head and (s:find("Hair") or s:find("Head") or s:find("Face") or s:find("Ear")) then return true end
    local bone = try(function() return mesh:GetSocketBoneName(FName(s)):ToString() end) or s
    for _, b in ipairs(roots) do
      if bone == b or try(function() return mesh:BoneIsChildOf(FName(bone), FName(b)) end) == true then return true end
    end
    return false
  end
  local kids = {}
  try(function() mesh.AttachChildren:ForEach(function(_, e) kids[#kids + 1] = e:get() end) end)
  local fa = addr(face)
  for _, k in ipairs(kids) do
    local a = valid(k) and addr(k)
    local socket = a and a ~= fa and try(function() return k:GetAttachSocketName() end)
    local s = socket and try(function() return socket:ToString() end)
    if s and s ~= "None" and under(s) then
      -- (KeepRelative: the copy's bone is where hers was, the piece's place)
      if c and try(function() k:K2_AttachToComponent(c, socket, 0, 0, 0, false); return true end) then
        h.riders[#h.riders + 1] = { c = k, socket = socket }
      elseif try(function() return k:IsVisible() end) == true and try(function() k:SetVisibility(false, false); return true end) then
        h.hidden[#h.hidden + 1] = k
      end
    end
  end
  -- (her hair rides the head's sockets on her mesh, or her face, which goes along.) Her ponytail is posed by her body
  -- (SBPonytail: no animation of its own, its master her mesh): it followed her posing head back onto her neck
  -- (playtest), so it is posed by the copy meanwhile, as is any other hair part her body poses
  h.posed = {}
  if head and c then
    local hairs = hair_of(pawn)
    for _, nm in ipairs({ "SBHair", "SBPonytail", "SBPonytailShort" }) do hairs[#hairs + 1] = try(function() return pawn[nm] end) end
    local me, seen = addr(mesh), {}
    for _, k in ipairs(hairs) do
      local a = valid(k) and addr(k)
      local master = a and try(function() return k.MasterPoseComponent:Get() end)
      if a and not seen[a] and master and addr(master) == me
        and try(function() k:SetMasterPoseComponent(c, true); return true end) then
        h.posed[#h.posed + 1] = k
      end
      if a then seen[a] = true end
    end
  end
  -- no per-bone motion blur on what moved onto the copy while photo mode is on: the head went from her neck's pose to
  -- the copy's in a frame, and paused, photo mode kept that frame's blur on it (playtest: blurry, as from motion)
  h.blur = {}
  local moved = { c, h.face }
  for _, r in ipairs(h.riders) do moved[#moved + 1] = r.c end
  for _, k in ipairs(h.posed) do moved[#moved + 1] = k end
  for _, k in ipairs(moved) do
    local was = valid(k) and try(function() return k.bPerBoneMotionBlur end)
    if was == true and try(function() k.bPerBoneMotionBlur = false; return true end) then h.blur[#h.blur + 1] = { c = k, was = true } end
  end
  -- (what is hidden here, for main.lua's showing her again up close to leave alone)
  h.set = {}
  for _, k in ipairs(h.hidden) do local a = addr(k); if a then h.set[a] = true end end
  -- where each piece is on her as it goes onto the copy: it hung in the air over her in photo mode's poses, strands
  -- down to her shoulder (playtest, not known yet whether her bodies or the copy put it there)
  local at = {}
  for _, b in ipairs(roots) do
    local l = try(function() local v = mesh:GetSocketLocation(FName(b)); return vec(v.X, v.Y, v.Z) end)
    local pv = try(function() local v = mesh:GetSocketLocation(FName("Bip001-Pelvis")); return vec(v.X, v.Y, v.Z) end)
    local over = l and ctx.rag and ctx.rag.over_floor and ctx.rag.over_floor(pawn, l)
    local sim = try(function() return mesh:IsSimulatingPhysics(FName(b)) end)
    local awake = try(function() return mesh:IsAnyRigidBodyAwake() end)
    at[#at + 1] = string.format("%s at %s, %s cm over the floor, %s cm from her pelvis, simulating %s (awake any %s)", b, v3(l),
      over and string.format("%.0f", over) or "?", (l and pv) and string.format("%.0f", len(vec(l.X - pv.X, l.Y - pv.Y, l.Z - pv.Z))) or "?",
      tostring(sim), tostring(awake))
  end
  if #at > 0 then log(tag .. ": the piece on her: " .. table.concat(at, "; ")) end
  log(string.format(tag .. ": %s cut off her %s (weights %s, pose %s%s), %d part(s) riding it moved over, %d hidden",
    table.concat(roots, ", "), c and "on a copy of her mesh" or "hidden", y, p, fq and ", her face along: " .. fq or "",
    #h.riders + #h.posed, #h.hidden))
  local names = {}
  for _, r in ipairs(h.riders) do names[#names + 1] = (name_of(r.c)) .. "@" .. (try(function() return r.socket:ToString() end) or "?") end
  for _, k in ipairs(h.posed) do names[#names + 1] = name_of(k) .. " (posed)" end
  if #names > 0 then log(tag .. ": onto the copy: " .. table.concat(names, ", ")) end
  return #roots, #h.riders
end
function M.slice(pawn, mesh, hit, why, kind) return start(pawn, mesh, hit, why, kind or "limb") end
-- a rolled limb cut's further limbs (tune.gore.death.moreLimbs): each one more with that chance, at most two more,
-- queued after it; each takes the arm or thigh nearest the hit not cut yet and flies the way the first one did
function M.more_limbs(pawn, mesh, hit, why)
  if cfg().followUpCuts == false then return 0 end
  local k = math.min(math.max(tonumber((cfg().death or {}).moreLimbs) or 0, 0), 1)
  local n = 0
  while n < 2 and math.random() < k do n = n + 1 end
  if n == 0 then return 0 end
  local fly = pending and pending.fly
  for _ = 1, n do
    queued[#queued + 1] = function()
      if not valid(mesh) then return false end
      aimed = fly and { d = fly, t = os.clock() } or nil
      return start(pawn, mesh, hit, why, "limb")
    end
  end
  M.queue_gap = cfg().queueGap or 1
  log(string.format("death: %d more limb%s after it (moreLimbs %.2f)", n, n == 1 and "" or "s", k))
  return n
end
-- tune.gore.torsoLegs: whether a death's waist cut keeps her legs in her animated fall, by the blade's swing (level
-- across her: `level`, slanted: `slant`) or, with none seen, `rolled`. Returns why when it does, nil else
function M.torso_legs(blade)
  local t = cfg().torsoLegs
  if type(t) ~= "table" or t.enabled == false then return nil end
  local odds, what = tonumber(t.rolled) or 0.5, "no blade seen"
  local n = blade and blade.n and norm(blade.n)
  if n then
    local level = math.abs(n.Z) >= math.cos(math.rad(tonumber(t.levelDeg) or 30))
    odds = tonumber(level and t.level or t.slant) or (level and 0.75 or 0.35)
    what = level and "a level swing" or "a slanted swing"
  end
  local r = math.random()
  log(string.format("waist cut: legs on in the fall at %.2f odds (%s), rolled %.2f", odds, what, r))
  if r < odds then return string.format("%s, %.0f%%", what, odds * 100) end
  return nil
end
-- normal: the split plane's normal (made square to her spine, the plane goes through it), or nil for her left/right
function M.split(pawn, mesh, hit, normal, why) return start(pawn, mesh, hit, why, "split", normal) end
-- a diagonal cut (M.diag_plane) from over one shoulder to the other hip, a split of its own. side: "R", "L", or nil:
-- the shoulder on the hit's side when it landed over her waist, else the other one (the hip's end on its side); with
-- no hit, either
function M.diagonal(pawn, mesh, hit, why, side)
  if not side then
    local pel, sp = bone_loc(mesh, "Bip001-Pelvis"), bone_loc(mesh, "Bip001-Spine1")
    local head = pel and bone_loc(mesh, "Bip001-Head")
    local axis = head and norm(sub(head, pel))
    local r = axis and M.her_right(mesh, axis)
    if hit and r and sp then
      local right = dot(sub(hit, sp), r) >= 0
      if dot(sub(hit, sp), axis) < 0 then right = not right end
      side = right and "R" or "L"
    else
      side = math.random() < 0.5 and "R" or "L"
    end
  end
  return start(pawn, mesh, hit, why, "split", nil, { at = bone_loc(mesh, "Bip001-Spine1") or vec(0, 0, 0), n = vec(0, 0, 1), diag = side })
end


-- Living-hit marks keep their public state on M for preload and world cleanup.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore_hit_marks.lua")(M, {
  native = native, cfg = cfg, log = log, load_obj = load_obj,
  vec = vec, sub = sub, add = add, scale = scale, len = len, norm = norm, dot = dot, cross = cross,
  bone_loc = bone_loc, command = command, triple = triple, num = num, pick = pick, niagara = niagara, FX = FX, MARK_AT = MARK_AT,
  guards = function() return try, valid, v3 end,
})

-- ---- the killing blow as a blade ----
-- The game's hit (main.lua) gives the swing's direction and the attacker's forward: the blade moved in the plane
-- holding both, through where it hit. What that plane goes through decides the cut: the neck alone (the head's end
-- of the spine on one side, the chest on the other) is a beheading, the rest of the spine the body in two along the
-- plane (any angle: down the middle, across the waist, shoulder to hip), past the spine the arm or leg it crosses
-- nearest the hit, cut along the blade.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/blade_decision.lua")(M, {
  PARTS = PARTS, SPINE_CHAIN = SPINE_CHAIN, enemy = enemy, cfg = cfg, log = log, already_cut = already_cut,
  bone_tm = bone_tm, start = start, norm = norm, cross = cross, dot = dot, vec = vec, add = add, sub = sub,
  scale = scale, qrot = qrot, qinv = qinv, CUT_AT_DEFAULT = CUT_AT_DEFAULT, SPINE_TOL = SPINE_TOL,
  body_frame = body_frame, from_body = from_body, to_body = to_body, mark = mark,
  v3 = function() return v3 end, ctx = function() return ctx end,
  queued = function() return queued end, aimed = function() return aimed end, set_aimed = function(v) aimed = v end,
})

-- Owner tagging always sees the current lists; recovery and enemy cleanup may replace them.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore_ownership.lua")(enemy, M, function() return ctx end,
  function() return valid end,
  function() return { spawned, bleeds, later, caps, hung, trackers, decals, no_decals, cuts, queued, hid } end)
local owner_of = enemy.owner_of

local stage_step
local function stage_tick(q)
  local stage, t0 = q.stage, os.clock()
  local outer = prof
  prof = { t = t0 }
  local ok, err = xpcall(stage_step, debug and debug.traceback or tostring, q)
  mark("rest")
  local ms = (os.clock() - t0) * 1000
  M.last_stage = { t = os.clock(), what = string.format("%s stage %s %.0f ms", q.kind, stage, ms) }
  -- every stage, with how long after the cut was asked for it ran: the cut showed late after her death (twenty-fifth
  -- playtest)
  -- (only a slow one without verboseLog: one line a stage was most of a cut's log)
  -- (the anim stage, a tick each while her fall plays on, only when slow: its last is the halves' ragdoll, 53 ms once,
  -- playtest)
  if (stage ~= "anim" and ctx.tune.verboseLog) or ms >= (cfg().slowMs or 15) then
    log(string.format("%s stage %s at +%.0f ms took %.0f ms%s", q.kind, stage, (t0 - (q.t0 or t0)) * 1000, ms,
      ms >= (cfg().slowMs or 15) and ": " .. table.concat(prof, ", ") or ""))
  end
  prof = outer
  if not ok then error(err, 0) end
end
stage_step = function(q)
  if q.kind == "split" then return split_tick(q) end
  if q.stage == "cut" then
    local r = stage_cut(q)
    if r == "again" then return end
    if r then q.stage = #q.c.chains > 0 and "chains" or "caps"; q.wait = 0; return end
    pending = nil
    -- nothing came off: give the LOD back unless an earlier cut still needs it
    release_lods()
  elseif q.stage == "chains" then
    M.stage_chains(q)
    if #q.c.chains == 0 then q.stage = "caps" end
  elseif q.stage == "caps" then
    M.stage_caps(q, 1)
    q.stage, q.wait = "caps2", 0
  elseif q.stage == "caps2" then
    M.stage_caps(q, 2)
    q.stage, q.wait = "stubs", 0
  elseif q.stage == "stubs" then
    M.stage_stubs(q, 1)
    q.stage, q.wait = "stubs2", 0
  elseif q.stage == "stubs2" then
    M.stage_stubs(q, 2)
    -- (a frame's wait before the piece came off made each cut show ~50 ms later, playtest; openWait frames now)
    q.stage, q.wait = "open", cfg().openWait or 0
  else
    pending = nil
    stage_open(q)
  end
end

-- Background preparation retains the same pacing and reads live lifecycle state.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore_watch.lua")(M, {
  native = native, cfg = cfg, load_obj = load_obj, log = log, command = command, POOL_DECALS = POOL_DECALS,
  FX = FX, SFX = SFX, vox = vox, MPC_DIRTY = MPC_DIRTY, CAP_MATERIAL = CAP_MATERIAL, STUB_MESH = STUB_MESH,
  nosink_list = nosink_list, nocarry_list = nocarry_list, limbs_list = limbs_list, LIMB_ROOTS = LIMB_ROOTS,
}, function() return try, valid end, function() return ctx end, function() return pending end)

-- tm: main.lua's slow tick marker (each part's time, when the tick is slow)
function M.tick(pawn, tm)
  if cfg().enabled == false then return end
  if (ctx.tune.stains or {}).enabled == true then M.bodyBlood.clear(); M.blood_restore = nil end
  tm = tm or function() end
  native_tick()
  M.lod_guard()
  M.bodyBlood.restore(pawn)
  M.bodyBlood.tick()
  tm("gore blood")
  pools_tick()
  tm("gore pools")
  lids_tick()
  tm("gore lids")
  -- Timers continue at gore-tick speed. Ready impact work is serviced one item per render frame by pump().
  for i = #later, 1, -1 do
    local l = later[i]
    l.n = l.n - 1
    if l.n <= 0 and not M.impactSteps[l.label] then
      table.remove(later, i)
      local t0 = os.clock()
      local ok, err = pcall(enemy.run, owner_of(l), l.fn)
      local ms = (os.clock() - t0) * 1000
      if ms >= 10 then log(string.format("delayed step %s took %.0f ms", l.label or "other", ms)) end
      if not ok then log("delayed step failed: " .. tostring(err)) end
    end
  end
  for i = #bleeds, 1, -1 do
    local b = bleeds[i]
    if b.left then b.left = b.left - 1 end
    if (b.left and b.left <= 0) or not valid(b.comp) then
      if valid(b.comp) then try(function() b.comp:Deactivate() end) end
      table.remove(bleeds, i)
    elseif b.every then
      b.n = b.n + 1
      if b.n % b.every == 0 then b.ready = (b.ready or 0) + 1 end
    end
  end
  for i = #enemy.shrink, 1, -1 do
    local x = enemy.shrink[i]
    local k = 1 - (os.clock() - x.t0) / x.over
    if k <= 0 or not enemy.alive(x.a) then
      table.remove(enemy.shrink, i)
      if enemy.alive(x.a) then try(function() x.a:K2_DestroyActor() end) end
    else
      try(function() x.a:SetActorScale3D({ X = x.s.X * k, Y = x.s.Y * k, Z = x.s.Z * k }) end)
    end
  end
  tm("gore later, bleeds")
  if limb_watch then
    local w = limb_watch
    w.n = w.n + 1
    if w.n == 30 or w.n == 150 then
      if valid(w.mesh) then
        log(string.format("cut stretch, %s at %.0f s: %s", w.bone, w.n * TICK_S, stretch_report(w.mesh, w.n == 150 and 3 or nil)))
        if #w.kept > 0 and w.anchor then log(string.format("cut chains, %s at %.0f s: %s", w.bone, w.n * TICK_S, chain_reach(w.mesh, w.kept, w.anchor))) end
      end
      if w.n == 150 then limb_watch = nil end
    elseif not valid(w.mesh) then
      limb_watch = nil
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
        -- (at 2 s her half's skin to probe1.obj, the copy's to probe2.obj, and what rides the copy: to tell a stub or
        -- a cap off where it should be from the skin)
        for k, h in ipairs({ { "her half", w.her }, { "copy", w.comp } }) do
          if valid(h[2]) then log(string.format("split stretch, %s at %.1f s: %s", h[1], w.n * TICK_S, stretch_report(h[2], w.n == 60 and k or nil))) end
        end
        if w.n == 60 then
          local out = {}
          try(function()
            w.comp.AttachChildren:ForEach(function(_, e)
              local c = e:get()
              local o = valid(c) and try(function() return c:GetOwner() end)
              local l = valid(c) and try(function() local v = c:K2_GetComponentLocation(); return vec(v.X, v.Y, v.Z) end)
              local sc = valid(c) and try(function() local v = c:K2_GetComponentScale(); return vec(v.X, v.Y, v.Z) end)
              out[#out + 1] = string.format("%s on %s at %s scale %s", valid(o) and (try(function() return o:GetName() end) or "?") or "?",
                try(function() return c:GetAttachSocketName():ToString() end) or "?", v3(l), v3(sc))
            end)
          end)
          log(string.format("split copy at 2.0 s: pelvis at %s, %d things on it: %s", v3(bone_loc(w.comp, "Bip001-Pelvis")), #out, table.concat(out, "; ")))
        end
        log(string.format("split helpers off their parents at %.1f s: her half %s | copy %s", w.n * TICK_S,
          helper_drift(w.her, w.helpers.her), helper_drift(w.comp, w.helpers.copy)))
        if w.n == 60 then copy_watch = nil end
      end
    end
  end
end

-- The scheduler reads current queues after callbacks because recovery may replace them.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore_scheduler.lua")(M, enemy, cfg,
  function() return try, valid end, function() return later, bleeds, cuts, queued, pending end,
  function() return pending end, function(q) pending = q end, owner_of, stage_tick, release_lods, log)

-- an early cut's (h.early) further cuts of the blow and her sword's, held till her death (main.lua's gore_cut)
M.held = {}
function M.release_held()
  for _, f in ipairs(M.held) do queued[#queued + 1] = f end
  local n = #M.held
  M.held = {}
  local sw = M.held_sword
  M.held_sword = nil
  if sw and valid(sw.mesh) and ctx.rag and ctx.rag.weapon_cut then
    local hn = sw.hand and bone_tm(sw.mesh, "Bip001-R-Hand")
    if hn then sw.at, sw.n = add(hn.t, qrot(hn.q, sw.hand.at)), qrot(hn.q, sw.hand.n) end
    local ok, err = pcall(ctx.rag.weapon_cut, sw.mesh, sw.at, sw.n, M.blocking)
    if not ok then log("weapon cut: " .. tostring(err)) end
  end
  return n
end

-- the killing blow's wound, the moment her HP bar hits 0 (main.lua): blood and the slice where the blade met her,
-- before the death is even reported (the ragdoll key comes 0.2-0.5 s later, and the cut opens a few frames after it:
-- the hit and the cut were far apart, playtest)
-- (sound: the sound kind, "cut" by default; a blunt blow's "crunch")
function M.wound(pawn, mesh, at, sound)
  if cfg().enabled == false or not at then return end
  -- the death's floor blood is needed seconds from now: ask the async loader for any of it not already
  -- rooted, so an early death doesn't pay a full object scan per pool (asking is hitch-free; already
  -- pending requests are left to their timeout so a broken async delivery still falls back to sync)
  if native.state == "ready" then
    local paths = { POOL_DECALS[1], POOL_DECALS[2] }
    if M.niagaraBlood then paths[#paths + 1], paths[#paths + 2] = M.SMASH_BLOOD, M.SMASH_GRINDER end
    for _, path in ipairs(paths) do
      if not native.rooted[path] and not native.async.pending[path] then
        try(function() native.async_load(path, pawn) end)
      end
    end
  end
  M.on_hit(pawn, mesh, at)
  -- Aside: the wound's layer must neither hold back the cut that may follow it nor be held back by one.
  -- Without this the opening sound fell inside the apart window of the wound and was dropped, leaving the next
  -- cut's sound to read as heavily late after this cut.
  sfx(sound or "cut", pawn, at, nil, nil, true)
end

function M.full_smash_active(mesh)
  local a = addr(mesh)
  if not a then return false end
  if pending and pending.fullSmash and addr(pending.mesh) == a then return true end
  for _, c in ipairs(cuts) do if c.addr == a and c.fullSmash then return true end end
  return false
end
function M.on_hit(pawn, mesh, at)
  if cfg().enabled == false or cfg().blood == false then return end
  niagara(FX.hit, pawn, nil, at, false)
  if cfg().hitSplat ~= false then
    local life = cfg().splatLife or 30
    later[#later + 1] = { n = 2, label = "hit splat", fn = function()
      if valid(pawn) and cfg().blood ~= false and not M.full_smash_active(mesh) then M.splat(pawn, at, life) end
    end }
  end
end

-- once the body has settled, leave a pool under it
function M.on_settled(pawn, mesh)
  if cfg().enabled == false or cfg().pool == false then return end
  if M.full_smash_active(mesh) then return end
  -- A small stump, stray splat or chunk pool does not replace the main-body pool.
  -- An existing torso-sized opening already supplies it, so avoid stacking another large decal there.
  local bodyRadius = pool_radius("body") * (cfg().poolScale or 1)
  for _, k in ipairs(trackers) do
    if k.pawn == pawn and k.bone ~= "smash chunk" and k.rmax >= bodyRadius then shield(mesh); return end
  end
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
  local keep, saved = {}, nil
  for _, c in ipairs(cuts) do if c.bone == "split" and c.saved then saved = c end end
  for _, c in ipairs(cuts) do
    if c.bone == "split" or c.bone == "split copy" then
      -- (after her arm cuts: hers back as saved, the copy's split sinks with hers; "x" on either would take the arm's)
      if saved then
        if c == saved and valid(c.mesh) and addr(c.mesh) == c.addr then
          log("split undone, her arm cuts kept: " .. command(string.format("R%x,0,%x", c.addr, c.copy or 0)))
        elseif c.bone == "split copy" and valid(c.mesh) and addr(c.mesh) == c.addr then
          -- R restores the original component; the copy still owns its own render override.
          command(string.format("x%x,0,1", c.addr))
        end
      elseif valid(c.mesh) and addr(c.mesh) == c.addr then command(string.format("x%x,0", c.mesh:GetAddress())) end
    else keep[#keep + 1] = c end
  end
  cuts = keep
  restore_rehomed()
  M.rig_back()
  for _, c in ipairs(clones) do
    local a = addr(c)
    if a then forced[a] = nil end
    if valid(c) then try(function() c:K2_DestroyComponent(c) end) end
  end
  clones = {}
  copy_watch, limb_watch = nil, nil
  if #cuts == 0 then command("r") end
  release_lods()
end

-- undo everything before she is reused (respawn / sandbox recover)
local function cleanup_eve(pawn, mesh, theirs)
  M.bodyBlood.down()
  local nd = pools_clear()
  if nd > 0 then log(string.format("removed %d floor blood decals", nd)) end
  pending = nil
  queued = {}
  M.held, M.held_sword, M.blocking = {}, nil, nil
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
  skinned = {}
  local nh = 0
  for _, pc in ipairs(hung) do
    if valid(pc) then try(function() pc:BreakConstraint() end); try(function() pc:K2_DestroyComponent(pc) end); nh = nh + 1 end
  end
  hung = {}
  M.rig_back()
  if ctx.reset_pairs and valid(mesh) then try(function() ctx.reset_pairs(mesh) end) end
  if #cuts == 0 then
    if n > 0 then log(string.format("removed %d blood effects", n)) end
    release_lods()
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
  local ns = M.smashed.back()
  if ns > 0 then steps[#steps + 1] = string.format("smashed(%d)", ns) end
  local nc = 0
  for _, c in ipairs(clones) do
    local a = addr(c)
    if a then forced[a] = nil end
    if valid(c) then try(function() c:K2_DestroyComponent(c) end); nc = nc + 1 end
  end
  clones = {}
  copy_watch, limb_watch = nil, nil
  if nc > 0 then steps[#steps + 1] = string.format("copies(%d)", nc) end
  if nh > 0 then steps[#steps + 1] = string.format("chains(%d)", nh) end
  -- the collapsed helper bones live on the mesh asset, which outlives a destroyed component. A cut enemy's corpse
  -- still rides its own asset's sinks (and the BoneMap entries every cut borrows): then only her assets'
  local rs = {}
  if #theirs.cuts == 0 then
    rs[1] = "r"
  else
    local done_sm = {}
    for _, c in ipairs(cuts) do
      if c.sm and not done_sm[c.sm] then
        done_sm[c.sm] = true
        rs[#rs + 1] = string.format("r%x", c.sm)
      end
    end
  end
  -- (a regrow's copy still fading out over her rides them: put back once it is gone, M.ghost_end)
  if M.sinksHeld then
    M.sinksHeld.cmds = rs
    if #rs > 0 then steps[#steps + 1] = "sinks(held for the dissolve's copy)" end
  else
    for _, r in ipairs(rs) do steps[#steps + 1] = "sinks(" .. command(r) .. ")" end
  end
  cuts = {}
  -- the face, when a head came off (an enemy's cut mesh keeps its LOD)
  local keep_lod = {}
  for _, c in ipairs(theirs.cuts) do keep_lod[c.addr or 0] = true end
  for a, comp in pairs(forced) do
    if not keep_lod[a] then
      if valid(comp) and comp ~= mesh then M.lod0(comp, false) end
      forced[a] = nil
    end
  end
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
  if c and valid(c.cap) and c.capResp then step("capsule", function() c.cap:SetCollisionResponseToChannel(5, c.capResp) end) end
  if c and valid(c.hair) and c.hairResp then step("hair", function() c.hair:SetCollisionResponseToChannel(5, c.hairResp) end) end
  later = {}
  if valid(mesh) then
    step("lod", function() M.lod0(mesh, false) end)
    -- recreating the physics state brings back the broken constraint; a body still simulating then keeps
    -- simulating on its own after recovery (a leg left lying on the floor), so stop simulation first
    step("physics", function()
      mesh:SetAllBodiesSimulatePhysics(false)
      mesh:SetSimulatePhysics(false)
      -- the outfit's own asset, or the one physfix gave a mesh without one (the mesh's own is none then)
      local pa = ctx.physics_of(mesh)
      if pa then mesh:SetPhysicsAsset(pa, true) end
    end)
  end
  -- her joints are whole again: nothing of her is cut off any more (active.lua's severed bones)
  if ctx.on_mended and valid(mesh) then try(function() ctx.on_mended(mesh) end) end
  log(string.format("undid cut of %s: %d caps, %d effects, %s", table.concat(bones, ","), k, n, table.concat(steps, " ")))
end

-- an enemy's items set aside while her recovery runs, then put back
local function aside(l)
  local mine, theirs = {}, {}
  for _, x in ipairs(l) do if owner_of(x) then theirs[#theirs + 1] = x else mine[#mine + 1] = x end end
  return mine, theirs
end
local function merge(l, more) for _, x in ipairs(more) do l[#l + 1] = x end end
function M.cleanup(pawn, mesh)
  for a, c in pairs(M.weddingCloth) do
    if valid(c.mesh) and addr(c.mesh) == a then try(function() c.mesh.ClothBlendWeight = c.old end) end
  end
  M.weddingCloth = {}
  M.clear_marks()
  -- (a piece lying on its copy back on her first: its bones stayed hidden on her, the regrown arm unseen)
  if M.pieceHid then M.hide_pieces(nil, nil, false) end
  local t = {}
  spawned, t.spawned = aside(spawned)
  bleeds, t.bleeds = aside(bleeds)
  later, t.later = aside(later)
  caps, t.caps = aside(caps)
  hung, t.hung = aside(hung)
  trackers, t.trackers = aside(trackers)
  decals, t.decals = aside(decals)
  no_decals, t.no_decals = aside(no_decals)
  cuts, t.cuts = aside(cuts)
  queued, t.queued = aside(queued)
  hid, t.hid = aside(hid)
  local theirs_pending = pending and pending.owner and pending
  if theirs_pending then pending = nil end
  local ok, err = pcall(cleanup_eve, pawn, mesh, t)
  merge(spawned, t.spawned); merge(bleeds, t.bleeds); merge(later, t.later); merge(caps, t.caps); merge(hung, t.hung)
  merge(trackers, t.trackers); merge(decals, t.decals); merge(no_decals, t.no_decals); merge(cuts, t.cuts)
  merge(queued, t.queued); merge(hid, t.hid)
  pending = pending or theirs_pending
  if not ok then error(err, 0) end
end

-- Regrowth reads current cut, copy and LOD state; cleanup can replace those lists.
dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore_regrow.lua")(M, cfg, load_obj,
  function() return try, valid end, function() return cuts end, function() return clones end,
  function() return forced end, owner_of, addr, clone_of, name_of, command, log)

-- ---- enemies (enemies.lua) ----
-- a cut on an enemy's corpse: along the blade when the blow gives one (gore.blow, never a split), else kind ("limb",
-- "head", "torso", or "mark": no cut, a hit mark where it landed); h: { loc, dir, fwd, n, how, push, bone }. Returns
-- what it started, or nil
function M.enemy_cut(owner, pawn, mesh, h, kind, faced)
  if faced then enemy.faced[owner] = true end
  return enemy.run(owner, function()
    if pending then return nil end
    h = h or {}
    M.aim(h.push or h.dir)
    -- (M.blow knows an enemy is never split; h.noSplit, a body already cut, kept its body cuts along the blade off:
    -- a level swing through its waist rolled the odds)
    if kind ~= "mark" and (h.n or (h.dir and h.fwd)) and h.loc then
      if M.blow(pawn, mesh, h, "enemy") then return "blade" end
      if pending then return nil end
    end
    if kind == "mark" then return M.hit_mark(pawn, mesh, h.loc, h.dir, nil) and "mark" or nil end
    return start(pawn, mesh, h.loc, "enemy", kind or "limb") and (kind or "limb") or nil
  end)
end
-- the hit's blood where an enemy was struck, its effects tagged to it (they go with its corpse)
function M.enemy_hit(owner, pawn, mesh, at) return enemy.run(owner, M.on_hit, pawn, mesh, at) end
-- the bones cut off an enemy so far (and the one opening): their parts are off its body
function M.enemy_off(owner)
  local off = {}
  for _, c in ipairs(cuts) do if enemy.owned[c] == owner and c.bone then off[c.bone] = true end end
  if pending and pending.owner == owner and pending.bone then off[pending.bone] = true end
  return off
end
-- the cuts made on an enemy so far, and whether one is still opening or queued (the killing blow's multiCut)
function M.enemy_cuts(owner)
  local n, q = 0, false
  for _, c in ipairs(cuts) do if enemy.owned[c] == owner then n = n + 1 end end
  for _, f in ipairs(queued) do if enemy.owned[f] == owner then n, q = n + 1, true end end
  return n, q or (pending ~= nil and pending.owner == owner)
end
-- an enemy's corpse goes (destroyed, hidden for reuse, or up again): everything its cuts left goes with it. how:
-- nil, the corpse stays (its weights are taken off); "destroyed", its actor is being destroyed (its components and
-- weights go with it); "vanished", its object is already gone from the game's list (nothing of it is touched, its
-- memory may be freed: only this script's own caps and floor decals are removed). Its kind's sinks are put back once
-- no cut corpse of that kind is left (r<asset>), and everything (the borrowed BoneMap entries too) once no cut at all is
function M.enemy_gone(owner, mesh, how)
  local gone, lost = how ~= nil, how == "vanished"
  local nc, nf = 0, 0
  local sms = {}
  local function drop(l, fn)
    local keep = {}
    for _, x in ipairs(l) do
      if enemy.owned[x] == owner then
        if fn then try(function() fn(x) end) end
      else keep[#keep + 1] = x end
    end
    return keep
  end
  spawned = drop(spawned, function(c)
    if not lost and enemy.alive(c) then c:Deactivate(); c:K2_DestroyComponent(c); nf = nf + 1 end
  end)
  bleeds = drop(bleeds)
  later = drop(later)
  queued = drop(queued)
  hid = drop(hid)
  trackers = drop(trackers)
  caps = drop(caps, function(a) if enemy.alive(a) then a:K2_DestroyActor(); nc = nc + 1 end end)
  hung = drop(hung, function(pc) if not lost and enemy.alive(pc) then pc:BreakConstraint(); pc:K2_DestroyComponent(pc) end end)
  decals = drop(decals, function(d) if enemy.alive(d) then d:K2_DestroyComponent(d) end end)
  no_decals = drop(no_decals, function(e)
    if not gone and valid(e.comp) and addr(e.comp) == e.addr then e.comp:SetReceivesDecals(e.was ~= false) end
  end)
  local bones, faces = {}, {}
  cuts = drop(cuts, function(c)
    if c.bone == "face" then faces[#faces + 1] = c else bones[#bones + 1] = c.bone end
    if c.sm then sms[c.sm] = true end
  end)
  enemy.faced[owner] = nil
  enemy.faded[owner] = nil
  if pending and pending.owner == owner then pending = nil end
  -- (a destroyed actor's memory is still there until the next garbage collection: enemies.lua polls every tick)
  local a = mesh and addr(mesh) -- (GetAddress reads nothing of the object)
  if limb_watch and (gone or limb_watch.mesh == mesh) then limb_watch = nil end
  local steps = {}
  if a and forced[a] then
    if not gone and valid(forced[a]) then M.lod0(forced[a], false) end
    forced[a] = nil
  end
  if a and not gone and valid(mesh) then steps[#steps + 1] = "weights(" .. command(string.format("x%x,0,1", a)) .. ")" end
  -- an Eve-built enemy's face, cut whole with its head
  for _, c in ipairs(faces) do
    if forced[c.addr] then
      if not gone and valid(forced[c.addr]) then M.lod0(forced[c.addr], false) end
      forced[c.addr] = nil
    end
    if not gone and valid(c.mesh) and addr(c.mesh) == c.addr then
      steps[#steps + 1] = "face(" .. command(string.format("x%x,0", c.addr)) .. ")"
    end
  end
  if #cuts == 0 then
    steps[#steps + 1] = "sinks(" .. command("r") .. ")"
  else
    for sm in pairs(sms) do
      local shared = false
      for _, c in ipairs(cuts) do if c.sm == sm then shared = true end end
      if not shared then steps[#steps + 1] = "sinks(" .. command(string.format("r%x", sm)) .. ")" end
    end
  end
  if #bones > 0 or nc > 0 or nf > 0 then
    log(string.format("enemy %x gone%s: cuts %s, %d caps, %d effects %s", owner, gone and (" (" .. how .. ")") or "",
      #bones > 0 and table.concat(bones, ",") or "none", nc, nf, table.concat(steps, " ")))
  end
end

-- an enemy's corpse dissolving (the game's despawn show swapped its materials): its caps, bone stubs, bleeds and
-- drips go now (they stayed in the air where it had been). Its cut weights and floor blood stay until it goes
function M.enemy_fading(owner, quiet)
  enemy.faded[owner] = true
  local nc, nf = 0, 0
  local function drop(l, fn)
    local keep = {}
    for _, x in ipairs(l) do
      if enemy.owned[x] == owner then if fn then try(function() fn(x) end) end else keep[#keep + 1] = x end
    end
    return keep
  end
  -- the caps shrink away with the dissolve (gone at once, they popped out while the body still faded)
  local over = tonumber(((ctx.tune or {}).enemies or {}).capFade) or 1.5
  caps = drop(caps, function(a)
    if not enemy.alive(a) then return end
    nc = nc + 1
    local s = over > 0 and try(function() local v = a:GetActorScale3D(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    if s then enemy.shrink[#enemy.shrink + 1] = { a = a, s = s, t0 = os.clock(), over = over }
    else a:K2_DestroyActor() end
  end)
  spawned = drop(spawned, function(c) if enemy.alive(c) then c:Deactivate(); c:K2_DestroyComponent(c); nf = nf + 1 end end)
  bleeds = drop(bleeds)
  trackers = drop(trackers)
  if not quiet or nc + nf > 0 then
    log(string.format("enemy %x %s: %d caps, %d effects removed", owner, quiet and "dissolving, a late cut's" or "dissolving", nc, nf))
  end
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

-- a float field of a loaded DataTable's row, read, and set to v when v is given (UE4SS's Lua can't reach the rows:
-- sbslice.dll's d command, the field's offset from the row struct's reflection). The value it had, or nil and why.
-- The row's name has no number (FName "X_1" would be X with number 2). Gets the DLL up itself (gore may be off)
function M.row_float(dt, row, field, v)
  native_tick()
  if native.state ~= "ready" then return nil, "sbslice " .. native.state end
  local rs = try(function() return dt.RowStruct end)
  if not valid(rs) then return nil, "no row struct" end
  local off
  try(function() rs:ForEachProperty(function(p)
    if p:GetFName():ToString() == field then off = p:GetOffset_Internal(); return true end
  end) end)
  if not off then return nil, "no field " .. field end
  local idx = try(function() return FName(row):GetComparisonIndex() end)
  if not idx then return nil, "no name " .. row end
  local s = string.format("d%x,%x,%x,0,%x", addr(dt), addr(rs), idx, off)
  if v then s = s .. string.format(",%x", string.unpack("<I4", string.pack("<f", v))) end
  local r = command(s)
  local was = r:match("^ok row %x+ (%x+) %x+$")
  if not was then return nil, r end
  return string.unpack("<f", string.pack("<I4", tonumber(was, 16) & 0xffffffff))
end

-- photo mode's activation checks skipped (on) or back (sbslice.dll's photo_cmd: the game turns photo mode down
-- while she is dead, and its cheat for the switch is a stub in the shipping build)
function M.photo(on)
  if native.state ~= "ready" then return "sbslice " .. native.state end
  return command(on and "f1" or "f0")
end

-- photo mode entered directly (the key never reaches it in a death, and the game's check says no to her dead)
-- (her mesh shielded from photo mode's collision switch, which ended her ragdoll: sbslice.dll's photo_shield)
-- photo mode's manager as it is now ("ok photo state: mgr 38=.. 84=.. ...", 84 not 0 while photo mode is on); with her
-- actor, " own=1" too while photo mode's own option hides her
function M.photo_state(actor)
  if native.state ~= "ready" then return "sbslice " .. native.state end
  local a = actor and addr(actor)
  return command(a and string.format("f3%x", a) or "f3")
end
function M.photo_open(mesh)
  if native.state ~= "ready" then return "sbslice " .. native.state end
  local a = mesh and addr(mesh)
  return command(a and string.format("f2%x", a) or "f2")
end
-- her mesh shielded alone ("ok photo shield 1"), once a piece is off her: the game's own key opens photo mode too
function M.photo_shield(mesh)
  if native.state ~= "ready" then return "sbslice " .. native.state end
  local a = mesh and addr(mesh)
  return a and command(string.format("f4%x", a)) or "err no mesh"
end
-- photo mode's hiding of its subjects (up close among its reasons) off (true) or back to the game's (false): sbslice
-- patches the jumps that hide them
function M.photo_close(keep)
  if native.state ~= "ready" then return "sbslice " .. native.state end
  return command(keep and "f61" or "f60")
end
-- what hides her, read natively without calling anything (sbslice f9): her bHidden, SBCharacter's hide flags, photo
-- mode's manager state ("ok vis hidden=.. 3040=.. ... 84=.. 48=..")
function M.vis(pawn)
  if native.state ~= "ready" then return "sbslice " .. native.state end
  local a = pawn and addr(pawn)
  return a and command(string.format("f9%x", a)) or "err no actor"
end
-- and back on its own (no piece off her any more)
function M.photo_unshield()
  if native.state ~= "ready" then return "sbslice " .. native.state end
  return command("f5")
end

function M.state() return native.state end

-- a new Eve (the level reloaded after a death): drop every object held from the old one without touching it. Its
-- memory may be gone, and UE4SS's IsValid reads it: the first tick after the reload crashed the game.
-- pawn: the new Eve. Her old cuts' collapsed helper bones (sbslice's sinks) are her mesh assets' own, which outlive
-- the level: the ones on an asset the new Eve wears (her body, her face, an outfit's glove or sleeve mesh) are put back
-- (a fast travel or a load with an arm cut off her alive, Lose Arm at Low HP: else the new Eve showed the arm gone with
-- nothing cut). Only those, by asset: the DLL drops its records of an asset gone with the old level by itself
-- (assets_prune), and one of an enemy kind still around stays on its corpses' records till they go
function M.forget(pawn)
  M.outfit_forget()
  M.weddingCloth = {}
  M.stubs = {}
  local wears = {}
  if pawn and native.state == "ready" then
    local comps = {}
    try(function() comps[1] = pawn.Mesh end)
    try(function()
      for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.SkeletalMeshComponent"))) do comps[#comps + 1] = c end
    end)
    for _, c in ipairs(comps) do
      local sm = valid(c) and enemy.asset(c)
      if sm then wears[sm] = true end
    end
  end
  local put = {}
  local function put_back(sm, why)
    if put[sm] then return end
    put[sm] = true
    log(string.format("the level reloaded %s: sinks put back on mesh asset %x: %s", why, sm, command(string.format("r%x", sm))))
  end
  for _, c in ipairs(cuts) do
    if c.sm and wears[c.sm] and not owner_of(c) then put_back(c.sm, "with a cut on her (" .. tostring(c.bone) .. ")") end
  end
  -- (or mid regrow, the sinks held for its copy fading out: M.ghost_end won't come. "r" alone held: every asset of hers)
  local h = M.sinksHeld
  for _, r in ipairs(h and h.cmds or {}) do
    local sm = r:match("^r(%x+)$")
    sm = sm and tonumber(sm, 16)
    if sm and wears[sm] then put_back(sm, "as a regrow's copy faded")
    elseif r == "r" then for w in pairs(wears) do put_back(w, "as a regrow's copy faded") end end
  end
  spawned, bleeds, caps, cuts, forced, clones, rehomed = {}, {}, {}, {}, {}, {}, {}
  later, hung, queued, skinned, hid = {}, {}, {}, {}, {}
  M.held, M.held_sword, M.blocking, M.pieceHid, M.photoHid = {}, nil, nil, nil, nil
  M.sinksHeld = nil
  bleed_logged = false
  pending, collision_saved, self_saved, copy_watch, limb_watch = nil, nil, nil, nil, nil
  enemy.owned, enemy.cur, enemy.faced, enemy.faded, enemy.shrink = setmetatable({}, { __mode = "k" }), nil, {}, {}, {}
  M.assets.forget()
  bone_lists.clear()
  -- a collection's values live in the old world, which is gone with them
  -- (but the collection itself outlives her: the respawned Eve kept the death's blood all over her skin, reported.
  -- Its values from before the death are put back through the new one, on her first tick)
  M.bodyBlood.forget()
  stub_dims, M.bloodTintApplied = nil, nil
  decals, trackers, no_decals, M.drips = {}, {}, {}, {}
  M.mk.list = {}
  -- the pool's cap and stub actors and the split copies were the old level's: asking them anything read freed memory
  M.pool.lid, M.pool.core, M.pool.plain = {}, {}, {}
  -- Guarded assets are rooted package objects, not actors from the old world.
  -- Retain their identity guards across a level change; load_obj still checks
  -- the native object array before reusing a wrapper and replaces stale ones.
  M.copies.of, M.copies.dirty = {}, {}
  -- (the bones a smash or a carried cut hid were the old level's meshes')
  M.smashed.bones, M.smashed.shown = {}, {}
end

return M
