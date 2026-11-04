-- The characters' places shared by the watches (main.lua goreCtx.char_at): her watches, the enemies' part and the poll
-- each read every character of the level again, on frames of their own (0.5.2 Nexus report of the frame rate down).
-- One far off (100 m) is read about once a second, not every time a watch asks; one near her whenever one asks; and
-- the far one, warped in next to her, is followed by the swing within that second. She stands at (1000, 2000)
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"

local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local BONES = { "Bip001", "Bip001-Pelvis", "Bip001-Spine1", "Bip001-R-Hand", "Weapon_R" }
local function enemy(name, at)
  local e = { at = at, reads = 0 }
  e.mesh = F.obj(name .. "_Mesh", "SkeletalMeshComponent", {
    SkeletalMesh = F.obj("SK_" .. name, "SkeletalMesh"),
    GetNumBones = function() return #BONES end,
    GetBoneName = function(_, i) return F.fname(BONES[i + 1] or "None") end,
    GetSocketLocation = function() return vec(e.at.X - 40, e.at.Y, e.at.Z + 30) end,
  })
  e.obj = F.obj(name, "CH_M_NA_14_Blueprint_C", {
    Mesh = e.mesh, bActorIsBeingDestroyed = false, bHidden = false,
    K2_GetActorLocation = function() e.reads = e.reads + 1; return vec(e.at.X, e.at.Y, e.at.Z) end,
    GetVelocity = function() return vec(0, 0, 0) end,
  })
  return e
