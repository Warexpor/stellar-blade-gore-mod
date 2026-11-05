local create=dofile('ue4ss/Mods/StellarBladeGore/Scripts/split_plane.lua')
local function v(x,y,z) return {X=x,Y=y,Z=z} end
local function sub(a,b) return v(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
local function add(a,b) return v(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
local function scale(a,n) return v(a.X*n,a.Y*n,a.Z*n) end
local function dot(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
local function norm(a) local n=math.sqrt(dot(a,a)); return n>1e-4 and scale(a,1/n) or nil end
local function cross(a,b) return v(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X) end
local bones={ ['Bip001-Pelvis']=v(0,0,0), ['Bip001-Spine1']=v(0,0,40), ['Bip001-Neck']=v(0,0,80), ['Bip001-Head']=v(0,0,90),
 ['Bip001-L-Thigh']=v(-10,0,0), ['Bip001-R-Thigh']=v(10,0,0), ['Bip001-L-UpperArm']=v(-20,0,70), ['Bip001-R-UpperArm']=v(20,0,70) }
local cfg={tilt=0,splitYaw=15,splitBeside=0}
local M={}
local function try(f) local ok,r=pcall(f); if ok then return r end end
local split=create(M,function() return cfg end,function(_,b) return bones[b] end,v,sub,add,scale,norm,dot,cross,function() return try end)
local fails=0
local function check(ok,msg) print((ok and 'ok   ' or 'FAIL ')..msg); if not ok then fails=fails+1 end end
local function close(a,b) return math.abs(a-b)<1e-6 end
local axis=v(0,0,1)
local r=M.her_right({},axis)
check(r and close(r.X,1) and close(r.Z,0), 'body right is perpendicular to the spine')
check(M.hit_side({},nil,'Bip001-L-Forearm')=='left' and M.hit_side({},nil,'Bip001-R-Forearm')=='right', 'side-specific hit bones retain their sides')
check(M.hit_side({},v(8,0,10),'Bip001-Spine1')=='right' and M.hit_side({},v(-8,0,10),'Bip001-Spine1')=='left', 'central hit bones use body-space position')
check(M.hit_side({},v(1,0,10),'Bip001-Spine1')==nil, 'hits close to the midline have no side')
local q={mesh={},pawn={GetActorRightVector=function() return v(0,1,0) end},middle=true}
local at,n,source=split(q)
check(at and close(at.Z,40) and n and close(n.X,1) and source=='her middle', 'middle split follows the anatomical midline')
q.middle=false; q.out=v(0,1,0)
at,n=split(q)
check(n and close(dot(n,axis),0) and close(math.deg(math.acos(dot(n,r))),15), 'off-axis swing is clamped to configured split yaw')
local saved=bones['Bip001-Head']; bones['Bip001-Head']=nil
check(split(q)==nil and M.hit_side({},v(5,0,0),'Bip001-Spine1')=='right', 'missing head blocks a split while side selection uses neck')
bones['Bip001-Head']=saved
local right,rn,rd=M.diag_plane({},'R',false)
local left,ln,ld=M.diag_plane({},'L',false)
check(right and left and rn and ln and close(rd,ld) and close(right.X,-left.X) and close(rn.X,-ln.X), 'diagonal planes mirror across the body')
print(fails==0 and 'PASS' or 'FAIL')
