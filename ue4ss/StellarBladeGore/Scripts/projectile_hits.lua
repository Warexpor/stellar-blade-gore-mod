-- Projectile evidence, impact geometry and rock correction; queueing stays in the death lifecycle.
return function(sw, hm, get_pawn, get_gore, get_mesh_hit, try, valid, vof, len, dist, v3, log)
-- Equivalent circular cross-section from the two short half-extents. A shaft's length alone is
-- never treated as a broad striking face. Called on weapon discovery or projectile impact only.
function sw.cross_radius(extent, scale)
  if not extent then return nil end
  local axes = { math.abs(extent.X * (scale and scale.X or 1)), math.abs(extent.Y * (scale and scale.Y or 1)),
    math.abs(extent.Z * (scale and scale.Z or 1)) }
  for _, n in ipairs(axes) do if n ~= n or n == math.huge or n <= 0 then return nil end end
  table.sort(axes)
  return math.min(500, math.sqrt(axes[1] * axes[2]))
end
function sw.impact_radius(obj, component)
  local function shape(c)
    if not valid(c) then return nil end
    for _, method in ipairs({ "GetScaledSphereRadius", "GetScaledCapsuleRadius" }) do
      local r = try(function() return c[method](c) end)
      if type(r) == "number" and r == r and r > 0 and r < math.huge then return math.min(500, r), "collision radius" end
    end
    local extent = try(function() return vof(c:GetScaledBoxExtent()) end)
    local r = extent and sw.cross_radius(extent)
    if r then return r, "box cross-section" end
    extent = try(function() return vof(c.StaticMesh:GetBounds().BoxExtent) end)
      or try(function() return vof(c.SkeletalMesh:GetImportedBounds().BoxExtent) end)
    r = extent and sw.cross_radius(extent, try(function() return vof(c:K2_GetComponentScale()) end))
    if r then return r, "mesh cross-section" end
  end
  local radius, source = shape(component)
  if radius then return radius, source end
  if not valid(obj) then return nil end
  radius, source = shape(try(function() return obj.PhysicsShapeComponent end))
  if radius then return radius, source end
  local count = 0
  try(function() obj.CollisionGroupComponent.CreatedShapeComponent:ForEach(function(_, item)
    count = count + 1
    if count > 8 then return end
    local r, src = shape(item:get())
    if r and (not radius or r > radius) then radius, source = r, src end
  end) end)
  if radius then return radius, source end
  return shape(try(function() return obj.RootComponent end))
end
function sw.impact_pose(mesh, key)
  local gore = get_gore()
  local r = sw.rockLast
  if r and r.pose and r.key == key and r.mesh == mesh:GetAddress()
    and os.clock() >= r.t and os.clock() - r.t < 0.05 then return r.pose end
  return gore and gore.pose and try(function() return gore.pose(mesh) end)
end
-- The native projectile result carries the actual target GUID and hit point for every projectile type
-- that uses this broadcast. Ignore misses, blocks and other targets; never infer one from proximity.
function sw.projectile_event(_, _turn, projectile, target, _alias, result, location, _normal, bone, direction)
  local function val(p) return try(function() return p:get() end) end
  local pawn = get_pawn()
  local mine = pawn and try(function() return pawn.BroadcastSpawnInfo.ActorGuid end)
  local id, who, kind = val(projectile), val(target), val(result)
  if type(mine) ~= "number" or mine == 0 or who ~= mine or type(id) ~= "number" or id == 0 or kind ~= 1 then return end
  local loc, dir = try(function() return vof(val(location)) end), try(function() return vof(val(direction)) end)
  if not loc then return end
  if not dir or len(dir) < 1e-3 then dir = { X = 0, Y = 0, Z = -1 } end
  local bn = try(function() return val(bone):ToString() end)
  local mesh = pawn and try(function() return pawn.Mesh end)
  sw.projectile_record({ t = os.clock(), loc = loc, dir = dir, push = dir, bone = bn,
    projectile = true, src = "projectile hit result", id = id,
    pose = valid(mesh) and sw.impact_pose(mesh, "id:" .. tostring(id)) or nil }, "id:" .. tostring(id))
