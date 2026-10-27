-- The whole mod run through in one go, for errors: the scripts load with the shipped settings (sim_keys.lua: with
-- Developer Keys and Lose Arm at Low HP, SIM_DEV), the F3 key pressed (the menu itself needs the game's UI: it says
-- it couldn't be made), twelve deaths of every kind the odds roll (seeded, each one respawned), a fall death; with
-- SIM_DEV every key of the mod pressed alive (keys.lua's actions, on their default keys) and a camp rest. What fails is
-- any hook or tick error, any "failed"/"error" line in the mod's log, a death that never started or whose screen was
-- never shown, and a respawn that left her ragdolled. The engine isn't here (the fake answers nothing it doesn't
-- know), so "could not load" and the fake sbslice's unanswered commands are not counted
local F = require("fake")
local E = require("eve")
local R = require("rag")
math.randomseed(11)
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local function settings(dev)
  local f = assert(io.open(DIR .. "settings.lua", "w"))
  f:write(string.format([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = %s
s.gore.lowArm.enabled = %s
return s
]], tostring(dev), tostring(dev)))
  f:close()
end
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"
R.install(F, E)
F.world = R.step

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function mark() return #F.log_lines() + 1 end
local IGNORE = { "could not load", "no answer for", "didn't load", "no game instance" }
local function bad_lines(from)
  local out, seen = {}, {}
  for i, x in ipairs(F.log_lines()) do
    if i >= from and (x:find("[Ff]ailed") or x:find("[Ee]rror") or x:find("attempt to")) then
      local skip = false
      for _, p in ipairs(IGNORE) do if x:find(p, 1, true) then skip = true end end
      local k = x:gsub("^%[[^%]]*%] ", ""):gsub("%x%x%x%x%x%x%x%x+", "#")
      if not skip and not seen[k] then seen[k] = true; out[#out + 1] = x end
    end
  end
  return out
end
local function screen_hidden() local w = E.deadScreen and E.deadScreen.__w; return w and (w.vis == 1 or w.vis == 2) end

local DEV = SIM_DEV == true
settings(DEV)
local ok, err = pcall(dofile, DIR .. "main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)
check(F.find("tick error") == nil and #F.errors == 0, DEV and "loads and runs with Developer Keys" or "loads and runs with the shipped settings")
-- the menu, opened and shut
check(F.press("F3", ""), "F3 bound")
F.run(1, pawn)
F.press("F3", "")
F.run(1, pawn)

-- twelve deaths, each respawned
local started, shown, stood = 0, 0, 0
for i = 1, 12 do
  local d0 = mark()
  E.s.hp = 0
  E.die(true)
  F.run(4, pawn)
  if F.find("ragdoll state at start", d0) then started = started + 1 end
  local early = screen_hidden()
  F.run(8, pawn)
  if early and not screen_hidden() then shown = shown + 1 end
  E.respawn()
  F.run(3, pawn)
  -- (her bodies off again once she is up)
  if not E.s.sim then stood = stood + 1 end
end
check(started == 12, string.format("12 deaths, %d started the mod's death", started))
check(shown == 12, string.format("the death screen held hidden then shown in %d of 12", shown))
check(stood == 12, string.format("she was up, not ragdolled, after %d of 12 respawns", stood))
local cuts = {}
for _, x in ipairs(F.log_lines()) do
  local b = x:match("gore: cut (Bip001%-[%w%-]+) %(death%)")
  if b then cuts[b] = (cuts[b] or 0) + 1 end
end
local cs = {}
for b, n in pairs(cuts) do cs[#cs + 1] = b .. " x" .. n end
table.sort(cs)
print("  (death cuts: " .. (#cs > 0 and table.concat(cs, ", ") or "none") .. ")")
check(#cs > 0, "deaths cut her")

-- a fall death
local d0 = mark()
E.fall(1600, 1.8, 0, false)
F.run(12, pawn)
check(F.find("ragdoll state at start", d0) ~= nil, "a 16 m fall death is the mod's ragdoll")
E.respawn()
F.run(3, pawn)

-- every key of the mod pressed alive (Developer Keys)
if DEV then
local K = dofile(DIR .. "keys.lua")
local pressed, missing = 0, {}
for _, a in ipairs(K.ACTIONS) do
  if a.id ~= "menu" then
    local def = a.def
    local mods, key = {}, def
    for m in def:gmatch("(%a+)%+") do mods[#mods + 1] = K.MOD_KEY[m] end
    key = def:match("([^+]+)$")
    if F.press(key, table.concat(mods, "+")) then pressed = pressed + 1 else missing[#missing + 1] = a.id .. " (" .. def .. ")" end
    F.run(3, pawn)
    -- (the glass cannon, a toggle: off again)
    if a.id == "glass" then F.press(key, table.concat(mods, "+")); F.run(0.5, pawn) end
    -- (back on her feet: Test: Get Up, then a respawn if she died)
    F.press("F8", "")
    F.run(1, pawn)
    if E.s.dead or E.s.sim then E.respawn(); F.run(3, pawn) end
  end
end
check(#missing == 0, string.format("%d keys pressed%s", pressed, #missing > 0 and (", unbound: " .. table.concat(missing, ", ")) or ""))

-- a camp rest with an arm off (well after the last respawn: the respawn's own put-backs, a150-a630, give the arm back)
F.run(12, pawn)
E.s.hp = 0.3
F.press("F8", "ALT")
F.run(2, pawn)
local seq = F.obj("Interaction_Camp_Chair", "LevelSequence", {
  GetFullName = function() return "LevelSequence /Game/Sequence/Interaction_Camp_Chair.Interaction_Camp_Chair" end,
})
local player = F.obj("SequencePlayer", "LevelSequencePlayer", { IsPlaying = function() return true end, GetSequence = function() return seq end })
F.classes.LevelSequenceActor = { F.obj("Interaction_Camp_Chair_Actor", "LevelSequenceActor", { SequencePlayer = player }) }
local r0 = mark()
E.s.mode = 0
F.run(10, pawn)
check(F.find("regrow: a camp rest", r0) ~= nil, "a camp rest brings the arm back")
F.classes.LevelSequenceActor = nil
E.s.mode = 1
F.run(2, pawn)
end

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no hook or tick errors")
local bad = bad_lines(1)
for _, x in ipairs(bad) do print("  ! " .. x:sub(1, 260)) end
check(#bad == 0, string.format("no failure lines in the log (%d)", #bad))
print(fails == 0 and "PASS" or "FAIL")
