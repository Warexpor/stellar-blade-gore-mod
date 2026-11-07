-- Drive the real corpse AI directly: animation time, slow motion, swept lunges and cleanup.
local F=require('fake')
local print=F.say
local function v(x,y,z) return {X=x,Y=y,Z=z} end
local tune=dofile('ue4ss/Mods/StellarBladeGore/Scripts/tune.lua')
tune.enemies.afterDeath={enabled=true,time=30,swingReach=450,lunge=120}
local folder='/Game/Art/Character/Monster/Test/'
local anim=F.obj('Test_Attack','AnimSequence',{
  GetFullName=function() return 'AnimSequence '..folder..'Animation/Test_Attack.Test_Attack' end,
  IsA=function() return true end,GetPlayLength=function() return 6 end})
F.classes.AnimSequence={anim}
F.objects[folder..'Animation/Test_Attack.Test_Attack']=anim
local plays,restores,swept=0,0,true
local mesh=F.obj('EnemyMesh','SkeletalMeshComponent',{
  SkeletalMesh=F.obj('SK_Test','SkeletalMesh',{GetFullName=function() return 'SkeletalMesh '..folder..'Mesh/SK_Test.SK_Test' end}),
  PlayAnimation=function() plays=plays+1 end,
  SetAnimationMode=function(_,m) if m==0 then restores=restores+1 end end})
local at=v(300,0,0)
local spineGone = false
local enemy=F.obj('TestEnemy','Test_C',{Mesh=mesh,
  K2_GetActorLocation=function() return at end,
  K2_SetActorRotation=function() end,
  K2_SetActorLocation=function(_,p,sweep) at=p; swept=swept and sweep end})
local pawn=F.obj('Eve','Eve_C',{Mesh=F.obj('Body','SkeletalMeshComponent',{GetSocketLocation=function(_, b)
  if spineGone and tostring(b):find('Spine1', 1, true) then error('smashed away') end
  return v(0,0,30) end})})
local since,scale=F.t,0.15
local alog={}
local function has(pat) for _, s in ipairs(alog) do if s:find(pat, 1, true) then return true end end; return false end
local ctx={tune=tune,log=function(s) alog[#alog+1]=s end,
  try=function(f) local ok,r=pcall(f); if ok then return r end end,
  valid=function(o) return o~=nil and o~=false and not o.__dead end,
  keep=function(o) return {obj=o,alive=true} end,alive_ask=function() return true end,
  live_chars=function() return {{obj=enemy,addr=enemy:GetAddress(),cls='Test_C'}} end,
  dead_since=function() return since end,time_scale=function() return scale end,
  may_load=function() return true end}
local en=dofile('ue4ss/Mods/StellarBladeGore/Scripts/enemies.lua')
en.init(ctx)
-- warm tree cache while she lives (deterministic: the cold-cache deferral waits real 1.5 s, so the
-- death ticks below never depend on wall time)
at=v(5000,0,0)
since=nil
en.after_tick(pawn)
at=v(300,0,0)
since=F.t
local fails=0
local function check(ok,s) print((ok and 'ok   ' or 'FAIL ')..s); if not ok then fails=fails+1 end end
en.after_tick(pawn)
check(plays==1 and restores==0,'a nearby enemy starts an attack of its own')
for _=1,80 do F.t=F.t+0.05; en.after_tick(pawn) end
check(plays==1 and restores==0,'a six-second attack is not cut off at four real seconds in slow motion')
check(at.X>200 and at.X<300 and swept,'lunge follows animation time and keeps swept collision')
scale=1
for _=1,40 do F.t=F.t+0.05; en.after_tick(pawn) end
check(restores==0,'the attack keeps playing after slow motion ends until its animation duration')
for _=1,70 do F.t=F.t+0.05; en.after_tick(pawn) end
check(restores==1,'a long attack restores the animation Blueprint after six game seconds')
tune.enemies.afterDeath.enabled=false
en.after_tick(pawn)
check(not en.attacking(enemy,enemy:GetAddress()),'disabling corpse attacks clears their attack evidence')
-- a destroyed body ends the attacks: nothing left to hit
tune.enemies.afterDeath.enabled=true
local destroyed, probes = false, 0
ctx.gore={nothing_left=function(mesh)
  probes = probes + 1
  return destroyed and mesh ~= nil end}
local mark0 = #alog
en.after_tick(pawn)
for _=1,40 do F.t=F.t+0.05; en.after_tick(pawn) end
local function hasNew(pat) for i=mark0+1,#alog do if alog[i]:find(pat,1,true) then return true end end; return false end
local function countAll(pat) local n=0; for _,s in ipairs(alog) do if s:find(pat,1,true) then n=n+1 end end; return n end
check(probes > 0,'nothing-left check sees her mesh')
check(has('keep at her'),'takeover establishes while a body is left (tick-counted deferral, no wall time)')
destroyed = true
en.after_tick(pawn)
check(hasNew('nothing left of her'),'a destroyed body ends corpse attacks early')
-- latched: a spent death stays spent (no re-takeover every tick: the property churn and log flood, playtest).
-- Past the 90-tick deferral without the latch the takeover would fire again; with it, nothing does.
local keeps = countAll('keep at her')
for _=1,120 do F.t=F.t+0.05; en.after_tick(pawn) end
check(countAll('keep at her') == keeps,'a spent death stays spent: no re-takeover')
-- a new death recovers the loop; a smashed-away upper body does not blind the corpse AI: it aims at her
-- pelvis and keeps attacking
since = F.t + 1000000
destroyed = false
spineGone = true
local p0 = plays
for _=1,80 do F.t=F.t+0.05; en.after_tick(pawn) end
check(plays > p0,'a smashed upper-body socket falls back to her pelvis')
spineGone = false
-- cold cache defers the takeover off the death frame (a fresh module: no warm cache, real ms pass)
local enCold = dofile('ue4ss/Mods/StellarBladeGore/Scripts/enemies.lua')
enCold.init(ctx)
local markC = #alog
enCold.after_tick(pawn)
for _=1,5 do enCold.after_tick(pawn) end
local function hasCold(pat) for i=markC+1,#alog do if alog[i]:find(pat,1,true) then return true end end; return false end
check(hasCold('takeover in 1.5 s'),'cold cache defers the takeover off the death frame')
check(not hasCold('keep at her'),'no takeover before the deferral expires')
check(#F.errors==0,'no fake engine errors')
print(fails==0 and 'PASS' or 'FAIL')