end
local far = enemy("CH_M_NA_14_Blueprint_C_far", vec(11000, 2000, 90))
local near = enemy("CH_M_NA_14_Blueprint_C_near", vec(2500, 2000, 90))
F.classes.SBCharacter = { pawn, far.obj, near.obj }
for i = 1, 70 do
  local e = enemy("Distant_" .. i, vec(20000 + i * 10, 2000, 90))
  F.classes.SBCharacter[#F.classes.SBCharacter + 1] = e.obj
end

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
local biggest = 0
for _, c in ipairs(F.cmds) do
  if c.s:sub(1, 1) == "G" then biggest = math.max(biggest, (select(2, c.s:gsub(",", ",")) + 1) // 2) end
end
check(biggest >= 60, "fresh character guards validated in a batch (" .. biggest .. " entries)")
-- Simulate previously indexed characters whose guards have aged out of the shared list.
local function findctx(fn, seen)
  seen = seen or {}; if type(fn) ~= "function" or seen[fn] then return end; seen[fn] = true
  for i = 1, 200 do
    local name, value = debug.getupvalue(fn, i); if not name then break end
    if name == "goreCtx" then return value end
    if name ~= "_ENV" and type(value) == "function" then local found = findctx(value, seen); if found then return found end end
  end
end
local tick = F.hooks["/Game/Art/Character/PC/CH_P_EVE_01/Blueprints/CH_P_EVE_01_Blueprint.CH_P_EVE_01_Blueprint_C:ReceiveTick"][1]
local ctx = assert(findctx(tick), "game context")
-- The death-screen guard must not revalidate the whole actor list just to check one widget.
local widget = F.obj("guarded death widget", "UserWidget")
local wk = assert(ctx.keep(widget))
ctx.frame = ctx.frame + 1
check(ctx.held(wk), "widget guard obtains its native object index")
local realAsk, widgetBatch = ctx.alive_ask, nil
ctx.alive_ask = function(list) widgetBatch = #list; return realAsk(list) end
ctx.frame = ctx.frame + 1
check(ctx.held(wk, true) and widgetBatch == 1, "single widget validation does not scan unrelated held objects")
ctx.frame = ctx.frame + 1
ctx.alive_ask = function(list) list[1].alive = false; list[1].frame = ctx.frame; return true end
check(not ctx.held(wk, true) and wk.dead, "single widget validation rejects a stale object")
ctx.alive_ask = realAsk
local function newpoll() ctx.frame = ctx.frame + 1; ctx.poll = ctx.poll + 1 end
newpoll()
local chars = ctx.live_chars()
local removed = {}
for _, e in ipairs(chars) do e.k.listed = nil; removed[e.k] = true end
local keep = {}; for _, k in ipairs(ctx.heldList) do if not removed[k] then keep[#keep + 1] = k end end
ctx.heldList = keep
newpoll()
local before = #F.cmds
local again = ctx.live_chars()
local calls = 0
for i = before + 1, #F.cmds do if F.cmds[i].s:sub(1, 1) == "G" then calls = calls + 1 end end
check(#again == #chars and calls <= math.ceil(#chars / 64), "returning character guards are checked in bounded batches (" .. calls .. " calls)")
-- Her watches, the enemies' part and the poll share one walk per poll window: a second listing in the same window
-- returns the same list with no new lifetime checks.
local cached = ctx.live_chars()
local extracalls = 0
for i = before + 1, #F.cmds do if F.cmds[i].s:sub(1, 1) == "G" then extracalls = extracalls + 1 end end
check(cached == again and extracalls == calls, "one walk per poll window (" .. extracalls - calls .. " extra lifetime checks)")
-- A later phase of the same window, on a newer game frame, still shares the walk: no revalidation at all.
ctx.frame = ctx.frame + 1
local before2 = #F.cmds
local phase2 = ctx.live_chars()
local phase2calls = 0
for i = before2 + 1, #F.cmds do if F.cmds[i].s:sub(1, 1) == "G" then phase2calls = phase2calls + 1 end end
check(phase2 == again and phase2calls == 0, "later phases share the same walk (" .. phase2calls .. " extra lifetime checks)")

-- A long loading screen leaves guards listed but past the three-second held-list expiry. Previously the first
-- held() pruned all the others and each character revalidated a growing list on its own.
for _, e in ipairs(again) do e.k.asked = -1000 end
newpoll()
before = #F.cmds
local after_pause = ctx.live_chars()
calls = 0
for i = before + 1, #F.cmds do if F.cmds[i].s:sub(1, 1) == "G" then calls = calls + 1 end end
check(#after_pause == #again and calls <= math.ceil(#again / 64), "expired listed characters are validated in batches after a pause (" .. calls .. " calls)")

-- 3 s at 60 fps: 90 polls
far.reads, near.reads = 0, 0
F.run(3, pawn)
check(far.reads >= 2 and far.reads <= 5, "the one 100 m off read about once a second (" .. far.reads .. " reads in 3 s)")
check(near.reads >= 6 * far.reads and near.reads <= 100, "the one 15 m off read whenever a watch asks, at most once a poll (" .. near.reads .. " reads in 3 s, 90 polls)")

-- warped in next to her: followed by the swing within a second
local at = mark()
far.at = vec(1150, 2000, 90)
local t0 = F.t
local seen
for _ = 1, 90 do
  F.step(1 / 60, pawn)
  if not seen and F.find("swing: CH_M_NA_14_Blueprint_C holds", at) then seen = F.t - t0 end
end
check(seen ~= nil and seen <= 1.3, "the far one warped in: followed within a second (" .. tostring(seen and string.format("%.2f s", seen)) .. ")")

-- A seed never lands on a cut-opening frame: while a cut is busy the backfill waits (spawns still arrive through
-- the new-object watch), then runs on the first quiet poll. (After the read-rate checks: a reseed gives every guard
-- a fresh keep time, and fresh guards read live for their first seconds by design.)
local function findgore(fn, seen)
  seen = seen or {}; if type(fn) ~= "function" or seen[fn] then return end; seen[fn] = true
  for i = 1, 200 do
    local name, value = debug.getupvalue(fn, i); if not name then break end
    if name == "gore" then return value end
    if name ~= "_ENV" and type(value) == "function" then local found = findgore(value, seen); if found then return found end end
  end
end
local G = assert(findgore(tick), "gore module")
local realFind, seedFinds = FindAllOf, 0
FindAllOf = function(cls, ...)
  if cls == "SBCharacter" then seedFinds = seedFinds + 1 end
  return realFind(cls, ...)
end
local realBusy = G.busy
G.busy = function() return true end
ctx.reseed, ctx.seededAt = true, F.t - 10
newpoll()
local held = ctx.live_chars()
G.busy = realBusy
check(#held > 0 and seedFinds == 0, "no seed while a cut is busy (" .. seedFinds .. " object-array walks, " .. #held .. " listed)")
newpoll()
local seeded = ctx.live_chars()
FindAllOf = realFind
check(seedFinds == 1 and #seeded >= #held, "the backfill runs on the first quiet poll (" .. seedFinds .. " walk)")

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
