-- The entity spawner (enemies.lua, F3 → Spawner): any NPC by CharacterTable ID, and what spawned
-- NPCs fight (hostile to Eve, to each other, or passive). The F3 tab appears with dev on only.
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
-- the CharacterTable's rows: the hostility fields at offsets (bIsHostile a byte here), DefaultEffectArray's names
local OFF = { DeadAlias = 0x10, MaxHP = 0x14, MaxShield = 0x18, DespawnTimeAfterDeath = 0x1c, DefaultEffectArray = 0x20,
  bApplyDamageWhenPlayerAlive = 0x24, bIsHostile = 0x28 }
local function f2u(v) return string.unpack("<I4", string.pack("<f", v)) end
local rowsMem = {
  M_SkullSword = { [0x10] = idx("M_SkullSword"), [0x14] = 1200, [0x18] = 300, [0x1c] = f2u(1.0), [0x24] = 1, [0x28] = 0,
    eff = { "Rank_Enemy", "M_SkullSword_Default" } },
  N_AirborneSquad = { [0x10] = idx("N_AirborneSquad"), [0x14] = 40000, [0x18] = 2000, [0x1c] = f2u(1.0), [0x24] = 0, [0x28] = 0,
    eff = { "Airborne_Default" } },
}
local function snapshot()
  local o = {}
  for r, m in pairs(rowsMem) do o[r] = { m[0x10], m[0x14], m[0x18], m[0x1c], table.concat(m.eff, ","), m[0x24], m[0x28] } end
  return o
end
local before = snapshot()
local function prop(nm, off, class, mask)
  return { GetFName = function() return F.fname(nm) end, GetOffset_Internal = function() return off end,
    GetClass = function() return { GetFName = function() return F.fname(class) end } end,
    GetFieldMask = function() if not mask then error("no mask") end; return mask end }
end
local rs = F.obj("SBCharacterTableProperty", "ScriptStruct")
rs.ForEachProperty = function(self, cb)
  cb(prop("DeadAlias", 0x10, "NameProperty"))
  cb(prop("MaxHP", 0x14, "IntProperty"))
  cb(prop("DefaultEffectArray", 0x20, "ArrayProperty"))
  cb(prop("bApplyDamageWhenPlayerAlive", 0x24, "BoolProperty"))
  cb(prop("bIsHostile", 0x28, "ByteProperty"))
