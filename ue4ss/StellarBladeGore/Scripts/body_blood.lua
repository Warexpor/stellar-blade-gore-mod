-- Player skin blood ramp and recovery.
return function(M, cfg, load_obj, get_ctx, get_guards, log, MPC_DIRTY, TICK_S)
local body_blood = nil
-- her skin's own blood layer (MPC_PCDirtyOffset): raised over tune.gore.bodyBlood.time on a death cut, put back
-- on recovery. The collection is global, so this is all of her at once, not around the cut
local function mpc_get(pawn, mpc, name)
  local try = get_guards()
  local kml = load_obj("/Script/Engine.Default__KismetMaterialLibrary")
  return kml and try(function() return kml:GetScalarParameterValue(pawn, mpc, FName(name)) end)
end
local function mpc_set(pawn, mpc, name, v)
  local try = get_guards()
  local kml = load_obj("/Script/Engine.Default__KismetMaterialLibrary")
  return kml and try(function() kml:SetScalarParameterValue(pawn, mpc, FName(name), v); return true end)
end
local function blood_up(pawn)
  local ctx = get_ctx()
  -- Blood and Dirt owns this collection. A cut must not start a competing ramp over its native skin layer.
  if (ctx.tune.stains or {}).enabled == true then body_blood = nil; return end
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
  local ctx = get_ctx()
  if (ctx.tune.stains or {}).enabled == true then body_blood = nil; return end
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
  local ctx = get_ctx()
  local b = body_blood
  body_blood = nil
  if (ctx.tune.stains or {}).enabled == true then return end
  if not b then return end
  for k, v in pairs(b.from) do if v then mpc_set(b.pawn, b.mpc, k, v) end end
  log("body blood: put back")
end

local function restore(pawn)
  if not M.blood_restore then return end
  local _, valid = get_guards()
  if not valid(pawn) then return end
  local from, mpc = M.blood_restore, load_obj(MPC_DIRTY)
  M.blood_restore = nil
  if mpc then
    local restored = {}
    for k, v in pairs(from) do if v and mpc_set(pawn, mpc, k, v) then restored[#restored + 1] = string.format("%s %s", k, tostring(v)) end end
    table.sort(restored)
    log("body blood: put back on the new Eve: " .. table.concat(restored, ", "))
  end
end
return { up = blood_up, tick = blood_tick, down = blood_down, restore = restore,
  clear = function() body_blood = nil end,
  forget = function() M.blood_restore = body_blood and body_blood.from or M.blood_restore; body_blood = nil end }
end
