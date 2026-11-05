local create = dofile('ue4ss/Mods/StellarBladeGore/Scripts/gore_copies.lua')
local now, clock = 1, os.clock
os.clock = function() return now end
FName = function(x) return x end
local M, commands, lod, cuts, clones = {}, {}, {}, {}, {}
local on_command
local function obj(a) return { a=a, GetAddress=function(self) return self.a end } end
local mesh, asset = obj(0x100), obj(0x500)
mesh.SkeletalMesh=asset
local children={}
mesh.AttachChildren={ForEach=function(_,fn) for _,c in ipairs(children) do fn(nil,{get=function() return c end}) end end}
mesh.MasterPoseComponent={Get=function() return nil end}
local function try(fn) local ok,v=pcall(fn); if ok then return v end end
local function valid(o) return o~=nil and not o.dead end
M.lod0=function(c,on) lod[c.a]=on end
create(M,{addr=function(o) return o and o.a end,mesh_name=function(o) return o and o.SkeletalMesh and 'mesh' end,
  name_of=function() return 'mesh' end,command=function(s) commands[#commands+1]=s; if on_command then local f=on_command; on_command=nil; f() end; return 'ok' end,
  clone_of=function() end,log=function() end,clones=function() return clones end,cuts=function() return cuts end,
  guards=function() return try,valid end})
local fails=0
local function check(ok,msg) print((ok and 'ok   ' or 'FAIL ')..msg); if not ok then fails=fails+1 end end
local function members(cmd)
  local n=0; for _ in (cmd or ''):gmatch(',%x+') do n=n+1 end; return n-1
end
for i=1,20 do
  local c=obj(0x200+i); c.SkeletalMesh=asset; c.MasterPoseComponent={Get=function() return mesh end}; children[#children+1]=c
end
local own=obj(0x400); own.SkeletalMesh=asset; own.MasterPoseComponent={Get=function() return mesh end}; children[#children+1]=own; clones[1]=own
check(#M.copies_find(mesh)==20, 'discovers external pose-following copies and excludes our clone')
M.copies_sync(mesh,false)
check(#commands==2 and members(commands[1])==16 and members(commands[2])==4, 'synchronizes all 20 copies in native-sized batches')
local all_lod=true; for _,c in ipairs(children) do if c~=own and not lod[c.a] then all_lod=false end end
check(all_lod and lod[own.a]==nil, 'forces LOD0 on each synchronized external copy')
commands={}; M.copies_sync(mesh,false)
check(#commands==0, 'unchanged copies are not resent on ordinary discovery')
M.copies.dirty[mesh.a]=true; cuts={{addr=mesh.a,mesh=mesh}}
M.copies_flush()
check(#commands==2 and members(commands[1])==16 and members(commands[2])==4, 'dirty cut resynchronizes every existing copy')
commands={}; M.copies.dirty[mesh.a]=true
on_command=function() M.copies.dirty[mesh.a]=true end
M.copies_flush()
check(M.copies.dirty[mesh.a] == true, 'a cut queued during synchronization stays dirty for the next frame')
commands={}; M.copies_flush()
check(#commands==2 and not M.copies.dirty[mesh.a], 'next frame synchronizes the re-entrant cut and clears its dirty flag')
commands={}; M.copies.dirty[mesh.a]=true
on_command=function() error('injected synchronization failure') end
local ok = pcall(M.copies_flush)
check(not ok and M.copies.dirty[mesh.a], 'failed synchronization retains dirty work for retry')
commands={}; M.copies_flush()
check(#commands==2 and not M.copies.dirty[mesh.a], 'dirty work retries after a synchronization error')
commands={}; M.copies.dirty[mesh.a]=true
on_command=function() M.copies_clear(mesh.a) end
M.copies_flush()
local released=true; for _,c in ipairs(children) do if c~=own and lod[c.a]~=false then released=false end end
check(#commands==3 and released and M.copies.of[mesh.a]==nil, 'recovery during the first batch stops further synchronization')
commands={}; M.copies_sync(mesh,false)
commands={}; M.copies_clear(mesh.a)
check(#commands==2 and members(commands[1])==16 and members(commands[2])==4, 'recovery clears every copy in native-sized batches')
local all_released=true; for _,c in ipairs(children) do if c~=own and lod[c.a]~=false then all_released=false end end
check(all_released and M.copies.of[mesh.a]==nil and M.copies.dirty[mesh.a]==nil, 'recovery releases LOD and copy bookkeeping')
local old_sync, processed = M.copies_sync, {}
local other, removed = obj(0x600), obj(0x700)
cuts={{addr=mesh.a,mesh=mesh},{addr=other.a,mesh=other},{addr=removed.a,mesh=removed}}
M.copies.dirty={[mesh.a]=true,[other.a]=true,[removed.a]=true}
M.copies_sync=function(c)
  processed[#processed+1]=c.a
  if c==mesh then cuts={{addr=other.a,mesh=other}} end
end
M.copies_flush()
check(#processed==1 and M.copies.dirty[other.a] and not M.copies.dirty[removed.a], 'replaced cut list preserves only surviving pending work')
M.copies_flush()
check(#processed==2 and processed[2]==other.a and not M.copies.dirty[other.a], 'surviving cut synchronizes on the next frame')
M.copies_sync=old_sync
os.clock=clock
print(fails==0 and 'PASS' or 'FAIL')
