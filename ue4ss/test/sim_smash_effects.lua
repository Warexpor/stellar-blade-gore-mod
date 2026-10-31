-- Blood, chunk trails/pools, audio selection, and their independent switches against fake engine effects.
local T=require("smash_world").boot('s.gore.smash = { enabled = true }\ns.gore.torsoLegs = { enabled = false }')
local F,E,G,pawn,v=T.F,T.E,T.G,T.pawn,T.v
local print,fails=F.say,0
local function check(c,s) print((c and "ok   " or "FAIL ")..s); if not c then fails=fails+1 end end
local function run(sec) for _=1,math.floor(sec*60) do F.step(1/60); G.tick(pawn); G.pump() end end
local effects,sounds,decals={},{},{}
local function upvalue(fn, name)
  for i=1,100 do local n,x=debug.getupvalue(fn,i); if not n then break end; if n==name then return x end end
  error("missing upvalue "..name)
end
local poolRadius = upvalue(upvalue(G.on_settled,"track"),"pool_radius")
check(poolRadius("body")==110 and poolRadius("Bip001-Spine1")==110 and poolRadius("Bip001-L-Clavicle")==110,
  "body and torso pools use the larger radius")
check(poolRadius("Bip001-L-Forearm")==30 and poolRadius("Bip001-L-Thigh")==60,
  "limb pool radii stay unchanged")
