-- F7 a second after her ponytail reset made her meshes query only (an outfit's bodies re-made just before): their
-- collision given back before the ragdoll sets its own. Given back a tick after, it put her hair's collision on
-- again over the ragdoll's off (her head's bodies shoved by her hair: she flew 9 m up, playtest), and her mesh's
-- query only was what the ragdoll's end put back
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
local f = assert(io.open("ue4ss/Mods/StellarBladeGore/Scripts/settings.lua", "w"))
f:write('local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")\ns.dev = true\nreturn s\n')
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

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