end
-- Single-player collision callbacks can run without a network broadcast. Require Eve as the actual target.
function sw.projectile_collision(context, component, other, _othercomp, a, b, sweep)
  local pawn = get_pawn()
  local target = try(function() return other:get() end)
  local pa = pawn and try(function() return pawn:GetAddress() end)
  local ta = target and try(function() return target:GetAddress() end)
  if not (pa and ta and pa == ta) then return end
  local obj = try(function() return context:get() end)
  local hit = try(function() return sweep:get() end) or try(function() return b:get() end)
  local loc = hit and (try(function() return vof(hit.ImpactPoint) end) or try(function() return vof(hit.Location) end))
  if not loc or len(loc) < 1 then loc = obj and try(function() return vof(obj:K2_GetActorLocation()) end) end
  if not loc then return end
  local dir = obj and try(function() return vof(obj:GetVelocity()) end)
  if not dir or len(dir) < 1e-3 then dir = { X = 0, Y = 0, Z = -1 } end
  local key = obj and try(function() return "object:" .. tostring(obj:GetAddress()) end)
  local radius, source = sw.impact_radius(obj, try(function() return component:get() end))
  local mesh = pawn and try(function() return pawn.Mesh end)
  sw.projectile_record({ t = os.clock(), loc = loc, dir = dir, push = dir, projectile = true, src = "projectile collision",
    impactRadius = radius, impactSizeSource = source,
    pose = valid(mesh) and sw.impact_pose(mesh, key) or nil }, key)
  log("projectile collision on Eve at " .. v3(loc))
end
function sw.projectile_hit()
  local h = sw.projectileLast
  if h and os.clock() - h.t >= 0 and os.clock() - h.t <= 0.6 then return h end
end
-- Some kills report a projectile only in ActorDead, without a separate hit result.
function sw.death_projectile(mesh)
  local meshHit = get_mesh_hit()
  local d = hm.deadMsg
  if not (d and os.clock() - d.t >= 0 and os.clock() - d.t <= 1 and type(d.proj) == "number"
    and d.proj > 0 and d.proj < 0xffffffff and not (hm.FALL_FX and hm.FALL_FX[d.effect or -1])) then return nil end
  local m = meshHit and math.abs(meshHit.t - d.t) < 0.6 and meshHit or nil
  local loc = m and m.loc or try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Spine1"))) end)
  if not loc then return nil end
  local dir = m and m.push or { X = 0, Y = 0, Z = -1 }
  return { t = d.t, loc = loc, dir = dir, push = dir, projectile = true, src = "death projectile ID", id = d.proj }
end
-- The Gorilla B throws a large rock whose shake position can be well below its visible impact. Its two known
-- projectile blueprints expose EventOnHit with a world-space hit location. Watch the native base so their hooks are
-- installed as the classes load; never infer a rock from the enemy name or a random synthetic swing.
sw.rockHooks, sw.rockLast = {}, nil
function sw.rock_event(pawn, context, location, result)
  local gore = get_gore()
  local kind = result and try(function() return result:get() end)
  if kind ~= nil and kind ~= 1 then return end
  local at = try(function() return vof(location:get()) end)
  local mesh = pawn and try(function() return pawn.Mesh end)
  local pelvis = valid(mesh) and try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Pelvis"))) end)
  if at and pelvis and dist(at, pelvis) < 200 then
    local obj = try(function() return context:get() end)
    local radius, source = sw.impact_radius(obj)
    sw.rockLast = { t = os.clock(), loc = at, mesh = mesh:GetAddress(),
      key = obj and try(function() return "object:" .. tostring(obj:GetAddress()) end),
      impactRadius = radius, impactSizeSource = source,
      pose = gore and gore.pose and try(function() return gore.pose(mesh) end) }
    log("rock projectile hit near Eve at " .. v3(at))
  end
end
function sw.rock_watch(o)
  local cls = try(function() return o:GetClass():GetFName():ToString() end)
  if cls ~= "M_GorillaB_S18_ThrowStone_Projectile1_C" and cls ~= "M_GorillaB_S18_ThrowStone2_Projectile1_C" then return end
  if sw.rockHooks[cls] then return end
  local asset = cls:sub(1, -3)
  local path = "/Game/Art/Character/Monster/CH_M_NA_05/Projectile/" .. asset .. "." .. cls .. ":EventOnHit"
  local ok, err = pcall(RegisterHook, path, function(...) local success, why = pcall(sw.rock_event, ...); if not success then log("rock hit hook: " .. tostring(why)) end end)
  if ok then sw.rockHooks[cls] = true end
  log("hook rock " .. cls .. ": " .. (ok and "ok" or tostring(err)))
