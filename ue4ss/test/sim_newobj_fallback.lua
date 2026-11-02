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
print('PASS')
