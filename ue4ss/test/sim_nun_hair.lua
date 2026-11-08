-- The nun outfit's veil rides the head: hair_of sees headwear, and a behead moves
-- a neck-riding veil onto the head while master-pose hair stays as it is.
local T = require("smash_world").boot('s.gore.blood = false')
local F, E, G, pawn = T.F, T.E, T.G, T.pawn
local print, fails = F.say, 0
local function check(c, what) print((c and "ok   " or "FAIL ") .. what); if not c then fails = fails + 1 end end
-- a veil posed by her mesh counts as hair
local veilHead = F.obj("VeilHead", "SkeletalMeshComponent", {
  SkeletalMesh = F.obj("CH_P_EVE_47_Veil", "SkeletalMesh"),
  IsVisible = function() return true end,
  MasterPoseComponent = { Get = function() return E.mesh end },
})
rawset(E.mesh, "AttachChildren", { ForEach = function(_, f) f(1, { get = function() return veilHead end }) end })
local found = false
for _, c in ipairs(G.hair_of(pawn)) do if c == veilHead then found = true end end
check(found, "veil on her pose counts as hair")
-- a veil riding her neck moves onto the head at the behead; master-pose hair does not move
local movedTo = nil
local shown = true
local waistMoved = false
local waistCloth = F.obj("NunWaist", "SkeletalMeshComponent", {
  SkeletalMesh = F.obj("NunHabit", "SkeletalMesh"),
  GetAttachSocketName = function() return F.fname("Bip001-Pelvis") end,
  K2_AttachToComponent = function() waistMoved = true; return true end,
})
local headRider = F.obj("Adornment", "SkeletalMeshComponent", {
  SkeletalMesh = F.obj("Accessory", "SkeletalMesh"), AttachSocketName = F.fname("SC_Adornment"),
  IsVisible = function() return true end,
})
rawset(E.mesh, "GetSocketBoneName", function(_, sock)
  return F.fname(tostring(sock) == "SC_Adornment" and "Bip001-Head" or tostring(sock))
end)
local veilNeck = F.obj("VeilNeck", "SkeletalMeshComponent", {
  SkeletalMesh = F.obj("CH_P_EVE_47_Veil", "SkeletalMesh"),
  AttachSocketName = F.fname("Bip001-Neck"),
  IsVisible = function() return shown end,
  SetVisibility = function(_, on) shown = on end,
  RelativeLocation = { X = 1, Y = 2, Z = 3 }, RelativeRotation = { Pitch = 4, Yaw = 5, Roll = 6 },
  RelativeScale3D = { X = 1, Y = 2, Z = 1 },
  GetAttachSocketName = function() return F.fname("Bip001-Neck") end,
  K2_AttachToComponent = function(_, parent, sock) movedTo = { parent = parent, sock = sock }; return true end,
  K2_SetRelativeLocationAndRotation = function(self, p, r) self.restoredPosition, self.restoredRotation = p, r end,
  SetRelativeScale3D = function(self, s) self.restoredScale = s end,
})
rawset(E.mesh, "AttachChildren", { ForEach = function(_, f)
  f(1, { get = function() return veilHead end })
  f(2, { get = function() return veilNeck end })
  f(3, { get = function() return waistCloth end })
  f(4, { get = function() return headRider end })
end })
found = false
for _, c in ipairs(G.hair_of(pawn)) do if c == veilNeck then found = true end end
check(found, "neck-riding veil counts as hair before a beheading")
found = false
for _, c in ipairs(G.hair_of(pawn)) do if c == headRider then found = true end end
check(found, "a socket with an unrelated name resolves to its head bone")
G.smashed.hide({ pawn = pawn, mesh = E.mesh, bone = "Bip001-Head", c = {} })
check(not shown, "head smash hides the neck-riding veil")
G.smashed.back()
check(shown, "recovery shows the veil again")
check(G.headwear_to_head(pawn, E.mesh) == 1, "neck veil moves to the head")
check(not waistMoved, "similarly named clothing on the waist is not moved to the head")
check(movedTo and movedTo.parent == E.mesh, "veil re-attached to her mesh")
local sname = movedTo and movedTo.sock and movedTo.sock:ToString()
check(sname == "Bip001-Head", "veil rides the head bone (" .. tostring(sname) .. ")")
G.cleanup(pawn, E.mesh)
check(movedTo and movedTo.sock:ToString() == "Bip001-Neck", "recovery restores the original socket")
check(veilNeck.restoredPosition and veilNeck.restoredPosition.Z == 3 and veilNeck.restoredRotation.Yaw == 5
  and veilNeck.restoredScale.Y == 2, "recovery restores the original relative transform")
rawset(E.mesh, "AttachChildren", nil)
check(#F.errors == 0, "no errors (" .. table.concat(F.errors, "; ") .. ")")
print(fails == 0 and "PASS" or "FAIL")
