-- F6's struggle tests (main.lua's STRUGGLE_TESTS) with Death Struggle off (deathMoves false; on by default): each press
-- a ragdoll death with its set cuts, and the struggle must begin every time on what they left her (the stumps it
-- names), then F8 gets her up for the next
local F = require("fake")
local E = require("eve")
local R = require("rag")
math.randomseed(3)
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.deathMoves = false
return s
]])
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
local function dump(from, pat)
  for i, x in ipairs(F.log_lines()) do if i >= from and (not pat or x:find(pat)) then print("  | " .. x:sub(1, 230)) end end
end

local WANT = {
  { "her right arm off", "struggle: stumps: right shoulder, left arm and 2 legs on", { "Bip001%-R%-UpperArm" } },
  { "her left leg off", "struggle: stumps: left hip, left and right arms and 1 leg on", { "Bip001%-L%-Thigh" } },
  { "across the waist", "struggle: stumps: waist, left and right arms and 0 legs on", { "Bip001%-Spine1" } },
  { "left arm and right leg", "struggle: stumps: left shoulder, right hip, right arm and 1 leg on", { "Bip001%-L%-UpperArm", "Bip001%-R%-Thigh" } },
  { "both legs", "struggle: stumps: left hip, right hip, left and right arms and 0 legs on", { "Bip001%-L%-Thigh", "Bip001%-R%-Thigh" } },
  { "left forearm", "struggle: stumps: left elbow, right arm and 2 legs on", { "Bip001%-L%-Forearm" } },
  { "no cut", "struggle: no limb cut: tries to sit up only", {} },
}
for i, w in ipairs(WANT) do
  local at = mark()
  check(F.press("F6", ""), "F6 bound")
  F.run(6, pawn)
  check(F.find("F6: struggle test " .. i .. " of 7: .*" .. w[1], at) ~= nil, i .. ": F6 picked " .. w[1])
  for _, b in ipairs(w[3]) do check(F.find("gore: cut " .. b .. " %(death%)", at) ~= nil, i .. ": cut " .. b:gsub("%%", "")) end
  check(F.find(w[2], at) ~= nil, i .. ": the struggle began: " .. w[2]:gsub("%%", ""))
  check(F.find("F7: pushed", at) ~= nil, i .. ": F7's shove on it")
  if fails > 0 then dump(at, "struggle"); dump(at, "F6"); dump(at, "skipped"); break end
  F.press("F8", "")
  F.run(3, pawn)
  check(not F.find("F6: she is already down", at), i .. ": she was up again for the next")
end
for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
