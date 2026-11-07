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
local function findctx(fn, seen)
  seen = seen or {}; if type(fn) ~= "function" or seen[fn] then return end; seen[fn] = true
  for i = 1, 200 do
    local name, value = debug.getupvalue(fn, i); if not name then break end
    if name == "goreCtx" then return value end
    if name ~= "_ENV" and type(value) == "function" then local found = findctx(value, seen); if found then return found end end
  end
end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
local initHook = F.hooks["/Game/Art/Character/PC/CH_P_EVE_01/Blueprints/CH_P_EVE_01_Blueprint.CH_P_EVE_01_Blueprint_C:ReceiveTick"][1]
local initCtx = assert(findctx(initHook))
initCtx.tune.gore.voice = initCtx.tune.gore.voice or {}
initCtx.tune.gore.voice.sounds = { "vo_test_custom" }
F.run(100, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function dump(pat) for _, x in ipairs(F.log_lines()) do if not pat or x:find(pat) then print("  | " .. x:sub(1, 220)) end end end

check(F.find("async loads: on") ~= nil, "on: the library's layout checked")
check(asked["/Game/Sound/Dialogue/ActionVoice/Eve/vo_test_custom_VO.vo_test_custom_VO"] == 1, "custom death voice preloaded once")
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
-- Actor refills retain their normal cadence but must not share the scan's frame.
local hook = F.hooks["/Game/Art/Character/PC/CH_P_EVE_01/Blueprints/CH_P_EVE_01_Blueprint.CH_P_EVE_01_Blueprint_C:ReceiveTick"][1]
local G = assert(findctx(hook)).gore
local jobs, scans, combined, maxJobs = {}, {}, 0, 0
for _, c in ipairs(F.cmds) do
  if c.s:sub(1, 1) == "w" then scans[c.frame] = true end
  if c.s:sub(1, 1) == "J" and c.s:sub(2, 2) ~= "?" then jobs[c.frame] = (jobs[c.frame] or 0) + 1 end
end
for frame, count in pairs(jobs) do
  maxJobs = math.max(maxJobs, count)
  if scans[frame] then combined = combined + 1 end
end
check(maxJobs == 1 and combined == 0, "one async request or lookup per update, apart from bone scans")
local missingWarm = 0
for _, path in ipairs(order) do if not G.guardedAssets[path] then missingWarm = missingWarm + 1 end end
check(missingWarm == 0, "all delivered assets have guarded Lua wrappers before first use")
local oldFind, repeatedFinds = StaticFindObject, 0
StaticFindObject = function(path)
  if asked[path] then repeatedFinds = repeatedFinds + 1 end
  return oldFind(path)
end
for _, path in ipairs(order) do G.guarded_asset(path) end
G.sfx("big", pawn, { X = 0, Y = 0, Z = 0 }, true)
StaticFindObject = oldFind
check(repeatedFinds == 0, "first sound and effect use performs no preloaded asset path scans")
-- Rooted package assets survive world changes, while their object identities are still guarded.
local savedPath = order[2]
local savedGuard = G.guardedAssets[savedPath]
G.forget(nil)
check(savedGuard ~= nil and G.guardedAssets[savedPath] == savedGuard,
  "world reload retains the rooted asset identity guard")
oldFind, repeatedFinds = StaticFindObject, 0
StaticFindObject = function(path)
  if path == savedPath then repeatedFinds = repeatedFinds + 1 end
  return oldFind(path)
end
local reused = G.guarded_asset(savedPath)
StaticFindObject = oldFind
check(reused == savedGuard.obj and repeatedFinds == 0,
  "first asset use after world reload reuses its validated wrapper")
local oldowner = pawn.Mesh.GetOwner
pawn.Mesh.GetOwner = function() return pawn end
local oldfill, frames, first = G.pool_fill, {}, #F.cmds
G.pool_fill = function(p) frames[#frames + 1] = F.frame; return oldfill(p) end
F.run(3, pawn)
G.pool_fill = oldfill
pawn.Mesh.GetOwner = oldowner
local scans, overlap = {}, 0
for i = first + 1, #F.cmds do if F.cmds[i].s:sub(1, 1) == "w" then scans[F.cmds[i].frame] = true end end
for _, frame in ipairs(frames) do if scans[frame] then overlap = overlap + 1 end end
check(#frames > 0 and overlap == 0, string.format("pool refills run apart from bone scans (%d refills, %d shared frames)", #frames, overlap))
-- Run enough watches to hit the scan branch directly: the main loop's try wrapper otherwise hides an exception.
local watchError
for _ = 1, 12 do
  local worked, err = pcall(G.watch, pawn.Mesh, function() end)
  if not worked then watchError = err; break end
end
check(not watchError, "bone watch completes without a hidden exception" .. (watchError and (": " .. tostring(watchError)) or ""))
if fails > 0 then dump("async\\|cut assets\\|could not") end

-- A timed-out asset must survive a closed fallback window and take priority once loading is safe.
do
  local w, path = G.watching, "/Game/Test/LateAsset.LateAsset"
  w.preload, w.next, w.sounds = { "/Game/Test/NewAsset.NewAsset" }, 1, 2
  w.late, w.at, w.n, w.every, w.fillNext = { path }, F.t + 2, 0, 100000, nil
  G.watch(pawn.Mesh, function() end)
  check(w.late[1] == path, "late asset is retained during the load pacing gap")
  F.t = F.t + 3
  local mayLoad = initCtx.may_load
  initCtx.may_load = function() return false end
  G.watch(pawn.Mesh, function() end)
  check(w.late[1] == path, "late asset is retained while level loading blocks asset work")
  initCtx.may_load = mayLoad
  local before = #syncLoads
  G.watch(pawn.Mesh, function() end)
  check(#syncLoads == before + 1 and syncLoads[#syncLoads].path == path and #w.late == 0,
    "late asset loads before new requests once the window opens")
end
-- A stalling game thread holds the preload: no new async asks while polls arrive late.
do
  local w = G.watching
  local function asks()
    local n = 0
    for _, c in ipairs(F.cmds) do
      local s = c.s
      if s:sub(1, 1) == "J" and s:sub(2, 2):match("[0-9a-fA-F]") then n = n + 1 end
    end
    return n
  end
  w.preload, w.next, w.sounds = { "/Game/Test/CalmAsset.CalmAsset" }, 1, 2
  w.late, w.at, w.n, w.every, w.fillNext, w.asyncTurn = nil, 0, 0, 100000, nil, false
  w.lastPoll = os.clock() - 1
  local before = asks()
  G.watch(pawn.Mesh, function() end)
  check(w.calm == false and asks() == before, "no async ask while the game stalls")
  w.lastPoll = os.clock()
  for _ = 1, 30 do
    G.watch(pawn.Mesh, function() end)
    if asks() > before then break end
  end
  check(w.calm == true and asks() == before + 1, "the preload resumes once polls are on time")end
for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