end
-- Blueprint projectile hit events may execute without either native collision callback or the
-- network broadcasts. The event has no target argument, so require a successful hit close to Eve.
sw.projectileHooks = {}
function sw.projectile_blueprint_event(pawn, context, location, result)
  local kind = try(function() return result:get() end)
  local at = try(function() return vof(location:get()) end)
  local mesh = pawn and try(function() return pawn.Mesh end)
  if kind ~= 1 or not at or not valid(mesh) then return end
  local obj = try(function() return context:get() end)
  local cls = obj and try(function() return obj:GetClass():GetFName():ToString() end) or ""
  if cls:sub(1, 6) == "P_Eve_" then return end
  local near
  for _, bone in ipairs({ "Bip001-Head", "Bip001-Spine2", "Bip001-Spine1", "Bip001-Pelvis", "Bip001-L-Thigh", "Bip001-R-Thigh" }) do
    local p = try(function() return vof(mesh:GetSocketLocation(FName(bone))) end)
    local d = p and dist(at, p)
    if d and (not near or d < near) then near = d end
  end
  if not near or near > 45 then return end
  local dir = { X = 0, Y = 0, Z = -1 }
  local key = obj and try(function() return "object:" .. tostring(obj:GetAddress()) end)
  local radius, source = sw.impact_radius(obj)
  sw.projectile_record({ t = os.clock(), loc = at, dir = dir, push = dir, projectile = true, src = "projectile blueprint hit",
    impactRadius = radius, impactSizeSource = source, pose = sw.impact_pose(mesh, key) }, key)
  log(string.format("projectile blueprint hit %.0f cm from Eve at %s (%s)", near, v3(at), key or "identity unavailable"))
end
function sw.projectile_watch(o)
  sw.rock_watch(o)
  local full = try(function() return o:GetClass():GetFullName() end)
  local path = type(full) == "string" and full:match(" (%/Game/%S+_C)$")
  if not path or sw.projectileHooks[path] then return end
  sw.projectileHooks[path] = true
  local ok, err = pcall(RegisterHook, path .. ":EventOnHit", function(...)
    local good, why = pcall(sw.projectile_blueprint_event, ...)
    if not good then log("projectile blueprint hit hook error: " .. tostring(why)) end
  end)
  log("hook projectile blueprint " .. path .. ": " .. (ok and "ok" or tostring(err)))
end
function sw.rock_hit(mesh, m)
  local r = sw.rockLast
  if not (r and m and m.loc and math.abs(r.t - m.t) < 0.35 and os.clock() - r.t < 1 and dist(r.loc, m.loc) < 150) then return nil end
  if r.mesh and r.mesh ~= mesh:GetAddress() then return nil end
  local head = r.pose and r.pose["Bip001-Head"] and r.pose["Bip001-Head"].t
    or try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Head"))) end)
  local chest = r.pose and r.pose["Bip001-Spine2"] and r.pose["Bip001-Spine2"].t
    or try(function() return vof(mesh:GetSocketLocation(FName("Bip001-Spine2"))) end)
  if not (head and chest) then return nil end
  local hd, cd = dist(r.loc, head), dist(r.loc, chest)
  if math.min(hd, cd) > 130 then return nil end
  local loc = hd < cd and head or chest
  log(string.format("death: Gorilla rock impact %s: head %.0f cm, chest %.0f cm; target %s", v3(r.loc), hd, cd, hd < cd and "head" or "upper body"))
  return loc, r.pose
end
-- A known rock's callback and the generic projectile callback report the same low projectile origin.
-- Correct it before either lethal-watch or death selection can accept that generic packet. Keep the
-- packet identity and volley count, and compare against the impact-time pose after the ragdoll moves.
function sw.rock_blow(mesh)
  local meshHit = get_mesh_hit()
  local projectile, r = sw.projectile_hit(), sw.rockLast
  if projectile and projectile.rock then return projectile end
  if projectile and r and projectile.key and r.key and projectile.key:sub(1, 7) == "object:"
    and projectile.key ~= r.key then return nil end
  local m = meshHit and os.clock() - meshHit.t <= 1 and meshHit or projectile
  local at, pose = sw.rock_hit(mesh, m)
  if not at then return nil end
  if projectile and (math.abs(projectile.t - r.t) >= 0.35 or dist(projectile.loc, r.loc) >= 150) then return nil end
  local push = m.push or (projectile and projectile.push) or { X = 0, Y = 0, Z = -1 }
  local h = projectile or { t = r.t, src = "rock projectile", made = true }
  h.impact, h.loc, h.pose, h.rock = h.loc or r.loc, at, pose, true
  h.impactRadius, h.impactSizeSource = r.impactRadius or h.impactRadius, r.impactSizeSource or h.impactSizeSource
  h.push, h.dir = push, push
  return h
end

end
