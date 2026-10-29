-- Sandbox Bosses (bosses.lua): a boss's CharacterTable row made mortal while one spawned here is up, and put back
-- exactly as the game had it once none is; the boss bar held at its floor and hit again takes it down; its death gets
-- a face and a struggle of its own (a fresh struggle.lua) that ticks without error; one held invincible (blows landing on
-- nothing) taken down; off, nothing is changed
local F = require("fake")
local print = F.say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
-- names as the game's name table: an index each
local names, byIdx = {}, {}
local function idx(s) if not names[s] then byIdx[#byIdx + 1] = s; names[s] = #byIdx end; return names[s] end
FName = function(s)
  s = tostring(s)
  local f = F.fname(s)
  getmetatable(f).__index.GetComparisonIndex = function() return idx(s) end
  return f
end
-- the table: rows of u32 fields at offsets, and DefaultEffectArray's names
local OFF = { DeadAlias = 0x10, MaxHP = 0x14, MaxShield = 0x18, DespawnTimeAfterDeath = 0x1c, DefaultEffectArray = 0x20 }
local function f2u(v) return string.unpack("<I4", string.pack("<f", v)) end
local rowsMem = {
  M_Tachy = { [0x10] = idx("M_Tachy"), [0x14] = 109120, [0x18] = 3310, [0x1c] = f2u(134.5),
    eff = { "Rank_Boss", "M_Tachy_HitCheckCount", "Passive_Immortal", "M_Tachy_Phase1", "M_Tachy_Default" } },
  M_Raven = { [0x10] = idx("M_Raven"), [0x14] = 248304, [0x18] = 4805, [0x1c] = f2u(1.0),
    eff = { "Rank_Boss", "Passive_Immortal", "M_Common_HitProjectileCheckCount" } },
  M_RoyalGuardFemale = { [0x10] = idx("M_RoyalGuardFemale"), [0x14] = 35455, [0x18] = 908, [0x1c] = f2u(1.0),
    eff = { "Passive_Immortal", "M_RoyalGuardFemale_Phase1", "Check_TagWeakPointX", "M_RoyalGuardFemale_FX_On" } },
}
local function snapshot()
  local o = {}
  for r, m in pairs(rowsMem) do
    local e = {}
    for i, n in ipairs(m.eff) do e[i] = n end
    o[r] = { m[0x10], m[0x14], m[0x18], m[0x1c], table.concat(e, ",") }
  end
  return o
end
local before = snapshot()
local rs = F.obj("SBCharacterTableProperty", "ScriptStruct")
rs.ForEachProperty = function(self, cb)
  for nm, off in pairs(OFF) do
    cb({ GetFName = function() return F.fname(nm) end, GetOffset_Internal = function() return off end })
  end
end
local dt = F.obj("CharacterTable", "DataTable", { RowStruct = rs })
F.objects["/Game/Local/Data/CharacterTable.CharacterTable"] = dt
local cmds = {}
local hpOf = {} -- actor address -> { hp, mhp, sh, msh } read by vb (none: "none")
local function command(s)
  cmds[#cmds + 1] = s
  if s:sub(1, 2) == "vb" then
    local a = tonumber(s:match("^vb(%x+)"), 16)
    local h = hpOf[a]
    if not h then return "none" end
    local r = string.format("ok %s%.2f %.2f %.2f %.2f", h.told and "" or "found ", h[1], h[2], h[3], h[4])
    h.told = true
    return r
  end
  local c = s:sub(1, 1)
  local f = {}
  for x in s:sub(2):gmatch("[^,]+") do f[#f + 1] = tonumber(x, 16) end
  local row = byIdx[f[3]]
  local m = rowsMem[row]
  if not m then return "err no such row" end
  if c == "d" then
    local was = m[f[5]] or 0
    if f[6] then m[f[5]] = f[6] end
    return string.format("ok row %016x %016x %016x", 0x1234, was, m[f[5]])
  elseif c == "N" then
    local from, to, n = byIdx[f[6]], byIdx[f[8]], 0
    for i, nm in ipairs(m.eff) do if nm == from then m.eff[i] = to; n = n + 1 end end
    return string.format("ok names %d of %d", n, #m.eff)
  end
  return "err ?"
end
local logs = {}
local tune = dofile("ue4ss/Mods/StellarBladeGore/Scripts/tune.lua")
tune.bosses.enabled = true
local kills = {}
local ctx = { tune = tune, log = function(s) logs[#logs + 1] = s; print("  | " .. s) end,
  try = function(f) local ok, r = pcall(f); if ok then return r end end, valid = function(x) return x ~= nil and x ~= false end,
  gore = { command = command, native_state = function() return "ready" end, enemy_off = function() return {} end },
  enemies = { kill_one = function(e, her, a, why) kills[#kills + 1] = why end },
  new_face = function()
    return { start = function() logs[#logs + 1] = "face started" end, tick = function() end, stop = function() end }
  end,
  rag = { MASS = {} } }
local B = dofile("ue4ss/Mods/StellarBladeGore/Scripts/bosses.lua")
B.init(ctx)
local kinds = {}
for _, k in ipairs(tune.bosses.kinds) do kinds[k.key] = k end
local function has(pat) for _, l in ipairs(logs) do if l:find(pat) then return true end end return false end

-- off: nothing changed
tune.bosses.enabled = false
check(B.prepare(kinds.tachy) ~= nil and #cmds == 0, "off: not spawned, nothing written")
tune.bosses.enabled = true

-- Tachy made mortal
check(B.prepare(kinds.tachy) == nil, "Tachy's row made mortal")
local t = rowsMem.M_Tachy
check(byIdx[t[0x10]] == "M_SkullSword", "Tachy dies as M_SkullSword (" .. tostring(byIdx[t[0x10]]) .. ")")
check(t.eff[3] == "Passive_Immortal_Dispel", "her Passive_Immortal swapped for its dispel")
check(t[0x14] == 27280 and t[0x18] == 828, string.format("her MaxHP and MaxShield a quarter (%d, %d)", t[0x14], t[0x18]))
check(t[0x1c] == before.M_Tachy[4], "her despawn time left (134.5 s, over 120)")
-- a second spawn of her: nothing written again
local n0 = #cmds
check(B.prepare(kinds.tachy) == nil and #cmds == n0, "a second Tachy: her row as it is")
-- Raven: her corpse kept
check(B.prepare(kinds.raven) == nil, "Raven's row made mortal")
check(string.unpack("<f", string.pack("<I4", rowsMem.M_Raven[0x1c])) == 120, "Raven's corpse stays 120 s (was 1)")

-- one spawned here followed; the floor
local mesh = F.obj("BossMesh", "SkeletalMeshComponent")
local boss = F.obj("CH_M_NA_21_Blueprint_C_1", "CH_M_NA_21_Blueprint_C", { Mesh = mesh })
boss.K2_GetActorLocation = function() return { X = 500, Y = 0, Z = 0 } end
local e = { obj = boss, mesh = mesh, kind = kinds.tachy }
B.adopted(0xb055, e, true)
local pawn = F.obj("Eve", "CH_P_EVE_01_Blueprint_C")
pawn.K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end
local bar = { Percent = 0.4 }
local hud = F.obj("WB_MainHUD_EnemyInfo_C_0", "WB_MainHUD_EnemyInfo_C", { ProgressBar_HP = bar })
hud.IsVisible = function() return true end
-- (its class's default object found first: never the one read)
local cdo = F.obj("Default__WB_MainHUD_EnemyInfo_C", "WB_MainHUD_EnemyInfo_C", { ProgressBar_HP = { Percent = 1 } })
cdo.IsVisible = function() return false end
F.classes["WB_MainHUD_EnemyInfo_C"] = { cdo, hud }
F.t = F.t + 1; B.tick(pawn)
check(#kills == 0, "its bar at 0.40: up")
-- Passive Bosses: its own tree (on the pawn, as the game has it: the controller's BrainComponent is none) stopped
-- and its controller lets go of it while on (again if the game starts the tree or possesses it again); off, taken
-- back and its tree started over
local brain = { running = true, stops = 0, restarts = 0 }
brain.IsRunning = function() return brain.running end
brain.StopLogic = function() brain.running, brain.stops = false, brain.stops + 1 end
brain.RestartLogic = function() brain.running, brain.restarts = true, brain.restarts + 1 end
local ai = F.obj("BossAI", "SBAIController", { StopMovement = function() end, lets = 0, takes = 0 })
ai.UnPossess = function() ai.lets = ai.lets + 1; boss.Controller = nil end
ai.Possess = function(_, p) ai.takes = ai.takes + 1; p.Controller = ai end
local montage = 0
mesh.GetAnimInstance = function() return { Montage_Stop = function() montage = montage + 1 end } end
boss.Controller = ai
boss.BrainComponent = F.obj("BossBrain", "SBBehaviorTreeComponent", brain)
brain = boss.BrainComponent
tune.bosses.passive = true
F.t = F.t + 0.3; B.tick(pawn)
check(brain.stops == 1 and ai.lets == 1 and boss.Controller == nil and montage == 1
  and has("stands still %(Passive Bosses%): its tree SBBehaviorTreeComponent stopped, its SBAIController let go"),
  "passive: its own tree stopped, its controller let go of it, its attack cut short")
boss.Controller = ai
F.t = F.t + 0.3; B.tick(pawn)
check(ai.lets == 2 and boss.Controller == nil and has("possessed again, let go again"), "passive: let go again when the game possesses it")
brain.running = true
F.t = F.t + 0.3; B.tick(pawn)
check(brain.stops == 2 and not brain.running and montage == 3 and has("its tree started again, stopped again"), "passive: its tree stopped again when the game starts it")
F.t = F.t + 0.3; B.tick(pawn)
check(ai.lets == 2 and montage == 3, "passive: left alone while stopped and let go")
tune.bosses.passive = false
F.t = F.t + 0.3; B.tick(pawn)
check(ai.takes == 1 and boss.Controller == ai and brain.restarts == 1 and brain.running and has("fights again %(possessed, its tree started over%)"),
  "passive off: taken back, its tree started over")
bar.Percent = 0.03
F.t = F.t + 0.1; B.tick(pawn)
check(#kills == 0 and has("the next hit takes it down"), "its bar at 0.03: waiting for the next hit")
e.hit = { t = F.t + 0.05 }
F.t = F.t + 0.2; B.tick(pawn)
check(#kills == 1 and kills[1]:find("hit again"), "hit again at its floor: taken down (" .. tostring(kills[1]) .. ")")

-- a phase change waiting on its arena (Scarlet's Phase2 cutscene): the bar held above the floor, it standing there
local e2 = { obj = F.obj("CH_M_NA_961_Blueprint_C_1", "CH_M_NA_961_Blueprint_C", { Mesh = F.obj("BossMesh2", "SkeletalMeshComponent") }), kind = kinds.tachy }
local at2 = { X = 400, Y = 0, Z = 0 }
e2.obj.K2_GetActorLocation = function() return at2 end
e2.mesh = e2.obj.Mesh
B.adopted(0x5ca1, e2, true)
bar.Percent = 0.5
local k0 = #kills
for i = 1, 6 do e2.hit = { t = F.t + 0.01 }; F.t = F.t + 0.5; B.tick(pawn) end
check(#kills == k0, "held at 0.50 for 3 s through hits: not yet")
-- (moving about: it fights, not stuck)
at2 = { X = 300, Y = 100, Z = 0 }
for i = 1, 6 do e2.hit = { t = F.t + 0.01 }; F.t = F.t + 0.5; B.tick(pawn) end
check(#kills == k0, "moved: its count starts over")
for i = 1, 6 do e2.hit = { t = F.t + 0.01 }; F.t = F.t + 0.5; B.tick(pawn) end
check(#kills == k0 + 1 and kills[#kills]:find("phase change"), "standing, bar held through hits over 4 s: taken down (" .. tostring(kills[#kills]) .. ")")
for i = 1, 4 do e2.hit = { t = F.t + 0.01 }; F.t = F.t + 0.5; B.tick(pawn) end
check(#kills == k0 + 1, "taken down once")
B._live()[0x5ca1] = nil

-- one far off (40 m) with the bar at 0: another enemy's bar, never taken for its
local e4 = { obj = F.obj("CH_M_NA_21_Blueprint_C_4", "CH_M_NA_21_Blueprint_C", { Mesh = F.obj("BossMesh4", "SkeletalMeshComponent") }), kind = kinds.tachy }
e4.mesh = e4.obj.Mesh
e4.obj.K2_GetActorLocation = function() return { X = 4000, Y = 0, Z = 0 } end
B.adopted(0xfa4, e4, true)
bar.Percent = 0
k0 = #kills
for i = 1, 10 do F.t = F.t + 0.5; B.tick(pawn) end
check(#kills == k0, "40 m off, the bar at 0: not taken down")
B._live()[0xfa4] = nil

-- held invincible (a phase change waiting on its stopped tree: Tachy and Scarlet took no more damage partway down,
-- playtest): her blade through it (enemies.struck), no hit reaction, its bar unmoved. Passive: stuckHits such blows
-- over stuckS s take it down; blows it reacts to never do; one that fights needs twice that
local strikes = {}
ctx.enemies.struck = function(_, x, since) local t = strikes[x]; if t and t > (since or -1) then return t end end
local function boss_at(a, name)
  local x = { obj = F.obj(name, "CH_M_NA_21_Blueprint_C", { Mesh = F.obj(name .. "Mesh", "SkeletalMeshComponent") }), kind = kinds.tachy }
  x.mesh = x.obj.Mesh
  x.obj.K2_GetActorLocation = function() return { X = 300, Y = 0, Z = 0 } end
  x.obj.BrainComponent = F.obj(name .. "Brain", "SBBehaviorTreeComponent",
    { IsRunning = function() return false end, StopLogic = function() end, RestartLogic = function() end })
  B.adopted(a, x, true)
  return x
end
local function blows(x, n, react)
  for _ = 1, n do
    strikes[x] = F.t
    if react then x.hit = { t = F.t + 0.05 }; bar.Percent = bar.Percent - 0.01 end
    F.t = F.t + 0.5; B.tick(pawn)
  end
end
bar.Percent = 0.6
local e5 = boss_at(0x1a5, "CH_M_NA_21_Blueprint_C_5")
tune.bosses.passive = true
k0 = #kills
blows(e5, 10, true)
check(#kills == k0 and B._live()[0x1a5].passive, "passive, struck 10 times, each taken: up")
blows(e5, 6, false)
check(#kills == k0 and has("struck, no hit taken %(its bar 0.500%)"), "passive, 6 blows taken by nothing over 2.5 s: not yet")
blows(e5, 4, false)
check(#kills == k0 + 1 and kills[#kills]:find("no hit taken"), "passive, held invincible through blows over 4 s: taken down (" .. tostring(kills[#kills]) .. ")")
B._live()[0x1a5] = nil
tune.bosses.passive = false
local e6 = boss_at(0x1a6, "CH_M_NA_21_Blueprint_C_6")
k0 = #kills
blows(e6, 12, false)
check(#kills == k0, "fighting, 12 blows over 5.5 s taken by nothing (guarded): up")
blows(e6, 6, false)
check(#kills == k0 + 1, "fighting, blows taken by nothing over 8 s: taken down")
B._live()[0x1a6] = nil
-- its HP read in memory (vb): blows that take HP or shield are taken, though it shows no hit reaction (Tachy reacted
-- to blows that took nothing, and the other way round); blows that take nothing take it down, though it reacts
tune.bosses.passive = true
local e7 = boss_at(0x1a7, "CH_M_NA_21_Blueprint_C_7")
hpOf[0x1a7] = { 5000, 5456, 0, 166 }
k0 = #kills
for _ = 1, 10 do strikes[e7] = F.t; hpOf[0x1a7][1] = hpOf[0x1a7][1] - 100; F.t = F.t + 0.5; B.tick(pawn) end
check(#kills == k0 and has("B_Tachy 1a7: its HP found in memory %(by its maximum%): 4900.00 5456.00"), "HP read: blows that take HP, no hit reaction: up")
for _ = 1, 10 do strikes[e7] = F.t; e7.hit = { t = F.t + 0.05 }; F.t = F.t + 0.5; B.tick(pawn) end
check(#kills == k0 + 1 and kills[#kills]:find("no hit taken") and has("struck, no hit taken %(its HP 4000/5456"),
  "HP read: blows it reacts to, its HP unmoved: taken down (" .. tostring(kills[#kills]) .. ")")
B._live()[0x1a7] = nil
-- a read whose maximum is nowhere near its row's (the DLL's "by its ratio" on other numbers: 0/250 on a Tachy of
-- 5456, playtest) is left: not at its floor, not taken down
local e8 = boss_at(0x1a8, "CH_M_NA_21_Blueprint_C_8")
hpOf[0x1a8] = { 0, 250, 1.43, 7.6 }
k0 = #kills
for _ = 1, 4 do F.t = F.t + 1; B.tick(pawn) end
local x8 = B._live()[0x1a8]
check(x8 and x8.hp == nil and has("B_Tachy 1a8: a read of its HP left") and not has("B_Tachy 1a8: its HP found")
  and #kills == k0, "HP read: a maximum far off its row's left")
B._live()[0x1a8] = nil
tune.bosses.passive = false
ctx.enemies.struck = nil

-- its death: face and struggle
B.died(pawn, 0xb055, e)
check(B._dead()[0xb055] ~= nil and B._dead()[0xb055].struggle ~= nil, "its death: a struggle of its own")
for _ = 1, 40 do F.t = F.t + 0.05; B.tick(pawn) end
check(has("face started"), "its dead face started")
check(B._dead()[0xb055] and B._dead()[0xb055].struggle ~= nil and not has("struggle: .*:%d+:"), "its struggle ticks without error")

-- gone: the rows put back after 15 s, exactly; a Raven destroyed without enemies.lua telling (the spawner window's
-- Remove) no longer counted
local e3 = { obj = F.obj("CH_M_NA_53_Blueprint_C_1", "CH_M_NA_53_Blueprint_C", { Mesh = F.obj("BossMesh3", "SkeletalMeshComponent") }), kind = kinds.raven }
e3.mesh = e3.obj.Mesh
B.adopted(0x7a5e, e3, true)
e3.obj.bActorIsBeingDestroyed = true
B.gone(0xb055, e)
for _ = 1, 20 do F.t = F.t + 1; B.tick(pawn) end
local after = snapshot()
local same = true
for r, v in pairs(before) do for i = 1, 5 do if after[r][i] ~= v[i] then same = false; print("  " .. r .. " field " .. i .. ": " .. tostring(v[i]) .. " -> " .. tostring(after[r][i])) end end end
check(same, "none left: both rows put back as the game had them")
check(next(B._rows()) == nil, "nothing left to put back")

-- Naked Tachy (Nexus 3183): her body mesh pointing at a physics asset the game doesn't have (none loads): the game's
-- own put back as she is adopted; a vanilla one's left as it is
local function pa_obj(path)
  local nm = path:match("([^/]+)$")
  return F.obj(nm, "PhysicsAsset", { GetFullName = function() return "PhysicsAsset " .. path .. "." .. nm end })
end
local own = pa_obj("/Game/Art/Character/Monster/CH_M_NA_21/CH_M_NA_21_Body_Physics")
F.objects["/Game/Art/Character/Monster/CH_M_NA_21/CH_M_NA_21_Body_Physics.CH_M_NA_21_Body_Physics"] = own
local function tachy_mesh(pa)
  -- (its bodies made again simulating, as the game's were: the mesh set to simulate with none till then)
  local st = { pa = pa, sets = 0, sim = false }
  local m = F.obj("TachyMesh", "SkeletalMeshComponent", { SkeletalMesh = F.obj("CH_M_NA_21_Body", "SkeletalMesh"),
    GetPhysicsAsset = function() return st.pa end,
    SetPhysicsAsset = function(self, p, re) st.pa, st.sets, st.reinit, st.sim, self.PhysicsAssetOverride = p, st.sets + 1, re, true, p end,
    IsSimulatingPhysics = function() return st.sim end,
    SetSimulatePhysics = function(_, v) st.sim = v end, SetAllBodiesSimulatePhysics = function(_, v) st.sim = v end })
  return m, st
end
logs = {}
local mm, mms = tachy_mesh(nil)
B.adopted(0xb0a1, { obj = F.obj("CH_M_NA_21_Blueprint_C_8", "CH_M_NA_21_Blueprint_C", { Mesh = mm }), mesh = mm, kind = kinds.tachy }, true)
check(mms.pa == own and mms.reinit == true and has("the game.s own CH_M_NA_21_Body_Physics put back %(ok,"),
  "a modded Tachy body with no physics asset the game has: hers put back")
check(not mms.sim and has("its bodies made kinematic %(they came simulating%)"), "its new bodies kinematic, not a ragdoll (no death on spawn)")
check(mm.SkeletalMesh.PhysicsAsset == own and has("on its mesh asset too"), "hers on its mesh asset too (a body made again from it keeps it)")
check(has("B_Tachy: mesh CH_M_NA_21_Body %x+, override CH_M_NA_21_Body_Physics, asset's own CH_M_NA_21_Body_Physics, answers CH_M_NA_21_Body_Physics, pelvis not simulating"),
  "its body's physics logged")
-- her death: its physics logged then and over the next 2 s
local e8 = { obj = F.obj("CH_M_NA_21_Blueprint_C_8", "CH_M_NA_21_Blueprint_C", { Mesh = mm }), mesh = mm, kind = kinds.tachy }
mms.sim = true
B.died(pawn, 0xb0a1, e8)
for _ = 1, 25 do F.t = F.t + 0.1; B.tick(pawn) end
check(has("B_Tachy b0a1 at its death: .*pelvis simulating") and has("B_Tachy b0a1 0%.%d s after its death") and has("B_Tachy b0a1 2%.%d s after its death"),
  "her death's physics logged at it and over the next 2 s")
local mf, mfs = tachy_mesh(pa_obj("/Game/Art/Character/PC/CH_P_EVE_01/CH_P_EVE_01_Physics"))
B.adopted(0xb0a2, { obj = F.obj("CH_M_NA_21_Blueprint_C_9", "CH_M_NA_21_Blueprint_C", { Mesh = mf }), mesh = mf, kind = kinds.tachy }, true)
check(mfs.pa == own, "a modded Tachy body with another's physics asset: hers put back")
local mv, mvs = tachy_mesh(own)
B.adopted(0xb0a3, { obj = F.obj("CH_M_NA_21_Blueprint_C_10", "CH_M_NA_21_Blueprint_C", { Mesh = mv }), mesh = mv, kind = kinds.tachy }, true)
check(mvs.sets == 0 and has("its own physics asset %(CH_M_NA_21_Body_Physics"), "a vanilla Tachy body: left as it is")

-- the Royal Guard Sister (her actor Rael's): her row made mortal, and Passive Bosses stands her still
check(kinds.royalguard and B.prepare(kinds.royalguard) == nil, "the Royal Guard Sister's row made mortal")
local g = rowsMem.M_RoyalGuardFemale
check(byIdx[g[0x10]] == "M_SkullSword" and g.eff[1] == "Passive_Immortal_Dispel" and g[0x14] == 8864
  and string.unpack("<f", string.pack("<I4", g[0x1c])) == 120, "she dies as M_SkullSword, not immortal, a quarter HP, kept 120 s")
local gb = { running = true, stops = 0 }
gb.IsRunning = function() return gb.running end
gb.StopLogic = function() gb.running, gb.stops = false, gb.stops + 1 end
gb.RestartLogic = function() gb.running = true end
local gm = F.obj("RaelMesh", "SkeletalMeshComponent")
local gai = F.obj("RaelAI", "SBAIController", { StopMovement = function() end })
local rael = F.obj("CH_NPC_Rael_Blueprint_C_1", "CH_NPC_Rael_Blueprint_C", { Mesh = gm, Controller = gai })
gai.UnPossess = function() rael.Controller = nil end
gai.Possess = function(_, p) p.Controller = gai end
rael.K2_GetActorLocation = function() return { X = 300, Y = 0, Z = 0 } end
rael.BrainComponent = F.obj("RaelBrain", "SBBehaviorTreeComponent", gb)
gb = rael.BrainComponent
B.adopted(0x4a1, { obj = rael, mesh = gm, kind = kinds.royalguard }, true)
tune.bosses.passive = true
F.t = F.t + 0.3; B.tick(pawn)
check(gb.stops == 1 and rael.Controller == nil and has("B_RoyalGuard 4a1 stands still"), "passive: the Royal Guard Sister's tree stopped, her controller let go")
tune.bosses.passive = false
F.t = F.t + 0.3; B.tick(pawn)
check(gb.running and rael.Controller == gai and has("B_RoyalGuard 4a1 fights again"), "passive off: she fights again")
print(fails == 0 and "PASS" or "FAIL")
