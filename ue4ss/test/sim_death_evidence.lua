-- Real death-hit and smash dispatch: vertical mesh evidence and a later pre-ragdoll skill hit.
local T=require('smash_world').boot('s.gore.smash = { enabled = true }\ns.gore.blood = false\ns.gore.torsoLegs = { enabled = false }')
local F,E,G,pawn,v=T.F,T.E,T.G,T.pawn,T.v
local sw,hm,death_hit,cut=T.state.sw,T.state.hm,T.state.death_hit,T.state.gore_cut
local print,fails=F.say,0
local function check(ok,s) print((ok and 'ok   ' or 'FAIL ')..s); if not ok then fails=fails+1 end end
local function up(fn,want,value)
  for i=1,100 do local n=debug.getupvalue(fn,i); if not n then break end
    if n==want then debug.setupvalue(fn,i,value); return end end
  error('missing upvalue '..want)
end
sw.drop()
local chest=E.bone('Bip001-Spine1')
up(death_hit,'meshHit',{t=F.t,loc=chest,bone='Bip001-Spine1',push=v(0,0,-1000)})
local h=death_hit(pawn,E.mesh)
check(h and h.stomp and h.dir.Z < -0.99,'a purely vertical mesh hit survives without horizontal push or weapon trail')
check(h and sw.blunt_of(h),'the observed downward hit classifies blunt')
E.s.sim=true
cut(pawn,E.mesh,h,nil)
for _=1,100 do F.step(1/60); G.tick(pawn); G.pump() end
check(E.hiddenBones['Bip001-Spine1']==true,'the inferred but observed stomp actually completes a torso smash')
G.cleanup(pawn,E.mesh)
E.s.sim=false
up(death_hit,'meshHit',nil)
-- The actual hook supplies two different hits while the death animation has not ragdolled.
local hook='/Script/SB.SBNetworkPlayerController:ClientBroadcast_SkillHitResult'
local function hit(id,where,bone)
  F.fire(hook,F.param(nil),F.param(1),F.param(id),F.param(1),F.param(11),F.param(4242),F.param(1),
    F.param(F.fname('Attack')),F.param({}),F.param(where),F.param(v(0,0,1)),F.param(F.fname(bone)),
    F.param(v(0,1,0)),F.param(v(1,0,0)),F.param(0),F.param(false),F.param(1),F.param(F.fname('Hit')))
end
F.run(0.1,pawn)
hit(1,chest,'Bip001-Spine1')
F.step(0.05,pawn)
local arm=E.bone('Bip001-L-UpperArm')
hit(2,arm,'Bip001-L-UpperArm')
F.step(0.02,pawn)
local latest=death_hit(pawn,E.mesh)
check(latest and latest.skill==2 and latest.bone=='Bip001-L-UpperArm',
  'the second hit 50 ms into the pre-ragdoll animation supplies the death blade')
F.step(0.61,pawn)
check(not death_hit(pawn,E.mesh),'a skill hit older than the 0.6-second window cannot shape a later death')
check(#F.errors==0,'no fake engine errors')
print(fails==0 and 'PASS' or 'FAIL')
