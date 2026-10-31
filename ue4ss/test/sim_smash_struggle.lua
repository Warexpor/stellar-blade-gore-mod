-- Smash-specific death movements, including a torso destroyed after the ordinary struggle has begun.
local T=require("smash_world").boot('s.deathMoves=true\ns.gore.smash={enabled=true}\ns.gore.blood=false\ns.gore.torsoLegs={enabled=false}\ns.active.animated=false')
local F,E,G,ctx,pawn=T.F,T.E,T.G,T.ctx,T.pawn
local R=require("rag")
R.install(F,E)
F.world=function(dt) T.world.step(dt); R.step(dt) end
local fails=0
local function check(c,s) F.say((c and "ok   " or "FAIL ")..s); if not c then fails=fails+1 end end
local function state(module)
  for i=1,99 do local k,v=debug.getupvalue(module.tick,i); if not k then break end; if k=="st" then return v end end
end
local moves,voices={},0
local original=E.mesh.SetPhysicsAngularVelocityInDegrees
E.mesh.SetPhysicsAngularVelocityInDegrees=function(self,v,add,b)
  for i=2,8 do
    local info=debug.getinfo(i,"S")
    if not info then break end
    if info.source:find("convulse.lua",1,true) or info.source:find("struggle.lua",1,true) then
      moves[#moves+1]={bone=tostring(b),module=info.source,at=F.t}
      break
    end
  end
  return original(self,v,add,b)
end
G.voice_soft=function() voices=voices+1; return "test moan" end
local function run(sec)
  for _=1,math.floor(sec*60) do F.step(1/60); G.tick(pawn); G.pump(); ctx.convulse.tick(false); ctx.struggle.tick(false) end
end
local function smash(bone)
  local pick=G.smash_part
  G.smash_part=function() return bone,nil,bone=="Bip001-Spine1" and "torso" or "limb" end
  G.smash(pawn,E.mesh,nil,"test")
  G.smash_part=pick
  for _=1,120 do
    if G.smashed.has(E.mesh,bone) then return end
    run(1/60)
  end
  check(false,"smash pipeline completed for "..bone)
end
local function restart()
  ctx.struggle.stop(); ctx.convulse.stop(); G.cleanup(pawn,E.mesh)
  ctx.rag.stop(pawn); ctx.rag.mended(E.mesh)
  E.s.sim=true; R.lay(); ctx.animated=function() return false end
  ctx.rag.start(pawn,E.mesh,"quiet")
  ctx.convulse.start(pawn,E.mesh); ctx.struggle.start(pawn,E.mesh)
end
restart()
smash("Bip001-Spine1")
check(not ctx.struggle.due() and not ctx.struggle.busy(),"torso smash immediately blocks pending struggle")
local start,voice0=#moves,voices
run(7)
local cv=state(ctx.convulse)
check(G.smashed.has(E.mesh,"Bip001-Spine1") and cv and cv.smashed and cv.done,"torso smash switches convulsions to a finite four-second twitch sequence")
check(not state(ctx.struggle),"no struggle state remains after torso smash")
check(voices==voice0,"no new moans or breaths after torso smash")
local onlyLegs=true
for i=start+1,#moves do
  local m=moves[i]
  onlyLegs=onlyLegs and not m.module:find("struggle.lua",1,true) and
    (m.bone:find("Calf",1,true) or m.bone:find("Foot",1,true) or m.bone:find("Thigh",1,true))~=nil
end
check(#moves>start and onlyLegs,"all residual muscle impulses stay in the lower legs, no chest/hip/head/arm steering")
check(ctx.convulse.face()==nil,"no effort faces after torso smash")
-- Head destruction and an ordinary beheading must both stop pending and already-running movements.
for _,kind in ipairs({"smash", "cut"}) do
  restart()
  G.slice_bone(pawn,E.mesh,"Bip001-R-Forearm",nil,"test"); run(2)
  check(ctx.struggle.busy(),kind..": struggle starts before head loss")
  ctx.convulse.effort(3,1)
  if kind=="smash" then smash("Bip001-Head")
  else G.slice_bone(pawn,E.mesh,"Bip001-Head",nil,"test"); run(1) end
  start,voice0=#moves,voices
  run(1/60)
  check(not ctx.struggle.due() and not ctx.struggle.busy(),kind..": head loss cancels struggle")
  run(6)
  local minor=true
  for i=start+1,#moves do
    local m=moves[i]
    minor=minor and not m.module:find("struggle.lua",1,true) and (m.bone:find("Calf",1,true) or m.bone:find("Foot",1,true) or m.bone:find("Thigh",1,true))~=nil
  end
  check(#moves>start and minor and voices==voice0,kind..": only slight silent leg convulsions remain")
end
-- The ordinary waist cut still has its detached upper body and therefore keeps the existing struggle.
restart()
G.slice_bone(pawn,E.mesh,"Bip001-Spine1",nil,"test"); run(2)
check(not G.smashed.has(E.mesh,"Bip001-Spine1") and ctx.struggle.busy(),"ordinary waist cut keeps its upper-body struggle")
-- Smash while an act and face/pulse are already queued; neither may execute after destruction.
restart()
G.slice_bone(pawn,E.mesh,"Bip001-R-Forearm",nil,"test"); run(2)
check(ctx.struggle.busy(),"maimed ragdoll starts its usual struggle")
ctx.convulse.effort(3,1)
smash("Bip001-Spine1")
start,voice0=#moves,voices
run(1/60)
cv=state(ctx.convulse)
check(not state(ctx.struggle) and cv and #cv.faces==0 and not cv.jolts,"mid-struggle smash discards queued acts, face poses and gasp jolts")
run(5)
check(voices==voice0,"mid-struggle smash cannot restart effort sounds")
onlyLegs=true
for i=start+1,#moves do
  onlyLegs=onlyLegs and moves[i].module:find("struggle.lua",1,true)==nil and (moves[i].bone:find("Bip001-L-",1,true) or moves[i].bone:find("Bip001-R-",1,true))~=nil
end
check(onlyLegs,"mid-struggle smash immediately stops upper-body impulses")
-- A detached leg is never twitched on the floor after the torso is gone.
restart()
G.slice_bone(pawn,E.mesh,"Bip001-L-Thigh",nil,"test"); run(1)
smash("Bip001-Spine1")
start=#moves
run(6)
local attached=true
for i=start+1,#moves do attached=attached and not moves[i].bone:find("Bip001-L-",1,true) end
check(attached and #moves>start,"only the remaining right leg twitches after a left thigh cut")
-- Recovery removes the smash gate, and feature switches still stop all residual movement.
restart()
check(not G.smashed.has(E.mesh,"Bip001-Spine1"),"recovery clears the smash-specific gate")
ctx.tune.deathMoves=false
smash("Bip001-Spine1"); run(0.2); start=#moves; run(5)
check(#moves==start,"Death Movements off suppresses the residual leg twitches")
for _,err in ipairs(F.errors) do check(false,"hook: "..err) end
for _,l in ipairs(F.log_lines()) do
  if l:find("smash failed") or l:find("failed at stage") or l:find("delayed step failed") or l:find("convulse: .*attempt") then check(false,l) end
end
F.say(fails==0 and "PASS" or "FAIL")
