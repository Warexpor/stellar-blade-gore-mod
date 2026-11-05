-- Regrowth copies, material transitions and sink cleanup.
return function(M, cfg, load_obj, get_guards, get_cuts, get_clones, get_forced, owner_of, addr, clone_of, name_of, command, log)
-- ---- a part dissolving back in (main.lua's camp rest) ----
-- The cut stays on while it comes back: on each mesh of hers it is on (her body, her face with a head) the part's
-- bodies stop simulating, so its bones are on her pose again, and the part goes out of sight on her (sbslice "V",
-- keep 0: its vertices onto a collapsed sink; another mod's copies of her mesh take those weights). A copy of the mesh
-- on her pose, its own weights with everything but the part and its seam out of sight ("V", keep 1), wears the corpse
-- dissolve (MI_DeadMaterial_*, MA_DeadMaterial_01: the despawn show runs Dissolve 0 -> 1, Morph 0 -> 1 and
-- EmissiveBright 10 -> 0) with each slot's own textures (BaseColor, BaseNormalTex, ORM), run backwards
-- (M.ghost_set). Her own materials can't dissolve: MA_Skin_EVE is opaque and cooked. At the end the cut is undone
-- (M.cleanup, which destroys the copy with its other clones). Returns the state, or nil and why
M.REGROW_MAT = "/Game/Art/FX/Char/Monster/Common/Dead/MI_DeadMaterial_LurkerA_01.MI_DeadMaterial_LurkerA_01"
-- a material's texture parameters up its parents (an instance's own first)
function M.ghost_params(mat)
  local try, valid = get_guards()
  local out, m = {}, mat
  for _ = 1, 8 do
    if not valid(m) then break end
    try(function() m.TextureParameterValues:ForEach(function(_, e)
      local p = e:get()
      local n = p.ParameterInfo.Name:ToString()
      if out[n] == nil and valid(p.ParameterValue) then out[n] = p.ParameterValue end
    end) end)
    m = try(function() return m.Parent end)
  end
  return out
end
-- by one of names, else by the texture's own name ending in one of ends (not a parameter named with skip)
function M.ghost_pick(t, names, ends, skip)
  local try, valid = get_guards()
  for _, n in ipairs(names) do if t[n] then return t[n], n end end
  for n, x in pairs(t) do
    local low = n:lower()
    local bad = false
    for _, s in ipairs(skip) do bad = bad or low:find(s, 1, true) ~= nil end
    local tn = not bad and (try(function() return x:GetFName():ToString() end) or ""):lower()
    if tn then for _, e in ipairs(ends) do if tn:sub(-#e) == e then return x, n end end end
  end
  return nil
end
M.GHOST_SKIP = { "micro", "detail", "blood", "flake", "noise", "pattern", "cosmetic", "stocking", "mask", "dirt" }
function M.ghost_begin(pawn, mesh, parts, path)
  local try, valid = get_guards()
  local mat = load_obj(path or M.REGROW_MAT)
  if not mat then return nil, "no dissolve material" end
  local meshes, seen, want = {}, {}, { face = true }
  for _, p in ipairs(parts) do want[p] = true end
  -- (her own cuts of these parts only: not an enemy's, a split's copy or a failed one)
  -- (and only what shows: another mod's meshes kept hidden on her, as CNS's body variants it switches off in its
  -- settings, came out of hiding as their copies dissolved in, reported)
  local function shown(m)
    return try(function() return m:IsVisible() end) ~= false and try(function() return m.bHiddenInGame end) ~= true
  end
  for _, c in ipairs(get_cuts()) do
    if want[c.bone] and not owner_of(c) and valid(c.mesh) and addr(c.mesh) == c.addr and not seen[c.addr] and shown(c.mesh) then
      seen[c.addr] = true
      meshes[#meshes + 1] = c.mesh
    end
  end
  local g = { list = {}, mids = {}, t0 = os.clock() }
  local function fail(why) M.ghost_end(g); return nil, why end
  for _, m in ipairs(meshes) do
    local roots = {}
    for _, p in ipairs(parts) do
      local i = try(function() return m:GetBoneIndex(FName(p)) end)
      if i and i >= 0 then roots[#roots + 1] = string.format("%x", i) end
    end
    if #roots > 0 then
      -- (her pose on the part again: it lay where it fell)
      for _, p in ipairs(parts) do try(function() m:SetAllBodiesBelowSimulatePhysics(FName(p), false, true) end) end
      local c = clone_of(pawn, m)
      if not c then return fail("no copy of " .. name_of(m)) end
      local e = { mesh = m, copy = c, hid = {} }
      g.list[#g.list + 1] = e
      -- (on her pose, its own weights: the part whole, and the band of her seam the cut collapsed; with her cut's
      -- weights copied onto it, "y", the arm dissolved in standing off her shoulder by that band, test/real REGROW)
      -- (posed by what poses m: a sleeve or glove follows her body, and a copy following it was left on its bind pose,
      -- stretched between it and her as she moved, reported)
      local lead = try(function() return m.MasterPoseComponent:Get() end)
      try(function() c:SetMasterPoseComponent(valid(lead) and lead or m, true) end)
      -- (attached to the mesh it copies: clone_of only places it where that mesh is, so a copy on her pose stood where
      -- the regrow began while she walked off, out of sight, and the arm came back at the end at once, reported)
      try(function() c:K2_AttachToComponent(m, FName("None"), 2, 2, 2, false) end)
      local vc = command(string.format("V%x,0,1,%s", addr(c), table.concat(roots, ",")))
      local vm = command(string.format("V%x,0,0,%s", addr(m), table.concat(roots, ",")))
      if vc:sub(1, 9) ~= "ok vanish" or vm:sub(1, 9) ~= "ok vanish" then return fail("vanish: copy " .. vc .. ", hers " .. vm) end
      -- (another mod's copies of her mesh on her pose: her weights now)
      M.copies_sync(m, true)
      -- sections where nothing could be hidden, whole
      local function hide(comp, r, list)
        for mi, si in (r:match(" mats (%S+)") or ""):gmatch("(%d+)/(%d+)") do
          if try(function() comp:ShowMaterialSection(tonumber(mi), tonumber(si), false, 0); return true end) and list then
            list[#list + 1] = mi .. "/" .. si
          end
        end
      end
      hide(c, vc)
      hide(m, vm, e.hid)
      local nm = try(function() return c:GetNumMaterials() end) or 0
      local looks = {}
      for i = 0, nm - 1 do
        local src = try(function() return m:GetMaterial(i) end)
        local mid = try(function() return c:CreateDynamicMaterialInstance(i, mat, FName("None")) end)
        if valid(mid) then
          g.mids[#g.mids + 1] = mid
          local t = M.ghost_params(src)
          local base, bn = M.ghost_pick(t, { "BaseColor", "Base Color", "BaseColorTex", "Basecolor_Texture", "Albedo", "Diffuse" }, { "_a", "_d", "_bc", "_basecolor", "_albedo" }, M.GHOST_SKIP)
          local nrm, nn = M.ghost_pick(t, { "BaseNormal", "BaseNormalTex", "Normal", "NormalTex", "Normal_Texture" }, { "_n", "_normal" }, M.GHOST_SKIP)
          local orm, on = M.ghost_pick(t, { "ORM", "AORM_Texture", "ORM_Tex" }, { "_orm", "_arm" }, M.GHOST_SKIP)
          if base then try(function() mid:SetTextureParameterValue(FName("BaseColor"), base); mid:SetTextureParameterValue(FName("EmissiveTex"), base) end) end
          if nrm then try(function() mid:SetTextureParameterValue(FName("BaseNormalTex"), nrm) end) end
          if orm then try(function() mid:SetTextureParameterValue(FName("ORM"), orm) end) end
          looks[#looks + 1] = string.format("%d %s<%s %s %s>", i, valid(src) and try(function() return src:GetFName():ToString() end) or "?", bn or "-", nn or "-", on or "-")
        end
      end
      log(string.format("regrow: %s dissolving back in on a copy of %s (roots %s): copy %s, hers %s; textures %s%s", table.concat(parts, ", "),
        name_of(m), table.concat(roots, ","), vc, vm, table.concat(looks, "; "), #e.hid > 0 and ", sections hidden whole on her " .. table.concat(e.hid, ",") or ""))
      M.ghost_set(g, 0)
      try(function() c:SetComponentTickEnabled(true) end)
      try(function() c:SetHiddenInGame(false, false) end)
    end
  end
  if #g.list == 0 then return nil, "no mesh of hers has the parts' bones" end
  return g
end
-- x: 0 nothing of it, 1 all of it (tune.gore.lowArm.dissolve: glow, the EmissiveBright it peaks at halfway)
function M.ghost_set(g, x)
  local try, valid = get_guards()
  local d = type((cfg().lowArm or {}).dissolve) == "table" and cfg().lowArm.dissolve or {}
  local e = x * x * (3 - 2 * x)
  local glow = (tonumber(d.glow) or 10) * 4 * x * (1 - x)
  for _, mid in ipairs(g.mids) do
    if valid(mid) then try(function()
      mid:SetScalarParameterValue(FName("Dissolve"), 1 - e)
      mid:SetScalarParameterValue(FName("Morph"), (d.morph == false) and 0 or 1 - e)
      mid:SetScalarParameterValue(FName("EmissiveBright"), glow)
      mid:SetScalarParameterValue(FName("DissolveMaskScale"), tonumber(d.maskScale) or 200)
    end) end
  end
end
-- the hand-off: her own part back under the copy (the caller undoes the cut, M.cleanup, which leaves the copies on),
-- and the copy then dissolved out over it (M.ghost_fade). Swapped in one frame, the corpse material's look at Dissolve
-- 0 jumped to her own skin's (playtest: a snap at the end). The copy's hidden side sits on a point of its own and
-- bones borrowed into the asset's BoneMaps ("V"): the cleanup's full put back (sbslice "r", which takes those too)
-- waits for M.ghost_end. Its "x" puts the cut's sinks back at once, which the copy no longer rides (on them, her whole
-- body showed round the arm on the copy as it faded: a glitchy limb right after it came back, playtest)
function M.ghost_release(g)
  local try, valid = get_guards()
  M.sinksHeld = { g = g }
  for _, e in ipairs(g.list) do
    if #e.hid > 0 and valid(e.mesh) then try(function() e.mesh:ShowAllMaterialSections(0) end) end
    e.hid = {}
    local a = addr(e.copy)
    local clones = get_clones()
    for i = #clones, 1, -1 do if addr(clones[i]) == a then table.remove(clones, i) end end
  end
end
-- y: 0 the copy whole, 1 gone; no ripple, no glow
function M.ghost_fade(g, y)
  local try, valid = get_guards()
  local d = type((cfg().lowArm or {}).dissolve) == "table" and cfg().lowArm.dissolve or {}
  local e = y * y * (3 - 2 * y)
  for _, mid in ipairs(g.mids) do
    if valid(mid) then try(function()
      mid:SetScalarParameterValue(FName("Dissolve"), e)
      mid:SetScalarParameterValue(FName("Morph"), 0)
      mid:SetScalarParameterValue(FName("EmissiveBright"), 0)
      mid:SetScalarParameterValue(FName("DissolveMaskScale"), tonumber(d.maskScale) or 200)
    end) end
  end
end
-- the copies gone and her sections shown again (the cut itself: M.cleanup), and the sinks the cleanup left for them
-- put back. Returns what was done with those, for the log ("" none held)
function M.ghost_end(g)
  local try, valid = get_guards()
  for _, e in ipairs(g.list) do
    if #e.hid > 0 and valid(e.mesh) then try(function() e.mesh:ShowAllMaterialSections(0) end) end
    local a = addr(e.copy)
    local clones = get_clones()
    for i = #clones, 1, -1 do if addr(clones[i]) == a then table.remove(clones, i) end end
    if a then get_forced()[a] = nil end
    -- V gives this copy its own skin-weight render resource, even on a partially failed regrow.
    if a and valid(e.copy) then command(string.format("x%x,0,1", a)) end
    if valid(e.copy) then try(function() e.copy:K2_DestroyComponent(e.copy) end) end
  end
  g.list, g.mids = {}, {}
  local h = M.sinksHeld
  if not (h and h.g == g) then return "" end
  M.sinksHeld = nil
  if not h.cmds or #h.cmds == 0 then return "" end
  -- (a cut of hers made while the copy faded is on those sinks now: they stay down, its own cleanup puts them back)
  for _, c in ipairs(get_cuts()) do
    if not owner_of(c) then return ", sinks kept down (a new cut of hers on them)" end
  end
  local out = {}
  for _, r in ipairs(h.cmds) do out[#out + 1] = command(r) end
  return ", sinks(" .. table.concat(out, "; ") .. ")"
end

end
