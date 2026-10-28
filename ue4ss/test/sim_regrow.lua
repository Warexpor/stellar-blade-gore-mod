-- A camp rest bringing back her right arm (Lose Arm at Low HP's test key, Alt+F8): it dissolves back in on a copy of
-- her mesh, then the hand-off (main.lua hm.ghost_tick, gore.ghost_release): the cut undone under the copy, which
-- fades out over her for dissolve.fade s. The copy's hidden side sits on the cut's collapsed sinks (sbslice "V"), so
-- the sinks' put back (sbslice "r") must wait till the copy is destroyed (gore.ghost_end): before, her whole body
-- showed round the arm on the fading copy (playtest; test/run.sh unit in native/sbslice shows the mechanism)
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
-- Developer Keys and Lose Arm at Low HP on
local SET = "ue4ss/Mods/StellarBladeGore/Scripts/settings.lua"
local f = assert(io.open(SET, "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.gore = s.gore or {}
s.gore.lowArm = s.gore.lowArm or {}
s.gore.lowArm.enabled = true
return s
]])
f:close()
-- the cut's answers, as the game's log showed them (sbslice "c", a stage's "C", the photo shield "f")
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"
local ok, err = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function mark() return #F.log_lines() + 1 end
local function dump(from, pat)
  for i, x in ipairs(F.log_lines()) do if i >= from and (not pat or x:find(pat)) then print("  | " .. x:sub(1, 240)) end end
end

local at = mark()
E.s.hp = 0.3
F.run(0.5, pawn)
check(F.press("F8", "ALT"), "Alt+F8 bound")
F.run(3, pawn)
check(F.find("her right arm cut off", at) ~= nil, "Alt+F8: her right arm cut off")

-- the camp rest: she sits (movement none), the camp chair's sequence plays, 5 s later the rest's restore
local seqPlaying = true
local seq = F.obj("Interaction_Camp_Chair", "LevelSequence", {
  GetFullName = function() return "LevelSequence /Game/Sequence/Interaction_Camp_Chair.Interaction_Camp_Chair" end,
})
local player = F.obj("SequencePlayer", "LevelSequencePlayer", {
  IsPlaying = function() return seqPlaying end,
  GetSequence = function() return seq end,
})
local actor = F.obj("Interaction_Camp_Chair_Actor", "LevelSequenceActor", { SequencePlayer = player })
F.classes.LevelSequenceActor = { actor }
local rest = mark()
E.s.mode = 0
F.run(6, pawn)
check(F.find("regrow: a camp rest", rest) ~= nil, "a camp rest seen at the chair")
local l = F.find("dissolving back in over", rest)
check(l ~= nil, "the arm dissolving back in")
if not l then dump(rest, "regrow") end
-- the dissolve, then the hand-off's fade, sampled each frame on the copy's first material
local e0 = #F.events
local copy = E.added[#E.added]
-- (on her as she walks: only placed where her mesh was, it stood there while she walked off, reported)
check(copy and copy.parent == E.mesh and copy.attachRules[1] == 2, "the copy attached to her mesh, snapped onto it")
local samples = {}
for _ = 1, 4 * 60 do
  F.step(1 / 60, pawn)
  local p = copy and copy.mids[1] and copy.mids[1].p or {}
  samples[#samples + 1] = { t = F.t, d = p.Dissolve, m = p.Morph, g = p.EmissiveBright, dead = copy and copy.__dead }
end
check(F.find("dissolved in after", rest) ~= nil, "dissolved in")
-- the order: the cut undone under the copy (sbslice "x", her weights), the copy destroyed, then the sinks back ("r")
local undo, gone, rs = nil, nil, {}
for i = e0 + 1, #F.events do
  local w = F.events[i].what
  if not undo and w:find("^sbslice x") then undo = i end
  if not gone and w == copy.__name .. " destroyed" then gone = i end
  if w:find("^sbslice r") then rs[#rs + 1] = i end
end
-- (the copy on its own weights: her cut's copied onto it, "y", left the arm standing off her shoulder, playtest)
local ys = 0
for i = e0 + 1, #F.events do if F.events[i].what:find("^sbslice y") then ys = ys + 1 end end
for _, x in ipairs(F.log_lines()) do if x:find("dissolving back in on a copy") and x:find("weights on the copy") then ys = ys + 1 end end
check(ys == 0, "her cut's weights not copied onto the copy")
check(undo ~= nil, "the cut undone under the copy (sbslice x)")
check(gone ~= nil, "the copy destroyed")
check(#rs > 0, "the sinks put back (sbslice r)")
local early = 0
for _, i in ipairs(rs) do if not gone or i < gone then early = early + 1 end end
check(early == 0, string.format("no sinks put back while the copy is there (%d early)", early))
if undo and gone then
  check(F.events[gone].t - F.events[undo].t > 0.5, string.format("the copy fades %.2f s over her own arm", F.events[gone].t - F.events[undo].t))
end
-- the fade: its Dissolve back up 0 -> 1, no ripple, no glow; before it, the dissolve in (Dissolve 1 -> 0)
local fade, ripple, mono = 0, 0, true
local last
for _, x in ipairs(samples) do
  if undo and x.t >= F.events[undo].t and not x.dead and x.d then
    fade = fade + 1
    if (x.m or 0) > 0.001 or (x.g or 0) > 0.001 then ripple = ripple + 1 end
    if last and x.d < last - 1e-6 then mono = false end
    last = x.d
  end
end
check(fade >= 30, string.format("%d frames of fade", fade))
check(ripple == 0, "no ripple or glow in the fade")
check(mono, "its Dissolve only rises")
if fails > 0 then
  for i = e0 + 1, #F.events do print(string.format("  %.3f %s", F.events[i].t, F.events[i].what)) end
  dump(rest, "regrow")
end
print(fails == 0 and "PASS" or "FAIL")
