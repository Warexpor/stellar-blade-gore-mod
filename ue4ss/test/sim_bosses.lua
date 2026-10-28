-- Sandbox Bosses (bosses.lua): a boss's CharacterTable row made mortal while one spawned here is up, and put back
-- exactly as the game had it once none is; the boss bar held at its floor and hit again takes it down; its death gets
-- a face and a struggle of its own (a fresh struggle.lua) that ticks without error; off, nothing is changed
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
local function command(s)
  cmds[#cmds + 1] = s
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
F.classes["WB_MainHUD_EnemyInfo_C"] = { hud }
F.t = F.t + 1; B.tick(pawn)
check(#kills == 0, "its bar at 0.40: up")
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

-- its death: face and struggle
B.died(pawn, 0xb055, e)
check(B._dead()[0xb055] ~= nil and B._dead()[0xb055].struggle ~= nil, "its death: a struggle of its own")
for _ = 1, 40 do F.t = F.t + 0.05; B.tick(pawn) end
check(has("face started"), "its dead face started")
check(B._dead()[0xb055] and B._dead()[0xb055].struggle ~= nil and not has("struggle: .*:%d+:"), "its struggle ticks without error")

-- gone: the rows put back after 15 s, exactly
B.gone(0xb055, e)
for _ = 1, 20 do F.t = F.t + 1; B.tick(pawn) end
local after = snapshot()
local same = true
for r, v in pairs(before) do for i = 1, 5 do if after[r][i] ~= v[i] then same = false; print("  " .. r .. " field " .. i .. ": " .. tostring(v[i]) .. " -> " .. tostring(after[r][i])) end end end
check(same, "none left: both rows put back as the game had them")
check(next(B._rows()) == nil, "nothing left to put back")

print(fails == 0 and "PASS" or "FAIL")
