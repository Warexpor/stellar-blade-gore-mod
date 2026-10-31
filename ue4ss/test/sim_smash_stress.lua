-- Bounded work under extreme tuning, simultaneous bursts, frame rates and a freed level.
local T = require("smash_world").boot('s.gore.smash = { enabled = true }\ns.gore.blood = false\ns.gore.torsoLegs = { enabled = false }')
local F,E,G,pawn,W,v=T.F,T.E,T.G,T.pawn,T.world,T.v
local print,fails=F.say,0
local function check(c,s) print((c and "ok   " or "FAIL ")..s); if not c then fails=fails+1 end end
local function frames(n,dt) for _=1,n do F.step(dt or 1/60); G.tick(pawn); G.pump() end end
local s=T.ctx.tune.gore.smash
-- A menu toggle or edited mesh list must join the preload queue even after the initial list was completed.
local w=G.watching
local custom="/Game/Test/CustomMeat.CustomMeat"
s.enabled,s.meshes=true,{custom}
w.next=#w.preload+1
G.smashed.preload(w)
local n,where=0
for i,path in ipairs(w.preload) do if path==custom then n=n+1; where=i end end
check(n==1 and where<w.sounds and w.next<=where,"late menu enable/custom meat preloads before audio, under the existing load budget")
G.smashed.preload(w)
local again=0; for _,path in ipairs(w.preload) do if path==custom then again=again+1 end end
check(again==1,"preload scans never duplicate the meat queue")
s.meshes=nil
E.s.sim=true
local tests={
  {"huge count capped",100000,64}, {"negative count",-2,0}, {"fractional count",3.9,3},
  {"infinite count falls back",math.huge,44}, {"NaN count falls back",0/0,44}, {"string count","9",9},
}
for _,c in ipairs(tests) do
  s.chunksBody=c[2]
  s.sizeMin,s.sizeMax,s.kg,s.speed=20,-10,-1,math.huge
  local n0=#W.spheres
  G.smash(pawn,E.mesh,{loc=E.bone("Bip001-Spine2")},"death")
  frames(120)
  check(#W.spheres-n0==c[3],c[1]..": "..(#W.spheres-n0).." chunks")
  local good=true
  for i=n0+1,#W.spheres do local sp=W.spheres[i]; good=good and sp.radius>=0.5 and sp.radius<=10.625 and sp.kg>=0.01 and sp.vel.Z==sp.vel.Z end
  check(good,c[1]..": valid shapes, masses and velocities")
  G.cleanup(pawn,E.mesh)
end
s.sizeMin,s.sizeMax,s.kg,s.speed=5,11,0.3,350
-- Even a straight upward impact must scatter the torso rather than launch a vertical fountain.
s.chunksBody=44
local launched, chunk = {}, G.smashed.chunk
G.smashed.chunk=function(p,m,at,velocity,...)
  launched[#launched+1]=velocity
  return chunk(p,m,at,velocity,...)
end
G.aim(v(0,0,1))
G.smash(pawn,E.mesh,{loc=E.bone("Bip001-Spine2")},"death")
frames(120)
G.smashed.chunk=chunk
local flat=#launched==44
for _,velocity in ipairs(launched) do flat=flat and velocity.Z<=27 and math.sqrt(velocity.X^2+velocity.Y^2)>0 end
check(flat,"44 torso chunks scatter sideways even for a vertical upward hit")
G.cleanup(pawn,E.mesh)
-- Once the surviving pelvis falls, later batches must follow it rather than emit from midair.
local socket, originalChunk = E.mesh.GetSocketLocation, G.smashed.chunk
local drop, emitted = 0, {}
E.mesh.GetSocketLocation=function(self,b)
  local p=socket(self,b)
  if tostring(b)=="Bip001-Pelvis" then return v(p.X,p.Y,p.Z-drop) end
  return p
end
G.smashed.chunk=function(p,m,at,velocity,...)
  emitted[#emitted+1]=at.Z
  if #emitted==2 then drop=40 end
  return originalChunk(p,m,at,velocity,...)
end
G.smash(pawn,E.mesh,{loc=E.bone("Bip001-Spine2")},"death")
frames(120)
G.smashed.chunk, E.mesh.GetSocketLocation = originalChunk, socket
check(#emitted==44 and emitted[3] < emitted[1]-20,"later torso chunks follow the falling body instead of a fixed airborne source")
G.cleanup(pawn,E.mesh)
-- A long burst overlaps a second cut: each delayed diagnostic must retain its own chunk list.
s.chunksLeg,s.chunks=64,3
local from=#F.log_lines()+1
G.smash(pawn,E.mesh,{loc=v(1000,2009,70)},"death")
frames(8)
G.smash(pawn,E.mesh,{loc=v(1000,1981,126)},"death")
frames(120)
local lines={}
for i,l in ipairs(F.log_lines()) do
  if i>=from and l:find("chunks 2 s on:") then
    local n=0; for _ in l:gmatch("%([%d%-]+ [%d%-]+ [%d%-]+%)") do n=n+1 end
    lines[#lines+1]=n
  end
end
table.sort(lines)
check(#lines==2 and lines[1]==3 and lines[2]==64,"overlapping bursts retain independent 3- and 64-chunk diagnostics")
G.cleanup(pawn,E.mesh)
-- Collision contract plus ballistics across low/high frame rates. This model sweeps the world-dynamic wall.
local sm=F.objects[G.SMASH_MESHES[1]]
for _,fps in ipairs({15,30,60,144}) do
  local sp=G.smashed.chunk(pawn,E.mesh,v(1000,2000,160),v(3000,0,-1500),8,sm)
  frames(fps*4,1/fps)
  check(sp.at.Z>=sp.radius and math.abs(sp.at.Z-sp.radius)<1 and sp.at.X<=1100-sp.radius,
    fps.." fps: fast chunk stays above floor and behind world-dynamic wall")
  G.cleanup(pawn,E.mesh)
end
-- Deferred spawn failure must not leak its unfinished actor either.
for _,failure in ipairs({"failSpawn","failFinish"}) do
  W[failure]=true
  local before=#W.actors
  check(G.smashed.chunk(pawn,E.mesh,v(1000,2000,150),v(0,0,0),8,sm)==nil,failure..": refuses cleanly")
  local dead=true; for i=before+1,#W.actors do dead=dead and W.actors[i].__dead end
  check(dead,failure..": no unfinished actor remains")
  W[failure]=nil
end
-- The old world is freed between batches. Forget must drop references without IsValid on freed memory.
s.chunksBody=64
G.smash(pawn,E.mesh,{loc=E.bone("Bip001-Spine2")},"death")
frames(8)
local n0=#W.spheres
F.free_world()
local newPawn=E.make(F)
G.forget(newPawn)
for _=1,100 do F.step(1/60); G.tick(newPawn); G.pump() end
check(#W.spheres==n0,"world reload cancels every old burst callback")
check(#F.errors==0,"no read of freed old-world objects")
check(#W.violations==0,"all stress chunks use safe collision masks")
for _,e in ipairs(F.errors) do print("FAIL hook: "..e); fails=fails+1 end
for _,l in ipairs(F.log_lines()) do if l:find("failed at stage") or l:find("delayed step failed") then print("FAIL log: "..l); fails=fails+1 end end
print(fails==0 and "PASS" or "FAIL")
