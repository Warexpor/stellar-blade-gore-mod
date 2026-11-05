-- No Vertical Splits (gore.noSplits): odds nearly all split (90 split, 10 limb), and never split; the odds' split
-- share goes to the others, so every death still cuts a limb
local F = require("fake")
local E = require("eve")
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.gore.noSplits = true
s.gore.death = { limb = 10, head = 0, torso = 0, split = 90, moreLimbs = 0 }
return s
]])
f:close()
local original_dofile, G = dofile, nil
dofile = function(path)
  local result = original_dofile(path)
  if path == DIR .. "gore.lua" then G = result end
  return result
end
local ok, err = pcall(dofile, DIR .. "main.lua")
dofile = original_dofile
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local at = #F.log_lines() + 1
local cuts, splits, uncleared = 0, 0, 0
for _ = 1, 4 do
  E.die(true)
  F.run(6, pawn)
  local parts = G.cut_parts(E.mesh)
  local count, split = G.cuts_on(E.mesh)
  if count == 1 and #parts == 1 and (parts[1]:find("UpperArm", 1, true) or parts[1]:find("Thigh", 1, true)) then cuts = cuts + 1 end
  if split or G.split_on(E.mesh) then splits = splits + 1 end
  F.run(10, pawn); E.respawn(); F.run(6, pawn)
  if G.cuts_on(E.mesh) ~= 0 then uncleared = uncleared + 1 end
end
check(splits == 0, "no split in 4 deaths at 90% split odds")
check(cuts == 4, "every death cut a limb instead (" .. cuts .. " of 4)")
check(uncleared == 0, "each death's cut cleared on respawn")

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
if fails > 0 then for i, x in ipairs(F.log_lines()) do if i >= at and (x:find("death") or x:find("gore")) then print("  | " .. x:sub(1, 200)) end end end
print(fails == 0 and "PASS" or "FAIL")
