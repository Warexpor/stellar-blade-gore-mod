-- A maimed Eve's struggle on the floor (struggle.lua, F3's Death Struggle, deathMoves: on by default, set here too). Her right arm
-- comes off alive (Lose Arm at Low HP's test key, Alt+F8), then she dies a ragdoll. On the made-up ragdoll (rag.lua:
-- joints that turn, no gravity, floor or limits) the struggle's acts must start, steer her joints towards their
-- targets and keep most of each turn they set (in game the log said 0% kept: there the engine or something of the
-- mod's undid them; here nothing else should), and end with her death. What active.lua's settling does to her
-- turns meanwhile is counted (every zeroing of them all is an event)
-- (sim_waist.lua runs it with WAIST_CUT set: her death cuts her across the waist, and her upper body struggles)
local WAIST = rawget(_G, "WAIST_CUT") == true
local F = require("fake")
local E = require("eve")
local R = require("rag")
math.randomseed(7)
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
-- Death Struggle on (settings.lua's deathMoves, F3 -> Death; on by default)
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write(string.format([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.deathMoves = true
s.gore = s.gore or {}
s.gore.lowArm = s.gore.lowArm or {}
s.gore.lowArm.enabled = true
-- (a stage a frame, as the seeds were picked: chained stages roll the dice in another order)
s.gore.stageBudgetMs = 0
-- (her death takes a limb, not her head or body: the struggle needs her whole; or her waist, WAIST_CUT)
s.gore.death = { limb = %d, head = 0, torso = %d, split = 0, moreLimbs = 0 }
return s
]], WAIST and 0 or 100, WAIST and 100 or 0))
f:close()
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"
R.install(F, E)
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

local at = mark()
E.s.hp = 0.3
F.run(0.5, pawn)
check(F.press("F8", "ALT"), "Alt+F8 bound")
F.run(3, pawn)
check(F.find("her right arm cut off", at) ~= nil, "Alt+F8: her right arm cut off")
local hand0 = R.P["Bip001-L-Hand"]

-- her death, a ragdoll
local d0 = mark()
local e0 = #F.events
-- (its rolls from here on a seed of their own: how many the cut's stages drew before it doesn't change the struggle;
-- re-picked as the death face took more rolls: on 1 a short struggle had time for one act only)
math.randomseed(rawget(_G, "STRUGGLE_SEED") or 10)
E.s.hp = 0
E.die(true)
F.run(18, pawn)
local sg = lines(d0, "struggle: ")
for _, x in ipairs(sg) do print("  | " .. x:sub(1, 230)) end
if WAIST then
  check(F.find("struggle: stumps: waist, right shoulder, left arm and 0 legs on", d0) ~= nil,
    "the struggle began on her upper body: the waist first, her right arm's stump, her left arm, no legs")
  for _, x in ipairs(sg) do
    local a = x:match("struggle: [%d.]+ s: (%a+)")
    if a == "trying" or a == "propping" or a == "pushing" then check(false, "no sitting up or pushing on a waist cut: " .. x) end
  end
else
  check(F.find("struggle: stumps: .*right", d0) ~= nil, "the struggle began, her right arm's stump seen")
end
local acts, kept, off = 0, {}, {}
for _, x in ipairs(sg) do
  if x:find(" over: ") then
    acts = acts + 1
    local o, k = x:match("joints off by (%-?%d+) deg on average, (%-?%d+)%% of each turn kept")
    if k then kept[#kept + 1], off[#off + 1] = tonumber(k), tonumber(o) end
  end
end
check(acts >= 2, string.format("%d acts played out", acts))
check(#kept > 0, string.format("%d acts steered her joints", #kept))
local sum = 0
for _, k in ipairs(kept) do sum = sum + k end
local mean = #kept > 0 and sum / #kept or -1
check(mean >= 50, string.format("most of each turn kept on a ragdoll nothing else moves (%.0f%% on average)", mean))
local tops = {}
for b, w in pairs(R.top) do if w > 360 then tops[#tops + 1] = string.format("%s %.0f", b, w) end end
table.sort(tops)
print("  (turns set over 360 deg/s: " .. (#tops > 0 and table.concat(tops, ", ") or "none") .. ")")
local mv = R.P["Bip001-L-Hand"] and hand0 and math.sqrt((R.P["Bip001-L-Hand"].X - hand0.X) ^ 2 + (R.P["Bip001-L-Hand"].Y - hand0.Y) ^ 2 + (R.P["Bip001-L-Hand"].Z - hand0.Z) ^ 2)
check(F.find("struggle: over after", d0) ~= nil, "the struggle ran to its end")
check(F.find("struggle: .*dying", d0) ~= nil, "she died at its end (last tremors)")
check(not F.find("turning a body failed", d0), "no body push failed")
local z = 0
for i = e0 + 1, #F.events do if F.events[i].what == "her bodies' turns all zeroed" then z = z + 1 end end
print(string.format("  (her turns all zeroed %d times during the death; %d turns set, %d on a body asleep; her left hand moved %.0f cm)",
  z, R.sets, R.sleptSets, mv or -1))
check(R.sleptSets == 0 or R.sleptSets < R.sets / 10, "turns hardly ever set on a sleeping body")
for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
