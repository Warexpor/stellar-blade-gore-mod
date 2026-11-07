-- Settling still: a soft test ragdoll's neutral pose goes off lying on the floor (never fell fast),
-- and once asleep with nothing to move her, a slowly creeping body is stopped instead of jittering on.
local F = require("fake")
local E = require("eve")
local R = require("rag")
local pawn = E.make(F)
local print = F.say
local f = assert(io.open("ue4ss/Mods/StellarBladeGore/Scripts/settings.lua", "w"))
f:write([[local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.deathMoves = false
s.convulse.enabled = false
return s
]])
f:close()
R.install(F, E)
F.world = R.step
local ok, err = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)
-- a floor 10 cm under any traced point (a visibility trace down 10 m)
F.objects["/Script/Engine.Default__KismetSystemLibrary"] = F.obj("KSL", "KismetSystemLibrary", {
  LineTraceSingle = function(_, _, from, _, _, _, _, _, hit, ...)
    hit.ImpactPoint = { X = from.X, Y = from.Y, Z = from.Z - 10 }
    return true
  end,
})

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function mark() return #F.log_lines() + 1 end

check(F.press("F7", ""), "F7 bound")
local at = mark()
F.run(6, pawn)
-- (neutral never engages on the fake asset's physics: the direct drive below covers its floor switch-off)
for i, x in ipairs(F.log_lines()) do if i >= at and (x:find("neutral") or x:find("start timings") or x:find("tone")) then print("  | " .. x:sub(1, 220)) end end
check(F.find("settled after", at) ~= nil, "settled")
check(F.find("kept awake", at) == nil, "asleep, not kept awake (nothing to move her)")
-- a body woken afterwards, turning slowly: stopped again, never re-settling, never woken
E.mesh:WakeRigidBody(F.fname("Bip001-Pelvis"))
E.mesh:SetPhysicsAngularVelocityInDegrees({ X = 0, Y = 0, Z = 1 }, false, F.fname("Bip001-Pelvis"))
at = mark()
F.run(3, pawn)
check(F.find("still: slow bodies", at) ~= nil, "the creep stopped once asleep")
check(F.find("woken", at) == nil, "no waking over a slow creep")
F.press("F8", "")
F.run(2, pawn)
print(fails == 0 and "PASS" or "FAIL")

-- neutral directly: on, lying on the floor and slow, never fell fast -> off, then settle, then stop
do
  local A = dofile("ue4ss/Mods/StellarBladeGore/Scripts/active.lua")
  local tune2 = dofile("ue4ss/Mods/StellarBladeGore/Scripts/tune.lua")
  local logs2 = {}
  local try2 = function(f) local ok, r = pcall(f); if ok then return r end end
  local ctx2 = { tune = tune2,
    log = function(s) logs2[#logs2 + 1] = s end,
    try = try2,
    valid = function(o) return o ~= nil and o ~= false end,
    has_neutral = function() return true end,
    physics_of = function(m) return try2(function() return m:GetPhysicsAsset() end) end,
    convulse = { due = function() return false end },
    struggle = { due = function() return false end } }
  A.init(ctx2)
  local mesh = E.mesh
  rawset(mesh, "SetAllMotorsAngularPositionDrive", function() return true end)
  rawset(mesh, "SetAllMotorsAngularVelocityDrive", function() return true end)
  local function has2(pat) for _, l in ipairs(logs2) do if l:find(pat) then return true end end return false end
  A.start(pawn, mesh, "sandbox")
  check(has2("neutral pose on"), "neutral engaged")
  for i = 1, 80 do A.tick(0.033) end
  check(has2("neutral pose off lying on the floor"), "neutral off lying on the floor without any fall")
  check(has2("settled after"), "settled afterwards")
  A.stop(pawn)
  print(#logs2 .. " lines")
end
