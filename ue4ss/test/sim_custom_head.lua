-- A custom head swap (CNS, TK_Scarlet_Head): its face mesh on a component of its own, hers hidden
-- or the slot empty. Beheads cut the custom head, head smashes hide it, and a foreign-skeleton head falls back
-- to cutting the slot's face, as before.
local T = require("smash_world").boot('s.gore.blood = false')
local F, E, G, pawn = T.F, T.E, T.G, T.pawn
local print, fails = F.say, 0
local function check(c, what) print((c and "ok   " or "FAIL ") .. what); if not c then fails = fails + 1 end end
local function run(seconds)
  for _ = 1, math.floor(seconds * 60 + 0.5) do F.step(1/60); G.tick(pawn); G.pump() end
end

-- her slot face, hidden by the head swap (shown for the vanilla control first)
local slotShown = true
local slotFace = F.obj("Face", "SkeletalMeshComponent", {
  SkeletalMesh = F.obj("CH_P_EVE_Face", "SkeletalMesh"),
  GetBoneIndex = E.mesh.GetBoneIndex,
  GetSocketLocation = E.mesh.GetSocketLocation,
  GetSocketTransform = E.mesh.GetSocketTransform,
  GetNumBones = E.mesh.GetNumBones,
  GetBoneName = E.mesh.GetBoneName,
  IsVisible = function() return slotShown end,
})
rawset(pawn, "MeshInfoList", { ForEach = function(_, cb)
  cb(1, { get = function() return { MeshSlot = 1, MeshComponent = slotFace } end })
end })

local function headComp(name, asset, shown, boneIndex)
  local on = shown
  return F.obj(name, "SkeletalMeshComponent", {
    SkeletalMesh = asset,
    IsVisible = function() return on end,
    SetVisibility = function(_, v) on = v and true or false end,
    isHidden = function() return not on end,
    GetBoneIndex = boneIndex or E.mesh.GetBoneIndex,
    GetSocketLocation = E.mesh.GetSocketLocation,
    GetSocketTransform = E.mesh.GetSocketTransform,
    GetNumBones = E.mesh.GetNumBones,
    GetBoneName = E.mesh.GetBoneName,
    GetNumMaterials = function() return 1 end,
    MasterPoseComponent = { Get = function() return E.mesh end },
  }), function() return on end
end

local root = F.obj("Root", "CapsuleComponent", { AttachChildren = { ForEach = function(_, f)
  f(1, { get = function() return E.mesh end })
end } })
rawset(pawn, "RootComponent", root)
rawset(E.mesh, "AttachChildren", { ForEach = function(_, f) end })

-- vanilla control: a visible slot face is her face, no search
check(G.face_of(pawn, E.mesh) == slotFace, "a visible slot face is her face")

-- the swap's head on her tree, master-posed, her bones; the slot hidden
slotShown = false
local customAsset = F.obj("TK_Scarlet_Head", "SkeletalMesh")
local custom, customOn = headComp("TK_Scarlet_Head_Comp", customAsset, true)
rawset(E.mesh, "AttachChildren", { ForEach = function(_, f) f(1, { get = function() return custom end }) end })
check(G.face_of(pawn, E.mesh) == custom, "a visible custom head on her tree is her face")
local found = false
for _, c in ipairs(G.hair_of(pawn)) do if c == custom then found = true end end
check(found, "the custom head counts as hair")

-- a head smash hides it, recovery shows it again
G.smashed.hide({ pawn = pawn, mesh = E.mesh, bone = "Bip001-Head", c = {} })
check(customOn() == false, "a head smash hides the custom head")
G.smashed.back()
check(customOn() == true, "recovery shows the custom head again")

-- a behead cuts it
local at = #F.log_lines() + 1
check(G.slice_bone(pawn, E.mesh, "Bip001-Head", nil, "test"), "a behead on a custom head starts")
run(3)
local cutCustom, skipped = false, false
for i, x in ipairs(F.log_lines()) do if i >= at then
  if x:find("face TK_Scarlet_Head", 1, true) and x:find(": ok") then cutCustom = true end
  if x:find("head skipped", 1, true) then skipped = true end
end end
check(cutCustom, "the behead cuts the custom head")
check(F.find("cut Bip001%-Head %(test%)", at) ~= nil, "the head comes off")
check(not skipped, "no head skipped on a custom head")
G.cleanup(pawn, E.mesh)

-- the old variant hidden, as the swap does; the ModActor-owned one off her tree, posed off her body
custom:SetVisibility(false)
rawset(E.mesh, "AttachChildren", { ForEach = function(_, f) end })
local modActor = F.obj("CNS_ModActor", "ModActor", {})
local custom2Asset = F.obj("TK_Scarlet_Head", "SkeletalMesh")
local custom2 = headComp("TK_Scarlet_Head_Mod", custom2Asset, true)
rawset(custom2, "GetOwner", function() return modActor end)
F.classes["SkeletalMeshComponent"] = { custom2 }
check(G.face_of(pawn, E.mesh) == custom2, "a ModActor-owned custom head posed off her is her face")
F.classes["SkeletalMeshComponent"] = nil
custom2:SetVisibility(false)

-- a custom head without her bones (its own skeleton): the slot's face is cut instead, as before
local foreignAsset = F.obj("TK_Scarlet_Head", "SkeletalMesh")
local foreign = headComp("TK_Scarlet_Head_Foreign", foreignAsset, true, function() return -1 end)
rawset(E.mesh, "AttachChildren", { ForEach = function(_, f) f(1, { get = function() return foreign end }) end })
at = #F.log_lines() + 1
check(G.slice_bone(pawn, E.mesh, "Bip001-Head", nil, "test"), "a behead with a foreign-skeleton head starts")
run(3)
local cutSlot, cutForeign, skipped2 = false, false, false
for i, x in ipairs(F.log_lines()) do if i >= at then
  if x:find("cutting the slot's face instead", 1, true) then cutSlot = true end
  if x:find("face TK_Scarlet_Head", 1, true) and x:find(": ok") then cutForeign = true end
  if x:find("head skipped", 1, true) then skipped2 = true end
end end
check(cutSlot, "a foreign-skeleton head falls back to the slot's face")
check(not cutForeign, "the foreign-skeleton head itself is not cut")
check(not skipped2, "the behead still goes through")
check(F.find("cut Bip001%-Head %(test%)", at) ~= nil, "the head comes off on the fallback")
G.cleanup(pawn, E.mesh)

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
check(#F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
