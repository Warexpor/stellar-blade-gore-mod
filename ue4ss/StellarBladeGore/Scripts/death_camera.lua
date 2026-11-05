-- Held death camera and its lifetime; screen state remains shared with photo mode.
return function(screen, goreCtx, valid, try, log, lg, name, v3, dist, PELVIS, get_tune)
-- Playtest 41: the camera followed her body after an animated death went ragdoll (a split, a beheading, a leg): the
-- game moves her pawn after the ragdoll and the view rides the pawn. Nothing needs following: at a death a still
-- camera is put where the view is and made the view target, back to her at recovery (tune.cameraStill). The log says
-- where the view is against her capsule and head for 3 s
local camHeld = nil -- { pc, cam, pawn, mesh, d, pitch, yaw, t, pivot, home, from, turned, free, placed, photo, vt }
local function fwd(r)
  local p, y = math.rad(r.Pitch), math.rad(r.Yaw)
  return { X = math.cos(p) * math.cos(y), Y = math.cos(p) * math.sin(y), Z = math.sin(p) }
end
local camWatch = nil -- { t0, n }
local function camera_pelvis(h)
  return valid(h.mesh) and try(function() local v = h.mesh:GetSocketLocation(PELVIS); return { X = v.X, Y = v.Y } end)
end
-- her usual view, alive: the field of view and the camera's distance from her most of the polls had. The gun's aim
-- and a grab's close-up (a boss holding her and hitting) zoom in and come close; a death in one kept that view held
-- till she got up (playtest), so the held camera eases out to the usual one
screen.camUsual = { fov = {}, d = {}, EASE_S = 0.6 }
function screen.camera_learn(pawn)
  local camUsual = screen.camUsual
  -- (a view held most of the time: every 0.25 s is enough, five engine calls every poll were not free)
  local now = os.clock()
  if now < (camUsual.next or 0) then return end
  camUsual.next = now + 0.25
  local pcm = try(function() return pawn.Controller.PlayerCameraManager end)
  if not valid(pcm) then return end
  local f = try(function() return pcm:GetFOVAngle() end)
  local l = try(function() local v = pcm:GetCameraLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
  local c = try(function() local v = pawn:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
  local function count(t, k)
    local n = (t[k] or 0) + 1
    t[k] = n
    if not t.best or n > (t[t.best] or 0) then t.best = k end
  end
  if type(f) == "number" and f >= 20 and f <= 140 then count(camUsual.fov, math.floor(f + 0.5)) end
  if l and c then count(camUsual.d, math.floor(dist(l, c) / 10 + 0.5) * 10) end
end
local function camera_hold(pawn)
  local tune = get_tune()
  camWatch = { t0 = os.clock(), n = 0 }
  -- Customized Ragdoll's death camera instead, when that support is on and the mod is there (customrag.lua)
  if goreCtx.customrag and try(function() return goreCtx.customrag.camera_on(pawn) end) then return end
  if tune.cameraStill == false or tune.cameraFollow == true or camHeld then return end
  local gs = goreCtx.statics()
  local cls = StaticFindObject("/Script/Engine.CameraActor")
  local pc = valid(gs) and try(function() return gs:GetPlayerController(pawn, 0) end)
  local pcm = valid(gs) and try(function() return gs:GetPlayerCameraManager(pawn, 0) end)
  if not (valid(cls) and valid(pc) and valid(pcm)) then log("camera: no controller or camera manager, the view follows her"); return end
  local loc = try(function() local v = pcm:GetCameraLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
  local rot = try(function() local r = pcm:GetCameraRotation(); return { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end)
  local fov = try(function() return pcm:GetFOVAngle() end)
  if not (loc and rot) then log("camera: can't read the view, it follows her"); return end
  local tm = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = loc, Scale3D = { X = 1, Y = 1, Z = 1 } }
  local cam = try(function()
    local d = gs:BeginDeferredActorSpawnFromClass(pawn, cls, tm, 1, nil)
    return gs:FinishSpawningActor(d, tm)
  end)
  if not valid(cam) then log("camera: spawn failed, the view follows her"); return end
  try(function() cam:K2_SetActorLocationAndRotation(loc, rot, false, {}, true) end)
  local cc = try(function() return cam.CameraComponent end)
  if valid(cc) then
    try(function() cc.bConstrainAspectRatio = false end)
    if fov then try(function() cc:SetFieldOfView(fov) end) end
    -- no motion blur in its view (tune.cameraMotionBlur): following her body as she flies, the camera moved with her
    -- and the stump caps (procedural meshes, no motion of their own in the velocity buffer) were blurred along its
    -- motion, stretched the way the blow went (playtest)
    if tune.cameraMotionBlur ~= true then
      local ok = try(function()
        local pp = cc.PostProcessSettings
        pp.bOverride_MotionBlurAmount = true
        pp.MotionBlurAmount = 0
        cc.PostProcessBlendWeight = 1
        return pp.bOverride_MotionBlurAmount == true and pp.MotionBlurAmount == 0
      end)
      if not ok then log("camera: its motion blur not turned off (the stump caps may smear as it moves)") end
    end
  end
  try(function() pc:SetViewTargetWithBlend(cam, 0, 0, 0, false) end)
  -- it turns about the point it looked at, where she died (her capsule's distance down the view), all the way round
  -- either way, with the mouse and the right stick read straight off the controller's input (playtest 41: while she
  -- is dead the game turns the controller's rotation only sideways, and putting it back each frame didn't take)
  local cap = try(function() local v = pawn:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
  local d = cap and math.max(dist(loc, cap), 150) or 400
  local f = fwd(rot)
  local mesh = try(function() return pawn.Mesh end)
  camHeld = { pc = pc, cam = cam, pawn = pawn, mesh = mesh, d = d, dz = d, pitch = rot.Pitch, yaw = rot.Yaw, t = os.clock(), t0 = os.clock(),
    pivot = { X = loc.X + f.X * d, Y = loc.Y + f.Y * d, Z = loc.Z + f.Z * d } }
  camHeld.from = camera_pelvis(camHeld)
  camHeld.home = { X = camHeld.pivot.X, Y = camHeld.pivot.Y, Z = camHeld.pivot.Z }
  -- zoomed in (aiming, a grab): out to her usual view over EASE_S
  local uf, ud = screen.camUsual.fov.best, screen.camUsual.d.best
  local zoom = ""
  if valid(cc) and fov and uf and fov < uf - 3 then
    camHeld.cc, camHeld.fov0, camHeld.fov1 = cc, fov, uf
    zoom = string.format(", zoomed in: fov out to %d", uf)
  end
  if ud and d < ud - 30 then
    camHeld.d0, camHeld.d1 = d, ud
    zoom = zoom .. string.format(", %.0f cm out to %d", d, ud)
  end
  if camHeld.fov1 or camHeld.d1 then camHeld.e0 = os.clock() end
  log(string.format("camera: view held at %s (fov %s%s) till she gets up, target %s", v3(loc), tostring(fov), zoom,
    name(try(function() return pcm.ViewTarget.Target end))))
end
local function wrap(a) a = (a + 180) % 360 - 180; return a end
local ks = nil
-- every frame (game_tick): the held view turned about its point by the mouse (tune.cameraMouse degrees a unit of mouse
-- input) and the right stick (tune.cameraStick degrees a second at full tilt), the point flown about by WASD, Q/E and
-- the left stick and triggers (tune.cameraMove cm a second, Shift tune.cameraFast times that, no further than
-- tune.cameraRange from where it started), kept out of walls (traces on the Camera channel, her and the camera
-- ignored: the point stops 10 cm short of what it would fly into, the view 10 cm short of what is between them)
local function K(n) return { KeyName = FName(n) } end
local KEYS = { mx = K("MouseX"), my = K("MouseY"), sx = K("Gamepad_RightX"), sy = K("Gamepad_RightY"),
  lx = K("Gamepad_LeftX"), ly = K("Gamepad_LeftY"), lt = K("Gamepad_LeftTriggerAxis"), rt = K("Gamepad_RightTriggerAxis"),
  w = K("W"), a = K("A"), s = K("S"), d = K("D"), q = K("Q"), e = K("E"), shift = K("LeftShift"),
  wheel = K("MouseWheelAxis"), du = K("Gamepad_DPad_Up"), dd = K("Gamepad_DPad_Down"), rb = K("Gamepad_RightShoulder") }
local function axis(pc, k) return try(function() return pc:GetInputAnalogKeyState(k) end) or 0 end
local function down(pc, k) return try(function() return pc:IsInputKeyDown(k) end) and 1 or 0 end
local function dead(v) return math.abs(v) < 0.15 and 0 or v end
-- where a Camera-channel trace from a to b first hits, or nil
local function camera_trace(h, a, b)
  if not valid(ks) then ks = try(function() return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end) end
  if not valid(ks) then return nil end
  local hit = {}
  local blocked = try(function()
    return ks:LineTraceSingle(h.cam, a, b, 1, false, { h.pawn, h.cam }, 0, hit, true,
      { R = 1, G = 0, B = 0, A = 1 }, { R = 0, G = 1, B = 0, A = 1 }, 0)
  end)
  return blocked and try(function() local l = hit.Location; return { X = l.X, Y = l.Y, Z = l.Z } end) or nil
end
-- a point 10 cm short of where the way from a towards b (dir, len) is blocked, or b
local function camera_short(h, a, dir, len)
  local b = { X = a.X + dir.X * len, Y = a.Y + dir.Y * len, Z = a.Z + dir.Z * len }
  local at = camera_trace(h, a, b)
  if not at then return b end
  local l = math.max(dist(a, at) - 10, 0)
  return { X = a.X + dir.X * l, Y = a.Y + dir.Y * l, Z = a.Z + dir.Z * l }
end
screen.CAM_CLIP_CM = 80
local function camera_orbit()
  local tune = get_tune()
  local h = camHeld
  if not (h and valid(h.cam) and valid(h.pc)) then return end
  local now = os.clock()
  local dt = math.min(now - h.t, 0.1)
  h.t = now
  local pc = h.pc
  local eased = false
  if h.e0 then
    local k = math.min((now - h.e0) / screen.camUsual.EASE_S, 1)
    local e = k * k * (3 - 2 * k)
    if h.fov1 and valid(h.cc) then try(function() h.cc:SetFieldOfView(h.fov0 + (h.fov1 - h.fov0) * e) end) end
    if h.d1 then h.d, eased = h.d0 + (h.d1 - h.d0) * e, true; h.dz = h.d end
    if k >= 1 then h.e0 = nil end
  end
  -- photo mode (a held death) looks through its own pawn and takes the mouse and WASD; once it closes the view goes
  -- back to this camera, where it was left
  if screen.photo or h.photo then
    local vt = try(function() return pc.PlayerCameraManager.ViewTarget.Target end)
    local at = valid(vt) and vt:GetAddress() or 0
    if at ~= h.vt then
      h.vt = at
      local cls = at ~= 0 and try(function() return vt:GetClass():GetFName():ToString() end) or "nothing"
      if cls:find("PhotoMode") then
        h.photo = true
        log("camera: photo mode open (" .. cls .. ")")
      elseif h.photo then
        h.photo = false
        if at ~= h.cam:GetAddress() then try(function() pc:SetViewTargetWithBlend(h.cam, 0, 0, 0, false) end) end
        h.vt, h.clip = nil, nil
        log("camera: photo mode closed (the view was on " .. cls .. "), back on the held camera")
      end
    end
    if h.photo then return end
  end
  local mx, my, sx, sy = axis(pc, KEYS.mx), axis(pc, KEYS.my), dead(axis(pc, KEYS.sx)), dead(axis(pc, KEYS.sy))
  local km, kst = tune.cameraMouse or 3, tune.cameraStick or 150
  local dy = mx * km + sx * kst * dt
  local dp = (my * km + sy * kst * dt) * (tune.cameraInvertY and -1 or 1)
  if not h.turned and (dy ~= 0 or dp ~= 0) then
    h.turned = true
    log(string.format("camera: turning with the player (mouse %.2f %.2f, stick %.2f %.2f)", mx, my, sx, sy))
  end
  h.yaw, h.pitch = wrap(h.yaw + dy), wrap(h.pitch + dp)
  -- zoom: the mouse wheel and the D-pad (up in, down out) bring the view in towards the point it turns about, down
  -- to tune.cameraZoomMin cm, or back out to tune.cameraRange (Nexus request: up close to her body). The near clip
  -- plane comes in (tune.photoNearClip) while it is within CLIP_CM: the game's 10 cm cut into her up close
  -- (not with RB down: D-pad down + RB is holdPad, Shift+F4 on the controller)
  -- The wheel sets where it is going (dz), and the view eases there (tune.cameraZoomEase a second): a notch was a
  -- 15% jump at once
  -- Flown free, it has no point to come in to: the wheel and the D-pad move it along the view instead (40 cm a notch,
  -- 300 cm a second held), stopping short of walls
  local zw, zp = axis(pc, KEYS.wheel), down(pc, KEYS.rb) == 1 and 0 or down(pc, KEYS.du) - down(pc, KEYS.dd)
  if h.free and (zw ~= 0 or zp ~= 0) then
    local s = zw * 40 + zp * 300 * dt
    local f0 = fwd({ Pitch = h.pitch, Yaw = h.yaw, Roll = 0 })
    local dir = s < 0 and { X = -f0.X, Y = -f0.Y, Z = -f0.Z } or f0
    h.pivot, eased = camera_short(h, h.pivot, dir, math.abs(s)), true
  elseif zw ~= 0 or zp ~= 0 then
    local nd = (h.dz or h.d) * math.exp(-(zw * 0.15 + zp * 1.5 * dt))
    nd = math.min(math.max(nd, tune.cameraZoomMin or 15), tune.cameraRange or 1500)
    if nd ~= h.dz then
      h.dz, h.d1, h.e0 = nd, nil, h.fov1 and h.e0 or nil
      if not h.zoomed then h.zoomed = true; log(string.format("camera: zooming (%.0f cm from the point)", nd)) end
    end
  end
  if h.dz and h.dz ~= h.d then
    local ze = tune.cameraZoomEase or 10
    local k = ze > 0 and 1 - math.exp(-ze * dt) or 1
    h.d = math.abs(h.dz - h.d) < 0.05 and h.dz or h.d + (h.dz - h.d) * k
    eased = true
    local nc = tune.photoNearClip
    local clip = type(nc) == "number" and nc > 0 and h.d < screen.CAM_CLIP_CM
    if clip ~= (h.clip or false) and not screen.unhide then
      h.clip = clip
      screen.console(h.pawn, string.format("r.SetNearClipPlane %g", clip and nc or 10))
    end
  end
  -- past straight up or down the view goes on over the top, upside down
  local rot = { Pitch = h.pitch, Yaw = h.yaw, Roll = 0 }
  local f = fwd(rot)
  -- flying: forward along the view, sideways on the level (flipped upside down), up and down in the world
  local mf = down(pc, KEYS.w) - down(pc, KEYS.s) + dead(axis(pc, KEYS.ly))
  local mr = down(pc, KEYS.d) - down(pc, KEYS.a) + dead(axis(pc, KEYS.lx))
  local mu = down(pc, KEYS.e) - down(pc, KEYS.q) + dead(axis(pc, KEYS.rt)) - dead(axis(pc, KEYS.lt))
  local moved = false
  -- not till every key that flies it has been let go once: she died running, W still down, and it flew off at once.
  -- Nor before tune.cameraFlyAfter s into the death: till then it stays locked on her body (cameraBody), turned and
  -- zoomed round her; the first fly key after that lets go of her and flies it
  if not h.armed then h.armed = mf == 0 and mr == 0 and mu == 0 and now - h.t0 >= (tune.cameraFlyAfter or 1.5) end
  if h.armed and (mf ~= 0 or mr ~= 0 or mu ~= 0) then
    local y, flip = math.rad(h.yaw), math.cos(math.rad(h.pitch)) < 0 and -1 or 1
    local v = { X = f.X * mf - math.sin(y) * flip * mr, Y = f.Y * mf + math.cos(y) * flip * mr, Z = f.Z * mf + mu }
    local l = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
    local step = math.min(l, 1) * (tune.cameraMove or 400) * (down(pc, KEYS.shift) == 1 and (tune.cameraFast or 3) or 1) * dt
    if l > 0 and step > 0 then
      local dir = { X = v.X / l, Y = v.Y / l, Z = v.Z / l }
      -- the first press lets go of her: the camera on its own from where it is, the point it turned about brought
      -- to the camera itself, so the mouse and the stick turn it where it stands (it no longer goes round anything)
      if not h.free then
        h.free = true
        local w = h.wd or h.d
        h.pivot = { X = h.pivot.X - f.X * w, Y = h.pivot.Y - f.Y * w, Z = h.pivot.Z - f.Z * w }
        h.d, h.dz, h.wd, h.walled, h.d1 = 0, 0, 0, false, nil
        log(string.format("camera: flying free %.1f s into the death (it lets go of her body and turns where it stands)", now - h.t0))
      end
      local to = camera_short(h, h.pivot, dir, step)
      local range = tune.cameraRange or 1500
      local o = { X = to.X - h.home.X, Y = to.Y - h.home.Y, Z = to.Z - h.home.Z }
      local r = math.sqrt(o.X * o.X + o.Y * o.Y + o.Z * o.Z)
      if r > range then to = { X = h.home.X + o.X * range / r, Y = h.home.Y + o.Y * range / r, Z = h.home.Z + o.Z * range / r } end
      h.pivot, moved = to, true
    end
  end
  -- till then the point it turns about rides her body (tune.cameraBody, as Customized Ragdoll's camera does on her
  -- pelvis: up and down too, every frame, lightly smoothed by tune.cameraBodyRate so her ragdoll's shakes don't reach
  -- it): her upper body (Spine2, the chest) or her pelvis, tune.cameraBodyBone. Where it looked at her death is eased
  -- onto it over tune.cameraBodyBlend s; the range it may be flown in rides along
  local rate = tune.cameraTrack or 2.5
  screen.CAM_BONES = screen.CAM_BONES or { upper = FName("Bip001-Spine2"), pelvis = PELVIS }
  local bone = screen.CAM_BONES[tune.cameraBodyBone or "upper"] or screen.CAM_BONES.upper
  local p3 = not h.free and tune.cameraBody ~= false and valid(h.mesh)
    and try(function() local v = h.mesh:GetSocketLocation(bone); return { X = v.X, Y = v.Y, Z = v.Z } end)
  local p = not p3 and not h.free and rate > 0 and h.from and camera_pelvis(h)
  if p3 then
    if not h.off then
      h.off = { X = h.pivot.X - p3.X, Y = h.pivot.Y - p3.Y, Z = h.pivot.Z - p3.Z }
      log(string.format("camera: following her body (her %s, %.0f cm from where it looked)",
        tune.cameraBodyBone == "pelvis" and "pelvis" or "upper body", math.sqrt(h.off.X * h.off.X + h.off.Y * h.off.Y + h.off.Z * h.off.Z)))
    end
    local kb = math.exp(-dt / math.max(tune.cameraBodyBlend or 0.5, 0.01))
    h.off.X, h.off.Y, h.off.Z = h.off.X * kb, h.off.Y * kb, h.off.Z * kb
    local br = tune.cameraBodyRate or 15
    local k = br > 0 and 1 - math.exp(-br * dt) or 1
    local ox, oy, oz = (p3.X + h.off.X - h.pivot.X) * k, (p3.Y + h.off.Y - h.pivot.Y) * k, (p3.Z + h.off.Z - h.pivot.Z) * k
    if ox * ox + oy * oy + oz * oz > 0.0001 then
      h.pivot.X, h.pivot.Y, h.pivot.Z = h.pivot.X + ox, h.pivot.Y + oy, h.pivot.Z + oz
      h.home.X, h.home.Y, h.home.Z = h.home.X + ox, h.home.Y + oy, h.home.Z + oz
      moved = true
    end
  elseif p then
    local k = 1 - math.exp(-rate * dt)
    local ox, oy = (p.X - h.from.X) * k, (p.Y - h.from.Y) * k
    if ox * ox + oy * oy > 0.0001 then
      h.from.X, h.from.Y = h.from.X + ox, h.from.Y + oy
      h.pivot.X, h.pivot.Y = h.pivot.X + ox, h.pivot.Y + oy
      h.home.X, h.home.Y = h.home.X + ox, h.home.Y + oy
      moved = true
    end
  end
  if dy == 0 and dp == 0 and h.placed and not moved and not eased and not h.walled then return end
  h.placed = true
  -- a wall between: in at once, 10 cm short of it, so it never shows through; out again eased (tune.cameraWallEase
  -- a second) once the way clears, not snapped back (Customized Ragdoll's camera jumps both ways)
  local b = { X = -f.X, Y = -f.Y, Z = -f.Z }
  local at = camera_trace(h, h.pivot, { X = h.pivot.X + b.X * h.d, Y = h.pivot.Y + b.Y * h.d, Z = h.pivot.Z + b.Z * h.d })
  local want = at and math.max(dist(h.pivot, at) - 10, 0) or h.d
  if not h.wd or want <= h.wd then
    h.wd, h.walled = want, at ~= nil
  elseif h.walled then
    local we = tune.cameraWallEase or 4
    h.wd = h.wd + (want - h.wd) * (we > 0 and 1 - math.exp(-we * dt) or 1)
    if want - h.wd < 0.5 then h.wd, h.walled = want, at ~= nil end
  else
    h.wd = want
  end
  local loc = { X = h.pivot.X + b.X * h.wd, Y = h.pivot.Y + b.Y * h.wd, Z = h.pivot.Z + b.Z * h.wd }
  try(function() h.cam:K2_SetActorLocationAndRotation(loc, rot, false, {}, true) end)
end
local function camera_release(pawn)
  local h = camHeld
  camHeld, camWatch = nil, nil
  if goreCtx.customrag then try(goreCtx.customrag.camera_off) end
  if not h then return end
  if h.clip and not screen.unhide then screen.console(pawn, "r.SetNearClipPlane 10") end
  if valid(h.pc) and valid(pawn) then try(function() h.pc:SetViewTargetWithBlend(pawn, 0, 0, 0, false) end) end
  if valid(h.cam) then try(function() h.cam:K2_DestroyActor() end) end
  log("camera: view back on her")
end
local function camera_watch(pawn, mesh)
  local w = camWatch
  if not w or w.n >= 6 then return end
  local t = os.clock() - w.t0
  if t < w.n * 0.5 then return end
  w.n = w.n + 1
  local cam = try(function()
    local v = goreCtx.statics():GetPlayerCameraManager(pawn, 0):GetCameraLocation()
    return { X = v.X, Y = v.Y, Z = v.Z }
  end)
  local c = try(function() local v = pawn:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
  local h = try(function() local v = mesh:GetSocketLocation(FName("Bip001-Head")); return { X = v.X, Y = v.Y, Z = v.Z } end)
  lg.v(string.format("camera at %.1f s: view%s, %.0f cm from her capsule%s, %.0f from her head%s",
    t, v3(cam), dist(cam, c), v3(c), dist(cam, h), v3(h)))
end

return { hold = camera_hold, orbit = camera_orbit, release = camera_release, watch = camera_watch,
  held = function() return camHeld end, forget = function() camHeld, camWatch = nil, nil end }
end
