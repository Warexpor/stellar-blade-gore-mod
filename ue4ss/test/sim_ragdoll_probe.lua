-- Probe snapshots are diagnostic only: normal deaths must not collect them, but the explicit probe switch still does.
local T=require("smash_world").boot()
local F,E,R=T.F,T.E,T.ctx.rag
local fails=0
local function check(ok,msg) F.say((ok and "ok   " or "FAIL ")..msg); if not ok then fails=fails+1 end end
local counts={}
for i=1,100 do
  local name,fn=debug.getupvalue(R.start,i)
  if not name then break end
  if name=="joint_lengths" or name=="cape_lengths" or name=="joint_rolls" then
    counts[name]=0
    debug.setupvalue(R.start,i,function(...) counts[name]=counts[name]+1; return fn(...) end)
  end
end
check(counts.joint_lengths~=nil and counts.cape_lengths~=nil and counts.joint_rolls~=nil,"all diagnostic snapshots are instrumented")
E.s.sim=true
T.ctx.tune.gore.probes=false
R.start(T.pawn,E.mesh,"death",nil)
check(counts.joint_lengths==0 and counts.cape_lengths==0 and counts.joint_rolls==0,"ordinary death skips joint diagnostic snapshots")
R.stop(T.pawn)
T.ctx.tune.gore.probes=true
R.start(T.pawn,E.mesh,"death",nil)
check(counts.joint_lengths==1 and counts.cape_lengths==1 and counts.joint_rolls==1,"explicit probe setting retains all diagnostic snapshots")
R.stop(T.pawn)
F.say(fails==0 and "PASS" or "FAIL")
