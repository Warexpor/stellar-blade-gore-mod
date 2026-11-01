-- F7 a second after her ponytail reset made her meshes query only (an outfit's bodies re-made just before): their
-- collision given back before the ragdoll sets its own. Given back a tick after, it put her hair's collision on
-- again over the ragdoll's off (her head's bodies shoved by her hair: she flew 9 m up, playtest), and her mesh's
-- query only was what the ragdoll's end put back
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
F.sbslice.c = "ok verts=100 mode=0 limb=50 seam=10 vanished=0 unsunk=0 reweighted=2 stuck=0 watched=0 sinks=1,2 new=2 sinkmoved=2 held=2 active=10/0 cyc=1/0/0 pieces=0"
local print = F.say
local f = assert(io.open("ue4ss/Mods/StellarBladeGore/Scripts/settings.lua", "w"))
f:write('local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")\ns.dev = true\ns.gore.bone = "Bip001-L-Thigh"\nreturn s\n')
f:close()
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
local function dump(from, pat)
  for i, x in ipairs(F.log_lines()) do if i >= from and (not pat or x:find(pat)) then print("  | " .. x:sub(1, 240)) end end
end

local mesh = E.mesh
local SMC = "/Script/Engine.SkeletalMeshComponent"
local hairLog = {}
local hair = F.obj("SBHair", "SkeletalMeshComponent", {
  coll = 3,
  GetCollisionEnabled = function(self) return rawget(self, "coll") end,
  SetCollisionEnabled = function(self, v) rawset(self, "coll", v); hairLog[#hairLog + 1] = v end,
})
rawset(hair, "__isa", { [SMC] = true })
rawset(F.objects[SMC], "__path", SMC)
rawset(mesh, "__isa", { [SMC] = true })
local root = F.obj("Root", "CapsuleComponent", { AttachChildren = { ForEach = function(_, fn)
  fn(1, { get = function() return mesh end }); fn(2, { get = function() return hair end }) end } })
rawset(pawn, "RootComponent", root)
rawset(pawn, "SBHair", hair)

-- her respawn's reset: query only from 4 s on for 1.5 s; F7 inside it
local at = mark()
E.respawn()
F.run(4.5, pawn)
check(F.find("her ponytail reset %(NotifyBP_ReInitActor%): 2 mesh%(es%), 2 of them query only", at) ~= nil, "her meshes query only")
check(rawget(hair, "coll") == 1 and E.coll == 1, "both query only before F7")
hairLog = {}
check(F.press("F7", ""), "F7 bound")
F.run(2, pawn)
check(F.find("collision given back before her ragdoll %(2%)", at) ~= nil, "given back before the ragdoll")
check(F.find("collision given back early", at) == nil, "not given back a tick into it")
check(rawget(hair, "coll") == 0, "her hair has no collision in the ragdoll (" .. tostring(rawget(hair, "coll")) .. ")")
F.press("F8", "")
F.run(3, pawn)
check(rawget(hair, "coll") == 3, "her hair's collision back on after (" .. tostring(rawget(hair, "coll")) .. ")")
check((E.coll or 3) ~= 1, "her mesh not left query only after (" .. tostring(E.coll) .. ")")
if fails > 0 then dump(at, "cloth"); dump(at, "ragdoll") end

-- CNS bone probe captures relative pose and scale before and after a manual ragdoll.
local oldSk, oldIndex, oldParent, oldTransform = rawget(mesh, "SkeletalMesh"), rawget(mesh, "GetBoneIndex"),
  rawget(mesh, "GetParentBone"), rawget(mesh, "GetSocketTransform")
rawset(mesh, "SkeletalMesh", F.obj("CNS_Test", "SkeletalMesh", { GetFullName = function()
  return "SkeletalMesh /Game/CNSRepacked/5a2518e03d16a0cd/test/outfit.outfit" end }))
local blend, all = {}, nil
rawset(mesh, "bBlendPhysics", true)
rawset(mesh, "SetEnablePhysicsBlending", function(self, v) rawset(self, "bBlendPhysics", v) end)
rawset(mesh, "SetAllBodiesPhysicsBlendWeight", function(self, v) all = v end)
rawset(mesh, "SetAllBodiesBelowPhysicsBlendWeight", function(self, b, v) blend[b:ToString()] = v end)
rawset(mesh, "GetBoneIndex", function(self, b)
  if b:ToString() == "Ab-L-Breast" then return 1 end
  if b:ToString() == "Dm-L-Breast" or b:ToString() == "Dm-R-Breast" then return 1 end
  return oldIndex and oldIndex(self, b) or -1
end)
rawset(mesh, "GetParentBone", function(self, b)
  if b:ToString() == "Ab-L-Breast" then return F.fname("ProbeParent") end
  return oldParent and oldParent(self, b) or F.fname("None")
end)
rawset(mesh, "GetSocketTransform", function(self, b, space)
  if b:ToString() == "Ab-L-Breast" or b:ToString() == "ProbeParent" then
    return { Translation = { X = b:ToString() == "Ab-L-Breast" and 3 or 0, Y = 4, Z = 0 },
      Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
  end
  return oldTransform and oldTransform(self, b, space)
end)
at = mark()
F.press("F7", "")
F.run(3.5, pawn)
check(F.find("breast probe before F7 L: Ab%-L%-Breast parent=ProbeParent d=3%.00", at) ~= nil,
  "CNS breast probe records the pre-ragdoll parent distance")
check(F.find("breast probe 1 s L:", at) ~= nil and F.find("breast probe 3 s L:", at) ~= nil,
  "CNS breast probe records the ragdoll at 1 and 3 seconds")
check(all == 1 and blend["Dm-L-Breast"] == 0 and blend["Dm-R-Breast"] == 0
  and rawget(mesh, "bBlendPhysics") == false, "dress uses animation for breast chains including their parents")
F.press("F8", "")
F.run(1, pawn)
check(rawget(mesh, "bBlendPhysics") == true, "original forced physics blend restored after recovery")
rawset(mesh, "ClothBlendWeight", 0.7)
at = mark()
check(F.press("F9", ""), "F9 cut bound")
F.run(2, pawn)
check(rawget(mesh, "ClothBlendWeight") == 0 and F.find("wedding cloth: using skinned clothing after cut", at) ~= nil,
  "a cut switches wedding cloth to skinned form")
F.press("F8", "")
F.run(1, pawn)
check(rawget(mesh, "ClothBlendWeight") == 0.7, "recovery restores the original cloth blend")
rawset(mesh, "SkeletalMesh", F.obj("Other_CNS", "SkeletalMesh", { GetFullName = function()
  return "SkeletalMesh /Game/CNSRepacked/another/outfit.outfit" end }))
blend, all = {}, nil
F.press("F7", "")
F.run(1, pawn)
check(next(blend) == nil and all == nil and rawget(mesh, "bBlendPhysics") == true,
  "other CNS outfits do not get the dress blend override")
F.press("F8", "")
F.run(1, pawn)
rawset(mesh, "SkeletalMesh", oldSk)
rawset(mesh, "GetBoneIndex", oldIndex)
rawset(mesh, "GetParentBone", oldParent)
rawset(mesh, "GetSocketTransform", oldTransform)

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
