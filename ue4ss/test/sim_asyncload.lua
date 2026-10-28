-- the cuts' assets loaded ahead by the game's async loader (sbslice "J", tune.gore.asyncLoad): on the game thread one a
-- look, the first blood effect held a frame 1.4 s and every sound 30 ms (playtest). Each asked for once, kept ("o")
-- once it is in (loaded on two looks in a row), and one that never comes in loaded as before after ASYNC_S; nothing
-- loaded on the game thread meanwhile. (Off, the library not found, every other sim: loaded as before)
local F = require("fake")
local E = require("eve")
local R = require("rag")
local pawn = E.make(F)
local print = F.say
R.install(F, E)
F.world = R.step

F.objects["/Script/Engine.Default__KismetSystemLibrary"] = F.obj("Default__KismetSystemLibrary", "KismetSystemLibrary")
F.objects["/Script/Engine.KismetSystemLibrary:MakeSoftObjectPath"] = F.obj("MakeSoftObjectPath", "Function")
F.objects["/Script/Engine.KismetSystemLibrary:LoadAsset"] = F.obj("LoadAsset", "Function")

-- the loader: an asset asked for is in memory 0.3 s on (still loading: NeedLoad), loaded 0.6 s on; the first one asked
-- for never comes in
local asked, order, syncLoads, held = {}, {}, {}, nil
local function asset(path, loadedAt)
  return F.obj(path:match("([^/.]+)$"), "Object", {
    HasAnyFlags = function() return F.t < loadedAt and true or false end,
    HasAnyInternalFlags = function() return false end,
  })
end
F.sbslice.J = function(s)
  -- the library's parameters as the DLL reads them (UE4SS's Lua UFunction has no ForEachProperty)
  if s:sub(2, 2) == "?" then return "ok 0,16 size 40 / 0,8,48,64 size 88" end
  local path = s:match(";(.+)$")
  asked[path] = (asked[path] or 0) + 1
  order[#order + 1] = path
  if not held then held = path
  else
    local t = F.t
    F.loops[#F.loops + 1] = { ms = 300, at = t, cb = function()
      F.objects[path] = F.objects[path] or asset(path, t + 0.6)
      return true
    end }
  end
  return "ok " .. #order
end
local rooted = {}
F.sbslice.o = function(s) rooted[tonumber(s:sub(2), 16)] = true; return "ok rooted" end
F.sbslice.w = "ok watched 0"
LoadAsset = function(path)
  syncLoads[#syncLoads + 1] = { path = path, t = F.t }
  F.objects[path] = F.objects[path] or asset(path, 0)
  return F.objects[path]
end

local ok, err = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(100, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function dump(pat) for _, x in ipairs(F.log_lines()) do if not pat or x:find(pat) then print("  | " .. x:sub(1, 220)) end end end

check(F.find("async loads: on") ~= nil, "on: the library's layout checked")
local n, twice = 0, 0
for _, c in pairs(asked) do n = n + 1; if c > 1 then twice = twice + 1 end end
check(n >= 10 and twice == 0, string.format("each asked for once (%d assets, %d twice)", n, twice))
local early = 0
for _, l in ipairs(syncLoads) do if l.path ~= held then early = early + 1 end end
check(early == 0, string.format("nothing else loaded on the game thread (%d)", early))
check(#syncLoads == 1 and syncLoads[1].path == held, "the one that never came in loaded as before (" .. tostring(syncLoads[1] and syncLoads[1].path) .. ")")
local notRooted = 0
for _, p in ipairs(order) do
  local o = F.objects[p]
  if not (o and rooted[rawget(o, "__addr")]) then notRooted = notRooted + 1 end
end
check(notRooted == 0, string.format("every one kept (%d not)", notRooted))
check(F.find("cut assets loaded and kept: %d+ of %d+ %(%d+ by the async loader, 1 late and loaded as before%)") ~= nil, "the summary line")
if fails > 0 then dump("async\\|cut assets\\|could not") end

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
