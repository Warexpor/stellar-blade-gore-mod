-- A death face applies and clears its morphs, and reads settings again on its next start.
local module = dofile("ue4ss/Mods/StellarBladeGore/Scripts/death_face.lua")
local writes, messages = {}, {}
local target = { GetFName = function() return { ToString = function() return "eyeBlinkLeft" end } end }
local asset = { GetAddress = function() return 123 end, MorphTargets = {
  ForEach = function(_, cb) cb(1, { get = function() return target end }) end } }
local face = { SkeletalMesh = asset, AttachChildren = { ForEach = function() end },
  GetAddress = function() return 456 end, IsVisible = function() return true end,
  SetMorphTarget = function(_, n, value, clear) writes[#writes + 1] = { n, value, clear } end }
local pawn = { RootComponent = nil, Mesh = face }
local tune = { gore = { deathFace = { morphs = { { "eyeBlinkLeft", 0.8 } }, fade = 0.01,
  lidsShut = { 1, 1 }, jitter = 0, gaze = 0, jawSide = 0 } } }
FName = function(name) return name end
StaticFindObject = function() return {} end
FindAllOf = function() return {} end
local function safe(fn) local ok, value = pcall(fn); if ok then return value end end
local function valid(o) return o ~= nil end
local make = module(safe, valid, function() return "test" end, function(s) messages[#messages + 1] = s end,
  function() return tune end, function() return { face_of = function() return face end } end)
local f = make(function() return {} end)
local fails = 0
local function check(ok, text) print((ok and "ok   " or "FAIL ") .. text); if not ok then fails = fails + 1 end end
f.start(pawn, face, "test")
check(f.on ~= nil and f.on.face == face, "start selects a face with the requested eyelid morph")
f.on.t0 = os.clock() - 1
f.tick()
check(writes[#writes] and writes[#writes][1] == "eyeBlinkLeft" and math.abs(writes[#writes][2] - 0.8) < 1e-6,
  "the death face applies its requested weight")
f.stop()
check(f.on == nil and writes[#writes][1] == "eyeBlinkLeft" and writes[#writes][2] == 0 and writes[#writes][3] == true,
  "stop clears the held morph")
tune = { gore = { deathFace = { morphs = { { "eyeBlinkLeft", 0.3 } }, fade = 0.01,
  lidsShut = { 1, 1 }, jitter = 0, gaze = 0, jawSide = 0 } } }
f.start(pawn, face, "test reload")
f.on.t0 = os.clock() - 1
f.tick() -- every other poll is skipped
f.tick()
check(writes[#writes] and math.abs(writes[#writes][2] - 0.3) < 1e-6, "next start reads reloaded face settings")
f.stop()
print(fails == 0 and "PASS" or "FAIL")
