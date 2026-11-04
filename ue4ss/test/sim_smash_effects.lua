-- Blood, chunk trails/pools, audio selection, and their independent switches against fake engine effects.
local T=require("smash_world").boot('s.gore.smash = { enabled = true }\ns.gore.torsoLegs = { enabled = false }')
local F,E,G,pawn,v=T.F,T.E,T.G,T.pawn,T.v
local print,fails=F.say,0
local function check(c,s) print((c and "ok   " or "FAIL ")..s); if not c then fails=fails+1 end end
-- Wall and ring geometry checks must be spread over bounded passes while still rejecting a gap.
local originalTrace, traces = G.pool_trace, 0
G.pool_trace = function(_, from, to)
  traces=traces+1
  if from.Z == to.Z then return false end
  return true, v(to.X,to.Y,0), v(0,0,1)
end
local k={pawn=pawn,rmax=40,pool={at=v(0,0,0),n=v(0,0,1),ok=4,check={kind='wall',i=0,room=40}}}
for _=1,2 do local before=traces; G.pool_check_step(k,4); check(traces-before<=4,'wall check obeys four-trace budget') end
check(not k.pool.check and k.pool.rmax==36,'wall check completes with the original safety margin')
k.pool.check={kind='ring',i=0,ring=10}
for _=1,1 do G.pool_check_step(k,4) end
check(not k.pool.check and k.pool.ok==10,'flat ring is accepted only after every trace')
G.pool_trace=function() return false end
k.pool.check={kind='ring',i=0,ring=16}
G.pool_check_step(k,4)
check(k.pool.stopped and k.pool.ok==10,'gap stops growth at the last verified ring')
G.pool_trace=originalTrace
local function run(sec) for _=1,math.floor(sec*60) do F.step(1/60); G.tick(pawn); G.pump() end end
local effects,sounds,decals={},{},{}

local function upvalue(fn, name)
  for i=1,100 do local n,x=debug.getupvalue(fn,i); if not n then break end; if n==name then return x end end
  error("missing upvalue "..name)
