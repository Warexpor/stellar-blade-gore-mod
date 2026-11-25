-- Real death-hit and smash dispatch: vertical mesh evidence and a later pre-ragdoll skill hit.
local T=require('smash_world').boot('s.gore.smash = { enabled = true }\ns.gore.blood = false\ns.gore.torsoLegs = { enabled = false }')
local F,E,G,pawn,v=T.F,T.E,T.G,T.pawn,T.v
local sw,hm,death_hit,cut=T.state.sw,T.state.hm,T.state.death_hit,T.state.gore_cut
local print,fails=F.say,0
local function check(ok,s) print((ok and 'ok   ' or 'FAIL ')..s); if not ok then fails=fails+1 end end
local function up(fn,want,value)
  for i=1,100 do local n, old=debug.getupvalue(fn,i); if not n then break end
    if n==want then debug.setupvalue(fn,i,value); return old end end
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
local oldBlunt, oldSmash, oldRock = sw.blunt_of, sw.smash_kill, sw.rock_blow
local oldGlass = T.ctx.glass
T.ctx.glass = { bar_pct = function() return 0 end }
local swings, explosions = 0, 0
local oldSwing = up(hm.lethal_watch,'weapon_swing',function() swings=swings+1 end)
local oldExplosion = sw.explosion_hit
sw.explosion_hit = function() explosions=explosions+1 end
local oldMeshHit = up(death_hit,'meshHit',{t=F.t,loc=chest,bone='Bip001-Spine1',push=v(0,0,-1000)})
local oldCutAtHit = T.ctx.tune.gore.cutAtHit
T.ctx.tune.gore.cutAtHit = false
hm.lethal, hm.armed = nil, true
hm.lethal_watch(pawn,E.mesh)
check(swings==1 and explosions==1,'the lethal mesh-hit fallback reuses swing and projectile checks')
T.ctx.tune.gore.cutAtHit = oldCutAtHit
sw.explosion_hit = oldExplosion
up(hm.lethal_watch,'weapon_swing',oldSwing)
up(death_hit,'meshHit',oldMeshHit)
local early, final = {loc=chest}, {loc=chest, wbone='HammerEnd'}
local tried
sw.rock_blow = function() return early end
sw.blunt_of = function() return false end
sw.smash_kill = function(_, _, evidence)
  tried = evidence
  return evidence == final
end
hm.lethal, hm.armed = nil, true
hm.lethal_watch(pawn,E.mesh)
check(tried == early,'the lethal watch tries the first evidence')
check(not early.early,'a failed early attempt clears the flag on shared hit evidence')
cut(pawn,E.mesh,final)
check(tried == final,'an inconclusive early smash still tries the final hit evidence')
sw.blunt_of, sw.smash_kill, sw.rock_blow, T.ctx.glass = oldBlunt, oldSmash, oldRock, oldGlass

-- A real death can arrive while a previous cut is still opening.
hm.lethal = nil
local settings = T.ctx.tune.gore
settings.smash.enabled, settings.woundAtHit, settings.bladeFollow = false, false, 0
settings.death = { limb = 0, head = 100, torso = 0, split = 0, moreLimbs = 0 }
settings.oddsNear = { enabled = false }
local advance = G.pump_once
G.pump_once = function() end
check(G.slice_bone(pawn, E.mesh, 'Bip001-L-UpperArm', nil, 'test') and G.busy(), 'a previous cut is opening')
E.s.hp = 0; E.die(true); F.run(0.25, pawn)
G.pump_once = advance
F.run(2, pawn)
check(G.has_cut(E.mesh, 'Bip001-L-UpperArm') and G.has_cut(E.mesh, 'Bip001-Head'),
  'the killing cut runs after the previous cut finishes')
check(#F.errors==0,'no fake engine errors')
print(fails==0 and 'PASS' or 'FAIL')
