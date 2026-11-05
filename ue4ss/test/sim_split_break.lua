local create=dofile('ue4ss/Mods/StellarBladeGore/Scripts/split_break.lua')
local names={'pelvis','spine','spine1','spine2','neck','head'}
local positions={pelvis=0,spine=10,spine1=20,spine2=30,neck=40,head=50}
local function v(z) return {X=0,Y=0,Z=z} end
local function sub(a,b) return {X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z} end
local function dot(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
local function try(f) local ok,r=pcall(f); if ok then return r end end
FName=function(x) return x end
local M={}
local split=create(M,names,4,function(_,b) return positions[b] and v(positions[b]) end,sub,dot,function() return try end)
local parent={arm='spine2',leg='spine',spine2='spine1',spine1='spine',spine='pelvis',neck='spine2',head='neck'}
local mesh={BoneIsChildOf=function(_,child,ancestor)
  while child do if child==ancestor then return true end; child=parent[child] end
  return false
end}
local fails=0
local function check(ok,msg) print((ok and 'ok   ' or 'FAIL ')..msg); if not ok then fails=fails+1 end end
check(split(mesh,v(25),v(1))=='spine2', 'crossing plane selects the first spine bone above the cut')
check(split(mesh,v(2),v(1))==nil, 'plane within pelvis tolerance does not invent a break')
positions.neck=nil
check(split(mesh,v(25),v(1))==nil, 'missing spine bone rejects the break')
positions.neck=40
check(M.her_break(mesh,'spine2',{'arm'})=='spine2', 'original half breaks when every kept limb hangs from it')
check(M.her_break(mesh,'spine2',{'arm','leg'})==nil, 'original half keeps spine intact when a kept leg hangs below the break')
check(M.copy_break(mesh,'spine1',{'arm'})=='neck', 'copy break moves above all kept limbs')
check(M.copy_break(mesh,'spine1',{'leg'})=='spine1', 'copy may break at the plane when its kept limb is below it')
check(M.copy_break(mesh,'unknown',{'arm'})==nil, 'unknown spine bone is rejected')
print(fails==0 and 'PASS' or 'FAIL')
