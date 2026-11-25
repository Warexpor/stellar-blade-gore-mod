-- A component callback can queue a cut while the scheduler services a ready bleed.
local T = require('smash_world').boot('s.gore.smash.enabled = false')
local F, E, G, pawn = T.F, T.E, T.G, T.pawn
local function upvalue(fn, wanted)
  for i = 1, 100 do local n, v = debug.getupvalue(fn, i); if not n then break end; if n == wanted then return v end end
  error('missing upvalue ' .. wanted)
end
local bleeds = upvalue(G.tick, 'bleeds')
local called, accepted, callbackFinished, resumed = false, false, false, 0
local originalPumpOnce = G.pump_once
G.pump_once = function(...)
  if callbackFinished then resumed = resumed + 1 end
  return originalPumpOnce(...)
end
local comp = F.obj('ReentrantBleed', 'NiagaraComponent', {
  ResetSystem = function()
    called = true
    accepted = G.slice_bone(pawn, E.mesh, 'Bip001-L-UpperArm', nil, 'test')
    callbackFinished = true
  end,
})
bleeds[#bleeds+1] = { ready = 1, comp = comp }
G.pump()
G.pump_once = originalPumpOnce
local fails = 0
local function check(ok, msg) F.say((ok and 'ok   ' or 'FAIL ') .. msg); if not ok then fails=fails+1 end end
check(called and accepted, 'bleed callback queues a cut')
check(resumed == 1, 'scheduler observes and advances the newly queued cut after the callback')
G.cleanup(pawn, E.mesh)
check(not G.busy(), 'cleanup cancels the reentrant cut')

local mesh = F.obj('EnemyMesh', 'SkeletalMeshComponent', {
  SkeletalMesh = E.mesh.SkeletalMesh,
  GetSocketLocation = E.mesh.GetSocketLocation,
  GetBoneIndex = E.mesh.GetBoneIndex,
  IsSimulatingPhysics = function() return true end,
  GetNumMaterials = function() return 0 end,
})
local cls = 'CH_M_NA_26_Blueprint_C'
local enemy = F.obj('Target', cls, { Mesh = mesh, bActorIsBeingDestroyed = false, bHidden = false })
local ctx = T.ctx
local owner = enemy:GetAddress()
ctx.live_chars = function() return {{ obj = enemy, addr = owner, cls = cls, k = ctx.keep(enemy) }} end
ctx.tune.enemies.cutChance = 1
ctx.enemies.tick(pawn, E.mesh)
local _, opening = G.enemy_cuts(owner)
check(opening, 'an enemy kill starts a staged cut')
enemy.Mesh = F.obj('ReplacementMesh', 'SkeletalMeshComponent')
mesh.__dead, mesh.__freed = true, true
G.pump_once()
check(not G.busy(), 'the scheduler drops the old cut when the enemy mesh is replaced')
check(#F.errors == 0, 'the scheduler never asks the freed enemy mesh if it is valid')
F.say(fails == 0 and 'PASS' or 'FAIL')
