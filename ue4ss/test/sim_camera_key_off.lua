-- the follow-point hotkey (C) does nothing with Follow-Point Hotkey off (the default): her death
-- camera keeps following her upper body, and the log says the key is off
local F = require("fake")
local E = require("eve")
local R = require("rag")
local pawn = E.make(F)
local print = F.say
R.install(F, E)
F.world = R.step
local pcm = F.obj("PlayerCameraManager_0", "SBPlayerCameraManager", {
  GetFOVAngle = function() return 70 end,
  GetCameraLocation = function() local l = pawn:K2_GetActorLocation(); l.X = l.X - 300; return l end,
  GetCameraRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
  ViewTarget = { Target = pawn },
})
local ctl = rawget(pawn, "Controller")
rawset(ctl, "PlayerCameraManager", pcm)
rawset(ctl, "SetViewTargetWithBlend", function() end)
rawset(ctl, "GetInputAnalogKeyState", function() return 0 end)
rawset(ctl, "IsInputKeyDown", function() return false end)
local cam = F.obj("CameraActor_0", "CameraActor", {
  K2_SetActorLocationAndRotation = function(self, l, r) self.at, self.rot = l, r end,
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

-- no cameraBodyKey in the settings (off by default): C says the hotkey is off, and the held camera
-- stays on her upper body
local at = mark()
check(F.press("C", ""), "C bound")
F.run(0.5, pawn)
check(F.find("follow%-point hotkey is off", at) ~= nil, "off: the log says the hotkey is off")
check(F.find("follow point pelvis", at) == nil, "off: nothing switched to her pelvis")
check(F.find("follow point upper body", at) == nil, "off: nothing switched either")
E.die(true)
F.run(2, pawn)
local o = (function()
  local l, p = cam.at, pawn.Mesh:GetSocketLocation(FName("Bip001-Spine2"))
  return l and math.sqrt((l.X - p.X) ^ 2 + (l.Y - p.Y) ^ 2 + (l.Z - p.Z) ^ 2)
end)()
check(o and math.abs(o - 300) < 5, "off: the camera still off her upper body (" .. tostring(o) .. ")")
at = mark()
F.press("C", "")
F.run(1, pawn)
check(F.find("follow point pelvis", at) == nil, "off in a death: still nothing switched")
local notice = io.open("ue4ss/Mods/StellarBladeGore/spawner.cmd", "r")
local text = notice and notice:read("*a") or ""
if notice then notice:close() end
check(text:find("Follow%-point hotkey is off") ~= nil, "off in a death: an on-screen notice explains how to enable it")
E.respawn(); F.run(20, pawn)

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
