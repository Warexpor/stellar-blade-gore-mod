local F, E = require("fake"), require("eve")
local pawn = E.make(F)
local out = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write('local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")\n' ..
  's.deathScreen = "delay"\ns.reviveAt = 4\ns.deathMoves = false\ns.convulse = s.convulse or {}\ns.convulse.enabled = false\nreturn s\n')
f:close()
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"
local R = require("rag")
R.install(F, E); F.world = R.step
assert(pcall(dofile, DIR .. "main.lua"))
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil)); F.run(16, pawn)
local fails = 0
local function check(c, message) out((c and "ok   " or "FAIL ") .. message); if not c then fails = fails + 1 end end
E.s.hp = 0; F.run(0.2, pawn)
local diedAt = os.clock()
E.die(true)
while os.clock() - diedAt < 0.5 do F.run(0.2, pawn) end
check(F.find("held hidden") ~= nil, "the death screen is held hidden at once")
local w = E.deadScreen
check(w ~= nil, "the death screen widget exists")
local visReads = 0
local ww = w.__w
rawset(w, "GetVisibility", function() visReads = visReads + 1; return ww.vis end)
-- The steady hold is about a second into the death; with reviveAt 4 it lasts till about 3.5 s in.
while os.clock() - diedAt < 1.2 do F.run(0.2, pawn) end
local c1, t1 = visReads, os.clock()
while os.clock() - diedAt < 3.2 do F.run(0.2, pawn) end
check(F.find("death perf: .*pawn ticks/s, mod .*ms/tick") ~= nil,
  "short death windows report pawn tick rate and mod cost")
local c2, t2 = visReads, os.clock()
local polls = math.floor((t2 - t1) / 0.033 + 0.5)
if polls >= 40 then
  check(c2 - c1 >= math.floor(polls * 0.8),
    string.format("the steady hold checks every poll (%d reads over ~%d polls)", c2 - c1, polls))
else
  check(false, string.format("too few polls to judge cadence (~%d)", polls))
end
-- The hold ends on time: the screen comes up at reviveAt, not late.
local shown, guard = F.find("revive screen: shown"), 0
while not shown and guard < 60 do F.run(0.5, pawn); guard = guard + 1; shown = F.find("revive screen: shown") end
check(shown ~= nil, "the held screen is shown after reviveAt")
if shown then
  local t = tonumber(shown:match("shown (%d+%.?%d*) s"))
  check(t and t >= 3.9 and t <= 5.5, string.format("the screen comes up on time (%.1f s into the death)", t or -1))
end
for _, e in ipairs(F.errors) do out("hook error: " .. e) end
local te = F.find("tick error")
if te then out("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
out(fails == 0 and "PASS" or "FAIL")
