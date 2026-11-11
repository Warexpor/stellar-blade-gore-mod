-- The attack-down backlog must retain FIFO order on native failure, time-budget deferral, and new arrivals.
local F = require("fake")
local print = F.say
local E = dofile("ue4ss/Mods/StellarBladeGore/Scripts/enemies.lua")
local ctx = { tune={ enemies={attackDown=true}, gore={slowMs=1e9} }, log=function() end,
  try=function(f) local ok,v=pcall(f); if ok then return v end end,
  valid=function(o) return o ~= nil and o ~= false end,
  newobj={watch=function() end} }
E.init(ctx)
local function up(fn, name)
  for i=1,200 do local n,v=debug.getupvalue(fn,i); if not n then break end; if n==name then return v end end
  error('missing upvalue '..name)
end
local tick=up(E.tick,'down_tick')
local down=up(tick,'down')
down.mode,down.scanned,down.hooked='attack',true,true
local function item(i,t) return {k={id=i,idx=i,alive=false},t=t or F.t} end
for i=1,130 do down.pending[i]=item(i) end
down.pending[131]=item(131,F.t+10)
local attempts,fail={},true
ctx.alive_ask=function(ks)
  local ids={}; for _,k in ipairs(ks) do ids[#ids+1]=k.id; k.alive=false end
  attempts[#attempts+1]=ids
  if fail then fail=false; down.pending[#down.pending+1]=item(132,F.t+10); return false end
  return true
end
local fails=0
local function check(c,s) print((c and 'ok   ' or 'FAIL ')..s); if not c then fails=fails+1 end end
tick()
local ordered=#down.pending==132
for i=1,132 do if down.pending[i].k.id~=i then ordered=false end end
check(ordered and #attempts[1]==64, 'failed batch restored ahead of existing and newly queued entries')
tick(); tick(); tick()
local seen={}; for i=2,#attempts do for _,id in ipairs(attempts[i]) do seen[#seen+1]=id end end
ordered=#seen==130
for i=1,130 do if seen[i]~=i then ordered=false end end
check(ordered and #down.pending==2 and down.pending[1].k.id==131 and down.pending[2].k.id==132,
  'all due entries processed once in order; future entries retained')
down.pending={}; for i=1,10 do down.pending[i]=item(i) end
local clock=os.clock; local t=F.t; os.clock=function() t=t+0.003; return t end
tick(); os.clock=clock
ordered=#down.pending==9
for i=1,9 do if down.pending[i].k.id~=i+1 then ordered=false end end
check(ordered,'budget deferral restores the remaining entries in order')
print(fails==0 and 'PASS' or 'FAIL')
