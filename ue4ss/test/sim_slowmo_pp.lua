-- Motion blur suppression and camera de-lag while slow (slowmo_pp.lua).
local F = require("fake")
local print = F.say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local logs = {}
local function log(s) logs[#logs + 1] = s end
local destroyed = 0
local vol = { Settings = { bOverride_MotionBlurAmount = false, MotionBlurAmount = 1 } }
function vol:K2_DestroyActor() destroyed = destroyed + 1; return true end
local gs = {}
function gs:BeginDeferredActorSpawnFromClass() return {} end
function gs:FinishSpawningActor() return vol end
local camPP = { bOverride_MotionBlurAmount = false, MotionBlurAmount = 1 }
local cam = { PostProcessSettings = camPP }
function cam:GetFName() return { ToString = function() return "FollowCamera" end } end
function cam:GetAddress() return 0x501 end
local boom = { bEnableCameraLag = true }
function boom:GetFName() return { ToString = function() return "CameraBoom" end } end
function boom:GetAddress() return 0x502 end
local root = {}
function root:GetAddress() return 0x500 end
root.AttachChildren = { ForEach = function(_, fn)
  fn(1, { get = function() return cam end })
  fn(2, { get = function() return boom end })
end }
local pawn = F.obj("Eve", "Pawn")
pawn.RootComponent = root
local spawns = 0
local M = dofile("ue4ss/Mods/StellarBladeGore/Scripts/slowmo_pp.lua")(
  function() spawns = spawns + 1; return gs end,
  function(f) local ok, r = pcall(f); if ok then return r end end,
  function(x) return x ~= nil and x ~= false end, log)
_G.StaticFindObject = function() return {} end
check(M.want(pawn, true) == true, "slow: everything held")
check(spawns == 1, "volume spawned once")
check(vol.Settings.MotionBlurAmount == 0, "blur at zero in the volume")
check(camPP.MotionBlurAmount == 0 and camPP.bOverride_MotionBlurAmount == true, "her camera's blur off")
check(boom.bEnableCameraLag == false, "boom lag off")
check(M.want(pawn, true) == true, "slow again: nothing twice")
check(spawns == 1, "still one spawn")
check(M.want(pawn, false) == true, "full speed: everything handed back")
check(destroyed == 1, "volume destroyed")
check(camPP.MotionBlurAmount == 1 and camPP.bOverride_MotionBlurAmount == false, "her camera's blur back")
check(boom.bEnableCameraLag == true, "boom lag back")
check(M.want(pawn, false) == true, "letting go twice is a no-op")
check(destroyed == 1, "still one destroy")
print(fails == 0 and "PASS" or "FAIL")
