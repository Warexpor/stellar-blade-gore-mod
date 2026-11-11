-- Evidence (playtest 13:17-13:18): a limb cut's chains stage spent 19 ms of Lua walking every bone through the engine,
local F = require("fake")
local print = F.say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end

-- ---- phase 1: chain_skip / bone_indices against the engine loop, on faithful meshes ----
local M = dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore.lua")
M.init({ log = function() end, try = function(f) local ok, r = pcall(f); if ok then return r end end,
  valid = function(x) return x ~= nil end, v3 = function() return "" end, physics_of = function(m) return m.__pa end })
local function v(x, y, z) return { X = x, Y = y, Z = z } end
check(M.side_drivers(nil, {"Bip001-Head"}) == "", "head cuts skip the irrelevant side-driver tree walk")
check(M.side_drivers(nil, {"Bip001-Spine1"}) == "", "torso cuts skip the irrelevant side-driver tree walk")
local addrSeq = 0xA000
local function mesh(bones, bodies)
  addrSeq = addrSeq + 0x1000
  local base, ad = addrSeq, addrSeq + 0x800
  local by, list = {}, {}
  for i, b in ipairs(bones) do by[b[1]] = b; list[i - 1] = b[1] end
  local m = { __n = #bones, calls = { boneName = 0, childOf = 0, boneIndex = 0 } }
  m.SkeletalMesh = { GetAddress = function() return base end }
  function m:GetAddress() return ad end
  function m:GetNumBones() return #bones end
  function m:GetBoneName(i) m.calls.boneName = m.calls.boneName + 1; return FName(list[i] or "None") end
  function m:GetBoneIndex(n)
    m.calls.boneIndex = m.calls.boneIndex + 1
    for i = 0, #bones - 1 do if list[i] == n:ToString() then return i end end
    return -1
  end
  function m:GetParentBone(n) local b = by[n:ToString()]; return FName(b and b[2] or "None") end
  function m:GetSocketLocation(n) local b = by[n:ToString()]; return b and b[3] or v(0, 0, 0) end
  function m:BoneIsChildOf(x, y)
    m.calls.childOf = m.calls.childOf + 1
    local b = by[x:ToString()]
    while b and b[2] do if b[2] == y:ToString() then return true end; b = by[b[2]] end
    return false
  end
  local setups = {}
  for _, n in ipairs(bodies or {}) do setups[#setups + 1] = { BoneName = FName(n) } end
  m.__pa = { GetAddress = function() return ad + 0x100 end, SkeletalBodySetups = { ForEach = function(_, f) for i, s in ipairs(setups) do f(i, { get = function() return s end }) end end } }
  return m
end
-- Exercise the assembled native command cache as well as the underlying list cache.
local function findclosure(fn, wanted, seen)
  seen = seen or {}
  if type(fn) ~= "function" or seen[fn] then return nil end
  seen[fn] = true
  for i = 1, 200 do
    local name, value = debug.getupvalue(fn, i)
    if not name then break end
    if name == wanted then return value end
    if name ~= "_ENV" and type(value) == "function" then
      local found = findclosure(value, wanted, seen)
      if found then return found end
    end
  end
end
local send
for _, fn in pairs(M) do send = findclosure(fn, "send_nosink"); if send then break end end
if send then
  local enemy, ci, oldCommand
  for i = 1, 200 do
    local n, value = debug.getupvalue(send, i)
    if not n then break end
    if n == "enemy" then enemy = value end
    if n == "command" then ci, oldCommand = i, value end
  end
  local commands = {}
  local sm = mesh({ {"Root"}, {"Bip001-Head", "Root"}, {"Ab_Helper", "Root"} }, {"Bip001-Head"})
  if enemy and ci then
    debug.setupvalue(send, ci, function(command) commands[#commands + 1] = command; return "ok" end)
    enemy.cur = "unfaced"; send(sm)
    check(next(M.nosink_cmd) ~= nil, "valid physics asset enables assembled-command caching")
    enemy.cur = "faced"; enemy.faced.faced = true; send(sm)
    check(commands[1] and commands[2] and commands[1] ~= commands[2],
      "assembled sink commands distinguish faced and unfaced enemies sharing a mesh")
    M.nosink_cmd, commands = {}, {}
    enemy.cur = "faced"; send(sm)
    enemy.cur = "unfaced"; send(sm)
    check(commands[1] and commands[2] and commands[1] ~= commands[2],
      "assembled sink commands distinguish the reverse cache order")
    local oldPa = sm.__pa
    local replacement = mesh({ {"Root"}, {"Bip001-Head", "Root"}, {"Ab_Helper", "Root"} }, {"Ab_Helper"})
    M.nosink_cmd, commands = {}, {}
    enemy.cur = nil; send(sm)
    sm.__pa = replacement.__pa; send(sm)
    check(commands[1] and commands[2] and commands[1] ~= commands[2],
      "assembled sink commands follow a replacement physics asset")
    sm.__pa = oldPa
    enemy.cur, enemy.faced.faced = nil, nil
    debug.setupvalue(send, ci, oldCommand)
  else check(false, "assembled sink cache test can inspect its dependencies") end
else check(false, "assembled sink cache test can locate its builder") end

M.nosink_cmd["old-world-sentinel"] = "obsolete"
local forgot, forgetErr = pcall(M.forget, nil)
check(forgot and not M.nosink_cmd["old-world-sentinel"], "world cleanup drops assembled cut commands" .. (forgot and "" or ": " .. tostring(forgetErr)))

-- the old engine loop, as the reference
local function ref_skip(m, top, limb)
  local try = function(f) local ok, r = pcall(f); if ok then return r end end
  local nb = try(function() return m:GetNumBones() end) or 0
  local under = function(x, y) return try(function() return m:BoneIsChildOf(FName(x), FName(y)) end) == true end
  local skip, list = {}, {}
  -- nosink_list's own rule, inlined (Bip001/SC_/Ab_ prefixes and Hair/Cape/Breast/Prop parts)
  for i = 0, nb - 1 do
    local nm = try(function() return m:GetBoneName(i):ToString() end) or "None"
    local bad = nm == "Root" or nm == "None"
    for _, pre in ipairs({ "Bip001", "SC_", "Ab_" }) do if nm:sub(1, #pre) == pre then bad = true end end
    for _, part in ipairs({ "Hair", "Cape", "Breast", "Prop" }) do if nm:find(part, 1, true) then bad = true end end
    if bad then skip[i] = true end
  end
  for i = 0, nb - 1 do
    local nm = try(function() return m:GetBoneName(i):ToString() end) or "None"
    local chain = nm == top or under(nm, top)
    if chain and nm ~= top then skip[i] = nil
    elseif not chain and (nm == limb or under(nm, limb)) then skip[i] = true end
  end
  for i = 0, nb - 1 do if skip[i] then list[#list + 1] = string.format("%x", i) end end
  return table.concat(list, ",")
end
local function ref_indices(m, names)
  local out = {}
  for _, c in ipairs(names) do
    local i = (function() local ok, r = pcall(function() return m:GetBoneIndex(FName(c)) end); if ok then return r end end)()
    if i and i > 0 then out[#out + 1] = string.format("%x", i) end
  end
  return table.concat(out, ",")
end
local function same_list(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
-- a cape arm: shoulder, upper arm, twist, forearm, hand, 7 hanging cape links (all Ab_, skipped; the top kept)
local function cape_arm()
  local bones = { { "Bip001-Spine2", nil, v(0, 0, 130) }, { "Bip001-L-Clavicle", "Bip001-Spine2", v(5, 0, 140) },
    { "Bip001-L-UpperArm", "Bip001-L-Clavicle", v(15, 0, 140) }, { "Ab-L-UpperArm-Tw1", "Bip001-L-UpperArm", v(15, 0, 128) },
    { "Bip001-L-Forearm", "Bip001-L-UpperArm", v(15, 0, 116) }, { "Bip001-L-Hand", "Bip001-L-Forearm", v(15, 0, 94) } }
  local prev = "Ab-L-UpperArm-Tw1"
  for k = 1, 7 do
    local n = string.format("Ab_CapeL%02d", k)
    bones[#bones + 1] = { n, prev, v(15, 0, 128 - k * 10) }
    prev = n
  end
  return mesh(bones)
end
-- a leg strap: thigh, calf, 3 helper links round the thigh
local function leg_strap()
  local bones = { { "Bip001-Pelvis", nil, v(0, 0, 100) }, { "Bip001-L-Thigh", "Bip001-Pelvis", v(10, 0, 95) },
    { "Bip001-L-Calf", "Bip001-L-Thigh", v(10, 0, 50) } }
  local prev = "Bip001-L-Thigh"
  for k = 1, 3 do
    local n = string.format("Ab_LLA%02d", k)
    bones[#bones + 1] = { n, prev, v(10 + k, 0, 86 - 3 * k) }
    prev = n
  end
  return mesh(bones)
end
do
  local cases = {
    { cape_arm(), "Ab_CapeL01", "Bip001-L-UpperArm", "cape chain off the arm" },
    { leg_strap(), "Ab_LLA01", "Bip001-L-Thigh", "leg strap chain off the thigh" },
    { cape_arm(), "Bip001-L-UpperArm", "Bip001-L-UpperArm", "top is the limb itself" },
    { leg_strap(), "Nope", "Bip001-L-Thigh", "unknown chain top" },
  }
  for _, c in ipairs(cases) do
    local m, top, limb, what = c[1], c[2], c[3], c[4]
    local want = {}
    for h in ref_skip(m, top, limb):gmatch("[^,]+") do want[#want + 1] = h end
    m.calls.boneName, m.calls.childOf = 0, 0
    local got = M.chain_skip(m, top, limb)
    check(same_list(got, want), "chain_skip matches the engine loop (" .. what .. ")")
    local n1, c1 = m.calls.boneName, m.calls.childOf
    m.calls.boneName, m.calls.childOf = 0, 0
    local got2 = M.chain_skip(m, top, limb)
    check(same_list(got2, want) and m.calls.boneName == 0 and m.calls.childOf == 0,
      string.format("chain_skip uses the warm tree, no engine calls (%s: %d bone names, %d child checks)", what, m.calls.boneName, m.calls.childOf))
    if n1 == 0 and c1 == 0 then print("ok    tree was already warm on first call (" .. what .. ")") end
  end
  local m = leg_strap()
  local names = { "Bip001-L-Hand", "Nope", "Bip001-Pelvis", "Bip001-L-Calf", "Bip001" }
  local want = {}
  for h in ref_indices(m, names):gmatch("[^,]+") do want[#want + 1] = h end
  local got = {}
  for _, i in ipairs(M.bone_indices(m, names)) do got[#got + 1] = string.format("%x", i) end
  check(same_list(got, want), "bone_indices matches GetBoneIndex per bone (unknown names dropped)")
  m.calls.boneIndex = 0
  M.bone_indices(m, names)
  -- only the names the tree never has still ask the engine
  check(m.calls.boneIndex == 3, "bone_indices uses the warm tree (" .. m.calls.boneIndex .. " engine calls)")
  -- index 0 comes off the tree too (still dropped from the command, as before)
  local m0 = mesh({ { "Bip001", nil, v(0, 0, 100) }, { "Bip001-Head", "Bip001", v(0, 0, 155) } })
  local got0 = {}
  for _, i in ipairs(M.bone_indices(m0, { "Bip001", "Bip001-Head" })) do got0[#got0 + 1] = string.format("%x", i) end
  check(same_list(got0, { "1" }), "bone_indices drops index 0")
  m0.calls.boneIndex = 0
  M.bone_indices(m0, { "Bip001", "Bip001-Head" })
  check(m0.calls.boneIndex == 0, "bone_indices resolves index 0 off the warm tree")
end

local E = require("eve")
local R = require("rag")
local pawn = E.make(F)
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
F.objects["/Script/Engine.Default__KismetSystemLibrary"] = F.obj("Default__KismetSystemLibrary", "KismetSystemLibrary")
F.objects["/Script/Engine.KismetSystemLibrary:MakeSoftObjectPath"] = F.obj("MakeSoftObjectPath", "Function")
F.objects["/Script/Engine.KismetSystemLibrary:LoadAsset"] = F.obj("LoadAsset", "Function")
local asked, delivered = {}, {}
F.sbslice.J = function(s)
  if s:sub(2, 2) == "?" then return "ok 0,16 size 40 / 0,8,48,64 size 88" end
  local path = s:match(";(.+)$")
  asked[path] = (asked[path] or 0) + 1
  local t = F.t
  F.loops[#F.loops + 1] = { ms = 300, at = t, cb = function()
    F.objects[path] = F.objects[path] or F.obj(path:match("([^/.]+)$"), "Object", {
      HasAnyFlags = function() return false end, HasAnyInternalFlags = function() return false end })
    delivered[path] = true
    return true
  end }
  return "ok " .. #F.loops
end
F.sbslice.o = function() return "ok rooted" end
F.sbslice.w = "ok watched 0"
-- one enemy on her trail the whole hot phase
local foeMesh = F.obj("NA14_Mesh", "SkeletalMeshComponent", {
  GetNumBones = function() return 3 end,
  GetBoneName = function(_, i) return F.fname(({ "Bip001", "Bip001-Hand", "Weapon_R" })[i + 1] or "None") end,
  GetSocketLocation = function() return { X = 1300, Y = 2000, Z = 100 } end,
})
local foe = F.obj("CH_M_NA_14_Blueprint_C_9", "CH_M_NA_14_Blueprint_C", {
  Mesh = foeMesh, bActorIsBeingDestroyed = false, bHidden = false,
  K2_GetActorLocation = function() return { X = 1300, Y = 2000, Z = 90 } end,
  GetVelocity = function() return { X = 0, Y = 0, Z = 0 } end,
  GetActorForwardVector = function() return { X = -1, Y = 0, Z = 0 } end,
})
-- on the character list from the start, so the first seed after startup picks it up
F.classes.SBCharacter = { pawn, foe }
local ok, err = pcall(dofile, DIR .. "main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); print("FAIL"); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
-- the mod starts 10 s after the player start: run past startup before the hot phase
F.run(11, pawn)
F.run(0.5, pawn)
local function findctx(fn, seen)
  seen = seen or {}; if type(fn) ~= "function" or seen[fn] then return end; seen[fn] = true
  for i = 1, 200 do
    local name, value = debug.getupvalue(fn, i); if not name then break end
    if name == "goreCtx" then return value end
    if name ~= "_ENV" and type(value) == "function" then local found = findctx(value, seen); if found then return found end end
  end
end
local hook = F.hooks["/Game/Art/Character/PC/CH_P_EVE_01/Blueprints/CH_P_EVE_01_Blueprint.CH_P_EVE_01_Blueprint_C:ReceiveTick"][1]
local G = assert(findctx(hook)).gore
F.run(4, pawn)
local nDelivered, nGuardedHot, twice = 0, 0, 0
for path in pairs(delivered) do
  nDelivered = nDelivered + 1
  if G.guardedAssets[path] then nGuardedHot = nGuardedHot + 1 end
end
for _, n in pairs(asked) do if n > 1 then twice = twice + 1 end end
check(nDelivered >= 5, string.format("assets kept arriving while hot (%d delivered)", nDelivered))
check(nGuardedHot > 0, string.format("delivered assets are warmed during combat (%d of %d guarded)", nGuardedHot, nDelivered))
check(twice == 0, string.format("no delivered asset asked for twice while held (%d re-asked)", twice))
foe.bActorIsBeingDestroyed = true
F.run(15, pawn)
local missing = 0
for path in pairs(delivered) do if not G.guardedAssets[path] then missing = missing + 1 end end
check(missing == 0, string.format("every delivered asset gets a guarded wrapper (%d missing)", missing))
local twice2 = 0
for _, n in pairs(asked) do if n > 1 then twice2 = twice2 + 1 end end
check(twice2 == 0, "still asked for once each after the resume")

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
