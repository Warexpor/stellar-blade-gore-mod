-- one killing swing through both arms and her body (gore.blow, a level blade at her right upper arm): with
-- gore.followUpCuts on, the arm it met, then her body and the other arm; off, her body alone (one cut a swing)
local F = require("fake")
local E = require("eve")
local R = require("rag")
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local ON = rawget(_G, "FOLLOW_UP") ~= false
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write(string.format([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.gore.followUpCuts = %s
s.gore.bladeJitter = 0
s.gore.bladeShift = 0
return s
]], tostring(ON)))
f:close()
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.k = "ok collapsed 2"
R.install(F, E)
F.world = R.step
-- main.lua's own gore.lua, caught as it is loaded
local gore
local dofile0 = dofile
dofile = function(p, ...)
  local r = dofile0(p, ...)
  if type(p) == "string" and p:find("gore%.lua$") then gore = r end
  return r
end
local ok, err = pcall(dofile, DIR .. "main.lua")
dofile = dofile0
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
check(gore ~= nil, "gore.lua caught")
if not gore then print("FAIL"); return end
local tune = gore.cfg and gore.cfg() or nil
local from = #F.cmds + 1
-- a death's blade, level, not turned (bladeJitter 0)
local a, b = E.bone("Bip001-R-UpperArm"), E.bone("Bip001-R-Forearm")
local s1, s2 = E.bone("Bip001-Spine1"), E.bone("Bip001-Spine2")
local z = (s1.Z + s2.Z) / 2
local loc = { X = a.X, Y = a.Y, Z = z }
local okb, r = pcall(gore.blow, pawn, E.mesh, { t = os.clock(), loc = loc, n = { X = 0, Y = 0, Z = 1 } }, "death")
check(okb, "the blow ran (" .. tostring(r) .. ")")
F.run(4, pawn)
local cuts = 0
for i = from, #F.cmds do if F.cmds[i].s:sub(1, 1) == "c" then cuts = cuts + 1 end end
for _, x in ipairs(F.log_lines()) do if x:find("blade %(") then print("  | " .. x:sub(1, 240)) end end
if ON then
  check(cuts >= 2, string.format("on: more than one cut (%d)", cuts))
else
  check(cuts == 1, string.format("off: one cut (%d)", cuts))
  check(F.find("alone %(followUpCuts off%)") or F.find("more left whole: followUpCuts off"), "off: her body alone, the rest whole")
end
for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
