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
-- Spawner (only with settings.lua's dev on): F5 spawns the kind picked (Shift+F5 picks the next) in front of her, Shift+F6 opens the spawner window
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
-- seconds of her hand kept: a kill is seen when its ragdoll starts, which comes a while after the blow that killed it
-- (the death show's hit pause and stagger first); the swing is looked for round the hit, not in the last swingWindow
local HAND_S = 1.5

local known = {}     -- actor address -> { obj, mesh, cls, kind, dead, t, hit, cut, hits, still, sm }
local mine = {}      -- actor address -> true: spawned here (Remove all takes them)
local expect = {}    -- { kind, at, t }: spawn requests waiting for their actor
local pick = 1       -- the kind F5 spawns
local hand = {}      -- Eve's right hand, the last HAND_S seconds: { t, p }
local n = 0
local freed = false  -- the mouse is given to the spawner window

local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local function sub(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function cross(a, b) return vec(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
local function len(a) return math.sqrt(dot(a, a)) end
local function unit(a) local l = len(a); return l > 1e-6 and vec(a.X / l, a.Y / l, a.Z / l) or nil end
local function vof(v) return v and vec(v.X, v.Y, v.Z) or nil end
local function v3(v) return v and string.format("(%.0f %.0f %.0f)", v.X, v.Y, v.Z) or "(?)" end
local function addr(o) return try(function() return o:GetAddress() end) end
local function bone_loc(mesh, b) return try(function() return vof(mesh:GetSocketLocation(FName(b))) end) end

local function kinds() return cfg().kinds or {} end
-- a kind's Blueprint class name: the asset's name with _C
local function class_of(k) return (k.bp or ""):match("([^/]+)$") .. "_C" end
local byClass, byClassFor = nil, nil
local function kind_of(cls)
  if byClassFor ~= cfg().kinds then
    byClass, byClassFor = {}, cfg().kinds
    for _, k in ipairs(kinds()) do byClass[class_of(k)] = k end
  end
  return byClass[cls]
end

-- the spawner window's list (spawner.c reads it whenever it opens)
local function write_list()
  local f = io.open(LIST, "w")
  if not f then return end
  for i, k in ipairs(kinds()) do f:write(string.format("%s\t%d. %s\n", k.alias, i, k.label or k.alias)) end
  f:close()
end

function M.init(c)
  ctx, try, valid = c, c.try, c.valid
  write_list()
end
function M.reload() write_list(); byClassFor = nil end

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
  local ok_n = 0
  for i = 1, count do
    local off = (i - (count + 1) / 2) * spread
    local p = vec(at.X + fwd.X * d + right.X * off, at.Y + fwd.Y * d + right.Y * off, at.Z + (cfg().spawnLift or 30))
    local r = { Pitch = 0, Yaw = math.deg(yaw) + 180, Roll = 0 }
    local ok, err = pcall(function()
      pc:ServerRequest_CreateActor(k.id, p, r, false, true, 0, 0, 0, FName("None"), false)
    end)
    if ok then
      ok_n = ok_n + 1
      expect[#expect + 1] = { kind = k, at = p, t = os.clock() }
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
    if e and e.cut and ctx.gore then ctx.gore.enemy_gone(a, e.mesh, nil) end
    known[a] = nil
    if obj and valid(obj) and try(function() return obj.bActorIsBeingDestroyed end) == false then
      if try(function() obj:K2_DestroyActor(); return true end) then nr = nr + 1 end
    end
  end
  mine, expect = {}, {}
  log(string.format("removed %d spawned enemies", nr))
end

function M.spawn_pick(pawn)
  local k = kinds()[pick]
  if not k then log("F5: no kinds in tune.enemies.kinds"); return end
  spawn(pawn, k, 1)
end
function M.next_pick()
  local ks = kinds()
  if #ks == 0 then return end
  pick = pick % #ks + 1
  log(string.format("Shift+F5: F5 now spawns %d of %d, %s (%s)", pick, #ks, ks[pick].label or ks[pick].alias, ks[pick].alias))
end
function M.toggle_window()
  local f = io.open(CMD, "w")
  if f then f:write("toggle"); f:close() end
  write_list()
  log("Shift+F6: spawner window toggled (sbslice.dll shows it)")
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

local function simulating(e) return try(function() return e.mesh:IsSimulatingPhysics(FName("Bip001-Pelvis")) end) == true end
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
  -- one the spawner asked for: it can be removed again
  for i = #expect, 1, -1 do
    local x = expect[i]
    if os.clock() - x.t > 10 then table.remove(expect, i)
    elseif x.kind == k then
      local l = try(function() return vof(o:K2_GetActorLocation()) end)
      if l and len(sub(l, x.at)) < 800 then mine[a] = true; table.remove(expect, i); break end
    end
  end
  ;(mine[a] and log or vlog)(string.format("following %s %x (%s)%s%s", k.alias, a, cls, mine[a] and ", spawned here" or "",
    e.slice ~= nil and string.format(", its own slicer %s -> off", tostring(e.slice)) or ""))
  return e
end

-- how: nil (the corpse is still there), "destroyed" (being destroyed) or "vanished" (see gore.enemy_gone)
local function gone(a, e, how, why)
  known[a] = nil
  if e.cut and ctx.gore then try(function() ctx.gore.enemy_gone(a, e.mesh, how) end) end
  if e.cut then log(string.format("%s %x %s: its gore removed", e.kind.alias, a, why)) end
end

-- the kill: its cut, once gore is free (one cut opens at a time), tried for killWait seconds. What it waited for is
-- moved on with the body (its pelvis when it was asked and now): a corpse cut after another's flew on meanwhile, and
-- the blade's plane was left where it had been
local function try_cut(pawn, a, e)
  local r = e.want
  if not r then return end
  if os.clock() - r.t > (cfg().killWait or 2.0) then
    log(string.format("%s %x: its cut never started (another kept gore busy)", e.kind.alias, a))
    e.want = nil
    return
  end
  if ctx.gore.busy() then return end
  local pel = r.pel and bone_loc(e.mesh, "Bip001-Pelvis")
  if pel then
    local d = sub(pel, r.pel)
    local function mv(v) return v and vec(v.X + d.X, v.Y + d.Y, v.Z + d.Z) end
    r.loc = mv(r.loc)
    if r.h then r.h.loc = mv(r.h.loc) end
    r.pel = pel
  end
  local got = ctx.gore.enemy_cut(a, e.obj, e.mesh, r.h, r.kind, e.kind.face)
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
      if not r.tried[k] then r.kind = k; got = ctx.gore.enemy_cut(a, e.obj, e.mesh, h, k, e.kind.face); if got then break end; r.tried[k] = true end
    end
  end
  if got or ctx.gore.busy() then
    e.cut = true
    e.cuts = e.cuts + 1
    if r.loc then ctx.gore.enemy_hit(a, e.obj, e.mesh, r.loc) end
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

-- the spawner's Kill nearest (and Ctrl+F6): the followed character nearest her goes down as a ragdoll, which the
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
  local e = best
  try(function() e.obj.CharacterMovement:DisableMovement() end)
  try(function() e.obj.CapsuleComponent:SetCollisionEnabled(0) end)
  try(function() e.mesh:SetCollisionProfileName(FName("Ragdoll"), true) end)
  try(function() e.mesh:SetAllBodiesSimulatePhysics(true) end)
  try(function() e.mesh:WakeAllRigidBodies() end)
  -- knocked away from her
  local p = bone_loc(e.mesh, "Bip001-Spine2")
  local d = p and unit(vec(p.X - her.X, p.Y - her.Y, 0))
  if d then try(function() e.mesh:AddImpulseToAllBodiesBelow(vec(d.X * 350, d.Y * 350, 120), FName("Bip001-Pelvis"), true, true) end) end
  log(string.format("kill: %s %x, %.0f cm off, ragdolled", e.kind.alias, ba, bd))
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
    local ok, err = pcall(NotifyOnNewObject, "/Script/SB.SBBTDecorator_SbCheckActorEffect", function(o)
      if down.mode then down.pending[#down.pending + 1] = { k = ctx.keep(o), t = os.clock() + 1 } end
    end)
    if not ok then log("enemies: knockdown checks not watched: " .. tostring(err)) end
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
  if #batch > 0 and not ctx.alive_ask(ks) then
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
      local d1, n1 = attack_down(mode, { k.obj }, true)
      down.nd, down.nn = (down.nd or 0) + d1, (down.nn or 0) + n1
    end
  end
  if #down.pending == 0 and (down.nd or 0) > 0 then
    log(string.format("%s: %d knockdown checks in %d of the enemies' decision nodes", LOG[mode], down.nn, down.nd))
    down.nd, down.nn = 0, 0
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

-- every tick of hers (main.lua), pawn and mesh hers
-- tm: main.lua's slow tick marker (the enemies' step was 47-174 ms now and then, playtest)
function M.tick(pawn, mesh, tm)
  tm = tm or function() end
  n = n + 1
  down_tick()
  tm("enemies attack-down")
  if n % 8 == 0 and ctx.tune.dev then read_req(pawn); read_state(pawn) end
  tm("enemies dev reads")
  smooth_tick()
  tm("enemies smooth")
  local g = cfg()
  local gore = ctx.gore
  -- the cuts, or only the death's push (cuts off: the ragdolls still get it)
  local cuts = g.enabled ~= false and gore and (ctx.tune.gore or {}).enabled ~= false
  local pushes = (tonumber(g.push) or 0) > 0 or (tonumber(g.pushScale) or 1) ~= 1
  if not (cuts or pushes) then return end
  if cuts then track_hand(pawn, mesh) end
  tm("enemies hand")
  local her = try(function() return vof(pawn:K2_GetActorLocation()) end)
  local seen = {}
  for _, c in ipairs(ctx.live_chars()) do
    local k = kind_of(c.cls)
    if k then
      seen[c.addr] = true
      local e = known[c.addr]
      if e and e.obj ~= c.obj and addr(e.obj) ~= c.addr then e = nil end
      -- (an actor being destroyed stays in the list until the next GC: a removed spawn was adopted again every tick)
      if not e and not dying(c.obj) then e = adopt(c.obj, c.addr, c.cls, k, cuts) end
      if e then e.k = c.k end
      if e then
        if try(function() return e.obj.bActorIsBeingDestroyed end) ~= false then
          gone(c.addr, e, "destroyed", "destroyed")
        elseif not valid(e.mesh) then
          gone(c.addr, e, "destroyed", "lost its mesh")
        else
          local sim = simulating(e)
          local pel = bone_loc(e.mesh, "Bip001-Pelvis")
          local near = her and pel and len(sub(pel, her)) < (g.reach or 2500)
          if not e.dead then
            if near then poll_hit(e) end
            if sim and not hidden(e) then
              e.dead, e.t, e.still, e.looks = true, os.clock(), 0, looks(e.mesh)
              if near and pushes then death_push(pawn, e, pel) end
              local cut_now = cuts and near and math.random() <= (g.cutChance or 1.0)
              local corpses = 0
              for _, x in pairs(known) do if x.cut then corpses = corpses + 1 end end
              if cut_now and corpses >= (g.maxCorpses or 6) then
                log(string.format("%s %x died: %d cut corpses already (maxCorpses), left whole", k.alias, c.addr, corpses))
                cut_now = false
              end
              if cut_now then
                local h = kill_blow(pawn, e)
                e.want = { t = os.clock(), h = h.loc and h or nil, kind = roll_kind(), loc = h.loc, what = "killed", pel = pel,
                  src = string.format("blow %s at %s", h.src, v3(h.loc)) }
              end
            end
          else
            if hidden(e) then
              gone(c.addr, e, nil, "hidden (back in its pool)")
              seen[c.addr] = nil
            elseif not sim then
              -- up again (its death undone, or the actor reused): after a second of not simulating
              e.still = e.still + TICK_S
              if e.still > 1.0 then
                gone(c.addr, e, nil, "up again")
                seen[c.addr] = nil
              end
            else
              e.still = 0
              if e.scaleAt and os.clock() >= e.scaleAt then scale_push(e) end
              if not e.faded and n % 4 == 0 then
                local yes, now = dissolving(e)
                if yes then
                  e.faded, e.want = true, nil
                  if e.cut and gore then gore.enemy_fading(c.addr) end
                  log(string.format("%s %x dissolving (%s)%s", e.kind.alias, c.addr, now, e.cut and ": its caps and bleeds removed" or ""))
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
  -- gone from the characters list (its object went): its gore without touching it
  for a, e in pairs(known) do
    if not seen[a] then gone(a, e, "vanished", "gone") end
  end
end

-- the level reloaded: everything of the old world is dropped without touching it (gore.forget drops the gore)
function M.forget()
  known, mine, expect, hand = {}, {}, {}, {}
  down.done, down.next, down.pending = {}, 0, {}
  freed = false
end

return M
