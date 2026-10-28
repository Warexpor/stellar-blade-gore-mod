-- Customized Ragdoll (Nexus 3884) support (customizedRagdoll): its A_RagdollManager kept on her, Active, while she
-- lives (its death notify then leaves her physics alone), its camera modifier on through her death and off as she
-- is up, and the death screen up as the game puts it but see-through (render opacity 0, never collapsed: its keys
-- work), Shift+F4 showing it
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.customizedRagdoll = true
return s
]])
f:close()

-- that mod's classes, the manager it spawns and the camera manager
local FAC = "/Game/Art/Character/PC/CH_P_EVE_01/Animation/Facial/"
F.objects[FAC .. "A_RagdollManager.A_RagdollManager_C"] = F.obj("A_RagdollManager_C", "Class")
F.objects[FAC .. "CM_Ragdoll.CM_Ragdoll_C"] = F.obj("CM_Ragdoll_C", "Class")
local mgrs, mods, removed = {}, {}, {}
local pcm = F.obj("PlayerCameraManager_0", "PlayerCameraManager", {
  AddNewCameraModifier = function(_, cls)
    local m = F.obj("CM_Ragdoll_C_" .. #mods, "CM_Ragdoll_C", { cls = cls })
    mods[#mods + 1] = m
    return m
  end,
  RemoveCameraModifier = function(_, m) removed[#removed + 1] = m; return true end,
})
F.objects["/Script/Engine.Default__GameplayStatics"] = F.obj("Default__GameplayStatics", "GameplayStatics", {
  BeginDeferredActorSpawnFromClass = function(_, _, cls)
    local m = F.obj("A_RagdollManager_C_" .. #mgrs, "A_RagdollManager_C", { cls = cls, Active = false, BlendAmount = 0,
      K2_AttachToActor = function(self, to) self.attached = to end,
      K2_DestroyActor = function(self) self.__dead = true end })
    mgrs[#mgrs + 1] = m
    return m
  end,
  FinishSpawningActor = function(_, a) return a end,
  GetPlayerCameraManager = function() return pcm end,
})

local ok, err = pcall(dofile, DIR .. "main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function mark() return #F.log_lines() + 1 end
local function dump(from)
  for i, x in ipairs(F.log_lines()) do if i >= from then print("  | " .. x:sub(1, 200)) end end
end

-- 1: alive, the manager on her before any death (its notify is the death's first frame)
local m = mgrs[1]
check(#mgrs == 1 and m ~= nil, "a manager spawned while she lives (" .. #mgrs .. ")")
check(m and m.Active == true, "it is Active: its notify's Process does nothing")
check(m and m.Mesh == E.mesh and m.BlendAmount == 1.0, "pointed at her mesh, nothing to blend")
check(m and m.attached == pawn, "attached to her")
F.run(5, pawn)
check(#mgrs == 1, "kept, not spawned again (" .. #mgrs .. ")")

-- 2: her death: its camera on (not the mod's held camera), the death screen up but see-through
local at = mark()
E.die(true)
local w = E.deadScreen
local op = {}
rawset(w, "SetRenderOpacity", function(_, v) op[#op + 1] = v end)
F.run(2, pawn)
check(#mods == 1 and mods[1].cls == F.objects[FAC .. "CM_Ragdoll.CM_Ragdoll_C"], "its camera modifier added")
check(not F.find("camera: view held", at), "the mod's own held camera not used")
F.run(3, pawn)
local vis = w.__w.vis
check(vis ~= 1 and vis ~= 2, "the death screen not collapsed 5 s in (its keys work)")
check(op[#op] == 0, "the death screen see-through (opacity " .. tostring(op[#op]) .. ")")
F.run(8, pawn)
check(op[#op] == 0 and w.__w.vis ~= 1 and w.__w.vis ~= 2, "still up and see-through 13 s in, no delay or hold")
check(F.find("see%-through %(Customized Ragdoll support%)", at) ~= nil, "told in the log")

-- 3: Shift+F4 shows it, fading in
local n = #op
check(F.press("F4", "SHIFT"), "Shift+F4 bound")
F.run(1.5, pawn)
check(#op > n and op[#op] == 1, "Shift+F4: shown, faded in to 1 (" .. tostring(op[#op]) .. ")")
if fails > 0 then dump(at) end

-- 4: the game's respawn: its camera off, the manager still there
at = mark()
E.respawn()
F.run(6, pawn)
check(#removed == 1 and removed[1] == mods[1], "its camera modifier removed as she is up")
check(F.find("its death camera off", at) ~= nil, "told in the log")
check(#mgrs == 1 and mgrs[1].Active == true, "the manager kept Active through it")
if fails > 0 then dump(at) end

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
