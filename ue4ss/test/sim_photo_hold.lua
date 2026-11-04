-- Photo hold must zero velocities while photo mode is open (12 cm drift fix).
local F = require("fake")
local E = require("eve")
local R = require("rag")
local pawn = E.make(F)
local print = F.say
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
local photo = false
F.sbslice.f = function(s)
  if s:sub(1, 2) == "f2" then photo = true; return "ok photo entered 1" end
  if s:sub(1, 2) == "f3" then return "ok photo state: mgr 38=1 84=" .. (photo and "1" or "0") .. " 48=0" end
  return "ok photo shield 1"
end
R.install(F, E)
F.world = R.step
local ok, err = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)
local fails = 0
local function check(c, what) print((c and "ok   " or "FAIL ") .. what); if not c then fails = fails + 1 end end
local function mark() return #F.log_lines() + 1 end
E.die(true)
F.run(2, pawn)
local at = mark()
check(F.press("P", ""), "P bound")
F.run(1, pawn)
-- simulate physics drift while photo is open: spin up a body
R.W["Bip001-Head"] = { X = 100, Y = 0, Z = 0 }
R.V["Bip001-Head"] = { X = 50, Y = 0, Z = 0 }
local z0, lz0 = R.zeroed, R.linZeroed or 0
F.run(1.5, pawn)
local w = R.W["Bip001-Head"] or { X = 0, Y = 0, Z = 0 }
local v = R.V["Bip001-Head"] or { X = 0, Y = 0, Z = 0 }
local wl = math.sqrt(w.X * w.X + w.Y * w.Y + w.Z * w.Z)
local vl = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
check((R.zeroed or 0) > z0, "photo hold zeroes angular velocity")
check((R.linZeroed or 0) > lz0, "photo hold zeroes linear velocity")
check(wl < 1 and vl < 1, "drifted head stopped while photo open")
photo = false
F.run(1.5, pawn)
check(F.find("photo mode closed", at) ~= nil, "photo closed")
for _, e in ipairs(F.errors) do print("hook error: " .. e) end
check(#F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
