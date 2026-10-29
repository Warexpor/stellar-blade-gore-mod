-- the held death camera after a zoomed-in death: a grab's close-up (a boss holding her and hitting) or the gun's aim
-- kept that view held till she got up (playtest). Her usual view, learnt while she lives (the field of view and the
-- camera's distance most polls had), is eased out to
local F = require("fake")
local E = require("eve")
local R = require("rag")
local pawn = E.make(F)
local print = F.say
R.install(F, E)
F.world = R.step
-- the view: fov and the camera's distance in front of her, read off the camera manager
local view = { fov = 70, d = 300 }
local pcm = F.obj("PlayerCameraManager_0", "SBPlayerCameraManager", {
  GetFOVAngle = function() return view.fov end,
  GetCameraLocation = function() local l = pawn:K2_GetActorLocation(); l.X = l.X - view.d; return l end,
  GetCameraRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
  ViewTarget = { Target = pawn },
})
local ctl = rawget(pawn, "Controller")
rawset(ctl, "PlayerCameraManager", pcm)
rawset(ctl, "SetViewTargetWithBlend", function() end)
rawset(ctl, "GetInputAnalogKeyState", function() return 0 end)
rawset(ctl, "IsInputKeyDown", function() return false end)
local fovs = {}
local cam = F.obj("CameraActor_0", "CameraActor", {
  CameraComponent = F.obj("CameraComponent", "CameraComponent", { SetFieldOfView = function(_, f) fovs[#fovs + 1] = f end }),
  K2_SetActorLocationAndRotation = function(self, l) self.at = l end,
})
F.objects["/Script/Engine.CameraActor"] = F.obj("CameraActor", "Class")
F.objects["/Script/Engine.Default__GameplayStatics"] = F.obj("Default__GameplayStatics", "GameplayStatics", {
  GetPlayerController = function() return ctl end,
  GetPlayerCameraManager = function() return pcm end,
  BeginDeferredActorSpawnFromClass = function() return cam end,
  FinishSpawningActor = function(_, a) return a end,
})
local ok, err = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function mark() return #F.log_lines() + 1 end

-- 1: a grab's close-up at her death: fov 30, 120 cm off (150 at the least: it turns about a point 30 cm past her);
-- eased out to 70 and 300 cm from that point
local at = mark()
view.fov, view.d = 30, 120
F.run(0.3, pawn)
E.die(true)
F.run(2, pawn)
check(F.find("camera: view held at .-%(fov 30, zoomed in: fov out to 70, 150 cm out to 300%)", at) ~= nil, "1: zoomed in: held, eased out")
check(fovs[1] == 30 and math.abs((fovs[#fovs] or 0) - 70) < 0.01, "1: its fov from 30 to 70 (" .. tostring(fovs[#fovs]) .. ")")
-- the point it turns about rides her upper body (cameraBody, cameraBodyBone "upper"): 300 cm off her chest
local function off_body()
  local l, p = cam.at, pawn.Mesh:GetSocketLocation(FName("Bip001-Spine2"))
  return l and math.sqrt((l.X - p.X) ^ 2 + (l.Y - p.Y) ^ 2 + (l.Z - p.Z) ^ 2)
end
check(F.find("camera: following her body", at) ~= nil, "1: it follows her body")
local o = off_body()
check(o and math.abs(o - 300) < 5, "1: the camera 300 cm off her upper body (" .. tostring(o) .. ")")
E.respawn(); F.run(20, pawn)

-- 2: her usual view at her death: left as it is
at = mark()
view.fov, view.d = 70, 300
fovs = {}
-- W held from the fight on (she died running): ignored, and pressed again before cameraFlyAfter (1.5 s) too: it stays
-- locked on her, turning round her with the mouse
local held = { W = true }
rawset(ctl, "IsInputKeyDown", function(_, k) return held[k.KeyName:ToString()] == true end)
local mouse = 0
rawset(ctl, "GetInputAnalogKeyState", function(_, k) return k.KeyName:ToString() == "MouseX" and mouse or 0 end)
E.die(true)
F.run(0.3, pawn)
held.W = false
F.run(0.3, pawn)
held.W = true
mouse = 1
F.run(0.4, pawn)
held.W, mouse = false, 0
rawset(ctl, "GetInputAnalogKeyState", function() return 0 end)
F.run(1, pawn)
check(F.find("camera: view held at .-%(fov 70%)", at) ~= nil, "2: not zoomed in: held as it was")
check(#fovs == 1, "2: its fov set once (" .. #fovs .. ")")
check(F.find("camera: turning with the player", at) ~= nil, "2: turned round her while locked on")
check(F.find("camera: flying free", at) == nil, "2: W before cameraFlyAfter: still locked on her")
local o = off_body()
check(o and math.abs(o - 300) < 5, "2: turned, still 300 cm off her upper body (" .. tostring(o) .. ")")
-- her body carried off (the ragdoll sliding down a slope): the camera after it, up and down too
local sock = pawn.Mesh.GetSocketLocation
local lift = { X = 120, Y = -80, Z = -150 }
rawset(pawn.Mesh, "GetSocketLocation", function(self, n)
  local v = sock(self, n)
  return { X = v.X + lift.X, Y = v.Y + lift.Y, Z = v.Z + lift.Z }
end)
local c0 = { X = cam.at.X, Y = cam.at.Y, Z = cam.at.Z }
F.run(1, pawn)
local c1 = cam.at
o = off_body()
local mv = math.sqrt((c1.X - c0.X) ^ 2 + (c1.Y - c0.Y) ^ 2 + (c1.Z - c0.Z) ^ 2)
check(mv > 180 and o and math.abs(o - 300) < 5,
  string.format("2: the camera carried after her body (it moved %.0f cm, %.1f cm off her)", mv, o or -1))
-- past cameraFlyAfter, W: lets go of her and flies; her body carried off again, it stays where it was flown
held.W = true
F.run(0.5, pawn)
held.W = false
F.run(0.2, pawn)
check(F.find("camera: flying free", at) ~= nil, "2: W after cameraFlyAfter: it lets go of her and flies")
c0 = { X = cam.at.X, Y = cam.at.Y, Z = cam.at.Z }
lift = { X = 300, Y = 0, Z = 0 }
F.run(1, pawn)
c1 = cam.at
check(math.abs(c1.X - c0.X) < 1 and math.abs(c1.Y - c0.Y) < 1 and math.abs(c1.Z - c0.Z) < 1, "2: let go, it no longer follows her")
-- flown free, the mouse turns it where it stands: its place kept, only its view turned
c0 = { X = cam.at.X, Y = cam.at.Y, Z = cam.at.Z }
rawset(ctl, "GetInputAnalogKeyState", function(_, k) return k.KeyName:ToString() == "MouseX" and 1 or 0 end)
F.run(0.5, pawn)
rawset(ctl, "GetInputAnalogKeyState", function() return 0 end)
c1 = cam.at
check(F.find("turns where it stands", at) ~= nil and math.abs(c1.X - c0.X) < 1 and math.abs(c1.Y - c0.Y) < 1 and math.abs(c1.Z - c0.Z) < 1,
  string.format("2: flown free, the mouse turns it where it stands (it moved %.1f cm)",
    math.sqrt((c1.X - c0.X) ^ 2 + (c1.Y - c0.Y) ^ 2 + (c1.Z - c0.Z) ^ 2)))
rawset(pawn.Mesh, "GetSocketLocation", sock)
rawset(ctl, "IsInputKeyDown", function() return false end)

E.respawn(); F.run(20, pawn)
E.die(true)
F.run(2, pawn)

-- 3: the mouse wheel zooms it in, down to cameraZoomMin (15 cm) from the point it turns about (Nexus request)
at = mark()
local wheel = 1
rawset(ctl, "GetInputAnalogKeyState", function(_, k) return k.KeyName:ToString() == "MouseWheelAxis" and wheel or 0 end)
F.run(3, pawn)
wheel = 0
rawset(ctl, "GetInputAnalogKeyState", function() return 0 end)
F.run(0.5, pawn)
check(F.find("camera: zooming", at) ~= nil, "3: the wheel zooms")
o = off_body()
check(o and math.abs(o - 15) < 2, "3: in to 15 cm off the point (" .. tostring(o) .. ")")
E.respawn(); F.run(20, pawn)

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
if fails > 0 then for _, x in ipairs(F.log_lines()) do if x:find("camera") then print("  | " .. x:sub(1, 200)) end end end
print(fails == 0 and "PASS" or "FAIL")