end
-- Simultaneously ready expensive impact work must be spread in FIFO order; timers remain independent.
local pending = upvalue(G.tick, "later")
local ran = {}
for _, label in ipairs({"cut sound", "smash blood burst", "smash mesh load"}) do
  pending[#pending+1] = {n=1,label=label,fn=function() ran[#ran+1]={label=label,t=F.t} end}
end
pending[#pending+1] = {n=1,fn=function() ran.timer=F.t end}
run(0.2)
check(#ran==3 and ran[1].label=="cut sound" and ran[2].label=="smash blood burst" and ran[3].label=="smash mesh load" and ran[1].t<ran[2].t and ran[2].t<ran[3].t and ran.timer==ran[1].t,
  "impact work is FIFO on separate updates without delaying unrelated timers")
-- Opening audio must not wait for queued follow-up cuts or a backlog of blood/meat effects.
G.slice_bone(pawn,E.mesh,"Bip001-R-UpperArm",nil,"test")
local soundRan, bloodRan = false, false
pending[#pending+1] = {n=0,label="smash blood burst",fn=function() bloodRan=true end}
pending[#pending+1] = {n=0,label="cut sound",fn=function() soundRan=true end}
local beforeAudioCommands = #F.cmds
check(G.busy(),"a cut is still opening for the audio-priority check")
G.watch(E.mesh)
check(#F.cmds==beforeAudioCommands,"background bone and asset preparation pauses during cuts")
G.pump()
check(soundRan and not bloodRan and G.busy() and #F.cmds==beforeAudioCommands,
  "ready sound plays during a busy cut, before blood, with no cut work on its frame")
run(0.5)
G.cleanup(pawn,E.mesh)
pending = upvalue(G.tick, "later")
local frames={}
for _,label in ipairs({"cut sound", "smash blood burst", "smash mesh load"}) do
  pending[#pending+1]={n=0,label=label,fn=function() frames[#frames+1]=label end}
end
for i=1,3 do
  G.pump()
  check(#frames==i,"ready impact item "..i.." runs on its own render frame without another gore tick")
end
-- A rooted floor material is reused only while its native lifetime guard confirms its identity.
local native = upvalue(upvalue(G.guarded_asset, "load_obj"), "native")
local oldKeep, oldHeld = T.ctx.keep, T.ctx.held
T.ctx.keep=function(o) return {obj=o} end
T.ctx.held=function(k) return not k.obj.__dead end
local matPath="/Game/TestFloorMaterial"
local firstMat=F.obj("first floor material","Material")
F.objects[matPath]=firstMat
native.rooted[matPath]=true
local oldFind, lookups = StaticFindObject, 0
StaticFindObject=function(path) if path==matPath then lookups=lookups+1 end; return oldFind(path) end
check(G.guarded_asset(matPath)==firstMat and G.guardedAssets[matPath]~=nil,"rooted floor material is guarded and cached")
local firstLookups=lookups
check(G.guarded_asset(matPath)==firstMat and lookups==firstLookups,"repeated rooted asset access avoids another object lookup")
firstMat.__dead=true
local replacement=F.obj("replacement floor material","Material")
F.objects[matPath]=replacement
check(G.guarded_asset(matPath)==replacement,"stale floor material is discarded before replacement is read")
StaticFindObject=oldFind
T.ctx.keep,T.ctx.held=oldKeep,oldHeld
G.guardedAssets[matPath]=nil
-- A pool waiting for checks must not store seconds of growth and jump when they finish.
local trackers = upvalue(G.pool_grow, "trackers")
local decal=F.obj("GrowthTest", "DecalComponent", {})
decal.SetWorldScale3D=function(self, size) self.size=size end
local waiting={rmax=100,pool={ok=4,r=4,age=0,d=decal}}
trackers[#trackers+1]=waiting
G.poolClock=F.t
for _=1,20 do F.step(0.1); G.pool_grow() end
check(waiting.pool.age==0 and waiting.pool.r==4, "blocked pool does not accumulate growth")
waiting.pool.ok=10
F.step(0.1); G.pool_grow()
check(waiting.pool.r>4 and waiting.pool.r<7, "pool starts smoothly once floor check completes")
trackers[#trackers]=nil
G.poolClock=nil
local poolRadius = upvalue(upvalue(G.on_settled,"track"),"pool_radius")
check(poolRadius("body")==110 and poolRadius("Bip001-Spine1")==110 and poolRadius("Bip001-L-Clavicle")==110,
  "body and torso pools use the larger radius")
check(poolRadius("Bip001-L-Forearm")==30 and poolRadius("Bip001-L-Thigh")==60,
  "limb pool radii stay unchanged")
trackers[#trackers+1]={pawn=pawn, bone="smash chunk", rmax=11}
G.on_settled(pawn,E.mesh)
check(#trackers==2 and trackers[2].bone=="body" and math.abs(trackers[2].rmax-110*(T.ctx.tune.gore.poolScale or 1))<0.001,
  "a chunk or small wound cannot suppress the larger main-body pool")
G.on_settled(pawn,E.mesh)
check(#trackers==2, "an existing body-sized tracker prevents a duplicate pool")
trackers[#trackers]=nil; trackers[#trackers]=nil
local function effect(sys,at,bone)
  local c=F.obj("BloodFX","NiagaraComponent",{path=sys.__name,at=at,bone=bone})
  c.born=F.t
  c.K2_GetComponentLocation=function(self) return self.at or v(1000,2019,126) end
  c.SetWorldScale3D=function(self, scale) self.scale=scale end
  c.Deactivate=function(self) self.stopped=F.t end
  c.ResetSystem=function(self) self.resets=(self.resets or 0)+1; self.resetTimes=self.resetTimes or {}; self.resetTimes[#self.resetTimes+1]=F.t end
  c.K2_DestroyComponent=function(self) self.__dead=true; self.destroyed=F.t end
  effects[#effects+1]=c
  return c
end
F.objects["/Script/Niagara.Default__NiagaraFunctionLibrary"]=F.obj("Niagara","NiagaraFunctionLibrary",{
  SpawnSystemAtLocation=function(_,_,sys,at,_,scale)
    local c=effect(sys,at); c.scale=scale; return c
  end,
  SpawnSystemAttached=function(_,sys,_,bone,at) return effect(sys,at,tostring(bone)) end,
})
local gs=F.objects["/Script/Engine.Default__GameplayStatics"]
gs.PlaySoundAtLocation=function(_,_,sound,at,_,volume) sounds[#sounds+1]={path=sound.__name,at=at,volume=volume,t=F.t} end
gs.SpawnDecalAtLocation=function(_,_,mat,_,at,_,life)
  local d=F.obj("FloorBlood","DecalComponent",{at=at,mat=mat,life=life})
  d.SetWorldScale3D=function(self,s) self.scale=s end
  d.K2_DestroyComponent=function(self) self.__dead=true end
  decals[#decals+1]=d
  return d
end
F.objects["/Script/Engine.Default__KismetMathLibrary"]=F.obj("Math","KismetMathLibrary",{
  MakeRotFromX=function() return {Pitch=-90,Yaw=0,Roll=0} end,
})
F.objects["/Script/Engine.Default__KismetSystemLibrary"]=F.obj("System","KismetSystemLibrary",{
  LineTraceSingle=function(_,_,a,b,_,_,_,_,hit)
    if a.Z==b.Z or (a.Z>0)==(b.Z>0) then return false end
    local k=a.Z/(a.Z-b.Z)
    hit.ImpactPoint=v(a.X+(b.X-a.X)*k,a.Y+(b.Y-a.Y)*k,0)
    hit.ImpactNormal=v(0,0,1)
    return true
  end,
})
-- Supply the mod's real named effect and decal assets; unrelated game objects still use the shared fake loader.
local file=assert(io.open(T.dir.."gore.lua"))
local src=file:read("*a"); file:close()
for path in src:gmatch('"(/Game/Art/FX/[^"\n]+)"') do
  if not F.objects[path] then F.objects[path]=F.obj(path,"Asset") end
end
local load=LoadAsset
LoadAsset=function(path)
  if path:find("/Game/Sound/Character/",1,true) then
    F.objects[path]=F.objects[path] or F.obj(path,"SoundCue")
    return F.objects[path]
  end
  return load(path)
end
local g=T.ctx.tune.gore
local preload = { preload = {}, sounds = 1, next = 1 }
g.smash.splash = true
G.smashed.preload(preload)
local particlePreload = false
for _, path in ipairs(preload.preload) do particlePreload = particlePreload or path:find("/NS_", 1, true) ~= nil end
check(particlePreload and #preload.preload > 0, "smash preloads meat, materials and restored blood effects")
g.smash.splash = nil
-- Several effects in the same impact share one material-collection update.
local tintWrites=0
F.objects["/Game/Art/FX/MPC/MPC_BloodParameters.MPC_BloodParameters"]=F.obj("blood collection","MaterialParameterCollection")
F.objects["/Script/Engine.Default__KismetMaterialLibrary"]=F.obj("materials","KismetMaterialLibrary",{
  SetVectorParameterValue=function() tintWrites=tintWrites+1 end,
  SetScalarParameterValue=function() tintWrites=tintWrites+1 end,
  GetVectorParameterValue=function() return {R=0,G=0,B=0} end,
  GetScalarParameterValue=function() return 0 end,
})
G.on_hit(pawn,E.mesh,v(1000,2019,126))
G.smashed.blood(pawn,v(1000,2019,126),{blood=36})
check(tintWrites>0 and #effects>0,"smash blood applies the configured blood tint")
G.cleanup(pawn,E.mesh)
g.poolTime=5
E.s.sim=true
-- Multiple openings are sampled on different passes while their elapsed time advances normally.
local trackOpening = upvalue(G.on_settled, "track")
local sampled, passes = {0,0,0}, {}
for i=1,3 do
  trackOpening(pawn,function()
    sampled[i]=sampled[i]+1
    passes[F.t]=(passes[F.t] or 0)+1
    return v(F.t*100,0,20)
  end,"sample test",E.mesh,10,true)
end
run(1)
local spread=true
for _,n in pairs(passes) do if n>1 then spread=false end end
check(spread and sampled[1]>0 and sampled[2]>0 and sampled[3]>0,"three openings are sampled fairly on separate passes")
G.cleanup(pawn,E.mesh)
local at=v(1000,2019,126)
-- The immediate hit burst must not synchronously trace and spawn the floor splat.
local beforeHitDecals, beforeHitEffects = #decals, #effects
G.on_hit(pawn,E.mesh,at)
check(#effects==beforeHitEffects+1 and effects[#effects].path:find("NS_HitBlood_PC_01",1,true) and #decals==beforeHitDecals,
  "hit emits its blood particle while floor splat is deferred")
run(0.15)
check(#decals>beforeHitDecals,"deferred hit splat reaches the floor")
-- Real lethal-hit crunch, then the queued opening less than the usual 0.35 s sound gap later.
local beforeSmashSounds, beforeSmashEffects=#sounds, #effects
local originalCaps=G.stage_caps
local smashOutline
G.stage_caps=function(q, side)
  if q.smash and side==1 then smashOutline={body=q.ob, piece=q.ol} end
  return originalCaps(q, side)
end
G.wound(pawn,E.mesh,at,"crunch")
G.smash(pawn,E.mesh,{loc=at},"death")
run(1)
G.stage_caps=originalCaps
check(smashOutline and smashOutline.piece==nil,"smash skips parsing its hidden piece outline")
check(#sounds>=beforeSmashSounds+3,"blunt crunch and wet smash layers both played despite the sound gap")
check(sounds[beforeSmashSounds+2] and sounds[beforeSmashSounds+3]
  and sounds[beforeSmashSounds+2].t==sounds[beforeSmashSounds+3].t,
  "the actual smash plays both sound layers in the same update")
local guarded, guardedCalls = G.guarded_asset, 0
G.guarded_asset=function(...) guardedCalls=guardedCalls+1; return guarded(...) end
G.sfx("smash",pawn,at,true)
G.guarded_asset=guarded
check(guardedCalls==0,"gore sound playback reacquires cues without the guarded wrapper cache")
for i=1,20 do
  local before=#sounds
  T.ctx.poll=T.ctx.poll+1
  G.sfx("smash",pawn,at,true)
  local wet=false
  for j=before+1,#sounds do wet=wet or sounds[j].path:find("blood_power",1,true)~=nil or sounds[j].path:find("Blood_01",1,true)~=nil end
  check(wet,"smash sound selection includes a blood layer")
end
-- The same poll window never restarts a cue: forced layers landing together pile no duplicate voice onto the
-- audio thread, while separate windows keep the full selection.
T.ctx.poll=T.ctx.poll+1
local started=#sounds
for _=1,8 do G.sfx("smash",pawn,at,true) end
local fresh=#sounds-started
check(fresh>=2,"a new window plays the smash set")
check(fresh<=4,"one window starts each cue at most once ("..fresh.." starts)")
local slice=false
for _,s in ipairs(sounds) do slice=slice or s.path:find("Mon_slice",1,true)~=nil; check(s.volume>0,"sound has explicit positive volume") end
check(not slice,"smash never plays the blade slice cue")
check(#effects>0,"smash creates the 0.5.5 blood-only stump effect")
local flowEffect, loopEffect
for i=beforeSmashEffects+1,#effects do
  local fx=effects[i]
  if fx.path==G.SMASH_BLOOD and fx.bone then flowEffect=fx end
  if fx.path:find("NS_A_BloodLoop",1,true) and fx.bone then loopEffect=fx end
end
check(loopEffect and loopEffect.scale and flowEffect and loopEffect.born~=flowEffect.born,
  "continuous wound layer and stump spurt spawn on separate frames")
check(flowEffect and flowEffect.path==G.SMASH_BLOOD and flowEffect.bone and flowEffect.scale,
  "stump effect is attached and uses the requested blood asset and scale")
check(flowEffect and (flowEffect.resets or 0)>0,"stump effect restarts while bleeding")
check(flowEffect and math.abs(flowEffect.scale.X-0.6)<0.001,"smash retains the original 0.5.5 blood scale")
run(3)
check(flowEffect and flowEffect.stopped~=nil,"stump effect stops after the configured bleed duration")
check(loopEffect and loopEffect.stopped~=nil,"continuous wound layer stops after the configured bleed duration")

local armFlow = G.bleed_scale({ e = { X = 4, Y = 3 } }, 0.6)
local waistFlow = G.bleed_scale({ e = { X = 11, Y = 8 } }, 0.6)
check(waistFlow.X > armFlow.X and waistFlow.Y > armFlow.Y and waistFlow.Z == armFlow.Z,
  "wider openings produce wider blood without lengthening the flow")
local armOffset = G.bleed_offset({ e = { X = 4, Y = 3 }, x = v(1,0,0), z = v(0,0,1) })
local waistOffset = G.bleed_offset({ e = { X = 11, Y = 8 }, x = v(1,0,0), z = v(0,0,1) })
check(waistOffset.X > armOffset.X and waistOffset.Y == 0 and waistOffset.Z == 0,
  "additional streams are spaced along the opening and wider for a waist")
run(4)
local chunkTrails,chunkPools=0,0
for _,l in ipairs(F.log_lines()) do if l:find("floor blood from smash chunk:") then
  chunkTrails=chunkTrails+1
  if l:match("(%d+) pools") ~= "0" then chunkPools=chunkPools+1 end
end end
check(chunkTrails==3 and chunkPools==3,"three arm chunks leave landing pools within the tracking budget")
check(#decals>0,"blood reaches the floor through the trace/decal API")
G.cleanup(pawn,E.mesh)
local cleared=true
for _,e in ipairs(effects) do cleared=cleared and e.__dead==true end
for _,d in ipairs(decals) do cleared=cleared and (d.__dead==true or (d.life or 0)>0) end
check(cleared,"recovery destroys retained blood effects/decals; transient hit decals have an engine lifetime")
local s=g.smash
local function stump_since(start)
  for i=start+1,#effects do if effects[i].path==G.SMASH_BLOOD and effects[i].bone then return effects[i] end end
end
local e0=#effects

s.burstScale=math.huge
G.smash(pawn,E.mesh,{loc=E.bone("Bip001-Spine2")},"test"); run(1)
check(stump_since(e0)~=nil,"upper-body smash produces stump blood even with non-finite burst tuning")
local afterUpper=#effects
run(7)
check(#effects==afterUpper,"upper-body smash does not schedule additional particle systems")
G.cleanup(pawn,E.mesh)
s.burstScale=1
-- A full-body explosion uses the grinder cloud, samples the whole pose and has no invisible-body pool.
s.fullBody, s.fullBodyChance=true,1
local fullStart, chunkStart=#effects,#T.world.spheres
local oldSplat, fullSplats=G.splat,0
G.splat=function(...) fullSplats=fullSplats+1; return oldSplat(...) end
local preChunks=0
for _,k in ipairs(upvalue(G.pool_grow,"trackers")) do if k.bone=="smash chunk" then preChunks=preChunks+1 end end
check(G.smash(pawn,E.mesh,{loc=E.bone("Bip001-Spine2"),impactRadius=200},"death"),"full-body smash starts")
G.on_hit(pawn,E.mesh,at)
run(0.3)
check(fullSplats==0,"full-body hit and opening do not create a floating-body splat")
check(#effects>fullStart,"full-body smash produces blood effects")
run(1.5)
local chunkTracks,scaled=0,false
trackers=upvalue(G.pool_grow,"trackers")
local pscale=T.ctx.tune.gore.poolScale or 1
for _,k in ipairs(trackers) do
  if k.bone=="smash chunk" then
    chunkTracks=chunkTracks+1; check(k.noDrips,"full-body chunks only pool when settled")
    scaled=scaled or k.rmax/pscale>11
  end
end
check(scaled,"chunk pools grow past the meat sitting on them")
check(chunkTracks-preChunks==64,"every full-body chunk is tracked for its landing pool")
local fastGrow,chunkPooled=false,false
for _,k in ipairs(trackers) do
  if k.bone=="smash chunk" then
    if k.grow==math.min(T.ctx.tune.gore.poolGrow or 5,3) then fastGrow=true end
    if k.pool and k.pool.r>4 then chunkPooled=true end
  end
end
check(fastGrow,"settled chunk pools develop on the fast growth curve")
check(chunkPooled,"chunk pools grow past their starting size")
local trackerCount=#trackers
G.on_settled(pawn,E.mesh)
check(#trackers==trackerCount and chunkTracks>0,"full-body smash never starts a hidden-body pool")
local points={}
for i=chunkStart+1,#T.world.spheres do
  local p=T.world.spheres[i].spawnAt
  points[math.floor(p.Z/15)]=true
end
local heights=0; for _ in pairs(points) do heights=heights+1 end
check(#T.world.spheres-chunkStart==64 and heights>=3,"full-body pieces originate across the captured body pose")
run(2)
local grinder=false
for i=fullStart+1,#effects do if effects[i].path==G.SMASH_GRINDER then grinder=true; check(effects[i].stopped and effects[i].__dead,"full-body cloud stops and is cleaned up") end end
check(grinder,"full-body smash restores the grinder blood cloud")
G.cleanup(pawn,E.mesh)
G.splat=oldSplat
s.fullBody=false
-- Blood tracks actual flesh, independently of chunk-count tuning; missing children never reappear as blood.
local original=G.smash_part
local function packet_case(bone,weight)
  G.smash_part=function() return bone,nil,"limb" end
  local first=#effects
  G.smash(pawn,E.mesh,nil,"test"); run(1)
  G.smash_part=original
  local count,burst=0,nil
  for i=first+1,#effects do if effects[i].path==G.SMASH_BLOOD and not effects[i].bone then count=count+1; burst=effects[i] end end
  check(count==1 and burst.scale and math.abs(burst.scale.X-math.min(0.825,0.825*math.sqrt(weight/36)))<0.001,
    bone..": one scaled smash blood cloud at "..weight.." remaining flesh units")
end
for _,c in ipairs({{"Bip001-L-Forearm",6},{"Bip001-L-Calf",10},{"Bip001-L-Thigh",16},{"Bip001-Head",8}}) do
  packet_case(c[1],c[2]); G.cleanup(pawn,E.mesh)
end
packet_case("Bip001-L-Forearm",6)
packet_case("Bip001-L-UpperArm",4)
check(G.smashed.profile(E.mesh,"Bip001-Spine1").blood==26,"torso blood volume excludes the whole missing arm subtree")
G.cleanup(pawn,E.mesh)
s.chunks=0
packet_case("Bip001-L-UpperArm",10)
s.chunks=10
G.cleanup(pawn,E.mesh)
-- An absent custom asset must keep the ordinary hit burst and physical meat.
s.burstFx="/Game/Missing/NoBlood.NoBlood"
local n0,e0=#T.world.spheres,#effects
G.smash(pawn,E.mesh,{loc=at},"test"); run(1)
local fallback=false
for i=e0+1,#effects do fallback=fallback or effects[i].path:find("NS_HitBlood_PC_01",1,true)~=nil end
check(#T.world.spheres-n0==10 and fallback and #effects>e0,"missing custom cloud falls back to hit blood and keeps meat")
G.cleanup(pawn,E.mesh)
s.burstFx,s.burst=nil,false
e0=#effects
G.smash(pawn,E.mesh,{loc=at},"test"); run(1)
local disabled=true
for i=e0+1,#effects do disabled=disabled and (effects[i].path~=G.SMASH_BLOOD or effects[i].bone) end
check(disabled and stump_since(e0)~=nil,"burst switch leaves stump blood enabled")
G.cleanup(pawn,E.mesh)
s.burst=true
-- Blood off leaves physical meat and sound; sound off leaves physical meat and blood.
local n0,e0,a0=#T.world.spheres,#effects,#sounds
g.blood=false
T.ctx.poll=T.ctx.poll+1
G.smash(pawn,E.mesh,{loc=at},"death"); run(1)
check(#T.world.spheres-n0==10 and #effects==e0 and #sounds>a0,"blood off: meat and audio remain, no new particles")
G.cleanup(pawn,E.mesh)
g.blood,g.sounds=true,false
n0,e0,a0=#T.world.spheres,#effects,#sounds
T.ctx.poll=T.ctx.poll+1
G.smash(pawn,E.mesh,{loc=at},"death"); run(1)
check(#T.world.spheres-n0==10 and stump_since(e0)~=nil and #sounds==a0,"sounds off: physical meat and stump blood remain without audio")
G.cleanup(pawn,E.mesh)
local beforeLowArm = #effects
G.slice_bone(pawn,E.mesh,"Bip001-R-UpperArm",nil,"low HP")
run(1)
local lowBursts, lowAttached = 0, 0
for i=beforeLowArm+1,#effects do
  local fx=effects[i]
  if fx.path:find("NS_HitBlood_PC_01",1,true) and not fx.bone then lowBursts=lowBursts+1 end
  if fx.bone and (fx.path:find("NS_A_BloodLoop",1,true) or fx.path:find("NS_HitBlood_PC_01",1,true)) then lowAttached=lowAttached+1 end
end
check(lowBursts==0 and #effects>beforeLowArm,"low-HP cut produces the 0.5.5 stump effect")
check(#effects-beforeLowArm==2,"ordinary cuts produce blood on both openings")
local resetTimes={}
for i=beforeLowArm+1,#effects do
  local fx=effects[i]
  check(fx.path==G.SMASH_BLOOD and fx.bone and (fx.resets or 0)>0,"both 0.5.5 components are attached and repeat")
  for _,t in ipairs(fx.resetTimes or {}) do resetTimes[t]=(resetTimes[t] or 0)+1 end
end
local spread=true
for _,n in pairs(resetTimes) do if n>1 then spread=false end end
check(spread,"multiple stump restarts are spread across frames")
check(lowAttached==0,"low-HP cut does not use the parked hit or loop effects")
G.cleanup(pawn,E.mesh)
g.sounds=true
T.ctx.poll=T.ctx.poll+1
G.sfx("cut",pawn,at,true)
local beforeOpeningSounds=#sounds
T.ctx.poll=T.ctx.poll+1
G.slice_bone(pawn,E.mesh,"Bip001-L-UpperArm",nil,"after")
run(0.3)
check(#sounds>beforeOpeningSounds,"a cut opening plays despite a recent gore sound")
G.cleanup(pawn,E.mesh)
for _,e in ipairs(F.errors) do print("FAIL hook: "..e); fails=fails+1 end
for _,l in ipairs(F.log_lines()) do if l:find("smash failed") or l:find("delayed step failed") or l:find("failed at stage") then print("FAIL log: "..l); fails=fails+1 end end
print(fails==0 and "PASS" or "FAIL")
