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
  splat = "/Game/Art/FX/Char/Common/Hit/Flesh/NS_Hit_Flesh_Decal_Strong_01.NS_Hit_Flesh_Decal_Strong_01",
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
SFX = {
  cut = { { SLICE_BIG }, { SLICE_SMALL }, { SLICE_SMALL, BLOOD } },
  big = { { SLICE_BIG, SPLASH }, { SLICE_SMALL, SPLASH }, { SLICE_BIG, BLOOD } },
}
end
local SFX_GAP = 3.0 -- s a cue rests after it played
local sfx_last = {} -- cue path -> os.clock() it last played

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
local limb_watch = nil -- { mesh, bone, kept, anchor, n }: a limb cut's stretched skin and hanging chains, logged at 1 and 5 s
local skinned = {}      -- split lids that bend with her spine: { actor, pmc, comp, bones, v = per vertex skin, n }
-- the cut in progress, in stages a few ticks apart (see M.slice): { stage, wait, pawn, mesh, hit, why, ... }
local pending = nil
local queued = {}   -- more cuts from the same killing blow (multiCut), each started once the one before it is done
local collision_saved = nil -- the living mesh's collision setup, while a cut piece needs world collision
local self_saved = nil      -- { mesh, resp }: her PhysicsBody response before a cut turned self-collision off
-- enemies (enemies.lua): the same cuts on a generic humanoid enemy's corpse. Everything a cut leaves (caps, effects,
-- bleeds, pools, delayed steps, the cut records) is tagged with the enemy it was made for (owned: item -> its
-- address; Eve's are untagged or false), so a corpse going away takes only its own, and her recovery leaves theirs.
-- cur: the enemy the code running now cuts (nil: Eve). Their mesh assets are shared by every enemy of the kind, so
-- their sinks are put back once the last cut corpse of a kind is gone (see M.enemy_gone). faced: enemies built like
-- Eve (the Airborne Squad: her skeleton, a separate face mesh), cut with her rules: the face goes with the head
local enemy = { owned = setmetatable({}, { __mode = "k" }), cur = nil, faced = {} }
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
  if not valid(o) and LoadAsset then o = try(function() return LoadAsset(path) end) end
  if not valid(o) then o = try(function() return StaticFindObject(path) end) end
  cache[path] = valid(o) and o or false
  if not valid(o) then log("could not load " .. path) end
  -- an asset (not a native class or default object) stays loaded from now on: see native.root
  if valid(o) and path:sub(1, 8) ~= "/Script/" and native.root then native.root(path, o) end
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
  return read_file(RESULT) or "err no answer"
end

-- sbslice's stretch probe on comp's LOD0, its bone indices named
local function stretch_report(comp)
  local r = command(string.format("s%x,0", comp:GetAddress()))
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
    local ok = tostring(read_file(OK))
    -- every outfit keeps its LOD0 CPU copy (the DLL's NeedCPUData patch): physfix stops warning about the flag
    ctx.cpu_forced = ok:find("cpu copy LOD0 on", 1, true) ~= nil
    -- a reloaded script forgets its cuts, the DLL doesn't: put back anything a previous run left collapsed
    log("sbslice.dll ready: " .. ok .. ", leftovers: " .. command("r"))
  elseif file_exists(ERR) then
    native.state = "failed"; log("sbslice.dll refused: " .. tostring(read_file(ERR)))
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
local function sfx(kind, pawn, at)
  local g = cfg()
  if g.sounds == false or not at then return end
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  if not gs then return end
  -- the sets in random order; the first with no cue still ringing, else the one whose newest cue is the oldest
  local sets, now = SFX[kind] or {}, os.clock()
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
vox.ATTENUATION = "/Game/Sound/SoundAsset/Attenuations/Character/PC_ActionVoice.PC_ActionVoice"
-- vox.last: recording -> os.clock() it last played (none twice within voice.rest s)
function M.voice_death(pawn, mesh)
  local v = cfg().voice or {}
  if v.enabled == false or v.cry == false then return end
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  local at = valid(mesh) and try(function()
    local x = mesh:GetSocketLocation(FName("Bip001-Head")); return { X = x.X, Y = x.Y, Z = x.Z }
  end) or try(function() local x = pawn:K2_GetActorLocation(); return { X = x.X, Y = x.Y, Z = x.Z } end)
  if not (gs and at) then return end
  local now, rest, fresh = os.clock(), v.rest or 8, {}
  for _, path in ipairs(vox.DIE) do if now - (vox.last[path] or -1e9) >= rest then fresh[#fresh + 1] = path end end
  if #fresh == 0 then fresh = vox.DIE end
  local path = fresh[math.random(#fresh)]
  local snd = load_obj(path)
  if not snd then log("voice: " .. path .. " didn't load"); return end
  local vol = v.volume or 1.0
  local ok, err = pcall(function()
    gs:PlaySoundAtLocation(pawn, snd, vec(at.X, at.Y, at.Z), { Pitch = 0, Yaw = 0, Roll = 0 }, vol,
      0.97 + math.random() * 0.06, 0.0, load_obj(vox.ATTENUATION), nil, nil)
  end)
  if ok then vox.last[path] = now end
  log(string.format("voice: %s at %.2f%s", path:match("([^/.]+)$") or path, vol, ok and "" or (" failed: " .. tostring(err))))
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
-- a component's mesh asset (its address): an enemy's sinks are put back per asset
function enemy.asset(comp) local m = valid(comp) and try(function() return comp.SkeletalMesh end); return valid(m) and addr(m) or nil end
local function already_cut(mesh, bone)
  local a = addr(mesh)
  for _, c in ipairs(cuts) do if c.addr == a and c.bone == bone then return true end end
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

-- the flesh on a cap: MI_A_Meat_01_1 is an effect material whose BloodColor glows (emissive 10, 2.4, 0: bright orange
-- on her stumps), so each cap gets its own instance with tune.gore.capBloodColor
local cap_mid_logged = false
local function set_cap_material(comp, mat)
  if not mat then return end
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
  local a, root, lid
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
  M.repose(a, mesh, bone)
  -- EAttachmentRule::KeepWorld = 1
  try(function() a:K2_AttachToComponent(mesh, FName(bone), 1, 1, 1, false) end)
  return a, kind, lid
end

-- a snapped bone in a stump: GM_Brokenbone, its long axis along the opening's normal (out of that side), as thick as
-- stubBone of the opening's narrow radius, sticking out stubOut of it (scaled by that radius), riding the cap's bone.
-- Its own axes are read from its bounds (the longest one is the bone), so the asset's orientation doesn't matter
local stub_dims = nil
-- her back on a plane with normal z: square to her spine, away from her front. A Bip001 spine bone's own -Z points
-- to her back (within 15 degrees on every outfit's skeleton, pelvis to head), so it is read off the spine bone at
-- the cut (bone, else Spine1). It came from the hips and shoulders before (her right from the left thigh and upper
-- arm to the right ones), which were wherever her cut-off limbs lay by then: a waist cut after both arms and legs
-- put the spine stub off to her side (seventeenth playtest)
local SPINE_BONES = { ["Bip001-Pelvis"] = 1, ["Bip001-Spine"] = 1, ["Bip001-Spine1"] = 1, ["Bip001-Spine2"] = 1, ["Bip001-Neck"] = 1, ["Bip001-Head"] = 1 }
local function back_on(mesh, z, bone)
  local km = load_obj("/Script/Engine.Default__KismetMathLibrary")
  local b = SPINE_BONES[bone or ""] and bone or "Bip001-Spine1"
  local up = km and try(function()
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
-- spine: the cut goes through the spine or the neck (a thigh's parent is Bip001-Spine too, and by that bone's name its
-- hip stump's stub sat halfway to her back, sixteenth playtest)
local function stub(pawn, mesh, o, bone, rides, spine)
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
  if spine then
    local back = back_on(mesh, z, bone)
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
  M.repose(a, mesh, rides or bone)
  try(function() a:K2_AttachToComponent(mesh, FName(rides or bone), 1, 1, 1, false) end)
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
local limbs_cache = {}
local function limbs_list(comp, own)
  local sm = try(function() return comp.SkeletalMesh end)
  local key = valid(sm) and (addr(sm) .. "/" .. tostring(own))
  if key and limbs_cache[key] then return limbs_cache[key] end
  local t = M.bone_tree(comp)
  local n = t and t.n or 0
  local list = {}
  for i = 0, n - 1 do
    for _, r in ipairs(LIMB_ROOTS) do
      if r ~= own and M.under(t, i, r) then list[#list + 1] = string.format("%x", i); break end
    end
  end
  local s = table.concat(list, ",")
  if key and n > 0 then limbs_cache[key] = s end
  return s
end
-- the limb root a bone is on (itself or an ancestor in LIMB_ROOTS), else nil
local function limb_root(comp, bone)
  local t = M.bone_tree(comp)
  for _, r in ipairs(LIMB_ROOTS) do
    if bone == r or (t and t.index[bone] and M.under(t, t.index[bone], r)) then return r end
  end
end
-- bones that may never carry a stub (after ffff in the same command): the rig's Dm- drivers, which the animation points
-- at limbs (Dm-Spine-bland, blending Spine and Spine1, carried a waist cut's stub after the flying upper body). An
-- enemy's every bone: its mesh asset is shared with the live enemies of its kind, whose skin on a carrier would move
-- with the cut one's matrix. Nor a bone with a physics body of its own: it swings on its own constraint in a ragdoll
-- (a calf's stub went on Ab-L-Hip, the hip's jiggle body, and would have bounced with it)
local nocarry_cache = {}
-- her bones with a physics body (by index; sent after fffe in "n": a cut's sinks ride the body its stump rides). None
-- for an enemy (its sinks as before)
local function bodies_of(comp)
  local sm = try(function() return comp.SkeletalMesh end)
  local key = valid(sm) and (addr(sm) .. "b")
  if key and nocarry_cache[key] then return nocarry_cache[key] end
  local out = {}
  local pa = not enemy.cur and ctx.physics_of and try(function() return ctx.physics_of(comp) end)
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

-- limbs: true (a torso cut: every limb), a bone name (a limb or head cut: every limb but the one it is on), nil
local function send_nosink(comp, limbs)
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
  local r = command(string.format("n%x,%s,ffff%s%s", comp:GetAddress(), s, nc ~= "" and ("," .. nc) or "",
    #bl > 0 and (",fffe," .. table.concat(bl, ",")) or ""))
  if r:sub(1, 2) ~= "ok" then log("nosink list refused: " .. r) end
end

-- one sbslice.dll cut on a component: "c<comp>,<lod>,<bone>,<mode>,<radius in mm>[,<depth in mm>]", all hex
local function cut_command(comp, index, mode, radius, at, n, depth, limbs)
  send_nosink(comp, limbs)
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
  -- nor our own caps: her lid and spine pieces stand out of her half, over the plane on the copy's side, so they
  -- went to the copy too and rode its bones; her half lay open and the copy carried both lids, the second one in
  -- flat shards off its body as the halves moved apart (eighteenth playtest)
  for _, act in ipairs(caps) do
    local root = valid(act) and try(function() return act:K2_GetRootComponent() end)
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

local function kept_chains(mesh, bone, a, b)
  local pa = ctx.physics_of(mesh)
  if not valid(pa) then return {} end
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
-- with the blade at most sliceTilt degrees off square
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
    if not ok_cut(fr) then log("head skipped: the face can't be cut (no LOD0 CPU access on its mesh?)"); return nil end
  end
  -- the chains that stay on the body ("g": no gone roots, then them); always sent, so an earlier split's limbs aren't
  -- taken for them
  -- and the limbs an earlier cut took off that hang under this one (drop roots): their skin goes with this piece
  -- wherever it lies. Playtest 41: an arm, then the chest along the same blade; the flying arm lay across the chest's
  -- plane, the half on her side lost its weights to her spine and long sheets ran from her to the hand
  local kept, gone = {}, {}
  if (part.kind == "limb" or part.kind == "torso") and (part.mode == nil or part.mode == MODE.cut) then
    if part.kind == "limb" then kept = kept_chains(mesh, bone, a, b) end
    local tree, ma = M.bone_tree(mesh), addr(mesh)
    for _, c in ipairs(cuts) do
      if c.addr == ma and c.bone ~= bone and PARTS[c.bone] then
        local inside = tree and tree.index[c.bone] and M.under(tree, tree.index[c.bone], bone)
        if inside == nil then inside = try(function() return mesh:BoneIsChildOf(FName(c.bone), FName(bone)) end) == true end
        if inside then gone[#gone + 1] = c.bone end
      end
    end
    local f = { string.format("g%x", mesh:GetAddress()) }
    if #kept > 0 or #gone > 0 then
      f[#f + 1] = "0"
      for _, c in ipairs(kept) do
        local i = try(function() return mesh:GetBoneIndex(FName(c)) end)
        if i and i > 0 then f[#f + 1] = string.format("%x", i) end
      end
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
  local detached = {}
  if #kept > 0 and g.chains ~= "body" then
    for _, c in ipairs(kept) do
      local dr = detach_cut(mesh, c, bone)
      log(string.format("cut %s off %s: %s", c, bone, dr))
      if ok_cut(dr) then detached[#detached + 1] = c end
    end
  end
  return { at = at, n = n, result = r, face = fr and face, face_result = fr, facecut = facecut, kept = kept, detached = detached }
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
    -- her own fall can't stand on a leg that's gone (both thighs off, and she still played it, eighteenth playtest)
    if (q.why == "death" or q.why == "after") and cfg().legRagdoll ~= false and (b:find("Thigh") or b:find("Calf") or b:find("Foot"))
      and ctx.animated and ctx.animated() and ctx.on_need_ragdoll then
      try(function() ctx.on_need_ragdoll("a leg off") end)
    end
    q.c = cut_limb(q.pawn, q.mesh, b, q.why, blow, q.face, q.blade)
    mark("cut " .. b)
    if q.c then q.bone = b; break end
  end
  if not q.bone then log("nothing cut (" .. q.why .. ")"); return false end
  cuts[#cuts + 1] = { mesh = q.mesh, addr = addr(q.mesh), bone = q.bone, sm = enemy.asset(q.mesh) }
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
  q.posed = M.snap({ { q.mesh, { q.rideB, q.rideL } } })
  q.caps, q.kinds, q.stubs = {}, {}, {}
  return true
end

-- stage 1b, the next tick: the caps and stubs (hidden till the opening). In the cut's own tick they made its frame
-- 20 ms longer, and a killing blow's two or three cuts stuttered one after another (twenty-ninth playtest)
-- (and the caps and the stubs a tick each: together they were 23-29 ms, playtest 41)
function M.stage_caps(q)
  M.posed = q.posed
  if cfg().caps ~= false then
    q.caps[1], q.kinds[1] = cap(q.pawn, q.mesh, q.ob, q.rideB)
    q.caps[2], q.kinds[2] = cap(q.pawn, q.mesh, q.ol, q.rideL)
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
    q.stubs[#q.stubs + 1] = stub(q.pawn, q.mesh, q.ol, q.bone, q.rideL, spine)
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

-- a broken constraint takes its "don't collide" pair with it, and the two bodies overlap at the joint: the piece got
-- shoved out of the stump every frame (an upper body cut off a standing Eve spun wildly against her kinematic hips).
-- So after a cut her bodies stop colliding with each other (PhysicsBody = 5), until she recovers
local function no_self_collision(mesh)
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
  no_self_collision(q.mesh)
  mark("self collision")
  -- off it goes: the constraint at the limb's root breaks (its bodies start simulating if she was alive)
  local skip = {}
  for _, c in ipairs(q.c.kept or {}) do skip[c] = true end
  local tops = M.break_limb(q.mesh, q.bone, q.c.at, skip)
  local broke = true
  if #tops > 0 then world = world .. ", no body on " .. q.bone .. ": broke " .. table.concat(tops, ",") end
  mark("break")
  if ctx.on_cut and not enemy.cur then
    try(function() ctx.on_cut(q.mesh, q.bone) end)
    for _, c in ipairs(tops) do try(function() ctx.on_cut(q.mesh, c) end) end
  end
  mark("on_cut")
  local nh = hang_chains(q)
  mark("chains")
  if nh ~= "" then world = world .. ", " .. nh end
  -- a killing blow sends the piece flying the way it hit her (q.fly), else it drops off away from the body; every
  -- body of the piece gets the speed (the root's alone dragged the rest, a small push)
  local throw = q.fly and (g.deathThrow or 650) or (g.throw or 250)
  -- a leg is the big piece: dropping off it gets more (legThrow), or it dropped at her feet
  local leg = q.bone:find("Thigh") or q.bone:find("Calf")
  if leg and not q.fly then throw = throw * (g.legThrow or 1.4) end
  if throw > 0 then
    local v = q.fly and norm(add(add(q.fly, scale(q.c.n, 0.35)), vec((math.random() - 0.5) * 0.3, (math.random() - 0.5) * 0.3, 0.45)))
      or norm(add(q.c.n, vec((math.random() - 0.5) * 0.6, (math.random() - 0.5) * 0.6, 0.4)))
    v = v or q.c.n
    if leg then v = norm(add(v, vec(0, 0, g.legLift or 0.35))) or v end
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
  mark("throw")
  for _, a in pairs(q.caps) do if valid(a) then try(function() a:SetActorHiddenInGame(false) end) end end
  for _, a in pairs(q.stubs or {}) do if valid(a) then try(function() a:SetActorHiddenInGame(false) end) end end
  mark("show caps")
  if g.blood ~= false then
    if not enemy.cur then blood_up(q.pawn) end
    if q.parent then track_opening(q, q.caps[1], q.ob, q.mesh, q.rideB or q.parent) end
    track_opening(q, q.caps[2], q.ol, q.mesh, q.rideL or q.bone)
  end
  if g.blood ~= false then
    if g.sliceFx == true then niagara(FX.slice, q.pawn, nil, q.c.at, false) end
    niagara(FX.splat, q.pawn, nil, q.c.at, false)
  end
  mark("blood")
  -- a leg is as big a cut as the head or the waist
  sfx((q.bone == "Bip001-Head" or q.bone == "Bip001-Spine1" or q.bone:find("Thigh") or q.bone:find("Calf")) and "big" or "cut",
    q.pawn, q.c.at)
  if g.blood ~= false then
    -- bleed from both openings, for a while: from the cap, which rides on that side's bone, else from the
    -- opening's centre on the bone; oriented like that bone (the effect was made for bone attachment). The next
    -- tick: it was 10-15 ms of the opening's frame (playtest 41)
    local left = math.floor((g.bleedTime or 2.5) / TICK_S + 0.5)
    later[#later + 1] = { n = 1, fn = function()
      if not valid(q.mesh) then return end
      if q.parent then bleed_from(q, q.caps[1], q.ob, q.rideB or q.parent, left) end
      bleed_from(q, q.caps[2], q.ol, q.rideL or q.bone, left)
    end }
  end
  mark("sound, bleed")
  log(string.format("%s off (%s): %s, constraint broken=%s, caps %s / %s%s", q.bone, q.why, k, tostring(broke == true),
    tostring(q.kinds[1]), tostring(q.kinds[2]), world))
  if PARTS[q.bone] and PARTS[q.bone].kind ~= "head" then
    local anchor = parent_bone(q.mesh, q.bone)
    local pa = ctx.physics_of(q.mesh)
    local has = {}
    if valid(pa) then
      try(function() pa.SkeletalBodySetups:ForEach(function(_, e) local bs = e:get(); if valid(bs) then has[bs.BoneName:ToString()] = true end end) end)
    end
    while anchor and not has[anchor] do anchor = parent_bone(q.mesh, anchor) end
    -- (diagnostics: the stretch probe skins every vertex on the CPU, a stutter of its own; tune.gore.probes)
    if cfg().probes or ctx.tune.dev then limb_watch = { mesh = q.mesh, bone = q.bone, kept = q.c.kept or {}, anchor = anchor, n = 0 } end
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
  for _, b in ipairs(SPLIT_LIMBS) do
    local l = bone_loc(comp, b)
    if l then
      if dot(sub(l, at), n) < 0 then gone[#gone + 1] = b else keep[#keep + 1] = b end
    end
  end
  return gone, keep
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
  for _, b in ipairs(ride) do
    local tm = bone_tm(comp, b)
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
  local limit = (cfg().splitLidFollow or 12) / TICK_S
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
    local made, bent = 0, 0
    for _, pc in ipairs(pieces or {}) do
      local a, kind, pmc = cap(q.pawn, comp, o, pc.bone, pc.built)
      if a and pmc and pc.skin and skin_lid(comp, a, pmc, pc, ride) then bent = bent + 1 end
      if a then
        made = made + 1
        list[#list + 1] = { actor = a, o = o, ride = pc.bone, comp = comp, kind = kind, whole = pc.skin }
      end
    end
    local ns = spine_halves(q, comp, o, list)
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
  -- splitBeside: leaned about her front-to-back axis from her crotch to that far beside her neck, so the head stays
  -- whole on her half. Her crotch, the gap between her breasts (they sit 4.3 cm either side) and her neck all lie on
  -- her middle, so the lean is small: at 10 cm the cut ran 7 cm off it at the chest, through a breast; at 2, 1.4 cm
  local side, neck = cfg().splitBeside or 2, bone_loc(q.mesh, "Bip001-Neck")
  if side > 0 and neck then
    local t = norm(cross(axis, n))
    local d = sub(sub(neck, scale(n, side)), pel)
    local m = t and norm(cross(t, d))
    if m then
      if dot(m, n) < 0 then m = scale(m, -1) end
      at, n, from = pel, m, from .. ", beside the neck"
    end
  end
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

-- the copy's break: the spine bone her half breaks at, or the next one up when the copy's own legs hang off it (the
-- Biped thighs' parent is Bip001-Spine, not the pelvis): a waist split just over the pelvis broke both halves there,
-- and the copy let its legs go with the spine (playtest 40)
function M.copy_break(mesh, spine, kept)
  if not spine then return nil end
  local si
  for i, b in ipairs(SPINE_CHAIN) do if b == spine then si = i end end
  for _, l in ipairs(kept or {}) do
    if try(function() return mesh:BoneIsChildOf(FName(l), FName(spine)) end) == true then return si and SPINE_CHAIN[si + 1] end
  end
  return spine
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
    -- the head on her half's side (a leaned plane runs past it)
    local head = at and bone_loc(q.mesh, "Bip001-Head")
    if head and dot(sub(head, at), n) < 0 then n = scale(n, -1) end
    if at then q.spine = spine_break(q.mesh, at, n) end
  end
  if not at then log("split skipped: no bone transforms"); return false end
  q.c = { at = at, n = n }
  q.gone1, q.gone2 = limb_sides(q.mesh, at, n)
  q.spine2 = M.copy_break(q.mesh, q.spine, q.gone1)
  place_like(q.body2, q.mesh)
  local p = command(string.format("p%x,%x", q.mesh:GetAddress(), q.body2:GetAddress()))
  local neg = scale(n, -1)
  -- recorded before they are checked, so a failed half is undone with the rest
  cuts[#cuts + 1] = { mesh = q.mesh, addr = addr(q.mesh), bone = "split" }
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
  send_limbs(q.mesh, q.gone1, keep1, back, SPLIT_RIDE.of(q, q.mesh), q.spine, true)
  local h1 = send_neck(q.mesh, 1)
  local r1 = side_cut(q.mesh, SPLIT_SINK, at, n)
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
  send_limbs(q.body2, q.gone2, c1.keep2, front, SPLIT_RIDE.of(q, q.body2), q.spine2, false)
  local h2 = send_neck(q.body2, 2)
  local r2 = side_cut(q.body2, SPLIT_SINK, at, c1.neg)
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
  if q.bodies then return end
  q.bodies = true
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
  if cfg().probes or ctx.tune.dev then copy_watch = { comp = b2, her = q.mesh, n = 0, helpers = { her = helper_pose(q.mesh), copy = helper_pose(b2) } } end
  if ctx.on_copy then try(function() ctx.on_copy(b2) end) end
  mark("copy masses")
  -- she stood still while it was cut; now both halves fall, before they get pushed apart
  if ctx.on_release then try(function() ctx.on_release() end) end
  mark("release")
  log(string.format("split copy ragdoll: simulating %s%s, collision %s", tostring(sim2), sim and "" or " (second try)",
    tostring(try(function() return b2:GetCollisionEnabled() end))))
  local at, n = q.c.at, q.c.n
  local push = g.splitPush or 120
  no_self_collision(q.mesh)
  local b1 = settle_half(q.mesh, at, n, push, q.gone1, q.spine, true)
  -- the copy's head is closed over: its body comes off and weighs nothing, like a gone limb's
  local gone2 = { table.unpack(q.gone2 or {}) }
  if not (q.spine and q.spine ~= "Bip001-Head") then gone2[#gone2 + 1] = "Bip001-Head" end
  local b2l = settle_half(b2, at, scale(n, -1), push, gone2, q.spine2, false)
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
  local b2 = q.body2
  -- the copy takes over the pose she is in now
  place_like(b2, q.mesh)
  local p = command(string.format("p%x,%x", q.mesh:GetAddress(), b2:GetAddress()))
  try(function() b2:SetHiddenInGame(false, false) end)
  mark("copy shown")
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
    q.anim and string.format(", her fall plays on for %.1f s", q.anim) or ""))
end

local start -- below; a degenerate split falls back to a waist cut through it
local aimed -- M.aim: the next cut's flying direction
local split_stage
local function split_tick(q) split_stage(q) end
split_stage = function(q)
  if q.stage == "cut" then
    if stage_split_prep(q) then q.stage = "cut2"; q.wait = 2; return end
  elseif q.stage == "cut2" then
    if stage_split_cut(q) then q.stage = "cut3"; q.wait = 0; return end
  elseif q.stage == "cut3" then
    if M.stage_split_copy(q) then
      local function rides(c) local l = { "Bip001-Neck" }; for _, b in ipairs(SPLIT_RIDE.of(q, c) or {}) do l[#l + 1] = b end; return l end
      q.posed = M.snap({ { q.mesh, rides(q.mesh) }, { q.body2, rides(q.body2) } })
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
    if not q.anim then M.split_bodies(q) end
    q.stage, q.wait = "open", 1
    return
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
    face = face, out = out, plane = plane, blade = blade, owner = enemy.cur, bone = M.bone_once,
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
    or (not blade and tb.kind == "torso")
  -- unless it is a split and she is playing her fall: then both halves play on with it for tune.gore.splitAnim
  -- seconds before they come apart (split_tick)
  local anim = why == "death" and kind == "split" and (g.splitAnim or 0.7) > 0 and ctx.animated and ctx.animated()
  if anim then
    pending.anim = g.splitAnim or 0.7
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
  M.tick(pawn)
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

function M.slice(pawn, mesh, hit, why, kind) return start(pawn, mesh, hit, why, kind or "limb") end
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
  local crossed = {} -- per limb (side and arm / leg): its crossing nearest the hit
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
        local limb = sg[1]:match("Bip001%-(%a)%-") .. ((sg[1]:find("Arm") or sg[1]:find("Forearm")) and "arm" or "leg")
        if not crossed[limb] or dd < crossed[limb].d then crossed[limb] = c end
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
  -- more cuts from one wide swing (multiCut): every other arm or leg the plane crosses within reach cm of the hit,
  -- and the neck when it crosses that near, after the first cut. One cut a death left a sweep through both arms
  -- taking one of them
  local mc = cfg().multiCut or {}
  local reach, most = mc.reach or 40, mc.max or 3
  local function extras(first)
    local out = {}
    if mc.enabled == false or most <= 1 then return out end
    local skip = first and first.bone and (first.bone:match("Bip001%-(%a)%-") .. ((first.bone:find("Arm") or first.bone:find("Forearm")) and "arm" or "leg"))
    -- an arm the swing met first (raised to block, held in front of her) doesn't stop it: where its plane goes on
    -- through her spine below the neck, within bodyReach cm of the hit, her body is cut too, across the chest or the
    -- waist along the blade (it took the arm alone before)
    if first and first.kind == "limb" and skip and skip:find("arm") and mc.body ~= false and not already_cut(mesh, "Bip001-Spine1") then
      local near
      for i = 1, 4 do
        if (hs[i] < 0) ~= (hs[i + 1] < 0) then
          local a, b = bone_loc(mesh, SPINE_CHAIN[i]), bone_loc(mesh, SPINE_CHAIN[i + 1])
          local tt = hs[i] / (hs[i] - hs[i + 1])
          local x = a and b and add(a, scale(sub(b, a), tt))
          local dd = x and math.sqrt(dot(sub(x, at), sub(x, at)))
          if dd and dd < (mc.bodyReach or 60) and (not near or dd < near.d) then
            -- (the cut is made between Spine1 and Spine2, the blade's point clamped there: a crossing below it low,
            -- one above it high)
            near = { bone = "Bip001-Spine1", t = i == 3 and tt or (i < 3 and 0 or 1), d = dd, n = n }
          end
        end
      end
      if near then out[#out + 1] = { kind = "torso", blade = near } end
    end
    local list = {}
    for limb, c in pairs(crossed) do if limb ~= skip and c.d < reach then list[#list + 1] = c end end
    table.sort(list, function(x, y) return x.d < y.d end)
    for _, c in ipairs(list) do if #out < most - 1 then out[#out + 1] = { kind = "limb", blade = c } end end
    if first and first.kind ~= "head" and #out < most - 1 and (hs[5] < 0) ~= (hs[6] < 0) and not (out[1] and out[1].kind == "torso") then
      local nk = bone_loc(mesh, "Bip001-Neck")
      if nk and math.sqrt(dot(sub(nk, at), sub(nk, at))) < reach then out[#out + 1] = { kind = "head" } end
    end
    return out
  end
  -- the rest, queued in her own frame (the ragdoll moves on while the first cut opens)
  local function queue(list)
    if #list == 0 then return "" end
    local f = body_frame(mesh)
    local names = {}
    for _, e in ipairs(list) do
      local rel = f and e.blade and to_body(f, e.blade.n)
      queued[#queued + 1] = function()
        if e.kind == "head" then return start(pawn, mesh, bone_loc(mesh, "Bip001-Neck") or at, why, "head", h.dir) end
        local c = { bone = e.blade.bone, t = e.blade.t, d = e.blade.d, n = e.blade.n }
        local fn = rel and body_frame(mesh)
        if fn then c.n = norm(from_body(fn, rel)) or c.n end
        if already_cut(mesh, c.bone) then return false end
        return start(pawn, mesh, bone_loc(mesh, c.bone) or at, why, e.kind, nil, nil, c)
      end
      names[#names + 1] = e.kind == "head" and "head" or e.kind == "torso" and string.format("her body at %s %.0f cm in", e.blade.bone, e.blade.d) or e.blade.bone
    end
    return ", then " .. table.concat(names, ", ")
  end
  -- a cut down her length (the plane along her spine) at death is off (deathSplit false): the limbs it crosses near
  -- the hit come off instead, or the death's odds are rolled
  local axis = (function()
    local p0, p1 = bone_loc(mesh, "Bip001-Pelvis"), bone_loc(mesh, "Bip001-Neck")
    return p0 and p1 and norm(sub(p1, p0))
  end)()
  local lengthwise = axis and math.abs(dot(axis, n)) < 0.6
  if (what == "slice" or (not pos and not neg)) and lengthwise and (why == "death" or why == "after") and cfg().deathSplit == false then
    local list = extras(nil)
    if #list == 0 or list[1].kind ~= "limb" then
      log(string.format("blade (%s): %s plane down her length, no split at death (deathSplit off)", why, how))
      return false
    end
    local first = table.remove(list, 1)
    local more = queue(list)
    log(string.format("blade (%s): %s plane down her length, no split at death: %s at %.2f instead%s", why, how,
      first.blade.bone, first.blade.t, more))
    return start(pawn, mesh, at, why, "limb", nil, nil, first.blade)
  end
  -- a blade through her body splits her only bladeSplit of the time; else the death's odds are rolled (main.lua)
  -- (a hip or knee plane only moves to the waist: a torso cut, not a split, kept every time; at 0.2 they were rolled
  -- away and her deaths took a limb far more often than the head or the waist, thirty-fifth playtest)
  local splits = what == "slice"
  if splits and math.random() > (cfg().bladeSplit or 0.2) then
    log(string.format("blade (%s): %s plane through her body, no split this time (bladeSplit %.2f)", why, how, cfg().bladeSplit or 0.2))
    return false
  end
  -- a blow that would split her when she can't be split (h.noSplit: a hit after death on a body already cut; a split
  -- needs her whole): nothing here, main.lua marks her instead
  if h.noSplit and (hip or (what == "limb" and best and off < (cfg().spineReach or 15) and best.bone:find("Calf"))
    or (what ~= "limb" and what ~= "head")) then
    log(string.format("blade (%s): %s plane through her body, she is cut already: no split", why, how))
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
  -- a plane that crosses no arm or leg past the spine: the one the blow was aimed at is cut square, when it has one
  -- (nineteenth playtest: a swing 279 cm off, moved onto her forearm, ran along it and the death rolled its odds)
  if what == "limb" and not best and h.bone and not already_cut(mesh, h.bone) then
    for _, sg in ipairs(LIMB_SEGS) do
      if sg[1] == h.bone then
        local a, b = bone_loc(mesh, sg[1]), bone_loc(mesh, sg[2])
        local ax = a and b and norm(sub(b, a))
        if ax then
          best = { bone = sg[1], t = CUT_AT_DEFAULT, d = 0, n = ax }
          how = how .. " (along the limb it was aimed at: cut square)"
        end
        break
      end
    end
  end
  -- enemy swings mostly cross an arm or a leg (low, from the side), so a killing blade that would take a limb takes
  -- the head or her body instead bodyBias of the time (by the death odds' head : torso): the head square to the
  -- neck, the body across the waist along the blade when it crosses her, else square to her spine
  if what == "limb" and why == "death" and not h.noSplit and math.random() < (cfg().bodyBias or 0) then
    local d = cfg().death or {}
    local wh, wt = already_cut(mesh, "Bip001-Head") and 0 or (d.head or 20), already_cut(mesh, "Bip001-Spine1") and 0 or (d.torso or 30)
    if wh + wt > 0 then
      if math.random() * (wh + wt) < wh then
        log(string.format("blade (%s): %s plane would take a limb, the head instead (bodyBias %.2f)", why, how, cfg().bodyBias))
        return start(pawn, mesh, bone_loc(mesh, "Bip001-Neck") or at, why, "head", h.dir)
      end
      local a, b = bone_loc(mesh, "Bip001-Spine"), bone_loc(mesh, "Bip001-Spine1")
      if a and b then
        local w = add(a, scale(sub(b, a), 0.4))
        local across = axis and math.abs(dot(axis, n)) >= 0.6
        local wn = across and n or norm(sub(b, a))
        log(string.format("blade (%s): %s plane would take a limb, across the waist at %s instead (%s, bodyBias %.2f)",
          why, how, v3(w), across and "along the blade" or "square", cfg().bodyBias))
        return start(pawn, mesh, w, why, "split", wn, { at = w, n = wn })
      end
    end
  end
  local blade = what == "limb" and best or nil
  log(string.format("blade (%s): %s plane at %s normal %s, dir %s fwd %s attack %s, spine %s cm off it -> %s%s",
    why, how, v3(at), vs(n), vs(h.dir), vs(h.fwd), tostring(h.attack_dir), table.concat(spine, "/"), what,
    blade and (" " .. blade.bone .. string.format(" at %.2f", blade.t)) or ""))
  if what == "limb" then
    if not blade then return false end
    local more = why == "death" and queue(extras({ kind = "limb", bone = blade.bone })) or ""
    if more ~= "" then log("blade (" .. why .. "): one swing" .. more) end
    return start(pawn, mesh, at, why, "limb", nil, nil, blade)
  elseif what == "head" then
    local more = why == "death" and queue(extras({ kind = "head" })) or ""
    if more ~= "" then log("blade (" .. why .. "): one swing" .. more) end
    return start(pawn, mesh, at, why, "head", h.dir)
  end
  -- a plane along her that has every arm and leg on one side only grazes her: the other half was a sliver of skin
  -- and its copy stayed whole over her (a 45 degree blade on an animated death). Across the waist instead
  if not (pos and neg) then
    local front, back = 0, 0
    for _, b in ipairs(SPLIT_LIMBS) do
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

-- run fn(...) cutting for owner (an enemy's address, nil for Eve): whatever it adds to the lists is tagged with it
function enemy.run(owner, fn, ...)
  local prev = enemy.cur
  enemy.cur = owner
  local lists = { spawned, bleeds, later, caps, hung, trackers, decals, no_decals, cuts, queued, hid }
  local n0 = {}
  for i, l in ipairs(lists) do n0[i] = #l end
  local r = table.pack(pcall(fn, ...))
  for i, l in ipairs(lists) do
    for k = n0[i] + 1, #l do if enemy.owned[l[k]] == nil then enemy.owned[l[k]] = owner or false end end
  end
  enemy.cur = prev
  if not r[1] then error(r[2], 0) end
  return table.unpack(r, 2, r.n)
end
local function owner_of(x) return enemy.owned[x] or nil end

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
  if stage ~= "anim" then
    log(string.format("%s stage %s at +%.0f ms took %.0f ms%s", q.kind, stage, (t0 - (q.t0 or t0)) * 1000, ms,
      ms >= (cfg().slowMs or 15) and ": " .. table.concat(prof, ", ") or ""))
  end
  prof = nil
  if not ok then error(err, 0) end
end
stage_step = function(q)
  if q.kind == "split" then return split_tick(q) end
  if q.stage == "cut" then
    if stage_cut(q) then q.stage = "caps"; q.wait = 0; return end
    pending = nil
    -- nothing came off: give the LOD back unless an earlier cut still needs it
    release_lods()
  elseif q.stage == "caps" then
    M.stage_caps(q)
    q.stage, q.wait = "stubs", 0
  elseif q.stage == "stubs" then
    M.stage_stubs(q)
    q.stage, q.wait = "open", 1
  else
    pending = nil
    stage_open(q)
  end
end

-- her bones looked at while she plays, every WATCH_EVERY ticks: a stub's carrier must be a helper that held still
-- against its parent all along (sbslice "w"; an animation-driven corrective flung a thigh's stub about, twenty-fifth
-- playtest)
M.watching = { every = 5, n = 0 }
function M.watch(mesh)
  local w = M.watching
  if cfg().enabled == false or native.state ~= "ready" or not valid(mesh) then return end
  w.n = w.n + 1
  if w.n % w.every ~= 0 then return end
  local r = command(string.format("w%x", mesh:GetAddress()))
  if r:sub(1, 2) ~= "ok" and not w.logged then w.logged = true; log("bone watch refused: " .. r) end
  -- and while she plays, the cuts' assets are loaded (and kept: native.root) one a look, so even the first cut
  -- loads nothing
  if not w.preload then
    local g, list = cfg(), {}
    for _, v in pairs(FX) do list[#list + 1] = v end
    for _, sets in pairs(SFX) do for _, set in ipairs(sets) do for _, v in ipairs(set) do list[#list + 1] = v end end end
    for _, v in ipairs(vox.DIE) do list[#list + 1] = v end
    for _, v in ipairs(POOL_DECALS) do list[#list + 1] = v end
    for _, v in ipairs(DRIP_DECALS) do list[#list + 1] = v end
    for _, v in ipairs(M.MARK_DECALS) do list[#list + 1] = v end
    for _, v in ipairs(M.MARK_SLASH) do list[#list + 1] = v end
    for _, v in ipairs({ vox.ATTENUATION, MPC_DIRTY, g.capMaterial or CAP_MATERIAL, g.stubMesh or STUB_MESH }) do list[#list + 1] = v end
    w.preload, w.next = list, 1
  end
  -- and her outfit's bone tree, 40 bones a look, then the cut's bone lists made from it (warm: nothing left to read
  -- when the cut comes)
  local t = M.bone_tree(mesh, 40)
  if t and not t.warm then
    t.warm = true
    nosink_list(mesh); nocarry_list(mesh); limbs_list(mesh, nil)
    for _, r in ipairs(LIMB_ROOTS) do limbs_list(mesh, r) end
  end
  local path = w.preload[w.next]
  if path then
    w.next = w.next + 1
    if not native.rooted[path] then load_obj(path) end
    if w.next > #w.preload then
      local n = 0
      for _, ok in pairs(native.rooted) do if ok then n = n + 1 end end
      log(string.format("cut assets loaded and kept: %d of %d", n, #w.preload))
    end
  end
end

-- tm: main.lua's slow tick marker (each part's time, when the tick is slow)
function M.tick(pawn, tm)
  if cfg().enabled == false then return end
  tm = tm or function() end
  native_tick()
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
  tm("gore later, bleeds")
  if limb_watch then
    local w = limb_watch
    w.n = w.n + 1
    if w.n == 30 or w.n == 150 then
      if valid(w.mesh) then
        log(string.format("cut stretch, %s at %.0f s: %s", w.bone, w.n * TICK_S, stretch_report(w.mesh)))
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
        for _, h in ipairs({ { "her half", w.her }, { "copy", w.comp } }) do
          if valid(h[2]) then log(string.format("split stretch, %s at %.1f s: %s", h[1], w.n * TICK_S, stretch_report(h[2]))) end
        end
        log(string.format("split helpers off their parents at %.1f s: her half %s | copy %s", w.n * TICK_S,
          helper_drift(w.her, w.helpers.her), helper_drift(w.comp, w.helpers.copy)))
        if w.n == 60 then copy_watch = nil end
      end
    end
  end
  if not pending and #queued > 0 then
    local nx = table.remove(queued, 1)
    local ok, err = pcall(enemy.run, owner_of(nx), nx)
    if not ok then log("next cut of the blow failed: " .. tostring(err)) end
  end
  local q = pending
  if not q then return end
  if not valid(q.mesh) then pending = nil; return end
  if q.wait > 0 then q.wait = q.wait - 1; return end
  -- a stage that throws would run again on every tick and block every later cut: it ends the cut instead
  local ok, err = xpcall(enemy.run, debug and debug.traceback or tostring, q.owner, stage_tick, q)
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
      if valid(comp) and comp ~= mesh then try(function() comp:SetForcedLOD(0) end) end
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
    step("lod", function() mesh:SetForcedLOD(0) end)
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
    if kind ~= "mark" and (h.n or (h.dir and h.fwd)) and h.loc then
      h.noSplit = true
      if M.blow(pawn, mesh, h, "enemy") then return "blade" end
      if pending then return nil end
    end
    if kind == "mark" then return M.hit_mark(pawn, mesh, h.loc, h.dir, nil) and "mark" or nil end
    return start(pawn, mesh, h.loc, "enemy", kind or "limb") and (kind or "limb") or nil
  end)
end
-- the cuts made on an enemy so far, and whether one is still opening
function M.enemy_cuts(owner)
  local n = 0
  for _, c in ipairs(cuts) do if enemy.owned[c] == owner then n = n + 1 end end
  for _, f in ipairs(queued) do if enemy.owned[f] == owner then n = n + 1 end end
  return n, pending ~= nil and pending.owner == owner
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
    if not lost and valid(c) then c:Deactivate(); c:K2_DestroyComponent(c); nf = nf + 1 end
  end)
  bleeds = drop(bleeds)
  later = drop(later)
  queued = drop(queued)
  hid = drop(hid)
  trackers = drop(trackers)
  caps = drop(caps, function(a) if valid(a) then a:K2_DestroyActor(); nc = nc + 1 end end)
  hung = drop(hung, function(pc) if not lost and valid(pc) then pc:BreakConstraint(); pc:K2_DestroyComponent(pc) end end)
  decals = drop(decals, function(d) if valid(d) then d:K2_DestroyComponent(d) end end)
  no_decals = drop(no_decals, function(e)
    if not gone and valid(e.comp) and addr(e.comp) == e.addr then e.comp:SetReceivesDecals(e.was ~= false) end
  end)
  local bones, faces = {}, {}
  cuts = drop(cuts, function(c)
    if c.bone == "face" then faces[#faces + 1] = c else bones[#bones + 1] = c.bone end
    if c.sm then sms[c.sm] = true end
  end)
  enemy.faced[owner] = nil
  if pending and pending.owner == owner then pending = nil end
  -- (a destroyed actor's memory is still there until the next garbage collection: enemies.lua polls every tick)
  local a = mesh and addr(mesh) -- (GetAddress reads nothing of the object)
  if limb_watch and (gone or limb_watch.mesh == mesh) then limb_watch = nil end
  local steps = {}
  if a and forced[a] then
    if not gone and valid(forced[a]) then try(function() forced[a]:SetForcedLOD(0) end) end
    forced[a] = nil
  end
  if a and not gone and valid(mesh) then steps[#steps + 1] = "weights(" .. command(string.format("x%x,0,1", a)) .. ")" end
  -- an Eve-built enemy's face, cut whole with its head
  for _, c in ipairs(faces) do
    if forced[c.addr] then
      if not gone and valid(forced[c.addr]) then try(function() forced[c.addr]:SetForcedLOD(0) end) end
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
function M.enemy_fading(owner)
  local nc, nf = 0, 0
  local function drop(l, fn)
    local keep = {}
    for _, x in ipairs(l) do
      if enemy.owned[x] == owner then if fn then try(function() fn(x) end) end else keep[#keep + 1] = x end
    end
    return keep
  end
  caps = drop(caps, function(a) if valid(a) then a:K2_DestroyActor(); nc = nc + 1 end end)
  spawned = drop(spawned, function(c) if valid(c) then c:Deactivate(); c:K2_DestroyComponent(c); nf = nf + 1 end end)
  bleeds = drop(bleeds)
  trackers = drop(trackers)
  log(string.format("enemy %x dissolving: %d caps, %d effects removed", owner, nc, nf))
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
  later, hung, queued, skinned, hid = {}, {}, {}, {}, {}
  bleed_logged = false
  pending, collision_saved, self_saved, copy_watch, limb_watch = nil, nil, nil, nil, nil
  enemy.owned, enemy.cur, enemy.faced = setmetatable({}, { __mode = "k" }), nil, {}
  cache, nosink_cache, nocarry_cache, limbs_cache = {}, {}, {}, {}
  -- a collection's values live in the old world, which is gone with them
  body_blood, stub_dims = nil, nil
  decals, trackers, no_decals = {}, {}, {}
  M.mk.list = {}
end

return M
