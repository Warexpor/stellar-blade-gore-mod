-- Play As (playas.lua): Tachy's body and face on Eve's own components and her hair hidden; what the game puts back set
-- again; Raven's hair on a component of its own on her pose; Scarlet without the DLC changes nothing; never while she
-- is dead or a cut on her alive is out; Eve again gives back every mesh and shows what was hidden
local F = require("fake")
local print = F.say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function asset(path) local o = F.obj(path:match("([^.]+)$"), "SkeletalMesh"); F.objects[path] = o; return o end
local P = "/Game/Art/Character/"
local tBody = asset(P .. "NPC/CH_NPC_TachyNPC/CH_NPC_TachyNPC_Body.CH_NPC_TachyNPC_Body")
local tFace = asset(P .. "NPC/CH_NPC_TachyNPC/CH_NPC_TachyNPC_Face_Jali2.CH_NPC_TachyNPC_Face_Jali2")
local rBody = asset(P .. "PC/CH_P_EVE_11/CH_P_EVE_11.CH_P_EVE_11")
local rHair = asset(P .. "Monster/CH_M_NA_53/CH_M_NA_53_Hair.CH_M_NA_53_Hair")
local tSword = asset(P .. "Weapon/Sword/CH_W_Sword_02/CH_W_Sword_02.CH_W_Sword_02")
local rBlade = asset(P .. "Monster/CH_M_NA_53/CH_M_NA_53_Weapon.CH_M_NA_53_Weapon")
F.objects["/Script/Engine.SkeletalMeshComponent"] = F.obj("SkeletalMeshComponent", "Class")
local eveBody, eveFace, eveHair = F.obj("CH_P_EVE_01", "SkeletalMesh"), F.obj("CH_P_EVE_Face_Jali3", "SkeletalMesh"), F.obj("CH_P_EVE_Hair", "SkeletalMesh")
local function comp(name, sm)
  local c = F.obj(name, "SkeletalMeshComponent", { SkeletalMesh = sm, vis = true })
  c.SetSkeletalMesh = function(self, m) self.SkeletalMesh = m end
  c.SetVisibility = function(self, v) self.vis = v end
  c.IsVisible = function(self) return self.vis end
  return c
end
local eveSword, eveFolded = F.obj("CH_W_Sword_01", "SkeletalMesh"), F.obj("CH_W_Sword_01_Folded", "SkeletalMesh")
local body, face, hair = comp("Body", eveBody), comp("Face", eveFace), comp("Hair", eveHair)
local sword = comp("Weapon1", eveSword)
local list = { { MeshSlot = 0, MeshComponent = body }, { MeshSlot = 1, MeshComponent = face }, { MeshSlot = 2, MeshComponent = hair },
  { MeshSlot = 5, MeshComponent = sword } }
local added = {}
local pawn = F.obj("Eve", "CH_P_EVE_01_Blueprint_C", { Mesh = body,
  MeshInfoList = { ForEach = function(_, f) for i, x in ipairs(list) do f(i, { get = function() return x end }) end end } })
pawn.AddComponentByClass = function()
  local c = comp("Extra" .. (#added + 1), nil)
  c.SetMasterPoseComponent = function(self, m) self.master = m end
  c.K2_DestroyComponent = function(self) self.destroyed = true end
  added[#added + 1] = c
  return c
end
local tune = dofile("ue4ss/Mods/StellarBladeGore/Scripts/tune.lua")
local logs, cutsOn = {}, 0
local ctx = { tune = tune, log = function(s) logs[#logs + 1] = s; print("  | " .. s) end,
  try = function(f) local ok, r = pcall(f); if ok then return r end end, valid = function(x) return x ~= nil and x ~= false end,
  gore = { cuts_on = function() return cutsOn end }, may_load = function() return true end }
local PA = dofile("ue4ss/Mods/StellarBladeGore/Scripts/playas.lua")
PA.init(ctx)
local function tick(dead) F.t = F.t + 1.1; PA.tick(pawn, body, dead) end

tick()
check(body.SkeletalMesh == eveBody, "Eve: nothing changed")
tune.playAs.who = "tachy"
tick()
check(body.SkeletalMesh == tBody and face.SkeletalMesh == tFace, "Tachy: her body and face on Eve's components")
check(hair.vis == false, "Eve's hair hidden")
check(sword.SkeletalMesh == tSword, "Tachy's sword in place of Eve's")
body.SkeletalMesh = eveBody -- (the game's outfit put back)
tick()
check(body.SkeletalMesh == tBody, "the game's outfit put back: Tachy's set again")
body.SkeletalMesh = eveBody
tick(true)
check(body.SkeletalMesh == eveBody, "not while she is dead")
cutsOn = 1
tick()
check(body.SkeletalMesh == eveBody, "not while a cut on her alive is out")
cutsOn = 0
tick()
tune.playAs.who = "raven"
tick()
check(body.SkeletalMesh == rBody and face.SkeletalMesh == eveFace, "Raven: her suit on Eve's body, Eve's face back")
check(added[1] and added[1].SkeletalMesh == rHair and added[1].master == body, "Raven's hair on a component of its own, on Eve's pose")
check(hair.vis == false, "Eve's hair hidden for Raven")
check(sword.SkeletalMesh == rBlade, "Raven's blade in place of Eve's")
sword.SkeletalMesh = eveFolded -- (the game folds her sword away)
tick()
check(sword.SkeletalMesh == eveFolded, "her sword folded away by the game: left as the game has it")
sword.SkeletalMesh = eveSword -- (and draws it again)
tick()
check(sword.SkeletalMesh == rBlade, "drawn again: Raven's blade again")
tune.playAs.who = "scarlet"
tick()
check(body.SkeletalMesh == eveBody and added[1].destroyed and hair.vis == true, "Scarlet without the DLC: back as Eve, nothing else")
local said = false
for _, l in ipairs(logs) do if l:find("needs its DLC") then said = true end end
check(said, "the log says Scarlet needs her DLC")
tune.playAs.who = "tachy"; tick()
tune.playAs.who = "eve"; tick()
check(body.SkeletalMesh == eveBody and face.SkeletalMesh == eveFace and hair.vis == true and sword.SkeletalMesh == eveSword,
  "Eve again: her own body, face, hair and sword")
print(fails == 0 and "PASS" or "FAIL")
