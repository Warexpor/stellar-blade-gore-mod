-- A level reload (a fast travel, a load) with her right arm cut off her alive (Lose Arm at Low HP, Alt+F8). The game
-- makes a new Eve wearing the same mesh asset; the cut's collapsed helper bones (sbslice's sinks: the asset's own
-- inverse bind matrices) outlive the old level, so they must be put back for that asset (sbslice "r<asset>") as the
-- old Eve is dropped, or the new one shows the arm gone with nothing cut. Her blocks (No Sword) and the cut's state
-- must be gone too
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.gore.lowArm.enabled = true
return s
]])
f:close()
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"
-- her outfit's mesh asset, the same on the new Eve
local ASSET = F.obj("SK_CH_P_EVE_01", "SkeletalMesh")
rawset(E.mesh, "SkeletalMesh", ASSET)
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

local at = mark()
E.s.hp = 0.3
F.run(0.5, pawn)
F.press("F8", "ALT")
F.run(3, pawn)
check(F.find("her right arm cut off", at) ~= nil, "Alt+F8: her right arm cut off")

-- the level reloads: the old Eve gone (no tick of hers again), a new one ticking
local c0 = #F.cmds
local old = pawn
pawn = E.make(F)
rawset(E.mesh, "SkeletalMesh", ASSET)
old.__dead = true
local r0 = mark()
F.run(3, pawn)
check(F.find("new Eve .* the level reloaded", r0) ~= nil, "the new Eve adopted")
local want = string.format("r%x", ASSET.__addr)
local put = false
for i = c0 + 1, #F.cmds do if F.cmds[i].s == want or F.cmds[i].s == "r" then put = true end end
check(put, "her cut's helper bones put back for her mesh asset (" .. want .. ")")
check(F.find("low HP arm: .*sword back", r0) ~= nil or F.find("low HP arm: the arm came back", r0) ~= nil, "the arm's blocks lifted")
-- (a later Alt+F8 cuts again: nothing left over says the arm is still off)
local a2 = mark()
F.press("F8", "ALT")
F.run(3, pawn)
check(F.find("her right arm cut off", a2) ~= nil, "Alt+F8 again on the new Eve: cut")
for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
