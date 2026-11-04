local T = require("smash_world").boot('s.gore.blood=false\ns.active.buzzLog=false\ns.active.settle={enabled=false}')
local F, E, ctx = T.F, T.E, T.ctx
local R = require("rag")
R.install(F, E)
local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local fails = 0
local function check(c, s) F.say((c and "ok   " or "FAIL ") .. s); if not c then fails = fails + 1 end end
local rag = ctx.rag
rag.start(T.pawn, E.mesh, "quiet")
E.s.sim = true -- her bodies simulate (E.die would set this on a real death)
-- Count the spin cap's own engine reads; writes are counted by the fake ragdoll (R.sets).
local reads = 0
local realAV = E.mesh.GetPhysicsAngularVelocityInDegrees
rawset(E.mesh, "GetPhysicsAngularVelocityInDegrees", function(self, b) reads = reads + 1; return realAV(self, b) end)
local function tick() rag.tick(1 / 30, function() end) end
local HAND = "Bip001-R-Hand"
-- Phase A: a spinning hand under full rate (the fall's first 2 s).
local setsA, readsA = R.sets, reads
for _ = 1, 40 do R.W[HAND] = vec(0, 0, 2000); tick() end
local writesA, windowA = R.sets - setsA, reads - readsA
check(writesA >= 30, string.format("a fast spin is capped every tick while young (%d writes over 40 ticks)", writesA))
-- Phase B: the spin stops; the cap goes quiet but keeps watching.
local setsB = R.sets
for _ = 1, 45 do tick() end
check(R.sets - setsB == 0, "nothing over the cap needs no writes")
local readsB = reads - readsA - windowA
local setsC = R.sets
for _ = 1, 30 do tick() end
local windowB = reads - readsA - windowA - readsB
check(R.sets - setsC == 0, "the quiet spell stays write-free")
check(windowB >= windowA * 0.7, string.format("quiet bodies are checked every tick (%d reads over 30 ticks vs %d over 40)", windowB, windowA))
local transient = 0
for _ = 1, 9 do
  local before = R.sets
  R.W[HAND] = vec(0, 0, 2000)
  tick()
  if R.sets > before then transient = transient + 1 end
  R.W[HAND] = vec(0, 0, 0)
  tick()
end
check(transient == 9, string.format("single-tick late spins are capped (%d of 9)", transient))
local setsD = R.sets
local firstCap = 0
for i = 1, 6 do R.W[HAND] = vec(0, 0, 2000); tick(); if firstCap == 0 and R.sets > setsD then firstCap = i end end
check(firstCap == 1, string.format("a renewed spin is capped on the first tick (tick %d)", firstCap))
local setsE = R.sets
for _ = 1, 10 do R.W[HAND] = vec(0, 0, 2000); tick() end
check(R.sets - setsE >= 8, string.format("clamping restores the full rate (%d writes over 10 ticks)", R.sets - setsE))
for _, e in ipairs(F.errors) do F.say("hook error: " .. e) end
check(#F.errors == 0, "no engine simulation errors")
F.say(fails == 0 and "PASS" or "FAIL")
