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
local l, h = cam.at, pawn:K2_GetActorLocation()
check(l and math.abs(h.X - l.X - 270) < 5, "1: the camera 300 cm off the point it turns about (" .. tostring(l and h.X - l.X) .. ")")
E.respawn(); F.run(20, pawn)

-- 2: her usual view at her death: left as it is
at = mark()
view.fov, view.d = 70, 300
fovs = {}
E.die(true)
F.run(2, pawn)
check(F.find("camera: view held at .-%(fov 70%)", at) ~= nil, "2: not zoomed in: held as it was")
check(#fovs == 1, "2: its fov set once (" .. #fovs .. ")")

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
if fails > 0 then for _, x in ipairs(F.log_lines()) do if x:find("camera") then print("  | " .. x:sub(1, 200)) end end end
print(fails == 0 and "PASS" or "FAIL")
