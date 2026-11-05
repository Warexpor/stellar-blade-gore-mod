local create=dofile('ue4ss/Mods/StellarBladeGore/Scripts/split_cut.lua')
local M, cuts, commands, settings, copyOk, sideResponses = {}, {}, {}, {}, true, {}
local function v(x,y,z) return {X=x,Y=y,Z=z} end
local function sub(a,b) return v(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
local function add(a,b) return v(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
local function scale(a,n) return v(a.X*n,a.Y*n,a.Z*n) end
local function dot(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
local function len(a) return math.sqrt(dot(a,a)) end
local function norm(a) local n=len(a); return n>0 and scale(a,1/n) or nil end
local function obj(a) return {GetAddress=function() return a end} end
local body, clone = obj(100), obj(200)
local function addr(o) return o:GetAddress() end
local function command(s)
  commands[#commands+1]=s
  if s:sub(1,1)=='y' then return copyOk and 'ok copied 1' or 'err copy failed' end
  return 'ok'
end
M.ARM_CUTS={arm=true}; M.rig=function() return true end; M.her_break=function(_,s) return s end
M.copy_break=function(_,s) return s end; M.wedding_cloth=function() end; M.snap=function() return {} end
local prep,cut=create(M,{cfg=function() return settings end,addr=addr,face_of=function() end,clone_of=function() return clone end,
  log=function() end,bone_loc=function() return v(0,0,1) end,spine_break=function() return nil end,
  split_plane=function() return v(0,0,0),v(1,0,0),'test' end,body_frame=function() end,from_body=function() end,
  add=add,sub=sub,scale=scale,norm=norm,len=len,dot=dot,limb_sides=function() return {},{} end,
  place_like=function() end,command=command,enemy={asset=function() return 77 end},split_chains=function() return {},{} end,
  send_limbs=function() end,send_neck=function() return 'ok' end,
  side_cut=function() return table.remove(sideResponses,1) end,SPLIT_RIDE={lid=function() return {} end,of=function() return {} end},
  SPLIT_SINK='sink',ok_cut=function(r) return r:sub(1,2)=='ok' and r:find('seam=1',1,true)~=nil end,
  num=function(r,k) return tonumber(r:match(k..'=(%d+)')) end,v3=function() return function() return 'point' end end,
  cuts=function() return cuts end,add_cut=function(c) cuts[#cuts+1]=c end})
local fails=0
local function check(ok,msg) print((ok and 'ok   ' or 'FAIL ')..msg); if not ok then fails=fails+1 end end
local function q() return {mesh=body,pawn={},why='test'} end
cuts={{mesh=body,addr=100,bone='leg'}}
check(not prep(q()), 'preparation rejects a previous non-arm cut')
cuts={{mesh=body,addr=100,bone='arm'}}; commands={}; copyOk=false
local a=q(); check(prep(a) and not cut(a), 'copy failure aborts the split after an earlier arm cut')
check(#cuts==1 and commands[#commands]:sub(1,1)=='R', 'failed copy restores saved weights without adding split records')
cuts={}; commands={}; copyOk=true; sideResponses={'ok verts=100 vanished=40 unsunk=0 seam=1','ok verts=100 vanished=60 unsunk=0 seam=1'}
local b=q(); check(prep(b) and cut(b) and #cuts==2 and b.cut1~=nil, 'first half records both cuts and hands work to the next stage')
check(M.stage_split_copy(b) and b.cut1==nil and b.r1 and b.r2, 'valid second half completes the cut handoff')
cuts={}; commands={}; sideResponses={'ok verts=100 vanished=0 unsunk=0 seam=1','ok verts=100 vanished=99 unsunk=0 seam=1'}
local c=q(); prep(c); cut(c)
check(not M.stage_split_copy(c) and c.degenerate, 'tiny remaining half is rejected as degenerate')
print(fails==0 and 'PASS' or 'FAIL')
