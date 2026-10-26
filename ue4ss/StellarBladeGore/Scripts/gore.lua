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
-- Blood: the game's own Niagara systems, spawned on hits, on the cut (a pulsed bleed out of each opening) and as
-- floor drips and pools; the game's gore sounds play on cuts; a hit she lives through leaves a mark (hit_mark). Caps and lids use the game's meat material.
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
-- a vertical split: the body and face are cloned, each copy keeps one side of a plane through the spine (MODE_SIDE)
-- and the copy becomes its own ragdoll. The face's eyes, teeth and brows only know the head bone, so its vanished
-- side collapses onto a borrowed bone no face vertex uses (Spine1), made to follow the head
local SPLIT_SINK = "Bip001-Spine1"
local SPLIT_RIDE = { "Bip001-Head", "Bip001-Neck", "Bip001-Spine2", "Bip001-Spine1", "Bip001-Spine", "Bip001-Pelvis" }
-- the ones a half's lid and sheet may ride: never a bone that half lets go of (settle_half: the copy's head, the
-- other end of a broken spine), which falls free and spins, and the lid stretched after it in tall flashing sheets
-- (ragdoll deaths, playtest 26). q.spine: where the spine breaks (her half keeps it and what is above it); q.spine2:
-- where the copy's does (it lets go of that and what is above it)
function SPLIT_RIDE.of(q, comp)
  local copy = comp ~= q.mesh
  local s, si, list = copy and (q.spine2 or q.spine) or q.spine, nil, {}
  for i, b in ipairs(SPLIT_RIDE) do if b == s then si = i end end
  for i, b in ipairs(SPLIT_RIDE) do
    local ok = not si or (copy and i > si) or (not copy and i <= si)
    if copy and b == "Bip001-Head" and not (q.spine and q.spine ~= b) then ok = false end
    if ok then list[#list + 1] = b end
  end
  return #list > 0 and list or SPLIT_RIDE
end
-- the ones a half's lid bends with, and the sheet behind it (sbslice's bands): never the head. The points by the neck
-- turned fully with it, and as the head flopped in her ragdoll they fanned out of her in long spikes, where the
-- neck's skin follows it only in part (playtest)
function SPLIT_RIDE.lid(q, comp)
  local list = {}
  for _, b in ipairs(SPLIT_RIDE.of(q, comp)) do if b ~= "Bip001-Head" then list[#list + 1] = b end end
  return #list > 0 and list or SPLIT_RIDE.of(q, comp)
end
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
  -- the bleed: the flesh-slice effect without its meat stub (red, a cone in the effect's own space), fired again in
  -- pulses (tune.gore.bleedPulse). NS_Blood_Flooded_Attached, the bleed before, locks its emission to a fixed axis
  -- (SBLockAxis) whatever it is turned to: every spurt went the same wrong way
  bleed = "/Game/Art/FX/Char/Common/Hit/Flesh/NS_Hit_Flesh_Slice_BloodOnly.NS_Hit_Flesh_Slice_BloodOnly",
  -- red blood: the monster hit and its decal (NS_HitBlood_Monster_01_*, NS_HitBlood_SpawnDecal_L) are the Naytiba's
  -- glowing orange liquid (MI_A_EmissiveLiquid, EnemyCommon/MI_ParBloodDecal); Eve's own hit blood and the flesh
  -- decal use MI_A_DefaultBlood and the common decal, like the bleed
  hit = "/Game/Art/FX/Char/Common/Hit/PC/NS_HitBlood_PC_01.NS_HitBlood_PC_01",
}
-- the game's own gore sounds (sound cues, played where it happens): each kind has a few sets of cues from the same
-- family (the slice of a Naytiba's limb, a boss finisher's gore splash, a power hit's blood),
-- one set per event, never one with a cue that played in the last few seconds (a cue that is still playing drops its
-- next start: an arm cut right after a thigh's was silent, sixteenth playtest). The finishers' bass-heavy gore layers
-- (Boss_Gore, Crawler, Quadruped) were too much
local SFX
do -- (a block: the main chunk is near Lua's 200 locals)
local function cue(p) return "/Game/Sound/Character/" .. p .. "." .. p:match("([^/]+)$") end
local L = "Skill/Link/Boss/"
local SLICE_BIG, SLICE_SMALL = cue("Hit/Slice/Mon_slice_Big_Cue"), cue("Hit/Slice/Mon_slice_Small_Cue")
local SPLASH, BLOOD = cue(L .. "PC_LinkAttack_Boss_Gore_Splash_Cue"), cue("Hit/hit_Linkskill_Blood_01_Cue")
-- a smash (tune.gore.smash): a blunt crunch as the blow lands (crunch, at the lethal hit), then the meat bursting out
-- (smash): here the finishers' bass-heavy gore fits
local CRUNCH, THUD = cue("Hit/PCHitSound/Common/CSS_HIT_Blunt_Strong_Common_Cue"), cue("Hit/Result_Hit_Stand_Blunt_StrongAttack_Cue")
local GORE, POWER = cue(L .. "Crawler/PC_LinkAttack_Crawler_Gore_Impact_Cue"), cue("Hit/hit_common_blood_power_00_Cue")
SFX = {
  cut = { { SLICE_BIG }, { SLICE_SMALL }, { SLICE_SMALL, BLOOD } },
  big = { { SLICE_BIG, SPLASH }, { SLICE_SMALL, SPLASH }, { SLICE_BIG, BLOOD } },
  crunch = { { CRUNCH }, { THUD } },
  smash = { { GORE, POWER }, { SPLASH, CRUNCH }, { GORE, THUD } },
}
end
local SFX_GAP = 3.0 -- s a cue rests after it played
-- cue path -> os.clock() it last played; any: the last gore sound. Gore sounds are apart s apart at least: a swing
-- cutting a corpse three or four times in a second played each cut's pair of cues over the last (playtest: doubled
-- sounds on enemies)
local sfx_last = { apart = 0.35, any = -1e9 }

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
local cache = {}

local function cfg() return ctx.tune.gore or {} end
local function log(s) ctx.log("gore: " .. s) end
local try, valid, v3 = nil, nil, nil

local function file_exists(p) local f = io.open(p, "r"); if f then f:close(); return true end; return false end
local function read_file(p) local f = io.open(p, "r"); if not f then return nil end; local s = f:read("a"); f:close(); return s end

local function load_obj(path)
  -- nothing roots the Niagara systems once their components are cleaned up, so GC frees them; a cached
  -- wrapper then points at a dead object (crash on the next death's blood spawn). Checking the cached wrapper wasn't
  -- enough: a freed object's address gets reused, IsValid then passes on whatever lives there now, and a sound cue
  -- read that way crashed PlaySoundAtLocation (attenuation pointer 0x1, eighteenth playtest's F11). Found by path
  -- every time instead
  local o = try(function() return StaticFindObject(path) end)
  -- not from the pak around a respawn (ctx.may_load): a load then waited on the level's own loading, whose new
  -- objects wait on the Lua lock the tick holds (an endless loading screen, Nexus report); found next time instead
  if not valid(o) and not ctx.may_load() then return nil end
  if not valid(o) and LoadAsset then o = try(function() return LoadAsset(path) end) end
  if not valid(o) then o = try(function() return StaticFindObject(path) end) end
  cache[path] = valid(o) and o or false
  if not valid(o) then log("could not load " .. path) end
  -- an asset (not a native class or default object) stays loaded from now on: see native.root
  if valid(o) and path:sub(1, 8) ~= "/Script/" and native.root then native.root(path, o) end
  return valid(o) and o or nil
end

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

-- a stump seam is weighted to a helper, and that helper keeps moving after the cut (a thigh twist, Ab-AX3T, a knee
-- driver): the opening's point swings out and the cut face cones. "H" rewrites the collapse point onto the rim's bone.
-- No result file — reading one every frame is what stuttered. Her own tick calls this, before the mesh is posed.
-- The cheat CDO it calls on is kept in native.hold_cdo (this chunk is at Lua's 200-local limit)
function M.hold_seams()
  if native.state ~= "ready" or #cuts == 0 then return end
  local ok, err = pcall(function()
    local list = {}
    for _, c in ipairs(cuts) do
      if valid(c.mesh) and try(function() return c.mesh:GetAddress() end) == c.addr then list[#list + 1] = string.format("%x", c.addr) end
    end
    if #list == 0 then return end
    if not valid(native.hold_cdo) then native.hold_cdo = load_obj(CHEAT_CDO) end
    if not native.hold_cdo then return end
    native.hold_cdo:SBRewardGroupDropFormationPathLocation(FName("None"), 0, 0, 0, "H" .. table.concat(list, ","), 0, 0, 0)
  end)
  if not ok then native.hold_cdo = nil; log("seam hold failed: " .. tostring(err)) end
end

function M.native_ready() return native.state == "ready" end
-- a command with no answer file (active.lua's eased grip, sent every tick: reading an answer each time stuttered)
function M.fire(s)
  if native.state ~= "ready" then return end
  local ok, err = pcall(function()
    if not valid(native.hold_cdo) then native.hold_cdo = load_obj(CHEAT_CDO) end
    if native.hold_cdo then native.hold_cdo:SBRewardGroupDropFormationPathLocation(FName("None"), 0, 0, 0, s, 0, 0, 0) end
  end)
  if not ok then native.hold_cdo = nil; log("sbslice " .. s:sub(1, 1) .. " failed: " .. tostring(err)) end
end

-- one command to sbslice.dll (see exec_slice there); the answer it leaves in sbslice.cut
local function command(s, p, n)
  mark("lua")
  os.remove(RESULT)
  local cdo = load_obj(CHEAT_CDO)
  if not cdo then return "err no cheat manager" end
  p, n = p or vec(0, 0, 0), n or vec(0, 0, 0)
  local t0 = os.clock()
  local ok, err = pcall(function()
    cdo:SBRewardGroupDropFormationPathLocation(FName("None"), p.X, p.Y, p.Z, s, n.X, n.Y, n.Z)
  end)
  -- a command that holds the game thread long enough to show as a stutter (the split's, eighteenth playtest)
  local ms = (os.clock() - t0) * 1000
  if ms >= (cfg().slowMs or 15) then log(string.format("sbslice %s took %.0f ms", s:sub(1, 1), ms)) end
  mark("sbslice " .. s:sub(1, 1))
  if not ok then return "err call: " .. tostring(err) end
  local r = read_file(RESULT) or "err no answer"
  -- a cut mesh's copies (M.copies) take its new weights at the end of the frame's stage, and lose them with its own
  local k = s:sub(1, 1)
  if (k == "c" or k == "x") and r:sub(1, 2) == "ok" and M.copies then
    local a = tonumber(s:match("^.(%x+)") or "", 16)
    if a and k == "c" then M.copies.dirty[a] = true elseif a then M.copies_clear(a) end
  end
  return r
end

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

-- handshake with sbslice.dll: hand it the UFunction to repoint, then wait for its answer
local function native_tick()
  if native.state == "ready" or native.state == "failed" then return end
  if native.state == "init" then
    os.remove(OK); os.remove(ERR)
    -- what sbslice.dll noted as the last session ended: a command that never finished, a crash in it or in a command
    -- (no local of its own: this chunk is at Lua's 200-local limit)
    for _, p in ipairs({ "ue4ss/Mods/StellarBladeGore/sbslice.stuck", "ue4ss/Mods/StellarBladeGore/sbslice.crash" }) do
      local note = read_file(p)
      if note then log("sbslice.dll last session: " .. note); os.remove(p) end
    end
    -- (and its own start: written from its DllMain, by its own path, for a launch that closed before the first window)
    log("sbslice.dll " .. tostring(read_file("ue4ss/Mods/StellarBladeGore/sbslice.boot") or "boot: no note (an older sbslice.dll?)"))
    local f = try(function() return StaticFindObject(UFUNC) end)
    if not valid(f) then native.state = "failed"; log("no " .. UFUNC); return end
    -- (written whole, then renamed in: the DLL polls for it and could read it half written)
    local w = io.open(REQ .. ".tmp", "w")
    if not w then native.state = "failed"; log("cannot write " .. REQ); return end
    w:write(string.format("%x", f:GetAddress())); w:close()
    os.remove(REQ)
    if not os.rename(REQ .. ".tmp", REQ) then native.state = "failed"; log("cannot write " .. REQ); return end
    native.state = "waiting"
    log(string.format("asked sbslice.dll to take over %s (UFunction %x)", UFUNC, f:GetAddress()))
    return
  end
  native.waited = native.waited + 1
  if file_exists(OK) then
    native.state = "ready"
    local ok = tostring(read_file(OK))
    -- every outfit keeps its LOD0 CPU copy (the DLL's NeedCPUData patch): physfix stops warning about the flag
    ctx.cpu_forced = ok:find("cpu copy LOD0 on", 1, true) ~= nil
    -- a reloaded script forgets its cuts, the DLL doesn't: put back anything a previous run left collapsed
    log("sbslice.dll ready: " .. ok .. ", leftovers: " .. command("r"))
  elseif file_exists(ERR) then
    native.state = "failed"
    local e = tostring(read_file(ERR))
    -- (its engine calls are at fixed addresses in the exe: another build of the game, a patch or a modified exe, has
    -- them elsewhere, and the first one isn't found)
    log("sbslice.dll refused: " .. e .. (e:find("no thunk pointer", 1, true)
      and " (this game exe isn't the Steam build sbslice.dll was made for: no cuts, and no outfit physics fix)" or ""))
  elseif native.waited > 150 then
    native.state = "failed"
    log("sbslice.dll did not answer (is Mods/SBSlice/dlls/main.dll installed, with Mods/SBSlice/enabled.txt or SBSlice : 1 in mods.txt?)")
  end
end

function M.init(c)
  ctx = c
  try, valid, v3 = c.try, c.valid, c.v3
end

-- attached: follow comp (at bone, or at world loc / rot when given: KeepWorldPosition), else a one-off at loc
-- a gore sound where it happened (tune.gore.sounds, soundVolume). Every parameter is passed: UE4SS leaves the
-- missing ones at zero, which is a silent volume
-- force: even right after another gore sound (a smash's burst a few frames after its crunch)
local function sfx(kind, pawn, at, force)
  local g = cfg()
  if g.sounds == false or not at then return end
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  if not gs then return end
  -- the sets in random order; the first with no cue still ringing, else the one whose newest cue is the oldest
  local sets, now = SFX[kind] or {}, os.clock()
  if not force and now - sfx_last.any < sfx_last.apart then return end
  sfx_last.any = now
  local order = {}
  for i = 1, #sets do order[i] = i end
  for i = #order, 2, -1 do local j = math.random(i); order[i], order[j] = order[j], order[i] end
  local pick, pick_age = nil, -1
  for _, i in ipairs(order) do
    local age = math.huge
    for _, path in ipairs(sets[i]) do age = math.min(age, now - (sfx_last[path] or -1e9)) end
    if age >= SFX_GAP then pick = i; break end
    if age > pick_age then pick, pick_age = i, age end
  end
  local played = {}
  for _, path in ipairs(pick and sets[pick] or {}) do
    local snd = load_obj(path)
    if snd then
      -- no owning actor: the cues' concurrency is per owner, so a cut right after another on her was dropped as the
      -- same sound playing again (leg cuts came out silent, fifteenth playtest)
      local ok, err = pcall(function()
        gs:PlaySoundAtLocation(pawn, snd, vec(at.X, at.Y, at.Z), { Pitch = 0, Yaw = 0, Roll = 0 }, g.soundVolume or 1.0,
          0.92 + math.random() * 0.16, 0.0, nil, nil, nil)
      end)
      if ok then
        sfx_last[path] = now
        played[#played + 1] = path:match("([^/.]+)%.[^.]+$") or path
      else
        log("sound " .. path .. ": " .. tostring(err))
      end
    else
      log("sound " .. path .. " didn't load")
    end
  end
  log(string.format("sound %s: %s", kind, #played > 0 and table.concat(played, ", ") or "none"))
end

-- ---- her voice (tune.gore.voice) ----
-- Eve's own death cry (vo_eve_die_*, SoundWaves under Sound/Dialogue/ActionVoice/Eve, localized like the game's
-- voice), once, the moment she dies. Nothing after: the screams on later cuts and the moans and last breath that
-- followed played on over her body (twentieth playtest). Any death, real or a test key's, starts it (main.lua on_start)
local vox = { last = {} } -- one local for all of it (the chunk is at its 200-local limit)
vox.DIR = "/Game/Sound/Dialogue/ActionVoice/Eve/"
vox.DIE = {}
for i = 1, 5 do
  local n = string.format("vo_eve_die_%02d_VO", i)
  vox.DIE[i] = vox.DIR .. n .. "." .. n
end
-- the recordings to pick from: tune.gore.voice.sounds (names under vox.DIR, e.g. "vo_eve_die_fall_01", or full
-- object paths of any SoundWave or SoundCue, another mod's new ones too), else vox.DIE. A mod that replaces
-- vo_eve_die_* in place is heard with no setting at all
function vox.list(v)
  if type(v.sounds) ~= "table" or #v.sounds == 0 then return vox.DIE end
  local key = table.concat(v.sounds, "|")
  if vox.key ~= key then
    vox.key, vox.paths = key, {}
    for _, s in ipairs(v.sounds) do
      s = tostring(s)
      if s:sub(1, 1) ~= "/" then s = vox.DIR .. s:gsub("_VO$", "") .. "_VO" end
      if not s:find(".", 1, true) then s = s .. "." .. s:match("([^/]+)$") end
      vox.paths[#vox.paths + 1] = s
    end
  end
  return vox.paths
end
vox.ATTENUATION = "/Game/Sound/SoundAsset/Attenuations/Character/PC_ActionVoice.PC_ActionVoice"
-- vox.last: recording -> os.clock() it last played (none twice within voice.rest s)
-- The cry is spawned on her head (it flies with a cut-off head) and kept (vox.ac): a beheading cuts it off as the
-- head comes away (vox.cut), faded over voice.cutFade s so it doesn't end in a click
-- a recording on her head (kept as vox.ac: a beheading cuts it off), else at it: ok, how
function vox.spawn(pawn, mesh, snd, vol)
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  local at = valid(mesh) and try(function()
    local x = mesh:GetSocketLocation(FName("Bip001-Head")); return { X = x.X, Y = x.Y, Z = x.Z }
  end) or try(function() local x = pawn:K2_GetActorLocation(); return { X = x.X, Y = x.Y, Z = x.Z } end)
  if not (gs and at) then return false, "nowhere" end
  local pitch, att = 0.97 + math.random() * 0.06, load_obj(vox.ATTENUATION)
  vox.ac = nil
  -- (KeepRelativeOffset 0, stopped if her mesh goes, not auto-destroyed till it ends)
  local ok, ac = pcall(function()
    return gs:SpawnSoundAttached(snd, mesh, FName("Bip001-Head"), vec(0, 0, 0), { Pitch = 0, Yaw = 0, Roll = 0 }, 0, true,
      vol, pitch, 0.0, att, nil, true)
  end)
  local how = "on her head"
  if ok and valid(ac) then vox.ac = ac
  else
    how = "at her head (" .. tostring(ac) .. ")"
    ok, ac = pcall(function()
      return gs:SpawnSoundAtLocation(pawn, snd, vec(at.X, at.Y, at.Z), { Pitch = 0, Yaw = 0, Roll = 0 }, vol, pitch, 0.0, att, nil, true)
    end)
    if ok and valid(ac) then vox.ac = ac end
  end
  return ok, ok and how or (how .. " failed: " .. tostring(ac))
end
-- one of `list` (paths), the one rested longest first: path or nil
function vox.pick(list, rest)
  local now, fresh = os.clock(), {}
  for _, path in ipairs(list) do if now - (vox.last[path] or -1e9) >= rest then fresh[#fresh + 1] = path end end
  if #fresh == 0 then fresh = list end
  return fresh[math.random(#fresh)]
end
function M.voice_death(pawn, mesh)
  local v = cfg().voice or {}
  if v.enabled == false or v.cry == false then return end
  local path = vox.pick(vox.list(v), v.rest or 8)
  local snd = path and load_obj(path)
  if not snd then log("voice: " .. tostring(path) .. " didn't load"); return end
  local vol = v.volume or 1.0
  local ok, how = vox.spawn(pawn, mesh, snd, vol)
  local now = os.clock()
  if ok then vox.last[path], vox.t = now, now end
  log(string.format("voice: %s at %.2f %s", path:match("([^/.]+)$") or path, vol, how))
end
-- a quiet sound of hers while she convulses (convulse.lua: a moan with a spasm, a breath with a gasp): names under
-- vox.DIR or full paths; the name played, or nil. Never while her cry still sounds, nor once her head is off
function M.voice_soft(pawn, mesh, names, vol)
  if (cfg().voice or {}).enabled == false or type(names) ~= "table" or #names == 0 then return nil end
  if valid(vox.ac) and try(function() return vox.ac:IsPlaying() end) then return nil end
  local list = {}
  for _, s in ipairs(names) do
    s = tostring(s)
    if s:sub(1, 1) ~= "/" then s = vox.DIR .. s:gsub("_VO$", "") .. "_VO" end
    if not s:find(".", 1, true) then s = s .. "." .. s:match("([^/]+)$") end
    list[#list + 1] = s
  end
  local path = vox.pick(list, 6)
  local snd = load_obj(path)
  if not snd then return nil end
  local ok = vox.spawn(pawn, mesh, snd, vol)
  if not ok then return nil end
  local now = os.clock()
  vox.last[path], vox.t = now, now
  return path:match("([^/.]+)$") or path
end
-- her head came off: the cry, if it still sounds, fades out fast (a beheading is instant). A sharp stop clicked
function vox.cut()
  local ac = vox.ac
  if not valid(ac) or not try(function() return ac:IsPlaying() end) then return end
  local d = (cfg().voice or {}).cutFade or 0.08
  -- (Sin: EAudioFaderCurve 3, smooth at both ends)
  local ok = pcall(function() ac:FadeOut(d, 0.0, 3) end) or pcall(function() ac:FadeOut(d, 0.0) end)
  log(string.format("voice: cut off %.2f s in as her head came off (%.2f s fade%s)", os.clock() - (vox.t or 0), d, ok and "" or ", failed"))
end

-- Eve's blood effects (the bleed, her hit blood: MA_A_DefaultBlood_01, MA_A_GpuBlood_01) take their colour from
-- MPC_BloodParameters (DefaultBlood 0.15, 0, 0; DefaultBlood2 0.23, 0.05, 0; EmissiveBloodMinValue 0.15, read out of
-- the asset), and sprayed bright red, not the crimson of her pools (playtest). The collection is global and each
-- level gets its own copy, so it is set again at every spawn (tune.gore.bloodTint)
local niagara
do -- (a block: the main chunk is at Lua's 200 locals)
local tinted = nil -- the game's values, logged once
local function blood_tint(comp)
  local t = cfg().bloodTint
  local mpc = type(t) == "table" and load_obj("/Game/Art/FX/MPC/MPC_BloodParameters.MPC_BloodParameters")
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
  for k, v in pairs(t) do
    try(function()
      if type(v) == "table" then
        kml:SetVectorParameterValue(comp, mpc, FName(k), { R = v[1] or 0, G = v[2] or 0, B = v[3] or 0, A = v[4] or 1 })
      else kml:SetScalarParameterValue(comp, mpc, FName(k), v) end
    end)
  end
end

function niagara(sys_path, comp, bone, loc, attached, rot)
  if sys_path == FX.bleed or sys_path == FX.hit then blood_tint(comp) end
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
-- a component's mesh asset (its address): an enemy's sinks are put back per asset
function enemy.asset(comp) local m = valid(comp) and try(function() return comp.SkeletalMesh end); return valid(m) and addr(m) or nil end
local function already_cut(mesh, bone)
  local a = addr(mesh)
  for _, c in ipairs(cuts) do
    if c.addr == a and c.bone == bone then return true end
    -- (or gone with a smashed part: an arm under her smashed upper body, a forearm under its smashed upper arm)
    if c.addr == a and c.smashed and try(function() return mesh:BoneIsChildOf(FName(bone), FName(c.bone)) end) == true then
      return true
    end
  end
  return false
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

-- Tachy's flesh as a torn surface: rings from the rim in to the centre, each point raised by her
-- texture's relief (t.relief, read where that point lands on the disc) and a swell where the flesh pushes out of the
-- skin, the normals worked out from the faces so the light shows it. The relief fades out at the rim, which stays on
-- her skin, and under the core. The back face is lid_mesh's flat one. Same return as lid_mesh
-- one frame for both openings of a cut (tachy_lid, M.core): the body side's x and y. Each opening had its own (its
-- first rim point, its fitted ellipse) and Tachy's core was turned, not mirrored, onto the other side: the stump and
-- the cut piece showed different cross-sections, the bone in one place on the arm and elsewhere on the shoulder. With
-- this the piece's side is the stump's mirror image, as the two faces of one cut are
function M.pair(ob, ol)
  local z = ob and ob.z and norm(ob.z)
  local x = z and ob.x and norm(sub(ob.x, scale(z, dot(ob.x, z))))
  if not x then return end
  local y = cross(z, x)
  ob.tx, ob.ty = x, y
  if ol then ol.tx, ol.ty = x, y end
end
-- an opening's frame for the tachy look: x along it, y across it (the shared one, M.pair), and whether that is
-- mirrored (the cut piece's side: y = -(z cross x))
function M.tachy_frame(o, z)
  local x0 = o.tx or o.x
  local x = x0 and norm(sub(x0, scale(z, dot(x0, z))))
  if not x then return nil end
  local y = cross(z, x)
  local mirrored = o.ty and dot(y, o.ty) < 0 or false
  if mirrored then y = scale(y, -1) end
  return x, y, mirrored
end
-- a cap with no core of Tachy's over it (a neck's or waist's, which get the snapped bone at the spine, and a split's)
-- takes this patch of her disc, {x, y, radius} in disc radii: plain flesh away from her core, whose gold socket and
-- tube holes are painted on the disc and showed through on a neck as a stray bump by the bone (playtest)
M.TACHY_PATCH = { -0.3, -0.3, 0.38 }
-- how high the flesh rises in the middle of an opening of mean radius r (tachyDome of a dome: 0 flat, as a blade
-- leaves it; the lid was a smooth dome and read as a cover, not a cut, playtest). Tachy's core stands on it
function M.tachy_dome(r)
  return math.min(math.max(r * 0.18, 0.4), 1.8) * (cfg().tachyDome or 0)
end
-- smooth value noise, -1..1, on a hashed lattice
function M.tachy_noise(x, y)
  local function h(i, j)
    local n = (i * 374761393 + j * 668265263) % 2147483647
    n = (n ~ (n >> 13)) * 1274126177 % 2147483647
    return (n % 2001) / 1000 - 1
  end
  local i, j = math.floor(x), math.floor(y)
  local fx, fy = x - i, y - j
  fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
  local a = h(i, j) + (h(i + 1, j) - h(i, j)) * fx
  local b = h(i, j + 1) + (h(i + 1, j + 1) - h(i, j + 1)) * fx
  return a + (b - a) * fy
end
-- the torn surface: rings from the rim in, and points round each (the outline's, more put between them up to
-- TACHY_AROUND: at the outline's 15-40 the relief was too coarse to read as torn)
M.TACHY_RINGS = { 1, 0.94, 0.88, 0.82, 0.75, 0.68, 0.61, 0.54, 0.47, 0.4, 0.33, 0.26, 0.19, 0.12, 0.06 }
M.TACHY_AROUND = 72
function M.tachy_lid(o, k, t)
  local g = cfg()
  local n = #o.p
  local c = vec(0, 0, 0)
  for _, q in ipairs(o.p) do c = add(c, q) end
  c = scale(c, 1 / n)
  local z = o.z
  local r = 0
  for _, q in ipairs(o.p) do local d = sub(q, c); r = r + math.sqrt(math.max(dot(d, d) - dot(d, z) ^ 2, 0)) end
  r = r / n
  local dome = M.tachy_dome(r)
  -- (deep: a harsh cut's torn flesh; at r * 0.22 the relief's typical 0.27 of it was 2-3 mm on a neck and read as flat,
  -- playtest)
  -- (at r * 0.45 up to 3 cm, with the noise on top, it was too lumpy, playtest)
  -- (still too lumpy at r * 0.3 up to 1.5 cm, and its creases sank under the cut, where the limb's own closed skin hid the
  -- flesh: the stump looked uncovered, playtest. Creases go at most a fifth of it down)
  local amp = math.min(math.max(r * 0.12, 0.3), 0.8) * (g.tachyRelief or 1)
  local u, w = M.tachy_frame(o, z)
  if not u then
    u = norm(sub(o.p[1], add(c, scale(z, dot(sub(o.p[1], c), z))))) or o.x
    w = cross(z, u)
  end
  local disc, rel = t.disc, t.relief
  -- (a plain patch of the disc under a core too: the whole disc's painted gold socket showed beside the core's own,
  -- playtest)
  local pa = M.TACHY_PATCH
  local gs = rel and rel.size or 0
  -- the relief at a point of the disc's square (-1..1 each way), bilinear
  local function relief(x, y)
    if gs == 0 then return 0 end
    local fx, fy = (x + 1) * 0.5 * gs - 0.5, (y + 1) * 0.5 * gs - 0.5
    local x0, y0 = math.max(0, math.min(gs - 2, math.floor(fx))), math.max(0, math.min(gs - 2, math.floor(fy)))
    local ax, ay = math.max(0, math.min(1, fx - x0)), math.max(0, math.min(1, fy - y0))
    local function at(i, j) return (rel[j * gs + i + 1] or 0) / 99 end
    local h = (at(x0, y0) * (1 - ax) + at(x0 + 1, y0) * ax) * (1 - ay) + (at(x0, y0 + 1) * (1 - ax) + at(x0 + 1, y0 + 1) * ax) * ay
    -- torn finer than the texture's 48 cells: smooth noise on the disc (the same on both faces of a cut: they mirror)
    return math.max(-1, math.min(1, h + 0.25 * M.tachy_noise(x * 9, y * 9) + 0.15 * M.tachy_noise(x * 21 + 7, y * 21 + 3)))
  end
  local verts, normals, uvs, tris, tangents, colors = {}, {}, {}, {}, {}, {}
  local function vert(pos, nrm, uv)
    verts[#verts + 1] = pos
    normals[#normals + 1] = nrm
    uvs[#uvs + 1] = uv
    tangents[#tangents + 1] = { TangentX = u, bFlipTangentY = dot(cross(nrm, u), w) < 0 }
    colors[#colors + 1] = { R = 1, G = 1, B = 1, A = 1 }
    return #verts - 1
  end
  -- the front: ring i, point j; ρ the share of the way out to the rim
  local R = M.TACHY_RINGS
  local pts = {}
  local per = math.max(1, math.ceil(M.TACHY_AROUND / n))
  for j, q in ipairs(o.p) do
    local q2 = o.p[j % n + 1]
    for s2 = 0, per - 1 do pts[#pts + 1] = add(q, scale(sub(q2, q), s2 / per)) end
  end
  local nf = #pts
  local grid = {}
  for i, rho in ipairs(R) do
    grid[i] = {}
    for j, q in ipairs(pts) do
      local d = sub(q, c)
      local h = dot(d, z)
      local flat = sub(d, scale(z, h))
      local ang = math.atan(dot(flat, w), dot(flat, u))
      local cx, cy = pa[1] + math.cos(ang) * rho * pa[3], pa[2] + math.sin(ang) * rho * pa[3]
      -- (out at the rim: the skin's own height; in from it the dome, a swell just inside the skin, the relief, which
      -- fades in over the outer tenth, and under a core)
      local fade = math.min(1, (1 - rho) / 0.1) * (o.core and math.min(1, rho / 0.3) or 1)
      if o.boneAt then
        local b = sub(add(c, scale(flat, k * rho)), o.boneAt)
        local bd = math.sqrt(math.max(dot(b, b) - dot(b, z) ^ 2, 0))
        fade = fade * math.max(0, math.min(1, (bd - 1.2) / 1.5))
      end
      local lift = 0.2 + h * rho + dome * (1 - rho * rho) * 0.85 + dome * 0.35 * math.sin(math.min(1, (1 - rho) / 0.3) * math.pi)
        + amp * fade * math.max(relief(cx, cy), -0.2)
      grid[i][j] = vert(add(scale(flat, k * rho), scale(z, lift)), z,
        { X = disc[1] + disc[3] * cx, Y = disc[2] + disc[3] * cy })
    end
  end
  local centre = vert(scale(z, dome * 0.85 + 0.2), z, { X = disc[1] + disc[3] * pa[1], Y = disc[2] + disc[3] * pa[2] })
  local front = {}
  -- counter-clockwise from +z, as lid_mesh's (each written backwards for UE's clockwise front faces)
  local function tri(a, b, cc) front[#front + 1] = { a, b, cc } end
  for i = 1, #R - 1 do
    for j = 1, nf do
      local jn = j % nf + 1
      local a, b, cc, d = grid[i][j], grid[i][jn], grid[i + 1][jn], grid[i + 1][j]
      tri(a, b, cc); tri(a, cc, d)
    end
  end
  for j = 1, nf do tri(grid[#R][j], grid[#R][j % nf + 1], centre) end
  -- normals from the faces (each face's, by its area, onto its corners)
  local acc = {}
  for _, f in ipairs(front) do
    local p1, p2, p3 = verts[f[1] + 1], verts[f[2] + 1], verts[f[3] + 1]
    local fn = cross(sub(p2, p1), sub(p3, p1))
    if dot(fn, z) < 0 then fn = scale(fn, -1) end
    for _, v in ipairs(f) do acc[v] = acc[v] and add(acc[v], fn) or fn end
    tris[#tris + 1] = f[3]; tris[#tris + 1] = f[2]; tris[#tris + 1] = f[1]
  end
  for v, a in pairs(acc) do normals[v + 1] = norm(a) or z end
  -- the back: lid_mesh's flat face, the other way
  local nz = scale(z, -1)
  local base = #verts
  vert(scale(z, dome), nz, { X = disc[1], Y = disc[2] })
  for _, q in ipairs(o.p) do
    local d = sub(q, c)
    local h = dot(d, z)
    local flat = sub(d, scale(z, h))
    vert(add(scale(flat, k), scale(z, h + 0.2)), nz, { X = disc[1], Y = disc[2] })
  end
  for j = 0, n - 1 do
    local jn = (j + 1) % n
    tris[#tris + 1] = base + 1 + j; tris[#tris + 1] = base + 1 + jn; tris[#tris + 1] = base
  end
  return c, verts, tris, normals, uvs, tangents, colors
end

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
  for _, e in ipairs(M.pool.lid or {}) do mark_live(e.a, valid(e.a)) end
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
M.pool = { lid = {}, plain = {}, want = { lid = 6, plain = 6 } }
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
  if kind == "lid" then
    local pmc_cls = load_obj("/Script/ProceduralMeshComponent.ProceduralMeshComponent")
    local pmc = pmc_cls and try(function()
      return a:AddComponentByClass(pmc_cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }, false)
    end)
    if not valid(pmc) then try(function() a:K2_DestroyActor() end); return nil end
    try(function() pmc:SetCollisionEnabled(0) end)
    try(function() pmc:SetCastShadow(false) end)
    e.mat = M.cap_mat()
    set_cap_material(pmc, load_obj(e.mat))
    e.pmc = pmc
  end
  return e
end
-- one for a cut (kept in caps, which destroys it with the cut), at at
function M.pool_take(pawn, kind, at)
  local list, e = M.pool[kind], nil
  while #list > 0 and not e do
    local x = table.remove(list)
    if valid(x.a) and (kind ~= "lid" or valid(x.pmc)) then e = x end
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
  for _, kind in ipairs({ "lid", "plain" }) do
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
-- her metal bone alone, out of the core (its shaft and its end, two pieces; the two tubes and the flat disc by them
-- are left out), centred on 0, 0: a neck's or waist's stump shows only the bone, at her spine. {tris, centre, shaft}
-- (shaft: the shaft's radius in disc radii, from its vertices above the flare)
function M.tachy_bone(t)
  if t.bone then return t.bone end
  local v, nv = t.verts, #t.verts // 11
  local par = {}
  for i = 0, nv - 1 do par[i] = i end
  local function f(a) while par[a] ~= a do par[a] = par[par[a]]; a = par[a] end return a end
  for i = 1, #t.tris, 3 do
    local a, b, c = t.tris[i], t.tris[i + 1], t.tris[i + 2]
    par[f(a)] = f(b); par[f(b)] = f(c)
  end
  local comps = {}
  for i = 0, nv - 1 do
    local r = f(i)
    local c = comps[r] or { n = 0, x = 0, y = 0 }
    comps[r] = c
    c.n, c.x, c.y = c.n + 1, c.x + v[i * 11 + 1], c.y + v[i * 11 + 2]
  end
  local big
  for r, c in pairs(comps) do if not big or c.n > comps[big].n then big = r end end
  local bx, by = comps[big].x / comps[big].n, comps[big].y / comps[big].n
  local reach = 0
  for i = 0, nv - 1 do
    if f(i) == big then reach = math.max(reach, math.sqrt((v[i * 11 + 1] - bx) ^ 2 + (v[i * 11 + 2] - by) ^ 2)) end
  end
  local keep = {}
  for r, c in pairs(comps) do
    if math.sqrt((c.x / c.n - bx) ^ 2 + (c.y / c.n - by) ^ 2) < reach * 0.5 then keep[r] = true end
  end
  local tris = {}
  for i = 1, #t.tris, 3 do
    if keep[f(t.tris[i])] then for k = 0, 2 do tris[#tris + 1] = t.tris[i + k] end end
  end
  local shaft, top = 0, -1
  for i = 0, nv - 1 do if keep[f(i)] then top = math.max(top, v[i * 11 + 3]) end end
  for i = 0, nv - 1 do
    if keep[f(i)] and v[i * 11 + 3] > top * 0.4 then
      shaft = math.max(shaft, math.sqrt((v[i * 11 + 1] - bx) ^ 2 + (v[i * 11 + 2] - by) ^ 2))
    end
  end
  local set = {}
  for i = 0, nv - 1 do if keep[f(i)] then set[i] = true end end
  -- its lean: the shaft's middles over its lowest and highest quarters, per unit of height
  local z0, z1 = math.huge, -math.huge
  for i = 0, nv - 1 do if f(i) == big then z0, z1 = math.min(z0, v[i * 11 + 3]), math.max(z1, v[i * 11 + 3]) end end
  local lo, hi = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
  for i = 0, nv - 1 do
    local h = v[i * 11 + 3]
    local q = f(i) == big and (h < z0 + (z1 - z0) * 0.25 and lo or h > z1 - (z1 - z0) * 0.25 and hi) or nil
    if q then q[1], q[2], q[3], q[4] = q[1] + v[i * 11 + 1], q[2] + v[i * 11 + 2], q[3] + h, q[4] + 1 end
  end
  local lx, ly = 0, 0
  if lo[4] > 0 and hi[4] > 0 then
    local dz = hi[3] / hi[4] - lo[3] / lo[4]
    if dz > 1e-3 then lx, ly = (hi[1] / hi[4] - lo[1] / lo[4]) / dz, (hi[2] / hi[4] - lo[2] / lo[4]) / dz end
  end
  -- her gold socket: the flat pieces lying low on her disc (two rings, 0.05 high at most; a tube's end lies flat too,
  -- but up at its top)
  local gold, span = {}, {}
  for i = 0, nv - 1 do
    local r, h = f(i), v[i * 11 + 3]
    local sp = span[r] or { math.huge, -math.huge }
    span[r] = sp
    sp[1], sp[2] = math.min(sp[1], h), math.max(sp[2], h)
  end
  for i = 0, nv - 1 do local sp = span[f(i)]; if sp[2] < 0.08 and sp[2] - sp[1] < 0.1 then gold[i] = true end end
  t.bone = { tris = tris, cx = bx, cy = by, shaft = shaft > 0 and shaft or reach, verts = set, lx = lx, ly = ly, gold = gold }
  return t.bone
end
-- her bone in silver (boneSilver): on her texture it is painted ivory, not metal (its metal mask 0.01-0.04), and read
-- as pale dirt (playtest); her metal is on the strip along the bottom (v 0.82-0.93, a mask of 0.95) and in the tube
-- ends' tiles down the left. Its end goes onto a tube end's tile, its shaft onto the strip, each scaled, not turned
-- (her tangents stay right)
function M.bone_uv(t, i, u, w)
  if cfg().boneSilver == false or not M.tachy_bone(t).verts[i] then return { X = u, Y = w } end
  if u < 0.3 and w < 0.35 then return { X = 0.02 + (u - 0.01) / 0.28 * 0.15, Y = 0.40 + (w - 0.01) / 0.33 * 0.16 } end
  return { X = 0.05 + (u - 0.74) / 0.25 * 0.65, Y = 0.82 + (w - 0.12) / 0.87 * 0.11 }
end
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
  local function to(a, b, h) return add(add(scale(x, a), scale(y, b)), scale(z, h)) end
  local top, foot = 0, 0
  for i = 1, #v, 11 do top = math.max(top, v[i + 2] * hs) end
  for i = 1, #v, 11 do
    verts[#verts + 1] = scale(to(v[i] - ox - lx * v[i + 2], v[i + 1] - oy - ly * v[i + 2], v[i + 2] * hs), r)
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
  local e = M.pool_take(pawn, "lid", c)
  if not (e and valid(e.a) and valid(e.pmc)) then log("tachy core: spawn failed"); return nil end
  local a, pmc = e.a, e.pmc
  try(function() a:K2_SetActorRotation({ Pitch = 0, Yaw = 0, Roll = 0 }, false) end)
  local made = try(function() pmc:CreateMeshSection_LinearColor(0, verts, tris, normals, uvs, {}, {}, {}, colors, tangents, false); return true end)
    or try(function() pmc:CreateMeshSection_LinearColor(0, verts, tris, normals, uvs, colors, tangents, false); return true end)
  if not made then log("tachy core: no mesh section"); return nil end
  if e.mat ~= "core" then set_cap_material(pmc, load_obj(M.TACHY_MAT), "core"); e.mat = "core" end
  M.repose(a, mesh, rides or bone)
  try(function() a:K2_AttachToComponent(mesh, FName(rides or bone), 1, 1, 1, false) end)
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

-- her skin's own blood layer (MPC_PCDirtyOffset): raised over tune.gore.bodyBlood.time on a death cut, put back
-- on recovery. The collection is global, so this is all of her at once, not around the cut
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
    if ctx.tune.verboseLog then log(string.format("body blood: now BloodFactor %s, BloodOffset %s", tostring(mpc_get(b.pawn, b.mpc, "BloodFactor")),
      tostring(mpc_get(b.pawn, b.mpc, "BloodOffset")))) end
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
-- drips and splats: the pools' own (the Raven cinematic's splat, MI_FloorBloodDecal_5 on MA_A_BloodDecal_01, has no
-- BloodBright darkening and twice the specular: drips read bright red beside the dark pools, playtest)
local DRIP_DECALS = POOL_DECALS
-- the pool's final radius in cm by the cut bone (first match)
local POOL_R = { { "Neck", 55 }, { "Head", 55 }, { "Spine", 80 }, { "Pelvis", 80 }, { "Thigh", 60 }, { "UpperArm", 40 },
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

-- where a pool may spread: a decal's box projects along the floor's normal and paints whatever is in it, so a pool
-- spread up to a wall smeared down it in long streaks (playtest). Two checks keep it on open, flat floor:
-- wall_room as it starts: level traces in 16 directions, 3 and 10 cm over the floor, out to its full size; a surface
-- steeper than 45 deg is a wall, and the pool stays 10 % short of the nearest. ring_ok before it grows into each
-- next ring (6 cm out): 16 traces down onto the ring, each must find floor facing up (within 25 deg of the pool's)
-- within 3 cm of the pool's plane, else it stops at the last ring that held (a post, a curb, a step, a gap, a thin
-- wall a level trace slipped past). (On M: gore.lua is at Lua's 200 locals)
M.POOL_DIRS = 16
function M.pool_frame(n)
  local up = n or vec(0, 0, 1)
  local a = norm(cross(up, math.abs(up.X) < 0.9 and vec(1, 0, 0) or vec(0, 1, 0))) or vec(1, 0, 0)
  return up, a, cross(up, a)
end
function M.pool_trace(pawn, from, to)
  local ks = load_obj("/Script/Engine.Default__KismetSystemLibrary")
  if not ks then return nil end
  local hit = {}
  local ok = try(function()
    return ks:LineTraceSingle(pawn, from, to, 0, false, { pawn }, 0, hit, true,
      { R = 1, G = 0, B = 0, A = 1 }, { R = 0, G = 1, B = 0, A = 1 }, 0)
  end)
  if not ok then return false end
  local at = try(function() local l = hit.ImpactPoint or hit.Location; return vec(l.X, l.Y, l.Z) end)
  local hn = try(function() local l = hit.ImpactNormal or hit.Normal; return vec(l.X, l.Y, l.Z) end)
  return at ~= nil, at, hn and norm(hn)
end
function M.wall_room(pawn, at, n, rmax)
  local up, a, b = M.pool_frame(n)
  local room = rmax
  for _, h in ipairs({ 3, 10 }) do
    local from = add(at, scale(up, h))
    for i = 0, M.POOL_DIRS - 1 do
      local ang = i * 2 * math.pi / M.POOL_DIRS
      local d = add(scale(a, math.cos(ang)), scale(b, math.sin(ang)))
      local hit, p, hn = M.pool_trace(pawn, from, add(from, scale(d, rmax)))
      if hit and p and hn and math.abs(dot(hn, up)) < 0.7 then
        local w = len(sub(p, from))
        if w < room then room = w end
      end
    end
  end
  return math.max(room * 0.9, 4)
end
function M.ring_ok(pawn, at, n, ring)
  local up, a, b = M.pool_frame(n)
  for i = 0, M.POOL_DIRS - 1 do
    local ang = (i + 0.5) * 2 * math.pi / M.POOL_DIRS
    local c = add(at, add(scale(a, math.cos(ang) * ring), scale(b, math.sin(ang) * ring)))
    local hit, p, hn = M.pool_trace(pawn, add(c, scale(up, 15)), add(c, scale(up, -15)))
    if not (hit and p and hn) or dot(hn, up) < 0.9 or math.abs(dot(sub(p, at), up)) > 3 then return false end
  end
  return true
end

-- one decal on the floor under p, r cm across (radius); its box reaches 8 cm into and out of the floor (20 cm drew
-- the pools far up a wall beside them, playtest)
local function floor_decal(pawn, p, r, list, life)
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  local km = load_obj("/Script/Engine.Default__KismetMathLibrary")
  local mat = load_obj(pick(list))
  if not (gs and km and mat) then return nil end
  local t0 = os.clock()
  local at, n = floor_at(pawn, p)
  local t1 = os.clock()
  -- the decal projects along its X: into the floor, turned at random about it
  local rot = try(function() return km:MakeRotFromX(scale(n, -1)) end)
  rot = rot and { Pitch = rot.Pitch, Yaw = rot.Yaw, Roll = math.random() * 360 } or { Pitch = -90, Yaw = 0, Roll = math.random() * 360 }
  local d = try(function() return gs:SpawnDecalAtLocation(pawn, mat, vec(8, 1, 1), at, rot, life or 0) end)
  local t2 = os.clock()
  if valid(d) then try(function() d:SetWorldScale3D(vec(1, r, r)) end) end
  -- (each pool or drip pass held a frame 9-14 ms in 0.4.x, playtest: which part)
  local ms = (os.clock() - t0) * 1000
  if ms >= (cfg().slowMs or 15) * 0.5 then
    log(string.format("floor decal took %.1f ms: trace %.1f, spawn %.1f, scale %.1f", ms, (t1 - t0) * 1000,
      (t2 - t1) * 1000, (os.clock() - t2) * 1000))
  end
  if not valid(d) then return nil end
  -- (one with a life of its own goes by itself, kept off the list and its cap)
  if not life then decals[#decals + 1] = d end
  return { d = d, at = at, n = n, r = r }
end

-- the splat under a cut or a hit: a splash of the pools' blood on the floor under `at`, kept off walls as they are.
-- The game's splat effect (NS_Hit_Flesh_Decal_Strong_01) put its own blood decal down (MI_ParBloodDecal_01, coloured
-- by its particles), a brighter red than the pools (playtest). life: s it stays (a hit she lives through; 0: till
-- she is up again, with the pools)
function M.splat(pawn, at, life)
  if not at then return end
  local g = cfg()
  if not life and #decals >= (g.maxDecals or 60) then return end
  local r = (g.splatSize or 14) * (0.75 + math.random() * 0.5)
  local f, n = floor_at(pawn, at)
  if f then r = math.min(r, M.wall_room(pawn, f, n, r)) end
  floor_decal(pawn, at, r, POOL_DECALS, life)
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
  -- one decal made a pass (a floor trace and a spawn each): every opening's pool or drip due on the same pass took
  -- 9-14 ms, every 0.1 s for seconds after a cut (playtest); the rest come on the next passes
  local budget, ringBudget = 1, 2
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
      if not k.pool and k.still >= 0.3 and #decals < maxDecals and budget > 0 then
        -- it came to rest: a pool starts under it
        budget = budget - 1
        k.pool = floor_decal(k.pawn, p, 4, POOL_DECALS)
        if k.pool then
          k.pool.age, k.pools = 0, (k.pools or 0) + 1
          -- it spreads only up to the nearest wall
          k.pool.rmax = M.wall_room(k.pawn, k.pool.at, k.pool.n, k.rmax)
          if k.pool.rmax < k.rmax and not M.wallLogged then
            M.wallLogged = true
            log(string.format("floor blood: a pool by a wall spreads %.0f cm across, not %.0f", k.pool.rmax * 2, k.rmax * 2))
          end
        end
      elseif not k.pool and speed >= 25 and #decals < maxDecals and budget > 0 then
        -- on the move: drips every so often
        if not k.drop or len(sub(p, k.drop)) >= every then
          budget = budget - 1
          k.drop = p
          floor_decal(k.pawn, p, 2.5 + math.random() * 4, DRIP_DECALS)
          k.drips = (k.drips or 0) + 1
        end
      end
      if k.pool and valid(k.pool.d) then
        k.pool.age = k.pool.age + dt
        -- fast at first, slowing down: 63 % of the way after poolGrow s
        local rm = math.min(k.rmax, k.pool.rmax or k.rmax)
        local r = 4 + (rm - 4) * (1 - math.exp(-k.pool.age / grow))
        -- the next ring checked before it grows into it (one ring a pass, every pool's together under ringBudget)
        k.pool.ok = k.pool.ok or 4
        if r > k.pool.ok and not k.pool.stopped and ringBudget > 0 then
          ringBudget = ringBudget - 1
          local ring = math.min(k.pool.ok + 6, rm)
          if M.ring_ok(k.pawn, k.pool.at, k.pool.n, ring) then k.pool.ok = ring
          else
            k.pool.stopped = true
            if not M.ringLogged then
              M.ringLogged = true
              log(string.format("floor blood: a pool stopped at %.0f cm across, the floor not flat past it", k.pool.ok * 2))
            end
          end
        end
        r = math.min(r, k.pool.ok)
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
-- each mesh asset's bone names and parents by index, read once (M.watch reads hers a slice at a time while she plays):
-- the lists below come from it with no engine call. Read bone by bone at the cut, they held the first cut's frame
-- 15-34 ms more (twenty-ninth playtest). budget: at most that many bones now, nil if it isn't whole yet
M.trees = {}
function M.bone_tree(comp, budget)
  local sm = try(function() return comp.SkeletalMesh end)
  local key = valid(sm) and addr(sm)
  if not key then return nil end
  local t = M.trees[key]
  if not t then
    local n = try(function() return comp:GetNumBones() end) or 0
    if n <= 0 then return nil end
    t = { n = n, name = {}, pname = {}, index = {}, parent = {}, next = 0 }
    M.trees[key] = t
  end
  if t.done then return t end
  local stop = budget and math.min(t.n, t.next + budget) or t.n
  while t.next < stop do
    local i = t.next
    local nm = try(function() return comp:GetBoneName(i):ToString() end) or "None"
    t.name[i], t.index[nm] = nm, i
    t.pname[i] = try(function() return comp:GetParentBone(FName(nm)):ToString() end) or "None"
    t.next = i + 1
  end
  if t.next < t.n then return nil end
  for i = 0, t.n - 1 do t.parent[i] = t.index[t.pname[i]] or -1 end
  t.done = true
  return t
end
-- i is r's bone or under it (by name)
function M.under(t, i, r)
  local ri = t.index[r]
  if not ri then return false end
  local guard = 0
  while i and i >= 0 and guard < 512 do
    if i == ri then return true end
    i, guard = t.parent[i], guard + 1
  end
  return false
end
local NOSINK_PREFIX = { "Bip001", "SC_", "Ab_" }
local NOSINK_PART = { "Hair", "Cape", "Breast", "Prop" }
local nosink_cache = {}
local function nosink_list(comp)
  local sm = try(function() return comp.SkeletalMesh end)
  local key = valid(sm) and addr(sm)
  if key and nosink_cache[key] then return nosink_cache[key] end
  local t = M.bone_tree(comp)
  local n = t and t.n or 0
  local list = {}
  for i = 0, n - 1 do
    local nm = t.name[i]
    local bad = nm == "Root" or nm == "None"
    -- an enemy's Ab_ bones are its own deform helpers (the skulls' head has no other: without them its head had
    -- nothing to close on and vanished); a lurker's tentacles stay sinks too (its head closes on them)
    for _, pre in ipairs(NOSINK_PREFIX) do if nm:sub(1, #pre) == pre and not (enemy.cur and not enemy.faced[enemy.cur] and pre == "Ab_") then bad = true end end
    for _, part in ipairs(NOSINK_PART) do if nm:find(part, 1, true) then bad = true end end
    if bad then list[#list + 1] = string.format("%x", i) end
  end
  local s = table.concat(list, ",")
  if key and n > 0 then nosink_cache[key] = s end
  return s
end
-- a cut through the spine also keeps its sinks off the arms and legs: they swing on their own, and the bind pose's
-- arms hang down at the waist, where a waist cut's strap seam collapsed onto a triceps helper (seventeenth playtest).
-- A limb or head cut keeps them off every other limb (own: the cut bone's limb root, its own subtree stays allowed):
-- a thigh cut in a fall put the hip's seam on Ab-L-Elbow, the hand resting by the hip, and the seam rode the arm
-- off as she flailed, a sheet from the hip to the elbow (twenty-seventh playtest)
local LIMB_ROOTS = { "Bip001-L-Clavicle", "Bip001-R-Clavicle", "Bip001-L-Thigh", "Bip001-R-Thigh" }
-- the limb root bone i is on: under one of LIMB_ROOTS, or under a helper of the same name (CH_M_NA_40's arm helpers
-- hang off Ab-L-Clavicle, beside Bip001-L-Clavicle: a waist cut's seam took Ab-L-UpperArm-biceps and swung with the
-- arm), else nil
function M.limb_of(t, i)
  local guard = 0
  while i and i >= 0 and guard < 512 do
    local nm = t.name[i] or ""
    local side, part = nm:match("[-_]([LR])%-(Clavicle)$")
    if not side then side, part = nm:match("[-_]([LR])%-(Thigh)$") end
    if side then return "Bip001-" .. side .. "-" .. part end
    i, guard = t.parent[i], guard + 1
  end
end
local limbs_cache = {}
local function limbs_list(comp, own)
  local sm = try(function() return comp.SkeletalMesh end)
  local key = valid(sm) and (addr(sm) .. "/" .. tostring(own))
  if key and limbs_cache[key] then return limbs_cache[key] end
  local t = M.bone_tree(comp)
  local n = t and t.n or 0
  local list = {}
  for i = 0, n - 1 do
    local r = M.limb_of(t, i)
    if r and r ~= own then list[#list + 1] = string.format("%x", i) end
  end
  local s = table.concat(list, ",")
  if key and n > 0 then limbs_cache[key] = s end
  return s
end
-- the limb root a bone is on (M.limb_of), else nil
local function limb_root(comp, bone)
  local t = M.bone_tree(comp)
  if t and t.index[bone] then return M.limb_of(t, t.index[bone]) end
  for _, r in ipairs(LIMB_ROOTS) do if bone == r then return r end end
end
-- bones that may never carry a stub (after ffff in the same command): the rig's Dm- drivers, which the animation points
-- at limbs (Dm-Spine-bland, blending Spine and Spine1, carried a waist cut's stub after the flying upper body). An
-- enemy's every bone: its mesh asset is shared with the live enemies of its kind, whose skin on a carrier would move
-- with the cut one's matrix. Nor a bone with a physics body of its own: it swings on its own constraint in a ragdoll
-- (a calf's stub went on Ab-L-Hip, the hip's jiggle body, and would have bounced with it)
local nocarry_cache = {}
-- her bones with a physics body (by index; sent after fffe in "n": a cut's sinks ride the body its stump rides, and a
-- limb's seam closes in the opening's middle). An enemy's too: without them its seams closed on helpers 40-50 cm off
-- the cut, sheets of skin out of every opening (playtest: stretched faces on enemies)
local function bodies_of(comp)
  local sm = try(function() return comp.SkeletalMesh end)
  local key = valid(sm) and (addr(sm) .. "b")
  if key and nocarry_cache[key] then return nocarry_cache[key] end
  local out = {}
  local pa = ctx.physics_of and try(function() return ctx.physics_of(comp) end)
  if valid(pa) then
    try(function() pa.SkeletalBodySetups:ForEach(function(_, e)
      local bs = e:get()
      local t = M.bone_tree(comp)
      local i = valid(bs) and try(function() return t and t.index[bs.BoneName:ToString()] or comp:GetBoneIndex(bs.BoneName) end)
      if i and i >= 0 then out[i] = true end
    end) end)
  end
  if key and next(out) then nocarry_cache[key] = out end
  return out
end
local function nocarry_list(comp)
  local sm = try(function() return comp.SkeletalMesh end)
  local key = valid(sm) and (addr(sm) .. (enemy.cur and "e" or ""))
  if key and nocarry_cache[key] then return nocarry_cache[key] end
  local t = not enemy.cur and M.bone_tree(comp)
  local n = try(function() return comp:GetNumBones() end) or 0
  local body = bodies_of(comp)
  local list = {}
  for i = 0, n - 1 do
    local nm = enemy.cur and "" or (t and t.name[i]) or "None"
    if enemy.cur or nm:sub(1, 3) == "Dm-" or nm:sub(1, 3) == "Dm_" or body[i] then list[#list + 1] = string.format("%x", i) end
  end
  local s = table.concat(list, ",")
  if key and n > 0 then nocarry_cache[key] = s end
  return s
end

-- a cut through the spine also sends the rig's Dm- drivers and every helper under one (before the main skeleton), after
-- fffd: the animation points them across the cut, so they are a sink only when a section has nothing else.
-- CH_P_EVE_30's Ab-L-AX2, under Dm-L-AX2 on the pelvis, took a waist cut's lower seam and went with the flying upper
-- body: that half's opening stretched 3.5 m after it (playtest)
function M.driven_list(comp)
  local sm = try(function() return comp.SkeletalMesh end)
  local key = valid(sm) and (addr(sm) .. "d")
  if key and nocarry_cache[key] then return nocarry_cache[key] end
  local t = M.bone_tree(comp)
  local n = t and t.n or 0
  local list = {}
  for i = 0, n - 1 do
    local j, guard = i, 0
    while j and j >= 0 and guard < 512 and t.name[j]:sub(1, 6) ~= "Bip001" do
      local pre = t.name[j]:sub(1, 3)
      if pre == "Dm-" or pre == "Dm_" then list[#list + 1] = string.format("%x", i); break end
      j, guard = t.parent[j], guard + 1
    end
  end
  local s = table.concat(list, ",")
  if key and n > 0 then nocarry_cache[key] = s end
  return s
end

-- the drivers of a side (L, R) a split half lets go of: the animation moves them after those limbs, which fall free and
-- invisible, so its kept skin that hung partly on them stretched out after them, cones out of the half (playtest).
-- The half's skin lets go of them as of the limbs (sbslice fffc). Which limb a driver follows is read off the name of
-- the topmost Dm- bone over it (M.DRIVER_LIMB); a breast's or a cloth's follow her chest
M.DRIVER_LIMB = { arm = { "Trape", "Shoulder", "Side", "Pectro", "Arm", "Deltoid", "Tricep", "Elbow", "Forearm", "Brochi", "Clavicle" },
  leg = { "Thigh", "Hip", "Knee", "Venter", "Calf", "Ankle", "AX2" } }
function M.driver_limb(name)
  if name:find("Breast", 1, true) or name:find("Cloth", 1, true) then return nil end
  local side = name:match("[%-_]([LR])[%-_]")
  if not side then return nil end
  for kind, words in pairs(M.DRIVER_LIMB) do
    for _, w in ipairs(words) do if name:find(w, 1, true) then return side .. kind end end
  end
end
function M.side_drivers(comp, gone)
  local want, tag = {}, {}
  for _, b in ipairs(gone or {}) do
    local sd, part = b:match("^Bip001%-([LR])%-(%a+)")
    if sd then
      local k = sd .. ((part == "Thigh" or part == "Calf") and "leg" or "arm")
      if not want[k] then want[k] = true; tag[#tag + 1] = k end
    end
  end
  table.sort(tag)
  local sm = try(function() return comp.SkeletalMesh end)
  local key = valid(sm) and (addr(sm) .. "s" .. table.concat(tag))
  if key and nocarry_cache[key] then return nocarry_cache[key] end
  local t = M.bone_tree(comp)
  local n = t and t.n or 0
  local list = {}
  for i = 0, n - 1 do
    local j, guard, top = i, 0, nil
    while j and j >= 0 and guard < 512 and t.name[j]:sub(1, 6) ~= "Bip001" do
      local nm = t.name[j]
      if nm:sub(1, 3) == "Dm-" or nm:sub(1, 3) == "Dm_" then top = nm end
      j, guard = t.parent[j], guard + 1
    end
    local k = top and M.driver_limb(top)
    if k and want[k] then list[#list + 1] = string.format("%x", i) end
  end
  local r = table.concat(list, ",")
  if key and n > 0 then nocarry_cache[key] = r end
  return r
end

-- limbs: true (a torso cut: every limb, and the drivers), a bone name (a limb or head cut: every limb but the one it
-- is on), nil; driven: the drivers too (a split: its point sinks on driven helpers followed the limbs it lets go,
-- cones out of both halves, playtest); after: the drivers that follow the limbs a split half lets go (M.side_drivers)
local function send_nosink(comp, limbs, driven, after)
  local s = nosink_list(comp)
  if limbs then
    -- each bone once: the DLL reads at most as many fields as she has bones (and Bip001-* limb bones are in both)
    local seen, out = {}, {}
    local own = limbs ~= true and limb_root(comp, limbs) or nil
    for h in (s .. "," .. limbs_list(comp, own)):gmatch("[^,]+") do if not seen[h] then seen[h] = true; out[#out + 1] = h end end
    s = table.concat(out, ",")
  end
  local nc = nocarry_list(comp)
  -- her bodies only for a limb or the head (a cut through the torso keeps its sinks where they were)
  local bl = {}
  if limbs ~= true then for i in pairs(bodies_of(comp)) do bl[#bl + 1] = string.format("%x", i) end end
  local dr = (limbs == true or driven) and not enemy.cur and M.driven_list(comp) or ""
  -- (fffc's bones after fffd's: they are driven too, the later list wins)
  local r = command(string.format("n%x,%s,ffff%s%s%s%s", comp:GetAddress(), s, nc ~= "" and ("," .. nc) or "",
    #bl > 0 and (",fffe," .. table.concat(bl, ",")) or "", dr ~= "" and (",fffd," .. dr) or "",
    after and after ~= "" and (",fffc," .. after) or ""))
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
  send_nosink(comp, limbs, leg and true or nil, leg and M.side_drivers(comp, { limbs }) or nil)
  local s = string.format("c%x,0,%x,%x,%x", comp:GetAddress(), index, mode or 0, math.floor((radius or 0) * 10 + 0.5))
  if depth then s = s .. string.format(",%x", math.floor(depth * 10 + 0.5)) end
  return command(s, at, n)
end

-- (load_obj's) an asset the cuts use, kept loaded for good once loaded (sbslice "o" roots it): nothing else held
-- them, so garbage collection freed them between deaths and every cut loaded the bone stub, the cap material, the
-- effects and the sounds again from the pak on the game thread (stubs 54 ms, bleeds 35, blood 24: twenty-fifth
-- playtest). Tried once a path; a refusal is logged
native.rooted = {}
function native.root(path, o)
  if native.rooted[path] ~= nil or native.state ~= "ready" then return end
  local r = command(string.format("o%x", o:GetAddress()))
  native.rooted[path] = r:sub(1, 2) == "ok"
  if not native.rooted[path] then log("keeping " .. path .. " loaded refused: " .. r) end
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

M.face_of = face_of

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
M.hair_of = hair_of

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
local function kept_chains(mesh, bone, a, b, at, n)
  local pa = ctx.physics_of(mesh)
  if not valid(pa) then return {}, {} end
  local list, has = {}, {}
  try(function() pa.SkeletalBodySetups:ForEach(function(_, e) local bs = e:get(); if valid(bs) then local n = bs.BoneName:ToString(); list[#list + 1] = n; has[n] = true end end) end)
  local axis = norm(sub(b, a))
  local t = M.bone_tree(mesh)
  local function under(x, y)
    if t and t.index[x] then return x ~= y and M.under(t, t.index[x], y) end
    return try(function() return mesh:BoneIsChildOf(FName(x), FName(y)) end) == true
  end
  local out = {}
  for _, c in ipairs(list) do
    -- (nor a twist bone with a body of its own, CH_P_EVE_14's Ab-L-Thigh-Tw0: the off-axis test is the pose's, and
    -- with the leg turned it stood 3 cm off, the thigh's own skin and both straps under it kept on her, playtest)
    if not c:find("^Bip001") and not c:find("%-Tw%d+$") and under(c, bone) then
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
  local tops, stay = {}, {}
  local span = len(sub(b, a))
  for _, c in ipairs(out) do
    local inner = false
    for _, d in ipairs(out) do if d ~= c and under(c, d) then inner = true end end
    if not inner then
      -- a strap: on the body if its top is behind the plane, else it goes with the limb (not kept)
      local far = 0
      for _, d in ipairs(list) do
        local l = (d == c or under(d, c)) and bone_loc(mesh, d)
        if l and axis and span > 0 then far = math.max(far, dot(sub(l, a), axis) / span) end
      end
      local top = bone_loc(mesh, c)
      if far <= 1 and top and at and n then
        if dot(sub(top, at), n) <= 0 then tops[#tops + 1] = c; stay[c] = true end
      else
        tops[#tops + 1] = c
      end
    end
  end
  return tops, stay
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
  local nb = try(function() return mesh:GetNumBones() end) or 0
  local under = function(x, y) return try(function() return mesh:BoneIsChildOf(FName(x), FName(y)) end) == true end
  local skip, list = {}, {}
  for h in nosink_list(mesh):gmatch("[^,]+") do skip[tonumber(h, 16)] = true end
  for i = 0, nb - 1 do
    local nm = try(function() return mesh:GetBoneName(i):ToString() end) or "None"
    local chain = nm == top or under(nm, top)
    if chain and nm ~= top then skip[i] = nil
    elseif not chain and (nm == limb or under(nm, limb)) then skip[i] = true end
  end
  for i = 0, nb - 1 do if skip[i] then list[#list + 1] = string.format("%x", i) end end
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
  local a, b = bone_loc(mesh, part.from or bone), bone_loc(mesh, part.to)
  if not (a and b) then log("cut skipped: no bone transform for " .. tostring(bone)); return nil end
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
    log(string.format("face %s: %s", name_of(face), fr))
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
    local tree, ma = M.bone_tree(mesh), addr(mesh)
    for _, c in ipairs(cuts) do
      if c.addr == ma and c.bone ~= bone and PARTS[c.bone] then
        local inside = tree and tree.index[c.bone] and M.under(tree, tree.index[c.bone], bone)
        if inside == nil then inside = try(function() return mesh:BoneIsChildOf(FName(c.bone), FName(bone)) end) == true end
        if inside then gone[#gone + 1] = c.bone end
      end
    end
    local rigid = part.kind == "limb" and bone:find("Thigh") and M.skirt_chains(mesh) or {}
    local f = { string.format("g%x", mesh:GetAddress()) }
    if #kept > 0 or #gone > 0 or #rigid > 0 then
      f[#f + 1] = "0"
      for _, c in ipairs(kept) do
        local i = try(function() return mesh:GetBoneIndex(FName(c)) end)
        if i and i > 0 then f[#f + 1] = string.format("%x", i) end
      end
      -- (KEEP_RIGID, 0x8000 on the index)
      for _, i in ipairs(rigid) do f[#f + 1] = string.format("%x", i + 0x8000) end
      if #rigid > 0 then log(string.format("cut %s: %d skirt chain(s) with no body kept on her", bone, #rigid)) end
    end
    if #gone > 0 then
      f[#f + 1] = "0"
      f[#f + 1] = "0"
      for _, c in ipairs(gone) do
        local i = try(function() return mesh:GetBoneIndex(FName(c)) end)
        if i and i > 0 then f[#f + 1] = string.format("%x", i) end
      end
      log(string.format("cut %s: goes with %s, cut off before, wherever it lies", bone, table.concat(gone, ", ")))
    end
    command(table.concat(f, ","))
  end
  -- an enemy's head is cut like a limb: the plane's mode makes what is past it vanish (Eve's goes on her face mesh)
  local mode = (part.kind == "head" and enemy.cur and not face) and MODE.cut or part.mode
  local r = cut_command(mesh, index, mode, part.radius, at, n, nil, part.kind == "torso" or bone)
  log(string.format("cut %s (%s) at %.2f %s normal %s%s: %s", bone, why, t, v3(at), v3(n), lean, r))
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
    or ((part.kind ~= "head" or (enemy.cur and not fr)) and (num(r, "limb") or 0) == 0) then
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
    if (q.why == "death" or q.why == "after") and rule and ctx.animated and ctx.animated() and ctx.on_need_ragdoll then
      try(function() ctx.on_need_ragdoll(leg and "a leg off" or head and "beheaded" or "an arm off") end)
    end
    q.c = cut_limb(q.pawn, q.mesh, b, q.why, blow, q.face, q.blade)
    mark("cut " .. b)
    if q.c then q.bone = b; break end
  end
  if not q.bone then log("nothing cut (" .. q.why .. ")"); return false end
  q.entry = { mesh = q.mesh, addr = addr(q.mesh), bone = q.bone, sm = enemy.asset(q.mesh), riders = {} }
  cuts[#cuts + 1] = q.entry
  if q.c.face then cuts[#cuts + 1] = { mesh = q.c.face, addr = addr(q.c.face), bone = "face" } end
  q.parent = parent_bone(q.mesh, q.bone)
  -- a head's own opening is the bottom of the face's neck
  q.ob, q.ol = opening(q.c.result, "b"), q.c.face_result and opening(q.c.face_result, "l") or opening(q.c.result, "l")
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
  M.pair(q.ob, q.ol)
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
  -- (and the spine bones the stubs look for her back on: back_on, and the cut bone's far end: the stump bone's axis)
  local far = PARTS[q.bone] and PARTS[q.bone].to
  q.posed = M.snap({ { q.mesh, { q.rideB, q.rideL, q.parent or q.bone, q.bone, "Bip001-Spine1", far } } })
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
function M.stage_caps(q)
  M.posed = q.posed
  if cfg().caps ~= false then
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
    q.caps[1], q.kinds[1] = cap(q.pawn, q.mesh, q.ob, q.rideB)
    q.caps[2], q.kinds[2] = cap(q.pawn, q.mesh, q.ol, q.rideL)
    M.riders(q, q.caps[1], q.rideB)
    M.riders(q, q.caps[2], q.rideL)
    mark("caps")
  end
  M.posed = nil
end
function M.stage_stubs(q)
  M.posed = q.posed
  -- a bone in both stumps (the head's: the neck's spine); its look (spine or limb bone) goes by the cut's bones
  if cfg().caps ~= false then
    local spine = not (PARTS[q.bone] and PARTS[q.bone].kind == "limb")
    q.stubs[#q.stubs + 1] = stub(q.pawn, q.mesh, q.ob, q.parent or q.bone, q.rideB, spine)
    M.riders(q, q.stubs[#q.stubs], q.rideB)
    q.pieceStub = stub(q.pawn, q.mesh, q.ol, q.bone, q.rideL, spine)
    q.stubs[#q.stubs + 1] = q.pieceStub
    M.riders(q, q.pieceStub, q.rideL)
    mark("stubs")
  end
  M.posed = nil
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
    -- (each a few ticks off the last one's beat: every opening pulsing on the same tick reset 4-6 effects in one,
    -- 8-12 ms, a stutter that went on for seconds after a cut, playtest)
    bleeds[#bleeds + 1] = { comp = c, left = left, every = every, n = (#bleeds * 3) % every }
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

-- a broken constraint takes its "don't collide" pair with it, and the two bodies overlap at the joint: the piece got
-- shoved out of the stump every frame (an upper body cut off a standing Eve spun wildly against her kinematic hips).
-- So after a cut her bodies stop colliding with each other (PhysicsBody = 5), until she recovers. Not while her arms
-- collide with her chest (ctx.arm_pairs, main.lua): the collision table keeps every other pair apart, a broken
-- joint's too, so only the arms and chest go on colliding; keep false (a split that leaves one of those bodies on the
-- other half, invisible on hers) turns that off too
local function no_self_collision(mesh, keep)
  if keep and ctx.arm_pairs then return end
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
    collision_saved = c
    world = string.format(", world collision on (was %s, enabled %s)%s", tostring(c.profile), tostring(c.enabled),
      c.cap and string.format(", her capsule ignores it (was %s)", tostring(c.capResp)) or "")
    -- the piece weighs what a body part weighs, not the outfit's 100 kg chest and 80 kg cape links (active.lua does
    -- this for ragdolls)
    if ctx.on_piece then
      local m = try(function() return ctx.on_piece(q.pawn, q.mesh) end)
      if m then world = world .. ", " .. m end
    end
  end
  mark("collision")
  no_self_collision(q.mesh, true)
  mark("self collision")
  -- off it goes: the constraint at the limb's root breaks (its bodies start simulating if she was alive)
  local skip = {}
  for _, c in ipairs(q.c.kept or {}) do skip[c] = true end
  local tops = M.break_limb(q.mesh, q.bone, q.c.at, skip)
  if not enemy.cur and PARTS[q.bone] and PARTS[q.bone].kind == "head" then vox.cut() end
  local broke = true
  if #tops > 0 then world = world .. ", no body on " .. q.bone .. ": broke " .. table.concat(tops, ",") end
  mark("break")
  -- the piece collides with the rest of her from here on (main.lua, physfix.piece_collision), in her ragdoll only:
  -- standing, the rest of her is kinematic and the animation drives it, and her thigh, moving with the idle, threw
  -- her hand that hung beside it off at 2500 cm/s, the upper body with it (playtest)
  if ctx.piece_collision and not enemy.cur and not still then try(function() ctx.piece_collision(q.mesh, { q.bone }) end) end
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
  local held = M.hold_open(q, #tops > 0 and tops or { q.bone }, fling)
  if held ~= "" then world = world .. ", " .. held else fling() end
  mark("throw")
  -- (a smash's piece is gone: its cap and stub stay hidden, it neither drips nor bleeds)
  for i, a in pairs(q.caps) do if valid(a) and not (q.smash and i == 2) then try(function() a:SetActorHiddenInGame(false) end) end end
  for _, a in pairs(q.stubs or {}) do
    if valid(a) and not (q.smash and a == q.pieceStub) then try(function() a:SetActorHiddenInGame(false) end) end
  end
  mark("show caps")
  if q.smash then
    q.entry.smashed = true
    local ok, err = pcall(M.smashed.out, q)
    if not ok then log("smash failed: " .. tostring(err)) end
    mark("smash")
  end
  if g.blood ~= false then
    if not enemy.cur then blood_up(q.pawn) end
    if q.parent then track_opening(q, q.caps[1], q.ob, q.mesh, q.rideB or q.parent) end
    if not q.smash then track_opening(q, q.caps[2], q.ol, q.mesh, q.rideL or q.bone) end
  end
  mark("blood")
  -- the splat and the sound the next tick, the bleeds the one after: each its own frame (the opening's was 25-43 ms
  -- with them, a visible stutter at every cut, playtest)
  local at = q.c.at
  later[#later + 1] = { n = 1, fn = function()
    if g.blood ~= false then
      if g.sliceFx == true then niagara(FX.slice, q.pawn, nil, at, false) end
      M.splat(q.pawn, at)
    end
    -- a leg is as big a cut as the head or the waist
    -- (a hit after her death too: the small slice alone went unheard, playtest)
    if q.smash then sfx("smash", q.pawn, at, true); return end
    sfx((q.why == "after" or q.bone == "Bip001-Head" or q.bone == "Bip001-Spine1" or q.bone:find("Thigh") or q.bone:find("Calf"))
      and "big" or "cut", q.pawn, at)
  end }
  if g.blood ~= false then
    -- bleed from both openings, for a while: from the cap, which rides on that side's bone, else from the
    -- opening's centre on the bone; oriented like that bone (the effect was made for bone attachment). Out of the
    -- opening's frame: it was 10-15 ms of it (playtest 41)
    local left = math.floor((g.bleedTime or 2.5) / TICK_S + 0.5)
    later[#later + 1] = { n = 2, fn = function()
      if not valid(q.mesh) then return end
      if q.parent then bleed_from(q, q.caps[1], q.ob, q.rideB or q.parent, left) end
      if not q.smash then bleed_from(q, q.caps[2], q.ol, q.rideL or q.bone, left) end
    end }
  end
  mark("sound, bleed")
  log(string.format("%s off (%s): %s, constraint broken=%s, caps %s / %s%s", q.bone, q.why, k, tostring(broke == true),
    tostring(q.kinds[1]), tostring(q.kinds[2]), world))
  M.attached_report(q)
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

-- other mods' copies of a cut mesh on its pose: Ultra Violence draws her outfit and face blood on a see-through copy
-- of the mesh (the same asset following her, with its own weights). It kept her whole skin and stretched from the
-- stump to the flying limb, so each copy gets the cut mesh's weights ("y") and loses them with its own
M.copies = { of = {}, dirty = {}, next = 0 } -- of[mesh addr] = { [copy addr] = copy }
function M.copies_find(mesh)
  local out, me = {}, addr(mesh)
  local sk = me and try(function() return addr(mesh.SkeletalMesh) end)
  if not sk then return out end
  local ours = {}
  for _, c in ipairs(clones) do local a = addr(c); if a then ours[a] = true end end
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
  local list = {}
  for i = 1, math.min(#send, 16) do
    list[i] = string.format("%x", send[i]:GetAddress())
    M.lod0(send[i], true)
  end
  local r = command(string.format("y%x,0,%s", me, table.concat(list, ",")))
  log(string.format("%s's cut weights on %d cop%s of it on her pose (another mod's): %s", name_of(mesh), #list,
    #list == 1 and "y" or "ies", r))
end
function M.copies_clear(a)
  local had = M.copies.of[a]
  M.copies.of[a], M.copies.dirty[a] = nil, nil
  if not had then return end
  local list = {}
  for _, c in pairs(had) do
    if valid(c) then list[#list + 1] = string.format("%x", c:GetAddress()); M.lod0(c, false) end
  end
  if #list > 0 then log(string.format("cut weights off %d cop%s: %s", #list, #list == 1 and "y" or "ies",
    command(string.format("y%x,0,%s", a, table.concat(list, ","))))) end
end
-- the meshes cut this frame, and every half second the copies made since (Ultra Violence remakes its copy when her
-- blood or outfit changes)
function M.copies_flush()
  local now = os.clock()
  local look = now >= M.copies.next
  if not look and not next(M.copies.dirty) then return end
  if look then M.copies.next = now + 0.5 end
  local seen = {}
  for _, c in ipairs(cuts) do
    local a = c.addr
    if a and not seen[a] and (look or M.copies.dirty[a]) and valid(c.mesh) and addr(c.mesh) == a then
      seen[a] = true
      M.copies_sync(c.mesh, M.copies.dirty[a])
    end
  end
  M.copies.dirty = {}
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

local function side_cut(comp, bone, at, n, gone)
  local index = try(function() return comp:GetBoneIndex(FName(bone)) end)
  if not index or index < 0 then return "err no bone " .. bone end
  send_nosink(comp, nil, true, not enemy.cur and M.side_drivers(comp, gone) or nil)
  return command(string.format("c%x,0,%x,%x,0", comp:GetAddress(), index, MODE.side), at, n)
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
local function split_chains(comp, at, n)
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
    local q = p
    while top and q and not q:find("^Bip001") do
      if has[q] then top = false end
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
  local function world(i) return add(add(c, add(scale(u, gx[i]), scale(w, gy[i]))), scale(z, push)) end
  local pieces, order = {}, {}
  for _, t in ipairs(tris) do
    local m = one and c or scale(add(add(world(t[1]), world(t[2])), world(t[3])), 1 / 3)
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
local function skin_lid(comp, actor, pmc, pc, ride)
  local chain = {}
  -- (the bones as noted at the cut, M.posed: the lid's points are where the opening was then)
  local posed = M.posed and M.posed[addr(comp)] or {}
  for _, b in ipairs(ride) do
    local tm = posed[b] or bone_tm(comp, b)
    if tm then chain[#chain + 1] = { name = b, tm = tm } end
  end
  if #chain == 0 or not pc.wv then return false end
  local v = {}
  for k, p in ipairs(pc.wv) do
    local ja, jb, t, bd = 1, 1, 0, nil
    for j = 1, math.max(#chain - 1, 1) do
      local a, b = chain[j].tm.t, chain[math.min(j + 1, #chain)].tm.t
      local ab = sub(b, a)
      local l2 = dot(ab, ab)
      local x = l2 > 1e-6 and math.min(math.max(dot(sub(p, a), ab) / l2, 0), 1) or 0
      local d = sub(p, add(a, scale(ab, x)))
      d = dot(d, d)
      if not bd or d < bd then ja, jb, t, bd = j, math.min(j + 1, #chain), x, d end
    end
    local qa, qb = qinv(chain[ja].tm.q), qinv(chain[jb].tm.q)
    v[k] = { a = ja, b = jb, t = t, la = qrot(qa, sub(p, chain[ja].tm.t)), lb = qrot(qb, sub(p, chain[jb].tm.t)),
      na = qrot(qa, pc.wn[k]), nb = qrot(qb, pc.wn[k]) }
  end
  local names = {}
  for j, c2 in ipairs(chain) do names[j] = c2.name end
  skinned[#skinned + 1] = { actor = actor, pmc = pmc, comp = comp, bones = names, v = v, n = 0, half = #pc.wv / 2 }
  return true
end

local lid_ms = { n = 0, sum = 0, top = 0 }
local lids_step
local function lids_tick()
  if #skinned == 0 then
    if lid_ms.n > 0 then
      log(string.format("split lids followed her for %d ticks: %.1f ms a tick, %.1f at most", lid_ms.n, lid_ms.sum / lid_ms.n, lid_ms.top))
      lid_ms = { n = 0, sum = 0, top = 0 }
    end
    return
  end
  local t0 = os.clock()
  lids_step()
  local ms = (os.clock() - t0) * 1000
  lid_ms.n, lid_ms.sum, lid_ms.top = lid_ms.n + 1, lid_ms.sum + ms, math.max(lid_ms.top, ms)
end
lids_step = function()
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
        sig[#sig + 1] = m.q.X; sig[#sig + 1] = m.q.Y; sig[#sig + 1] = m.q.Z; sig[#sig + 1] = m.q.W
      end
      local still = s.sig ~= nil
      for k = 1, #sig do if still and math.abs(sig[k] - s.sig[k]) > (k % 7 >= 1 and k % 7 <= 3 and 0.05 or 0.0003) then still = false end end
      if still then ok = true
      else
        s.sig = sig
        local verts, normals = {}, {}
        local half = s.half or 0
        -- (the back side's vertices are the front's, its normals turned round)
        local tx, ty, tz, iq = at.t.X, at.t.Y, at.t.Z, at.q
        for k, w in ipairs(s.v) do
          if half > 0 and k > half then
            local p, n = verts[k - half], normals[k - half]
            verts[k], normals[k] = p, vec(-n.X, -n.Y, -n.Z)
          else
            local A, B = tms[w.a], tms[w.b]
            local u = w.t
            local pa, pb = qrot(A.q, w.la), qrot(B.q, w.lb)
            local px = (A.t.X + pa.X) * (1 - u) + (B.t.X + pb.X) * u - tx
            local py = (A.t.Y + pa.Y) * (1 - u) + (B.t.Y + pb.Y) * u - ty
            local pz = (A.t.Z + pa.Z) * (1 - u) + (B.t.Z + pb.Z) * u - tz
            verts[k] = qrot(iq, vec(px, py, pz))
            local na, nb = qrot(A.q, w.na), qrot(B.q, w.nb)
            normals[k] = qrot(iq, norm(vec(na.X * (1 - u) + nb.X * u, na.Y * (1 - u) + nb.Y * u, na.Z * (1 - u) + nb.Z * u)) or na)
          end
        end
        ok = try(function() s.pmc:UpdateMeshSection_LinearColor(0, verts, normals, {}, {}, {}, {}, {}, {}); return true end)
          or try(function() s.pmc:UpdateMeshSection_LinearColor(0, verts, normals, {}, {}, {}); return true end)
        if not ok then log("split lid: the procedural mesh didn't take the update, it stays rigid") end
      end
    end
    if not ok then table.remove(skinned, i) end
  end
end

-- one half's caps: the lid over the opening along the spine, in pieces riding the spine bones, and a domed one over
-- the neck where the head stayed on the other half (the DLL traces both: s0, n)
local function split_caps(q, comp, r, list)
  if cfg().caps == false then return end
  local g = cfg()
  local ride = SPLIT_RIDE.of(q, comp)
  local o = opening(r, "s0")
  if o and o.p then
    local pieces, nt = flat_lid(o, comp, g.splitLidGrow or 0.4, g.splitLidPush or 0.2, ride)
    mark("lid shape")
    local made, bent = 0, 0
    -- the lid bends with the spine up to the neck, as the sheet behind it does (SPLIT_RIDE.lid)
    local lid_ride = SPLIT_RIDE.lid(q, comp)
    for _, pc in ipairs(pieces or {}) do
      local a, kind, pmc = cap(q.pawn, comp, o, pc.bone, pc.built)
      -- a split's lid on the meat material, solid (capMatte.splitLids false): on the matte master it didn't look
      -- solid (playtest)
      if valid(pmc) and type(g.capMatte) == "table" and g.capMatte.splitLids == false then
        set_cap_material(pmc, load_obj(g.capMaterial or CAP_MATERIAL), true)
      end
      if a and pmc and pc.skin and skin_lid(comp, a, pmc, pc, lid_ride) then bent = bent + 1 end
      if a then
        made = made + 1
        list[#list + 1] = { actor = a, o = o, ride = pc.bone, comp = comp, kind = kind, whole = pc.skin }
      end
    end
    mark("lid pieces")
    local ns = spine_halves(q, comp, o, list)
    mark("spine pieces")
    log(string.format("split lid on %s: %d points, %d triangles, %d pieces (%d bending with the spine), %d spine pieces", name_of(comp),
      #o.p, nt or 0, made, bent, ns))
  elseif o then
    local at = nearest_bone(comp, o.c, ride)
    local a, kind = cap(q.pawn, comp, o, at)
    if a then list[#list + 1] = { actor = a, o = o, ride = at, comp = comp, kind = kind } end
  end
  local nk = opening(r, "n")
  if nk then
    local nb = "Bip001-Neck"
    for _, b in ipairs(ride) do if b == nb then nb = nil; break end end
    nb = nb and nearest_bone(comp, nk.c, ride) or "Bip001-Neck"
    local a, kind = cap(q.pawn, comp, nk, nb)
    if a then list[#list + 1] = { actor = a, o = nk, ride = nb, comp = comp, kind = kind } end
  end
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

-- a cut through her body is one of two kinds: across her (square to her spine, under her bust, leaned a little) or
-- down her length (through her middle, left from right). A blade within 45 degrees of her spine's line goes down it,
-- else across. Whatever angle the blade had, the cut snaps to one of them: free angles cut slabs off her chest and
-- slivers off her flank, each with a rule of its own to clean it up.
-- (A third kind, diagonal from a shoulder to the other hip at a set ~45 degrees, is left out for now.)
M.ALONG = math.sqrt(0.5)
-- her right, square to her spine (axis): from her left hip and shoulder joints to her right ones, which move with
-- her pelvis and chest whatever her arms and legs do
function M.her_right(mesh, axis, bl)
  bl = bl or function(b) return bone_loc(mesh, b) end
  local r = vec(0, 0, 0)
  for _, s in ipairs({ "Thigh", "UpperArm" }) do
    local l, rr = bl("Bip001-L-" .. s), bl("Bip001-R-" .. s)
    if l and rr then r = add(r, sub(rr, l)) end
  end
  return norm(sub(r, scale(axis, dot(r, axis))))
end

-- the plane: through the spine, its normal square to the spine (from the swing, else her right)
local function split_plane(q)
  local pel, head = bone_loc(q.mesh, "Bip001-Pelvis"), bone_loc(q.mesh, "Bip001-Head")
  local at = bone_loc(q.mesh, "Bip001-Spine1")
  if not (pel and head and at) then return nil end
  local axis = norm(sub(head, pel)) or vec(0, 0, 1)
  local function square(v) return v and norm(sub(v, scale(axis, dot(v, axis)))) end
  local n = not q.middle and square(q.out) or nil
  local from = "swing"
  if not n then
    from = "her right"
    n = square(try(function() local v = q.pawn:GetActorRightVector(); return vec(v.X, v.Y, v.Z) end)) or vec(0, 1, 0)
  end
  local tilt = q.middle and 0 or (cfg().tilt or 0.25) * 0.3
  n = square(add(n, vec((math.random() - 0.5) * tilt, (math.random() - 0.5) * tilt, (math.random() - 0.5) * tilt))) or n
  -- with no swing to follow, turned at random within splitYaw about her spine (it was the same plane every time)
  if from == "her right" and not q.middle then
    local th = (math.random() * 2 - 1) * math.rad(cfg().splitYaw or 15)
    n = square(add(scale(n, math.cos(th)), scale(cross(axis, n), math.sin(th)))) or n
  end
  -- left from right only, at most splitYaw off her middle: a plane facing her front cut a slab off her chest
  local r = M.her_right(q.mesh, axis)
  if r and q.middle then n, from = r, "her middle"
  elseif r then
    if dot(n, r) < 0 then r = scale(r, -1) end
    local max = math.rad(cfg().splitYaw or 15)
    if math.acos(math.max(-1, math.min(1, dot(n, r)))) > max then
      local f = norm(sub(n, scale(r, dot(n, r))))
      n = f and norm(add(scale(r, math.cos(max)), scale(f, math.sin(max)))) or r
      from = from .. string.format(", turned to %.0f deg off her middle", math.deg(max))
    end
  end
  -- splitBeside: leaned about her front-to-back axis from her crotch to that far beside her neck, so the head stays
  -- whole on her half. Her crotch, the gap between her breasts (they sit 4.3 cm either side) and her neck all lie on
  -- her middle, so the lean is small: at 10 cm the cut ran 7 cm off it at the chest, through a breast; at 2, 1.4 cm
  -- Its lower end moves up to splitHipShift cm off her crotch to either side at random, so it runs a little
  -- diagonally (the breasts, 4.3 cm off her middle, see under a third of it; the hip joints are 10 cm off)
  local side, neck = cfg().splitBeside or 2, bone_loc(q.mesh, "Bip001-Neck")
  if side > 0 and neck then
    local t = norm(cross(axis, n))
    local hip = q.middle and 0 or (math.random() * 2 - 1) * (cfg().splitHipShift or 4)
    local low = add(pel, scale(n, hip))
    local d = sub(sub(neck, scale(n, side)), low)
    local m = t and norm(cross(t, d))
    if m then
      if dot(m, n) < 0 then m = scale(m, -1) end
      at, n, from = low, m, from .. string.format(", beside the neck, %.1f cm off her crotch", hip)
    end
  end
  return at, n, from
end

-- the outfit's post-process AnimBP (CH_P_EVE_09_AnimBP) poses the rig's Dm- drivers after her arms and legs. A split
-- half has too few other helpers, so some of its sinks are on drivers of the limbs it keeps (Dm-R-Trape, Dm-R-AX2-Root:
-- "a sink ... a Dm- driver moves" in the harness): as those limbs flailed in the ragdoll the drivers carried the
-- collapsed skin out through the lid, spikes and patches over the cut face (playtest). Off on both halves before the
-- cut (prep waits 3 frames), so the drivers hold their place on the spine and pelvis as the harness has them; back on
-- for her when the split is undone or she is reused
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

-- arm cuts before it (a blade through her arm raised to block, then down her length: M.blow) are kept; any other
-- cut and she isn't split
M.ARM_CUTS = { ["Bip001-L-UpperArm"] = true, ["Bip001-L-Forearm"] = true, ["Bip001-R-UpperArm"] = true, ["Bip001-R-Forearm"] = true }
local function stage_split_prep(q)
  q.armcuts = {}
  for _, c in ipairs(cuts) do
    if c.addr == addr(q.mesh) then
      if not M.ARM_CUTS[c.bone] or cfg().splitArms == false then log("split skipped (" .. q.why .. "): she has been cut already"); return false end
      q.armcuts[#q.armcuts + 1] = c
    end
  end
  q.face = face_of(q.pawn, q.mesh)
  q.body2 = clone_of(q.pawn, q.mesh)
  if not q.body2 then log("split skipped: could not clone the body"); return false end
  if cfg().splitRigOff ~= false then
    log(string.format("split: the rig's post-process AnimBP off: hers %s, the copy's %s",
      M.rig(q.mesh, false) and "ok" or "failed", M.rig(q.body2, false) and "ok" or "failed"))
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

-- each half's break keeps the limbs that half keeps on one piece. Her half breaks only when every limb she keeps
-- hangs off the break (with the head): a lengthwise slice keeps an arm and a leg each side, and her half broke at
-- Spine2, tearing her thigh from her shoulder across 1.6 m of skin (playtest 44). The copy's break is the spine bone
-- hers is at, or the next one up while any limb the copy keeps hangs off it (the Biped thighs' parent is Bip001-Spine,
-- not the pelvis): a waist split just over the pelvis broke both halves there, and the copy let its legs go with the
-- spine (playtest 40)
function M.hangs_off(mesh, l, b) return try(function() return mesh:BoneIsChildOf(FName(l), FName(b)) end) == true end
function M.her_break(mesh, spine, kept)
  if not spine then return nil end
  for _, l in ipairs(kept or {}) do if not M.hangs_off(mesh, l, spine) then return nil end end
  return spine
end
function M.copy_break(mesh, spine, kept)
  if not spine then return nil end
  local si
  for i, b in ipairs(SPINE_CHAIN) do if b == spine then si = i end end
  while si do
    local free = true
    for _, l in ipairs(kept or {}) do if M.hangs_off(mesh, l, SPINE_CHAIN[si]) then free = false; break end end
    if free then return SPINE_CHAIN[si] end
    si = SPINE_CHAIN[si + 1] and si + 1 or nil
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
    -- a waist split keeps both arms on her half and gives both legs to the copy: in an animated fall the
    -- plane square to her lower spine ran flat through her bent hips, a thigh each side, and her half's chest flew
    -- off its pelvis stretching 3.7 m of skin (playtest 42). Squared again from her hips to her chest as she is now,
    -- else a waist cut
    if q.plane.waist and not M.waist_sides(q.mesh, at, n) then
      local a, b, c = bone_loc(q.mesh, "Bip001-Spine"), bone_loc(q.mesh, "Bip001-Spine1"), bone_loc(q.mesh, "Bip001-Spine2")
      local l, r = bone_loc(q.mesh, "Bip001-L-Thigh"), bone_loc(q.mesh, "Bip001-R-Thigh")
      local n2 = c and l and r and norm(sub(c, scale(add(l, r), 0.5)))
      if a and b and n2 and M.waist_sides(q.mesh, add(a, scale(sub(b, a), 0.4)), n2) then
        at, n, from = add(a, scale(sub(b, a), 0.4)), n2, from .. ", squared to her hips"
      else
        log(string.format("split (%s): the waist plane puts a leg or an arm on the wrong half: a waist cut instead", q.why))
        q.degenerate = true
        return false
      end
    end
    q.spine = spine_break(q.mesh, at, n)
  else
    at, n, from = split_plane(q)
    -- the head on her half's side (a leaned plane runs past it)
    local head = at and bone_loc(q.mesh, "Bip001-Head")
    if head and dot(sub(head, at), n) < 0 then n = scale(n, -1) end
    if at then q.spine = spine_break(q.mesh, at, n) end
  end
  if not at then log("split skipped: no bone transforms"); return false end
  q.c = { at = at, n = n }
  q.gone1, q.gone2 = limb_sides(q.mesh, at, n)
  q.spine = M.her_break(q.mesh, q.spine, q.gone2)
  q.spine2 = M.copy_break(q.mesh, q.spine, q.gone1)
  place_like(q.body2, q.mesh)
  local p = command(string.format("p%x,%x", q.mesh:GetAddress(), q.body2:GetAddress()))
  local neg = scale(n, -1)
  -- recorded before they are checked, so a failed half is undone with the rest
  -- her arm cuts before it: her weights and the sinks saved ("S": a split that fails puts them back, "R"; "x" would take
  -- the arm cuts with it), and the copy cut from her weights ("y"), the stump and the flying arm in them. Cut from the
  -- mesh's own, the copy's half put the arm's seam back on the shoulder, stretched out to where the arm flew (harness)
  local saved = false
  if #q.armcuts > 0 then
    local sv = command(string.format("S%x,0", q.mesh:GetAddress()))
    saved = sv:sub(1, 2) == "ok"
    local cp = saved and command(string.format("y%x,0,%x", q.mesh:GetAddress(), q.body2:GetAddress())) or "not saved"
    local names = {}
    for _, c in ipairs(q.armcuts) do names[#names + 1] = c.bone end
    log(string.format("split after the arm cut%s (%s): her weights %s, on the copy %s", #names > 1 and "s" or "", table.concat(names, ", "), sv, cp))
    if cp:sub(1, 9) ~= "ok copied" then
      if saved then command(string.format("R%x,0", q.mesh:GetAddress())) end
      log("split skipped: the copy can't take her cut weights")
      return false
    end
  end
  cuts[#cuts + 1] = { mesh = q.mesh, addr = addr(q.mesh), bone = "split", saved = saved or nil, copy = saved and addr(q.body2) or nil }
  cuts[#cuts + 1] = { mesh = q.body2, addr = addr(q.body2), bone = "split copy" }
  -- each half keeps the limbs on its side whole and lets the others go; the halves share the mesh's sinks, and each
  -- half's skin lets go of every helper past the plane, so the other half's sinks never pull on it (q.gone1, q.gone2:
  -- limb_sides, above)
  -- her half keeps the head, face and hair whole, on their own animation; the copy's neck closes. The DLL holds one
  -- neck plane, for the next split cut of that component
  local front, back = split_chains(q.mesh, at, n)
  local keep1, keep2 = {}, {}
  for _, b in ipairs(q.gone2) do keep1[#keep1 + 1] = b end
  for _, b in ipairs(front) do keep1[#keep1 + 1] = b end
  for _, b in ipairs(q.gone1) do keep2[#keep2 + 1] = b end
  for _, b in ipairs(back) do keep2[#keep2 + 1] = b end
  send_limbs(q.mesh, q.gone1, keep1, back, SPLIT_RIDE.lid(q, q.mesh), q.spine, true)
  local h1 = send_neck(q.mesh, 1)
  local r1 = side_cut(q.mesh, SPLIT_SINK, at, n, q.gone1)
  -- her spine as her half was cut: the lid's points are placed against it (skin_lid), as sbslice placed the sheet.
  -- Noted a frame later with the copy's, an animated fall had moved her on and the lid sat off the sheet
  q.posed1 = M.snap({ { q.mesh, { "Bip001-Neck", table.unpack(SPLIT_RIDE.of(q, q.mesh)) } } })
  -- the copy's cut the next tick (M.stage_split_copy): each cut is the engine building a new skin weight buffer,
  -- 15-30 ms, and the two in one frame were a stutter at the death (playtest 41). She is held still meanwhile, and
  -- the new weights show nothing till the opening
  q.cut1 = { from = from, p = p, h1 = h1, r1 = r1, front = front, back = back, keep2 = keep2, neg = neg }
  return true
end
function M.stage_split_copy(q)
  local c1 = q.cut1
  q.cut1 = nil
  local at, n, from, p, h1, r1, front, back = q.c.at, q.c.n, c1.from, c1.p, c1.h1, c1.r1, c1.front, c1.back
  send_limbs(q.body2, q.gone2, c1.keep2, front, SPLIT_RIDE.lid(q, q.body2), q.spine2, false)
  local h2 = send_neck(q.body2, 2)
  local r2 = side_cut(q.body2, SPLIT_SINK, at, c1.neg, q.gone2)
  log(string.format("split (%s) at %s normal %s (%s), pose %s, limbs %s | %s, chains %s | %s, spine breaks at %s, neck %s | %s",
    q.why, v3(at), v3(n), from, p, table.concat(q.gone2, ","), table.concat(q.gone1, ","), table.concat(front, ","),
    table.concat(back, ","), tostring(q.spine) .. (q.spine2 ~= q.spine and " (the copy's at " .. tostring(q.spine2) .. ")" or ""), h1, h2))
  log("split body: " .. r1)
  log("split body copy: " .. r2)
  -- a half that cut nothing falls back to a waist cut too: across her waist in an animated death that had just gone
  -- ragdoll, the copy vanished 101400 vertices with no seam and none sunk, and she died whole (playtest, CH_P_EVE_29)
  if not (ok_cut(r1) and ok_cut(r2)) then
    if r1:sub(1, 2) == "ok" and r2:sub(1, 2) == "ok" then
      log(string.format("split (%s) failed: the %s cut nothing: a waist cut instead", q.why, ok_cut(r1) and "copy" or "body"))
      q.degenerate = true
    end
    return false
  end
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
  -- (the lids the next tick: with them the split held one frame 200 ms, twenty-ninth playtest)
  q.caps, q.r1, q.r2 = {}, r1, r2
  return true
end

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
local function settle_half(comp, at, n, push, gone, spine, upper)
  local broke = {}
  for _, b in ipairs(gone or {}) do
    M.break_limb(comp, b, bone_loc(comp, b) or at)
    broke[#broke + 1] = b
  end
  if spine then
    try(function() comp:BreakConstraint(vec(0, 0, 0), bone_loc(comp, spine) or at, FName(spine)) end)
    if not upper then broke[#broke + 1] = spine end
  end
  local pa = ctx.physics_of(comp)
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
    -- (not the neck: halved, the 4.5 kg head shook on it)
    -- what the half lets go of falls free, invisible, at its own mass: at 0.02 kg the chains shook and went through
    -- the floor, and kinematic they froze in the air where she was cut, with whatever still rode them (a floating
    -- piece of the outfit)
    if off then
      if ctx.on_free then try(function() ctx.on_free(comp, bn) end) end
    elseif math.abs(h) < 4 and bn ~= "Bip001-Neck" and bn ~= "Bip001-Head" then set_mass(comp, bn, 0.5) end
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
  rehome(q, b2, q.c.at, q.c.n)
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
  local b1 = settle_half(q.mesh, at, n, push, q.gone1, q.spine, true)
  -- the copy's head is closed over: its body comes off and weighs nothing, like a gone limb's
  local gone2 = { table.unpack(q.gone2 or {}) }
  if not (q.spine and q.spine ~= "Bip001-Head") then gone2[#gone2 + 1] = "Bip001-Head" end
  local b2l = settle_half(b2, at, scale(n, -1), push, gone2, q.spine2, false)
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
    blood_up(q.pawn)
    niagara(FX.hit, q.pawn, nil, q.hit or at, false)
    M.splat(q.pawn, at)
    -- bleeding along the seam: from the chest and neck lids of each half
    local left = math.floor((g.bleedTime or 2.5) / TICK_S + 0.5)
    for _, c in ipairs(q.caps) do
      if valid(c.actor) and c.kind ~= "spine" and (q.plane or c.whole or c.ride == "Bip001-Spine2" or c.ride == "Bip001-Neck" or c.ride == "Bip001-Spine") then
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
    q.anim and (q.anim > 0 and string.format(", her fall plays on for %.1f s", q.anim) or ", she ragdolls now") or ""))
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
    -- a half's lids a tick (both in one were 35-43 ms), then the copy's physics bodies, made ahead of the opening
    M.posed = q.posed
    split_caps(q, q.mesh, q.r1, q.caps)
    M.posed = nil
    q.stage, q.wait = "caps2", 0
    return
  elseif q.stage == "caps2" then
    M.posed = q.posed
    split_caps(q, q.body2, q.r2, q.caps)
    M.posed = nil
    mark("lids")
    if not q.anim then M.split_bodies(q); q.stage, q.wait = "masses", 0; return end
    q.stage, q.wait = "open", 1
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
    if q.anim then q.stage, q.t, q.seen = "anim", 0, nil; return end
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
    -- (two frames at least: the halves fall on at the speed the animation gave each body)
    if q.t < q.anim or not vel then return end
    pending = nil
    if valid(q.body2) then try(function() q.body2:SetMasterPoseComponent(nil, true) end) end
    for _, c in ipairs(q.copies2 or {}) do if valid(c) then try(function() c:SetMasterPoseComponent(q.body2, true) end) end end
    command(string.format("p%x,%x", q.mesh:GetAddress(), q.body2:GetAddress()))
    mark("copy pose")
    if ctx.on_need_ragdoll then try(function() ctx.on_need_ragdoll("split") end) end
    mark("her ragdoll")
    split_physics(q, vel)
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
    if q.kind == "split" and not q.middle then
      log("split (" .. q.why .. "): once more, straight down her middle")
      M.splitMiddle = true
      local ok = start(q.pawn, q.mesh, q.hit, q.why, "split")
      M.splitMiddle = nil
      if ok then return end
    end
    start(q.pawn, q.mesh, q.hit, q.why, "torso")
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
  local tb = not enemy.cur and PARTS[g.bone or ""] or {}
  local face = not enemy.cur and (kind == "head" or (kind ~= "split" and not blade and tb.kind == "head"))
  -- (an enemy built like her: its face whenever the cut may take the head)
  if enemy.cur and enemy.faced[enemy.cur] then face = kind == "head" or (blade ~= nil and kind ~= "split") end
  face = face and face_of(pawn, mesh) or nil
  local waited = force_lod(mesh)
  if face then waited = force_lod(face) or waited end
  pending = { stage = "cut", wait = waited and 2 or 0, t0 = os.clock(), pawn = pawn, mesh = mesh, hit = hit, why = why, kind = kind,
    face = face, out = out, plane = plane, blade = blade, owner = enemy.cur, bone = M.bone_once, middle = M.splitMiddle,
    smash = M.smash_once and not enemy.cur or nil, fly = aimed and os.clock() - aimed.t < 1 and aimed.d or nil }
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
    log("waist cut: her legs play the fall on, the upper body flies off (" .. legs .. ")")
  elseif anim then
    pending.anim = math.max(tonumber(g.splitAnim) or 0, 0)
    local pa = ctx.physics_of(mesh)
    pending.bodies = {}
    if valid(pa) then
      try(function() pa.SkeletalBodySetups:ForEach(function(_, e) local bs = e:get(); if valid(bs) then pending.bodies[#pending.bodies + 1] = bs.BoneName:ToString() end end) end)
    end
  elseif (why == "death" or why == "after") and halves and ctx.on_need_ragdoll then
    try(function() ctx.on_need_ragdoll(kind) end)
  end
  -- a split comes first, then the fall: she is held where she is until it opens
  if kind == "split" and not anim and ctx.on_hold then try(function() ctx.on_hold(mesh) end) end
  -- its first stage now, in this frame, when nothing waits
  M.pump()
  return true
end

-- that part (a PARTS bone) cut off, whatever tune.gore.bone says (glass.lua: where the hit landed)
function M.slice_bone(pawn, mesh, bone, hit, why)
  if not PARTS[bone] or already_cut(mesh, bone) then return false end
  M.bone_once = bone
  local ok = start(pawn, mesh, hit, why, PARTS[bone].kind)
  M.bone_once = nil
  return ok
end
function M.has_cut(mesh, bone) return already_cut(mesh, bone) end

-- ---- smash (tune.gore.smash, experimental) ----
-- A blunt killing blow (main.lua's blunt_of: a hammer, a fist, a stomp) smashes the part it landed on instead of
-- cutting it clean: the part comes off as any cut does (its stump keeps its cap, bone and bleed), but the piece itself
-- vanishes (its bones hidden on every part of her that has them, a head's hair and what rides it too) and the game's
-- own meat chunks (SM_meat_01-04, its effects' meshes) burst out where it was, with blood; a few drip and pool where
-- they land. Each chunk is a static mesh riding an invisible simulated sphere (its mesh may have no collision)
M.SMASH_MESHES = {
  "/Game/Art/FX/SM/SM_meat_01.SM_meat_01", "/Game/Art/FX/SM/SM_meat_02.SM_meat_02",
  "/Game/Art/FX/SM/SM_meat_03.SM_meat_03", "/Game/Art/FX/SM/SM_meat_04.SM_meat_04",
}
M.SMASH_FX = "/Game/Art/FX/Enviroment/Matrix_XI/Cinematic/ME05_02_EliteNative_Finish/NS_A_MeatSplash.NS_A_MeatSplash"
-- the part a blunt blow at `at` smashes: the arm, leg, head or upper body whose bone runs nearest it, not one already
-- off. With no blow (F6's test death, smash.always) the kind is rolled on the death odds (tune.gore.death: limb, head,
-- torso; a split's share left out), the limb at random: a pick among the parts alone never took the head in 50 F6
-- deaths, and never her body (playtest)
M.SMASH_SEG = { ["Bip001-Spine1"] = { "Bip001-Pelvis", "Bip001-Neck" } }
function M.smash_part(mesh, at)
  local cands = {}
  for bone, p in pairs(PARTS) do
    if not already_cut(mesh, bone) then cands[#cands + 1] = { bone = bone, p = p } end
  end
  table.sort(cands, function(x, y) return x.bone < y.bone end)
  if not at then
    local w = cfg().death or {}
    local odds = { limb = tonumber(w.limb) or 42, head = tonumber(w.head) or 25, torso = tonumber(w.torso) or 15 }
    local by = {}
    for _, c in ipairs(cands) do by[c.p.kind] = by[c.p.kind] or {}; table.insert(by[c.p.kind], c.bone) end
    local sum = 0
    for k, x in pairs(odds) do if not by[k] then odds[k] = 0 else sum = sum + math.max(x, 0) end end
    if sum <= 0 then return nil end
    local r = math.random() * sum
    for _, k in ipairs({ "limb", "head", "torso" }) do
      r = r - math.max(odds[k], 0)
      if r <= 0 and by[k] then return pick(by[k]), nil, k end
    end
    return nil
  end
  local best, bd
  for _, c in ipairs(cands) do
    local bone, p = c.bone, c.p
    local seg = M.SMASH_SEG[bone]
    local a, b = bone_loc(mesh, seg and seg[1] or p.from or bone), bone_loc(mesh, seg and seg[2] or p.to)
    -- (the head's own bone is the skull's base: its segment runs on up past it, to the top of her head)
    if a and b and p.kind == "head" then b = vec(b.X + (b.X - a.X) * 3, b.Y + (b.Y - a.Y) * 3, b.Z + (b.Z - a.Z) * 3) end
    if a and b then
      a, b = vec(a.X, a.Y, a.Z), vec(b.X, b.Y, b.Z)
      local ab = sub(b, a)
      local t = math.max(0, math.min(1, dot(sub(at, a), ab) / math.max(dot(ab, ab), 1e-4)))
      local d = len(sub(at, add(a, scale(ab, t))))
      if not bd or d < bd then best, bd = bone, d end
    end
  end
  return best, bd, best and PARTS[best].kind
end
-- h: the killing blow (main.lua's death_hit: loc, push/dir). True when the smash started; false, "later" for her body
-- at the lethal hit (it needs her ragdoll: smashed at the death instead)
function M.smash(pawn, mesh, h, why)
  local bone, d, kind = M.smash_part(mesh, h and h.loc)
  if not bone then log("smash (" .. why .. "): nothing left to smash"); return false end
  if kind == "torso" and h and h.early then
    log("smash (" .. why .. "): her body, at her death")
    return false, "later"
  end
  log(string.format("smash (%s): %s, %s", why, bone, d and string.format("%.0f cm from the blow", d) or "rolled (no blow seen)"))
  M.smash_once = true
  local ok = M.slice_bone(pawn, mesh, bone, h and h.loc, why)
  M.smash_once = nil
  return ok
end
-- the piece hidden: its bones on her mesh and every part of her that has them (outfit pieces, a head's face), and
-- what rides them on a socket (a head's hair, earrings): PBO_None (0), only how they show (PBO_Term on her mesh
-- stopped her ragdoll, playtest 13)
function M.smashed.hide(q)
  local comps, seen = { q.mesh, q.c and q.c.face }, {}
  try(function() q.pawn.MeshInfoList:ForEach(function(_, e) comps[#comps + 1] = e:get().MeshComponent end) end)
  -- (her upper body takes the head along)
  local head = PARTS[q.bone] and (PARTS[q.bone].kind == "head" or PARTS[q.bone].kind == "torso")
  local nb, nv = 0, 0
  local function hide(c)
    local a = valid(c) and addr(c)
    if not a or seen[a] then return end
    seen[a] = true
    if try(function() return c:GetBoneIndex(FName(q.bone)) end) ~= -1
      and try(function() c:HideBoneByName(FName(q.bone), 0); return true end) then
      M.smashed.bones[#M.smashed.bones + 1] = { c = c, b = q.bone }
      nb = nb + 1
    end
  end
  for _, c in ipairs(comps) do hide(c) end
  local function invisible(c)
    local a = valid(c) and addr(c)
    if a and not seen["v" .. a] and try(function() return c:IsVisible() end) == true
      and try(function() c:SetVisibility(false, false); return true end) then
      seen["v" .. a] = true
      M.smashed.shown[#M.smashed.shown + 1] = c
      nv = nv + 1
    end
  end
  if head then
    for _, c in ipairs(hair_of(q.pawn)) do invisible(c) end
    for _, nm in ipairs({ "SBHair", "SBPonytail", "SBPonytailShort" }) do invisible(try(function() return q.pawn[nm] end)) end
  end
  -- what rides the piece's bones on her mesh or face (not our caps and stubs: the piece's stay hidden, see stage_open)
  for _, m in ipairs({ q.mesh, q.c and q.c.face }) do
    if valid(m) then
      local kids = {}
      try(function() m.AttachChildren:ForEach(function(_, e) kids[#kids + 1] = e:get() end) end)
      for _, k in ipairs(kids) do
        local s = valid(k) and try(function() return k:GetAttachSocketName():ToString() end)
        local bone = s and s ~= "None" and (try(function() return m:GetSocketBoneName(FName(s)):ToString() end) or s)
        if bone and (bone == q.bone or try(function() return m:BoneIsChildOf(FName(bone), FName(q.bone)) end) == true) then
          invisible(k)
        end
      end
    end
  end
  return nb, nv
end
function M.smashed.back()
  local n = 0
  for _, e in ipairs(M.smashed.bones) do
    if valid(e.c) then try(function() e.c:UnHideBoneByName(FName(e.b)) end); n = n + 1 end
  end
  for _, c in ipairs(M.smashed.shown) do
    if valid(c) then try(function() c:SetVisibility(true, false) end); n = n + 1 end
  end
  M.smashed.bones, M.smashed.shown = {}, {}
  return n
end
-- one chunk at `at`, flying at v (cm/s): an actor (in caps, destroyed with the cut) whose sphere simulates and
-- carries the meat mesh, scaled to cm across
function M.smashed.chunk(pawn, mesh, at, v, cm, sm)
  local s = cfg().smash or {}
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  local acls = load_obj("/Script/Engine.StaticMeshActor")
  local scls, mcls = load_obj("/Script/Engine.SphereComponent"), load_obj("/Script/Engine.StaticMeshComponent")
  if not (gs and acls and scls and mcls and sm) then return nil end
  local tm = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = at, Scale3D = vec(1, 1, 1) }
  local a = try(function()
    local d = gs:BeginDeferredActorSpawnFromClass(pawn, acls, tm, 1, nil)
    return gs:FinishSpawningActor(d, tm)
  end)
  if not valid(a) then return nil end
  caps[#caps + 1] = a
  local root = try(function() return a.StaticMeshComponent end)
  if valid(root) then try(function() root:SetMobility(2) end); try(function() root:SetCollisionEnabled(0) end) end
  local id = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }
  local sp = try(function() return a:AddComponentByClass(scls, true, id, false) end)
  local m = try(function() return a:AddComponentByClass(mcls, true, id, false) end)
  if not (valid(sp) and valid(m)) then return nil end
  local b = try(function() local x = sm:GetBounds(); return { o = vec(x.Origin.X, x.Origin.Y, x.Origin.Z), e = vec(x.BoxExtent.X, x.BoxExtent.Y, x.BoxExtent.Z) } end)
  local big = b and math.max(b.e.X, b.e.Y, b.e.Z) or 0
  local k = big > 0.01 and cm / (2 * big) or 1
  local ok = try(function()
    sp:SetMobility(2)
    sp:K2_SetWorldLocationAndRotation(at, { Pitch = math.random() * 360, Yaw = math.random() * 360, Roll = math.random() * 360 }, false, {}, true)
    sp:SetSphereRadius(math.max(cm * 0.35, 1), false)
    sp:SetHiddenInGame(true, false)
    -- the level alone (WorldStatic, WorldDynamic): landing on her as well, the upper body's seven came out inside
    -- her hidden chest's bodies, still simulating, and the game froze 0.1 s on (the first upper body smash, F6)
    sp:SetCollisionProfileName(FName("PhysicsActor"), true)
    sp:SetCollisionResponseToAllChannels(0)
    sp:SetCollisionResponseToChannel(0, 2)
    sp:SetCollisionResponseToChannel(1, 2)
    sp:SetCollisionEnabled(3)
    try(function() sp.BodyInstance.bUseCCD = true end)
    m:SetMobility(2)
    m:SetStaticMesh(sm)
    m:SetCollisionEnabled(0)
    -- (the stumps' meat material: the meshes' own is the effects', and the chunks vanished at once, playtest)
    if s.material ~= false then
      local mat = load_obj(s.material or CAP_MATERIAL)
      local nm = try(function() return m:GetNumMaterials() end) or 1
      if mat then for i = 0, math.max(nm, 1) - 1 do m:SetMaterial(i, mat) end end
    end
    m:K2_AttachToComponent(sp, FName("None"), 1, 1, 1, false)
    m:SetRelativeScale3D(vec(k, k, k))
    if b then m:K2_SetRelativeLocation(scale(b.o, -k), false, {}, true) end
    try(function() m:SetReceivesDecals(false) end)
    sp:SetSimulatePhysics(true)
    sp:SetMassOverrideInKg(FName("None"), s.kg or 0.3, true)
    try(function() sp:SetAngularDamping(s.angularDamping or 1.5) end)
    sp:SetPhysicsLinearVelocity(v, false, FName("None"))
    sp:SetPhysicsAngularVelocityInDegrees(vec((math.random() - 0.5) * 1440, (math.random() - 0.5) * 1440, (math.random() - 0.5) * 720), false, FName("None"))
    return true
  end)
  if not ok then try(function() a:K2_DestroyActor() end); return nil end
  return sp
end
-- the piece of cut q goes: hidden, and the meat flies where it was, a couple of chunks a tick
function M.smashed.out(q)
  local s = cfg().smash or {}
  local nb, nv = M.smashed.hide(q)
  -- where it was: the middle of the part (the head's up past its bone), else the cut
  local p = PARTS[q.bone] or {}
  local seg = M.SMASH_SEG[q.bone]
  local a, b = bone_loc(q.mesh, seg and "Bip001-Spine1" or p.from or q.bone), bone_loc(q.mesh, seg and seg[2] or p.to or q.bone)
  local at = q.c.at
  if a and b then
    local k = p.kind == "head" and 2.2 or 0.5
    at = vec(a.X + (b.X - a.X) * k, a.Y + (b.Y - a.Y) * k, a.Z + (b.Z - a.Z) * k)
  end
  if not at then log("smash: nowhere to put the meat"); return end
  local leg = q.bone:find("Thigh") or q.bone:find("Calf")
  local n = math.floor(p.kind == "head" and (s.chunksHead or 4) or p.kind == "torso" and (s.chunksBody or 7)
    or leg and (s.chunksLeg or 4) or (s.chunks or 3))
  local lo, hi = s.sizeMin or 4, s.sizeMax or 10
  local speed = s.speed or 350
  local fly = q.fly and norm(q.fly)
  local meshes = {}
  for _, path in ipairs(s.meshes or M.SMASH_MESHES) do local o = load_obj(path); if o then meshes[#meshes + 1] = o end end
  local made, left = 0, n
  M.smashed.list = {}
  local drips = s.drips or 3
  local pawn, mesh = q.pawn, q.mesh
  local function batch()
    if not valid(pawn) or #meshes == 0 then return end
    for _ = 1, math.min(2, left) do
      left = left - 1
      -- out every way, more along the blow; up a little so they arc
      local r = norm(vec(math.random() - 0.5, math.random() - 0.5, math.random() * 0.6 + 0.2)) or vec(0, 0, 1)
      local dir = fly and norm(add(scale(fly, 0.8), r)) or r
      local v = scale(dir, speed * (0.5 + math.random()))
      local off = vec((math.random() - 0.5) * 8, (math.random() - 0.5) * 8, (math.random() - 0.5) * 8)
      local sp = M.smashed.chunk(pawn, mesh, add(at, off), v, lo + math.random() * (hi - lo), pick(meshes))
      if sp then
        made = made + 1
        M.smashed.list[#M.smashed.list + 1] = sp
        -- the first few drip as they fly and pool where they land (a hand's small pool)
        if made <= drips and cfg().blood ~= false then
          track(pawn, function()
            if not valid(sp) then return nil end
            return try(function() local l = sp:K2_GetComponentLocation(); return vec(l.X, l.Y, l.Z) end)
          end, "Bip001-L-Hand", mesh)
        end
      end
    end
    if left > 0 then later[#later + 1] = { n = 1, fn = batch }
    else
      log(string.format("smash: %d of %d meat chunks out at %s", made, n, v3(at)))
      -- (where they are 2 s on: they vanished at once, playtest)
      later[#later + 1] = { n = 60, fn = function()
        local out = {}
        for _, sp in ipairs(M.smashed.list or {}) do
          out[#out + 1] = valid(sp) and v3(try(function() return sp:K2_GetComponentLocation() end)) or "gone"
        end
        log("smash: chunks 2 s on: " .. table.concat(out, " "))
      end }
    end
  end
  batch()
  -- (the hit blood alone: the flesh-slice burst's own meat stub and the finisher's splash hung in the air as a
  -- huge bone, playtest; the stump bleeds as a cut's)
  if cfg().blood ~= false then
    if s.splash == true then niagara(s.fx or M.SMASH_FX, pawn, nil, at, false) end
    niagara(FX.hit, pawn, nil, at, false)
    later[#later + 1] = { n = 1, fn = function() M.splat(pawn, at) end }
  end
  log(string.format("smash: %s gone (%d bones hidden, %d parts riding it hidden)", q.bone, nb, nv))
end
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

-- the parts cut off this mesh so far (a limb, the head, her upper body), by their root bone
function M.cut_parts(mesh)
  local a, out = addr(mesh), {}
  for _, c in ipairs(cuts) do if c.addr == a and PARTS[c.bone] and not c.smashed then out[#out + 1] = c.bone end end
  return out
end
-- photo mode with a piece off her alive: her mesh used to stop ticking (its animation pulled the piece back onto her,
-- physics being paused), and photo mode's poses and expressions never showed (reported). Now the piece goes onto a
-- copy of her mesh as photo mode opens: her cut weights ("y"), her pose with every bone but the piece's scaled to
-- nothing ("P"), not ticking or simulating, so it lies where it fell. On her the piece's bones are hidden (her face's
-- too with a head), and what rides them (caps, stubs, bleeds, accessories on their sockets) moves onto the copy's same
-- bone, where it sits as it did. Her mesh poses on. As photo mode closes it all goes back and the copy is destroyed.
-- Returns how many pieces went onto the copy, and what rode them
M.pieceHid = nil
function M.hide_pieces(pawn, mesh, on)
  local h = M.pieceHid
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
    for _, c in ipairs(h.copies) do
      local a = addr(c)
      for i = #clones, 1, -1 do if addr(clones[i]) == a then table.remove(clones, i) end end
      if a then forced[a] = nil end
      if valid(c) then try(function() c:K2_DestroyComponent(c) end) end
    end
    return #h.roots, #h.riders
  end
  if h then return #h.roots, #h.riders end
  local roots = M.cut_parts(mesh)
  if #roots == 0 then return 0, 0 end
  local idx = {}
  for _, b in ipairs(roots) do
    local i = try(function() return mesh:GetBoneIndex(FName(b)) end)
    if i and i >= 0 then idx[#idx + 1] = string.format("%x", i) end
  end
  if #idx == 0 then return 0, 0 end
  local c = clone_of(pawn, mesh)
  if not c then log("photo mode: no copy for the piece cut off her"); return 0, 0 end
  h = { mesh = mesh, roots = roots, copies = { c }, bones = {}, riders = {}, hidden = {} }
  M.pieceHid = h
  try(function() c.bNoSkeletonUpdate = true end)
  place_like(c, mesh)
  local y = command(string.format("y%x,0,%x", addr(mesh), addr(c)))
  local p = command(string.format("P%x,%x,%s", addr(mesh), addr(c), table.concat(idx, ",")))
  if y:sub(1, 9) ~= "ok copied" or p:sub(1, 8) ~= "ok piece" then
    log(string.format("photo mode: the piece's copy failed (weights %s, pose %s): her mesh poses with the piece hidden", y, p))
    for i = #clones, 1, -1 do if addr(clones[i]) == addr(c) then table.remove(clones, i) end end
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
  for _, b in ipairs(roots) do
    for _, m in ipairs({ mesh, not h.face and face or nil }) do
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
  -- (what is hidden here, for main.lua's showing her again up close to leave alone)
  h.set = {}
  for _, k in ipairs(h.hidden) do local a = addr(k); if a then h.set[a] = true end end
  log(string.format("photo mode: %s cut off her %s (weights %s, pose %s%s), %d part(s) riding it moved over, %d hidden",
    table.concat(roots, ", "), c and "on a copy of her mesh" or "hidden", y, p, fq and ", her face along: " .. fq or "",
    #h.riders + #h.posed, #h.hidden))
  local names = {}
  for _, r in ipairs(h.riders) do names[#names + 1] = (name_of(r.c)) .. "@" .. (try(function() return r.socket:ToString() end) or "?") end
  for _, k in ipairs(h.posed) do names[#names + 1] = name_of(k) .. " (posed)" end
  if #names > 0 then log("photo mode: onto the copy: " .. table.concat(names, ", ")) end
  return #roots, #h.riders
end
function M.slice(pawn, mesh, hit, why, kind) return start(pawn, mesh, hit, why, kind or "limb") end
-- a rolled limb cut's further limbs (tune.gore.death.moreLimbs): each one more with that chance, at most two more,
-- queued after it; each takes the arm or thigh nearest the hit not cut yet and flies the way the first one did
function M.more_limbs(pawn, mesh, hit, why)
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

-- ---- a living hit's mark (tune.gore.hitMarks) ----
-- A hit she lives through leaves a slash of blood on her skin, no cut: a deferred decal (the cinematic floor blood's
-- streaky one, stretched along the swing) on the skin where the hit landed, riding the bone that moves that skin. The
-- DLL finds that skin ("m": a ray from the nearest part's bone axis out through the physics hit, the first skin it
-- leaves through, and its normal), so the mark sits on her and not on the capsule the hit was reported on. Its box
-- reaches only a share of the part's radius into her, so it never shows on the far side or on the arm beside her.
-- Marks heal (heal_marks): each remembers her HP bar before its hit and fades once healing brings it back past that;
-- all go when she recovers (cleanup)
M.mk = { list = {} }
M.decal_seen = {}   -- outfit mesh address -> true once its decal setup is logged (hit_mark)
M.MARK_AT = MARK_AT

M.MARK_DECALS = {
  "/Game/Art/FX/Enviroment/WasteLand/Cinematic/MV_Nest_RavenBattle_After_QTE_success/MI_FloorBloodDecal_5.MI_FloorBloodDecal_5",
}
-- its shape: the floor blood's own (BaseTex) is a lumpy puddle with a normal map, which squeezed to a slash on her
-- skin read as a dent. The mark gets its own instance with the game's sword scar instead (a long thin streak, 64 x 512,
-- along the decal's Y) and no normal relief
M.MARK_SLASH = { "/Game/Art/FX/Tex/Decal/T_A_SwordScars_01.T_A_SwordScars_01" }

-- at: where the game says she was hit (world), dir: the blade's motion there (the slash runs along it), or nil;
-- pre: her HP bar before the hit (0-1), or nil. True when a mark went on
function M.hit_mark(pawn, mesh, at, dir, pre)
  local g = cfg()
  local c = g.hitMarks or {}
  if g.enabled == false or c.enabled == false or not (at and valid(mesh)) then return false end
  if native.state ~= "ready" then return false end
  -- the part: the bone segment nearest the hit
  local best, bd, bc
  for _, w in ipairs(M.MARK_AT) do
    local a, b = bone_loc(mesh, w.bone), bone_loc(mesh, w.to)
    if a and b then
      a, b = vec(a.X, a.Y, a.Z), vec(b.X, b.Y, b.Z)
      local ab = sub(b, a)
      local t = math.max(0, math.min(1, dot(sub(at, a), ab) / math.max(dot(ab, ab), 1e-4)))
      local p = add(a, scale(ab, t))
      local d = len(sub(at, p))
      if not bd or d < bd then best, bd, bc = w, d, p end
    end
  end
  if not best or bd > (c.reach or 40) then
    log(string.format("hit mark skipped: no part of her within %d cm of %s", c.reach or 40, v3(at)))
    return false
  end
  local out = norm(sub(at, bc)) or (dir and norm(scale(dir, -1))) or vec(1, 0, 0)
  local reach = math.min(math.max(bd + 8, 12), 30)
  local r = command(string.format("m%x,0,%x", mesh:GetAddress(), math.floor(reach + 0.5)), bc, out)
  local hit, n = triple(r, "hit", 1), triple(r, "n", 0.01)
  if r:sub(1, 2) ~= "ok" or not (hit and n) then log("hit mark skipped: " .. r); return false end
  n = norm(n) or out
  local bi = num(r, "bone")
  local ride = bi and bi >= 0 and try(function() return mesh:GetBoneName(bi):ToString() end) or best.bone
  if ride == "None" then ride = best.bone end
  -- along the skin: the swing's motion, flattened onto it, else any way round
  local along = dir and norm(sub(dir, scale(n, dot(dir, n))))
  if not along then
    local side = math.abs(n.Z) < 0.9 and vec(0, 0, 1) or vec(1, 0, 0)
    local x, y = norm(cross(n, side)), nil
    y = cross(n, x)
    local a = math.random() * 2 * math.pi
    along = norm(add(scale(x, math.cos(a)), scale(y, math.sin(a)))) or x
  end
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  local km = load_obj("/Script/Engine.Default__KismetMathLibrary")
  local mat = load_obj(pick(c.decals or M.MARK_DECALS))
  if not (gs and km and mat) then log("hit mark skipped: no decal material"); return false end
  -- its size: a slash of length x width, kept within the part's curve (a slash round a forearm would leave the box)
  local k = (c.scale or 1.0) * (0.75 + math.random() * 0.5)
  local half_l = math.min((c.length or 14) * 0.5 * k, best.r * 1.3)
  local half_w = (c.width or 4) * 0.5 * k
  local depth = math.max(1.5, best.r * (c.depth or 0.5))
  -- the decal projects along its X: into her skin; its Y runs along the slash
  local rot = try(function() local q = km:MakeRotFromXY(scale(n, -1), along); return { Pitch = q.Pitch, Yaw = q.Yaw, Roll = q.Roll } end)
  if not rot then log("hit mark skipped: no rotation"); return false end
  -- marks spawned on CH_P_EVE_30 (SBPR) and never showed: once per outfit mesh, decals are switched on if they were
  -- off, and the log says how its materials take decals (deferred decals skip translucent materials, and DBuffer
  -- decals skip a material whose MaterialDecalResponse is None, 0)
  local sk = try(function() return mesh.SkeletalMesh end)
  local ska = valid(sk) and try(function() return sk:GetAddress() end)
  if ska and not M.decal_seen[ska] then
    M.decal_seen[ska] = true
    local rd = try(function() return mesh.bReceivesDecals end)
    if rd == false then try(function() mesh:SetReceivesDecals(true) end) end
    local ms = {}
    for i = 0, (try(function() return mesh:GetNumMaterials() end) or 0) - 1 do
      local m = try(function() return mesh:GetMaterial(i) end)
      local base = valid(m) and try(function() return m:GetBaseMaterial() end)
      if valid(base) then
        ms[#ms + 1] = string.format("%s blend %s response %s", try(function() return base:GetFName():ToString() end) or "?",
          tostring(try(function() return base.BlendMode end)), tostring(try(function() return base.MaterialDecalResponse end)))
      end
    end
    local dm = try(function() return mat:GetBaseMaterial() end)
    log(string.format("hit marks on %s: receives decals %s%s; the mark's material blend %s; %s",
      try(function() return sk:GetFName():ToString() end) or "?", tostring(rd),
      rd == false and " (switched on)" or "", tostring(valid(dm) and try(function() return dm.DecalBlendMode end)),
      table.concat(ms, ", ")))
  end
  -- EAttachLocation::KeepWorldPosition = 1: it rides the bone at the skin's point and turn
  local d = try(function() return gs:SpawnDecalAttached(mat, vec(depth, half_l, half_w), mesh, FName(ride), hit, rot, 1, 0) end)
  if not valid(d) then log("hit mark skipped: the decal didn't spawn"); return false end
  local tex = c.slash ~= false and load_obj(pick(c.slash or M.MARK_SLASH))
  if tex then
    local mid = try(function() return d:CreateDynamicMaterialInstance() end)
    if not (valid(mid) and try(function()
      mid:SetTextureParameterValue(FName("BaseTex"), tex)
      mid:SetScalarParameterValue(FName("NormalStrength"), 0)
      return true
    end)) then log("hit mark: no instance of its own, the puddle's shape stays") end
  end
  local list = M.mk.list
  list[#list + 1] = { d = d, pre = pre, low = pre, t = os.clock() }
  -- the oldest goes first past the cap
  while #list > (c.max or 12) do
    local o = table.remove(list, 1)
    if valid(o.d) then try(function() o.d:K2_DestroyComponent(o.d) end) end
  end
  if g.blood ~= false and c.blood ~= false then niagara(FX.hit, pawn, nil, hit, false) end
  log(string.format("hit mark on %s (rides %s): %.0f x %.1f cm at %s, %.1f cm out of the bone, %s off the reported hit, HP bar before %s",
    best.bone, ride, half_l * 2, half_w * 2, v3(hit), num(r, "out") or -1, string.format("%.1f cm", len(sub(hit, at))),
    pre and string.format("%.3f", pre) or "?"))
  return true
end

-- her HP bar now (0-1): marks whose hit healing has undone fade out over healFade s, then go. A mark counts as healed
-- once the bar has risen from its lowest since the hit and reached the reading it had before it (a hit that took
-- nothing waits for her recovery; one with no reading before it, for a full bar)
function M.heal_marks(pct)
  local c = cfg().hitMarks or {}
  local keep, now = {}, os.clock()
  for _, m in ipairs(M.mk.list) do
    if not valid(m.d) then
      -- gone with her mesh
    elseif m.gone then
      if now >= m.gone then try(function() m.d:K2_DestroyComponent(m.d) end) else keep[#keep + 1] = m end
    else
      if pct then
        m.low = math.min(m.low or pct, pct)
        if pct > m.low + 0.01 and pct >= (m.pre or 0.98) - 0.005 then
          local f = c.healFade or 2.5
          try(function() m.d:SetFadeOut(0, f, false) end)
          m.gone = now + f + 0.2
          log(string.format("hit mark healed: HP bar %.3f (was %s before the hit, %.3f at its lowest)", pct,
            m.pre and string.format("%.3f", m.pre) or "?", m.low))
        end
      end
      keep[#keep + 1] = m
    end
  end
  M.mk.list = keep
end

-- every mark off her at once (her recovery, a respawn)
function M.clear_marks()
  local n = 0
  for _, m in ipairs(M.mk.list) do
    if valid(m.d) then try(function() m.d:K2_DestroyComponent(m.d) end); n = n + 1 end
  end
  M.mk.list = {}
  if n > 0 then log(string.format("removed %d hit marks", n)) end
end
function M.marks() return #M.mk.list end

-- ---- the killing blow as a blade ----
-- The game's hit (main.lua) gives the swing's direction and the attacker's forward: the blade moved in the plane
-- holding both, through where it hit. What that plane goes through decides the cut: the neck alone (the head's end
-- of the spine on one side, the chest on the other) is a beheading, the rest of the spine the body in two along the
-- plane (any angle: down the middle, across the waist, shoulder to hip), past the spine the arm or leg it crosses
-- nearest the hit, cut along the blade.
M.FLAT_LIMB = 10 -- cm: a limb this near the plane at both ends lies in it (classify)
local LIMB_SEGS = {
  { "Bip001-L-UpperArm", "Bip001-L-Forearm" }, { "Bip001-L-Forearm", "Bip001-L-Hand" },
  { "Bip001-R-UpperArm", "Bip001-R-Forearm" }, { "Bip001-R-Forearm", "Bip001-R-Hand" },
  { "Bip001-L-Thigh", "Bip001-L-Calf" }, { "Bip001-L-Calf", "Bip001-L-Foot" },
  { "Bip001-R-Thigh", "Bip001-R-Calf" }, { "Bip001-R-Calf", "Bip001-R-Foot" },
}
local function blade_plane(h)
  -- the plane the enemy's weapon swept (main.lua's weapon_swing)
  if h.n then return norm(h.n), h.how or "weapon" end
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

-- her pose for M.blow (main.lua notes it with every sample of an enemy's swing): each bone the blade is judged on
-- (the spine's and the arms' and legs'), its world position and rotation ({ t, q })
M.pose_bones = (function()
  local l, seen = {}, {}
  for _, b in ipairs(SPINE_CHAIN) do l[#l + 1], seen[b] = b, true end
  for _, sg in ipairs(LIMB_SEGS) do
    for _, b in ipairs(sg) do if not seen[b] then l[#l + 1], seen[b] = b, true end end
  end
  return l
end)()
function M.pose(mesh)
  local p = {}
  for _, b in ipairs(M.pose_bones) do p[b] = bone_tm(mesh, b) end
  return p
end

function M.blow(pawn, mesh, h, why)
  local n, how = blade_plane(h)
  -- a hit after her death with no plane (a bare hand's swing along the attacker's forward, no attack direction from
  -- the game: "no plane", blood only, playtest): sideways or from the front, as a rolled attack direction would be
  if not n and why == "after" then
    n, how = blade_plane(setmetatable({ attack_dir = math.random() < 0.5 and 1 or 3 }, { __index = h }))
    if n then how = how .. " (rolled: no plane of its own)" end
  end
  local at = h.loc
  -- her pose as the blow landed (h.pose, from main.lua's swing samples): the blade is judged against it, not a frame
  -- into her death, when the death show had swung her arms on (an arm raised to block kept, the body behind it cut).
  -- What is chosen is then moved with its bone to where that bone is now (go): a limb's cut along its own bone, the
  -- rest with Spine1 (a head's with the neck)
  local P = h.pose
  if P then how = how .. string.format(" (on her pose %.2f s before)", h.pose_ago or 0) end
  local function bl(b)
    local x = P and P[b]
    if x then return x.t end
    return bone_loc(mesh, b)
  end
  local function go(at, why, kind, out, plane, blade)
    -- a cut at the hit, before her death is reported (h.early, main.lua): a limb, the head or her body, which come off
    -- her animated body as F9's do (and open over openTime); a split waits for the death (it needs her ragdoll)
    if h.early then
      if not (kind == "limb" or kind == "head" or kind == "torso") then
        M.held = {}
        log(string.format("blade (early): %s %s waits for her death", kind, blade and blade.bone or ""))
        return false
      end
    end
    local ref = blade and blade.bone or (kind == "head" and "Bip001-Neck") or "Bip001-Spine1"
    local was, now = P and P[ref], P and bone_tm(mesh, ref)
    if was and now then
      local function dirv(v) return v and qrot(now.q, qrot(qinv(was.q), v)) end
      local function pt(v) return v and add(now.t, dirv(sub(v, was.t))) end
      at, out = pt(at), dirv(out)
      if plane then plane = { at = pt(plane.at), n = dirv(plane.n) } end
      if blade then
        local c = {}
        for k, v in pairs(blade) do c[k] = v end
        c.n = dirv(blade.n)
        blade = c
      end
    end
    return start(pawn, mesh, at, why, kind, out, plane, blade)
  end
  local function vs(v) return v and string.format("(%.2f %.2f %.2f)", v.X, v.Y, v.Z) or "?" end
  if not (n and at) then
    log(string.format("blade (%s): no plane from dir %s fwd %s attack %s", why, vs(h.dir), vs(h.fwd), tostring(h.attack_dir)))
    return false
  end
  -- her sword, when the blade went through it (active.lua's weapon_cut: a blow she blocked with it, playtest); at
  -- the hit (h.early) once her death comes (M.release_held), she is still holding it
  -- The plane is the one at the blow, on her pose then (h.pose): carried with her sword hand to where it is now. Judged
  -- on her pose at the death instead, the death show had swung the sword out of it: "the blade misses it" on a blow
  -- she blocked with her blade up, split down the middle, the sword whole (playtest)
  local wat, wn = at, norm(n)
  local hw, hn = P and P["Bip001-R-Hand"], P and bone_tm(mesh, "Bip001-R-Hand")
  if hw and hn and wn then
    wat = add(hn.t, qrot(hn.q, qrot(qinv(hw.q), sub(at, hw.t))))
    wn = qrot(hn.q, qrot(qinv(hw.q), wn))
  end
  -- (at the hit: kept in the hand's frame, put back where the hand is when her death comes)
  if h.early then
    local l = hn and { at = qrot(qinv(hn.q), sub(wat, hn.t)), n = qrot(qinv(hn.q), wn) }
    M.held_sword = { mesh = mesh, at = wat, n = wn, hand = l }
  end
  if why == "death" and not h.early and not enemy.cur and ctx.rag and ctx.rag.weapon_cut then
    local ok, err = pcall(ctx.rag.weapon_cut, mesh, wat, wn, M.blocking)
    if not ok then log("weapon cut: " .. tostring(err)) end
  end
  -- a blow from above (a stomp, an overhead chop): it cuts down through her, never across her (a level waist cut from
  -- a stomp, playtest); splitDown as main.lua's split_normal
  local dn = h.dir and norm(h.dir)
  local down = dn ~= nil and dn.Z < -(cfg().splitDown or 0.6)
  -- what the plane does to her: the spine's heights over it, the arms and legs it crosses, and the first cut
  local function classify(n, at)
  local hs = {}
  for i, b in ipairs(SPINE_CHAIN) do
    local l = bl(b)
    if not l then return nil end
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
  local crossed = {} -- per limb (side and arm / leg): its crossing nearest the hit
  for _, sg in ipairs(LIMB_SEGS) do
    local a, b = bl(sg[1]), bl(sg[2])
    local ax = a and b and norm(sub(b, a))
    if ax and math.abs(dot(ax, n)) > 0.3 and not already_cut(mesh, sg[1]) then
      local ha, hb = dot(sub(a, at), n), dot(sub(b, at), n)
      if (ha < 0) ~= (hb < 0) then
        local t = ha / (ha - hb)
        local x = add(a, scale(sub(b, a), t))
        local dd = math.sqrt(dot(sub(x, at), sub(x, at)))
        local c = { bone = sg[1], t = t, d = dd, n = n }
        local limb = sg[1]:match("Bip001%-(%a)%-") .. ((sg[1]:find("Arm") or sg[1]:find("Forearm")) and "arm" or "leg")
        if not crossed[limb] or dd < crossed[limb].d then crossed[limb] = c end
        if not best or dd < best.d then best = c end
        if h.bone == sg[1] then struck = c end
      end
    end
  end
  -- an arm or leg lying along the plane, inside it (both ends within FLAT_LIMB cm): the blade went through it
  -- lengthwise, a forearm held across her to block a level swing. It was left out as "along the limb" and the swing
  -- took her waist alone behind it (playtest). It comes off where it is nearest the hit (multiCut), leaning with the
  -- blade as far as sliceTilt lets it
  for _, sg in ipairs(LIMB_SEGS) do
    local a, b = bl(sg[1]), bl(sg[2])
    local ax = a and b and norm(sub(b, a))
    if ax and math.abs(dot(ax, n)) <= 0.3 and not already_cut(mesh, sg[1])
      and math.abs(dot(sub(a, at), n)) <= M.FLAT_LIMB and math.abs(dot(sub(b, at), n)) <= M.FLAT_LIMB then
      local ab = sub(b, a)
      local t = math.max(0.2, math.min(0.9, dot(sub(at, a), ab) / math.max(dot(ab, ab), 1e-4)))
      local x = add(a, scale(ab, t))
      local dd = math.sqrt(dot(sub(x, at), sub(x, at)))
      local limb = sg[1]:match("Bip001%-(%a)%-") .. ((sg[1]:find("Arm") or sg[1]:find("Forearm")) and "arm" or "leg")
      if not crossed[limb] then crossed[limb] = { bone = sg[1], t = t, d = dd, n = n, flat = true } end
    end
  end
  -- the limb the blow was aimed at (h.bone), when the plane crosses it, over whatever else it crosses nearer
  if struck then best = struck end
  -- how far the hit is from the spine (the nearest point of its segments)
  local off = 1e9
  for i = 1, #SPINE_CHAIN - 1 do
    local a, b = bl(SPINE_CHAIN[i]), bl(SPINE_CHAIN[i + 1])
    local ab = sub(b, a)
    local t = math.max(0, math.min(1, dot(sub(at, a), ab) / math.max(dot(ab, ab), 1e-4)))
    local x = add(a, scale(ab, t))
    off = math.min(off, math.sqrt(dot(sub(at, x), sub(at, x))))
  end
  -- down her length (the plane holds her spine's line) and how near the spine it passes
  local p0, p1 = bl("Bip001-Pelvis"), bl("Bip001-Neck")
  local ax = p0 and p1 and norm(sub(p1, p0))
  local along = ax and math.abs(dot(ax, n)) < M.ALONG
  local near = 1e9
  for i = 1, 5 do near = math.min(near, math.abs(hs[i])) end
  -- a blow from above landing at her neck (nearer it than her chest): a beheading, whichever way its plane runs
  local nk, s2 = bl("Bip001-Neck"), bl("Bip001-Spine2")
  local at_neck = down and nk and s2 and dot(sub(at, nk), sub(at, nk)) < dot(sub(at, s2), sub(at, s2))
  local what
  if at_neck and not already_cut(mesh, "Bip001-Head") then
    what = "head"
  elseif best and best.d < (cfg().limbReach or 12) and off > (cfg().spineReach or 15) then
    what = "limb" -- the blade met an arm or leg away from the body: that limb, whatever the plane does further on
  elseif pos and neg then
    -- through the spine: the neck (the chest clearly on the other side from the head) is a beheading
    what = hs[4] * head_s < -SPINE_TOL and "head" or "slice"
  elseif not pos and not neg then
    what = "slice" -- along the spine
  elseif along and near <= (cfg().spineReach or 15) then
    -- down her length a little beside the spine (14/10/7/3/-2/-3 cm off it): split there, it took nothing and the
    -- odds were rolled (playtest)
    what = "slice"
  else
    what = "limb"
  end
  -- down her length facing her front or back: a split there would be front from back, a slab of her chest (a blade
  -- down her front 4-10 cm off the spine, playtest). A cut across her body instead (shave), or the limb it met
  local r = along and M.her_right(mesh, ax, bl)
  local shave = false
  if what == "slice" and r and math.abs(dot(n, r)) < M.ALONG then
    if best and best.d < (cfg().limbReach or 12) then what = "limb" else shave = true end
  end
  return { hs = hs, pos = pos, neg = neg, spine = spine, head_s = head_s, best = best, crossed = crossed, off = off, what = what,
    shave = shave }
  end
  -- the blade decides what comes off, nothing rolled over it. For variety each blade is turned up to bladeJitter
  -- degrees and moved up to bladeShift cm along its normal (a sweep across her chest takes one arm, both, or an arm and
  -- the chest), and a death that would take the same first part as the last one tries other turns of it (up to
  -- bladeTries): one enemy's one attack took the same arm every time
  local g = cfg()
  local n0, at0, c = n, at, nil
  local jit = (why == "death" or why == "after") and not h.laser and (g.bladeJitter or 15) or 0
  local tries = jit > 0 and (g.bladeTries or 4) or 1
  local function key(x) return x.what .. (x.what == "limb" and x.best and (" " .. x.best.bone) or "") end
  -- a blade through her body (a split, a body cut) is taken as it came: turned, a vertical blade ran across her and
  -- missed, and the next death with the same attack, avoiding the split the last one made, rolled the head (playtest)
  local x0 = jit > 0 and classify(n0, at0)
  if x0 and x0.what ~= "limb" then tries, c = 0, x0 end
  for i = 1, tries do
    local nn, aa = n0, at0
    if jit > 0 then
      local r = norm(vec(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)) or vec(0, 0, 1)
      local u = norm(cross(n0, r))
      if u then
        local th = math.rad((math.random() * 2 - 1) * jit)
        nn = norm(add(scale(n0, math.cos(th)), scale(cross(u, n0), math.sin(th)))) or n0
      end
      aa = add(at0, scale(n0, (math.random() * 2 - 1) * (g.bladeShift or 10)))
    end
    local x = classify(nn, aa)
    if not x then return false end
    if not c or why ~= "death" or key(x) ~= M.last_blow then n, at, c = nn, aa, x end
    if why ~= "death" or key(c) ~= M.last_blow then break end
  end
  if not c then return false end
  if why == "death" then
    if c.what == "limb" and key(c) == M.last_blow then how = how .. " (same as the last death, no other turn of it)" end
    M.last_blow = key(c)
  end
  local hs, pos, neg, spine, head_s, best, crossed, off, what = c.hs, c.pos, c.neg, c.spine, c.head_s, c.best, c.crossed, c.off, c.what
  -- a plane past the spine that only takes a thigh at its hip joint (or a calf right at the knee from a blow aimed at
  -- the body) cut the hips: across the waist instead, square to the spine
  local hip = what == "limb" and best and best.bone:find("Thigh") and best.t < 0.25 and not down
  -- more cuts from one wide swing (multiCut): every other arm or leg the plane crosses within reach cm of the hit,
  -- and the neck when it crosses that near, after the first cut. One cut a death left a sweep through both arms
  -- taking one of them
  local mc = cfg().multiCut or {}
  -- a laser's beam (main.lua's sw.laser_hit) takes everything its plane goes through, however far from where it met her
  if h.laser then mc = setmetatable({ reach = 1e4, max = 8, bodyReach = 1e4 }, { __index = mc }) end
  local reach, most = mc.reach or 40, mc.max or 3
  -- her body cut along the blade, where its plane goes through her spine below the neck within bodyReach cm of the
  -- hit, or passes within bodyGraze cm beside it, through her flank; nil when it doesn't or her body is cut already.
  -- The cut is made under her bust (PARTS), whatever height the blade crossed her at; a blade running down her
  -- length cuts square to the spine there instead
  local function body_blade()
    if already_cut(mesh, "Bip001-Spine1") then return nil end
    local near
    local under = PARTS["Bip001-Spine1"].at
    for i = 1, 4 do
      if (hs[i] < 0) ~= (hs[i + 1] < 0) then
        local a, b = bl(SPINE_CHAIN[i]), bl(SPINE_CHAIN[i + 1])
        local tt = hs[i] / (hs[i] - hs[i + 1])
        local x = a and b and add(a, scale(sub(b, a), tt))
        local dd = x and math.sqrt(dot(sub(x, at), sub(x, at)))
        if dd and dd < (mc.bodyReach or 60) and (not near or dd < near.d) then
          near = { bone = "Bip001-Spine1", t = under, d = dd, n = n }
        end
      end
    end
    if not near then
      local graze = mc.bodyGraze or 10
      for j = 1, 5 do
        local l = bl(SPINE_CHAIN[j])
        local dd = l and math.sqrt(dot(sub(l, at), sub(l, at)))
        if l and math.abs(hs[j]) <= graze and dd < (mc.bodyReach or 60) and (not near or math.abs(hs[j]) < near.off) then
          near = { bone = "Bip001-Spine1", t = under, d = dd, n = n, off = math.abs(hs[j]) }
        end
      end
    end
    if near then
      local a, b = bl("Bip001-Spine1"), bl("Bip001-Spine2")
      local sp = a and b and norm(sub(b, a))
      if sp and math.abs(dot(sp, n)) < M.ALONG then
        -- squared, a blade from above would cut her level: no body cut, the limbs alone
        if down then return nil end
        near.n, near.square = sp, true
      end
    end
    return near
  end
  local function limb_key(b) return b:match("Bip001%-(%a)%-") .. ((b:find("Arm") or b:find("Forearm")) and "arm" or "leg") end
  -- the limb h.second (main.lua: the swing's other blade) swept, crossed by its plane where it went through, else at
  -- the point of the limb nearest where it swept (a plane running down the limb), leaning with that blade
  local function second_blade(skip)
    local s2 = h.second
    if not (s2 and s2.n and s2.at and s2.part and (why == "death" or why == "after")) then return nil end
    local p2 = s2.part:match("Bip001%-%a%-") and s2.part
    if not p2 then return nil end
    local key2 = limb_key(p2)
    if key2 == skip then return nil end
    local n2, best
    n2 = norm(s2.n)
    for _, sg in ipairs(LIMB_SEGS) do
      if limb_key(sg[1]) == key2 and not already_cut(mesh, sg[1]) then
        local a, b = bl(sg[1]), bl(sg[2])
        if a and b and n2 then
          local ha, hb = dot(sub(a, s2.at), n2), dot(sub(b, s2.at), n2)
          local ab = sub(b, a)
          local t
          if (ha < 0) ~= (hb < 0) and math.abs(dot(norm(ab) or n2, n2)) > 0.3 then t = ha / (ha - hb)
          else t = math.max(0.2, math.min(0.9, dot(sub(s2.at, a), ab) / math.max(dot(ab, ab), 1e-4))) end
          local x = add(a, scale(ab, t))
          local dd = math.sqrt(dot(sub(x, s2.at), sub(x, s2.at)))
          if not best or dd < best.d then best = { bone = sg[1], t = t, d = dd, n = n2, second = true } end
        end
      end
    end
    return best
  end
  local function extras(first)
    local out = {}
    if mc.enabled == false or most <= 1 then return out end
    local skip = first and first.bone and (first.bone:match("Bip001%-(%a)%-") .. ((first.bone:find("Arm") or first.bone:find("Forearm")) and "arm" or "leg"))
    -- an arm or leg the swing met first (an arm raised to block, a leg in its way) doesn't stop it: where its plane
    -- goes on through her spine below the neck, within bodyReach cm of the hit, her body is cut too, across the chest
    -- or the waist along the blade (it took the arm alone before). A plane that passes within bodyGraze cm beside
    -- the spine goes through her flank too: the cut is put on the spine at the blade's angle (it took the limb alone,
    -- however the swing ran on into her, playtest 41; a leg's never went on). One running down her length is cut
    -- square to the spine instead
    if first and first.kind == "limb" and skip and mc.body ~= false then
      local near = body_blade()
      if near then out[#out + 1] = { kind = "torso", blade = near } end
    end
    local list = {}
    for limb, c in pairs(crossed) do if limb ~= skip and c.d < reach then list[#list + 1] = c end end
    table.sort(list, function(x, y) return x.d < y.d end)
    -- the swing's second blade (a cross slash with two): the arm or leg it swept comes off along its own plane, first
    -- of the rest (its first blade's plane rarely crossed that one too, and it stayed whole)
    local two = second_blade(skip)
    if two then
      local l2 = limb_key(two.bone)
      for i = #list, 1, -1 do if limb_key(list[i].bone) == l2 then table.remove(list, i) end end
      table.insert(list, 1, two)
    end
    -- with her body cut too, one leg at most comes off (the first cut's or the nearest): a swing through her hips
    -- took a thigh, the waist and the other thigh, her pelvis a lump of its own (fell apart like a lego set, playtest)
    local torso = (first and first.kind == "torso") or (out[1] and out[1].kind == "torso")
    local legs = skip and skip:find("leg") and 1 or 0
    for _, c in ipairs(list) do
      local leg = c.bone:find("Thigh") or c.bone:find("Calf")
      if #out < most - 1 and not (torso and leg and legs >= 1) then
        out[#out + 1] = { kind = "limb", blade = c }
        if leg then legs = legs + 1 end
      end
    end
    if first and first.kind ~= "head" and #out < most - 1 and (hs[5] < 0) ~= (hs[6] < 0) and not (out[1] and out[1].kind == "torso") then
      local nk = bl("Bip001-Neck")
      if nk and math.sqrt(dot(sub(nk, at), sub(nk, at))) < reach then out[#out + 1] = { kind = "head" } end
    end
    return out
  end
  -- the rest, queued in her own frame (the ragdoll moves on while the first cut opens)
  local function queue(list)
    if #list == 0 then return "" end
    M.queue_gap = cfg().queueGap or 1
    local f = body_frame(mesh)
    local names = {}
    for _, e in ipairs(list) do
      local rel = not P and f and e.blade and to_body(f, e.blade.n)
      local into = h.early and M.held or queued
      into[#into + 1] = function()
        if e.kind == "head" then return go(bl("Bip001-Neck") or at, why, "head", h.dir) end
        local c = { bone = e.blade.bone, t = e.blade.t, d = e.blade.d, n = e.blade.n, square = e.blade.square }
        local fn = rel and body_frame(mesh)
        if fn then c.n = norm(from_body(fn, rel)) or c.n end
        if already_cut(mesh, c.bone) then return false end
        return go(bl(c.bone) or at, why, e.kind, nil, nil, c)
      end
      names[#names + 1] = e.kind == "head" and "head" or e.kind == "torso" and string.format("her body at %s %.0f cm in%s%s", e.blade.bone, e.blade.d,
        e.blade.off and string.format(", the blade %.0f cm beside her spine", e.blade.off) or "", e.blade.square and ", square" or "") or (e.blade.bone .. (e.blade.flat and " (lying in the blade)" or "") .. (e.blade.second and " (the second blade)" or ""))
    end
    return ", then " .. table.concat(names, ", ")
  end
  -- both arms the blade crosses within reach cm of the hit, nearest first, and no split: the first now, the other
  -- queued (armsOverSplit, h.armsOnly). A blade down her length through her arms raised split her nearly every time,
  -- the arms coming off only on the way, and a split rolled took her whatever the blade had crossed (playtest)
  local function both_arms()
    local arms = {}
    for limb, c in pairs(crossed) do if limb:find("arm") and c.d < reach then arms[#arms + 1] = c end end
    if #arms < 2 then return nil end
    table.sort(arms, function(x, y) return x.d < y.d end)
    return arms
  end
  local function arms_cut(arms, what)
    local first = table.remove(arms, 1)
    local list = {}
    for _, c2 in ipairs(arms) do list[#list + 1] = { kind = "limb", blade = c2 } end
    local more = queue(list)
    log(string.format("blade (%s): %s %s: both arms instead, %s at %.2f first%s", why, how, what, first.bone, first.t, more))
    return go(at, why, "limb", nil, nil, first)
  end
  if h.armsOnly then
    local arms = mc.enabled ~= false and both_arms()
    if not arms then return false end
    return arms_cut(arms, "with a split rolled")
  end
  -- a cut down her length (the plane along her spine) at death is off (deathSplit false): the limbs it crosses near
  -- the hit come off instead, or the death's odds are rolled. An enemy is never split: the same for its corpse (a
  -- downward chop through one rolled its odds, whatever arm it went through)
  local axis = (function()
    local p0, p1 = bl("Bip001-Pelvis"), bl("Bip001-Neck")
    return p0 and p1 and norm(sub(p1, p0))
  end)()
  local lengthwise = axis and math.abs(dot(axis, n)) < M.ALONG
  local nosplit = why == "enemy" or ((why == "death" or why == "after") and cfg().deathSplit == false)
  if (what == "slice" or (not pos and not neg)) and lengthwise and nosplit then
    local list = extras(nil)
    if #list == 0 or list[1].kind ~= "limb" then
      log(string.format("blade (%s): %s plane down her length, no split %s", why, how,
        why == "enemy" and "on an enemy" or "at death (deathSplit off)"))
      return false
    end
    local first = table.remove(list, 1)
    local more = queue(list)
    log(string.format("blade (%s): %s plane down her length, no split %s: %s at %.2f instead%s", why, how,
      why == "enemy" and "on an enemy" or "at death", first.blade.bone, first.blade.t, more))
    return go(at, why, "limb", nil, nil, first.blade)
  end
  -- a blade across her body cuts it along the blade (the chest or the waist), and every arm and leg it crossed comes
  -- off after it (multiCut); one down her length splits her along it. A bladeSplit roll split her a fifth of the time
  -- whichever way the blade went, and rolled the odds the rest (a waist cut square to her spine and nothing else,
  -- though the weapon went through her arms, playtest)
  local splits = what == "slice"
  if splits and (not lengthwise or c.shave) then
    local body = not h.noSplit and mc.body ~= false and body_blade()
    if not body then
      log(string.format("blade (%s): %s plane across her body, too far from the hit or cut already", why, how))
      return false
    end
    local more = (why == "death" or why == "enemy") and queue(extras({ kind = "torso" })) or ""
    log(string.format("blade (%s): %s plane %s: her body at %s %.2f%s%s",
      why, how, c.shave and "down her length facing her front or back: no split" or "across her body",
      body.bone, body.t, body.square and ", square" or "", more))
    return go(bl(body.bone) or at, why, "torso", nil, nil, body)
  end
  -- a blow that would split her when she can't be split (h.noSplit: a hit after death on a body already cut; a split
  -- needs her whole): the arms and legs its plane crossed near the hit come off instead, else her body along the
  -- blade while it is whole; only with neither does main.lua mark her (every such hit was a mark, playtest)
  local knee = what == "limb" and best and off < (cfg().spineReach or 15) and best.bone:find("Calf") and not down
  if h.noSplit and (hip or knee
    or (what ~= "limb" and what ~= "head")) then
    local list = extras(nil)
    if list[1] and list[1].kind == "limb" then
      local first = table.remove(list, 1)
      local more = queue(list)
      log(string.format("blade (%s): %s plane through her body, she is cut already: no split, %s at %.2f instead%s",
        why, how, first.blade.bone, first.blade.t, more))
      return go(at, why, "limb", nil, nil, first.blade)
    end
    local body = mc.body ~= false and body_blade()
    if body then
      log(string.format("blade (%s): %s plane through her body, she is cut already: no split, her body at %s %.2f instead",
        why, how, body.bone, body.t))
      return go(bl(body.bone) or at, why, "torso", nil, nil, body)
    end
    log(string.format("blade (%s): %s plane through her body, she is cut already: no split, no arm, leg or body cut near it", why, how))
    return false
  end
  -- (an enemy: its waist cut square to the spine, as a body cut: it is never split)
  if (hip or knee) and why == "enemy" and not already_cut(mesh, "Bip001-Spine1") then
    local a, b = bl("Bip001-Spine1"), bl("Bip001-Spine2")
    local sp = a and b and norm(sub(b, a))
    if sp then
      log(string.format("blade (%s): it only met %s at %.2f, its waist cut square instead", why, best.bone, best.t))
      return go(a, why, "torso", nil, nil, { bone = "Bip001-Spine1", t = PARTS["Bip001-Spine1"].at, d = 0, n = sp, square = true })
    end
  end
  if why == "enemy" and (hip or knee or (what ~= "limb" and what ~= "head")) then
    log(string.format("blade (%s): %s plane through its body, no split on an enemy", why, how))
    return false
  end
  if hip or knee then
    local a, b = bl("Bip001-Spine"), bl("Bip001-Spine1")
    if a and b then
      at = add(a, scale(sub(b, a), 0.4))
      log(string.format("blade (%s): it only met %s at %.2f, cut across the waist at %s instead", why, best.bone,
        best.t, v3(at)))
      return go(at, why, "split", norm(sub(b, a)), { at = at, n = norm(sub(b, a)) })
    end
  end
  -- a plane that crosses no arm or leg past the spine: the one the blow was aimed at is cut square, when it has one
  -- (nineteenth playtest: a swing 279 cm off, moved onto her forearm, ran along it and the death rolled its odds)
  if what == "limb" and not best and h.bone and not already_cut(mesh, h.bone) then
    for _, sg in ipairs(LIMB_SEGS) do
      if sg[1] == h.bone then
        local a, b = bl(sg[1]), bl(sg[2])
        local ax = a and b and norm(sub(b, a))
        if ax then
          best = { bone = sg[1], t = CUT_AT_DEFAULT, d = 0, n = ax }
          how = how .. " (along the limb it was aimed at: cut square)"
        end
        break
      end
    end
  end
  local blade = what == "limb" and best or nil
  log(string.format("blade (%s): %s plane at %s normal %s, dir %s fwd %s attack %s, spine %s cm off it -> %s%s",
    why, how, v3(at), vs(n), vs(h.dir), vs(h.fwd), tostring(h.attack_dir), table.concat(spine, "/"), what,
    blade and (" " .. blade.bone .. string.format(" at %.2f", blade.t)) or ""))
  if what == "limb" then
    if not blade then return false end
    local more = (why == "death" or why == "enemy") and queue(extras({ kind = "limb", bone = blade.bone })) or ""
    if more ~= "" then log("blade (" .. why .. "): one swing" .. more) end
    return go(at, why, "limb", nil, nil, blade)
  elseif what == "head" then
    local more = (why == "death" or why == "enemy") and queue(extras({ kind = "head" })) or ""
    if more ~= "" then log("blade (" .. why .. "): one swing" .. more) end
    return go(at, why, "head", h.dir)
  end
  -- down her length: through her middle, left from right, turned towards the blade at most splitYaw (split_plane;
  -- the blade's own plane split her anywhere: slivers off her flank, her hips flattened into the cut). The arms its
  -- plane crosses within reach cm of the hit (an arm raised to block, playtest: the split kept it whole) come off
  -- first along the blade, nearest first, then the split (splitArms; the split takes a body whose only cuts are arms,
  -- stage_split_prep). At the hit (h.early) the first one now and the rest with the split at her death
  local arms, names = {}, {}
  for limb, c in pairs(crossed) do
    if limb:find("arm") then
      names[#names + 1] = string.format("%s at %.2f, %.0f cm from the hit%s", c.bone, c.t, c.d, c.flat and " (lying in it)" or "")
      if c.d < reach then arms[#arms + 1] = c end
    end
  end
  table.sort(arms, function(x, y) return x.d < y.d end)
  -- and the arm the swing's second blade swept (a cross slash), along its own plane
  local two = mc.enabled ~= false and second_blade(nil)
  if two and limb_key(two.bone):find("arm") then
    for i = #arms, 1, -1 do if limb_key(arms[i].bone) == limb_key(two.bone) then table.remove(arms, i) end end
    arms[#arms + 1] = two
    names[#names + 1] = string.format("%s at %.2f (the second blade)", two.bone, two.t)
  end
  local cut_arms = #arms > 0 and why == "death" and cfg().splitArms ~= false and mc.enabled ~= false
  if cut_arms and #arms >= 2 and math.random() < (cfg().armsOverSplit or 0.6) then
    local two2 = both_arms() or arms
    return arms_cut(two2, "plane down her length")
  end
  if #names > 0 then
    log(string.format("blade (%s): the split's plane crosses %s%s", why, table.concat(names, "; "),
      cut_arms and "" or " (kept whole by its half)"))
  end
  if cut_arms then
    local first = table.remove(arms, 1)
    local list = {}
    for _, c in ipairs(arms) do list[#list + 1] = { kind = "limb", blade = c } end
    local into = h.early and M.held or queued
    local n0 = #into
    local more = queue(list)
    -- (the split itself: go refuses one at the hit, and the first cut took the throw's direction, M.aim)
    local fly = aimed and aimed.d
    into[#into + 1] = function()
      local e = h.early
      h.early = nil
      if fly then aimed = { d = fly, t = os.clock() } end
      local ok, r = pcall(go, at, why, "split", n)
      h.early = e
      if not ok then error(r, 0) end
      return r
    end
    log(string.format("blade (%s): %s plane down her length: %s at %.2f first%s, then the split", why, how, first.bone,
      first.t, more))
    if go(at, why, "limb", nil, nil, first) then return true end
    -- the arm didn't come off: the split alone, as it was
    while #into > n0 do table.remove(into) end
  end
  return go(at, why, "split", n)
end

-- run fn(...) cutting for owner (an enemy's address, nil for Eve): whatever it adds to the lists is tagged with it
function enemy.run(owner, fn, ...)
  local prev = enemy.cur
  enemy.cur = owner
  local lists = { spawned, bleeds, later, caps, hung, trackers, decals, no_decals, cuts, queued, hid }
  local n0 = {}
  for i, l in ipairs(lists) do n0[i] = #l end
  local r = table.pack(pcall(fn, ...))
  for i, l in ipairs(lists) do
    for k = n0[i] + 1, #l do
      local x = l[k]
      if enemy.owned[x] == nil then
        enemy.owned[x] = owner or false
        -- an object on an enemy goes with its actor, freed by the game unseen: kept to be checked safely (enemy.alive),
        -- its index taken now (held reads it only within keepFresh s of keep: the caps, first checked at the dissolve
        -- seconds later, read as gone and were left up long after the corpse, playtest)
        if owner and type(x) == "userdata" then
          local k = ctx.keep(x)
          enemy.kept[x] = k
          if k then ctx.held(k) end
        end
      end
    end
  end
  enemy.cur = prev
  -- a cut that finished opening on a corpse already dissolving: its caps and bleeds go at once (they stayed in the
  -- air where it had been until it went back to its pool, playtest: leftover covers)
  if owner and enemy.faded[owner] then M.enemy_fading(owner, true) end
  if not r[1] then error(r[2], 0) end
  return table.unpack(r, 2, r.n)
end
local function owner_of(x) return enemy.owned[x] or nil end
-- valid() for an object tagged to an enemy: never read once the game may have freed it (main.lua held)
function enemy.alive(x)
  local k = enemy.kept[x]
  if k then return ctx.held(k) end
  return not enemy.owned[x] and valid(x)
end

local stage_step
local function stage_tick(q)
  local stage, t0 = q.stage, os.clock()
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
  prof = nil
  if not ok then error(err, 0) end
end
stage_step = function(q)
  if q.kind == "split" then return split_tick(q) end
  if q.stage == "cut" then
    if stage_cut(q) then q.stage = #q.c.chains > 0 and "chains" or "caps"; q.wait = 0; return end
    pending = nil
    -- nothing came off: give the LOD back unless an earlier cut still needs it
    release_lods()
  elseif q.stage == "chains" then
    M.stage_chains(q)
    if #q.c.chains == 0 then q.stage = "caps" end
  elseif q.stage == "caps" then
    M.stage_caps(q)
    q.stage, q.wait = "stubs", 0
  elseif q.stage == "stubs" then
    M.stage_stubs(q)
    -- (a frame's wait before the piece came off made each cut show ~50 ms later, playtest; openWait frames now)
    q.stage, q.wait = "open", cfg().openWait or 0
  else
    pending = nil
    stage_open(q)
  end
end

-- her bones looked at while she plays, every WATCH_EVERY ticks: a stub's carrier must be a helper that held still
-- against its parent all along (sbslice "w"; an animation-driven corrective flung a thigh's stub about, twenty-fifth
-- playtest)
-- tm: main.lua's slow tick marker, each part named (a look held a frame 466-563 ms in the first minute with no asset
-- load over 15 ms, playtest)
-- gap: s between two preloads (each one 30-35 ms of the game thread: a sound a look, every 5 ticks, was 20 hitches in
-- a row, a stutter run, playtest)
M.watching = { every = 5, n = 0, gap = 0.5, at = 0 }
function M.watch(mesh, tm)
  local w = M.watching
  if cfg().enabled == false or native.state ~= "ready" or not valid(mesh) then return end
  w.n = w.n + 1
  if w.n % w.every ~= 0 then return end
  tm = tm or function() end
  local r = command(string.format("w%x", mesh:GetAddress()))
  if r:sub(1, 2) ~= "ok" and not w.logged then w.logged = true; log("bone watch refused: " .. r) end
  tm("bone watch w")
  -- and while she plays, the cuts' assets are loaded (and kept: native.root) one a look, so even the first cut
  -- loads nothing
  if not w.preload then
    local g, list = cfg(), {}
    for _, v in pairs(FX) do list[#list + 1] = v end
    -- (the sounds after the rest, and not in her first 30 s: loaded as the lobby came up, while the game's audio
    -- mixer was starting, its render thread crashed on a null lock, exe+0xb4b8817, on one launch in a few since
    -- 0.3.0 added her breaths and moans here, playtest)
    local sounds = {}
    for _, sets in pairs(SFX) do for _, set in ipairs(sets) do for _, v in ipairs(set) do sounds[#sounds + 1] = v end end end
    for _, v in ipairs(vox.DIE) do sounds[#sounds + 1] = v end
    local cv = type(ctx.tune.convulse) == "table" and ctx.tune.convulse.voice
    if type(cv) == "table" and cv.enabled ~= false then
      for _, names in ipairs({ cv.breaths or {}, cv.moans or {} }) do
        for _, n in ipairs(names) do
          n = tostring(n)
          if n:sub(1, 1) ~= "/" then n = vox.DIR .. n:gsub("_VO$", "") .. "_VO" end
          if not n:find(".", 1, true) then n = n .. "." .. n:match("([^/]+)$") end
          sounds[#sounds + 1] = n
        end
      end
    end
    for _, v in ipairs(POOL_DECALS) do list[#list + 1] = v end
    for _, v in ipairs(M.MARK_DECALS) do list[#list + 1] = v end
    for _, v in ipairs(M.MARK_SLASH) do list[#list + 1] = v end
    for _, v in ipairs({ MPC_DIRTY, g.capMaterial or CAP_MATERIAL, g.stubMesh or STUB_MESH }) do list[#list + 1] = v end
    if M.tachy() then list[#list + 1] = M.TACHY_MAT end
    local sm = type(g.smash) == "table" and g.smash or {}
    if sm.enabled == true then
      for _, v in ipairs(sm.meshes or M.SMASH_MESHES) do list[#list + 1] = v end
      if sm.splash == true then list[#list + 1] = sm.fx or M.SMASH_FX end
      list[#list + 1] = sm.material or CAP_MATERIAL
    end
    if type(g.capMatte) == "table" and g.capMatte.enabled ~= false then
      list[#list + 1] = g.capMatte.material or M.matte.master
      for _, v in pairs(M.matte.tex) do list[#list + 1] = v end
    end
    sounds[#sounds + 1] = vox.ATTENUATION
    w.sounds = #list + 1
    for _, v in ipairs(sounds) do list[#list + 1] = v end
    w.preload, w.next, w.t0 = list, 1, os.clock()
  end
  tm("bone watch list")
  -- and her outfit's bone tree, 40 bones a look, then the cut's bone lists made from it, one a look (warm: nothing
  -- left to read when the cut comes)
  local t = M.bone_tree(mesh, 40)
  tm("bone watch tree")
  if t and (t.warm or 0) < 8 then
    t.warm = (t.warm or 0) + 1
    local k = t.warm
    if k == 1 then nosink_list(mesh) elseif k == 2 then nocarry_list(mesh) elseif k == 3 then limbs_list(mesh, nil)
    elseif k == 4 then M.driven_list(mesh) else limbs_list(mesh, LIMB_ROOTS[k - 4]) end
    tm("bone watch warm " .. k)
  end
  -- and a cap or stub actor made ahead, one a look (M.pool), none while a cut is opening, nor before the preloads
  -- have the cap's material (a lid made first loaded it there and then, untimed: a look held a frame 551 ms, playtest)
  if not pending and w.next >= w.sounds then
    local owner = try(function() return mesh:GetOwner() end)
    if valid(owner) then M.pool_fill(owner) end
    tm("bone watch pool")
  end
  local path = w.preload[w.next]
  if path and w.next >= w.sounds and os.clock() - w.t0 < 30 then path = nil end
  if path and native.rooted[path] then w.next = w.next + 1
  elseif path and os.clock() >= w.at and ctx.may_load() then
    w.next = w.next + 1
    w.at = os.clock() + w.gap
    local t0 = os.clock()
    load_obj(path)
    -- (a look held a frame 440-540 ms in the first minute, playtest: which asset)
    local ms = (os.clock() - t0) * 1000
    if ms >= (cfg().slowMs or 15) then log(string.format("cut asset load took %.0f ms: %s", ms, path)) end
    tm("bone watch load")
  end
  if path and w.next > #w.preload and not w.told then
    w.told = true
    local n = 0
    for _, ok in pairs(native.rooted) do if ok then n = n + 1 end end
    log(string.format("cut assets loaded and kept: %d of %d", n, #w.preload))
  end
end

-- tm: main.lua's slow tick marker (each part's time, when the tick is slow)
function M.tick(pawn, tm)
  if cfg().enabled == false then return end
  tm = tm or function() end
  native_tick()
  M.lod_guard()
  if M.blood_restore and valid(pawn) then
    local from, mpc = M.blood_restore, load_obj(MPC_DIRTY)
    M.blood_restore = nil
    if mpc then
      local l = {}
      for k, v in pairs(from) do if v and mpc_set(pawn, mpc, k, v) then l[#l + 1] = string.format("%s %s", k, tostring(v)) end end
      table.sort(l)
      log("body blood: put back on the new Eve: " .. table.concat(l, ", "))
    end
  end
  blood_tick()
  tm("gore blood")
  pools_tick()
  tm("gore pools")
  lids_tick()
  tm("gore lids")
  for i = #later, 1, -1 do
    local l = later[i]
    l.n = l.n - 1
    if l.n <= 0 then
      table.remove(later, i)
      local ok, err = pcall(enemy.run, owner_of(l), l.fn)
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

-- the cut's stages, one a frame (main.lua calls this every frame, ahead of her mesh's tick; q.wait counts frames).
-- On the 33 ms poll they were a tick each and the piece came off 350 ms after the killing blow, which read as a long
-- delay between the hit and the cut (playtest); a frame each still keeps every stage's work in a frame of its own
function M.pump()
  if cfg().enabled ~= false and #cuts > 0 and not M.pumping then
    local ok, err = pcall(M.copies_flush)
    if not ok then log("copies: " .. tostring(err)) end
  end
  if cfg().enabled == false or (not pending and #queued == 0) or M.pumping then return end
  -- (a queued cut started from here runs its first stage below, not inside its start: a stage a frame)
  M.pumping = true
  local ok0, err0 = pcall(M.pump_once)
  M.pumping = false
  if not ok0 then error(err0, 0) end
end
function M.pump_once()
  if not pending and #queued > 0 then
    -- a few frames between one cut of the blow and the next: the engine's weight override waits on the render
    -- thread, still busy with the cut before (a waist cut right after a thigh's held the frame 126 ms, playtest)
    if (M.queue_gap or 0) > 0 then M.queue_gap = M.queue_gap - 1; return end
    M.queue_gap = cfg().queueGap or 1
    local nx = table.remove(queued, 1)
    local ok, err = pcall(enemy.run, owner_of(nx), nx)
    if not ok then log("next cut of the blow failed: " .. tostring(err)) end
  end
  local q = pending
  if not q then return end
  if not valid(q.mesh) then pending = nil; return end
  if q.wait > 0 then q.wait = q.wait - 1; return end
  -- a stage that throws would run again on every frame and block every later cut: it ends the cut instead
  local ok, err = xpcall(enemy.run, debug and debug.traceback or tostring, q.owner, stage_tick, q)
  if not ok then
    if pending == q then pending = nil end
    log(string.format("%s (%s) failed at stage %s, dropped: %s", q.kind, q.why, tostring(q.stage), tostring(err)))
  end
end

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
  M.on_hit(pawn, mesh, at)
  sfx(sound or "cut", pawn, at)
end

function M.on_hit(pawn, mesh, at)
  if cfg().enabled == false or cfg().blood == false then return end
  niagara(FX.hit, pawn, nil, at, false)
  if cfg().hitSplat ~= false then M.splat(pawn, at, cfg().splatLife or 30) end
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
  local keep, saved = {}, nil
  for _, c in ipairs(cuts) do if c.bone == "split" and c.saved then saved = c end end
  for _, c in ipairs(cuts) do
    if c.bone == "split" or c.bone == "split copy" then
      -- (after her arm cuts: hers back as saved, the copy's split sinks with hers; "x" on either would take the arm's)
      if saved then
        if c == saved and valid(c.mesh) and addr(c.mesh) == c.addr then
          log("split undone, her arm cuts kept: " .. command(string.format("R%x,0,%x", c.addr, c.copy or 0)))
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
  blood_down()
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
  if #theirs.cuts == 0 then
    steps[#steps + 1] = "sinks(" .. command("r") .. ")"
  else
    local done_sm = {}
    for _, c in ipairs(cuts) do
      if c.sm and not done_sm[c.sm] then
        done_sm[c.sm] = true
        steps[#steps + 1] = "sinks(" .. command(string.format("r%x", c.sm)) .. ")"
      end
    end
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
  M.clear_marks()
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
-- memory may be gone, and UE4SS's IsValid reads it: the first tick after the reload crashed the game
function M.forget()
  spawned, bleeds, caps, cuts, forced, clones, rehomed = {}, {}, {}, {}, {}, {}, {}
  later, hung, queued, skinned, hid = {}, {}, {}, {}, {}
  M.held, M.held_sword, M.blocking, M.pieceHid, M.photoHid = {}, nil, nil, nil, nil
  bleed_logged = false
  pending, collision_saved, self_saved, copy_watch, limb_watch = nil, nil, nil, nil, nil
  enemy.owned, enemy.cur, enemy.faced, enemy.faded, enemy.shrink = setmetatable({}, { __mode = "k" }), nil, {}, {}, {}
  cache, nosink_cache, nocarry_cache, limbs_cache = {}, {}, {}, {}
  -- a collection's values live in the old world, which is gone with them
  -- (but the collection itself outlives her: the respawned Eve kept the death's blood all over her skin, reported.
  -- Its values from before the death are put back through the new one, on her first tick)
  M.blood_restore = body_blood and body_blood.from or M.blood_restore
  body_blood, stub_dims = nil, nil
  decals, trackers, no_decals = {}, {}, {}
  M.mk.list = {}
  -- the pool's cap and stub actors and the split copies were the old level's: asking them anything read freed memory
  M.pool.lid, M.pool.plain = {}, {}
  M.copies.of, M.copies.dirty = {}, {}
end

return M