end
F.objects["/Game/Local/Data/CharacterTable.CharacterTable"] = F.obj("CharacterTable", "DataTable", { RowStruct = rs })
local ers = F.obj("SBEffectTableProperty", "ScriptStruct")
ers.ForEachProperty = function(self, cb) cb(prop("ID", 0x0, "IntProperty")) end
F.objects["/Game/Local/Data/EffectTable.EffectTable"] = F.obj("EffectTable", "DataTable", { RowStruct = ers })
local effMem = { Passive_Immortal_Dispel = { [0x0] = 999 } }
local cmds = {}
local function command(s)
  cmds[#cmds + 1] = s
  local c = s:sub(1, 1)
  local f = {}
  for x in s:sub(2):gmatch("[^,]+") do f[#f + 1] = tonumber(x, 16) end
  local row = byIdx[f[3]]
  local m = rowsMem[row] or effMem[row]
  if not m then return "err no such row" end
  if c == "d" then
    local was = m[f[5]] or 0
    if f[6] then m[f[5]] = f[6] end
    return string.format("ok row %016x %016x %016x", 0x1234, was, m[f[5]] or 0)
  elseif c == "N" then
    local from, to, n = byIdx[f[6]], byIdx[f[8]], 0
    for i, nm in ipairs(m.eff or {}) do if nm == from then m.eff[i] = to; n = n + 1 end end
    return string.format("ok names %d of %d", n, #(m.eff or {}))
  end
  return "err ?"
end
local logs = {}
local function has(pat) for _, l in ipairs(logs) do if l:find(pat) then return true end end return false end
local tune = dofile("ue4ss/Mods/StellarBladeGore/Scripts/tune.lua")
tune.dev = true
tune.enemies.attackDown = false
tune.holdDown = false
tune.enemies.afterDeath.enabled = false
tune.enemies.pushScale = 2 -- the adoption part of the tick runs (the cuts stay off)
tune.enemies.cutChance = 0
local chars = {}
local spawned = {}
local preparedForce = nil -- what enemies.spawn passes as bosses.prepare's force
local pawn = F.obj("Eve", "CH_P_EVE_01_Blueprint_C", {
  K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end,
  GetControlRotation = function() return { Yaw = 0 } end,
})
local pc = F.obj("PC", "SBNetworkPlayerController", {
  ServerRequest_CreateActor = function(self, id, p, r) spawned[#spawned + 1] = { id = id, p = p }; return true end,
})
pawn.Controller = pc
local ctx = { tune = tune, log = function(s) logs[#logs + 1] = s; print("  | " .. s) end,
  try = function(f) local ok, r = pcall(f); if ok then return r end end, valid = function(x) return x ~= nil and x ~= false end,
  gore = { command = command, native_state = function() return "ready" end, busy = function() return false end },
  bosses = { prepare = function(k, force) preparedForce = force; return nil end,
    adopted = function() end, gone = function() end, tick = function() end,
    died = function() end, kinematic = function() end },
  live_chars = function() return chars end }
local E = dofile("ue4ss/Mods/StellarBladeGore/Scripts/enemies.lua")
E.init(ctx)
local function hos_now()
  for i = 1, 100 do local n, v = debug.getupvalue(E.hostile_tick, i); if not n then break end
    if n == "hos" and type(v) == "table" then v.next = 0; return end end
  error("no hos upvalue")
end
local function tick() E.tick(pawn, nil, function() end) end
local function brain()
  local st = { running = true, stops = 0, restarts = 0, montages = 0, movement = 0, unpossess = 0, possess = 0 }
  local props = {
    IsRunning = function() return st.running end,
    StopLogic = function() st.running, st.stops = false, st.stops + 1 end,
    RestartLogic = function() st.running, st.restarts = true, st.restarts + 1 end }
  local ctl = F.obj("AI", "SBAIController", props)
  local bb = F.obj("Brain", "SBBehaviorTreeComponent", props)
  ctl.BrainComponent = bb
  ctl.StopMovement = function() end
  ctl.UnPossess = function(self) st.unpossess = st.unpossess + 1; if self.pawn then self.pawn.Controller = nil end end
  ctl.Possess = function(self, pawn) st.possess = st.possess + 1; self.pawn = pawn; pawn.Controller = self end
  return ctl, bb, st
end
local function blackboard()
  local vals = {}
  local asset = F.obj("BBA", "BlackboardAsset", { Parent = nil })
  asset.Keys = { ForEach = function(self, cb)
    local i = 0
    for _, k in ipairs({ "Target", "Home" }) do
      i = i + 1
      cb(i, { get = function()
        return { EntryName = F.fname(k),
          KeyType = { IsValid = function() return true end,
            GetClass = function() return { GetFName = function() return F.fname("BlackboardKeyType_Object") end } end } }
      end })
    end
  end }
  local bb = F.obj("BB", "Blackboard", {
    BlackboardAsset = asset,
    GetValueAsObject = function(self, fn) return vals[fn.s] end,
    SetValueAsObject = function(self, fn, o) vals[fn.s] = o; return true end })
  return bb, vals
end
local function make_enemy(alias, cls, x, opts)
  opts = opts or {}
  local mesh = F.obj(alias .. "Mesh", "SkeletalMeshComponent", {
    IsSimulatingPhysics = function() return false end,
    GetSocketLocation = function() return { X = x, Y = 0, Z = 0 } end })
  local bb, vals = blackboard()
  local ctl, br, bst = brain()
  mesh.GetAnimInstance = function() return { Montage_Stop = function() bst.montages = bst.montages + 1 end } end
  ctl.Blackboard = bb
  local o = F.obj(alias .. "_1", cls, { Mesh = mesh, Controller = ctl,
    CharacterMovement = { StopMovementImmediately = function() bst.movement = bst.movement + 1 end },
    bActorIsBeingDestroyed = false,
    K2_GetActorLocation = function() return { X = x, Y = 0, Z = 0 } end })
  o.BrainComponent = br
  ctl.pawn = o
  if opts.brain == false then o.BrainComponent, ctl.BrainComponent = nil, nil end
  local c = { addr = o:GetAddress(), obj = o, cls = cls, k = "fake" }
  return c, o, vals, bst, ctl
end

-- the foldable groups: Naytiba, Angels, Bosses, Custom, then every other tribe in the table
local groups = E.pick_groups()
local gmap = {}
for _, gr in ipairs(groups) do gmap[gr.id] = gr end
check(#gmap.naytiba.members == 27 and #gmap.angels.members == 1 and #gmap.bosses.members == 5
  and #gmap.custom.members == 0, "curated groups (27 Naytiba, 1 angel, 5 bosses, Custom)")
local roster = E.roster()
check(#roster >= 600, "the full table roster (" .. #roster .. " rows)")
local tribeN, tribeGroups = 0, 0
for _, gr in ipairs(groups) do
  if gr.id:find("^tribe_") then tribeGroups = tribeGroups + 1; tribeN = tribeN + #gr.members end
end
check(tribeGroups >= 10 and tribeN > 600, tribeGroups .. " tribe groups, " .. tribeN .. " roster NPCs")
check(E.pick_kind("SD_N_TachyNPC_01").id == 62002000, "a roster row resolves by alias")
check(E.pick_kind("M_SkullSwordAlone").id == 50173, "a roster variant resolves by alias")
check(E.portrait("B_Tachy") == "/Game/Art/UI/Texture/Album/NPC/image/CH_NPC_TachyNPC.CH_NPC_TachyNPC", "Tachy uses the known album object")
check(E.portrait("B_Scarlet"):match("^/Game/DLC_2/.+%.CH_NPC_Scarlet$") ~= nil, "Scarlet uses the DLC album object")
check(E.portrait("B_RoyalGuard"):match("/NPC/image/CH_NPC_Rael%.CH_NPC_Rael$"), "Royal Guard uses Rael's album")
check(E.portrait("M_SkullSword"):match("/Native/image/CH_M_NA_17%.CH_M_NA_17$"), "monster album path")
check(E.portrait("M_StatueB"):match("/Native/image/CH_M_NA_40_Type_B%.CH_M_NA_40_Type_B$"), "statue variant album path")
check(E.portrait("M_LurkerB"):match("/Native/image/CH_M_NA_45%.CH_M_NA_45$"), "lurker variant shares album art")
check(E.portrait("M_ClriketB"):match("/Native/image/CH_M_NA_03%.CH_M_NA_03$"), "_BP assets share the monster album art")
check(E.portrait("N_AirborneSquad") ~= nil, "the angel keeps an album candidate (verified in game)")
for _, group in ipairs(groups) do
  for _, member in ipairs(group.members) do
    local k = E.pick_kind(member.alias)
    spawned = {}; preparedForce = nil
    tune.spawner.pick = member.alias
    E.spawn_pick(pawn)
    check(#spawned == 1 and spawned[1].id == k.id and (not k.row or preparedForce == true), "spawn request for " .. member.alias)
    local path = E.portrait(member.alias)
    check(not path or path:match("^/Game/.+/([^/]+)%.%1$"), "portrait object path or fallback for " .. member.alias)
  end
end
check(E.pick_kind("M_SkullSword").id == 50170, "a known kind picked by alias")
check(E.pick_kind("B_Tachy").id == 50210, "a boss picked by alias too")
check(E.pick_kind("nope") == nil, "an unknown pick is nothing")
tune.spawner.pick, tune.spawner.id = "custom", 0
check(E.pick_kind("custom") == nil, "Custom ID with id 0 is nothing (told, not spawned)")
-- a boss from the Spawner: forced mortal, no Boss Spawning toggle needed
preparedForce = nil
tune.spawner.pick, tune.spawner.id = "B_Tachy", 0
logs, spawned = {}, {}
E.spawn_pick(pawn)
check(#spawned == 1 and spawned[1].id == 50210 and preparedForce == true, "a boss spawn forces its row mortal")

-- F5 spawns the pick, in front of her
tune.spawner.pick, tune.spawner.id, tune.spawner.count = "M_SkullSword", 0, 1
logs, spawned = {}, {}
E.spawn_pick(pawn)
check(#spawned == 1 and spawned[1].id == 50170, "F5 spawns the pick (CharacterTable 50170)")
check(math.floor(spawned[1].p.X) == 450, "in front of her (" .. tostring(math.floor(spawned[1].p.X)) .. " cm)")
tune.spawner.count = 3
E.spawn_pick(pawn)
check(#spawned == 4, "Spawn Count 3 sends three (F3 → Spawner)")
tune.spawner.count = 1
E.next_pick()
check(tune.spawner.pick == "M_SkullSpear", "Insert picks the next (" .. tostring(tune.spawner.pick) .. ")")
-- Insert cycles within the pick's group (the full roster made one long cycle useless)
tune.spawner.pick = "M_LurkerB"
E.next_pick()
check(tune.spawner.pick == "M_SkullJuggernaut", "Insert steps into the new kinds (Lurker B -> Skull juggernaut)")
tune.spawner.pick = "M_StatueD"
E.next_pick()
check(tune.spawner.pick == "M_Marionette", "Insert steps into the new kind (Statue D -> Marionette)")
tune.spawner.pick = "M_Marionette"
E.next_pick()
check(tune.spawner.pick == "M_SkullSword", "Insert wraps within the group (Marionette -> Skull sword)")
tune.spawner.pick = "M_SkullSword"
-- portrait candidates: known art, native fallback, alias fallbacks for roster rows
local paths = E.portrait_paths("M_SkullSword")
check(paths[1]:match("/Native/image/CH_M_NA_17%.CH_M_NA_17$") ~= nil, "the monster album path first")
local rpaths = E.portrait_paths("M_SkullSwordAlone")
check(#rpaths >= 2 and rpaths[#rpaths]:match("M_SkullSwordAlone$") ~= nil, "a roster row falls back to alias album paths")

-- any NPC by its CharacterTable ID
E.remove_spawned() -- discard the earlier unfulfilled requests before testing proximity
tune.spawner.pick, tune.spawner.id = "custom", 12345
local existing = make_enemy("Existing", "CH_M_XX_99_Blueprint_C", 450)
chars = { existing }
logs, spawned = {}, {}
E.spawn_pick(pawn)
check(#spawned == 1 and spawned[1].id == 12345, "Custom ID spawns any CharacterTable ID (12345)")
tick()
check(E.entry(existing.addr) == nil, "a character present before the request is not adopted by proximity")
-- an unknown class near the request is it (its Blueprint is in no kinds)
local cc, cobj = make_enemy("Custom", "CH_M_XX_99_Blueprint_C", 450)
chars = { cc }
tick()
local adopted = E.entry(cc.addr)
check(adopted ~= nil and adopted.kind.alias == "ID_12345" and adopted.kind.custom == true, "the unknown class adopted as the custom kind")
E.remove_spawned()
chars = {}
check(has("removed 1 spawned enemies"), "Remove all takes the custom spawn too")

-- Eve herself by a spawn point is never adopted as the spawn
tune.spawner.pick, tune.spawner.id = "custom", 12345
E.spawn_pick(pawn)
chars = { { addr = pawn:GetAddress(), obj = pawn, cls = "CH_P_EVE_01_Blueprint_C", k = "fake" } }
tick()
check(E.entry(pawn:GetAddress()) == nil, "Eve standing by the spawn point is not the spawn")
chars = {}

-- a roster row without a Blueprint: adopted by proximity, tracked, never cut
tune.spawner.pick, tune.spawner.id = "M_SkullSwordAlone", 0
E.spawn_pick(pawn)
local rc, robj = make_enemy("Roster", "CH_M_XX_99_Blueprint_C", 450)
chars = { rc }
tick()
local rad = E.entry(rc.addr)
check(rad ~= nil and rad.kind.alias == "M_SkullSwordAlone" and rad.kind.roster == true, "the roster kind adopted by proximity")
E.remove_spawned()
chars = {}

-- Spawn tracking is independent of the gore and push switches.
tune.enemies.enabled, tune.enemies.pushScale, tune.enemies.push = false, 1, 0
tune.spawner.pick = "M_SkullSword"
E.spawn_pick(pawn)
local nc = make_enemy("NoGore", "CH_M_NA_17_Blueprint_C", 450)
chars = { nc }; tick()
check(E.entry(nc.addr) ~= nil, "spawn adopted with gore and pushes off")
E.remove_spawned(); chars = {}
tune.enemies.enabled, tune.enemies.pushScale = true, 2

-- hostile: the angel's row made hostile and damageable, its target kept on Eve
tune.spawner.pick, tune.spawner.id, tune.spawner.hostile, tune.spawner.infight = "N_AirborneSquad", 0, "hostile", false
logs = {}
E.spawn_pick(pawn)
local ac, aobj, avals, abst, actl = make_enemy("Angel", "CH_NPC_AirborneSquad_C", 450)
chars = { ac }
tick()
hos_now()
tick()
check(rowsMem.N_AirborneSquad[0x24] == 1 and rowsMem.N_AirborneSquad[0x28] == 1, "the angel's row damageable and hostile")
check(has("N_AirborneSquad's row hostile"), "the row patch logged")
check(avals.Target == pawn, "its blackboard target kept on Eve")
-- infight: two spawns target each other
tune.spawner.pick = "M_SkullSword"
E.spawn_pick(pawn)
local sc, sobj, svals = make_enemy("Skull", "CH_M_NA_17_Blueprint_C", 550)
chars = { ac, sc }
tune.spawner.infight = true
hos_now()
tick()
hos_now()
tick()
check(avals.Target == sobj and svals.Target == aobj, "infight: spawned NPCs target each other")
-- passive: their AI stopped
tune.spawner.hostile, tune.spawner.infight = "passive", false
tune.dev = false
hos_now()
tick()
check(abst.stops == 1 and abst.unpossess == 1 and abst.montages == 1 and abst.movement == 1 and not aobj.Controller, "passive without dev: stopped and unpossessed")
abst.running = true
hos_now(); tick()
check(abst.stops == 2 and abst.montages == 2, "passive stops a restarted brain and montage again")
actl:Possess(aobj)
hos_now(); tick()
check(not aobj.Controller and abst.unpossess == 2 and abst.montages == 3, "passive releases a repossessed NPC again")
-- back to game: rows put back exactly, AI started again
tune.spawner.hostile = "game"
hos_now()
tick()
local after = snapshot()
local same = true
for r, w in pairs(before) do for i = 1, 7 do if after[r][i] ~= w[i] then same = false; print("  " .. r .. " field " .. i) end end end
check(same, "none hostile left: rows put back exactly as the game had them")
check(next(E.hostile_rows()) == nil, "no rows left patched")
check(abst.restarts == 1 and aobj.Controller == actl and abst.possess == 2, "its controller and tree restored")
tune.dev = true

-- a row without bIsHostile: damageable, the gap told, the byte untouched
rs.ForEachProperty = function(self, cb)
  cb(prop("DeadAlias", 0x10, "NameProperty"))
  cb(prop("bApplyDamageWhenPlayerAlive", 0x24, "BoolProperty"))
end
tune.spawner.hostile = "hostile"
logs = {}
hos_now()
tick()
hos_now()
tick()
check(rowsMem.N_AirborneSquad[0x24] == 1 and rowsMem.N_AirborneSquad[0x28] == 0
  and has("row hostile while one spawned here is up: damageable"), "a row without bIsHostile: damageable, told, the byte left alone")
E.remove_spawned()
chars = {}
hos_now()
tick()
tune.spawner.hostile = "game"

-- a roster kill without a Blueprint: tracked, ragdolled, never cut
tune.enemies.cutChance = 1
tune.spawner.pick, tune.spawner.id = "SD_N_TachyNPC_01", 0
logs = {}
E.spawn_pick(pawn)
local dc, dobj = make_enemy("Dummy", "CH_M_XX_99_Blueprint_C", 450)
chars = { dc }
tick()
local simmed = false
dobj.Mesh.IsSimulatingPhysics = function() simmed = true; return true end
dobj.Mesh.IsVisible = function() return true end
hos_now()
tick()
check(E.entry(dc.addr) ~= nil and E.entry(dc.addr).dead == true, "the roster NPC dies as a ragdoll")
hos_now()
tick()
check(has("SD_N_TachyNPC_01 " .. string.format("%x", dc.addr) .. ": left whole %(no Blueprint to cut by%)"),
  "a kill with no Blueprint to follow: tracked, left whole")
tune.enemies.cutChance = 0
E.remove_spawned()
chars = {}
hos_now()
tick()

-- the F3 tab: no dev gate, foldable groups, the Sandbox merge, avatars, the Spawn button
ctx.enemies = E
local gui = dofile("ue4ss/Mods/StellarBladeGore/Scripts/gui.lua")
gui.init({ tune = tune, log = function() end, try = function(f) local ok, r = pcall(f); if ok then return r end end,
  valid = function(o) return o ~= nil end, enemies = E })
-- the menu before the spawner loads: its static rows stay under the section, nothing breaks
local gui2 = dofile("ue4ss/Mods/StellarBladeGore/Scripts/gui.lua")
gui2.init({ tune = tune, log = function() end, try = function(f) local ok, r = pcall(f); if ok then return r end end,
  valid = function(o) return o ~= nil end })
local function tab2(name)
  for _, r in ipairs(gui2.ROWS) do if r.section == name then return true end end
  return false
end
check(tab2("Spawner") and not tab2("Sandbox"), "spawner-first menu: Spawner tab, no Sandbox, no crash")
local function tab(name)
  for _, r in ipairs(gui.ROWS) do if r.section == name then return true end end
  return false
end
local function row(key)
  for _, r in ipairs(gui.ROWS) do if r.key == key then return r end end
end
local function group(id)
  for _, r in ipairs(gui.ROWS) do if r.group == id then return r end end
end
local function select(alias)
  for _, r in ipairs(gui.ROWS) do if r.select == alias then return r end end
end
tune.dev = true
gui.refresh()
check(tab("Spawner"), "the Spawner tab with dev on")
check(not tab("Sandbox"), "no Sandbox tab: the boss spawner merged in")
check(group("naytiba") ~= nil and group("naytiba").kind == "group", "a Naytiba group header")
check(group("naytiba").label:find("27"), "the header counts its NPCs (" .. tostring(group("naytiba").label) .. ")")
tune.spawner.collapsed = { naytiba = false } -- one group at a time
gui.refresh()
check(select("M_SkullSword") ~= nil and select("N_AirborneSquad") == nil, "only the chosen group opens")
check(select("M_SkullSword").label == "  Skull, sword", "select rows show the NPC's label")
tune.spawner.collapsed = { bosses = false }; gui.refresh()
check(row("bosses.enabled") ~= nil and row("bosses.enabled").ingroup == "bosses", "boss tuning under the Bosses group")
tune.spawner.collapsed = { custom = false }; gui.refresh()
check(row("spawner.id") ~= nil and row("spawner.id").ingroup == "custom", "Custom ID under the Custom group")
check(row("spawner.hostile") ~= nil and row("enemies.spawn_pick") == nil, "settings and buttons outside the groups")
local spawnedHere = false
for _, r in ipairs(gui.ROWS) do
  if r.call == "enemies.spawn_pick" or r.call == "enemies.remove_spawned" or r.call == "enemies.kill_nearest" then
    spawnedHere = true
  end
end
check(spawnedHere, "Spawn, Remove Spawned and Kill Nearest buttons")
-- folding a group hides its NPCs; the selection stays on the header
tune.spawner.collapsed = { naytiba = false }; gui.refresh()
local idx = nil
for i, r in ipairs(gui.ROWS) do if r.select == "M_SkullSword" then idx = i break end end
gui.state.sel = idx
tune.spawner.collapsed = { naytiba = true }
gui.refresh()
check(select("M_SkullSword") == nil and group("naytiba") ~= nil, "folded: the group's NPCs hidden, its header stays")
check(gui.ROWS[gui.state.sel].group == "naytiba", "the selection stays on the folded group's header")
-- fresh state: everything folded; unfolding one folds the rest (accordion, saved)
tune.spawner.collapsed = nil
gui.refresh()
local folded, headers = true, 0
for _, r in ipairs(gui.ROWS) do
  if r.select then folded = false end
  if r.group then headers = headers + 1 end
end
check(folded and headers == #groups, "first open: every group folded (" .. headers .. " headers)")
tune.spawner.collapsed = { unknown = false, bosses = false, custom = false }
gui.refresh()
check(select("B_Tachy") ~= nil and select("custom") == nil, "unknown and multiple open groups normalize to one")
tune.spawner.collapsed = { naytiba = false, angels = true, bosses = true, custom = true }
gui.refresh()
check(select("M_SkullSword") ~= nil and select("N_AirborneSquad") == nil, "one group open at a time")
tune.spawner.collapsed = { naytiba = false }
gui.refresh()
check(select("M_SkullSword") ~= nil, "unfolded: the NPCs back")
tune.dev = false
gui.refresh()
check(not tab("Spawner"), "no Spawner tab with dev off: gated again")
check(row("spawner.count") == nil and row("spawner.hostile") == nil and row("spawner.infight") == nil, "no spawner settings with dev off")
local leaked = false
for _, r in ipairs(gui.ROWS) do
  if r.call == "enemies.spawn_pick" or r.call == "enemies.remove_spawned" or r.call == "enemies.kill_nearest" then leaked = true end
end
check(not leaked, "no spawner buttons with dev off (nothing leaks into Gameplay)")
tune.dev = true
gui.refresh()
check(tab("Spawner"), "the Spawner tab back with dev on")
check(gui.dimmed(row("spawner.infight")), "Fight Each Other dims unless Hostile to Eve")
tune.spawner.hostile = "hostile"
check(not gui.dimmed(row("spawner.infight")), "Fight Each Other brightens with Hostile to Eve")
tune.spawner.hostile = "game"
-- the spawner keys need dev again
local K = dofile("ue4ss/Mods/StellarBladeGore/Scripts/keys.lua")
K.init({ tune = tune, log = function() end })
local gated = 0
for _, a in ipairs(K.ACTIONS) do
  if a.dev and (a.id == "spawn" or a.id == "nextEnemy" or a.id == "spawner" or a.id == "kill") then gated = gated + 1 end
end
check(gated == 4, "spawn, next, window and kill need dev")
tune.spawner.pick, tune.spawner.id = "M_SkullSword", 0
logs, spawned = {}, {}
local ok, err = pcall(function()
  local m, f = ("enemies.spawn_pick"):match("^(%w+)%.([%w_]+)$")
  ctx[m][f](pawn)
end)
check(ok and #spawned == 1 and spawned[1].id == 50170, "the Spawn button spawns the pick")
for _, e in ipairs(F.errors) do print("hook error: " .. e) end
check(#F.errors == 0, "no engine simulation errors")
print(fails == 0 and "PASS" or "FAIL")
