-- Buried keep-angel-bodies toggle (tune.enemies.keepAngelBodies): a dead Airborne Squad angel's
-- CharacterTable row is held at a long despawn while one lies, and put back exactly after. Wiring: the
-- enemies' watch engages bosses.keep_despawn on the first kept death and releases it once none is left.
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
local function f2u(v) return string.unpack("<I4", string.pack("<f", v)) end
local function u2f(u) return string.unpack("<f", string.pack("<I4", u & 0xffffffff)) end
-- the table: one float field that matters here
local OFF = { DespawnTimeAfterDeath = 0x1c }
local rowsMem = {
  N_AirborneSquad = { [0x1c] = f2u(1.0) },
  LongLived = { [0x1c] = f2u(7200.0) },
  M_SkullSword = { [0x1c] = f2u(5.0) },
}
local function snapshot()
  local o = {}
  for r, m in pairs(rowsMem) do o[r] = m[0x1c] end
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
local native, cmds, failWrite = "ready", {}, false
local function command(s)
  cmds[#cmds + 1] = s
  local f = {}
  for x in s:sub(2):gmatch("[^,]+") do f[#f + 1] = tonumber(x, 16) end
  local row = byIdx[f[3]]
  local m = rowsMem[row]
  if not m then return "err no such row" end
  if f[6] and failWrite then return "err injected write failure" end
  local was = m[f[5]] or 0
  if f[6] then m[f[5]] = f[6] end
  return string.format("ok row %016x %016x %016x", 0x1234, was, m[f[5]] or 0)
end
local logs = {}
local tune = dofile("ue4ss/Mods/StellarBladeGore/Scripts/tune.lua")
local ctx = { tune = tune, log = function(s) logs[#logs + 1] = s; print("  | " .. s) end,
  try = function(f) local ok, r = pcall(f); if ok then return r end end,
  valid = function(x) return x ~= nil and x ~= false end,
  gore = { command = command, native_state = function() return native end } }
local B = dofile("ue4ss/Mods/StellarBladeGore/Scripts/bosses.lua")
B.init(ctx)
local function has(pat) for _, l in ipairs(logs) do if l:find(pat, 1, true) then return true end end return false end

-- off: nothing written
check(B.keep_despawn("N_AirborneSquad", 3600) == nil, "held while a body lies")
check(rowsMem.N_AirborneSquad[0x1c] == f2u(3600), "its despawn held at 3600 s (was 1)")
check(has("kept on the ground"), "told in the log")
-- held twice, released once: still held
check(B.keep_despawn("N_AirborneSquad", 3600) == nil, "a second body: still held, nothing more written")
B.unkeep_despawn("N_AirborneSquad", "test")
check(rowsMem.N_AirborneSquad[0x1c] == f2u(3600), "one of two gone: still held")
B.unkeep_despawn("N_AirborneSquad", "no kept bodies left")
local same = true
for r, v in pairs(before) do if rowsMem[r][0x1c] ~= v then same = false end end
check(same and has("despawn put back as the game has it"), "none left: put back exactly as the game had it")
check(next(B._keeps()) == nil, "nothing left to put back")
-- unknown row: an error, nothing written
local n0 = #cmds
check(B.keep_despawn("N_NoSuchRow", 3600) ~= nil, "unknown row: an error, not held")
check(#cmds == n0 + 1 and rowsMem.N_AirborneSquad[0x1c] == before.N_AirborneSquad, "unknown row: nothing else written")
-- an already-long row: held as it is, no write
n0 = #cmds
check(B.keep_despawn("LongLived", 3600) == nil, "an already-long row: held as it is")
check(rowsMem.LongLived[0x1c] == f2u(7200.0) and has("already despawns after"), "no write, told")
B.unkeep_despawn("LongLived", "test")
check(rowsMem.LongLived[0x1c] == f2u(7200.0), "released untouched")
check(B.keep_despawn("N_AirborneSquad", 3600) == nil, "held for restore retry")
failWrite = true
check(B.unkeep_despawn("N_AirborneSquad", "test") ~= nil and B._keeps().N_AirborneSquad,
  "failed restore retains its original value and hold record")
failWrite = false
check(B.unkeep_despawn("N_AirborneSquad", "retry") == nil and rowsMem.N_AirborneSquad[0x1c] == before.N_AirborneSquad,
  "retry restores the exact original value")
check(B.keep_despawn("N_AirborneSquad", 3600) == nil, "held before a failed restore and new keeper")
failWrite = true
check(B.unkeep_despawn("N_AirborneSquad", "test") ~= nil, "restore failure recorded")
failWrite = false
check(B.keep_despawn("N_AirborneSquad", 3600) == nil, "new keeper adopts the pending hold")
check(B.unkeep_despawn("N_AirborneSquad", "last keeper") == nil and rowsMem.N_AirborneSquad[0x1c] == before.N_AirborneSquad,
  "one release restores after a pending hold is adopted")
-- sbslice down: an error, nothing written
native = "booting"
n0 = #cmds
check(B.keep_despawn("N_AirborneSquad", 3600) ~= nil, "sbslice down: an error")
check(#cmds == n0, "sbslice down: nothing written")
native = "ready"
-- a hold outstanding at a level reload: released
check(B.keep_despawn("N_AirborneSquad", 3600) == nil, "held again")
check(B.keep_despawn("N_AirborneSquad", 3600) == nil, "second hold before level reload")
B.forget()
same = true
for r, v in pairs(before) do if rowsMem[r][0x1c] ~= v then same = false end end
check(same and next(B._keeps()) == nil, "level reloaded: released and put back")
check(B.keep_despawn("N_AirborneSquad", 3600) == nil, "held before reload restore failure")
failWrite = true
B.forget()
check(B._keeps().N_AirborneSquad ~= nil, "failed reload restore retains the original value")
failWrite = false
F.t = F.t + 5.1; B.tick(nil)
check(rowsMem.N_AirborneSquad[0x1c] == before.N_AirborneSquad and not B._keeps().N_AirborneSquad,
  "failed reload restore is retried without another keeper")
check(B.keep_despawn("N_AirborneSquad", 3600) == nil, "held before reload and replacement keeper")
failWrite = true
B.forget()
failWrite = false
check(B.keep_despawn("N_AirborneSquad", 3600) == nil, "new keeper adopts a failed reload restore")
F.t = F.t + 5.1; B.tick(nil)
check(rowsMem.N_AirborneSquad[0x1c] == f2u(3600), "retry does not release the replacement keeper")
B.unkeep_despawn("N_AirborneSquad", "last keeper")
check(rowsMem.N_AirborneSquad[0x1c] == before.N_AirborneSquad, "replacement keeper releases normally")

-- ---- the enemies' wiring: the first kept death holds the row, the last going releases it ----
local keepCalls, unkeepCalls, failRestore = {}, {}, false
local chars = {}
local function v(x, y, z) return { X = x, Y = y, Z = z } end
local ctx2 = { tune = tune, log = ctx.log, try = ctx.try, valid = ctx.valid,
  live_chars = function() return chars end,
  char_at = function(e) return v(100, 0, 100) end,
  keep = function(o) return { obj = o } end, held = function() return true end,
  newobj = { watch = function() end },
  bosses = {
    tick = function() end, adopted = function() end, died = function() end,
    is_passive = function() return false end,
    keep_despawn = function(row, secs) keepCalls[#keepCalls + 1] = { row, secs }; return nil end,
    unkeep_despawn = function(row, why) unkeepCalls[#unkeepCalls + 1] = { row, why }; if failRestore then return "injected" end end,
  } }
local E = dofile("ue4ss/Mods/StellarBladeGore/Scripts/enemies.lua")
E.init(ctx2)
tune.enemies.keepAngelBodies = true
local sim, vis = false, true
local mesh = F.obj("AngelMesh", "SkeletalMeshComponent")
mesh.IsSimulatingPhysics = function(_, b) return sim and tostring(b) == "Bip001-Pelvis" end
mesh.GetSocketLocation = function() return v(100, 0, 100) end
mesh.IsVisible = function() return vis end
local angel = F.obj("CH_NPC_AirborneSquad_C_1", "CH_NPC_AirborneSquad_C",
  { Mesh = mesh, bActorIsBeingDestroyed = false })
angel.K2_GetActorLocation = function() return v(100, 0, 100) end
local pawn = F.obj("Eve", "CH_P_EVE_01_Blueprint_C")
pawn.K2_GetActorLocation = function() return v(0, 0, 100) end
local herMesh = F.obj("EveMesh", "SkeletalMeshComponent")
chars[1] = { obj = angel, addr = angel:GetAddress(), cls = "CH_NPC_AirborneSquad_C" }
F.t = F.t + 0.1; E.tick(pawn, herMesh)
check(#keepCalls == 0, "alive: nothing held")
sim = true
F.t = F.t + 0.1; E.tick(pawn, herMesh)
check(#keepCalls == 1 and keepCalls[1][1] == "N_AirborneSquad" and keepCalls[1][2] == 3600,
  "the first kept death holds the row at 3600 s")
F.t = F.t + 0.1; E.tick(pawn, herMesh)
check(#keepCalls == 1 and #unkeepCalls == 0, "still lying: held once, not released")
tune.enemies.keepAngelBodies = false
failRestore = true
F.t = F.t + 0.1; E.tick(pawn, herMesh)
check(#unkeepCalls == 1 and unkeepCalls[1][1] == "N_AirborneSquad", "toggled off: restore attempted")
failRestore = false
F.t = F.t + 5.1; E.tick(pawn, herMesh)
check(#unkeepCalls == 2, "failed restore is retried")
tune.enemies.keepAngelBodies = true
F.t = F.t + 0.1; E.tick(pawn, herMesh)
check(#keepCalls == 2, "toggled back on with it still lying: held again")
vis = false
F.t = F.t + 0.1; E.tick(pawn, herMesh)
check(#unkeepCalls == 3, "its body gone: released")
E.forget()

-- A story actor may be observed before its body mesh is assigned. Retry the classification.
local storyMesh = F.obj("StoryMesh", "SkeletalMeshComponent")
storyMesh.IsSimulatingPhysics = function() return false end
storyMesh.GetSocketLocation = function() return v(100, 0, 100) end
storyMesh.IsVisible = function() return true end
local story = F.obj("StoryAngel", "CH_NPC_Story_C", { Mesh = storyMesh, bActorIsBeingDestroyed = false })
story.K2_GetActorLocation = function() return v(100, 0, 100) end
chars[1] = { obj = story, addr = story:GetAddress(), cls = "CH_NPC_Story_C" }
F.t = F.t + 0.1; E.tick(pawn, herMesh)
check(not has("Eve-bodied story angel"), "unassigned body is not classified as an angel")
local bodyReady = false
storyMesh.SkeletalMesh = F.obj("CH_P_EVE_01_Body", "SkeletalMesh", {
  GetFName = function() if bodyReady then return F.fname("CH_P_EVE_01_Body") end end,
  GetFullName = function() if bodyReady then return "CH_P_EVE_01_Body" end end,
})
F.t = F.t + 0.1; E.tick(pawn, herMesh)
check(not has("Eve-bodied story angel"), "an unreadable body name is not cached as a non-angel")
bodyReady = true
F.t = F.t + 0.1; E.tick(pawn, herMesh)
check(has("Eve-bodied story angel"), "story angel is classified after its body arrives")
E.forget()
local otherMesh = F.obj("OtherMesh", "SkeletalMeshComponent", { SkeletalMesh = F.obj("OtherBody", "SkeletalMesh") })
story.Mesh = otherMesh
chars[1] = { obj = story, addr = story:GetAddress(), cls = "CH_NPC_Other_C" }
F.t = F.t + 0.1; E.tick(pawn, herMesh)
chars[1] = nil
F.t = F.t + 0.1; E.tick(pawn, herMesh)
story.Mesh = storyMesh
chars[1] = { obj = story, addr = story:GetAddress(), cls = "CH_NPC_Reused_C" }
local count = #logs
F.t = F.t + 0.1; E.tick(pawn, herMesh)
local followed = false
for i = count + 1, #logs do if logs[i]:find("Eve-bodied story angel", 1, true) then followed = true end end
check(followed, "a vanished non-angel's reused address can be classified as an angel")
E.forget()

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
check(#F.errors == 0, "no errors (" .. table.concat(F.errors, "; ") .. ")")
print(fails == 0 and "PASS" or "FAIL")
