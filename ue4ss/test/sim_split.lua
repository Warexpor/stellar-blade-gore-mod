-- Real split dispatch on the fake engine: stop pending/active death movements, stage cap work, and clean up.
local T = require("smash_world").boot('s.deathMoves=true\ns.gore.blood=false\ns.active.animated=false\ns.gore.caps=true\ns.gore.splitPush=0\ns.gore.splitTip=0\ns.gore.noSplits=false')
local F,E,G,ctx,pawn = T.F,T.E,T.G,T.ctx,T.pawn
local actualAnimated=ctx.animated
local R=require("rag")
R.install(F,E)
F.world=function(dt) T.world.step(dt); R.step(dt) end
local fails=0
local function check(c,s) F.say((c and "ok   " or "FAIL ")..s); if not c then fails=fails+1 end end
local function find(fn,wanted,seen)
  seen=seen or {}; if type(fn)~="function" or seen[fn] then return end; seen[fn]=true
  for i=1,math.huge do
    local name,v=debug.getupvalue(fn,i); if not name then break end
    if name==wanted then return v,fn,i end
    if name~="_ENV" and type(v)=="function" then
      local a,b,c=find(v,wanted,seen); if b then return a,b,c end
    end
  end
end
local function state(m) return find(m.tick,"st") end
local function run(n)
  for _=1,n do F.step(1/60); G.tick(pawn); G.pump(); ctx.convulse.tick(false); ctx.struggle.tick(false) end
