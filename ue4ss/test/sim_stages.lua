-- a cut's stages in fewer frames (tune.gore.stageBudgetMs): the cut, then its caps, stubs and opening a frame each,
-- the piece came off 32-63 ms after the blow (playtest). The cut keeps a frame of its own; the stages after it go on
-- in one frame while they are quick. With the budget 0, a stage a frame as before
local F = require("fake")
local E = require("eve")
local R = require("rag")
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local BUDGET = rawget(_G, "STAGE_BUDGET")
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write(string.format([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.gore = s.gore or {}
s.gore.lowArm = s.gore.lowArm or {}
s.gore.lowArm.enabled = true
%s
return s
]], BUDGET and ("s.gore.stageBudgetMs = " .. BUDGET) or ""))
f:close()
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.k = "ok collapsed 2"
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

-- her arm off alive (Alt+F8, Lose Arm at Low HP's key): the frames from the cut ("c") to its opening ("k")
E.s.hp = 0.3
F.run(0.5, pawn)
local from = #F.cmds + 1
F.press("F8", "ALT")
F.run(3, pawn)
local cf, kf
for i = from, #F.cmds do
  local c = F.cmds[i]
  if not cf and c.s:sub(1, 1) == "c" then cf = c.frame end
  if cf and not kf and c.s:sub(1, 1) == "k" then kf = c.frame end
end
check(cf ~= nil and kf ~= nil, string.format("cut and opened (frames %s, %s)", tostring(cf), tostring(kf)))
local gap = cf and kf and kf - cf or -1
if BUDGET == 0 then
  check(gap >= 5, string.format("a stage a frame: opened %d frames after the cut", gap))
else
  check(gap >= 1 and gap <= 2, string.format("opened %d frame(s) after the cut, the cut in a frame of its own", gap))
end
check(F.find("Bip001%-%a%-UpperArm off %(low HP%)") ~= nil, "the arm came off")

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
