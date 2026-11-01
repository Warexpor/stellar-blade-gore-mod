-- Batch cancellation, multipart visibility, no-face failures, repeated deaths and real respawn hooks.
local T = require("smash_world").boot([[
s.gore.smash = { enabled = true, always = true }
s.active.animated = false
s.gore.afterHits = { enabled = false }
s.deathMoves = false
s.gore.blood = false
]])
local F, E, G, pawn, W, v = T.F, T.E, T.G, T.pawn, T.world, T.v
local print, fails = F.say, 0
local function check(c, what) print((c and "ok   " or "FAIL ") .. what); if not c then fails = fails + 1 end end
local function frames(n) for _ = 1, n do F.step(1/60); G.tick(pawn); G.pump() end end
local function live() local n=0; for _, a in ipairs(W.actors) do if not a.__dead then n=n+1 end end; return n end
local hair = F.obj("Hair", "SkeletalMeshComponent", {
  visible = true,
  IsVisible = function(self) return self.visible end,
  SetVisibility = function(self, b) self.visible = b end,
})
pawn.SBHair = hair
local earring = F.obj("Earring", "StaticMeshComponent", {
  visible = true,
  IsVisible = function(self) return self.visible end,
  SetVisibility = function(self, b) self.visible = b end,
  GetAttachSocketName = function() return F.fname("Bip001-Head") end,
})
E.mesh.GetSocketBoneName = function(_, b) return b end
E.mesh.AttachChildren = { ForEach = function(_, cb) cb(1, { get = function() return earring end }) end }
-- Every default supported part through the actual death broadcast and respawn, not just calls into gore.lua.
local counts = { limb = 0, head = 0, torso = 0 }
math.randomseed(76412)
for i=1,90 do
  local g = T.ctx.tune.gore
  local wanted = ({ "limb", "head", "torso" })[(i-1)%3+1]
  g.death.limb, g.death.head, g.death.torso, g.death.split = 0, 0, 0, 0
  g.death[wanted] = 100
  local from, n0 = #F.log_lines()+1, #W.spheres
  E.s.hp = 0
  E.die(true)
  F.run(1.1, pawn)
  local line = F.find("smash %(death%):", from)
  local expected = wanted == "head" and 8 or wanted == "torso" and 44 or nil
  local got = #W.spheres-n0
  if not line or (expected and got ~= expected) or (not expected and got ~= 6 and got ~= 10 and got ~= 16) then
    check(false, "death " .. i .. ": " .. wanted .. " smash/chunk count (" .. got .. ")")
  else counts[wanted] = counts[wanted]+1 end
  if wanted ~= "limb" then
    if hair.visible or earring.visible or not T.face.hiddenBones[wanted == "head" and "Bip001-Head" or "Bip001-Spine1"] then
      check(false, "death " .. i .. ": hair, earring and face removed with " .. wanted)
    end
  end
  E.respawn()
  F.run(0.3, pawn)
  if live() ~= 0 or next(E.hiddenBones) or next(T.face.hiddenBones) or not hair.visible or not earring.visible then
    check(false, "death " .. i .. ": respawn left pieces or visibility changes")
  end
end
check(counts.limb==30 and counts.head==30 and counts.torso==30, "90 death/respawn cycles: 30 limb, 30 head and 30 torso smashes")
check(live()==0, "no surviving chunk actors after the soak")
-- Cancel between the first batch and the next. No deferred chunks may appear after recovery.
E.s.sim=true
local n0=#W.spheres
G.smash(pawn,E.mesh,{loc=E.bone("Bip001-Spine2")},"death")
local hiddenAt
for _=1,30 do
  frames(1)
  if E.hiddenBones["Bip001-Spine1"] and not hiddenAt then hiddenAt=F.t end
  if #W.spheres>n0 then break end
