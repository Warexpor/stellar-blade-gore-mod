-- Fallback for the Juggernaut's scripted grab: its animation contains three
-- impact cues, but its hits may not update Eve's PhysicalHitForce fields.
return function(ctx, get_pawn, get_gore, is_active, recent_pound, note_pound, try, valid, log)
local M = {}
local TIMES = { 1.565, 2.055, 2.82 }
local ANIM = "Hit_SkullJuggernaut_Beta_Grab"
local function unwrap(p) return try(function() return p:get() end) end
local function address(o) return valid(o) and try(function() return o:GetAddress() end) end
local function text(v)
  if type(v) == "string" then return v end
  return v and (try(function() return v:GetFName():ToString() end)
    or try(function() return v:ToString() end)) or nil
end
function M.start(actorParam, animParam)
  local actor = unwrap(actorParam)
  local pawn = get_pawn()
  local a = address(actor)
  if not (a and a == address(pawn)) then return end
  local anim = text(unwrap(animParam))
  if not (anim and anim:match("[/%.]?" .. ANIM .. "$")) then return end
  if is_active() then return end
  -- Duplicate callbacks for the same animation must not restart its clock.
  if M.run and M.run.pawn == a and os.clock() - M.run.started < 0.25 then return end
  local gameTime = try(function() return pawn:GetGameTimeSinceCreation() end)
  M.run = { pawn = a, started = os.clock(), last = os.clock(), lastGame = type(gameTime) == "number" and gameTime or nil,
    elapsed = 0, next = 1 }
  log("Juggernaut grab: player animation detected; watching its impact cues")
end
function M.tick(pawn, mesh)
  local r, gore = M.run, get_gore()
  if not r then return end
  local g = ctx.tune.gore or {}
  if is_active() or address(pawn) ~= r.pawn or not valid(mesh) or not gore
    or g.enabled == false or (g.smash or {}).enabled ~= true or (g.smash or {}).grabPounds == false then
    M.run = nil; return
  end
  local now = os.clock()
  local dt = math.max(0, now - r.last); r.last = now
  -- Large wall-clock gaps are commonly pauses/loading; never manufacture a burst of old hits.
  if dt > 0.5 then M.run = nil; return end
  -- The grab show itself changes global time dilation. Game time follows those
  -- changes; the mod's own slow-motion flag alone does not.
  local gameTime = try(function() return pawn:GetGameTimeSinceCreation() end)
  if r.lastGame and type(gameTime) == "number" then
    local gameDt = gameTime - r.lastGame
    if gameDt < 0 then M.run = nil; return end
    r.elapsed, r.lastGame = r.elapsed + gameDt, gameTime
  else
    r.lastGame = type(gameTime) == "number" and gameTime or nil
    local scale = (ctx.time_scale and ctx.time_scale()) or 1
    r.elapsed = r.elapsed + dt * math.max(0, scale)
  end
  -- Only trust alpha as an interruption signal if this build actually reported it active.
  local alpha = try(function() return pawn:GetCurrentCustomAnimAlpha(0) end)
  if type(alpha) == "number" and alpha > 0.1 then r.seenAlpha = true
  elseif r.seenAlpha and type(alpha) == "number" and alpha <= 0.01 then M.run = nil; return end
  local when = TIMES[r.next]
  if not when then M.run = nil; return end
  if r.elapsed < when then return end
  if r.elapsed - when > 0.3 then r.next = r.next + 1; return end
  if recent_pound() then r.next = r.next + 1; return end
  if gore.busy() then return end
  local loc = try(function() local p = mesh:GetSocketLocation(FName("Bip001-Spine2")); return { X = p.X, Y = p.Y, Z = p.Z } end)
  r.next = r.next + 1
  if not loc then return end
  local ok, made = pcall(gore.smash, pawn, mesh,
    { t = now, loc = loc, grabPound = true, attacker = "CH_M_NA_15_Blueprint_C", src = "Juggernaut grab animation" }, "grab")
  if not ok then log("Juggernaut grab: impact failed: " .. tostring(made))
  elseif made then note_pound(now); log(string.format("Juggernaut grab: animation impact %d smashed a limb", r.next - 1)) end
end
return M
end
