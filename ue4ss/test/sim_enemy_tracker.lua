local T = require('smash_world').boot('s.gore.blood = true\ns.gore.pool = true')
local F, E, G, pawn = T.F, T.E, T.G, T.pawn
local function upvalue(fn, wanted)
  for i = 1, 100 do local n, v = debug.getupvalue(fn, i); if not n then break end; if n == wanted then return v end end
  error('missing upvalue ' .. wanted)
end
local enemy = upvalue(G.enemy_hit, 'enemy')
local track = upvalue(G.smashed.out, 'track')
local trackers = select(2, upvalue(G.pool_grow, 'get_lists')())
local function pos() return T.v(0, 0, 0) end
enemy.run(nil, function() track(pawn, pos, 'body', E.mesh, 30) end)
local player = trackers[#trackers]
local owner = 0x12345
enemy.run(owner, function() track(pawn, pos, 'smash chunk', E.mesh, 11) end)
local chunk = trackers[1]
local function contains(list, obj) for _, v in ipairs(list) do if v == obj then return true end end return false end
local fails = 0
local function check(ok, msg) F.say((ok and 'ok   ' or 'FAIL ') .. msg); if not ok then fails = fails + 1 end end
check(enemy.owned[chunk] == owner, 'front-inserted smash tracker belongs to the enemy')
G.enemy_gone(owner, nil, 'vanished')
trackers = select(2, upvalue(G.pool_grow, 'get_lists')())
check(not contains(trackers, chunk), 'enemy cleanup removes its smash tracker')
check(contains(trackers, player), 'enemy cleanup preserves the player tracker')
enemy.run(owner, function() track(pawn, pos, 'smash chunk', E.mesh, 11) end)
chunk = trackers[1]
G.cleanup(pawn, E.mesh)
trackers = select(2, upvalue(G.pool_grow, 'get_lists')())
check(not contains(trackers, player), 'player recovery removes its own tracker')
check(contains(trackers, chunk), 'player recovery preserves the enemy tracker')
G.enemy_gone(owner, nil, 'vanished')
local later = upvalue(G.tick, 'later')
local delayed = { n = 10, fn = function() end }
enemy.run(owner, function() later[#later + 1] = delayed end)
check(enemy.owned[delayed] == owner, 'owner tagging reads the list replaced by cleanup')
G.enemy_gone(owner, nil, 'vanished')
later = upvalue(G.tick, 'later')
check(not contains(later, delayed), 'enemy cleanup removes newly tagged delayed work')
local ok = pcall(enemy.run, owner, function() error('injected failure') end)
check(not ok and enemy.cur == nil, 'callback failure restores the previous owner')
enemy.run(owner, function()
  local nested = pcall(enemy.run, owner + 1, function() error('nested failure') end)
  check(not nested and enemy.cur == owner, 'nested failure restores the outer owner')
end)
check(enemy.cur == nil, 'outer operation clears its owner')
-- A decal-shield engine callback can cause recovery before track() inserts the new entry.
local fired = false
local reentrant = F.obj('ReentrantShield', 'SkeletalMeshComponent', {
  bReceivesDecals = true,
  SetReceivesDecals = function()
    if not fired then fired = true; G.cleanup(pawn, E.mesh) end
  end,
})
enemy.run(owner, function() track(pawn, pos, 'smash chunk', reentrant, 11) end)
trackers = select(2, upvalue(G.pool_grow, 'get_lists')())
local newChunk = trackers[1]
check(fired and newChunk and enemy.owned[newChunk] == owner,
  'tracker joins the current list when shield callback triggers recovery')
G.enemy_gone(owner, nil, 'vanished')
trackers = select(2, upvalue(G.pool_grow, 'get_lists')())
check(not contains(trackers, newChunk), 'enemy cleanup removes the reentrant tracker')
-- Pool growth can call into the engine before the tracker loop starts.
local poolsTick = upvalue(G.tick, 'pools_tick')
for i = 1, 100 do
  local name = debug.getupvalue(poolsTick, i)
  if not name then break end
  if name == 'pool_n' then debug.setupvalue(poolsTick, i, 2); break end
end
local grew, sampled = false, false
local decal = F.obj('ReentrantPool', 'DecalComponent', {
  SetWorldScale3D = function() grew = true; G.cleanup(pawn, E.mesh) end,
})
trackers[#trackers + 1] = { pawn = pawn, bone = 'test', rmax = 30, t = 0, still = 0, sampled = 0, slot = 1,
  where = function() sampled = true; return pos() end,
  pool = { d = decal, at = pos(), n = T.v(0, 0, 1), ok = 30, r = 4, age = 0 } }
F.step(0.1)
G.poolClock = F.t - 0.1
G.tick(pawn)
check(grew and not sampled, 'pool tick uses the replacement list after a growth callback triggers recovery')
F.say(fails == 0 and 'PASS' or 'FAIL')
