-- Fall damage deaths (main.lua hm.lethal_watch, hm.take). From 16 m the game's death show gave no ragdoll in two
-- playtests: the mod takes the death over (`death: taken over`), ragdolls her and holds the death screen hidden. The
-- controls: the show's ragdoll key working (the mod's own death as ever, no takeover); a medium fall leaving her at
-- 1 HP (the bar reads 0, no death screen: nothing); a death while swimming with no ragdoll (not taken over, named)
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
local ok, err = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
-- the mod starts 10 s after her start, then needs a moment (sbslice's handshake, its tables)
F.run(16, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function mark() return #F.log_lines() + 1 end
local function dump(from, pat)
  for i, x in ipairs(F.log_lines()) do if i >= from and (not pat or x:find(pat)) then print("  | " .. x) end end
end
local function screen_hidden() local w = E.deadScreen.__w; return w.vis == 1 or w.vis == 2 end
local function next_life() F.run(14, pawn); E.respawn(); F.run(6, pawn) end

-- 1: the 16 m drop, no ragdoll from the game
local at = mark()
E.fall(1600, 1.8, 0, false)
F.run(0.5, pawn)
local l = F.find("death: taken over", at)
check(l ~= nil, "16 m fall, no ragdoll from its show: taken over")
check(E.s.sim, "her bodies simulate")
check(F.find("ragdoll state at start", at) ~= nil, "the mod's death started")
F.run(3, pawn)
check(screen_hidden(), "the death screen held hidden 3 s in")
F.run(7.5, pawn)
check(not screen_hidden(), "the death screen shown at 10 s")
check(not F.find("death NOT seen", at), "no 'death NOT seen'")
if fails > 0 then dump(at, "death") end
next_life()

-- 2: the same drop, the show's ragdoll key working
at = mark()
E.fall(1600, 1.8, 0, true)
F.run(1, pawn)
check(F.find("ragdoll state at start", at) ~= nil, "16 m fall, its show's ragdoll working: the mod's death")
check(not F.find("taken over", at), "not taken over")
check(screen_hidden(), "the death screen held hidden")
next_life()

-- 3: a medium fall, 1 HP left (the bar reads 0.000)
at = mark()
E.fall(600, 1.1, 0.0004, nil)
F.run(3, pawn)
check(not F.find("taken over", at) and not F.find("ragdoll state at start", at), "a 6 m fall at 1 HP: no death, no takeover")
check(not E.s.sim, "she isn't ragdolled")
E.s.hp = 0.5
F.run(1, pawn)

-- 4: a death while swimming, no ragdoll from its show
at = mark()
E.s.mode, E.s.hp = 4, 0
F.run(0.2, pawn)
E.die(false)
F.run(1, pawn)
check(not F.find("taken over", at), "a swimming death: not taken over")
check(F.find("death NOT seen.*swimming", at) ~= nil, "named in the log (death NOT seen ..., swimming)")
next_life()

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
print(fails == 0 and "PASS" or "FAIL")