end
local copies={}
F.objects["/Script/Engine.SkeletalMeshComponent"]=F.obj("SkeletalMeshComponent","Class")
pawn.AddComponentByClass=function()
  local props={}
  for k,v in pairs(E.mesh) do if k:sub(1,2)~="__" then props[k]=v end end
  local c=F.obj("SplitCopy"..(#copies+1),"SkeletalMeshComponent",props)
  c.SetSkeletalMesh=function(self,sm) self.SkeletalMesh=sm end
  c.SetHiddenInGame=function(self,on) self.hidden=on end
  c.SetMasterPoseComponent=function(self,m) self.master=m end
  c.SetCollisionEnabled=function(self,n) self.collision=n end
  c.GetCollisionEnabled=function(self) return self.collision or 0 end
  c.SetSimulatePhysics=function(self,on) self.sim=on end
  c.IsSimulatingPhysics=function(self) return self.sim==true end
  c.SetAllBodiesSimulatePhysics=c.SetSimulatePhysics
  copies[#copies+1]=c
  return c
end
F.sbslice.c="ok verts=62882 mode=4 limb=7912 seam=30000 vanished=30000 unsunk=0 reweighted=3786 stuck=0 far=0.0 sinks=100,85 new=2 sinkmoved=0 held=2 active=928/0 cyc=192/85/0 s0c=1000,2000,120 s0x=1000,0,0 s0z=0,1000,0 s0e=10,10,35 s0p=990,2000,95;1010,2000,95;1010,2000,145;990,2000,145"
F.sbslice.k="ok collapsed 2"
F.sbslice.p="ok pose"
F.sbslice.S="ok saved"
-- Keep the real outline, skinning and dispatcher. Only the engine's cap allocation is faked.
local split_caps=assert(find(G.pump_once,"split_caps"))
local cap,capfn,capi=find(split_caps,"cap")
local actors,events={},{}
local function event(k) events[#events+1]={kind=k,frame=F.frame} end
local function fakecap(_,comp,o,bone,built)
  event("mesh")
  local a=F.obj("Lid"..(#actors+1),"StaticMeshActor",{hidden=true})
  a.SetActorHiddenInGame=function(self,on) self.hidden=on end
  a.GetTransform=function() return {Translation=T.v(0,0,0),Rotation={X=0,Y=0,Z=0,W=1}} end
  local pmc=F.obj("LidPMC"..(#actors+1),"ProceduralMeshComponent")
  pmc.UpdateMeshSection_LinearColor=function(self,_,verts,normals) self.verts,self.normals=verts,normals end
  actors[#actors+1]={actor=a,pmc=pmc}
  return a,"lid",pmc
end
debug.setupvalue(capfn,capi,fakecap)
-- Cap and skin must never share a dispatch frame.
local skin,skinfn,skini=find(split_caps,"skin_lid")
debug.setupvalue(skinfn,skini,function(...) event("skin"); return skin(...) end)
local function restart()
  ctx.struggle.stop(); ctx.convulse.stop(); G.cleanup(pawn,E.mesh)
  ctx.rag.stop(pawn); ctx.rag.mended(E.mesh)
  E.s.sim=true; R.lay(); ctx.animated=function() return false end
  ctx.rag.start(pawn,E.mesh,"quiet")
  ctx.convulse.start(pawn,E.mesh); ctx.struggle.start(pawn,E.mesh)
end
restart()
G.slice_bone(pawn,E.mesh,"Bip001-R-Forearm",nil,"test"); run(130)
check(ctx.struggle.busy(),"ordinary arm loss has an active struggle before splitting")
ctx.convulse.effort(3,1)
actors,events={},{}
local unrelated=F.obj("OtherMesh","SkeletalMeshComponent")
check(G.split(pawn,E.mesh,nil,nil,"test"),"manual split accepted")
check(G.split_on(E.mesh) and not G.split_on(unrelated),"pending split blocks only its own mesh")
ctx.convulse.tick(true); ctx.struggle.tick(true)
check(not state(ctx.convulse) and not state(ctx.struggle),"split cancels active movement and queued faces even while paused")
ctx.convulse.start(pawn,E.mesh); ctx.struggle.start(pawn,E.mesh)
check(not state(ctx.convulse) and not state(ctx.struggle),"pending split refuses new movement state")
local hidden=true
for _=1,150 do
  if G.splitting() then for _,x in ipairs(actors) do hidden=hidden and x.actor.hidden end end
  run(1)
end
check(not G.splitting() and select(2,G.cuts_on(E.mesh)),"manual split completes both halves")
check(G.split_on(E.mesh) and G.split_on(copies[#copies]),"both completed halves block movements")
check(hidden and #actors>=2 and actors[1].actor.hidden==false,"caps stay hidden until the split opens")
local stages=true
for _,a in ipairs(events) do for _,b in ipairs(events) do if a.kind=="mesh" and b.kind=="skin" and a.frame==b.frame then stages=false end end end
check(stages and #events>=4,"procedural creation and skin binding have separate frames")
local skinned=assert(find(skin,"skinned"))
check(#skinned>=2,"both lids retain live bending records")
local mirrored=true
for _,s in ipairs(skinned) do
  for k=1,s.half do
    local a,b=s.v[k],s.v[k+s.half]
    mirrored=mirrored and a.a==b.a and a.b==b.b and a.t==b.t and a.la.X==b.la.X
  end
end
check(mirrored,"back faces reuse the same skin positions and weights")
ctx.convulse.start(pawn,E.mesh); ctx.struggle.start(pawn,E.mesh); run(60)
check(not state(ctx.convulse) and not state(ctx.struggle),"completed split never restarts death movements")
G.cleanup(pawn,E.mesh)
check(not G.split_on(E.mesh),"cleanup clears split eligibility for the next life")
-- The animated death branch also suppresses movement and reaches the later ragdoll release.
restart()
ctx.animated=function() return true end
check(G.split(pawn,E.mesh,nil,nil,"death"),"natural animated-death split accepted")
ctx.convulse.start(pawn,E.mesh); ctx.struggle.start(pawn,E.mesh)
run(180)
check(not G.splitting() and select(2,G.cuts_on(E.mesh)),"animated split reaches its ragdoll release")
check(not state(ctx.convulse) and not state(ctx.struggle),"animated-death split has no struggle or convulsions")
G.cleanup(pawn,E.mesh)
restart()
G.slice_bone(pawn,E.mesh,"Bip001-Spine1",nil,"test"); run(130)
check(ctx.struggle.busy() and state(ctx.convulse),"ordinary waist cut retains its existing death movements")
-- Drive the actual game death notification and main.lua's roll, not a developer key or direct split call.
G.cleanup(pawn,E.mesh)
ctx.animated=actualAnimated
ctx.tune.gore.death={limb=0,head=0,torso=0,split=100,diagonal=0,moreLimbs=0}
ctx.tune.gore.sliceChance=1
E.respawn(); F.run(2,pawn)
local deathStart=#F.log_lines()+1
E.die(true); F.run(4,pawn)
check(F.find("death: split rolled",deathStart) and select(2,G.cuts_on(E.mesh)),"game death notification rolls and completes a vertical split")
check(not state(ctx.convulse) and not state(ctx.struggle),"natural-death setup cannot reintroduce split movements")
-- Following a rigidly rotating half needs no mesh upload. Bending relative to that half still does.
G.cleanup(pawn,E.mesh)
local turn,shift,bend,uploads=0,T.v(0,0,0),0,0
local function world(x,y,z)
  local c,s=math.cos(turn),math.sin(turn)
  return T.v(shift.X+x*c-y*s,shift.Y+x*s+y*c,shift.Z+z)
end
local function rotation() return {X=0,Y=0,Z=math.sin(turn/2),W=math.cos(turn/2)} end
local body=F.obj("RigidHalf","SkeletalMeshComponent")
body.GetSocketTransform=function(_,b)
  local z=tostring(b)=="top" and 10 or 0
  return {Translation=world(z>0 and bend or 0,0,z),Rotation=rotation()}
end
local actor=F.obj("RigidLid","StaticMeshActor",{GetTransform=function() return {Translation=shift,Rotation=rotation()} end})
local pmc=F.obj("RigidPMC","ProceduralMeshComponent")
pmc.UpdateMeshSection_LinearColor=function(self,_,verts,normals) uploads=uploads+1; self.verts,self.normals=verts,normals end
local pc={wv={T.v(-1,0,2),T.v(1,0,2),T.v(1,0,8),T.v(-1,0,8)},wn={}}
for k=1,4 do pc.wv[k+4]=pc.wv[k]; pc.wn[k]=T.v(0,1,0); pc.wn[k+4]=T.v(0,-1,0) end
check(skin(body,actor,pmc,pc,{"bottom","top"}),"independent lid binds to two spine bones")
local lids_step=assert(find(G.tick,"lids_step"))
lids_step()
local initial=uploads
turn,shift=math.pi/3,T.v(11,-7,5)
lids_step()
check(initial==1 and uploads==initial,"rigid rotation and translation skip redundant lid mesh uploads")
bend=1
lids_step()
local symmetric=uploads==initial+1
for k=1,4 do
  local a,b=pmc.verts[k],pmc.verts[k+4]
  local n,m=pmc.normals[k],pmc.normals[k+4]
  symmetric=symmetric and math.abs(a.X-b.X)+math.abs(a.Y-b.Y)+math.abs(a.Z-b.Z)<1e-6
    and math.abs(n.X+m.X)+math.abs(n.Y+m.Y)+math.abs(n.Z+m.Z)<1e-6
  local expected=pc.wv[k].X+pc.wv[k].Z/10
  symmetric=symmetric and math.abs(a.X-expected)+math.abs(a.Y)+math.abs(a.Z-pc.wv[k].Z)<1e-6
end
check(symmetric,"a real bend uploads matching faces with opposite normals")
-- Prepared topology matches the original limb/spine rules.
local plan=G.split_layout(E.mesh,{"Bip001-L-UpperArm"},"Bip001-Spine1",true)
local topology=true
for _,bn in ipairs(plan.names) do
  local function child(b,parent)
    while b do if b==parent then return true end; b=E.PARENT[b] end
    return false
  end
  local expected=child(bn,"Bip001-L-UpperArm") or not child(bn,"Bip001-Spine1")
  topology=topology and plan.off[bn]==expected
end
check(topology and #plan.names>0,"prepared body layout preserves broken-limb and upper-spine membership")
G.cleanup(pawn,E.mesh)
for _,e in ipairs(F.errors) do F.say("hook error: "..e) end
local te=F.find("tick error"); if te then F.say(te) end
check(#F.errors==0 and not te and not F.find("failed at stage"),"no engine simulation or split-stage errors")
F.say(fails==0 and "PASS" or "FAIL")
