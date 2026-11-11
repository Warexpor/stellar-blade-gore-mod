-- enemies.lua: the gore on generic humanoid enemies (tune.enemies), and the enemy spawner.
--
-- Gore: every character of a kind tune.enemies.kinds lists (Naytiba on the Bip001 skeleton Eve's cuts know: the
-- skulls, the lab mutant, the statues, the lurkers; the Airborne Squad, built like her, face and all) is followed
-- while it is within reach of Eve. Its
-- mesh's hit reaction says where she hit it; her right hand's path says how she swung. When it dies (its ragdoll
-- starts) the killing blow cuts it as one cuts her (gore.enemy_cut: along her swing, a limb, the head or across the
-- waist, never a split), and her swings through its corpse cut it again. The game's own monster slicer is switched
-- off on them (tune.enemies.nativeSlice). When the corpse starts dissolving its caps and bleeds go (gore.enemy_fading);
-- when it goes (destroyed, hidden for reuse, or up again) the rest of its gore goes with it (gore.enemy_gone).
-- Experimental spawner: F5 spawns the kind picked (Insert picks the next) in front of her, Home opens the spawner window
-- (sbslice.dll, native/sbslice/spawner.c), which lists the kinds and asks for spawns (and kills) through spawner.req. Spawning
-- goes through the game's own SBNetworkPlayerController:ServerRequest_CreateActor (CharacterTable ID, position,
-- rotation), which runs locally in single player.
local M = {}
local ctx, try, valid
local function cfg() return ctx.tune.enemies or {} end
local function log(s) ctx.log("enemies: " .. s) end
local function vlog(s) if ctx.tune.verboseLog then log(s) end end -- (per-enemy chatter: tune.verboseLog only)

