-- Capsule must not follow the ragdoll: socket cleared to None on death.
local F = require("fake")
local E = require("eve")
local R = require("rag")
local pawn = E.make(F)
local print = F.say
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"
-- the game's default: capsule follows the pelvis; the mod must clear it
rawset(pawn, "RagdollInfo", { CapsuleComponentFollowingSocket = F.fname("Bip001-Pelvis") })
R.install(F, E)
F.world = R.step
local ok, err = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)
local fails = 0
local function check(c, what) print((c and "ok   " or "FAIL ") .. what); if not c then fails = fails + 1 end end
local function mark() return #F.log_lines() + 1 end
local at = mark()
E.die(true)
F.run(2, pawn)
local sock = nil
pcall(function() sock = pawn.RagdollInfo.CapsuleComponentFollowingSocket:ToString() end)
check(sock == "None", "capsule socket cleared to None (" .. tostring(sock) .. ")")
check(F.find("capsule: the ragdoll had it follow", at) ~= nil, "capsule clear logged")
for _, e in ipairs(F.errors) do print("hook error: " .. e) end
check(#F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
