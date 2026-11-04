-- Compare the optimized weapon sweep with the original vector calculation across long, fast trails.
local timer = os.clock
local F, E = require("fake"), require("eve")
local print = F.say
local pawn = E.make(F)
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
assert(pcall(dofile, DIR .. "main.lua"))
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)
local function up(fn, wanted, seen)
  seen = seen or {}; if type(fn) ~= "function" or seen[fn] then return end; seen[fn] = true
  for i = 1, 200 do
    local n, v = debug.getupvalue(fn, i); if not n then break end
    if n == wanted then return v end
    if n ~= "_ENV" and type(v) == "function" then local x = up(v, wanted, seen); if x then return x end end
  end
end
local tick = F.hooks["/Game/Art/Character/PC/CH_P_EVE_01/Blueprints/CH_P_EVE_01_Blueprint.CH_P_EVE_01_Blueprint_C:ReceiveTick"][1]
local ctx, sw = assert(up(tick, "goreCtx")), assert(up(tick, "sw"))
local actor = F.obj("sweep enemy", "Enemy", { GetActorForwardVector = function() return {X=1,Y=0,Z=0} end })
local guard = assert(ctx.keep(actor))
local function v(x,y,z) return {X=x,Y=y,Z=z} end
local function sub(a,b) return v(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
local function dot(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
local function length(a) return math.sqrt(dot(a,a)) end
local function near(p,a,b)
  local ab = sub(b,a)
  local t = math.max(0, math.min(1, dot(sub(p,a),ab)/math.max(dot(ab,ab),1e-4)))
  local x = v(a.X+ab.X*t,a.Y+ab.Y*t,a.Z+ab.Z*t)
  return x,length(sub(p,x))
end
local function reference(h, now)
  local best
  for i=2,#h do
    local dt = h[i].t-h[i-1].t
    local o,e=h[i-1].w[1],h[i].w[1]
    local speed=math.max(length(sub(o.a,e.a)),length(sub(o.b,e.b)))/dt
    if speed>=300 then
      local n,d,p,bone
      local cuts=math.max(2,math.min(12,math.ceil(speed*dt/15)))
      for _,spec in ipairs(ctx.SWING_AT) do
        local a=h[i].pose[spec[1]].t
        local b=spec[3] and h[i].pose[spec[3]].t
        local pt=b and v(a.X+0.4*(b.X-a.X),a.Y+0.4*(b.Y-a.Y),a.Z+0.4*(b.Z-a.Z)) or a
        for j=0,cuts do
          local f=j/cuts
          local x=v(o.a.X+(e.a.X-o.a.X)*f,o.a.Y+(e.a.Y-o.a.Y)*f,o.a.Z+(e.a.Z-o.a.Z)*f)
          local y=v(o.b.X+(e.b.X-o.b.X)*f,o.b.Y+(e.b.Y-o.b.Y)*f,o.b.Z+(e.b.Z-o.b.Z)*f)
          local point,dist=near(pt,x,y)
          if not d or dist<d then n,d,p,bone=point,dist,pt,spec[1] end
        end
      end
      local s0=near(p,o.a,o.b)
      local s1=near(p,e.a,e.b)
      local away=dot(sub(s1,s0),sub(p,s0))<0
      local score=d-30*math.min(1,speed/9000)+(away and 60 or 0)+60*(now-h[i].t)
      if not best or score<best.score then best={score=score,dist=d,point=n,bone=bone,speed=speed} end
    end
  end
  return best
end
math.randomseed(715)
local passed, cases=true, {}
for test=1,12 do
  local h, pose = {}, {}
  for _, spec in ipairs(ctx.SWING_AT) do
    for _, name in ipairs({spec[1],spec[3] or spec[1]}) do
      if not pose[name] then pose[name]={t=v(math.random(-30,30),math.random(-30,30),math.random(-30,30))} end
    end
  end
  local now=os.clock()
  for i=1,30 do
    local x=(i-15)*8+test; local z=math.sin(i/3)*7
    h[i]={t=now-(30-i)*0.016, pose=pose, w={[1]={a=v(x,-25,z),b=v(x,25,z+4)}}}
  end
  local s={hist=h,k=guard,actor=actor,who="test",weapons={[1]={name="blade",socket="hand"}}}
  cases[#cases+1]=s
  local expected=reference(h,now)
  local actual=sw.of(s,pawn.Mesh)
  if not actual or actual.part~=expected.bone or math.abs(actual.part_d-expected.dist)>1e-8
    or length(sub(actual.at,expected.point))>1e-8 or math.abs(actual.speed-expected.speed)>1e-8 then
    print("FAIL sweep differs on case " .. test); passed=false
  end
end
do
  local a, b, both = cases[1], {}, {}
  for i, step in ipairs(a.hist) do
    local w=step.w[1]
    local w2={a=v(w.a.X+13,w.a.Y,w.a.Z+6),b=v(w.b.X+13,w.b.Y,w.b.Z+6)}
    b[i]={t=step.t,pose=step.pose,w={[1]=w2}}
    both[i]={t=step.t,pose=step.pose,w={[1]=w,[2]=w2}}
  end
  local ea, eb = reference(a.hist,os.clock()), reference(b,os.clock())
  local expected = ea.score <= eb.score and ea or eb
  local actual = sw.of({hist=both,k=guard,actor=actor,who="test",weapons={[1]={name="one",socket="hand"},[2]={name="two",socket="hand"}}},pawn.Mesh)
  if not actual or actual.part~=expected.bone or math.abs(actual.part_d-expected.dist)>1e-8
    or length(sub(actual.at,expected.point))>1e-8 then print("FAIL two-blade sweep differs"); passed=false end
end
local t=timer()
for _,s in ipairs(cases) do reference(s.hist,os.clock()) end
local old=timer()-t
t=timer()
for _,s in ipairs(cases) do sw.of(s,pawn.Mesh) end
local new=timer()-t
print(string.format("12 long sweeps: reference %.3f s, optimized %.3f s",old,new))
print(passed and "PASS" or "FAIL")
