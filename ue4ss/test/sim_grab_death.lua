-- A death after an enemy's grab is a full ragdoll: no animated fall, no legs-on fall,
-- so the finisher's posing can't pull a separated half back onto her.
local T = require("smash_world").boot('s.gore.blood = false')
local F, G = T.F, T.G
local print, fails = F.say, 0
local function check(c, what) print((c and "ok   " or "FAIL ") .. what); if not c then fails = fails + 1 end end
check(T.ctx.grabDeath ~= nil, "grabDeath wiring exists")
check(T.ctx.grabDeath() == false, "no grab: not a grab death")
T.state.hm.lethal = { t = os.clock(), wasGrab = true }
check(T.ctx.grabDeath() == true, "lethal hit in a grab: grab death")
local held = 0
for _ = 1, 20 do if G.torso_legs() == nil then held = held + 1 end end
check(held == 20, "grab death: legs never stay in the fall")
check(F.find("grab death") ~= nil, "grab death logged")
T.state.hm.lethal = nil
check(T.ctx.grabDeath() == false, "lethal cleared: not a grab death")
-- A non-limb result rolled at the hit must be the one used after the grab releases.
local hm, sw = T.state.hm, T.state.sw
local oldSlice, oldNear, oldLaser, oldGlass = G.slice, G.near_odds, sw.laser_hit, T.ctx.glass
local oldEnemies, oldWound, oldDeath = T.ctx.enemies, G.wound, T.ctx.tune.gore.death
local oldExplosion, oldRock, oldProjectile, oldDeathProjectile = sw.explosion_hit, sw.rock_blow, sw.projectile_hit, sw.death_projectile
T.ctx.enemies = { grab_now = function() return { cls = "Enemy", mn = "grab", how = "hand", last = os.clock(), since = os.clock() - 1 } end }
T.ctx.glass = { bar_pct = function() return 0 end }
T.ctx.tune.gore.death = { limb = 0, head = 100, torso = 0, split = 0, diagonal = 0 }
G.wound = function() end
G.near_odds = function() return nil end
sw.explosion_hit, sw.rock_blow, sw.projectile_hit, sw.death_projectile = function() end, function() end, function() end, function() end
local deathHitIndex, originalDeathHit, guessed = nil, nil, 0
for i = 1, math.huge do
  local n, v = debug.getupvalue(hm.lethal_watch, i)
  if not n then break end
  if n == "death_hit" then deathHitIndex, originalDeathHit = i, v; break end
end
assert(deathHitIndex, "lethal watcher must expose death_hit")
debug.setupvalue(hm.lethal_watch, deathHitIndex, function() guessed = guessed + 1; return { n = { X = 1, Y = 0, Z = 0 } } end)
hm.armed, hm.lethal = true, nil
hm.lethal_watch(T.pawn, T.E.mesh)
check(hm.lethal and hm.lethal.roll == "blade" and hm.lethal.kind == "head",
  "real no-blade lethal watcher rolls and retains the head before grab release")
check(guessed == 0, "a deferred rolled result does not fall through to a later guessed blade")
-- A torso smash can defer even when no grab was detected. The later death swing must
-- not replace the killing hit (as in the Juggernaut report).
local oldSmashKill, killing, laterHit = sw.smash_kill, { loc = { X = 1, Y = 2, Z = 3 } }, { loc = { X = 9, Y = 9, Z = 9 } }
local replayed
T.ctx.enemies = { grab_now = function() return nil end }
sw.rock_blow = function() return killing end
sw.smash_kill = function(_, _, h)
  if h.early then return false, "later" end
  replayed = h; return true
end
hm.armed, hm.lethal = true, nil
hm.lethal_watch(T.pawn, T.E.mesh)
check(hm.lethal and hm.lethal.held == killing, "deferred torso smash retained without a grab")
sw.laser_hit = function() return nil end
T.state.gore_cut(T.pawn, T.E.mesh, laterHit, nil)
check(replayed == killing, "death replays killing smash instead of later swing")
sw.smash_kill = oldSmashKill
debug.setupvalue(hm.lethal_watch, deathHitIndex, originalDeathHit)
hm.lethal = nil
T.ctx.enemies, G.wound, T.ctx.tune.gore.death = oldEnemies, oldWound, oldDeath
sw.explosion_hit, sw.rock_blow, sw.projectile_hit, sw.death_projectile = oldExplosion, oldRock, oldProjectile, oldDeathProjectile
local selected
local oldBlow, blows = G.blow, 0
G.blow = function() blows = blows + 1; return true end
G.slice = function(_, _, _, _, kind) selected = kind; return true end
G.near_odds = function() return nil end
sw.laser_hit = function() return nil end
T.ctx.glass = { death_cut = function() return nil end }
hm.lethal = { t = os.clock(), wasGrab = true, roll = "odds", kind = "head" }
T.state.gore_cut(T.pawn, T.E.mesh, nil, nil)
check(selected == "head", "deferred grab death uses the kind rolled at the hit")
selected = nil
hm.lethal = { t = os.clock(), wasGrab = true, roll = "blade", kind = "head", judged = true }
T.state.gore_cut(T.pawn, T.E.mesh, { t = os.clock(), n = { X = 1, Y = 0, Z = 0 } }, nil)
check(selected == "head" and blows == 0, "no-blade grab roll survives a later unrelated blade")
hm.lethal = nil
G.slice, G.near_odds, sw.laser_hit, T.ctx.glass = oldSlice, oldNear, oldLaser, oldGlass
G.blow = oldBlow
-- Find the real animated-death decision through registered callbacks, and compare the same marked show.
local visited, decide = {}, nil
local function find(fn)
  if type(fn) ~= "function" or visited[fn] or decide then return end
  visited[fn] = true
  for i = 1, math.huge do
    local name, value = debug.getupvalue(fn, i)
    if not name then break end
    if name == "animated_death" then decide = value; return end
    if name ~= "_ENV" then find(value) end
  end
end
for _, callbacks in pairs(F.hooks) do for _, fn in ipairs(callbacks) do find(fn) end end
for _, b in ipairs(F.binds) do find(b.cb) end
check(type(decide) == "function", "production animated-death decision found")
T.ctx.tune.active.animated = true
rawset(T.pawn, "RagdollInfo", { ImpulseLimitVelocity = 701 })
T.E.s.sim = true
hm.lethal = { t = os.clock(), wasGrab = true }
check(decide(T.pawn, T.E.mesh, nil) == false and T.E.s.sim, "marked grab death leaves physics on")
hm.lethal = nil
check(decide(T.pawn, T.E.mesh, nil) == true, "same marked show animates without a grab")
check(#F.errors == 0, "no errors (" .. table.concat(F.errors, "; ") .. ")")
print(fails == 0 and "PASS" or "FAIL")
