-- Exact seam-instance reuse, every meat material slot, live colour changes and cap-less fallback shading.
local T=require("smash_world").boot('s.gore.smash = { enabled = true }\ns.gore.blood = false')
local F,E,G,pawn,v=T.F,T.E,T.G,T.pawn,T.v
local print,fails=F.say,0
local function check(c,s) print((c and "ok   " or "FAIL ")..s); if not c then fails=fails+1 end end
local function run() for _=1,40 do F.step(1/60); G.tick(pawn); G.pump() end end
local function meshes(from)
  local out={}
  for i=from+1,#T.world.actors do
    for _,c in ipairs(T.world.actors[i].comps) do if c.sm then out[#out+1]=c end end
  end
  return out
end
local g=T.ctx.tune.gore
local red={R=0.12,G=0.005,B=0.002,A=1}
local seam=F.obj("ActualSeamMID","MaterialInstanceDynamic",{vectors={BloodColor=red},scalars={['Roughness Min']=0.78}})
seam.K2_GetVectorParameterValue=function(self,key) return self.vectors[tostring(key)] end
local cap=F.obj("SurvivingStumpLid","ProceduralMeshComponent",{GetMaterial=function() return seam end})
-- The geometry/engine boundary supplies a surviving procedural cap, just as cap()'s third return does in game.
local caps=G.stage_caps
G.stage_caps=function(q,side) caps(q,side); if side==1 then q.seam=cap end end
E.s.sim=true
local n0=#T.world.actors
G.smash(pawn,E.mesh,{loc=v(1000,2019,126)},"death"); run()
local meat=meshes(n0)
check(#meat==10,"ten material-bearing meat meshes spawned")
local exact=true
for _,m in ipairs(meat) do exact=exact and m.mats[0]==seam and m.mats[1]==seam end
check(exact,"every material slot uses the exact surviving seam instance, including colour and roughness")
local newRed={R=0.2,G=0.01,B=0.005,A=1}
seam.vectors.BloodColor=newRed
local live=true
for _,m in ipairs(meat) do live=live and m:GetMaterial(0):K2_GetVectorParameterValue(FName("BloodColor"))==newRed end
check(live,"a live seam tint change reaches existing chunks through the shared material")
G.cleanup(pawn,E.mesh)
G.stage_caps=caps
-- No generated cap in this geometry fixture: chunks must use the same seam material-building path.
g.capBloodColor={0.31,0.02,0.015}
n0=#T.world.actors
G.smash(pawn,E.mesh,{loc=v(1000,2019,126)},"death"); run()
meat=meshes(n0)
local fallback=true
for _,m in ipairs(meat) do
  local mat=m:GetMaterial(0)
  local c=mat and mat.vectors and mat.vectors.BloodColor
  fallback=fallback and mat==m:GetMaterial(1) and c and c.R==0.31 and c.G==0.02 and c.B==0.015
end
check(#meat==10 and fallback,"cap-less chunks use capBloodColor instead of the base meat material's orange glow")
G.cleanup(pawn,E.mesh)
-- Alternate seam shading is built by the same code, including validated matte texture parameters.
g.capMatte.enabled=true
for _,path in pairs(G.matte.tex) do F.objects[path]=F.obj(path,"Texture2D") end
F.objects[g.capMatte.material]=F.obj("MatteGore","Material")
n0=#T.world.actors
G.smash(pawn,E.mesh,{loc=v(1000,2019,126)},"death"); run()
meat=meshes(n0)
local matte=true
for _,m in ipairs(meat) do
  local mat=m:GetMaterial(0)
  matte=matte and mat==m:GetMaterial(1) and mat.Parent==F.objects[g.capMatte.material]
    and mat.scalars['Roughness Min']==g.capMatte.roughness[1] and mat.textures.Basecolor~=nil
end
check(#meat==10 and matte,"matte seams: chunks inherit the same master, flesh textures and roughness settings")
G.cleanup(pawn,E.mesh)
for _,e in ipairs(F.errors) do print("FAIL hook: "..e); fails=fails+1 end
print(fails==0 and "PASS" or "FAIL")
