-- The death-screen class is expensive to look up; hold it safely while registering its six hooks.
local F, E = require("fake"), require("eve")
local print = F.say
local pawn = E.make(F)
local path = "/Game/Art/UI/Widget/HUD/WB_MainHUD_Dead.WB_MainHUD_Dead_C"
local lookup, original = 0, StaticFindObject
StaticFindObject = function(p) if p == path then lookup = lookup + 1 end; return original(p) end
assert(pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua"))
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
local function hooked()
  local n = 0
  for name in pairs(F.hooks) do if name:sub(1, #path + 1) == path .. ":" then n = n + 1 end end
  return n
end
for _ = 1, 1800 do F.step(1/60, pawn); if hooked() >= 1 then break end end
local first = hooked()
local old = F.objects[path]
old.__freed = true
F.objects[path] = F.obj("WB_MainHUD_Dead_C_new", "Class")
F.run(8, pawn)
local pass = first == 1 and hooked() == 6 and lookup == 2 and #F.errors == 0
print(string.format("%s  six hooks registered, class replaced safely; %d lookups, %d errors", pass and "ok" or "FAIL", lookup, #F.errors))
print(pass and "PASS" or "FAIL")
