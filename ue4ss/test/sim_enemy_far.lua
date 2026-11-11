-- A kill by another enemy still cuts, even far from her (prologue spectacle fights): the
-- death is detected at the ragdoll start and the cut is attempted on that tick. A boss kind keeps
-- its sound and metal core; a basic kind is muted on both.
local F = require("fake")
local print, fails = F.say, 0
local function check(c, what) print((c and "ok   " or "FAIL ") .. what); if not c then fails = fails + 1 end end
local function v(x, y, z) return { X = x, Y = y, Z = z } end
local try = function(f, ...) local o, r = pcall(f, ...); if o then return r end end
local valid = function(x) return x ~= nil and x ~= false end

local logs = {}
local tune = dofile("ue4ss/Mods/StellarBladeGore/Scripts/tune.lua")
tune.enemies.odds = { limb = 100, head = 0, torso = 0 }
-- her at the origin, its pelvis 30 m off: far past the 25 m reach
local bp = {
  ["Bip001-Pelvis"] = v(3000, 0, 100), ["Bip001-Spine"] = v(3000, 0, 112), ["Bip001-Spine1"] = v(3000, 0, 122),
  ["Bip001-Spine2"] = v(3000, 0, 135), ["Bip001-Neck"] = v(3000, 0, 148), ["Bip001-Head"] = v(3000, 0, 160),
  ["Bip001-L-UpperArm"] = v(2980, 0, 140), ["Bip001-L-Forearm"] = v(2978, 0, 120), ["Bip001-L-Hand"] = v(2978, 0, 105),
  ["Bip001-R-UpperArm"] = v(3020, 0, 140), ["Bip001-R-Forearm"] = v(3022, 0, 120), ["Bip001-R-Hand"] = v(3022, 0, 105),
  ["Bip001-L-Thigh"] = v(2990, 0, 90), ["Bip001-L-Calf"] = v(2990, 0, 50), ["Bip001-L-Foot"] = v(2990, 0, 10),
  ["Bip001-R-Thigh"] = v(3010, 0, 90), ["Bip001-R-Calf"] = v(3010, 0, 50), ["Bip001-R-Foot"] = v(3010, 0, 10),
}
local mmesh = F.obj("FarMesh", "SkeletalMeshComponent", { SkeletalMesh = F.obj("CH_M_NA_26", "SkeletalMesh") })
mmesh.GetSocketLocation = function(_, b) return bp[tostring(b)] or v(3000, 0, 100) end
mmesh.IsSimulatingPhysics = function() return true end
mmesh.IsVisible = function() return true end
mmesh.GetNumMaterials = function() return 0 end
local mobj = F.obj("CH_M_NA_26_Blueprint_C_1", "CH_M_NA_26_Blueprint_C",
  { Mesh = mmesh, bActorIsBeingDestroyed = false, bHidden = false })
mobj.K2_GetActorLocation = function() return v(3000, 0, 100) end
mobj.K2_GetComponentsByClass = function() return {} end
local chars = { { obj = mobj, addr = mobj:GetAddress(), cls = "CH_M_NA_26_Blueprint_C", k = "k1" } }
local pawn = F.obj("Eve", "CH_P_EVE_01_Blueprint_C", {})
pawn.K2_GetActorLocation = function() return v(0, 0, 100) end
local herMesh = F.obj("EveMesh", "SkeletalMeshComponent")
herMesh.GetSocketLocation = function() return v(10, 0, 150) end
local calls = {}
local ctx = { tune = tune, try = try, valid = valid, log = function(s) logs[#logs + 1] = s end,
  live_chars = function() return chars end, keep = function(o) return { obj = o } end, held = function() return true end,
  newobj = { watch = function() end },
  gore = { busy = function() return false end,
    enemy_cut = function(owner, obj, mesh, h, kind, face, mute, noCore)
      calls[#calls + 1] = { kind = kind, mute = mute, noCore = noCore }
      return nil
    end,
    enemy_hit = function() end, enemy_cuts = function() return 0, false end } }
local E = dofile("ue4ss/Mods/StellarBladeGore/Scripts/enemies.lua")
E.init(ctx)
local rnd = math.random
math.random = function(a) if a then return 1 else return 0.99 end end
E.tick(pawn, herMesh)
E.tick(pawn, herMesh)
math.random = rnd
check(#calls >= 1, "a far kill still cuts (" .. #calls .. " attempts)")
check(calls[1] and calls[1].mute == true, "a far basic kill is muted")
check(calls[1] and calls[1].noCore == true, "a far naytiba kill skips the metal core")
local leftWhole = false
for _, l in ipairs(logs) do if l:find("left whole") then leftWhole = true end end
check(not leftWhole, "no left-whole for a far kill")
for _, e in ipairs(F.errors) do print("hook error: " .. e) end
check(#F.errors == 0 and not F.find("tick error"), "no errors")
print(fails == 0 and "PASS" or "FAIL")
