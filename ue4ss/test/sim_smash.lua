-- Real smash stages, collision/flight contracts, multipart hiding, recovery, failures and repeat deaths.
local T = require("smash_world").boot('s.gore.smash = { enabled = true, always = true }\ns.gore.blood = false\ns.gore.torsoLegs = { enabled = false }')
local F, E, G, pawn, W, v = T.F, T.E, T.G, T.pawn, T.world, T.v
local print, fails = F.say, 0
local function run(seconds)
  for _ = 1, math.floor(seconds * 60 + 0.5) do F.step(1/60); G.tick(pawn); G.pump() end
end
local function check(c, what) print((c and "ok   " or "FAIL ") .. what); if not c then fails = fails + 1 end end
local function live() local n = 0; for _, a in ipairs(W.actors) do if not a.__dead then n = n + 1 end end; return n end
local function midpoint(a, b) a, b = E.bone(a), E.bone(b); return v((a.X+b.X)/2, (a.Y+b.Y)/2, (a.Z+b.Z)/2) end
local tune = T.ctx.tune.gore
math.randomseed(1337)
-- Geometry: all ten supported bones, including both lower limbs and the top of the skull.
local cases = {
  { "Bip001-L-UpperArm", "Bip001-L-Forearm", 10 }, { "Bip001-R-UpperArm", "Bip001-R-Forearm", 10 },
  { "Bip001-L-Forearm", "Bip001-L-Hand", 6 }, { "Bip001-R-Forearm", "Bip001-R-Hand", 6 },
  { "Bip001-L-Thigh", "Bip001-L-Calf", 16 }, { "Bip001-R-Thigh", "Bip001-R-Calf", 16 },
  { "Bip001-L-Calf", "Bip001-L-Foot", 10 }, { "Bip001-R-Calf", "Bip001-R-Foot", 10 },
  { "Bip001-Head", "Bip001-HeadNub", 8 }, { "Bip001-Spine1", "Bip001-Spine2", 44 },
}
for _, c in ipairs(cases) do
  local at = midpoint(c[1], c[2])
  local b = G.smash_part(E.mesh, at)
  check(b == c[1], c[1] .. ": hit selects its own part (" .. tostring(b) .. ")")
  E.s.sim = true
  local n0 = #W.spheres
  G.aim(v(1, 0, 0))
  check(G.smash(pawn, E.mesh, { loc = at }, "death"), c[1] .. ": smash starts")
  run(0.6)
  check(E.hiddenBones[c[1]] == true, c[1] .. ": removed piece hidden")
  check(#W.spheres - n0 == c[3], c[1] .. ": expected chunk count")
  local k = c[1]:find("Forearm") and 0.9 or c[1]:find("Thigh") and 1.15 or c[1]:find("Calf") and 1.05 or c[1]:find("Spine") and 1.25 or 1
  local sized = true
  for i = n0 + 1, #W.spheres do
    local box = W.spheres[i]
    sized = sized and math.abs(box.extent.Y / box.extent.X - 0.5) < 0.001 and math.abs(box.extent.Z / box.extent.X - 0.4) < 0.001 and box.angularDamping == 3
    local cm = box.radius / 0.425
    sized = sized and cm >= 7 * k - 0.001 and cm <= 14 * k + 0.001
  end
  check(sized, c[1] .. ": larger meat sized to the body part")
  check(#G.cut_parts(E.mesh) == 0, c[1] .. ": no severed piece left for photo/settling")
  if c[1] == "Bip001-Spine1" then
    check(G.already_cut(E.mesh, "Bip001-L-UpperArm") and G.already_cut(E.mesh, "Bip001-Head"), "torso: head and arms cannot be cut again")
    check(not G.already_cut(E.mesh, "Bip001-L-Thigh"), "torso: legs remain available")
  end
  run(4)
  local settled = true
  for i = n0 + 1, #W.spheres do local sp = W.spheres[i]; settled = settled and sp.at.Z >= sp.radius - 0.001 and sp.at.Z < sp.radius + 1 end
  check(settled, c[1] .. ": chunks land and settle above the floor")
  G.cleanup(pawn, E.mesh)
  run(0.2)
  check(live() == 0 and next(E.hiddenBones) == nil, c[1] .. ": recovery destroys chunks and restores bones")
end
-- A large impact's reported point can be outside the skin and slightly closer to an arm's centre line.
-- It should still reach the broader head/chest; a direct limb hit remains a limb hit.
local head, arm = E.bone("Bip001-HeadNub"), midpoint("Bip001-L-UpperArm", "Bip001-L-Forearm")
local chest = E.bone("Bip001-Spine2")
local function between(a, b, t) return v(a.X + (b.X-a.X)*t, a.Y + (b.Y-a.Y)*t, a.Z + (b.Z-a.Z)*t) end
local pickedHead, _, _, headDistances = G.smash_part(E.mesh, between(head, arm, 0.55))
check(pickedHead == "Bip001-Head", "near face and arm: head surface takes priority (" .. tostring(pickedHead) .. "; " .. tostring(headDistances) .. ")")
check(G.smash_part(E.mesh, between(chest, arm, 0.55)) == "Bip001-Spine1", "near chest and arm: torso surface takes priority")
check(G.smash_part(E.mesh, arm) == "Bip001-L-UpperArm", "direct arm impact stays on the arm")
-- Missing flesh must not be emitted twice when a later smash takes the parent part.
for _, c in ipairs({
  { "Bip001-L-Forearm", "Bip001-L-Hand", "Bip001-L-UpperArm", "Bip001-L-Forearm", 4 },
  { "Bip001-L-Calf", "Bip001-L-Foot", "Bip001-L-Thigh", "Bip001-L-Calf", 6 },
}) do
  G.smash(pawn, E.mesh, { loc = midpoint(c[1], c[2]) }, "test"); run(0.6)
  local n0 = #W.spheres
  G.smash(pawn, E.mesh, { loc = midpoint(c[3], c[4]) }, "test"); run(0.6)
  check(#W.spheres - n0 == c[5], "parent smash excludes the already missing " .. c[1])
  G.cleanup(pawn, E.mesh)
end
-- A whole arm cut off normally takes its forearm too; the torso must exclude both.
G.slice_bone(pawn, E.mesh, "Bip001-L-UpperArm", nil, "test"); run(0.6)
G.smash(pawn, E.mesh, { loc = midpoint("Bip001-Head", "Bip001-HeadNub") }, "test"); run(0.6)
local n0 = #W.spheres
G.smash(pawn, E.mesh, { loc = midpoint("Bip001-Spine1", "Bip001-Spine2") }, "test"); run(0.8)
check(#W.spheres - n0 == 22, "upper body excludes a severed arm and smashed head")
G.cleanup(pawn, E.mesh)
check(#W.violations == 0, "physics starts with world collision and no pawn/body collision")
-- Failed component construction must destroy the actor immediately, even before a cut exists.
local sm = F.objects[G.SMASH_MESHES[1]]
W.failClass = "BoxComponent"
local before = live()
check(G.smashed.chunk(pawn, E.mesh, v(1000, 2000, 120), v(100, 0, 0), 8, sm) == nil and live() == before,
  "missing box: no orphan actor")
W.failClass = nil
W.throwPhysics = true
check(G.smashed.chunk(pawn, E.mesh, v(1000, 2000, 120), v(100, 0, 0), 8, sm) == nil and live() == before,
  "physics exception: no orphan actor")
W.throwPhysics = nil
-- Collision type must not depend on a modded PhysicsActor profile.
W.profileType = 1
local sp = G.smashed.chunk(pawn, E.mesh, v(1000, 2000, 120), v(100, 0, 0), 8, sm)
check(sp and sp.objType == 5 and sp.resp[5] == 0, "chunk uses PhysicsBody even with a modified profile: chunks never collide with each other")
W.profileType = nil
G.cleanup(pawn, E.mesh)
-- A thrown cut must not leave the next ordinary cut flagged as a smash.
local slice = G.slice_bone
G.slice_bone = function() error("injected cut failure") end
pcall(G.smash, pawn, E.mesh, { loc = midpoint(cases[1][1], cases[1][2]) }, "death")
check(G.smash_once == nil, "cut exception clears smash flag")
G.slice_bone = slice
-- No-hit rolls exclude split odds, and zero weights must never get selected (even on the RNG boundary).
local death, random = tune.death, math.random
tune.death = { limb = 0, head = 0, torso = 100, split = 10000 }
math.random = function(n) return n and 1 or 0 end
check(G.smash_part(E.mesh) == "Bip001-Spine1", "RNG zero: zero-weight kinds never selected")
math.random, tune.death = random, death
local weights = { limb = 42, head = 25, torso = 15, split = 9000 }
tune.death = weights
local rolls = { limb = 0, head = 0, torso = 0 }
for _ = 1, 10000 do local _, _, kind = G.smash_part(E.mesh); rolls[kind] = rolls[kind] + 1 end
local close = true
for kind, n in pairs(rolls) do close = close and math.abs(n / 10000 - weights[kind] / 82) < 0.02 end
check(close, string.format("10000 no-hit rolls follow limb/head/torso weights, ignoring split (%d/%d/%d)", rolls.limb, rolls.head, rolls.torso))
tune.death = { limb = 0, head = 0, torso = 0, split = 100 }
check(G.smash_part(E.mesh) == nil, "no smash kinds weighted: no arbitrary part removed")
tune.death = death
local missing = F.obj("NoBones", "SkeletalMeshComponent", { GetBoneIndex = function() return -1 end })
check(G.smash_part(missing) == nil and G.smash_part(missing, v(0,0,0)) == nil, "missing skeleton never selects a nonexistent part")
for _, e in ipairs(F.errors) do print("FAIL hook: " .. e); fails = fails + 1 end
for _, l in ipairs(F.log_lines()) do
  if l:find("tick error") or l:find("smash failed") or l:find("delayed step failed") then print("FAIL log: " .. l); fails = fails + 1 end
end
print(fails == 0 and "PASS" or "FAIL")
