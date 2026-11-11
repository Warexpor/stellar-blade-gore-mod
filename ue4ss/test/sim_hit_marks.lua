local create = dofile('ue4ss/Mods/StellarBladeGore/Scripts/gore_hit_marks.lua')
local response = dofile('ue4ss/Mods/StellarBladeGore/Scripts/slice_response.lua')
local M, native, config = {}, { state = 'ready' }, { hitMarks = { max = 1, healFade = 1 } }
local now, clock = 10, os.clock
os.clock = function() return now end
FName = function(s) return s end
local function v(x,y,z) return {X=x,Y=y,Z=z} end
local function sub(a,b) return v(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
local function add(a,b) return v(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
local function scale(a,s) return v(a.X*s,a.Y*s,a.Z*s) end
local function dot(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
local function len(a) return math.sqrt(dot(a,a)) end
local function norm(a) local n=len(a); return n > 0.0001 and scale(a,1/n) or nil end
local function cross(a,b) return v(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X) end
local spawned = {}
local gs = {}
function gs:SpawnDecalAttached(mat,size,mesh,bone,hit,rot)
  local d = {bone=bone, hit=hit}
  function d:K2_DestroyComponent() self.destroyed=true end
  function d:SetFadeOut(_,f) self.fade=f end
  function d:CreateDynamicMaterialInstance() return { SetTextureParameterValue=function() end, SetScalarParameterValue=function() end } end
  spawned[#spawned+1]=d
  return d
end
local km = {MakeRotFromXY=function() return {Pitch=0,Yaw=0,Roll=0} end}
local function load(path)
  if path:find('GameplayStatics',1,true) then return gs end
  if path:find('KismetMathLibrary',1,true) then return km end
  return {}
end
local function try(fn) local ok,r=pcall(fn); if ok then return r end end
local function valid(x) return x ~= nil and not x.destroyed end
local mesh = {GetAddress=function() return 123 end, GetBoneName=function() return {ToString=function() return 'ride' end} end}
local part = {bone='start',to='finish',r=4}
local positions = { start=v(0,0,0), finish=v(0,0,10) }
local calls, reply = 0, 'ok hit=5,0,5 n=100,0,0 bone=3 mat=1 out=5 uv=0.2,0.3'
create(M, {native=native,cfg=function() return config end,log=function() end,load_obj=load,
  vec=v,sub=sub,add=add,scale=scale,len=len,norm=norm,dot=dot,cross=cross,
  bone_loc=function(_,b) return positions[b] end, command=function() calls=calls+1; return reply end,
  triple=response.triple,num=response.num,pick=function(t) return t[1] end,niagara=function() end,FX={hit='hit'},MARK_AT={part},
  guards=function() return try,valid,function() return 'position' end end})
local fails=0
local function check(ok,msg) print((ok and 'ok   ' or 'FAIL ')..msg); if not ok then fails=fails+1 end end
local q = M.skin_query(mesh,v(5,0,5),nil,40)
check(q and q.part==part and q.bone==3 and q.hit.X==5 and q.n.X==1 and q.u==0.2, 'skin query resolves nearest segment and native response')
check(not M.skin_query(mesh,v(100,0,5),nil,40) and calls==1, 'distant hit skips native query')
check(M.hit_mark({},mesh,v(5,0,5),v(0,0,1),0.8) and M.marks()==1 and spawned[1].bone=='ride', 'mark attaches to resolved bone')
check(M.hit_mark({},mesh,v(5,0,5),nil,0.7) and M.marks()==1 and spawned[1].destroyed, 'mark cap destroys the oldest decal')
M.heal_marks(0.5); M.heal_marks(0.69)
check(not spawned[2].fade and M.marks()==1, 'mark remains before health reaches its prior level')
M.heal_marks(0.7)
check(spawned[2].fade==1 and M.marks()==1, 'healed mark begins configured fade')
now=12; M.heal_marks(0.7)
check(spawned[2].destroyed and M.marks()==0, 'expired fade destroys mark')
M.hit_mark({},mesh,v(5,0,5),nil,nil); M.clear_marks()
check(spawned[3].destroyed and M.marks()==0, 'recovery clears remaining marks')
local asset = {GetAddress=function() return 77 end, GetFName=function() return {ToString=function() return 'outfit' end} end}
local function replacement(address)
  return {SkeletalMesh=asset, bReceivesDecals=false, GetAddress=function() return address end,
    GetBoneName=mesh.GetBoneName, GetNumMaterials=function() return 0 end,
    SetReceivesDecals=function(self,on) self.bReceivesDecals=on end}
end
local first, second = replacement(124), replacement(125)
M.hit_mark({},first,v(5,0,5),nil,nil)
M.hit_mark({},second,v(5,0,5),nil,nil)
check(first.bReceivesDecals and second.bReceivesDecals, 'each replacement component enables decals even when the outfit was already logged')
M.clear_marks()
native.state='init'
check(not M.hit_mark({},mesh,v(5,0,5),nil,nil) and M.marks()==0, 'unready native bridge cannot create a mark')
os.clock=clock
print(fails==0 and 'PASS' or 'FAIL')
