local create=dofile('ue4ss/Mods/StellarBladeGore/Scripts/hits_after.lua')
local now, clock=10,os.clock
os.clock=function() return now end
local sw={list={},after_geometry=function() end}
local ah={t0=0,n=0,armedBy={},lastBy={},missBy={},projectiles={}}
local tune={gore={afterHits={from=0,rearm=0},smash={enabled=true}}}
local swing={hist={}}
local calls=0
local gore={busy=function() return false end,cuts_on=function() return 0,false end,aim=function() end,smash=function() calls=calls+1; return true end}
local function v(x,y,z) return {X=x,Y=y,Z=z} end
local function sub(a,b) return v(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
local function dot(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
local function len(a) return math.sqrt(dot(a,a)) end
local function dist(a,b) return len(sub(a,b)) end
local function cross(a,b) return v(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X) end
local function unit(a) local n=len(a); return n>0 and v(a.X/n,a.Y/n,a.Z/n) or nil end
local function try(fn) local ok,r=pcall(fn); if ok then return r end end
local tick=create(sw,ah,{held=function() return true end},function() return tune end,function() return gore end,
  function() return swing end,try,function(vv) return vv end,len,dist,sub,dot,cross,unit,function() end)
local fails=0
local function check(ok,msg) print((ok and 'ok   ' or 'FAIL ')..msg); if not ok then fails=fails+1 end end
local function shot() ah.projectiles={{t=now,src='test',dir=v(1,0,0)}} end
shot(); tick({},{}); check(calls==1 and ah.n==1 and #ah.projectiles==0, 'pending projectile dispatches through current gore service')
now=11; gore={busy=function() return false end,cuts_on=function() return 0,false end,aim=function() end,smash=function() calls=calls+10; return true end}
shot(); tick({},{}); check(calls==11 and ah.n==2, 'replacement gore service handles the next projectile')
now=12; tune={gore={afterHits={from=0,rearm=0},smash={enabled=false}}}
shot(); tick({},{}); check(calls==11 and #ah.projectiles==1, 'replacement settings disable projectile smash')
local prev=v(0,0,0); swing={bones={'hand'},hist={{t=11.8,p={prev}},{t=12,p={v(100,0,0)}}}}
local step=sw.after_step(swing,{})
check(step and step.name=='hand' and math.abs(step.v-500)<0.001, 'weapon step resolves motion from current swing history')
os.clock=clock
print(fails==0 and 'PASS' or 'FAIL')
