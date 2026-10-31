-- Hair fix must never reset cinematic hair, including when a scene interrupts its collision window.
local F=require('fake')
local E=require('eve')
local pawn=E.make(F)
local f=assert(io.open('ue4ss/Mods/StellarBladeGore/Scripts/settings.lua','w'))
f:write('local s=dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")\ns.dev=true\nreturn s\n'); f:close()
local gs=F.obj('GameplayStatics','GameplayStatics')
F.objects['/Script/Engine.Default__GameplayStatics']=gs
local view=F.obj('CinematicCamera','CineCameraActor')
local manager={ViewTarget={Target=pawn}}
gs.GetPlayerCameraManager=function() return manager end
local smc='/Script/Engine.SkeletalMeshComponent'
rawset(F.objects[smc], '__path', smc)
rawset(E.mesh,'__isa',{[smc]=true})
local hair=F.obj('SBHair','SkeletalMeshComponent',{coll=3})
rawset(hair,'__isa',{[smc]=true})
hair.GetCollisionEnabled=function(self) return self.coll end
hair.SetCollisionEnabled=function(self,v) self.coll=v end
pawn.RootComponent=F.obj('Root','CapsuleComponent',{AttachChildren={ForEach=function(_,fn)
  fn(1,{get=function() return E.mesh end}); fn(2,{get=function() return hair end}) end}})
pawn.SBHair=hair
local ok,err=pcall(dofile,'ue4ss/Mods/StellarBladeGore/Scripts/main.lua')
if not ok then F.say('FAIL load: '..tostring(err)); return end
F.fire('/Script/Engine.PlayerController:ClientRestart',F.param(nil)); F.run(16,pawn)
local fails=0
local function check(c,s) F.say((c and 'ok   ' or 'FAIL ')..s); if not c then fails=fails+1 end end
local function count(p) local n=0; for _,l in ipairs(F.log_lines()) do if l:find(p) then n=n+1 end end; return n end
-- Enter while the fix holds collisions query-only: restore them and cancel its pending auto F8.
E.respawn(); F.run(4.3,pawn)
check(hair.coll==1,'gameplay hair reset starts normally')
local reset, f8=count('her ponytail reset'), count('auto F8:')
manager.ViewTarget.Target=view; F.run(8,pawn)
check(hair.coll==3 and E.coll==3,'cinematic immediately restores temporary collision settings')
check(count('her ponytail reset')==reset and count('auto F8:')==f8,'cutscene does not run a reset or auto F8')
E.respawn(); F.run(8,pawn)
check(count('her ponytail reset')==reset and count('auto F8:')==f8,'reinitialization during cinematic cannot queue a later reset')
manager.ViewTarget.Target=pawn; F.run(7,pawn)
check(count('her ponytail reset')==reset and count('auto F8:')==f8,'cinematic requests do not replay after the scene')
-- Active sequences can precede the camera switch.
local sequence=F.obj('Sequence','LevelSequencePlayer',{IsPlaying=function() return true end})
F.classes.LevelSequenceActor={F.obj('Scene','LevelSequenceActor',{SequencePlayer=sequence})}
E.respawn(); F.run(6,pawn)
check(count('her ponytail reset')==reset and count('auto F8:')==f8,'active sequence blocks a reset with the ordinary camera')
F.classes.LevelSequenceActor=nil
E.respawn(); F.run(6,pawn)
check(count('her ponytail reset')>reset,'a later gameplay respawn still fixes hair')
check(#F.errors==0 and not F.find('tick error'),'no hook or tick errors')
F.say(fails==0 and 'PASS' or 'FAIL')