local function effect(sys,at,bone)
  local c=F.obj("BloodFX","NiagaraComponent",{path=sys.__name,at=at,bone=bone})
  c.born=F.t
  c.SetWorldScale3D=function(self, scale) self.scale=scale end
  c.Deactivate=function(self) self.stopped=F.t end
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
gs.PlaySoundAtLocation=function(_,_,sound,at,_,volume) sounds[#sounds+1]={path=sound.__name,at=at,volume=volume} end
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
g.poolTime=5
E.s.sim=true
local at=v(1000,2019,126)
-- Real lethal-hit crunch, then the queued opening less than the usual 0.35 s sound gap later.
G.wound(pawn,E.mesh,at,"crunch")
G.smash(pawn,E.mesh,{loc=at},"death")
run(1)
check(#sounds>=3,"blunt crunch and wet smash layers both played despite the sound gap")
for i=1,20 do
  local before=#sounds
  G.sfx("smash",pawn,at,true)
  local wet=false
  for j=before+1,#sounds do wet=wet or sounds[j].path:find("blood_power",1,true)~=nil or sounds[j].path:find("Blood_01",1,true)~=nil end
  check(wet,"smash sound selection includes a blood layer")
end
local slice=false
for _,s in ipairs(sounds) do slice=slice or s.path:find("Mon_slice",1,true)~=nil; check(s.volume>0,"sound has explicit positive volume") end
check(not slice,"smash never plays the blade slice cue")
local hit,bleed,stump=0,0,nil
for _,e in ipairs(effects) do
  if e.path:find("NS_HitBlood_PC_01",1,true) and not e.bone then hit=hit+1 end
  if e.path:find("NS_HitBlood_PC_01",1,true) and e.bone then bleed=bleed+1; stump=e; check(e.bone~="Bip001-L-UpperArm","hidden smashed piece never bleeds") end
end
check(hit>0 and bleed>0,"hit burst and surviving stump bleed spawned")
check(stump and math.abs(stump.scale.X - g.bleedSize * 0.8)<0.001,"limb smash stump bleed is smaller")
local bursts={}
for _,e in ipairs(effects) do if e.path==G.SMASH_BLOOD and not e.bone then bursts[#bursts+1]=e end end
local burst=bursts[1]
check(#bursts==1 and math.abs(burst.scale.X-0.75*math.sqrt(10/36))<0.001 and math.abs(burst.at.Y-2018.5)<0.01 and burst.at.Z==126,
  "whole arm: one smaller proportional burst at the vanished part")
for _,e in ipairs(bursts) do
  check(e.stopped and e.stopped-e.born<=0.1 and not e.__dead,
    "droplet source stops within 0.1 s, existing droplets are not killed")
end
local finisher=false
for _,e in ipairs(effects) do finisher=finisher or e.path==G.SMASH_FX end
check(not finisher,"default burst never uses the finisher's unwanted meat/bone splash")
run(4)
check(stump.stopped and stump.stopped-stump.born > 0.95 and stump.stopped-stump.born < 1.15,"smash stump bleeding stops after about 64 gore ticks")
local chunkTrails,chunkPools=0,0
for _,l in ipairs(F.log_lines()) do if l:find("floor blood from smash chunk:") then
  chunkTrails=chunkTrails+1
  if l:match("(%d+) pools") ~= "0" then chunkPools=chunkPools+1 end
end end
check(chunkTrails==10 and chunkPools==10,"all ten arm chunks leave a landing pool")
check(#decals>0,"blood reaches the floor through the trace/decal API")
G.cleanup(pawn,E.mesh)
local cleared=true
for _,e in ipairs(effects) do cleared=cleared and e.__dead==true end
for _,d in ipairs(decals) do cleared=cleared and (d.__dead==true or (d.life or 0)>0) end
check(cleared,"recovery destroys retained blood effects/decals; transient hit decals have an engine lifetime")
local s=g.smash
local e0=#effects
s.burstScale=math.huge
G.smash(pawn,E.mesh,{loc=E.bone("Bip001-Spine2")},"test"); run(1)
local body,bodyCount=nil,0
for i=e0+1,#effects do if effects[i].path==G.SMASH_BLOOD and not effects[i].bone then body=effects[i]; bodyCount=bodyCount+1 end end
check(body and body.scale.X==0.75 and bodyCount==1,"upper body: one three-quarter-size burst, non-finite tuning falls back safely")
local bodyBleed
for i=e0+1,#effects do if effects[i].path:find("NS_HitBlood_PC_01",1,true) and effects[i].bone then bodyBleed=effects[i] end end
check(bodyBleed and math.abs(bodyBleed.scale.X-g.bleedSize)<0.001,"upper-body smash keeps full stump bleed size")
run(7)
check(body and body.__dead,"empty blood component has a bounded safety lifetime after droplets finish")
G.cleanup(pawn,E.mesh)
s.burstScale=1
-- Blood tracks actual flesh, independently of chunk-count tuning; missing children never reappear as blood.
local original=G.smash_part
local function packet_case(bone,weight)
  G.smash_part=function() return bone,nil,"limb" end
  local first=#effects
  G.smash(pawn,E.mesh,nil,"test"); run(1)
  G.smash_part=original
  local count,burst=0,nil
  for i=first+1,#effects do if effects[i].path==G.SMASH_BLOOD and not effects[i].bone then count=count+1; burst=effects[i] end end
  check(count==1 and math.abs(burst.scale.X-0.75*math.sqrt(weight/36))<0.001,bone..": burst scaled to "..weight.." remaining flesh units")
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
check(#T.world.spheres-n0==10 and fallback,"missing burst asset falls back to hit blood without losing meat")
G.cleanup(pawn,E.mesh)
s.burstFx,s.burst=nil,false
e0=#effects
G.smash(pawn,E.mesh,{loc=at},"test"); run(1)
local disabled=true
for i=e0+1,#effects do disabled=disabled and (effects[i].path~=G.SMASH_BLOOD or effects[i].bone) end
check(disabled and #effects>e0,"burst switch disables only smash droplets, retaining other blood effects")
G.cleanup(pawn,E.mesh)
s.burst=true
-- Blood off leaves physical meat and sound; sound off leaves physical meat and blood.
local n0,e0,a0=#T.world.spheres,#effects,#sounds
g.blood=false
G.smash(pawn,E.mesh,{loc=at},"death"); run(1)
check(#T.world.spheres-n0==10 and #effects==e0 and #sounds>a0,"blood off: meat and audio remain, no new particles")
G.cleanup(pawn,E.mesh)
g.blood,g.sounds=true,false
n0,e0,a0=#T.world.spheres,#effects,#sounds
G.smash(pawn,E.mesh,{loc=at},"death"); run(1)
check(#T.world.spheres-n0==10 and #effects>e0 and #sounds==a0,"sounds off: meat and blood remain, no audio")
G.cleanup(pawn,E.mesh)
for _,e in ipairs(F.errors) do print("FAIL hook: "..e); fails=fails+1 end
for _,l in ipairs(F.log_lines()) do if l:find("smash failed") or l:find("delayed step failed") or l:find("failed at stage") then print("FAIL log: "..l); fails=fails+1 end end
print(fails==0 and "PASS" or "FAIL")
