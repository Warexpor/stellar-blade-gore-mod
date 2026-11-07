local create=dofile('ue4ss/Mods/StellarBladeGore/Scripts/hits_after.lua')
local now, clock=10,os.clock
os.clock=function() return now end
local lines={}
local function log(s) lines[#lines+1]=s end
local function has(pat) for _, s in ipairs(lines) do if s:find(pat, 1, true) then return true end end; return false end
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
  function() return swing end,try,function(vv) return vv end,len,dist,sub,dot,cross,unit,log)
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
local slow={time_scale=function() return 0.25 end,held=function() return true end}
local tick_slow=create(sw,ah,slow,function() return tune end,function() return gore end,
  function() return swing end,try,function(vv) return vv end,len,dist,sub,dot,cross,unit,log)
local step2=tick_slow and sw.after_step(swing,{})
check(step2 and math.abs(step2.v-2000)<0.001, 'under quarter-speed slow motion the same motion reads four times as fast')
local verySlow={time_scale=function() return 0.05 end,held=function() return true end}
create(sw,ah,verySlow,function() return tune end,function() return gore end,
  function() return swing end,try,function(vv) return vv end,len,dist,sub,dot,cross,unit,log)
swing={bones={'hand'},hist={{t=now-0.01,p={v(0,0,0)}},{t=now,p={v(1,0,0)}}}}
local shortStep=sw.after_step(swing,{})
check(shortStep and math.abs(shortStep.v-2000)<0.001, 'short frames remain measurable at five percent speed')
-- blunt melee follow-up smashes instead of cutting (second hammer blow after the upper body)
now=13
local smashed, blown, marked = 0, 0, 0
gore={busy=function() return false end,cuts_on=function() return 0,false end,aim=function() end,
  smash=function() smashed=smashed+1; return true end,blow=function() blown=blown+1; return false end,
  on_hit=function() end,hit_mark=function() marked=marked+1 end}
sw.blunt_of=function(h) return h.wbone == 'HammerEnd' end
sw.after_geometry=function(mesh, best, reach) return v(0,0,0), 5, 'Bip001-R-Calf', nil end
sw.list={{addr=99,k='k1',actor='a1',who='HammerGuy',bones={'HammerEnd'},
  hist={{t=now-0.05,p={v(0,0,0)}},{t=now,p={v(100,0,0)}}}}}
tune={gore={afterHits={from=0,rearm=0},smash={enabled=true}}}
ah.projectiles = {}
local tick2=create(sw,ah,{held=function() return true end},function() return tune end,function() return gore end,
  function() return swing end,try,function(vv) return vv end,len,dist,sub,dot,cross,unit,log)
tick2({},{})
check(smashed == 1 and blown == 0, 'blunt after-death melee smashes instead of cutting')
-- sharp hair still cuts, never smashes
smashed, blown, marked = 0, 0, 0
sw.list={{addr=100,k='k2',actor='a2',who='CH_M_NA_26_Blueprint_C_1',bones={'LeftHandHair4'},
  hist={{t=now-0.05,p={v(0,0,0)}},{t=now,p={v(100,0,0)}}}}}
sw.blunt_of=function(h) return false end
tune={gore={afterHits={from=0,rearm=0},smash={enabled=true},hitMarks={enabled=false}}}
gore.blow=function() blown=blown+1; return true end
local tick3=create(sw,ah,{held=function() return true end},function() return tune end,function() return gore end,
  function() return swing end,try,function(vv) return vv end,len,dist,sub,dot,cross,unit,log)
tick3({},{})
check(smashed == 0 and blown == 1, 'sharp hair after-death blow cuts, never smashes')
-- a body hit after a decapitation: the head is off, the torso hit still cuts (never nothing with no line)
now=14
smashed, blown, marked, lines = 0, 0, 0, {}
ah.t0, ah.n, ah.armedBy, ah.lastBy, ah.toldSoon = now-1, 0, {}, {}, nil
local function freshSwing(addr, who, dx)
  sw.list={{addr=addr,k='k'..addr,actor='a'..addr,who=who,bones={'Blade'},
    hist={{t=now-0.05,p={v(0,0,0)}},{t=now,p={v(dx,0,0)}}}}}
end
freshSwing(101, 'BladeGuy', 100)
sw.blunt_of=function() return false end
sw.after_geometry=function(mesh, best, reach, cut)
  check(cut and cut('Bip001-Head') == true and not cut('Bip001-Spine1'),
    'severed parts read as cut, the rest as kept')
  return v(0,0,0), 5, 'Bip001-Spine1', nil
