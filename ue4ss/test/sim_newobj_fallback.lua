-- A native watcher failure must not silently install general UE4SS callbacks on loading threads.
local path = 'ue4ss/Mods/StellarBladeGore/Scripts/newobj.lua'
local function run(mode, state)
  local callbacks = 0
  NotifyOnNewObject = function() callbacks = callbacks + 1 end
  local m = dofile(path)
  m.init({ tune = { newObjectWatch = mode }, log = function() end,
    try = function(f) local ok, v = pcall(f); if ok then return v end end,
    valid = function(o) return o ~= nil end,
    gore = { native_state = function() return state end } })
  m.watch('/Script/SB.SBCharacter', function() end)
  m.tick()
  return m.mode(), callbacks
end
local mode, n = run(true, 'failed')
assert(mode == 'off' and n == 0, 'failed native watcher registered unsafe callback')
mode, n = run('ue4ss', 'failed')
assert(mode == 'lua' and n == 1, 'explicit UE4SS mode no longer registers callback')
mode, n = run(false, 'failed')
assert(mode == 'off' and n == 0, 'disabled watcher registered callback')
-- Failed reconfiguration or a truncated native class list must not be reported as confirmed.
local F = require('fake')
local realPrint = F.say
local status = 'ok watching 1, super +64'
local m = dofile(path)
m.init({ tune={newObjectWatch=true}, log=function() end,
  try=function(f) local ok,v=pcall(f); if ok then return v end end,
  valid=function(o) return o ~= nil and o ~= false end,
  gore={native_state=function() return 'ready' end,
    command=function(s) if s == 'O?' then return 'ok 0 queued, 0 dropped, 0 taken' end; return status end,
    fire=function() F.cdo.DebugCameraControllerRef=nil end} })
m.watch('/Script/SB.SBCharacter',function() end)
m.tick()
assert(m.mode() == 'native' and m.watched('/Script/SB.SBCharacter'), 'successful native registration not confirmed')
m.watch('/Script/UMG.UserWidget',function() end)
status='err registration failed'
m.tick()
assert(not m.watched('/Script/UMG.UserWidget') and not m.watched('/Script/SB.SBCharacter'),
  'failed registration must leave watch status unconfirmed')
m.watch('/Script/SB.SBBTDecorator_SbCheckActorEffect',function() end)
status='ok watching 1, super +64'
m.tick()
assert(not m.watched('/Script/SB.SBCharacter'), 'truncated native list must leave watch status unconfirmed')
m.watch('/Script/SB.SBCharacter',function() end)
status='ok watching 4, super +64'
m.tick()
assert(m.watched('/Script/SB.SBCharacter') and m.watched('/Script/UMG.UserWidget'),
  'later successful full registration restores confirmed status')
realPrint('PASS')
