-- Living-hit decal placement, healing, and cleanup.
-- The owner supplies live guards; these are initialized after the scripts load.
return function(M, d)
local native, cfg, log, load_obj = d.native, d.cfg, d.log, d.load_obj
local vec, sub, add, scale, len, norm, dot, cross = d.vec, d.sub, d.add, d.scale, d.len, d.norm, d.dot, d.cross
local bone_loc, command, triple, num, pick, niagara, FX = d.bone_loc, d.command, d.triple, d.num, d.pick, d.niagara, d.FX
local function try(...) local f = d.guards(); return f(...) end
local function valid(...) local _, f = d.guards(); return f(...) end
local function v3(...) local _, _, f = d.guards(); return f(...) end
local MARK_AT = d.MARK_AT
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

-- the skin under a hit (sbslice "m"): at, where the game says she was hit (world); dir, the blow's motion or nil;
-- reach, how far off her parts' bone axes the hit may lie (40 cm). A table { hit, n (unit), bone (index), part (a
-- MARK_AT row), mat (the material slot of the skin's section), u, v (its UV, channel 0) }, or nil and why. mat and
-- u / v are nil when the DLL couldn't tell (no CPU copy of the UVs)
function M.skin_query(mesh, at, dir, reach_cm)
  if native.state ~= "ready" then return nil, "sbslice not ready" end
  if not (at and valid(mesh)) then return nil, "no hit" end
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
  if not best or bd > (reach_cm or 40) then
    return nil, string.format("no part of her within %d cm of %s", reach_cm or 40, v3(at))
  end
  local out = norm(sub(at, bc)) or (dir and norm(scale(dir, -1))) or vec(1, 0, 0)
  local reach = math.min(math.max(bd + 8, 12), 30)
  local r = command(string.format("m%x,0,%x", mesh:GetAddress(), math.floor(reach + 0.5)), bc, out)
  local hit, n = triple(r, "hit", 1), triple(r, "n", 0.01)
  if r:sub(1, 2) ~= "ok" or not (hit and n) then return nil, r end
  local u, v = r:match(" uv=(%-?[%d.]+),(%-?[%d.]+)")
  return { hit = hit, n = norm(n) or out, bone = num(r, "bone"), part = best, mat = num(r, "mat"),
    u = tonumber(u), v = tonumber(v), out = num(r, "out") }
end

-- at: where the game says she was hit (world), dir: the blade's motion there (the slash runs along it), or nil;
-- pre: her HP bar before the hit (0-1), or nil. True when a mark went on
function M.hit_mark(pawn, mesh, at, dir, pre)
  local g = cfg()
  local c = g.hitMarks or {}
  if g.enabled == false or c.enabled == false or not (at and valid(mesh)) then return false end
  if native.state ~= "ready" then return false end
  local q, why = M.skin_query(mesh, at, dir, c.reach or 40)
  if not q then log("hit mark skipped: " .. why); return false end
  local best, hit, n = q.part, q.hit, q.n
  local bi = q.bone
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
  -- This flag belongs to the component, not the skeletal asset. A replacement
  -- mesh can use an already-logged asset while still having decals disabled.
  local rd = try(function() return mesh.bReceivesDecals end)
  if rd == false then try(function() mesh:SetReceivesDecals(true) end) end
  if ska and not M.decal_seen[ska] then
    M.decal_seen[ska] = true
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
    best.bone, ride, half_l * 2, half_w * 2, v3(hit), q.out or -1, string.format("%.1f cm", len(sub(hit, at))),
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


end