end
tune={gore={afterHits={from=0.6,rearm=0.35},smash={enabled=true},hitMarks={enabled=false}}}
gore={busy=function() return false end,cuts_on=function() return 1,false end,aim=function() end,
  already_cut=function(mesh, b) return b == 'Bip001-Head' end,
  smash=function() smashed=smashed+1; return true end,blow=function() blown=blown+1; return true end,
  on_hit=function() end,hit_mark=function() marked=marked+1 end}
local tick4=create(sw,ah,{held=function() return true end},function() return tune end,function() return gore end,
  function() return swing end,try,function(vv) return vv end,len,dist,sub,dot,cross,unit,log)
tick4({},{})
check(blown == 1 and smashed == 0, 'body hit after a decapitation cuts the torso')
check(has('after death (') and not has('blood only'), 'the torso cut leaves its line')
-- the killing swing's own follow-through: too soon, told once, never silent and never a cut
now=15
smashed, blown, lines = 0, 0, {}
ah.t0, ah.toldSoon = now-0.1, nil
freshSwing(101, 'BladeGuy', 100)
tick4({},{})
check(ah.toldSoon == true and smashed == 0 and blown == 0 and has('too soon'), 'too-soon follow-through is told once')
tick4({},{})
local soon=0
for _, s in ipairs(lines) do if s:find('too soon', 1, true) then soon=soon+1 end end
check(soon == 1, 'the too-soon line fires once a death')
-- no part of her near the swing, and too far or too slow: told, capped, never silent
now=16
lines, ah.toldSoon, ah.t0, ah.noGeo, ah.farDrops = {}, true, now-1, 0, 0
freshSwing(101, 'BladeGuy', 100)
sw.after_geometry=function() return nil end
for i=1,5 do tick4({},{}) end
local geo=0
for _, s in ipairs(lines) do if s:find('no part of her near', 1, true) then geo=geo+1 end end
check(geo == 4, 'missing geometry is told, capped (' .. geo .. ')')
now=17
lines, ah.farDrops = {}, 0
freshSwing(101, 'BladeGuy', 100)
sw.after_geometry=function() return v(0,0,0), 200, 'Bip001-Spine1', 40 end
for i=1,5 do tick4({},{}) end
local far=0
for _, s in ipairs(lines) do if s:find('too far or too slow', 1, true) then far=far+1 end end
check(far == 4, 'far or slow passes are told, capped (' .. far .. ')')
-- a gated hit (weapon never slowed, rearm not up): told, capped, never silent. Mid-speed: slow enough to
-- gate, fast enough that the slowdown re-arm does not clear the gate first
now=18
lines = {}
ah.armedBy[200], ah.lastBy[200] = false, now
freshSwing(200, 'SlowGuy', 20)
tune={gore={afterHits={from=0,rearm=10},smash={enabled=true}}}
tick4({},{})
check(has('not cut, its weapon not slowed'), 'a gated hit names its gate')
-- past the first few non-blows: still told, capped, never silent
now=19
lines, ah.quietBlow, ah.brushes = {}, 0, 3
freshSwing(201, 'Idler', 100)
sw.after_geometry=function() return v(0,0,0), 5, 'Bip001-Spine1', nil end
tune={gore={afterHits={from=0,rearm=0},smash={enabled=true}}}
local ctx5={held=function() return true end,enemies={attacking=function() return false end}}
local tick5=create(sw,ah,ctx5,function() return tune end,function() return gore end,
  function() return swing end,try,function(vv) return vv end,len,dist,sub,dot,cross,unit,log)
for i=1,5 do tick5({},{}) end
local quiet=0
for _, s in ipairs(lines) do if s:find(': not a blow (', 1, true) then quiet=quiet+1 end end
check(quiet == 4, 'later non-blows stay visible, capped (' .. quiet .. ')')
-- Faster misses, gated packmates and other weapons must not hide a genuine crossing.
local function reset_at(t)
  now=t; lines={}; blown=0
  ah.t0,ah.n,ah.armedBy,ah.lastBy,ah.missBy=now-1,0,{},{},{}
  ah.projectiles={}
  tune={gore={afterHits={from=0.4,rearm=0.35},hitMarks={enabled=false}}}
