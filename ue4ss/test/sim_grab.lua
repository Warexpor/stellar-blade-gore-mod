-- her death in an enemy's grab (enemies.grab_tick / grab_now / grab_holds): Raven's grab plays no montage (playtest:
-- "no montage", the grab never seen and her body taken out of the grip at once), so a hand held on her is a grab with
-- or without one; without, it lasts while the hand stays on her or she is attached to it. A hand passing through her
-- in a swing isn't one
local F = require("fake")
local print = F.say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local logs = {}
local tune = dofile("ue4ss/Mods/StellarBladeGore/Scripts/tune.lua")
local chars = {}
local ctx = { tune = tune, log = function(s) logs[#logs + 1] = s; print("  | " .. s) end,
  try = function(f) local ok, r = pcall(f); if ok then return r end end,
  valid = function(x)
    if type(x) == "table" and x.__freed then error("freed grabber touched") end
    return x ~= nil and x ~= false
  end,
  live_chars = function() return chars end, held = function(k) return not k.obj.__freed end,
  grab_character = function(ad) if chars[1] and chars[1].addr == ad then return chars[1] end end }
local E = dofile("ue4ss/Mods/StellarBladeGore/Scripts/enemies.lua")
E.init(ctx)
local function has(pat) for _, l in ipairs(logs) do if l:find(pat) then return true end end return false end

-- her bones at the origin, up her body
local herBones = { ["Bip001-Pelvis"] = 0, ["Bip001-Spine1"] = 20, ["Bip001-Spine2"] = 35, ["Bip001-Neck"] = 55, ["Bip001-Head"] = 65 }
local herMesh = F.obj("EveMesh", "SkeletalMeshComponent")
herMesh.GetSocketLocation = function(_, b) local z = herBones[tostring(b)]; return z and { X = 0, Y = 0, Z = 100 + z } end
local parent
local root = F.obj("EveCapsule", "CapsuleComponent")
root.GetAttachParentActor = function() return parent end
local pawn = F.obj("Eve", "CH_P_EVE_01_Blueprint_C", { Mesh = herMesh, RootComponent = root })
herMesh.GetAnimInstance = function() return { GetCurrentActiveMontage = function() return nil end } end
pawn.K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 100 } end

-- Raven, 58 cm off, no montage; her right hand where `hand` says
local hand = { X = 300, Y = 0, Z = 150 }
local rmesh = F.obj("RavenMesh", "SkeletalMeshComponent")
rmesh.GetSocketLocation = function(_, b)
  b = tostring(b)
  if b == "Bip001-R-Hand" then return hand end
  if b == "Bip001-L-Hand" then return { X = 60, Y = 40, Z = 120 } end
end
local montage
rmesh.GetAnimInstance = function()
  return { GetCurrentActiveMontage = function() return montage end, Montage_IsPlaying = function() return montage ~= nil end }
end
local raven = F.obj("CH_M_NA_53_Blueprint_C_1", "CH_M_NA_53_Blueprint_C", { Mesh = rmesh })
raven.K2_GetActorLocation = function() return { X = 58, Y = 0, Z = 100 } end
chars[1] = { obj = raven, addr = raven:GetAddress(), cls = "CH_M_NA_53_Blueprint_C", k = { obj = raven } }

local function run(s) local t1 = F.t + s; while F.t < t1 do F.t = F.t + 0.1; E.grab_tick(pawn, herMesh) end end
parent = raven
local direct = E.grab_attached(pawn)
check(direct and direct.addr == chars[1].addr and E.grab_holds(direct, pawn, herMesh),
  "direct attachment identifies a grab before the first watch sample")
parent = nil
check(E.grab_attached(pawn) == nil, "a nearby character alone is not an attachment")

-- a swing passing through her: no grab
hand = { X = 5, Y = 0, Z = 155 }
run(0.1)
hand = { X = 300, Y = 0, Z = 150 }
run(0.6)
check(E.grab_now() == nil, "a hand passing through her in a swing: no grab")

-- the grab: its hand on her neck, no montage
hand = { X = 8, Y = 0, Z = 158 }
run(0.6)
local g = E.grab_now()
check(g ~= nil and g.mont == nil and has("grab: CH_M_NA_53_Blueprint_C has her: Bip001%-R%-Hand on her Bip001%-Neck"),
  "Raven's hand on her neck 0.6 s, no montage: a grab")
-- (her death: the tick stops, the grab is asked whether it still holds)
check(E.grab_holds(g, pawn, herMesh), "its hand still on her: it holds")
hand = { X = 30, Y = 0, Z = 160 }
check(E.grab_holds(g, pawn, herMesh), "her body swaying in its grip (30 cm): it holds")
hand = { X = 300, Y = 0, Z = 150 }
check(not E.grab_holds(g, pawn, herMesh), "its hand off her: let go")
-- attached to it
parent = raven
check(E.grab_holds(g, pawn, herMesh), "her attached to it: it holds")
parent = nil

-- with a montage: it lasts while the montage plays, the hand off her between hits
montage = F.obj("AM_Raven_Grab", "AnimMontage")
hand = { X = 8, Y = 0, Z = 158 }
run(0.6)
g = E.grab_now()
check(g ~= nil and g.mont == montage:GetAddress(), "a grab records the montage address")
hand = { X = 300, Y = 0, Z = 150 }
check(E.grab_holds(g, pawn, herMesh), "its hand off her between hits, the montage on: it holds")
montage = nil
check(not E.grab_holds(g, pawn, herMesh), "its montage over: let go")
raven.__freed = true
check(not E.grab_holds(g, pawn, herMesh), "a freed grabber is dropped before inspecting its montage")

check(#F.errors == 0, "no errors (" .. table.concat(F.errors, "; ") .. ")")
print(fails == 0 and "PASS" or "FAIL")
