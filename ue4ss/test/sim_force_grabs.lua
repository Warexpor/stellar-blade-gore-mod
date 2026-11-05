-- Forced grabs (enemies.forceGrabs): attack branches play their tree's own grab; put back on off.
local F = require("fake")
local print = F.say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end

local tune = dofile("ue4ss/Mods/StellarBladeGore/Scripts/tune.lua")
tune.enemies = tune.enemies or {}
tune.enemies.forceGrabs = true
local logs = {}
local watched = {}
local ctx = {
  tune = tune,
  log = function(s) logs[#logs + 1] = s; print("  | " .. s) end,
  try = function(f) local ok, r = pcall(f); if ok then return r end end,
  valid = function(x) return x ~= nil and x ~= false end,
  keep = function(o) return { addr = o:GetAddress(), obj = o, alive = true } end,
  held = function(k) return k and k.alive and k.obj or nil end,
  alive_ask = function(ks) for _, k in ipairs(ks) do k.alive = true end; return true end,
  newobj = { watch = function(path, fn) watched[path] = fn end },
}
local E = dofile("ue4ss/Mods/StellarBladeGore/Scripts/enemies.lua")
E.init(ctx)

-- pure picks
check(E.force_is_grab("M_Raven_BetaGrab"), "grab skill recognized")
check(not E.force_is_grab("M_Raven_SlashCombo"), "slash is no grab")
check(E.force_plain_grab("M_Raven_BetaGrab"), "plain grab picked")
check(not E.force_plain_grab("M_Raven_BetaCounterGrab"), "counter grab not plain")
check(not E.force_plain_grab("M_Crawler_GrabFail"), "fail show not plain")
check(E.force_pick({ M_Raven_SlashCombo = true, M_Raven_BetaGrab = true }) == "M_Raven_BetaGrab",
  "pick prefers the plain grab")
check(E.force_pick({ M_ElderPhase2_Grab = true }) == "M_ElderPhase2_Grab",
  "a lone grab still picked when nothing plainer")
check(E.force_pick({ M_LionA_SlashCombo = true }) == nil, "no grab skill, no pick")
check(E.force_attack_node({ "M_Raven_SlashCombo" }), "slash branch renamed")
check(not E.force_attack_node({ "M_Raven_BetaGrab" }), "grab branch left alone")
check(not E.force_attack_node({ "M_Raven_BetaEvadeLeft", "M_Raven_BetaEvadeRight" }),
  "evades left alone")
check(not E.force_attack_node({}), "empty skill list left alone")

-- fake UseSkill nodes: SkillName arrays read like the game's, written whole or per element
local function arr(list, noelem)
  local a = { items = { table.unpack(list) } }
  function a:ForEach(fn)
    for i, s in ipairs(self.items) do
      local e = { v = s }
      function e:get() return { ToString = function() return e.v end } end
      if not noelem then function e:set(nv) e.v = nv; a.items[i] = nv end end
      fn(i, e)
    end
  end
  return a
end
local function node(tree, skills, opts)
  opts = opts or {}
  local o = F.obj("SBBTTask_SbUseSkill_" .. tree .. "_" .. (#skills > 0 and skills[1] or "empty"), "SBBTTask_SbUseSkill")
  -- writes intercepted every time through a backing store (__newindex only fires for absent keys,
  -- so the value itself never lives on the object, mirroring the game's array semantics)
  local store = {}
  local mt = getmetatable(o)
  setmetatable(o, { __index = function(t, k)
      if k == "SkillName" then return store.SkillName end
      return mt.__index(t, k)
    end,
    __newindex = function(t, k, v)
      if k == "SkillName" then
        if type(v) == "table" and not v.ForEach then
          if rawget(t, "__noassign") then error("no whole-list write on this build") end
          v = arr(v)
        end
        store.SkillName = v
      else
        rawset(t, k, v)
      end
    end })
  o.SkillName = arr(skills, opts.noelem)
  if opts.noassign then o.__noassign = true end
  local full = opts.full or ("SBBTTask_SbUseSkill /Game/GameDesign/Combat/BehaviorTree/Monster/" .. tree .. "." .. tree .. ":SBBTTask_SbUseSkill_1")
  o.GetFullName = function() return full end
  return o
end
local raven_slash = node("M_Raven_AI", { "M_Raven_SlashCombo" })
local raven_grab = node("M_Raven_AI", { "M_Raven_BetaGrab" })
local raven_evade = node("M_Raven_AI", { "M_Raven_BetaEvadeLeft" })
local saw_grab = node("M_Sawshark_AI", { "M_Sawshark_LS01_DoubleGrab" })
local saw_swing = node("M_Sawshark_AI", { "M_Sawshark_S01_RightSwing" })
local lion_swing = node("M_Lion_AI", { "M_LionA_SlashCombo" })
-- one build corner each: element writes only, and neither write
local elem_only = node("M_Raven_AI", { "M_Raven_Thrust" }, { noassign = true })
local unwritable = node("M_Raven_AI", { "M_Raven_Spin" }, { noassign = true, noelem = true })
-- closers, ranged attacks and buffs keep theirs
local raven_charge = node("M_Raven_AI", { "M_Raven_BetaChargeCombo" })
local saw_ranged = node("M_Sawshark_AI", { "M_Sawshark_RangeExplosion" })
-- a node the game made up on the fly (no tree in its name) groups by its outer
local dyn_grab = node("?", { "M_Crawler_ComboGrab" },
  { full = "SBBTTask_SbUseSkill /Game/Art/Character/Monster/CH_M_NA_22.CH_M_NA_22_Blueprint_C_2147480323:SBBTTask_SbUseSkill_9" })
local dyn_swing = node("?", { "M_Crawler_ClawAttack" },
  { full = "SBBTTask_SbUseSkill /Game/Art/Character/Monster/CH_M_NA_22.CH_M_NA_22_Blueprint_C_2147480323:SBBTTask_SbUseSkill_4" })
F.classes["SBBTTask_SbUseSkill"] = { raven_slash, raven_grab, raven_evade, saw_grab, saw_swing, lion_swing, elem_only, unwritable, raven_charge, saw_ranged, dyn_grab, dyn_swing }

local function skills(o)
  local out = {}
  o.SkillName:ForEach(function(_, e) out[#out + 1] = e:get():ToString() end)
  return out
end
local function run(s) local t1 = F.t + s; while F.t < t1 do F.t = F.t + 0.01; E.force_tick() end end

run(0.2)
check(skills(raven_slash)[1] == "M_Raven_BetaGrab", "raven slash plays BetaGrab now")
check(#skills(raven_slash) == 1, "replaced whole, nothing of the old list left")
check(skills(raven_grab)[1] == "M_Raven_BetaGrab", "raven grab untouched")
check(skills(raven_evade)[1] == "M_Raven_BetaEvadeLeft", "evade untouched")
check(skills(saw_swing)[1] == "M_Sawshark_LS01_DoubleGrab", "sawshark swing plays DoubleGrab now")
check(skills(lion_swing)[1] == "M_LionA_SlashCombo", "a tree with no grab skill stays as the game has it")
check(skills(elem_only)[1] == "M_Raven_BetaGrab", "renamed by element writes where whole-list fails")
check(skills(unwritable)[1] == "M_Raven_Spin", "left alone where neither write holds")
check(skills(raven_charge)[1] == "M_Raven_BetaGrab", "a lunging combo comes out a grab too")
check(skills(saw_ranged)[1] == "M_Sawshark_RangeExplosion", "a ranged attack keeps its skill")
check(skills(dyn_swing)[1] == "M_Crawler_ComboGrab", "pawn-made nodes group by their outer")
local origs = E.force_orig_skills()
check(origs["M_Raven_SlashCombo"] and origs["M_Sawshark_S01_RightSwing"],
  "saved originals join aft.skills")

-- a tree streaming in later is caught through the new-object watch
local crawler_swing = node("M_Crawler_AI", { "M_Crawler_ClawAttack" })
local crawler_grab = node("M_Crawler_AI", { "M_Crawler_ComboGrab" })
check(watched["/Script/SB.SBBTTask_SbUseSkill"] ~= nil, "late trees watched as they are made")
watched["/Script/SB.SBBTTask_SbUseSkill"](crawler_grab)
watched["/Script/SB.SBBTTask_SbUseSkill"](crawler_swing)
run(2)
check(skills(crawler_swing)[1] == "M_Crawler_ComboGrab", "late tree swapped once made")

-- off: everything put back
tune.enemies.forceGrabs = false
run(0.2)
check(skills(raven_slash)[1] == "M_Raven_SlashCombo", "raven slash put back on off")
check(skills(saw_swing)[1] == "M_Sawshark_S01_RightSwing", "sawshark swing put back on off")
check(next(E.force_orig_skills()) == nil, "no originals kept after putback")

check(#F.errors == 0, "no errors (" .. table.concat(F.errors, "; ") .. ")")
print(fails == 0 and "PASS" or "FAIL")