end
local function trail(addr,dx,y)
  return {addr=addr,k='k'..addr,actor='a'..addr,who='enemy'..addr,bones={'Blade'},
    hist={{t=now-0.05,p={v(0,y,0)},origin=v(0,0,0)},{t=now,p={v(dx,y,0)},origin=v(0,0,0)}}}
end
sw.after_geometry=function(_,best) return v(0,0,0), math.abs(best.q.Y), 'Bip001-Spine1',20 end
local observed
gore.blow=function(_,_,h) blown=blown+1; observed=h; return true end
reset_at(20)
sw.list={trail(1,150,100),trail(2,100,0)}
tick4({},{})
check(blown==1 and observed.attacker=='enemy2', 'a faster off-target packmate cannot hide a crossing')
reset_at(21)
sw.list={trail(1,150,0),trail(2,100,0)}
ah.armedBy[1],ah.lastBy[1]=false,now
tick4({},{})
check(blown==1 and observed.attacker=='enemy2', 'an unarmed faster packmate cannot gate a different attacker')
reset_at(22)
local dual=trail(1,0,0)
dual.weapons={{name='fast-miss'},{name='sword'}}
dual.hist[1].w={{a=v(0,100,0),b=v(10,100,0)},{a=v(0,0,0),b=v(10,0,0)}}
dual.hist[2].w={{a=v(150,100,0),b=v(160,100,0)},{a=v(100,0,0),b=v(110,0,0)}}
sw.list={dual}
tick4({},{})
check(blown==1 and observed.wbone=='sword', 'a faster missing blade cannot hide the other blade crossing')
check(observed and observed.weaponNames and observed.weaponNames[2]=='sword', 'follow-up classification receives the hitting tracker weapon names')
reset_at(23)
ah.t0=now-0.399
sw.list={trail(1,100,0)}
tick4({},{})
check(blown==0, '0.399 seconds is still the killing follow-through window')
ah.t0=now-0.401
tick4({},{})
check(blown==1, 'a genuine crossing at 0.401 seconds is eligible')
-- A fresh next step before rearm still cannot count twice; slowdown and elapsed rearm remain independent.
now=now+0.1; sw.list={trail(1,100,0)}
tick4({},{})
check(blown==1, 'the next fast step of the same swing is not counted twice')
now=now+0.05; sw.list={trail(1,1,0)}; tick4({},{})
now=now+0.05; sw.list={trail(1,100,0)}; tick4({},{})
check(blown==2, 'a slowed then accelerated weapon rearms before the timer')
now=now+0.36; sw.list={trail(1,100,0)}; tick4({},{})
check(blown==3, 'a continuous combo can rearm after 0.35 seconds')
reset_at(24)
sw.list={trail(1,100,0)}
now=now+0.21
tick4({},{})
check(blown==0, 'a stale trail cannot hit a body that has since flown into its old path')
reset_at(25)
sw.list={trail(1,100,0)}
sw.list[1].hist[2].origin=v(100,0,0)
tick5({},{})
check(blown==0, 'fast actor translation without relative swing still fails the no-montage gate')
reset_at(26)
sw.list={trail(1,1,0)}
sw.list[1].hist[1].t=now-0.01
local slowNoMontage=create(sw,ah,{held=function() return true end,time_scale=function() return 0.05 end,
  enemies={attacking=function() return false end}},function() return tune end,function() return gore end,
  function() return swing end,try,function(vv) return vv end,len,dist,sub,dot,cross,unit,log)
slowNoMontage({},{})
check(blown==1, 'short slow-motion frame uses game-time relative speed for the no-montage gate')
-- an ordered attack with no weapon trail: told, capped, never silent
now=27
lines, ah.noTrail = {}, 0
sw.list={{addr=203,k='k203',actor='a203',who='Ghost',bones={'Hand'},
  hist={{t=now-1,p={v(0,0,0)}},{t=now-0.9,p={v(10,0,0)}}}}}
local ctx6={held=function() return true end,afterOrderedAt=now-0.5}
local tick6=create(sw,ah,ctx6,function() return tune end,function() return gore end,
  function() return swing end,try,function(vv) return vv end,len,dist,sub,dot,cross,unit,log)
for i=1,5 do tick6({},{}) end
local trail=0
for _, s in ipairs(lines) do if s:find('no weapon trail', 1, true) then trail=trail+1 end end
check(trail == 4, 'an ordered attack with no trail is told, capped (' .. trail .. ')')
os.clock=clock
print(fails==0 and 'PASS' or 'FAIL')
