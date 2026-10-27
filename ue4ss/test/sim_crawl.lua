-- Crawling and pushing along the floor (struggle.lua's drag): her strokes only turn her limbs against her body, and in
-- game they swept the air while she stayed put (playtest), so a hand or foot planted and pulling speeds her torso
-- along the floor towards her head. The made-up ragdoll (rag.lua) doesn't move bodies by linear velocity, so what is
-- added to each is summed (R.lin): her torso's must point headward, along the floor.
-- Crawl: face down (rag.lua's faceDown), her right arm off alive (Alt+F8), a leg off at her death, only crawling
-- picked. Push (sim_push.lua, PUSH set): on her back, her right arm off alive and her left at her death (only one
-- comes off alive), heels shoving her
local PUSH = rawget(_G, "PUSH") == true
local F = require("fake")
local E = require("eve")
local R = require("rag")
-- (seeds whose death cut takes a leg for the crawl, her left arm for the push)
math.randomseed(rawget(_G, "SEED") or (PUSH and 2 or 1))
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.deathMoves = true
s.gore = s.gore or {}
s.gore.lowArm = s.gore.lowArm or {}
s.gore.lowArm.enabled = true
s.gore.death = { limb = 100, head = 0, torso = 0, split = 0, moreLimbs = 0 }
s.struggle = s.struggle or {}
s.struggle.weights = { clutch = 0, reach = 0, turn = 0, crawl = 3, rise = 0, prop = 0, push = 3, curl = 0, lie = 0 }
return s
]])
f:close()
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"
R.install(F, E, { faceDown = not PUSH })
F.world = R.step
local ok, err = pcall(dofile, DIR .. "main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function mark() return #F.log_lines() + 1 end
local function lines(from, pat)
  local out = {}
  for i, x in ipairs(F.log_lines()) do if i >= from and x:find(pat) then out[#out + 1] = x end end
  return out
end

E.s.hp = 0.3
F.run(0.5, pawn)
F.press("F8", "ALT")
F.run(3, pawn)

local d0 = mark()
E.s.hp = 0
E.die(true)
F.run(18, pawn)
local sg = lines(d0, "struggle: ")
for _, x in ipairs(sg) do print("  | " .. x:sub(1, 200)) end
local act = PUSH and "pushes, her pelvis moved" or "crawl over"
local held, n = 0, 0
for _, x in ipairs(sg) do
  if x:find(act, 1, true) then
    n = n + 1
    held = held + (tonumber(x:match("%((%a+) for ([%d.]+) s%)") and x:match("for ([%d.]+) s%)")) or 0)
  end
end
check(n > 0, string.format("%s: %d played out", PUSH and "pushing" or "crawling", n))
check(held > 0.2, string.format("a limb planted and %s for %.1f s in all", PUSH and "driving" or "pulling", held))
-- (headward: +X, her head's way as she lies; along the floor: no up or down in it)
local sum = { X = 0, Y = 0, Z = 0 }
for _, b in ipairs({ "Bip001-Pelvis", "Bip001-Spine", "Bip001-Spine1", "Bip001-Spine2" }) do
  local v = R.lin[b]
  if v then sum.X, sum.Y, sum.Z = sum.X + v.X, sum.Y + v.Y, sum.Z + v.Z end
end
print(string.format("  (velocity added to her torso's bodies in all: %.0f, %.0f, %.0f cm/s)", sum.X, sum.Y, sum.Z))
check(sum.X > 50 and math.abs(sum.Z) < sum.X / 4, "her torso sped headward along the floor")
for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