end
check(#W.spheres-n0==2, "torso burst is budgeted: first two chunks only")
check(hiddenAt and F.t-hiddenAt<=0.05, "first meat pieces appear within two ticks of the torso disappearing")
G.cleanup(pawn,E.mesh)
local made=#W.spheres
frames(90)
check(#W.spheres==made and live()==0, "recovery mid-burst cancels pending batches")
-- HideBone scales a subtree to zero; the burst must sample its centre before doing that.
local socket=E.mesh.GetSocketLocation
E.mesh.GetSocketLocation=function(self,b)
  if E.hiddenBones["Bip001-Head"] and tostring(b)=="Bip001-Head" then return E.bone("Bip001-Neck") end
  return socket(self,b)
end
n0=#W.spheres
G.smash(pawn,E.mesh,{loc=E.bone("Bip001-HeadNub")},"death")
for _=1,30 do frames(1); if #W.spheres>n0 then break end end
local sp=W.spheres[n0+1]
check(sp and sp.at.Z>=159, "head chunks originate in the skull, before hidden-bone transforms collapse")
G.cleanup(pawn,E.mesh)
E.mesh.GetSocketLocation=socket
-- A missing face must drop the failed cut without recording a phantom severed head or throwing.
local info=pawn.MeshInfoList
pawn.MeshInfoList=nil
local from=#F.log_lines()+1
G.smash(pawn,E.mesh,{loc=E.bone("Bip001-HeadNub")},"death")
frames(30)
check(not F.find("failed at stage",from) and #G.cut_parts(E.mesh)==0, "missing face: clean refusal, no phantom cut")
pawn.MeshInfoList=info
G.cleanup(pawn,E.mesh)
-- A component with no usable bone query must not be hidden speculatively.
local bad=F.obj("NoSkeleton","SkeletalMeshComponent",{GetBoneIndex=function() error("unavailable") end})
local hidden=0
bad.HideBoneByName=function() hidden=hidden+1 end
pawn.MeshInfoList={ForEach=function(_,cb) cb(1,{get=function() return {MeshComponent=bad} end}) end}
G.smashed.hide({pawn=pawn,mesh=E.mesh,bone="Bip001-L-UpperArm"})
check(hidden==0,"failed bone lookup never hides an unrelated component")
G.smashed.back()
pawn.MeshInfoList=info
check(#W.violations==0,"all soak chunks start physics with safe collision masks")
-- A torso smash must release a weapon before hiding its hand, and failures must retain its original attachment.
local rag = T.ctx.rag
local function upvalue(fn, wanted)
  for i = 1, 100 do local n, x = debug.getupvalue(fn, i); if not n then break end; if n == wanted then return x end end
  error("missing upvalue " .. wanted)
end
local grips = upvalue(rag.smash_drop, "gripped")
local originalParent = F.obj("SwordSocketParent", "SceneComponent")
local swordMesh = F.obj("Sword", "SkeletalMesh", { GetImportedBounds = function() return { Origin = v(0,0,0), BoxExtent = v(40,3,2) } end })
local sword = F.obj("SwordComp", "SkeletalMeshComponent", { SkeletalMesh = swordMesh, RelativeLocation = v(1,2,3), RelativeRotation = { Pitch=4,Yaw=5,Roll=6 }, parent = E.mesh, visible=true })
sword.IsVisible = function(self) return self.visible end
sword.GetAttachParent = function(self) return self.parent end
sword.GetAttachSocketName = function() return F.fname("Bip001-R-Hand") end
sword.K2_GetComponentLocation = function() return E.bone("Bip001-R-Hand") end
sword.K2_GetComponentRotation = function() return {Pitch=0,Yaw=0,Roll=0} end
sword.GetForwardVector = function() return v(1,0,0) end
sword.GetRightVector = function() return v(0,1,0) end
sword.GetUpVector = function() return v(0,0,1) end
sword.K2_AttachToComponent = function(self,parent) self.parent=parent end
sword.K2_SetRelativeLocationAndRotation = function(self,loc,rot) self.restored=loc.X==1 and rot.Yaw==5 end
local oldInfo, oldAdd = pawn.MeshInfoList, pawn.AddComponentByClass
pawn.MeshInfoList = { ForEach = function(_,cb) cb(1,{get=function() return {MeshSlot=5,MeshComponent=sword} end}) end }
local originalGrip = function() return { comp=sword, hand="Bip001-R-Hand", parent=originalParent, socket=F.fname("weapon"), loc=v(1,2,3), rot={Pitch=4,Yaw=5,Roll=6} } end
local box
pawn.AddComponentByClass = function()
  box=F.obj("SwordBox","BoxComponent",{BodyInstance={}})
  for _,n in ipairs({"K2_SetWorldLocationAndRotation","SetBoxExtent","SetHiddenInGame","SetCollisionProfileName","SetCollisionResponseToChannel","SetCollisionEnabled","SetSimulatePhysics","SetMassOverrideInKg","SetPhysicsLinearVelocity","SetPhysicsAngularVelocityInDegrees"}) do box[n]=function() end end
  box.K2_DestroyComponent=function(self) self.__dead=true end
  return box
end
grips[sword:GetAddress()]=originalGrip()
rag.smash_drop(pawn,E.mesh,"Bip001-Spine1")
check(sword.parent==box and not grips[sword:GetAddress()],"torso smash releases held sword onto its physics box")
rag.stop(pawn)
check(sword.parent==originalParent and sword.restored and box.__dead,"recovery returns dropped sword to original socket and transform")
-- No collision box is available: keep the grip for recovery even if the sword is subsequently hidden.
sword.parent, sword.restored, sword.visible = E.mesh, false, true
grips = upvalue(rag.smash_drop, "gripped")
grips[sword:GetAddress()]=originalGrip()
local boxClass=F.objects["/Script/Engine.BoxComponent"]
F.objects["/Script/Engine.BoxComponent"]=nil
rag.smash_drop(pawn,E.mesh,"Bip001-Spine1")
sword.visible=false
check(grips[sword:GetAddress()]~=nil,"failed sword drop keeps its original attachment")
local release = upvalue(rag.tick, "grip_release")
local runIndex, previousRun
for i=1,100 do local n,x=debug.getupvalue(release,i); if not n then break end; if n=="run" then runIndex,previousRun=i,x; break end end
assert(runIndex, "missing grip run state")
debug.setupvalue(release,runIndex,{})
release(pawn,E.mesh,T.ctx.tune.active)
debug.setupvalue(release,runIndex,previousRun)
check(grips[sword:GetAddress()]~=nil,"grip timer preserves attachment after a failed hidden-weapon drop")
rag.stop(pawn)
check(sword.parent==originalParent and sword.restored,"failed drop still restores sword on recovery")
F.objects["/Script/Engine.BoxComponent"]=boxClass
-- Animated deaths do not create a grip record: a weapon near the hand drops for a torso smash.
for _, bone in ipairs({"Bip001-Spine1"}) do
  sword.parent, sword.restored, sword.visible = originalParent, false, true
  rag.smash_drop(pawn,E.mesh,bone)
  check(sword.parent==box, "animated " .. bone .. ": held weapon drops without grip state")
  rag.stop(pawn)
  check(sword.parent==originalParent and sword.restored, "animated " .. bone .. ": recovery restores weapon")
end
-- The game's animated fall can retain a run despite never starting a weapon grip.
sword.parent, sword.restored, sword.visible = originalParent, false, true
debug.setupvalue(release,runIndex,{})
rag.smash_drop(pawn,E.mesh,"Bip001-Spine1")
check(sword.parent==box,"animated torso with an active run releases the held sword")
debug.setupvalue(release,runIndex,previousRun)
rag.stop(pawn)
check(sword.parent==originalParent and sword.restored,"animated torso with a run restores the sword")
sword.K2_GetComponentLocation = function() return v(100000,100000,100000) end
sword.parent=originalParent
rag.smash_drop(pawn,E.mesh,"Bip001-Spine1")
check(sword.parent==originalParent,"torso smash leaves a holstered weapon alone")
sword.K2_GetComponentLocation = function() return E.bone("Bip001-R-Hand") end
sword.parent=originalParent
rag.smash_drop(pawn,E.mesh,"Bip001-Head")
check(sword.parent==originalParent,"animated head smash leaves the held weapon with the animation")
sword.K2_GetComponentLocation = function() return v(100000,100000,100000) end
sword.parent=originalParent
rag.smash_drop(pawn,E.mesh,"Bip001-Head")
check(sword.parent==originalParent,"animated death leaves a weapon away from both hands alone")
-- Actual animated waist cut: the legs continue their fall while the upper body and held weapon separate.
sword.K2_GetComponentLocation = function() return E.bone("Bip001-R-Hand") end
sword.parent, sword.restored = originalParent, false
local oldAnimated, oldLegs = T.ctx.animated, T.ctx.tune.gore.torsoLegs
T.ctx.animated = function() return true end
T.ctx.tune.gore.torsoLegs = { enabled=true, rolled=1 }
E.s.sim = false
local fromWaist = #F.log_lines()+1
G.slice_bone(pawn,E.mesh,"Bip001-Spine1",nil,"death")
frames(35)
check(F.find("waist cut: her legs play the fall on",fromWaist) and sword.parent==box,
  "animated waist cut drops the sword when the upper body separates")
G.cleanup(pawn,E.mesh)
rag.stop(pawn)
check(sword.parent==originalParent and sword.restored,"waist-cut sword restores on recovery")
T.ctx.animated, T.ctx.tune.gore.torsoLegs = oldAnimated, oldLegs
-- A second cut callback may obtain a fresh wrapper for the same UE component.
-- It must recognize the existing split, instead of making a third visible sword half.
local splits = upvalue(rag.weapon_cut, "splits")
local wrapper = F.obj("SwordWrapper", "SkeletalMeshComponent", {
  SkeletalMesh=swordMesh, IsVisible=function() return true end,
  GetAddress=function() return sword:GetAddress() end,
  K2_GetComponentLocation=sword.K2_GetComponentLocation,
  GetForwardVector=sword.GetForwardVector, GetRightVector=sword.GetRightVector, GetUpVector=sword.GetUpVector,
})
local stored = {w=sword, b=F.obj("SwordHalf", "SkeletalMeshComponent")}
splits[#splits+1]=stored
pawn.MeshInfoList = {ForEach=function(_, cb) cb(1, {get=function() return {MeshSlot=5, MeshComponent=wrapper} end}) end}
F.objects["/Script/Engine.SkeletalMeshComponent"] = F.obj("SkeletalMeshComponent", "Class")
local cutlog = #F.log_lines()+1
local owner_before = E.mesh.GetOwner
E.mesh.GetOwner = function() return pawn end
rag.weapon_cut(E.mesh, E.bone("Bip001-R-Hand"), v(1,0,0), true)
check(F.find("in two already", cutlog) ~= nil and #splits==1,
  "repeated sword cut recognizes a fresh wrapper for the already split component")
splits[#splits]=nil
E.mesh.GetOwner = owner_before
F.objects["/Script/Engine.BoxComponent"], pawn.MeshInfoList, pawn.AddComponentByClass = boxClass, oldInfo, oldAdd
for _, e in ipairs(F.errors) do print("FAIL hook: "..e); fails=fails+1 end
for _, l in ipairs(F.log_lines()) do
  if l:find("tick error") or l:find("failed at stage") or l:find("delayed step failed") then print("FAIL log: "..l); fails=fails+1 end
end
print(fails==0 and "PASS" or "FAIL")