local DIR = "ue4ss/Mods/StellarBladeGore/"
local LIST, CMD, REQ, STATE = DIR .. "spawner.list", DIR .. "spawner.cmd", DIR .. "spawner.req", DIR .. "spawner.state"
local TICK_S = 0.033
local FAR_EVERY = 4
-- seconds of her hand kept: a kill is seen when its ragdoll starts, which comes a while after the blow that killed it
-- (the death show's hit pause and stagger first); the swing is looked for round the hit, not in the last swingWindow
local HAND_S = 1.5

local known = {}     -- actor address -> { obj, mesh, cls, kind, dead, t, hit, cut, hits, still, sm }
local mine = {}      -- actor address -> true: spawned here (Remove all takes them)
local expect = {}    -- { kind, at, t }: spawn requests waiting for their actor
local hand = {}      -- Eve's right hand, the last HAND_S seconds: { t, p }
local n = 0
local freed = false  -- the mouse is given to the spawner window
local restore_boss_weapons

local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local function sub(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function cross(a, b) return vec(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
local function len(a) return math.sqrt(dot(a, a)) end
local function unit(a) local l = len(a); return l > 1e-6 and vec(a.X / l, a.Y / l, a.Z / l) or nil end
local function vof(v) return v and vec(v.X, v.Y, v.Z) or nil end
local function v3(v) return v and string.format("(%.0f %.0f %.0f)", v.X, v.Y, v.Z) or "(?)" end
local function addr(o) return try(function() return o:GetAddress() end) end
-- (bone names made into FNames once: each FName() looks the string up in the name table, and these run per enemy per poll)
local FN = setmetatable({}, { __index = function(t, b) local f = FName(b); t[b] = f; return f end })
local function bone_loc(mesh, b) return try(function() return vof(mesh:GetSocketLocation(FN[b])) end) end

-- the kinds followed: tune.enemies.kinds, then the Bosses group's kinds (bosses.lua: spawned from F3 →
-- Spawner, cut as these are)
local allKinds, allFor, allForB = {}, nil, nil
local function kinds()
  local a, b = cfg().kinds or {}, (ctx.tune.bosses or {}).kinds or {}
  if allFor ~= a or allForB ~= b then
    allKinds, allFor, allForB = {}, a, b
    for _, k in ipairs(a) do allKinds[#allKinds + 1] = k end
    for _, k in ipairs(b) do allKinds[#allKinds + 1] = k end
  end
  return allKinds
end
-- a kind's Blueprint class name: the asset's name with _C
local function class_of(k) return (k.bp or ""):match("([^/]+)$") .. "_C" end
local byClass, byClassFor = nil, nil
local function kind_of(cls)
  local ks = kinds()
  if byClassFor ~= ks then
    byClass, byClassFor = {}, ks
    for _, k in ipairs(ks) do byClass[class_of(k)] = k end
  end
  return byClass[cls]
end
-- story angels on a different Blueprint but Eve's body (an ending fight's humanoids): cut as the Airborne Squad.
-- kind_of only knows the curated Blueprint, so variants would track as roster rows and never cut. Eve herself
-- (CH_P_) is never it. Cached by address; cleared when the actor goes and on forget.
local angelCache, angelKind = {}, nil
local function angel_kind_for(c)
  local a = c.addr
  if angelCache[a] ~= nil then return angelCache[a] or nil end
  local k = nil
  if not c.cls:find("CH_P_", 1, true) then
    local mesh = valid(c.obj) and try(function() return c.obj.Mesh end)
    local sm = valid(mesh) and try(function() return mesh.SkeletalMesh end)
    -- Meshes can arrive after their actor; don't cache a miss or call into a null engine object.
    if not valid(sm) then return nil end
    local nm = try(function() return sm:GetFName():ToString() end) or ""
    if nm == "" then nm = try(function() return sm:GetFullName() end) or "" end
    if nm == "" then return nil end
    if nm:find("AirborneSquad", 1, true) or nm:find("CH_P_EVE_01_Body", 1, true) then
      if not angelKind then for _, x in ipairs(kinds()) do if x.alias == "N_AirborneSquad" then angelKind = x break end end end
      k = angelKind
      if k then log(string.format("following %s %x (%s): Eve-bodied story angel, cut as %s", k.alias, a, c.cls, k.alias)) end
    end
  end
  angelCache[a] = k or false
  return k
end

local function spcfg() return ctx.tune.spawner or {} end
-- every CharacterTable row (roster.lua, generated from the base game's table dump): spawnable by alias or ID.
-- No Blueprint: adopted by proximity, tracked and hostility-patched, but never cut
local rosterKinds, rosterByAlias = nil, nil
local function load_roster()
  if rosterKinds then return rosterKinds, rosterByAlias end
  rosterKinds, rosterByAlias = {}, {}
  local known = {}
  for _, k in ipairs(kinds()) do known[k.alias] = true end
  local ok, r = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/roster.lua")
  if ok and type(r) == "table" then
    for _, e in ipairs(r) do
      if e.alias and e.id and e.id > 0 and not known[e.alias] then
        known[e.alias] = true
        local k = { alias = e.alias, label = e.alias:gsub("_", " "), id = e.id,
          tribe = (e.tribe ~= "" and e.tribe) or "Other", roster = true }
        rosterKinds[#rosterKinds + 1] = k
        rosterByAlias[e.alias] = k
      end
    end
  end
  return rosterKinds, rosterByAlias
end
function M.roster() return load_roster() end
-- the Spawner tab's foldable groups (F3 → Spawner, the play-as menu's character list): the curated NPCs by name,
-- then every other table row by tribe
function M.pick_groups()
  local naytiba, angels, bosses = {}, {}, {}
  for _, k in ipairs(kinds()) do
    local m = { alias = k.alias, label = k.label or k.alias }
    if k.row then bosses[#bosses + 1] = m
    elseif k.alias == "N_AirborneSquad" then angels[#angels + 1] = m
    else naytiba[#naytiba + 1] = m end
  end
  local groups = {
    { id = "naytiba", label = "Naytiba", members = naytiba,
      help = "The curated monsters: skulls, crickets, gorillas, the lab mutant, the statues, the lurkers and more (cut as Eve is)." },
    { id = "angels", label = "Angels", members = angels,
      help = "The Airborne Squad: passive NPCs, hostile to nothing by default." },
    { id = "bosses", label = "Bosses", members = bosses,
      help = "Humanoid bosses, spawned and killed like any enemy (Boss Spawning on)." },
  }
  -- the rest of the table by tribe (tracked and hostile-patched, never cut: no Blueprint to follow)
  local byTribe, order = {}, {}
  for _, r in ipairs(load_roster()) do
    local t = r.tribe ~= "" and r.tribe or "Other"
    if not byTribe[t] then byTribe[t] = {}; order[#order + 1] = t end
    byTribe[t][#byTribe[t] + 1] = { alias = r.alias, label = r.label }
  end
  for _, t in ipairs(order) do
    groups[#groups + 1] = { id = "tribe_" .. t, label = t:gsub("_", " "), members = byTribe[t],
      help = "Every CharacterTable row of this tribe (spawned as-is: tracked, never cut)." }
  end
  groups[#groups + 1] = { id = "custom", label = "Custom", members = {},
    help = "Any NPC in the game by its CharacterTable ID." }
  return groups
end
-- Album assets use full object paths; some are only available after the game loads them.
local PORTRAITS = {
  B_Tachy = "/Game/Art/UI/Texture/Album/NPC/image/CH_NPC_TachyNPC.CH_NPC_TachyNPC",
  B_TachyNPC = "/Game/Art/UI/Texture/Album/NPC/image/CH_NPC_TachyNPC.CH_NPC_TachyNPC",
  B_Raven = "/Game/Art/UI/Texture/Album/NPC/image/CH_NPC_Raven.CH_NPC_Raven",
  B_Scarlet = "/Game/DLC_2/Art/UI/Texture/Album/NPC/image/CH_NPC_Scarlet.CH_NPC_Scarlet",
  B_RoyalGuard = "/Game/Art/UI/Texture/Album/NPC/image/CH_NPC_Rael.CH_NPC_Rael",
}
-- an NPC's avatar candidates (the play-as menu's pictures): its own, the album's NPC and Native
-- pictures by name. The menu loads the first one the game has, else shows none (memory-only lookups)
function M.portrait_paths(alias)
  local out = {}
  local k = M.pick_kind(alias)
  if k and k.portrait then out[#out + 1] = k.portrait end
  for _, p in ipairs(PORTRAITS[alias] and { PORTRAITS[alias] } or {}) do out[#out + 1] = p end
  local name = k and k.bp and (k.bp:match("/(CH_M_NA_%d+)[^/]*_Blue[Pp]rint$") or k.bp:match("/(CH_M_NA_%d+)[^/]*_BP$"))
  local variant = k and k.bp and k.bp:match("_Type_([BC])_Blueprint$")
  if name and variant and name ~= "CH_M_NA_45" then name = name .. "_Type_" .. variant end
  if name then out[#out + 1] = "/Game/Art/UI/Texture/Album/Native/image/" .. name .. "." .. name end
  local base = k and k.bp and k.bp:match("([^/]+)$")
  if base then base = base:gsub("_Blueprint$", "") end
  if base and base ~= "" then
    out[#out + 1] = "/Game/Art/UI/Texture/Album/NPC/image/" .. base .. "." .. base
  end
  if not name and alias then
    out[#out + 1] = "/Game/Art/UI/Texture/Album/Native/image/" .. alias .. "." .. alias
    out[#out + 1] = "/Game/Art/UI/Texture/Album/NPC/image/" .. alias .. "." .. alias
  end
  return out
end
function M.portrait(alias)
  return M.portrait_paths(alias)[1]
end
-- the Spawner tab's pick (F3 → Spawner, the play-as mod's character list): every known NPC by name, then the
-- custom CharacterTable ID (spawner.id: any NPC in the game)
function M.pick_list()
  local v = {}
  for _, k in ipairs(kinds()) do v[#v + 1] = k.alias end
  v[#v + 1] = "custom"
  return v
end
function M.pick_names()
  local n = {}
  for _, k in ipairs(kinds()) do n[#n + 1] = k.label or k.alias end
  n[#n + 1] = "Custom ID..."
  return n
end
function M.pick_kind(pick)
  if pick == "custom" then
    local id = math.floor(tonumber(spcfg().id) or 0)
    if id > 0 then return { alias = "ID_" .. id, label = "Custom NPC " .. id, id = id, custom = true } end
    return nil
  end
  for _, k in ipairs(kinds()) do if k.alias == pick then return k end end
  local _, byAlias = load_roster()
  return byAlias[pick]
end
-- a freshly spawned actor of a class no kind names near a pending spawn request is it (a roster kind without
-- a Blueprint, or a custom ID: kind_of knows nothing about it). Never Eve herself standing by the spawn point
local function proximity_expect(c, selfAddr)
  for i = #expect, 1, -1 do
    local x = expect[i]
    if os.clock() - x.t > 10 then table.remove(expect, i)
    elseif not x.kind.bp then
      local a = c.addr or try(function() return c.obj:GetAddress() end)
      if a and a ~= selfAddr and not (x.before and x.before[a]) then
        local l = try(function() return vof(c.obj:K2_GetActorLocation()) end)
        if l and len(sub(l, x.at)) < 800 then return x.kind end
      end
    end
  end
  return nil
end

-- the spawner window's list (spawner.c reads it whenever it opens; the window shows the first 64)
local function write_list()
  local f = io.open(LIST, "w")
  if not f then return end
  local n = 0
  for i, k in ipairs(kinds()) do
    n = n + 1
    f:write(string.format("%s\t%d. %s\n", k.alias, i, k.label or k.alias))
  end
  for _, r in ipairs(load_roster()) do
    n = n + 1
    f:write(string.format("%s\t%d. %s\n", r.alias, n, r.alias:gsub("_", " ")))
  end
  f:close()
end

function M.init(c)
  ctx, try, valid = c, c.try, c.valid
  write_list()
end
function M.reload() allFor, byClassFor = nil, nil; write_list() end

-- ---- spawning ----
local function controller(pawn)
  local pc = try(function() return pawn.Controller end)
  if valid(pc) then return pc end
  pc = try(function() return FindFirstOf("SBNetworkPlayerController") end)
  return valid(pc) and pc or nil
end

-- count of kind k, in a row across in front of her, facing her
local function spawn(pawn, k, count)
  local pc = controller(pawn)
  if not pc then log("spawn: no player controller"); return false end
  local at = try(function() return vof(pawn:K2_GetActorLocation()) end)
  local rot = try(function() return pawn:GetControlRotation() end)
  if not at then log("spawn: no Eve location"); return false end
  local yaw = math.rad(rot and rot.Yaw or 0)
  local fwd, right = vec(math.cos(yaw), math.sin(yaw), 0), vec(-math.sin(yaw), math.cos(yaw), 0)
  local d, spread = cfg().spawnDistance or 450, cfg().spawnSpread or 160
  -- a Bosses-group boss: its CharacterTable row made mortal first (bosses.lua forced: the Spawner is the
  -- boss spawner now, no toggle needed), and set further off (they lunge)
  if k.row and not (ctx.bosses and ctx.bosses.prepare) then
    log("spawn " .. tostring(k.alias) .. ": not spawned: boss preparation unavailable"); return false
  end
  if k.row then
    local why = ctx.bosses.prepare(k, true)
    if why then log(string.format("spawn %s: not spawned: %s", k.alias, why)); return false end
    d = k.distance or d
  end
  -- A proximity-only request must not claim a character already present at the spawn point.
  local before
  if not k.bp then
    before = {}
    for _, c in ipairs(ctx.live_chars()) do if c.addr then before[c.addr] = true end end
  end
  local ok_n = 0
  for i = 1, count do
    local off = (i - (count + 1) / 2) * spread
    local p = vec(at.X + fwd.X * d + right.X * off, at.Y + fwd.Y * d + right.Y * off, at.Z + (cfg().spawnLift or 30))
    local r = { Pitch = 0, Yaw = math.deg(yaw) + 180, Roll = 0 }
    local ok, err = pcall(function()
      return pc:ServerRequest_CreateActor(k.id, p, r, false, true, 0, 0, 0, FName("None"), false)
    end)
    if ok and err ~= false then
      ok_n = ok_n + 1
      expect[#expect + 1] = { kind = k, at = p, t = os.clock(), before = before }
    else
      log(string.format("spawn %s: ServerRequest_CreateActor failed: %s", k.alias, tostring(err)))
    end
  end
  log(string.format("spawn: asked for %d %s (CharacterTable %d) %.0f cm in front of her: %d sent", count, k.alias, k.id, d, ok_n))
  return ok_n > 0
end

-- every enemy spawned here goes (its gore first, while it is still whole to the game)
local function remove_all()
  local nr = 0
  for a in pairs(mine) do
    local e = known[a]
    local obj = e and e.obj
    if e and e.kind.row and ctx.bosses then ctx.bosses.gone(a, e) end
    if e and e.cut and ctx.gore then ctx.gore.enemy_gone(a, e.mesh, nil) end
    if e and restore_boss_weapons then restore_boss_weapons(e, true) end
    known[a] = nil
    if obj and valid(obj) and try(function() return obj.bActorIsBeingDestroyed end) == false then
      if try(function() obj:K2_DestroyActor(); return true end) then nr = nr + 1 end
    end
  end
  mine, expect = {}, {}
  log(string.format("removed %d spawned enemies", nr))
end

function M.spawn_pick(pawn)
  local g = ctx.tune.spawner or {}
  local k = M.pick_kind(g.pick)
  if not k then
    log(g.pick == "custom" and "spawn: Custom ID picked but spawner.id is 0 (F3 → Spawner: set the CharacterTable ID)"
      or string.format("spawn: no NPC %s in the kinds (F3 → Spawner)", tostring(g.pick)))
    return
  end
  spawn(pawn, k, math.max(1, math.min(9, tonumber(g.count) or 1)))
end
function M.next_pick()
  local g = ctx.tune.spawner or {}
  -- within its own group (the full roster made one long Insert cycle useless)
  local members = nil
  for _, gr in ipairs(M.pick_groups()) do
    for _, m in ipairs(gr.members) do if m.alias == g.pick then members = gr.members break end end
    if members then break end
  end
  local v = {}
  if members then for _, m in ipairs(members) do v[#v + 1] = m.alias end
  else v = M.pick_list() end
  if #v == 0 then return end
  local k = 1
  for i, x in ipairs(v) do if x == g.pick then k = i end end
  k = k % #v + 1
  g.pick = v[k]
  if not ctx.tune.spawner then ctx.tune.spawner = g end
  local kn = M.pick_kind(v[k])
  log(string.format("Insert: F5 now spawns %d of %d, %s (%s)", k, #v, kn and (kn.label or kn.alias) or v[k], v[k]))
end
function M.toggle_window()
  local f = io.open(CMD, "w")
  if f then f:write("toggle"); f:close() end
  write_list()
  log("Home: spawner window toggled (sbslice.dll shows it)")
end

-- while the spawner window shows, the game lets go of the mouse (the cursor shown, input to game and UI, not locked):
-- it kept the cursor captured, and nothing in the window could be clicked (twenty-third playtest)
local function free_mouse(pawn, on)
  local pc = controller(pawn)
  if not pc then return end
  local lib = try(function() return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end)
  try(function() pc.bShowMouseCursor = on end)
  local ok = valid(lib) and try(function()
    if on then lib:SetInputMode_GameAndUIEx(pc, nil, 0, false) else lib:SetInputMode_GameOnly(pc) end
    return true
  end)
  freed = on
  log(string.format("spawner window %s: mouse %s%s", on and "open" or "closed", on and "freed" or "back to the game", ok and "" or " (input mode not set)"))
end
local function read_state(pawn)
  local f = io.open(STATE, "r")
  if not f then return end
  local on = (f:read("a") or ""):sub(1, 1) == "1"
  f:close()
  if on ~= freed then free_mouse(pawn, on) end
end

local function read_req(pawn)
  local f = io.open(REQ, "r")
  if not f then return end
  local s = f:read("a") or ""
  f:close()
  os.remove(REQ)
  local what, alias, count = s:match("^(%a+)\t?([^\t]*)\t?(%d*)")
  if what == "clear" then remove_all(); return end
  if what == "kill" then M.kill_nearest(pawn); return end
  if what ~= "spawn" then log("spawner: unknown request " .. s); return end
  for _, k in ipairs(kinds()) do
    if k.alias == alias then spawn(pawn, k, math.max(1, math.min(9, tonumber(count) or 1))); return end
  end
  log("spawner: no kind " .. tostring(alias))
end

-- ---- Eve's swing ----
-- her right hand, sampled every tick; a kill's blade is the fastest stretch of the swingWindow seconds up to the hit
-- (since..upto; the last swingWindow seconds when not given), its plane the arc through the samples round it (else
-- the swing and her forward)
local function track_hand(pawn, mesh)
  local now = os.clock()
  local p = bone_loc(mesh, "Bip001-R-Hand")
  if p then hand[#hand + 1] = { t = now, p = p } end
  local keep = math.max(cfg().swingWindow or 0.5, HAND_S)
  while #hand > 0 and now - hand[1].t > keep do table.remove(hand, 1) end
end
local function her_swing(pawn, since, upto)
  since = since or os.clock() - (cfg().swingWindow or 0.5)
  local best
  for i = 2, #hand do
    local dt = hand[i].t - hand[i - 1].t
    if dt > 1e-3 and hand[i].t > since and (not upto or hand[i - 1].t <= upto) then
      local v = len(sub(hand[i].p, hand[i - 1].p)) / dt
      if not best or v > best.v then best = { v = v, i = i } end
    end
  end
  if not best or best.v < (cfg().swingMinSpeed or 250) then return nil end
  local i = best.i
  local p0, p1 = hand[i - 1].p, hand[i].p
  local dir = unit(sub(p1, p0))
  local rot = try(function() return pawn:GetControlRotation() end)
  local yaw = math.rad(rot and rot.Yaw or 0)
  local fwd = vec(math.cos(yaw), math.sin(yaw), 0)
  local nrm, how
  local pa, pc = hand[i - 2] and hand[i - 2].p, hand[i + 1] and hand[i + 1].p
  for _, pr in ipairs({ { pa and sub(p0, pa), sub(p1, p0) }, { sub(p1, p0), pc and sub(pc, p1) } }) do
    if not nrm and pr[1] and pr[2] then
      local c = cross(pr[1], pr[2])
      if len(c) > 0.2 * len(pr[1]) * len(pr[2]) then nrm, how = unit(c), "her arc" end
    end
  end
  if not nrm and dir then
    local c = cross(dir, fwd)
    if len(c) > 0.3 then nrm, how = unit(c), "her swing x forward" end
  end
  if not (dir and nrm) then return nil end
  return { dir = dir, n = nrm, how = how, at = p1, fwd = fwd, speed = best.v, t = hand[i].t }
end

-- where a blow lands on an enemy: the parts it is struck on, as for her (main.lua's SWING_AT)
local PARTS = {
  { "Bip001-Spine1", 3 }, { "Bip001-Spine2", 3 }, { "Bip001-Neck", 2 }, { "Bip001-Spine", 1 },
  { "Bip001-L-UpperArm", 1.5, "Bip001-L-Forearm" }, { "Bip001-R-UpperArm", 1.5, "Bip001-R-Forearm" },
  { "Bip001-L-Forearm", 0.75, "Bip001-L-Hand" }, { "Bip001-R-Forearm", 0.75, "Bip001-R-Hand" },
  { "Bip001-L-Thigh", 0.8, "Bip001-L-Calf" }, { "Bip001-R-Thigh", 0.8, "Bip001-R-Calf" },
  { "Bip001-L-Calf", 0.4, "Bip001-L-Foot" }, { "Bip001-R-Calf", 0.4, "Bip001-R-Foot" },
}
local function part_at(mesh, e)
  local a = bone_loc(mesh, e[1])
  if not a or not e[3] then return a end
  local b = bone_loc(mesh, e[3])
  return b and vec(a.X + 0.4 * (b.X - a.X), a.Y + 0.4 * (b.Y - a.Y), a.Z + 0.4 * (b.Z - a.Z)) or a
end

-- where the body is struck near p: p itself when one of its parts is within ONTO cm, else the nearest part (a hit's
-- location the game reported off the body, above its head: the blade's plane through it missed it, playtest)
local ONTO = 30
local ONTO_ALSO = { { "Bip001-Head" }, { "Bip001-Pelvis" } }
local function onto(mesh, p)
  local bd, bl, bb
  for _, x in ipairs(PARTS) do
    local l = part_at(mesh, x)
    local d = l and len(sub(l, p))
    if d and (not bd or d < bd) then bd, bl, bb = d, l, x[1] end
  end
  -- (the head and the hips are struck too, though no blade is aimed at them as parts)
  for _, x in ipairs(ONTO_ALSO) do
    local l = bone_loc(mesh, x[1])
    local d = l and len(sub(l, p))
    if d and (not bd or d < bd) then bd, bl, bb = d, l, nil end
  end
  if not bd or bd <= ONTO then return p, nil end
  return bl, bb
end

-- the killing blow on enemy e: her swing up to the hit, its plane through where its mesh was hit (else the part
-- nearest the plane and her hand, moved onto it), else a made-up blade from her towards it. The hit is moved on with
-- the body since (its pelvis then and now): the ragdoll starts a while after the blow
local function kill_blow(pawn, e)
  local g = cfg()
  local hit = e.hit and os.clock() - e.hit.t < (g.hitWindow or 1.0) and e.hit or nil
  local w = g.swingWindow or 0.5
  local sw = math.random() <= (g.bladeChance or 0.85)
    and (hit and her_swing(pawn, hit.t - w, hit.t + 0.1) or her_swing(pawn)) or nil
  local her = try(function() return vof(pawn:K2_GetActorLocation()) end)
  local pel = bone_loc(e.mesh, "Bip001-Pelvis")
  local push = hit and hit.push or (her and pel and unit(vec(pel.X - her.X, pel.Y - her.Y, 0)))
  local hloc, hbone = hit and hit.loc, hit and hit.bone
  if hloc then
    if hit.pel and pel then hloc = vec(hloc.X + pel.X - hit.pel.X, hloc.Y + pel.Y - hit.pel.Y, hloc.Z + pel.Z - hit.pel.Z) end
    local b
    hloc, b = onto(e.mesh, hloc)
    hbone = b or hbone
  end
  if sw then
    local loc, bone, off = hloc, hbone, nil
    if not loc then
      local bd
      for _, p in ipairs(PARTS) do
        local l = part_at(e.mesh, p)
        if l then
          local d = math.abs(dot(sub(l, sw.at), sw.n))
          local sc = d + 0.3 * len(sub(l, sw.at)) - p[2]
          if not bd or sc < bd then bd, loc, bone, off = sc, l, p[1], d end
        end
      end
    end
    if loc then
      -- the plane through the point it struck, keeping its angle
      local k = dot(sub(loc, sw.at), sw.n)
      return { loc = loc, dir = sw.dir, fwd = sw.fwd, n = sw.n, how = sw.how, push = push or sw.dir, bone = bone,
        src = string.format("%s at %.0f cm/s", sw.how, sw.speed), off = math.abs(k) }
    end
  end
  -- no swing: a blade from her side, level, slanted or down across it, through a part of it
  if not push then return { loc = hloc, push = nil, src = "none" } end
  local side = math.random() < 0.5 and -1 or 1
  local ang = math.rad(({ 0, 20, 45, 45, 70, 90 })[math.random(6)])
  local dir = vec(-push.Y * side * math.cos(ang), push.X * side * math.cos(ang), -math.sin(ang))
  local loc, bone = hloc, hbone
  if not loc then
    local sum = 0
    for _, p in ipairs(PARTS) do sum = sum + p[2] end
    local r = math.random() * sum
    for _, p in ipairs(PARTS) do
      r = r - p[2]
      if r <= 0 then loc, bone = part_at(e.mesh, p), p[1]; break end
    end
  end
  return { loc = loc, dir = dir, fwd = push, push = push, bone = bone, attack_dir = 0, src = "made up" }
end

local function roll_kind()
  local o = cfg().odds or {}
  local list = { { "limb", o.limb or 0.55 }, { "head", o.head or 0.3 }, { "torso", o.torso or 0.15 } }
  local sum = 0
  for _, x in ipairs(list) do sum = sum + x[2] end
  local r = math.random() * sum
  for _, x in ipairs(list) do r = r - x[2]; if r <= 0 then return x[1] end end
  return "limb"
end

-- ---- following them ----
local function poll_hit(e)
  local m = e.mesh
  local f = try(function() return vof(m.PhysicalHitForceVector) end)
  local at = try(function() return vof(m.PhysicalHitForceLocation) end)
  local sp = try(function() return vof(m.VertexShakeInfo.ShakeHitPosition) end)
  local key = string.format("%s %s %s", v3(f), v3(at), v3(sp))
  if e.key == nil then e.key = key; return end
  if key == e.key then return end
  e.key = key
  local pel = bone_loc(m, "Bip001-Pelvis")
  local function near(p) return p and pel and len(sub(p, pel)) < 150 end
  e.hit = { t = os.clock(), loc = (near(at) and at) or (near(sp) and sp) or nil, push = f and len(f) > 1e-3 and unit(f) or nil,
    bone = try(function() return m.PhysicalHitForceTargetBone:ToString() end), pel = pel }
end

local function simulating(e) return try(function() return e.mesh:IsSimulatingPhysics(FN["Bip001-Pelvis"]) end) == true end
local function dying(o) return try(function() return o.bActorIsBeingDestroyed end) ~= false end

-- what a corpse's slots show: a material's name, a dynamic instance's parent's. The game's despawn show swaps them
-- for MI_DeadMaterial_* (SBShowMaterialChangeKey) and dissolves the body: the caps and bleeds go then, not when the
-- actor is hidden ~15 s later (they hung in the air where the corpse had dissolved)
local function looks(mesh)
  local out = {}
  local nm = try(function() return mesh:GetNumMaterials() end) or 0
  for i = 0, math.min(nm, 8) - 1 do
    out[#out + 1] = try(function()
      local m = mesh:GetMaterial(i)
      local p = m.Parent
      local name = m:GetFName():ToString()
      if name:find("MaterialInstanceDynamic") and p and p:IsValid() then name = p:GetFName():ToString() end
      return name
    end) or "?"
  end
  return table.concat(out, ",")
end
local function dissolving(e)
  local now = looks(e.mesh)
  return now ~= e.looks and (now:find("DeadMaterial") or now:find("Dissolve")) ~= nil, now
end
local function hidden(e)
  return try(function() return e.obj.bHidden end) == true or try(function() return e.obj.bCharacterHiddenInGame end) == true
    or try(function() return e.mesh:IsVisible() end) == false
end

M.BOSS_FAR = 6000
-- its weapon on a socket whose bone its ragdoll doesn't move: Raven's sword sits on SC_Weapon (bone
-- SC_WeaponConstraint, under her right hand) and hung in the air where her hand had been once she went limp
-- (playtest). Put on the nearest bone up from there that simulates, on the ragdolled mesh, where it is now
local WEAPON_CLASSES = { "/Script/Engine.SkeletalMeshComponent", "/Script/Engine.StaticMeshComponent" }
local function weapons_on_ragdoll(e)
  local o, mesh = e.obj, e.mesh
  local out = {}
  for _, cp in ipairs(WEAPON_CLASSES) do
    local cls = try(function() return StaticFindObject(cp) end)
    for _, c in ipairs(valid(cls) and try(function() return o:K2_GetComponentsByClass(cls) end) or {}) do
      local sock = valid(c) and addr(c) ~= addr(mesh) and try(function() return c.AttachSocketName:ToString() end)
      local nm = sock and (try(function() return (c.SkeletalMesh or c.StaticMesh):GetFName():ToString() end) or "")
      if sock and sock ~= "None" and (sock:find("Weapon") or nm:find("Weapon")) then
        local par = try(function() return c:GetAttachParent() end)
        local bone = valid(par) and try(function() return par:GetSocketBoneName(FName(sock)):ToString() end)
        local onmesh = valid(par) and addr(par) == addr(mesh)
        local b, guard = bone, 0
        while b and b ~= "None" and guard < 16 and try(function() return mesh:IsSimulatingPhysics(FName(b)) end) ~= true do
          b = try(function() return mesh:GetParentBone(FName(b)):ToString() end)
          guard = guard + 1
        end
        if not (b and b ~= "None") then
          out[#out + 1] = string.format("%s on %s (%s): no simulated bone above it", nm, sock, tostring(bone))
        elseif b ~= bone or not onmesh then
          local ok = try(function() c:K2_AttachToComponent(mesh, FName(b), 1, 1, 1, false); return true end)
          out[#out + 1] = string.format("%s on %s (%s%s) -> %s%s", nm, sock, tostring(bone), onmesh and "" or ", another mesh", b, ok and "" or " FAILED")
        end
      end
    end
  end
  if #out > 0 then log(string.format("%s: its weapon onto its ragdoll: %s", e.kind.alias, table.concat(out, "; "))) end
end
M._weapons_on_ragdoll = weapons_on_ragdoll

-- A spawned boss's visible weapons need their own rigid bodies. Some follow the boss's master pose, so simply
-- reattaching their component to a hand does not release the pose or let the sword fall. Remember the original
-- attachment for pooled actors; never touch objects from a vanished/destroyed world.
restore_boss_weapons = function(e, touch)
  for _, d in ipairs(e.weaponDrops or {}) do
    if touch and valid(d.comp) and valid(d.parent) then
      try(function()
        d.comp:K2_AttachToComponent(d.parent, d.socket or FName("None"), 2, 2, 2, false)
        if d.loc and d.rot then d.comp:K2_SetRelativeLocationAndRotation(d.loc, d.rot, false, {}, true) end
        if d.scale then d.comp:SetRelativeScale3D(d.scale) end
        if valid(d.master) then d.comp:SetMasterPoseComponent(d.master, true) end
      end)
    end
    if touch and valid(d.box) then try(function() d.box:K2_DestroyComponent(d.box) end) end
  end
  e.weaponDrops = nil
end
local function drop_boss_weapons(e)
  local o, mesh = e.obj, e.mesh
  local cls = try(function() return StaticFindObject("/Script/Engine.BoxComponent") end)
  if not valid(cls) then log(e.kind.alias .. ": weapon drop unavailable: no BoxComponent class"); return end
  local candidates, seen = {}, {}
  local function add(c)
    local a = valid(c) and addr(c)
    if a and not seen[a] and a ~= addr(mesh) and try(function() return c:IsVisible() end) == true then
      seen[a] = true; candidates[#candidates + 1] = c
    end
  end
  try(function() o.MeshInfoList:ForEach(function(_, item)
    local i = item:get()
    if i.MeshSlot >= 5 and i.MeshSlot <= 8 then add(i.MeshComponent) end
  end) end)
  for _, cp in ipairs(WEAPON_CLASSES) do
    local c = try(function() return StaticFindObject(cp) end)
    for _, w in ipairs(valid(c) and try(function() return o:K2_GetComponentsByClass(c) end) or {}) do
      local nm = try(function() return (w.SkeletalMesh or w.StaticMesh):GetFName():ToString() end) or ""
      local socket = try(function() return w:GetAttachSocketName():ToString() end) or ""
      if nm:lower():find("weapon", 1, true) or socket:lower():find("weapon", 1, true) then add(w) end
    end
  end
  local id = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = vec(0, 0, 0), Scale3D = vec(1, 1, 1) }
  for _, w in ipairs(candidates) do
    local bounds = try(function() return w.SkeletalMesh:GetImportedBounds() end)
      or try(function() return w.StaticMesh:GetBounds() end)
    local b = bounds and try(function() return { o = vof(bounds.Origin), e = vof(bounds.BoxExtent) } end)
    local parent = try(function() return w:GetAttachParent() end)
    local pos = try(function() return w:K2_GetComponentLocation() end)
    local rot = try(function() return w:K2_GetComponentRotation() end)
    if b and b.o and b.e and valid(parent) and pos and rot then
      local box = try(function() return o:AddComponentByClass(cls, true, id, false) end)
      if valid(box) then
        local d = { comp = w, box = box, parent = parent, socket = try(function() return w:GetAttachSocketName() end),
          loc = try(function() return vof(w.RelativeLocation) end),
          rot = try(function() local r = w.RelativeRotation; return { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end),
          scale = try(function() return vof(w.RelativeScale3D) end),
          master = try(function() return w.MasterPoseComponent:Get() end) }
        e.weaponDrops = e.weaponDrops or {}; e.weaponDrops[#e.weaponDrops + 1] = d
        local ok = try(function()
          local f, r, u = w:GetForwardVector(), w:GetRightVector(), w:GetUpVector()
          local at = vec(pos.X + f.X*b.o.X + r.X*b.o.Y + u.X*b.o.Z,
            pos.Y + f.Y*b.o.X + r.Y*b.o.Y + u.Y*b.o.Z, pos.Z + f.Z*b.o.X + r.Z*b.o.Y + u.Z*b.o.Z)
          box:K2_SetWorldLocationAndRotation(at, rot, false, {}, true)
          local ex = { math.max(1.5, math.min(b.e.X, 60)), math.max(1.5, math.min(b.e.Y, 60)), math.max(1.5, math.min(b.e.Z, 60)) }
          local thin = ex[1] <= ex[2] and (ex[1] <= ex[3] and 1 or 3) or (ex[2] <= ex[3] and 2 or 3)
          ex[thin] = 0.75
          box:SetBoxExtent(vec(ex[1], ex[2], ex[3]), false)
          box:SetHiddenInGame(true, false)
          box:SetCollisionProfileName(FName("PhysicsActor"), true)
          box:SetCollisionResponseToChannel(2, 0)
          box:SetCollisionEnabled(3)
          box:SetSimulatePhysics(true)
          box:SetMassOverrideInKg(FName("None"), 1.5, true)
          if valid(d.master) then w:SetMasterPoseComponent(nil, true) end
          if w:K2_AttachToComponent(box, FName("None"), 1, 1, 1, false) == false then error("weapon attach failed") end
          return true
        end)
        if not ok then
          restore_boss_weapons({ weaponDrops = { d } }, true)
          table.remove(e.weaponDrops)
          log(e.kind.alias .. ": weapon drop failed; attachment restored")
        end
      end
    else
      log(e.kind.alias .. ": weapon drop skipped: missing bounds or attachment")
    end
  end
  if e.weaponDrops and #e.weaponDrops > 0 then log(string.format("%s: dropped %d weapon(s)", e.kind.alias, #e.weaponDrops))
  elseif #candidates == 0 then log(e.kind.alias .. ": no visible weapon component found to drop") end
end
M._drop_boss_weapons, M._restore_boss_weapons = drop_boss_weapons, restore_boss_weapons
local function match_spawn(o, a, k)
  local miss
  for i = #expect, 1, -1 do
    local x = expect[i]
    if os.clock() - x.t > 10 then table.remove(expect, i)
    elseif x.kind.alias == k.alias then
      local l = try(function() return vof(o:K2_GetActorLocation()) end)
      local d = l and len(sub(l, x.at))
      if d and d < (k.row and M.BOSS_FAR or 800) then mine[a] = true; table.remove(expect, i); break end
      miss = d
    end
  end
  return miss
end

local function adopt(o, a, cls, k, cuts)
  local mesh = try(function() return o.Mesh end)
  if not valid(mesh) then return nil end
  local e = { obj = o, mesh = mesh, cls = cls, kind = k, dead = false, cuts = 0, hits = 0 }
  if cuts and cfg().nativeSlice == false then
    local was = try(function() return o.bUseSliceSkeletalMesh end)
    if was then try(function() o.bUseSliceSkeletalMesh = false end) end
    e.slice = was
  end
  known[a] = e
  -- one the spawner asked for: it can be removed again. A boss of the kind asked for in the last 10 s is it wherever it
  -- turns up (BOSS_FAR): Tachy comes in from off where she was asked for, wasn't taken for one spawned here, and
  -- Passive Bosses never touched her (she attacked, playtest). Told by alias: a setting changed in the menu that
  -- spawned it makes the kinds over (Scarlet, Tachy and the Royal Guard weren't taken for hers, playtest)
  local miss = match_spawn(o, a, k)
  ;((mine[a] or miss or k.row) and log or vlog)(string.format("following %s %x (%s)%s%s%s", k.alias, a, cls,
    mine[a] and ", spawned here" or "", miss and not mine[a] and string.format(", not the one asked for (%.0f cm off)", miss) or "",
    e.slice ~= nil and string.format(", its own slicer %s -> off", tostring(e.slice)) or ""))
  if k.row and ctx.bosses then ctx.bosses.adopted(a, e, mine[a] == true) end
  return e
end

-- how: nil (the corpse is still there), "destroyed" (being destroyed) or "vanished" (see gore.enemy_gone)
local function gone(a, e, how, why)
  known[a] = nil
  angelCache[a] = nil
  if e.kind.row and ctx.bosses then ctx.bosses.gone(a, e) end
  if e.cut and ctx.gore then try(function() ctx.gore.enemy_gone(a, e.mesh, how) end) end
  restore_boss_weapons(e, how == nil)
  if e.cut then log(string.format("%s %x %s: its gore removed", e.kind.alias, a, why)) end
end

-- buried: dead angels kept on the ground (tune.enemies.keepAngelBodies): the N_AirborneSquad row's
-- DespawnTimeAfterDeath held long while one lies, put back exactly after. Kept cut angels don't count at
-- maxCorpses (they're meant to stay; live ones may pinch near their helpers meanwhile).
local function is_angel(kind) return kind and kind.alias == "N_AirborneSquad" end
local angelKept, angelRetry = nil, 0
local function keep_secs() return math.max(tonumber(cfg().keepAngelFor) or 3600, 60) end
local function angel_keep_tick()
  local want = cfg().keepAngelBodies == true
  local n = 0
  if want then for _, e in pairs(known) do if e.dead and is_angel(e.kind) then n = n + 1 end end end
  if n > 0 and not angelKept and os.clock() >= angelRetry then
    local err
    if ctx.bosses and ctx.bosses.keep_despawn then err = ctx.bosses.keep_despawn("N_AirborneSquad", keep_secs())
    else err = "bosses unavailable" end
    if err then angelRetry = os.clock() + 5; log(string.format("keep angel bodies: not held (%s)", tostring(err)))
    else angelKept = "N_AirborneSquad" end
  elseif n == 0 and angelKept and os.clock() >= angelRetry then
    local err = ctx.bosses and ctx.bosses.unkeep_despawn and ctx.bosses.unkeep_despawn(angelKept, "no kept bodies left")
      or (not (ctx.bosses and ctx.bosses.unkeep_despawn) and "bosses unavailable")
    if err then angelRetry = os.clock() + 5; log(string.format("keep angel bodies: restore pending (%s)", tostring(err)))
    else angelKept = nil end
  end
  return angelKept ~= nil
end

-- the kill: its cut, once gore is free (one cut opens at a time), tried for killWait seconds. What it waited for is
-- moved on with the body (its pelvis when it was asked and now): a corpse cut after another's flew on meanwhile, and
-- the blade's plane was left where it had been
local function try_cut(pawn, a, e)
  local r = e.want
  if not r then return end
  -- a kind with no Blueprint to follow (a roster row): tracked, never cut (its skeleton isn't Eve's Bip001)
  if not e.kind.bp then
    log(string.format("%s %x: left whole (no Blueprint to cut by)", e.kind.alias, a))
    e.want = nil
    return
  end
  if os.clock() - r.t > (cfg().killWait or 2.0) then
    log(string.format("%s %x: its cut never started (another kept gore busy)", e.kind.alias, a))
    e.want = nil
    return
  end
  if ctx.gore.busy() then return end
  -- (a kind whose waist can't be cut, Marionette's legs following the upper body: a rolled torso becomes a limb,
  -- and the blade carries the veto (M.blow's noTorso) so no waist cut lands through it either)
  if e.kind.noTorso then
    if r.kind == "torso" then r.kind = "limb" end
    if r.h then r.h.noTorso = true end
  end
  local pel = r.pel and bone_loc(e.mesh, "Bip001-Pelvis")
  if pel then
    local d = sub(pel, r.pel)
    local function mv(v) return v and vec(v.X + d.X, v.Y + d.Y, v.Z + d.Z) end
    r.loc = mv(r.loc)
    if r.h then r.h.loc = mv(r.h.loc) end
    r.pel = pel
  end
  -- basic enemies die silent: the cut's sound only plays for boss kinds (sandbox bosses keep it).
  -- naytibas get no metal bone either: Tachy's core is built for Eve and reads wrong on monsters (angels keep it)
  local mute = e.kind.row and nil or true
  local noCore = (e.kind.bp or ""):find("/Monster/", 1, true) and true or nil
  local got = ctx.gore.enemy_cut(a, e.obj, e.mesh, r.h, r.kind, e.kind.face, mute, noCore)
  -- (a corpse hit cuts along her blade or not at all: the fallback took the nearest limb wherever it was, the right
  -- arm off its flying chest for a swing through its cut-off left arm, playtest)
  if not got and not ctx.gore.busy() and r.kind ~= "mark" and not r.blade_only then
    -- nothing came off that way: the next kind (a limb, the head, across the waist), each once, near where it was
    -- struck and flying the way the blow went
    r.tried = r.tried or {}
    r.tried[r.kind] = true
    local h = { loc = r.loc, push = r.h and r.h.push }
    r.h = nil
    for _, k in ipairs({ "limb", "head", "torso" }) do
      if not r.tried[k] and not (k == "torso" and e.kind.noTorso) then r.kind = k; got = ctx.gore.enemy_cut(a, e.obj, e.mesh, h, k, e.kind.face, mute, noCore); if got then break end; r.tried[k] = true end
    end
  end
  if got or ctx.gore.busy() then
    e.cut = true
    e.cuts = e.cuts + 1
    if r.loc then ctx.gore.enemy_hit(a, e.obj, e.mesh, r.loc) end
    -- (its blood onto her when she's near: stains.lua)
    if ctx.stains and (r.loc or r.pel) then pcall(ctx.stains.splash, r.loc or r.pel, "cut") end
    log(string.format("%s %x: %s %s (%s)", e.kind.alias, a, r.what, tostring(got or r.kind), r.src))
  else
    log(string.format("%s %x: nothing came off (%s)", e.kind.alias, a, r.src))
  end
  e.want = nil
end

-- her swing passing through a corpse: cut again (corpseHits). Her sword reaches past her hand: a part within reach cm
-- of the swing's plane and blade cm of her hand is struck (her hand alone within 35 cm of a lying corpse's part
-- almost never was)
-- whether bone is off the corpse's body: it or a bone it hangs from was cut off (off: gore.enemy_off). Its parent
-- bones are asked once per enemy
local function cut_off(e, bone, off)
  e.parents = e.parents or {}
  for _ = 1, 24 do
    if not bone or bone == "None" then return false end
    if off[bone] then return true end
    local up = e.parents[bone]
    if up == nil then
      up = try(function() return e.mesh:GetParentBone(FName(bone)):ToString() end) or false
      e.parents[bone] = up
    end
    bone = up or nil
  end
  return false
end

local function corpse_hit(pawn, a, e)
  local ch = cfg().corpseHits or {}
  if ch.enabled == false or e.want or e.hits >= (ch.max or 4) or os.clock() - e.t < (ch.from or 0.6) then return end
  -- one cut a swing: an arc sampled every frame struck a corpse three times in a second, on top of the killing
  -- swing's own cuts (playtest), and none while one is still opening
  if os.clock() - (e.hitAt or -1e9) < (ch.gap or 0.5) then return end
  local _, opening = ctx.gore.enemy_cuts(a)
  if opening then return end
  local sw = her_swing(pawn, math.max(e.lastSwing or 0, e.t + (ch.from or 0.6), os.clock() - (cfg().swingWindow or 0.5)))
  if not sw then return end
  local reach, blade = ch.reach or 35, ch.blade or 130
  -- the parts still on its body: a cut-off arm lying by it was struck, and something else cut off (playtest)
  local gone = ctx.gore.enemy_off(a)
  local bd, bl, bb
  for _, p in ipairs(PARTS) do
    local l = not cut_off(e, p[1], gone) and part_at(e.mesh, p)
    if l then
      local off = math.abs(dot(sub(l, sw.at), sw.n))
      local d = len(sub(l, sw.at))
      if off < reach and d < blade and (not bd or off < bd) then bd, bl, bb = off, l, p[1] end
    end
  end
  if not bl then return end
  e.lastSwing, e.hitAt = sw.t, os.clock()
  e.hits = e.hits + 1
  local k = dot(sub(bl, sw.at), sw.n)
  local loc = vec(bl.X - k * sw.n.X, bl.Y - k * sw.n.Y, bl.Z - k * sw.n.Z)
  local cut = math.random() <= (ch.cutChance or 0.7)
  e.want = { t = os.clock(), kind = cut and "limb" or "mark", loc = loc, what = "corpse hit", blade_only = cut,
    pel = bone_loc(e.mesh, "Bip001-Pelvis"),
    src = string.format("%s at %.0f cm/s, %.0f cm off %s", sw.how, sw.speed, bd, bb),
    h = { loc = loc, dir = sw.dir, fwd = sw.fwd, n = cut and sw.n or nil, how = sw.how, push = sw.dir, bone = bb } }
end

-- the spawner's Kill nearest (and End): the followed character nearest her goes down as a ragdoll, which the
-- tick takes for its death (the cut follows). The Airborne Squad are passive NPCs the player's blows don't hurt
function M.kill_nearest(pawn)
  local her = try(function() return vof(pawn:K2_GetActorLocation()) end)
  if not her then return end
  local best, bd, ba
  for a, e in pairs(known) do
    local p = not e.dead and ctx.held(e.k) and valid(e.mesh) and bone_loc(e.mesh, "Bip001-Pelvis")
    local d = p and len(sub(p, her))
    if d and d < (cfg().reach or 2500) and (not bd or d < bd) then best, bd, ba = e, d, a end
  end
  if not best then log("kill: no live one followed near her"); return end
  M.kill_one(best, her, ba, string.format("%.0f cm off", bd))
end
-- one followed character down as a ragdoll, its AI stopped (the tick takes the ragdoll for its death; the cut follows).
-- her: where she is (it is knocked away from her)
function M.kill_one(e, her, ba, why)
  local ctl = try(function() return e.obj.Controller end)
  if valid(ctl) then
    try(function() ctl.BrainComponent:StopLogic("SBGore") end)
    try(function() ctl:StopMovement() end)
  end
  -- (its own tree, on the pawn: a boss's runs there, its controller's is none)
  try(function() e.obj.BrainComponent:StopLogic("SBGore") end)
  try(function() e.obj.CharacterMovement:DisableMovement() end)
  try(function() e.obj.CapsuleComponent:SetCollisionEnabled(0) end)
  try(function() e.mesh:SetCollisionProfileName(FName("Ragdoll"), true) end)
  try(function() e.mesh:SetAllBodiesSimulatePhysics(true) end)
  try(function() e.mesh:WakeAllRigidBodies() end)
  -- knocked away from her
  local p = bone_loc(e.mesh, "Bip001-Spine2")
  local d = p and her and unit(vec(p.X - her.X, p.Y - her.Y, 0))
  if d then try(function() e.mesh:AddImpulseToAllBodiesBelow(vec(d.X * 350, d.Y * 350, 120), FName("Bip001-Pelvis"), true, true) end) end
  log(string.format("kill: %s %x, %s, ragdolled", e.kind.alias, ba or 0, why or ""))
end

-- Enemies attack her while she is knocked down (tune.enemies.attackDown): the game's enemy behaviour trees hold the
-- attack while the target has a knockdown effect (an SbCheckActorEffect decorator on the target: her own knockdowns
-- and tumbles, the shared Getup, FastGetup, Down, DownFace*; about 100 of the 149 trees). Those names are swapped for
-- one no effect has, in every such decorator loaded (the trees' nodes are shared by every enemy running them), and
-- put back when it is turned off. The monsters' own KnockDownForward / Backward, the revival item's and the QTE's
-- are left alone. Trees load with their levels: all of them are looked for once (FindAllOf, 50-90 ms: every 3 s it
-- was a stutter of its own, playtest), then each new one is caught as it is made and swapped a second later, once
-- its asset's names are in.
-- Off, with tune.holdDown (she lies in the data mod's Down_Eve, a name no tree knows), the checks listing Down get
-- Down_Eve in place of KnockDownForward (a monster's own, never on her), so they wait through it as through Down.
-- The 11 lone Down checks (EffectAlias, a few bosses: Juggernaut, Scarlet, Tachy, Sawshark) are left as they are
local DOWN = { Getup = true, FastGetup = true, Down = true, Down_Eve = true, DownFaceUp = true, DownFaceUp_E = true,
  DownFaceDown = true, DownFaceDown_E = true, KnockDownForward_Eve = true, KnockDownBackward_Eve = true,
  KnockDownForwardTumbling_Eve = true, KnockDownBackwardTumbling_Eve = true, KnockDownForwardTumblingReady_Eve = true,
  KnockDownBackwardTumblingReady_Eve = true }
local NOT_DOWN = "SBGore_NotDown"
-- the swap each mode makes in a decorator's name list: the new name for one, or nil to leave it (all: the list's names)
local SWAP = {
  attack = function(nm) return DOWN[nm] and NOT_DOWN end,
  wait = function(nm, all) return nm == "KnockDownForward" and all.Down and not all.Down_Eve and "Down_Eve" or nil end,
}
-- mode: "attack", "wait" or nil (the game's trees); done: decorator address -> the decorator; orig: its name ->
-- { field -> { was, now } (or a list of those) }; pending: { obj, t } made since
local down = { mode = nil, done = {}, orig = {}, pending = {} }
local DOWN_MS = 2
local function decorators() return try(function() return FindAllOf("SBBTDecorator_SbCheckActorEffect") end) or {} end
local function swap_names(d, key, field, list, mode)
  local o = down.orig[key]
  local swap = SWAP[mode]
  local changed = 0
  if list then
    local arr = try(function() return d[field] end)
    if not arr then return 0 end
    local names, all = {}, {}
    try(function() arr:ForEach(function(i, e) local nm = e:get():ToString(); names[i] = nm; all[nm] = true end) end)
    try(function() arr:ForEach(function(i, e)
      local nm = names[i]
      if not swap then
        local was = o and o[field] and o[field][i]
        if was and nm == was[2] then e:set(FName(was[1])); changed = changed + 1 end
      else
        local to = nm and swap(nm, all)
        if to then
          down.orig[key] = down.orig[key] or {}
          down.orig[key][field] = down.orig[key][field] or {}
          down.orig[key][field][i] = { nm, to }
          e:set(FName(to)); changed = changed + 1
        end
      end
    end) end)
  else
    local nm = try(function() return d[field]:ToString() end)
    if not swap then
      local was = o and o[field]
      if was and nm == was[2] then try(function() d[field] = FName(was[1]) end); changed = 1 end
    else
      local to = nm and swap(nm, { [nm] = true })
      if to then
        down.orig[key] = down.orig[key] or {}
        down.orig[key][field] = { nm, to }
        try(function() d[field] = FName(to) end); changed = 1
      end
    end
  end
  return changed
end
local LOG = { attack = "they attack her while she is down", wait = "they wait while she is held down (Down_Eve)" }
-- mode nil: the ones in list put back as the game has them
local function attack_down(mode, list, quiet)
  local nd, nn = 0, 0
  for _, d in ipairs(list or decorators()) do
    -- (by address for the ones already seen: a name for each of them every scan was a stutter of its own)
    local a = valid(d) and addr(d)
    -- only the checks on the target (ActorType Target: 1)
    local key = a and (not mode or not down.done[a]) and try(function() return d.ActorType end) == 1 and try(function() return d:GetFullName() end)
    -- (kept by its path: put back only while the game still has it, an enemy's tree goes with it, see main.lua held)
    if a and mode and not down.done[a] then down.done[a] = key and ctx.keep(d) or true end
    if key then
      local k = swap_names(d, key, "EffectAlias", false, mode) + swap_names(d, key, "OrCheck_EffectAliasArray", true, mode)
        + swap_names(d, key, "AndCheck_EffectAliasArray", true, mode)
      if k > 0 then nd, nn = nd + 1, nn + k end
    end
  end
  if not mode then down.done, down.orig = {}, {} end
  if nd > 0 and not quiet then
    log(string.format("%s: %d knockdown checks in %d of the enemies' decision nodes", LOG[mode] or "they wait while she is down again",
      nn, nd))
  end
  return nd, nn
end
local function down_tick()
  local mode = cfg().attackDown == true and "attack" or ctx.tune.holdDown ~= false and "wait" or nil
  if mode ~= down.mode then
    if down.mode then
      local list = {}
      for _, k in pairs(down.done) do if k ~= true and ctx.held(k) then list[#list + 1] = k.obj end end
      attack_down(nil, list)
    end
    down.mode = mode
    down.scanned, down.pending = false, {}
  end
  if not mode then return end
  if not down.hooked then
    down.hooked = true
    ctx.newobj.watch("/Script/SB.SBBTDecorator_SbCheckActorEffect", function(o)
      if down.mode then down.pending[#down.pending + 1] = { k = ctx.keep(o), t = os.clock() + 1 } end
    end)
  end
  -- the first scan through the same queue, DOWN_MS a tick: the level's every decorator at once was a 1.4-2.2 s freeze
  -- (playtest). Only their addresses are taken here, each one's index asked in its batch below: asked all in this
  -- tick, 64 to an sbslice call through its answer file, the scan still held one tick 2.1 s (playtest)
  if not down.scanned then
    down.scanned = true
    local t0, now = os.clock(), os.clock()
    local n = 0
    for _, d in ipairs(decorators()) do
      local k = ctx.keep(d)
      if k then down.pending[#down.pending + 1] = { k = k, t = now }; n = n + 1 end
    end
    log(string.format("%d knockdown checks to look at, found in %.0f ms", n, (os.clock() - t0) * 1000))
    return
  end
  -- the new ones a few at a time, at most DOWN_MS a tick: a fight's worth loading at once (an enemy's whole tree) was
  -- 62-127 ms in one tick, at a death too (playtest). Due in order, as they were made. Each tick's batch is asked
  -- in one sbslice call (its object array check) before any is touched: one freed in the meantime (an enemy's tree
  -- going at her death) was read by its ActorType and crashed the game (UE4SS reading the freed object's class,
  -- playtest). (Through held, each tick's first check asked again every decorator held in the last 3 s)
  local t0 = os.clock()
  local batch = {}
  while #batch < 64 and down.pending[1] and down.pending[1].t <= t0 do batch[#batch + 1] = table.remove(down.pending, 1) end
  local ks = {}
  for i, x in ipairs(batch) do ks[i] = x.k end
  local ta = os.clock()
  local asked = #batch == 0 or ctx.alive_ask(ks)
  local askMs = (os.clock() - ta) * 1000
  if not asked then
    -- (sbslice not up or not answering: the batch again next tick)
    for i = #batch, 1, -1 do table.insert(down.pending, 1, batch[i]) end
    return
  end
  -- (the budget from the answer on: the call alone can take DOWN_MS, and nothing would ever be done)
  t0 = os.clock()
  for i, x in ipairs(batch) do
    if i > 1 and os.clock() - t0 >= DOWN_MS / 1000 then
      -- (the rest next tick, asked again then)
      for j = #batch, i, -1 do table.insert(down.pending, 1, batch[j]) end
      break
    end
    local k = x.k
    if k.alive and k.idx then
      down.done[k.addr] = nil
      local t1 = os.clock()
      local d1, n1 = attack_down(mode, { k.obj }, true)
      down.nd, down.nn = (down.nd or 0) + d1, (down.nn or 0) + n1
      local ms = (os.clock() - t1) * 1000
      if ms >= 50 then log(string.format("attack-down: a decision node took %.0f ms (%s)", ms, tostring(try(function() return k.obj:GetFullName() end)))) end
    end
  end
  -- (a 437 ms tick here as Raven spawned, playtest: which part. And 48-56 ms at each death's start with neither part
  -- over 50, playtest: both, with the batch, from slowMs on)
  local loopMs = (os.clock() - t0) * 1000
  if askMs + loopMs >= ((ctx.tune.gore or {}).slowMs or 15) then
    log(string.format("attack-down: %d decision nodes (%d still to do): asking sbslice %.0f ms, the checks %.0f ms", #batch,
      #down.pending, askMs, loopMs))
  end
  if #down.pending == 0 and (down.nd or 0) > 0 then
    log(string.format("%s: %d knockdown checks in %d of the enemies' decision nodes", LOG[mode], down.nn, down.nd))
    down.nd, down.nn = 0, 0
  end
end

-- Forced grab attacks (tune.enemies.forceGrabs): every enemy whose decision tree names a grab skill attacks
-- with grabs. The tree itself is left alone (its ranges, dice rolls, cooldowns and phases still pick the
-- branch): what each attack branch plays is renamed to the tree's own grab, so whatever it picks comes out a
-- grab-QTE move. Read from the game's trees (Raven's BetaGrab, the Sawshark's DoubleGrab, the Crawler's
-- ComboGrab...): a tree with no grab skill in it stays as the game has it (the Elder's grab lives in the
-- fight's script, not its tree). A branch that already grabs, and the dodges, get-ups and starts (aft's
-- skipped/attacky words), keep theirs. Put back as the game has them when it is turned off, and the saved
-- originals join aft.skills so Hits After Death still finds the attacks.
local force = { on = false, nodes = {}, by_tree = {}, pending = {}, hooked = false, scanned = false, method = nil }
local FORCE_NON_GRAB = { "success", "fail", "counter", "chain", "catch", "linkbreak", "preview" }
-- a grab skill's name (in the tree, as in the Animation folder next to its mesh)
function M.force_is_grab(nm) return tostring(nm):find("Grab", 1, true) ~= nil end
-- one worth playing for every attack: a grab, not a counter, a chain's link, a catch or a success/fail show
function M.force_plain_grab(nm)
  if not M.force_is_grab(nm) then return false end
  local l = tostring(nm):lower()
  for _, w in ipairs(FORCE_NON_GRAB) do if l:find(w, 1, true) then return false end end
  return true
end
-- the tree's grab to play: its plainest grab (the first), else any grab, else none
function M.force_pick(set)
  local any = nil
  for nm in pairs(set) do
    if M.force_plain_grab(nm) then return nm end
    if not any and M.force_is_grab(nm) then any = nm end
  end
  return any
end
-- a branch worth renaming: a close attack or a lunging one, none of its skills a grab already. Leaps,
-- dashes, charges, spins and ground slams close in on their own or are thrown point blank, so they come out
-- grabs too; dodges, get-ups, guards, turns and falls back, buffs, phases and true ranged attacks (shots and
-- beams) keep theirs, and the fight keeps its shape at a distance
local FORCE_RANGED = { "Shot", "Range", "Beam", "Missile", "Projectile", "Wave" }
function M.force_attack_node(skills)
  if #skills == 0 then return false end
  local attacky = false
  for _, nm in ipairs(skills) do
    if M.force_is_grab(nm) then return false end
    for _, w in ipairs(FORCE_RANGED) do if nm:find(w, 1, true) then return false end end
    if not attacky and M.attacky(nm) then attacky = true end
  end
  return attacky
end
-- the skill names the saved originals still hold (for aft.skills)
function M.force_orig_skills()
  local out = {}
  for _, f in pairs(force.nodes) do for _, nm in ipairs(f.orig) do out[nm] = true end end
  return out
end
-- the skill names a UseSkill node plays now, or nil
local function force_read(t)
  local out = nil
  try(function()
    out = {}
    t.SkillName:ForEach(function(_, e) out[#out + 1] = e:get():ToString() end)
  end)
  return out and #out > 0 and out or nil
end
-- a node's whole skill list played as one grab. Whole-list assignment first (a node with two attacks must
-- not keep the second), element-wise for a lone skill when that is all the build takes. Verified by reading
-- back; the first method that holds on this build is logged once
local function force_write(t, list)
  if #list == 0 then return false end
  local ok = try(function() t.SkillName = list; return true end) and (function()
    local back = force_read(t)
    return back and #back == #list and back[1] == list[1]
  end)()
  local how = ok and "table" or nil
  if not ok and #list == 1 then
    ok = try(function()
      local n = 0
      t.SkillName:ForEach(function(_, e) n = n + 1; if n == 1 then e:set(list[1]) end end)
      return n == 1
    end) and (function()
      local back = force_read(t)
      return back and #back == 1 and back[1] == list[1]
    end)()
    how = ok and "elem" or nil
  end
  if ok and not force.method then
    force.method = how
    log(string.format("forcegrabs: skill lists rename by %s on this build",
      how == "table" and "whole-list assignment" or "element writes"))
  end
  return ok or false
end
-- a UseSkill node's tree, from its full name ("...M_Raven_AI.M_Raven_AI:SBBTTask_SbUseSkill_3"). A node
-- the game made up on the fly has no tree in its name (its outer is the pawn): those group by that outer, so
-- their pick still comes from their own enemy's skills
local function force_tree(t)
  local full = try(function() return t:GetFullName() end) or ""
  local tree = full:match("([%w_]+%.[%w_]+):SBBTTask") or full:match("([%w_]+):SBBTTask")
  if not tree then
    tree = "?"
    if not force.unknownLogged then
      force.unknownLogged = true
      log(string.format("forcegrabs: a skill node with no tree in its name: %s", full ~= "" and full or "no full name"))
    end
  end
  return tree
end
-- note a UseSkill node, swapping it when its tree's grab is known
local function force_note(a, k, t)
  local skills = force_read(t)
  if not skills then return end
  local tree = force_tree(t)
  local bt = force.by_tree[tree]
  if not bt then bt = { skills = {}, pick = nil, nodes = {}, logged = false }; force.by_tree[tree] = bt end
  for _, nm in ipairs(skills) do bt.skills[nm] = true end
  if not bt.pick then
    bt.pick = M.force_pick(bt.skills)
    -- the tree's grab only just found: its earlier attack nodes queued again
    if bt.pick then for addr in pairs(bt.nodes) do
      if force.nodes[addr] and not force.nodes[addr].swapped then force.pending[#force.pending + 1] = { a = addr, t = os.clock() } end
    end end
  end
  local f = force.nodes[a]
  if not f then
    f = { k = k, tree = tree, orig = skills, swapped = false, failed = false }
    force.nodes[a], bt.nodes[a] = f, true
  end
  if bt.pick and not f.swapped and not f.failed and M.force_attack_node(f.orig) then
    if force_write(t, { bt.pick }) then
      f.swapped = true
      if not bt.logged then
        bt.logged = true
        log(string.format("forcegrabs: %s: its attacks play %s now", tree, bt.pick))
      end
    else
      f.failed = true
      log(string.format("forcegrabs: %s: %s not renamed (this build takes neither skill list write)", tree,
        table.concat(f.orig, ", ")))
    end
  end
end
-- everything renamed put back as the game has it (only what the game still holds)
local function force_restore()
  local back = 0
  for a, f in pairs(force.nodes) do
    if f.swapped and ctx.held(f.k) then
      if force_write(f.k.obj, f.orig) then back = back + 1 end
      f.swapped = false
    end
  end
  if back > 0 then log(string.format("forcegrabs: %d attack branches put back as the game has them", back)) end
  force.nodes, force.by_tree, force.method = {}, {}, nil
end
function M.force_tick()
  local on = cfg().forceGrabs == true
  if on ~= force.on then
    if force.on then force_restore() end
    force.on, force.scanned, force.pending = on, false, {}
    if on then log("forcegrabs: on: enemies with a grab skill attack with it") end
  end
  if not on then return end
  if not force.hooked then
    force.hooked = true
    ctx.newobj.watch("/Script/SB.SBBTTask_SbUseSkill", function(o)
      if force.on then force.pending[#force.pending + 1] = { k = ctx.keep(o), t = os.clock() + 1 } end
    end)
  end
  if not force.scanned then
    force.scanned = true
    local t0, n = os.clock(), 0
    for _, t in ipairs(try(function() return FindAllOf("SBBTTask_SbUseSkill") end) or {}) do
      local k = ctx.keep(t)
      if k then force.pending[#force.pending + 1] = { k = k, t = os.clock() }; n = n + 1 end
    end
    log(string.format("forcegrabs: %d attack nodes to look at, found in %.0f ms", n, (os.clock() - t0) * 1000))
    return
  end
  local t0, n = os.clock(), 0
  while #force.pending > 0 and n < 8 and os.clock() - t0 < 0.004 do
    local x = table.remove(force.pending, 1)
    n = n + 1
    if x.a then
      local f = force.nodes[x.a]
      if f and ctx.held(f.k) and not f.swapped and not f.failed then force_note(x.a, f.k, f.k.obj) end
    elseif x.k and x.t and x.t <= os.clock() then
      if ctx.alive_ask({ x.k }) and x.k.alive and valid(x.k.obj) then
        local a = addr(x.k.obj)
        if a and not force.nodes[a] then force_note(a, x.k, x.k.obj) end
      end
    elseif x.k then
      force.pending[#force.pending + 1] = x
      break
    end
  end
end

-- the death's push (pushScale, push, pushUp): the game's own throw (its death show's ragdoll key, 0.01 s in) scaled
-- once it is in, and a push of our own along the blow on top, every body of it at once (velocity, not force: the
-- same on any kind's mass). The blow: where its mesh was last hit from, else away from her
local function blow_dir(pawn, e, pel)
  local hit = e.hit and os.clock() - e.hit.t < (cfg().hitWindow or 1.0) and e.hit or nil
  if hit and hit.push then return hit.push end
  local her = try(function() return vof(pawn:K2_GetActorLocation()) end)
  return her and pel and unit(vec(pel.X - her.X, pel.Y - her.Y, 0)) or nil
end
local function push_all(e, v)
  return try(function() e.mesh:AddImpulseToAllBodiesBelow(v, FName("Bip001"), true, true); return true end) == true
end
local function death_push(pawn, e, pel)
  local g = cfg()
  local p, up = tonumber(g.push) or 0, math.min(math.max(tonumber(g.pushUp) or 0.2, 0), 1)
  local d = p > 0 and blow_dir(pawn, e, pel)
  if d then
    local h = math.sqrt(d.X * d.X + d.Y * d.Y)
    if h > 1e-3 then
      local v = vec(d.X / h * (1 - up) * p, d.Y / h * (1 - up) * p, up * p)
      if push_all(e, v) then log(string.format("%s died: pushed %.0f cm/s along the blow", e.kind.alias, p)) end
    end
  end
  local k = tonumber(g.pushScale) or 1
  if k ~= 1 then e.scaleAt = os.clock() + 0.06 end
end
-- the game's throw scaled: what its pelvis moves at, times pushScale less one, added to every body (0: dropped dead)
local function scale_push(e)
  e.scaleAt = nil
  local k = math.max(tonumber(cfg().pushScale) or 1, 0)
  local v = try(function() return vof(e.mesh:GetPhysicsLinearVelocity(FName("Bip001-Pelvis"))) end)
  if v and push_all(e, vec(v.X * (k - 1), v.Y * (k - 1), v.Z * (k - 1))) then
    log(string.format("%s: its throw %.0f cm/s scaled x%g", e.kind.alias, len(v), k))
  end
end

-- tune.smoothAnim: every character's animation updated every frame. The engine's update rate optimisation skips
-- frames on characters further off or small on screen, and they ran choppy next to a smooth world (reported). Each
-- character is set once (keyed by its live-check token), looked over once a second; switched off again, the engine's
-- own is given back to those set
local smooth = { next = 0, set = setmetatable({}, { __mode = "k" }) }
local function smooth_tick()
  local now = os.clock()
  if now < smooth.next then return end
  smooth.next = now + 1
  local on = ctx.tune.smoothAnim == true
  local n = 0
  for _, c in ipairs(ctx.live_chars()) do
    if (smooth.set[c.k] or false) ~= on then
      smooth.set[c.k] = on
      local m = try(function() return c.obj.Mesh end)
      if valid(m) and try(function() m.bEnableUpdateRateOptimizations = not on; return true end) then n = n + 1 end
    end
  end
  if n > 0 then log(string.format("smoothAnim %s: %d characters' animation %s", tostring(on), n, on and "updated every frame" or "back to the engine's rate")) end
end

-- after her death the enemies around her keep at her (tune.enemies.afterDeath, off by default): for `time` s their
-- blackboards keep her as their target (the object keys that held her while she lived, else the ones named Target),
-- and the trees' target searches (SBBTTask_SbDetectTarget) take a dead target too (bDead) and drop it only once it is
-- destroyed (TargetCancel Destroy, 2: ZeroHP, 0, dropped her the moment she died and they never came at her, playtest;
-- SB keeps its targets off the blackboards, whose keys are its ints, floats, vectors and bools), the patrol's searches
-- too (SbMoveToHome), and the trees' checks on the target's life (SbIsAlive) swapped (they still never came, playtest:
-- "target alive" guards their attacks), put back as the game had them when the time is up or she gets up. How far the trees go on attacking a dead target is the game's: the log
-- says what was kept and set ("after death: ...")
local aft = { keys = {}, next = 0, tasks = nil, sw = {}, anims = {} }
-- blackboard key names, by blackboard asset: static per asset, so the asset walk (ForEach plus a class
-- and name lookup per key, ~55 ms every 2 s with a pack around her, playtest) runs once. Values are still
-- re-read every look: that is the look.
local keyNames, keyNameCount = {}, 0
function M.after_keys(bb)
  local out = {}
  local aid = try(function() local a = bb.BlackboardAsset; return a and addr(a) end)
  if aid and keyNames[aid] then
    for i, nm in ipairs(keyNames[aid]) do out[i] = nm end
    return out
  end
  try(function()
    local asset = bb.BlackboardAsset
    local guard = 0
    while asset and asset:IsValid() and guard < 8 do
      guard = guard + 1
      asset.Keys:ForEach(function(_, e)
        local en = e:get()
        local kt = en.KeyType
        local cls = kt and kt:IsValid() and kt:GetClass():GetFName():ToString() or ""
        if cls:find("Object", 1, true) then out[#out + 1] = en.EntryName:ToString() end
      end)
      asset = asset.Parent
    end
  end)
  if aid then
    if keyNameCount > 60 then keyNames, keyNameCount = {}, 0 end
    keyNames[aid], keyNameCount = out, keyNameCount + 1
  end
  return out
end
function M.after_bb(o)
  local ctl = try(function() return o.Controller end)
  local bb = ctl and valid(ctl) and try(function() return ctl.Blackboard end)
  return bb and valid(bb) and bb or nil
end
-- their swings at her body (afterDeath.swing): the trees above bring them to her and keep her their target, but the
-- game's skills never fire at a dead target (playtest: an enemy followed her body and never swung). So an enemy within
-- swingReach cm of her body turns to her and plays one of its attacks itself, the AnimSequence its tree's skills are
-- named after (SbUseSkill's SkillName, in the Animation folder next to its mesh; not the dodges, get-ups, starts or
-- cautions), on its mesh in place of its animation Blueprint (PlayAnimation), which is given back when it ends. Its
-- trees stop it at its attack range (an enemy walked round her body, never within 260 cm, playtest), so it lunges in
-- to `lunge` cm off her body over the swing's first third. Its weapon then cuts her through the hits after death
-- (main.lua). No damage: the game has her dead
local SKIP_ANIM = { "Evasion", "Dodge", "StandUp", "Getup", "GetUp", "BattleStart", "Caution", "Step", "Spawn", "Idle", "Dead",
  "Die", "Result_", "Hit_", "Turn", "Run", "Walk", "Move", "Wait", "Guard", "Grab", "Phase", "Jump", "Groggy", "Down",
  "Entrance", "RootMotion", "_RM" }
-- an animation of its own loaded (one it played) counts when its name says it is an attack: the skill names didn't
-- match the Sawshark's (M_Sawshark_S01_RightSwing ...), so none was found and it never swung (playtest)
local ATTACK_WORDS = { "Attack", "Swing", "Slash", "Combo", "Dash", "Grinder", "Claw", "Thrust", "Stab", "Smash",
  "Strike", "Punch", "Kick", "Bite", "Rampage", "Chain", "Cut", "Slam", "Shot", "Spin", "Charge" }
local function skipped(nm)
  for _, w in ipairs(SKIP_ANIM) do if nm:find(w, 1, true) then return true end end
  return false
end
local function attacky(nm)
  if skipped(nm) then return false end
  for _, w in ipairs(ATTACK_WORDS) do if nm:find(w, 1, true) then return true end end
  return false
end
M.attacky = attacky -- forced grabs reuse the attack words for what a branch plays
-- an object's path (/Game/...): its full name less the class. UE4SS's objects have no GetPathName (it answered
-- nothing, so every enemy's mesh read "in no monster folder" and no attack of theirs was ever found, playtest)
local function path_of(o)
  local f = valid(o) and try(function() return o:GetFullName() end) or ""
  return f:match("^%S+ (.+)$") or ""
end
M.path_of = path_of
-- the monsters' attack animations loaded now (kept objects, not paths: per-path lookups cost
-- ~10 ms each in this build, 465 ms draining one folder on the death frame, playtest), by folder
function aft.scan_anims()
  aft.loaded = {}
  local nl = 0
  for _, an in ipairs(try(function() return FindAllOf("AnimSequence") end) or {}) do
    local p = path_of(an)
    local folder, rest = p:match("^(/Game/Art/Character/Monster/[^/]+/)(.+)$")
    local nm = rest and rest:find("Anim", 1, true) and rest:match("([^/%.]+)%.[^/]*$")
    if folder and nm and attacky(nm) then
      aft.loaded[folder] = aft.loaded[folder] or {}
      table.insert(aft.loaded[folder], { name = nm, hold = ctx.keep and ctx.keep(an) or nil, obj = an })
      nl = nl + 1
    end
  end
  return nl
end
local ANIM_CLS
-- its attacks, found a few at a time: the skill names are every loaded tree's, and a load of each in one go (most
-- aren't its own: the load fails) would stall the game; the loaded ones (after_scan) are only looked up.
-- Budgets per call (quests of ~10 ms each, playtest): the death path never drains (kept objects only).
local function attack_anims(mesh, sfBudget, loadBudget)
  local sk = try(function() return mesh.SkeletalMesh end)
  local path = path_of(sk)
  local folder = path:match("^(/Game/Art/Character/Monster/[^/]+/)")
  if not folder then
    aft.badPath = aft.badPath or {}
    if not aft.badPath[path] then
      aft.badPath[path] = true
      log(string.format("after death: its mesh %s is in no monster folder: no attacks of its own", path))
    end
    return {}, true
  end
  local f = aft.anims[folder]
  if not f then
    f = { out = {}, todo = {}, seen = {} }
    -- the scan's own need no lookup: kept already
    for _, e in ipairs((aft.loaded or {})[folder] or {}) do
      local a = (e.hold and e.hold.obj) or e.obj
      if valid(a) and not f.seen[e.name] then
        f.seen[e.name] = true
        f.out[#f.out + 1] = { a = a, name = e.name }
      end
    end
    for nm in pairs(aft.skills or {}) do
      if not skipped(nm) and not f.seen[nm] then
        f.todo[#f.todo + 1] = { path = folder .. "Animation/" .. nm .. "." .. nm }
      end
    end
    aft.anims[folder] = f
    if #f.todo == 0 and #f.out == 0 then log(string.format("after death: %s attacks of its own: nothing to look for", folder)) end
  else
    -- a kept asset gone: order only what plays
    for i = #f.out, 1, -1 do if not valid(f.out[i].a) then table.remove(f.out, i) end end
  end
  if #f.todo == 0 then return f.out, true end
  -- skill guesses resolve only while she lives: in-death each lookup cost ~10 ms (the drain ran 465 ms
  -- on one death frame, playtest); the scan's own above need none
  if ctx.dead_since and ctx.dead_since() then
    if #f.out == 0 and not f.noOutLogged then
      f.noOutLogged = true
      log(string.format("after death: %s attacks of its own: none loaded, skill guesses wait for life", folder))
    end
    return f.out, false
  end
  ANIM_CLS = ANIM_CLS or StaticFindObject("/Script/Engine.AnimSequence")
  local loads, n, sfMax, loadMax = 0, 0, sfBudget or 40, loadBudget or 2
  while #f.todo > 0 and loads < loadMax and n < sfMax do
    n = n + 1
    local t = table.remove(f.todo, 1)
    local nm = t.path:match("([^/%.]+)%.[^/]*$") or t.path
    if not f.seen[nm] then
      local a = try(function() return StaticFindObject(t.path) end)
      if not valid(a) and LoadAsset and ctx.may_load and ctx.may_load() then
        loads = loads + 1
        a = try(function() return LoadAsset(t.path) end)
      end
      if valid(a) and try(function() return a:IsA(ANIM_CLS) end) then
        f.seen[nm] = true
        f.out[#f.out + 1] = { a = a, name = nm }
      end
    end
  end
  if #f.todo == 0 then
    local n = {}
    for _, x in ipairs(f.out) do n[#n + 1] = x.name end
    log(string.format("after death: %s attacks of its own: %s", folder, #n > 0 and table.concat(n, ", ") or "none found"))
  end
  return f.out, #f.todo == 0
end
local function swing_back(e)
  if valid(e.mesh) then try(function() e.mesh:SetAnimationMode(0) end) end
end
local function swings_tick(pawn, c)
  if c.swing == false then return end
  local her = valid(pawn) and try(function() return pawn.Mesh end)
  -- aim at what is left of her: her upper body gone, the lunges and swings go for her pelvis and legs instead
  -- of where her chest was (or nowhere, when even her pelvis gives no socket)
  local gl = ctx.gore
  local upperGone = gl and gl.has_cut and try(function() return gl.has_cut(her, "Bip001-Spine1") end)
  local body = valid(her) and bone_loc(her, upperGone and "Bip001-Pelvis" or "Bip001-Spine1")
  if not body then body = valid(her) and bone_loc(her, upperGone and "Bip001-Spine1" or "Bip001-Pelvis") end
  if not body then return end
  local now, me = os.clock(), addr(pawn)
  local speed = ctx.time_scale and ctx.time_scale() or 1
  if not (speed and speed > 0) then speed = 1 end
  local reach, near, nearCls = c.swingReach or 450, nil, nil
  for _, ch in ipairs(ctx.live_chars()) do
    local a = ch.addr
    local e = known[a]
    local sw = aft.sw[a]
    if sw and sw.till then
      sw.elapsed = (sw.elapsed or 0) + math.max(0, now - (sw.tick or now)) * speed
      sw.tick = now
    end
    if sw and sw.till and sw.elapsed >= sw.duration then
      swing_back(sw)
      sw.till, sw.next, sw.lunge = nil, now + 0.6 + math.random() * 1.4, nil
    end
    -- the lunge: slid along the floor to `lunge` cm off her body over the swing's first third (swept: walls stop it)
    if sw and sw.lunge and valid(ch.obj) then
      local l = sw.lunge
      local k = math.min(1, sw.elapsed / l.dur)
      try(function()
        ch.obj:K2_SetActorLocation({ X = l.from.X + (l.to.X - l.from.X) * k, Y = l.from.Y + (l.to.Y - l.from.Y) * k,
          Z = l.from.Z }, true, {}, false)
      end)
      if k >= 1 then sw.lunge = nil end
    end
    if a ~= me and not (e and e.dead) and not (ctx.ignored and ctx.ignored(ch.cls)) then
      local at = ctx.char_at and ctx.char_at(ch) or (ctx.char_at == nil and try(function() return vof(ch.obj:K2_GetActorLocation()) end) or nil)
      local d = at and len(vec(body.X - at.X, body.Y - at.Y, 0))
      if d and (not near or d < near) then near, nearCls = d, ch.cls end
      local mesh = d and d < reach and not (sw and (sw.till or now < (sw.next or 0))) and try(function() return ch.obj.Mesh end)
      if valid(mesh) then
        local list, done = attack_anims(mesh)
        local pick = #list > 0 and list[math.random(#list)]
        if pick then
          local yaw = math.deg(math.atan(body.Y - at.Y, body.X - at.X))
          try(function() ch.obj:K2_SetActorRotation({ Pitch = 0, Yaw = yaw, Roll = 0 }, false) end)
          local ok = try(function() mesh:PlayAnimation(pick.a, false); return true end)
          local len_s = try(function() return pick.a:GetPlayLength() end) or 1.5
          local lunge
          local stop = c.lunge or 120
          if ok and d > stop then
            local k = (d - stop) / d
            lunge = { from = at, to = { X = at.X + (body.X - at.X) * k, Y = at.Y + (body.Y - at.Y) * k }, t0 = now,
              dur = math.max(0.15, len_s / 3) }
          end
          -- AnimSequence playback follows game time. A real-time deadline cut every slow-motion attack off
          -- before its contact frame; the four-second clamp also truncated long combos at full speed.
          aft.sw[a] = { mesh = mesh, till = ok and true or nil, elapsed = 0, tick = now, duration = len_s,
            next = now + 3, lunge = lunge }
          -- (ordered attacks with no weapon trail died before geometry with no line at all, playtest: stamp the order
          -- so hits_after can tell "no swing" from "a swing with no trail")
          if ok then ctx.afterOrderedAt = os.clock() end
          aft.swings = (aft.swings or 0) + 1
          if aft.swings <= 6 then
            log(string.format("after death: %s %x swings %s at her body %.0f cm off%s (%.1f s)%s", ch.cls, a, pick.name, d,
              lunge and string.format(", lunging %.0f cm in", d - stop) or "", len_s, ok and "" or ": NOT played"))
          end
        elseif done then
          aft.sw[a] = { next = now + 5 }
        end
      end
    end
  end
  -- the nearest enemy's distance to her body, each second for the first 8 (no swing: how near they came)
  aft.near = aft.near or { n = 0, next = 0 }
  if aft.near.n < 8 and now >= aft.near.next then
    aft.near.n, aft.near.next = aft.near.n + 1, now + 1
    log(string.format("after death: nearest enemy to her body: %s", near and string.format("%s %.0f cm (swings within %.0f)", nearCls, near, reach) or "none"))
  end
end
local function swings_stop()
  local n = 0
  for _, sw in pairs(aft.sw) do if sw.till then swing_back(sw); n = n + 1 end end
  aft.sw, aft.swings, aft.near, aft.checked = {}, 0, nil, nil
  return n
end

-- the trees' nodes looked up ahead (after_scan), not in the death's frame: four full object scans there took 195 ms,
-- a hitch with every death (playtest). Looked up while she lives with no enemy within scanClear cm of her (a level
-- just loaded, enemies streamed in far off) whenever an enemy of a class not around at the last look turns up, and in
-- the death only when none of the nodes looked up lives on. Each kept (keep) and asked at once, its index read while
-- it surely lives
local function after_scan(why, classes)
  local t0 = os.clock()
  local s = { det = {}, alive = {}, classes = classes or {} }
  for _, cls in ipairs({ "SBBTTask_SbDetectTarget", "SBBTTask_SbMoveToHome" }) do
    for _, t in ipairs(try(function() return FindAllOf(cls) end) or {}) do
      if valid(t) and try(function() return t.bEnemy end) == true
        and (cls ~= "SBBTTask_SbMoveToHome" or try(function() return t.bDetectTarget end) == true) then
        s.det[#s.det + 1] = ctx.keep(t)
      end
    end
  end
  for _, d in ipairs(try(function() return FindAllOf("SBBTDecorator_SbIsAlive") end) or {}) do
    if valid(d) and try(function() return d.ActorType end) == 1 then s.alive[#s.alive + 1] = ctx.keep(d) end
  end
  -- (the skill names only: strings, nothing held)
  aft.skills = {}
  for _, t in ipairs(try(function() return FindAllOf("SBBTTask_SbUseSkill") end) or {}) do
    try(function() t.SkillName:ForEach(function(_, e) aft.skills[e:get():ToString()] = true end) end)
  end
  -- (forced grabs renamed the branches: the originals still count as attacks)
  for nm in pairs(M.force_orig_skills()) do aft.skills[nm] = true end
  aft.anims = {}
  local nl = aft.scan_anims()
  local all = {}
  for _, k in ipairs(s.det) do all[#all + 1] = k end
  for _, k in ipairs(s.alive) do all[#all + 1] = k end
  for i = 1, #all, 64 do ctx.alive_ask({ table.unpack(all, i, math.min(i + 63, #all)) }) end
  local nsk = 0
  for _ in pairs(aft.skills) do nsk = nsk + 1 end
  aft.scan = s
  log(string.format("after death: trees looked up (%s): %d target searches, %d target alive checks, %d skills, %d attack animations loaded, in %.0f ms",
    why, #s.det, #s.alive, nsk, nl, (os.clock() - t0) * 1000))
end

-- the decision nodes changed put back (only the ones still alive: asked by index, nothing of a freed one read)
local function after_putback()
  local list = {}
  for _, k in ipairs(aft.tasks or {}) do list[#list + 1] = k end
  local back = 0
  for i = 1, #list, 64 do
    local part = { table.unpack(list, i, math.min(i + 63, #list)) }
    if ctx.alive_ask(part) then
      for _, k in ipairs(part) do
        if k.alive and valid(k.obj) then
          for f, v in pairs(aft.undo[k] or {}) do try(function() k.obj[f] = v end) end
          back = back + 1
        end
      end
    end
  end
  return back
end
-- the takeover undone, once, with its reason
local function after_over(why)
  if not aft.tasks then return end
  local back = after_putback()
  local sws, stopped = aft.swings or 0, swings_stop()
  log(string.format("after death: over (%s), %d decision nodes put back, blackboards kept on her %d times, %d swings at her body (%d cut short)",
    why, back, aft.sets or 0, sws, stopped))
  aft.tasks, aft.sets, aft.undo = nil, 0, nil
end
function M.after_tick(pawn)
  local c = cfg().afterDeath or {}
  local since = ctx.dead_since and ctx.dead_since()
  -- a spent death stays spent: without the latch every tick re-took over and put back (property writes plus
  -- two log lines a tick till time up, playtest). A new death carries a new `since` and clears it.
  if aft.overSince and aft.overSince ~= since then aft.overSince = nil end
  local on = c.enabled == true and since and os.clock() - since < (c.time or 10) and not aft.overSince
  local tAft = os.clock()
  if not on then
    after_over(since and "time up" or "she is up")
    if c.enabled ~= true or since then return end
    -- while she lives: which of the near enemies' object keys hold her, every 2 s; and the trees looked up again
    -- once an enemy of a new class is around and none is near her
    if os.clock() < aft.next then return end
    aft.next = os.clock() + 2
    local tAlive = os.clock()
    local her = try(function() return vof(pawn:K2_GetActorLocation()) end)
    local me = addr(pawn)
    local classes, fresh, close = {}, false, false
    for _, ch in ipairs(ctx.live_chars()) do
      if ch.addr ~= me and not (ctx.ignored and ctx.ignored(ch.cls)) then
        local at = ctx.char_at and ctx.char_at(ch) or (ctx.char_at == nil and try(function() return vof(ch.obj:K2_GetActorLocation()) end) or nil)
        classes[ch.cls] = true
        if not (aft.scan and aft.scan.classes[ch.cls]) then fresh = true end
        if her and at and len(sub(at, her)) < (c.scanClear or 1500) then close = true end
        local bb = her and at and len(sub(at, her)) < (c.reach or 3000) and M.after_bb(ch.obj)
        if bb then
          local mine = {}
          for _, nm in ipairs(M.after_keys(bb)) do
            local v = try(function() return bb:GetValueAsObject(FName(nm)) end)
            if v and addr(v) == me then mine[#mine + 1] = nm end
          end
          if #mine > 0 then aft.keys[ch.addr] = mine end
        end
      end
    end
    local tKeys = os.clock()
    if fresh and not close and next(classes) then after_scan("new enemies around", classes) end
    local tScan = os.clock()
    -- attack animations warmed while she lives: in-death lookups cost ~10 ms each (465 ms draining one
    -- folder on the death frame, playtest). Only out of combat (enemies near: the tick matters more than
    -- the warming); one unfinished folder per 2 s look, few lookups and one load, gated as ever.
    if not close and aft.scan and c.swing ~= false and ctx.may_load and ctx.may_load() then
      for _, ch in ipairs(ctx.live_chars()) do
        if ch.addr ~= me and not (ctx.ignored and ctx.ignored(ch.cls)) and (not ctx.alive or ctx.alive(ch.k) ~= false) then
          local m = try(function() return ch.obj.Mesh end)
          if valid(m) then
            local _, done = attack_anims(m, 4, 1)
            if not done then break end
          end
        end
      end
    end
    local tEnd = os.clock()
    if (tEnd - tAlive) * 1000 > 50 then log(string.format(
      "after death: slow alive tick %.0f ms: keys %.0f, scan %.0f, warm %.0f",
      (tEnd - tAlive) * 1000, (tKeys - tAlive) * 1000, (tScan - tKeys) * 1000, (tEnd - tScan) * 1000)) end
    return
  end
  if not aft.tasks then
    -- the nodes looked up ahead (after_scan), still alive
    local function live(list)
      local out = {}
      for i = 1, #list, 64 do
        local part = { table.unpack(list, i, math.min(i + 63, #list)) }
        if ctx.alive_ask(part) then
          for _, k in ipairs(part) do if k.alive and valid(k.obj) then out[#out + 1] = k end end
        end
      end
      return out
    end
    local det, alv, ready = {}, {}, true
    if aft.scan then det, alv = live(aft.scan.det), live(aft.scan.alive) end
    if #det + #alv == 0 then
      -- cold cache at her death: the full scan hits the death frame with hundreds of ms (the stutter on the
      -- smash deaths, playtest). Defer the takeover a moment; the ordered attacks below still play meanwhile,
      -- enemies taking seconds to close in anyway. Real 1.5 s or 90 ticks (the same at 60 fps), whichever first.
      ready = false
      aft.deferTicks = (aft.deferTicks or 0) + 1
      if aft.deferUntil and os.clock() < aft.deferUntil and (aft.deferTicks or 0) <= 90 then
        -- still waiting
      elseif not aft.deferUntil then
        aft.deferUntil = os.clock() + 1.5
        log("after death: trees not looked up ahead: takeover in 1.5 s, ordered attacks meanwhile")
      else
        aft.deferUntil, aft.deferTicks = nil, nil
        ready = true
      end
    else
      aft.deferTicks = nil
    end
    if ready then
    local ahead = #det + #alv > 0
    if not ahead then
      after_scan("in her death: none looked up ahead lives", aft.scan and aft.scan.classes)
      det, alv = aft.scan.det, aft.scan.alive
    end
    aft.tasks, aft.sets, aft.undo = {}, 0, {}
    local t0 = os.clock()
    -- a node changed, its fields as they were kept (put back through its index when the time is up)
    local function change(k, set)
      local o, was = k.obj, {}
      for f, v in pairs(set) do
        local old = try(function() return o[f] end)
        if old ~= nil and old ~= v and try(function() o[f] = v; return true end) then was[f] = old end
      end
      if not next(was) then return false end
      aft.tasks[#aft.tasks + 1], aft.undo[k] = k, was
      return true
    end
    -- the trees' target searches (and the patrol's, SbMoveToHome with bDetectTarget) take a dead target, and drop it
    -- only once it is destroyed (ESBAIDetectTargetCancel: ZeroHP 0, Despawn 1, Destroy 2)
    local nd, cancels = 0, {}
    for _, k in ipairs(det) do
      local tc = try(function() return k.obj.TargetCancel end)
      if tc then cancels[tostring(tc)] = (cancels[tostring(tc)] or 0) + 1 end
      if change(k, { bDead = true, TargetCancel = 2 }) then nd = nd + 1 end
    end
    -- the checks on the target's life (SbIsAlive, ActorType Target 1; ESBBTDecoratorAliveCheckType: Alive 0, Dead 1)
    -- swapped: "target alive" holds while she lies dead, "target dead" (their walk off) doesn't
    local na = 0
    for _, k in ipairs(alv) do
      local ct = try(function() return k.obj.CheckType end)
      if (ct == 0 or ct == 1) and change(k, { CheckType = 1 - ct }) then na = na + 1 end
    end
    local cs = {}
    for k, v in pairs(cancels) do cs[#cs + 1] = k .. "x" .. v end
    local nk = 0
    for _ in pairs(aft.keys) do nk = nk + 1 end
    log(string.format("after death: enemies keep at her for %.0f s: %d target searches take the dead now (TargetCancel was %s), %d target alive checks swapped, %d enemies had her on their blackboards (%s, %.0f ms)",
      c.time or 10, nd, #cs > 0 and table.concat(cs, " ") or "-", na, nk, ahead and "trees looked up ahead" or "trees looked up now",
      (os.clock() - t0) * 1000))
  end
  end
  local tTake = os.clock()
  if on then
    -- nothing left of her to hit (every part cut or smashed away, at her death or after follow-ups): call it off
    -- early, same as time up. Probed after the takeover so the over line fires with its nodes to put back.
    local mesh = valid(pawn) and try(function() return pawn.Mesh end)
    local gl = ctx.gore
    if mesh and gl and gl.nothing_left and (try(function() return gl.nothing_left(mesh) end) or false) then
      on = false
      aft.overSince = since
      -- what reads gone and why (playtest: the loop ended with a leg left)
      local detail = ""
      if gl.cut_state then
        detail = try(function() return " [" .. table.concat(gl.cut_state(mesh), ", ") .. "]" end) or ""
      end
      after_over("nothing left of her" .. detail)
    end
  end
  if on then swings_tick(pawn, c) end
  local tSwing = os.clock()
  do
    -- the blackboard loop runs at most every quarter second; a slow takeover/swings tick that skips it
    -- still reports itself
    local tNow = os.clock()
    if tNow < aft.next then
      if (tNow - tAft) * 1000 > 100 then log(string.format(
        "after death: slow tick %.0f ms: takeover %.0f, swings %.0f, blackboards skipped",
        (tNow - tAft) * 1000, (tTake - tAft) * 1000, (tSwing - tTake) * 1000)) end
      return
    end
  end
  aft.next = os.clock() + 0.25
  local her = try(function() return vof(pawn:K2_GetActorLocation()) end)
  local me = addr(pawn)
  for _, ch in ipairs(ctx.live_chars()) do
    if ch.addr ~= me and not (ctx.ignored and ctx.ignored(ch.cls)) then
      local e = known[ch.addr]
      local at = not (e and e.dead) and (ctx.char_at and ctx.char_at(ch) or (ctx.char_at == nil and try(function() return vof(ch.obj:K2_GetActorLocation()) end) or nil))
      local bb = her and at and len(sub(at, her)) < (c.reach or 3000) and M.after_bb(ch.obj)
      if bb then
        -- re-checking every blackboard key every quarter second cost whole slow ticks with a pack around her
        -- (playtest): each enemy's keys are re-read at most every 2 s, a dropped key noticed no later than that
        local checked = aft.checked or {}
        aft.checked = checked
        if os.clock() - (checked[ch.addr] or 0) >= 2 then
          checked[ch.addr] = os.clock()
        local names = aft.keys[ch.addr]
        if not names then
          names = {}
          for _, nm in ipairs(M.after_keys(bb)) do if nm:find("Target", 1, true) then names[#names + 1] = nm end end
          aft.keys[ch.addr] = names
          if #names > 0 then log(string.format("after death: %s %x had no key on her, kept on %s", ch.cls, ch.addr, table.concat(names, ", "))) end
        end
        for _, nm in ipairs(names) do
          local v = try(function() return bb:GetValueAsObject(FName(nm)) end)
          if not v or addr(v) ~= me then
            try(function() bb:SetValueAsObject(FName(nm), pawn) end)
            aft.sets = (aft.sets or 0) + 1
            if (aft.sets or 0) <= 5 then log(string.format("after death: %s %x dropped her off %s (%s): set again", ch.cls, ch.addr, nm, v and "something else" or "empty")) end
          end
        end
        end
      end
    end
  end
  -- which phase of the corpse loop costs when the tick is slow (the 671 ms death-frame hitch, playtest)
  local tEnd = os.clock()
  if (tEnd - tAft) * 1000 > 100 then log(string.format(
    "after death: slow tick %.0f ms: takeover %.0f, swings %.0f, blackboards %.0f",
    (tEnd - tAft) * 1000, (tTake - tAft) * 1000, (tSwing - tTake) * 1000, (tEnd - tSwing) * 1000)) end
end

-- every tick of hers (main.lua), pawn and mesh hers
-- tm: main.lua's slow tick marker (the enemies' step was 47-174 ms now and then, playtest)
function M.tick(pawn, mesh, tm)
  tm = tm or function() end
  n = n + 1
  down_tick()
  tm("enemies attack-down")
  M.force_tick()
  tm("enemies force grabs")
  -- Always maintain the spawner's selected hostility mode.
  M.hostile_tick(pawn)
  tm("enemies hostility")
  M.after_tick(pawn)
  tm("enemies after death")
  if n % 8 == 0 and ctx.tune.dev then read_req(pawn); read_state(pawn) end
  tm("enemies dev reads")
  smooth_tick()
  tm("enemies smooth")
  if ctx.bosses then ctx.bosses.tick(pawn) end
  tm("enemies bosses")
  local g = cfg()
  local gore = ctx.gore
  -- the cuts, or only the death's push (cuts off: the ragdolls still get it)
  local cuts = g.enabled ~= false and gore and (ctx.tune.gore or {}).enabled ~= false
  local pushes = (tonumber(g.push) or 0) > 0 or (tonumber(g.pushScale) or 1) ~= 1
  -- Adoption and spawn diagnostics must run even when enemy gore and pushes are disabled.
  for i = #expect, 1, -1 do
    local x = expect[i]
    if os.clock() - x.t > 10 then
      log(string.format("spawn %s (CharacterTable %d): no matching actor observed within 10 seconds; request was sent but the game did not confirm creation", x.kind.alias, x.kind.id))
      table.remove(expect, i)
    end
  end
  if cuts then track_hand(pawn, mesh) end
  tm("enemies hand")
  local her = try(function() return vof(pawn:K2_GetActorLocation()) end)
  local me = addr(pawn)
  local seen, seenCharacters = {}, {}
  local now = os.clock()
  for _, c in ipairs(ctx.live_chars()) do
    seenCharacters[c.addr] = true
    if not ctx.alive or ctx.alive(c.k) ~= false then
    local k = kind_of(c.cls) or angel_kind_for(c) or proximity_expect(c, me)
    if not k then
      -- already followed (an unknown class adopted by proximity: its request is gone, but it is still it)
      local old = known[c.addr]
      if old and old.k and ctx.alive and ctx.alive(old.k) == false then old = nil end
      if old and addr(old.obj) == c.addr then k = old.kind end
    end
    if k then
      seen[c.addr] = true
      local e = known[c.addr]
      if e and e.k and ctx.alive and ctx.alive(e.k) == false then e = nil end
      if e and e.obj ~= c.obj and addr(e.obj) ~= c.addr then e = nil end
      -- (an actor being destroyed stays in the list until the next GC: a removed spawn was adopted again every tick)
      if not e and not dying(c.obj) then e = adopt(c.obj, c.addr, c.cls, k, cuts) end
      if e then
        e.k = c.k
        -- A pooled actor can already be followed when the game reuses it for a request.
        if not mine[c.addr] then
          match_spawn(c.obj, c.addr, k)
          if mine[c.addr] then
            log(string.format("following %s %x (%s), reused for spawn", k.alias, c.addr, c.cls))
            if k.row and ctx.bosses then ctx.bosses.adopted(c.addr, e, true) end
          end
        end
      end
      -- one out of reach at the last look is looked at every FAR_EVERY polls, each on its own poll (by its address):
      -- every enemy and corpse of the level every poll was ~1 ms of each poll, the poll's costliest part while she
      -- played (frame cost, a Nexus report of 144 fps down to 100-110 with microstutter). Nothing is cut or pushed
      -- out of reach, and its death or vanishing is seen ~0.1 s later
      if e and e.far and (n + (c.addr // 0x1000)) % FAR_EVERY ~= 0 then e = nil end
      if e then
        local dt = now - (e.lookAt or now)
        e.lookAt = now
        if try(function() return e.obj.bActorIsBeingDestroyed end) ~= false then
          gone(c.addr, e, "destroyed", "destroyed")
        elseif not valid(e.mesh) then
          gone(c.addr, e, "destroyed", "lost its mesh")
        else
          local sim = simulating(e)
          -- (a boss's physics asset just put back: its bodies came simulating, no death; bosses.own_physics)
          if sim and not e.dead and e.physHold and os.clock() < e.physHold and ctx.bosses then
            ctx.bosses.kinematic(e.mesh)
            if not e.physHeld then e.physHeld = true; log(string.format("%s %x: its bodies simulating after its physics asset was put back: kinematic again, not its death", k.alias, c.addr)) end
            sim = false
          end
          local pel = bone_loc(e.mesh, "Bip001-Pelvis")
          local near = her and pel and len(sub(pel, her)) < (g.reach or 2500)
          e.far = not near
          if not e.dead then
            -- (hit forces update on any hit, hers or another enemy's: read for every followed enemy so a kill
            -- by another enemy cuts where it landed too, near or far)
            poll_hit(e)
            if sim and not hidden(e) then
              e.dead, e.t, e.still, e.looks = true, os.clock(), 0, looks(e.mesh)
              local okw, ew = pcall(k.row and mine[c.addr] and drop_boss_weapons or weapons_on_ragdoll, e)
              if not okw then log("weapon on its ragdoll: " .. tostring(ew)) end
              -- (its outfit's KawaiiPhysics off on its ragdoll, as hers: gore.kawaii)
              if ctx.gore and ctx.gore.kawaii then
                local okk, kn, kall = pcall(ctx.gore.kawaii, e.mesh, false)
                if okk and (kall or 0) > 0 then log(string.format("%s %x: its KawaiiPhysics off on its ragdoll (%d of %d nodes)", k.alias, c.addr, kn, kall)) end
              end
              if k.row and ctx.bosses then ctx.bosses.died(pawn, c.addr, e) end
              if near and pushes then death_push(pawn, e, pel) end
              -- kills by other enemies cut too, near or far (the prologue's spectacle fights): the game's own
              -- throw moves a far corpse, the mod's push stays near-gated
              local cut_now = cuts and math.random() <= (g.cutChance or 1.0)
              local corpses = 0
              local kept = angelKept ~= nil
              for _, x in pairs(known) do
                if x.cut and not (kept and is_angel(x.kind)) then corpses = corpses + 1 end
              end
              if cut_now and corpses >= (g.maxCorpses or 6) then
                log(string.format("%s %x died: %d cut corpses already (maxCorpses), left whole", k.alias, c.addr, corpses))
                cut_now = false
              end
              if cut_now then
                local h = kill_blow(pawn, e)
                e.want = { t = os.clock(), h = h.loc and h or nil, kind = roll_kind(), loc = h.loc, what = "killed", pel = pel,
                  src = string.format("blow %s at %s", h.src, v3(h.loc)) }
                -- the cut starts on this tick, on the death hit, not a tick after the fall: when gore is busy
                -- try_cut leaves e.want queued and a later tick retries it for its kill window as before
                try_cut(pawn, c.addr, e)
              end
            end
          else
            if hidden(e) then
              gone(c.addr, e, nil, "hidden (back in its pool)")
              seen[c.addr] = nil
            elseif not sim then
              -- up again (its death undone, or the actor reused): after a second of not simulating
              e.still = e.still + math.max(dt, TICK_S)
              if e.still > 1.0 then
                gone(c.addr, e, nil, "up again")
                seen[c.addr] = nil
              end
            else
              e.still = 0
              if e.scaleAt and os.clock() >= e.scaleAt then scale_push(e) end
              -- (its materials every 0.5 s, a far one on its own poll: up to 8 slots, 4 engine reads each, for every
              -- corpse near her 8 times a second were a good part of the enemies' poll after a fight; the caps and
              -- bleeds go a few frames later as it dissolves)
              if not e.faded and now >= (e.matAt or 0) then
                e.matAt = now + 0.5
                local yes, now = dissolving(e)
                if yes then
                  e.faded, e.want = true, nil
                  if e.cut and gore then gore.enemy_fading(c.addr) end
                  log(string.format("%s %x dissolving (%s)%s", e.kind.alias, c.addr, now, e.cut and ": its caps and bleeds removed" or ""))
                  if angelKept and is_angel(e.kind) then
                    log(string.format("%s %x kept but dissolving: its CharacterTable row may differ from N_AirborneSquad; send this log", e.kind.alias, c.addr))
                  end
                end
              end
              if e.faded or not cuts then -- nothing more on a body going (cuts off: the push was all)
              elseif e.want then try_cut(pawn, c.addr, e) elseif near then corpse_hit(pawn, c.addr, e) end
            end
          end
        end
      end
    end
    end
  end
  -- gone from the characters list (its object went): its gore without touching it
  for a, e in pairs(known) do
    if not seen[a] then gone(a, e, "vanished", "gone") end
  end
  for a in pairs(angelCache) do if not seenCharacters[a] then angelCache[a] = nil end end
  angel_keep_tick()
end
-- ---- her death in an enemy's grab (tune.enemies.grab) ----
-- Raven grabbed her and hit her again and again; she died on one of the hits, the mod's ragdoll took her out of it at
-- once and Raven went on hitting thin air (playtest). While she lives, every GRAB_EVERY s an enemy within GRAB_NEAR cm
-- with a hand within reach cm of her body (or her attached to it) is noted; held for `hold` s it has her (a swing
-- passing through her is gone in a tenth of that). Raven's grab plays no montage on her (playtest: "no montage", the
-- grab never seen and her body taken out of the grip at once), so a montage isn't needed: with one, the grab lasts
-- while it plays (its hand off her between two hits); without, while its hand stays on her (M.grab_holds). main.lua's
-- death waits for that, so the grab runs out on her and the death comes at its end
local GRAB_EVERY, GRAB_NEAR = 0.1, 400
local GRAB_HANDS = { "Bip001-R-Hand", "Bip001-L-Hand" }
local GRAB_HER = { "Bip001-Pelvis", "Bip001-Spine1", "Bip001-Spine2", "Bip001-Neck", "Bip001-Head" }
local grab = { next = 0, on = {} }
local function montage_of(o)
  local ai = try(function() return o.Mesh:GetAnimInstance() end)
  local m = valid(ai) and try(function() return ai:GetCurrentActiveMontage() end)
  if not valid(m) then return nil end
  return m, ai, try(function() return m:GetFName():ToString() end) or "?"
end
M.montage_of = montage_of
-- her body's bones within GRAB_SPAN cm of her pelvis, so a hand further than reach + that off it touches none of them
local GRAB_SPAN = 100
local function her_bones(mesh)
  local her = {}
  for _, b in ipairs(GRAB_HER) do her[#her + 1] = { b, bone_loc(mesh, b) } end
  return her
end
-- its hand on her: the hand, her bone and how far (cm), else nil; and her bones if read. at0: her pelvis, her:
-- her_bones (both read once a watch, not once an enemy: 5 bones and the montage read for every enemy near her, 10
-- times a second, were most of 0.5.2's "lethal" poll part in a fight, 1.2-2 ms a poll, a Nexus report of the frame
-- rate down)
local function hand_on(o, mesh, reach, at0, her)
  local hands = {}
  local om = try(function() return o.Mesh end)
  if not valid(om) then return nil, nil, nil, her end
  for _, hb in ipairs(GRAB_HANDS) do
    local h = bone_loc(om, hb)
    if h and not (at0 and len(sub(h, at0)) > reach + GRAB_SPAN) then hands[#hands + 1] = { hb, h } end
  end
  if #hands == 0 then return nil, nil, nil, her end
  her = her or her_bones(mesh)
  local best, bh, bb
  for _, e in ipairs(hands) do
    local hb, h = e[1], e[2]
    for _, p in ipairs(her) do
      local d = p[2] and len(sub(h, p[2]))
      if d and d < reach and (not best or d < best) then best, bh, bb = d, hb, p[1] end
    end
  end
  return bh, bb, best, her
end
function M.grab_tick(pawn, mesh)
  local c = cfg().grab or {}
  local now = os.clock()
  if c.enabled == false or now < grab.next then return end
  grab.next = now + GRAB_EVERY
  local at0 = bone_loc(mesh, GRAB_HER[1])
  if not at0 then return end
  grab.pawn, grab.mesh = pawn, mesh
  local me = addr(pawn)
  local root = try(function() return pawn.RootComponent end)
  local parent = valid(root) and addr(try(function() return root:GetAttachParentActor() end))
  local seen, her = {}, nil
  for _, ch in ipairs(ctx.live_chars()) do
    -- (a boss standing still, Passive Bosses: her walking up to it put its hand on her neck, a grab logged, playtest)
    if ch.addr ~= me and not (ctx.ignored and ctx.ignored(ch.cls)) and not (ctx.bosses and ctx.bosses.is_passive(ch.addr)) then
      local o = ch.obj
      local at = ctx.char_at and ctx.char_at(ch) or (ctx.char_at == nil and try(function() return vof(o:K2_GetActorLocation()) end) or nil)
      if at and len(sub(at, at0)) < GRAB_NEAR then
        local touch, bone, d = parent and parent == ch.addr and "attached", nil, nil
        if not touch then
          local reach = c.reach or 40
          -- (her bones read for the first enemy with a hand near her, kept for the rest)
          touch, bone, d, her = hand_on(o, mesh, reach, at0, her)
        end
        local g = grab.on[ch.addr]
        -- (its montage only for an enemy touching her or noted already: one with neither isn't a grab)
        local m, mid, mn
        if touch or g then m, mid, mn = montage_of(o) end
        mn = mn or "no montage"
        if touch then
          if not g or g.mn ~= mn then g = { since = now, mn = mn, obj = o, cls = ch.cls, addr = ch.addr }; grab.on[ch.addr] = g end
          g.last, g.mont, g.how = now, m, touch .. (bone and string.format(" on her %s (%.0f cm)", bone, d) or "")
          seen[ch.addr] = true
          if not g.said and g.last - g.since >= (c.hold or 0.4) then
            g.said = true
            log(string.format("grab: %s has her: %s, %s, her %s", ch.cls, g.how, mn,
              (select(3, montage_of(pawn))) or "no montage"))
          end
        elseif g and m and g.mont and g.mn == mn and now - g.last < 1 then
          seen[ch.addr] = true -- (the same montage, its hand off her between two hits)
        end
      end
    end
  end
  for a in pairs(grab.on) do if not seen[a] then grab.on[a] = nil end end
end
-- the enemy that has her now (held hold s), else nil
function M.grab_now()
  local c = cfg().grab or {}
  if c.enabled == false then return nil end
  local now, best = os.clock(), nil
  for _, g in pairs(grab.on) do
    if now - g.last < 0.3 and g.last - g.since >= (c.hold or 0.4) and (not best or g.since < best.since) then best = g end
  end
  return best
end
-- the grab still on: its montage still playing on it; without one, her still attached to it or its hand on her
-- (a little further than it took: her body sways in its grip)
function M.grab_holds(g)
  if not (g and valid(g.obj)) then return false end
  if g.mont then
    local m, ai = montage_of(g.obj)
    if not m or m ~= g.mont then return false end
    return try(function() return ai:Montage_IsPlaying(m) end) ~= false
  end
  local pawn, mesh = grab.pawn, grab.mesh
  if not (valid(pawn) and valid(mesh)) then return false end
  local root = try(function() return pawn.RootComponent end)
  if valid(root) and addr(try(function() return root:GetAttachParentActor() end)) == addr(g.obj) then return true end
  return hand_on(g.obj, mesh, ((cfg().grab or {}).reach or 40) * 1.5) ~= nil
end
-- the montages the enemies near her play, for the log (what a grab's is called)
function M.near_montages(pawn)
  local her = try(function() return vof(pawn:K2_GetActorLocation()) end)
  local out, me = {}, addr(pawn)
  local mesh = try(function() return pawn.Mesh end)
  if not valid(mesh) then mesh = nil end
  for _, ch in ipairs(her and ctx.live_chars() or {}) do
    local at = ch.addr ~= me and (ctx.char_at and ctx.char_at(ch) or (ctx.char_at == nil and try(function() return vof(ch.obj:K2_GetActorLocation()) end) or nil))
    if at and len(sub(at, her)) < GRAB_NEAR then
      local _, _, mn = montage_of(ch.obj)
      -- (its nearest hand to her body: a grab without a montage told from a miss)
      local hb, bb, hd
      if mesh then hb, bb, hd = hand_on(ch.obj, mesh, 200) end
      out[#out + 1] = string.format("%s %.0f cm: %s%s", ch.cls, len(sub(at, her)), mn or "no montage",
        hb and string.format(", %s %.0f cm from her %s", hb, hd, bb) or "")
    end
  end
  return #out > 0 and table.concat(out, "; ") or "none near"
end
-- an enemy in an attack: one of its montages playing, not a walk, turn, hit reaction or the like, or one of the
-- after-death swings at her body (hits after death: a weapon only brushing her body cut her, reported)
local NOT_ATTACK = { "Idle", "Walk", "Run", "Move", "Turn", "Wait", "Hit_", "Result_", "Groggy", "Down", "StandUp",
  "Getup", "GetUp", "Caution", "Spawn", "Entrance", "Evasion", "Dodge", "Step", "Guard", "Jump", "Dead", "Die" }
function M.attacking(o, a)
  local sw = a and aft.sw[a]
  if sw and sw.till then return "its swing at her body" end
  local m, _, mn = montage_of(o)
  if not m then return nil end
  for _, w in ipairs(NOT_ATTACK) do if mn:find(w, 1, true) then return nil end end
  return mn
end

-- (bosses.lua: spawning a kind, and a followed character by its address)
M.spawn_kind = function(pawn, k, count) return spawn(pawn, k, count or 1) end
function M.entry(a) return known[a] end
-- every one spawned here still followed (Remove all takes them)
function M.remove_spawned() remove_all() end

-- ---- hostility: what spawned NPCs fight (F3 → Spawner, dev only) ----
-- spawner.hostile = "game": as the game has them; "hostile": hostile to Eve (and damageable, even the angels);
-- "passive": their AI stopped, they never fight. spawner.infight with hostile: they fight each other too.
-- Hostile works two ways. The NPC's CharacterTable row is patched while one spawned of it lives (bIsHostile when
-- the row names one, bApplyDamageWhenPlayerAlive, its immortality dispelled; put back exactly once none is left,
-- as the bosses' rows are), and its blackboard's target keys are kept on Eve — or on each other for infight (the
-- after-death code's trick: after_keys/after_bb). A row the spawn didn't name (a custom ID) gets blackboards only.
local hos = { rows = {}, stopped = {}, next = 0, logged = {}, setLogged = nil }
local CHAR = "/Game/Local/Data/CharacterTable.CharacterTable"
local EFFECT = "/Game/Local/Data/EffectTable.EffectTable"

local function name_idx(s) return try(function() return FName(s):GetComparisonIndex() end) end
local function row_struct(path)
  local dt = try(function() return StaticFindObject(path or CHAR) end)
  local rs = valid(dt) and try(function() return dt.RowStruct end)
  if not (valid(dt) and valid(rs)) then return nil end
  return dt, rs
end
local function row_fields(rs) -- the row's fields: name -> { off, cls, mask }
  local out = {}
  try(function() rs:ForEachProperty(function(p)
    local nm = try(function() return p:GetFName():ToString() end)
    if nm then out[nm] = { off = try(function() return p:GetOffset_Internal() end),
      cls = try(function() return p:GetClass():GetFName():ToString() end),
      mask = try(function() return p:GetFieldMask() end) } end
  end) end)
  return out
end
-- the 4 bytes at a row's field: read, and written with u when given (sbslice's d, as the bosses' rows)
local function row_u32(row, off, u)
  if not ctx.gore then return nil, "no gore" end
  local dt, rs = row_struct()
  if not dt then return nil, "no CharacterTable loaded" end
  local idx = name_idx(row)
  if not (idx and off) then return nil, "no name or field" end
  local s = string.format("d%x,%x,%x,0,%x", addr(dt), addr(rs), idx, off)
  if u then s = s .. string.format(",%x", u & 0xffffffff) end
  local r = ctx.gore.command(s)
  local was = r:match("^ok row %x+ (%x+) %x+$")
  if not was then return nil, r end
  return tonumber(was:sub(-8), 16)
end
local function swap_effect(row, rs, off, from, to) -- DefaultEffectArray's from -> to; the answer's count or nil
  local dt = row_struct()
  if not dt then return nil end
  local ri, a, b = name_idx(row), name_idx(from), name_idx(to)
  if not (ri and a and off and b) then return nil end
  local r = ctx.gore and ctx.gore.command(string.format("N%x,%x,%x,0,%x,%x,0,%x,0", addr(dt), addr(rs), ri, off, a, b))
  return r and r:match("^ok names (%d+)")
end
local function dispel_exists(name) -- an effect row exists (a dispel to swap in proves by reading, as bosses.lua's)
  local dt, rs = row_struct(EFFECT)
  if not dt then return false end
  local off
  for _, f in pairs(row_fields(rs)) do if f.off and (not off or f.off < off) then off = f.off end end
  if not off then return false end
  local idx = name_idx(name)
  if not idx then return false end
  local r = ctx.gore and ctx.gore.command(string.format("d%x,%x,%x,0,%x", addr(dt), addr(rs), idx, off - off % 4)) or ""
  return r:match("^ok row") ~= nil
end
local function hostile_patch(row) -- the row hostile to Eve while one's up; nil ok, else why not
  if hos.rows[row] then return nil end
  if not (ctx.gore and ctx.gore.native_state() == "ready") then return "sbslice.dll isn't up yet" end
  local dt, rs = row_struct()
  if not dt then return "no CharacterTable loaded" end
  local fs = row_fields(rs)
  local was, out = { u32 = {} }, {}
  local function save_byte(f, off, byte) -- one byte written in its aligned 4, the old 4 kept for the put-back
    local at = off - off % 4
    local old = row_u32(row, at)
    if not old then return false end
    local new = old & ~(0xff << (off % 4 * 8)) | (byte & 0xff) << (off % 4 * 8)
    if new ~= old and not row_u32(row, at, new) then return false end
    was.u32[at] = old
    return true
  end
  -- damageable (an ally takes nothing while she lives: bApplyDamageWhenPlayerAlive false, the angels)
  local df = fs.bApplyDamageWhenPlayerAlive
  if df and df.off then
    if save_byte("bApplyDamageWhenPlayerAlive", df.off, 1) then out[#out + 1] = "damageable" end
  end
  -- the hostile flag, when the row names one: a plain byte (an enum or a byte), or a single-bit bool. Anything
  -- else is left alone (a bitfield's neighbours are not ours to clear)
  local hf = fs.bIsHostile
  if hf and hf.off then
    if hf.cls == "ByteProperty" or hf.cls == "EnumProperty" then
      if save_byte("bIsHostile", hf.off, 1) then out[#out + 1] = "hostile" end
    elseif hf.cls == "BoolProperty" and hf.mask and hf.mask ~= 0 and (hf.mask & (hf.mask - 1)) == 0 then
      local bit, m = 0, hf.mask
      while m > 1 do m = m >> 1; bit = bit + 1 end
      local at = hf.off - hf.off % 4
      local old = row_u32(row, at)
      if old then
        local new = old | (1 << (hf.off % 4 * 8 + bit))
        if (new ~= old and row_u32(row, at, new) or new == old) then
          was.u32[at] = old; out[#out + 1] = "hostile"
        end
      end
    else
      out[#out + 1] = "bIsHostile left (" .. tostring(hf.cls) .. ")"
    end
  end
  -- its immortality dispelled (a row that lists none stays as it is)
  local ef = fs.DefaultEffectArray
  if ef and ef.off and dispel_exists("Passive_Immortal_Dispel") then
    local n = swap_effect(row, rs, ef.off, "Passive_Immortal", "Passive_Immortal_Dispel")
    if n and n ~= "0" then was.immortal = true; out[#out + 1] = "not immortal" end
  end
  if not (next(was.u32) or was.immortal) then return "nothing to change (" .. table.concat(out, ", ") .. ")" end
  hos.rows[row] = { dt = addr(dt), was = was }
  log(string.format("%s's row hostile while one spawned here is up: %s", row, table.concat(out, ", ")))
  return nil
end
local function hostile_unpatch(row, why)
  local st = hos.rows[row]
  hos.rows[row] = nil
  if not st then return end
  local dt, rs = row_struct()
  if not (dt and addr(dt) == st.dt) then log(string.format("%s: its table is gone (%s), nothing to put back", row, why)); return end
  local fs = row_fields(rs)
  local ef = fs.DefaultEffectArray
  local n = 0
  for at, v in pairs(st.was.u32) do if row_u32(row, at, v) then n = n + 1 end end
  if st.was.immortal and ef and ef.off then
    if swap_effect(row, rs, ef.off, "Passive_Immortal_Dispel", "Passive_Immortal") then n = n + 1 end
  end
  log(string.format("%s's row put back as the game has it (%s): %d fields", row, why, n))
end
local function force_target(e, who) -- its blackboard's target keys kept on who (Eve, or another spawn for infight)
  local bb = M.after_bb(e.obj)
  if not bb then return false end
  local did = false
  for _, nm in ipairs(M.after_keys(bb)) do
    if nm:find("Target", 1, true) then
      local cur = try(function() return bb:GetValueAsObject(FName(nm)) end)
      if (not cur and who) or (cur and who and addr(cur) ~= addr(who)) then
        if try(function() bb:SetValueAsObject(FName(nm), who); return true end) then did = true end
      end
    end
  end
  return did
end
function M.hostile_tick(pawn)
  if os.clock() < hos.next then return end
  hos.next = os.clock() + 0.25
  local g = spcfg()
  local mode = g.hostile or "game"
  if mode ~= "hostile" and mode ~= "passive" then mode = "game" end
  if mode ~= "hostile" then hos.logged = {} end
  local live = {}
  for a, e in pairs(known) do
    if mine[a] and not e.dead and valid(e.mesh) then live[#live + 1] = { a = a, e = e } end
  end
  -- rows wanted hostile now (a spawn's own kind row, never a story fight's: only spawned here are counted)
  local need = {}
  if mode == "hostile" then
    for _, x in ipairs(live) do
      local r = x.e.kind.row or (not x.e.kind.custom and x.e.kind.alias)
      if r then need[r] = true end
    end
  end
  for row in pairs(need) do
    if not hos.rows[row] and not hos.logged[row] then
      local why = hostile_patch(row)
      if why then hos.logged[row] = true; log(string.format("hostile: %s: %s", row, why)) end
    end
  end
  for row in pairs(hos.rows) do if not need[row] then hostile_unpatch(row, "none spawned here left") end end
  for _, x in ipairs(live) do
    local a, e = x.a, x.e
    if mode == "passive" then
      local o = e.obj
      local ctl = try(function() return o.Controller end)
      if not valid(ctl) then ctl = nil end
      local own = try(function() return o.BrainComponent end)
      if not valid(own) then own = nil end
      local held = hos.stopped[a]
      local running = own and try(function() return own:IsRunning() end)
      if own and running ~= false then try(function() own:StopLogic("SBGore passive") end) end
      if ctl then
        local b = try(function() return ctl.BrainComponent end)
        if valid(b) and b ~= own then try(function() b:StopLogic("SBGore passive") end) end
        try(function() ctl:StopMovement() end)
        try(function() ctl:UnPossess() end)
      end
      if ctl or running == true or not held then
        try(function() e.mesh:GetAnimInstance():Montage_Stop(0.25, nil) end)
        try(function() o.CharacterMovement:StopMovementImmediately() end)
      end
      if not held and (ctl or own) then
        hos.stopped[a] = { ctl = ctl, own = own }
        log(string.format("passive: %s %x: its AI stopped, it never fights", e.kind.alias, a))
      elseif held then
        if ctl then held.ctl = ctl end
        if own then held.own = own end
      end
    elseif hos.stopped[a] then
      local held = hos.stopped[a]
      hos.stopped[a] = nil
      local ctl = try(function() return e.obj.Controller end)
      if not valid(ctl) and valid(held.ctl) then try(function() held.ctl:Possess(e.obj) end) end
      local b = valid(held.ctl) and try(function() return held.ctl.BrainComponent end)
      if valid(b) then try(function() b:RestartLogic() end) end
      if valid(held.own) and held.own ~= b then try(function() held.own:RestartLogic() end) end
      log(string.format("%s %x: its AI started again", mode, a))
    end
  end
  if mode == "hostile" then
    table.sort(live, function(x, y) return x.a < y.a end)
    local fight = g.infight == true and #live > 1
    for i, x in ipairs(live) do
      local who = fight and live[i % #live + 1].e.obj or pawn
      if who and force_target(x.e, who) and not hos.setLogged then
        hos.setLogged = true
        log(string.format("hostile: spawned NPCs target %s now", fight and "each other (infight)" or "Eve"))
      end
    end
  else
    hos.setLogged = nil
  end
end
function M.hostile_rows() return hos.rows end

-- the level reloaded: everything of the old world is dropped without touching it (gore.forget drops the gore)
function M.forget()
  known, mine, expect, hand = {}, {}, {}, {}
  angelCache, angelKind = {}, nil
  if angelKept then
    if ctx.bosses and ctx.bosses.unkeep_despawn then pcall(ctx.bosses.unkeep_despawn, angelKept, "level reloaded") end
    angelKept = nil
  end
  angelRetry = 0
  -- (after death's swings, attacks and tree nodes were the old level's, by address: a swing still on would be given back
  -- to a freed mesh, IsValid reading it, once a new enemy took its address. Dropped without touching them; the trees
  -- are looked up again in the new level. Nodes it changed that outlive the level, their tree asset kept loaded, are
  -- put back first: asked by index, the freed ones aren't read)
  if aft.tasks then
    local ok, back = pcall(after_putback)
    log(string.format("after death: the level reloaded while it was on: %s decision nodes put back", ok and tostring(back) or ("? (" .. tostring(back) .. ")")))
  end
  aft.keys, aft.tasks, aft.undo, aft.sets, aft.overSince, aft.deferUntil, aft.deferTicks = {}, nil, nil, 0, nil, nil, nil
  grab.on, grab.pawn, grab.mesh = {}, nil, nil
  aft.sw, aft.swings, aft.near, aft.anims, aft.scan, aft.loaded, aft.checked = {}, 0, nil, {}, nil, nil, nil
  down.done, down.next, down.pending = {}, 0, {}
  for row in pairs(hos.rows) do hostile_unpatch(row, "level reloaded") end
  hos.stopped, hos.logged, hos.setLogged, hos.next = {}, {}, nil, 0
  freed = false
end

return M
