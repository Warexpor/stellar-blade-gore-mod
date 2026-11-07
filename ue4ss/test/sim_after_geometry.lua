-- Geometry checks use a single known limb so the expected contact is independent of the game loop.
local function v(x,y,z) return { X=x, Y=y, Z=z } end
local function sub(a,b) return v(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
local function dot(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
local function dist(a,b) local d=sub(a,b); return math.sqrt(dot(d,d)) end
local function seg_dist(a,b,p)
  local d=sub(b,a)
  local t=math.max(0,math.min(1,dot(sub(p,a),d)/math.max(dot(d,d),1e-4)))
  return dist(v(a.X+t*d.X,a.Y+t*d.Y,a.Z+t*d.Z),p)
end
local function safe(f) local ok,x=pcall(f); if ok then return x end end
FName=function(s) return s end
local points={ arm=v(0,0,0), elbow=v(0,0,20) }
local mesh={ GetSocketLocation=function(_,name) return assert(points[name]) end }
-- The segment's anatomical name matters for the radius.
points["Bip001-L-UpperArm"], points["Bip001-L-Forearm"] = points.arm, points.elbow
local geometry=dofile("ue4ss/Mods/StellarBladeGore/Scripts/after_hit_geometry.lua")(
  safe, function(x) return x end, { { "Bip001-L-UpperArm", nil, "Bip001-L-Forearm" } }, sub, dot, dist, seg_dist)
local fails=0
local function check(ok,msg) print((ok and "ok   " or "FAIL ")..msg); if not ok then fails=fails+1 end end
local hit,d,bone,reach=geometry(mesh,{p=v(-20,0,10),q=v(20,0,10)},40)
check(hit and bone=="Bip001-L-UpperArm" and d<1e-6 and reach==12 and math.abs(hit.Z-10)<1e-6,
  "hand sweep intersects the middle of the limb")
local _,miss,_,limit=geometry(mesh,{p=v(-20,30,10),q=v(20,30,10)},40)
check(miss and miss>limit, "a distant sweep misses the limb")
local steps={ {v(-20,-5,10),v(20,-5,10)}, {v(-20,0,10),v(20,0,10)}, {v(-20,5,10),v(20,5,10)} }
local _,swept,which,allowed=geometry(mesh,{steps=steps},25)
check(which=="Bip001-L-UpperArm" and swept<1e-6 and swept<=allowed,
  "sampled blade sweep detects a crossing between endpoints")
-- Adjacent limb segments share a joint. Each successful socket is read once per geometry pass,
-- but a later pass must observe movement and a failed read remains eligible for retry.
local reads, moving, failOnce = {}, { A=v(0,0,0), B=v(0,0,20), C=v(0,0,40) }, false
local sharedMesh={GetSocketLocation=function(_,name)
  reads[name]=(reads[name] or 0)+1
  if name=='B' and failOnce then failOnce=false; error('temporary missing socket') end
  return assert(moving[name])
end}
local shared=dofile("ue4ss/Mods/StellarBladeGore/Scripts/after_hit_geometry.lua")(
  safe,function(x) return x end,{{'A',nil,'B'},{'B',nil,'C'}},sub,dot,dist,seg_dist)
local _, first=shared(sharedMesh,{p=v(-10,0,10),q=v(10,0,10)},40)
check(first<1e-6 and reads.B==1, 'shared joint is sampled once per geometry pass')
moving.B=v(0,30,20); reads={}
local _, second=shared(sharedMesh,{p=v(-10,0,10),q=v(10,0,10)},40)
check(second>1 and reads.B==1, 'next pass reads the updated joint position')
reads={}; failOnce=true
local _, retried=shared(sharedMesh,{p=v(-10,30,30),q=v(10,30,30)},40)
check(reads.B==2 and retried ~= nil, 'a failed shared socket read is retried later in the pass')
-- a severed part is no target: the same sweep through the head and the limb reads the head with nothing cut, and
-- the limb once the head is off (a swing at her body after a beheading must read the torso, never the severed head)
points["Bip001-Head"]=v(0,0,10)
local _, headed, headBone=geometry(mesh,{p=v(-20,0,10),q=v(20,0,10)},40)
check(headBone=="Bip001-Head", 'with nothing cut the head sphere wins the tie at its own point')
local _, kept, keptBone=geometry(mesh,{p=v(-20,0,10),q=v(20,0,10)},40,function(b) return b=="Bip001-Head" end)
check(keptBone=="Bip001-L-UpperArm" and kept and kept<1e-6, 'with the head cut the same sweep reads the limb instead')
local _, _, segBone=shared(sharedMesh,{p=v(-10,0,10),q=v(10,0,10)},40,function(b) return b=="A" end)
check(segBone=="B", 'a cut segment is skipped, its neighbour still reads')
print(fails==0 and "PASS" or "FAIL")
