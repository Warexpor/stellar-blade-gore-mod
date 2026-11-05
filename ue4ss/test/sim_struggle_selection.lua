-- Reproduce the no-cut action selection on the side and face down.
local F = require("fake")
local S = dofile("ue4ss/Mods/StellarBladeGore/Scripts/struggle.lua")
S.init({ tune = { struggle = {} }, log = function() end, try = function(fn) return fn() end, valid = function(x) return x ~= nil end })
local function find(fn, wanted, seen)
  seen = seen or {}; if type(fn) ~= "function" or seen[fn] then return end; seen[fn] = true
  for i=1,200 do
    local name, value = debug.getupvalue(fn,i); if not name then break end
    if name == wanted then return value end
    if name ~= "_ENV" and type(value) == "function" then local found=find(value,wanted,seen); if found then return found end end
  end
end
local choose=assert(find(S.tick,"choose"))
local index
for i=1,200 do local name=debug.getupvalue(choose,i); if not name then break end; if name=="st" then index=i; break end end
assert(index)
local _, previous=debug.getupvalue(choose,index)
local oldRandom=math.random
math.random=function() return 0.5 end
local fails=0
local function check(ok, msg) F.say((ok and "ok   " or "FAIL ")..msg); if not ok then fails=fails+1 end end
local function action(deg)
  local state={plan={alone=true,arms={"L","R"},legs={"L","R"}},tries=0,triesMax=1,acts={}}
  debug.setupvalue(choose,index,state)
  local a=math.rad(deg)
  return choose({up={X=1,Y=0,Z=0},front={X=0,Y=-math.sin(a),Z=math.cos(a)}},1)
end
local left,right,front=action(-98),action(98),action(180)
check(left=="rise" or left=="prop", "left-side pose starts an attempted rise")
check(right=="rise" or right=="prop", "right-side pose starts an attempted rise")
check(front=="curl", "face-down pose starts a curl instead of remaining idle")
math.random=oldRandom
debug.setupvalue(choose,index,previous)
F.say(fails==0 and "PASS" or "FAIL")
