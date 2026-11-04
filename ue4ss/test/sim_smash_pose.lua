-- A bare-hand killing blow is judged on her pose at the blow, not her ragdoll-moved body.
-- Replays the installed session's repeated left-forearm blunt smash: the swing-time point at her chest
-- (Spine2) must smash her upper body even after the death launch carries her live bones 40 cm off it.
local T=require("smash_world").boot('s.gore.smash = { enabled = true }\ns.gore.blood = false')
local F,E,G,pawn,v=T.F,T.E,T.G,T.pawn,T.v
local print,fails=F.say,0
local function check(c,s) print((c and "ok   " or "FAIL ")..s); if not c then fails=fails+1 end end
local function run(sec) for _=1,math.floor(sec*60+0.5) do F.step(1/60); G.tick(pawn); G.pump() end end
-- The blow-time point and body: her chest as the enemy's hand met it.
local at=E.bone("Bip001-Spine2")
check(G.smash_part(E.mesh,at)=="Bip001-Spine1","chest blow smashes the upper body")
-- Her blow-time pose, as main.lua notes it with every swing sample.
local pose={}
for _,b in ipairs(G.pose_bones) do pose[b]={t=E.bone(b),q={X=0,Y=0,Z=0,W=1}} end
-- The death launch carries her live body 40 cm sideways; the stale world point now sits over the left arm.
local socket,transform=E.mesh.GetSocketLocation,E.mesh.GetSocketTransform
local shift={X=0,Y=-40,Z=0}
E.mesh.GetSocketLocation=function(self,b) local p=socket(self,b); return v(p.X+shift.X,p.Y+shift.Y,p.Z+shift.Z) end
E.mesh.GetSocketTransform=function(self,b) local t=transform(self,b)
  t.Translation=v(t.Translation.X+shift.X,t.Translation.Y+shift.Y,t.Translation.Z+shift.Z); return t end
local stale=G.smash_part(E.mesh,at)
check(stale=="Bip001-L-UpperArm" or stale=="Bip001-L-Forearm",
  "stale live bones mis-target the trailing left arm ("..tostring(stale)..")")
check(stale~="Bip001-Spine1","stale live bones lose the upper body")
local fixed=G.smash_part(E.mesh,at,nil,pose)
check(fixed=="Bip001-Spine1","blow-time pose keeps the chest blow on the upper body ("..tostring(fixed)..")")
-- End to end: the posed smash removes the torso, leaving the left forearm alone.
E.s.sim=true
check(G.smash(pawn,E.mesh,{loc=at,pose=pose,pose_ago=0.11},"death"),"posed chest smash starts")
run(1)
check(E.hiddenBones["Bip001-Spine1"]==true,"posed smash removes the upper body, not the left forearm")
check(E.hiddenBones["Bip001-L-Forearm"]==nil and E.hiddenBones["Bip001-L-UpperArm"]==nil,
  "posed smash leaves the left arm alone")
G.cleanup(pawn,E.mesh)
run(0.2)
E.mesh.GetSocketLocation,E.mesh.GetSocketTransform=socket,transform
-- Without a pose (projectile reports) behavior is unchanged.
check(G.smash_part(E.mesh,at)=="Bip001-Spine1","no-pose targeting still smashes the chest blow")
for _,e in ipairs(F.errors) do print("FAIL hook: "..e); fails=fails+1 end
for _,l in ipairs(F.log_lines()) do
  if l:find("smash failed") or l:find("delayed step failed") or l:find("failed at stage") then print("FAIL log: "..l); fails=fails+1 end
end
print(fails==0 and "PASS" or "FAIL")
