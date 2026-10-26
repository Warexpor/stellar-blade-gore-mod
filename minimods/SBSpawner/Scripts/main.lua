-- SBSpawner: the Stellar Blade Gore mod's enemy spawner on its own, for a game without the gore mod.
--   F5        spawns the kind picked, SPAWN_DISTANCE cm in front of Eve, facing her
--   Insert    picks the next kind (the log and the window's toast say which)
--   Home      shows or hides the spawner window (SBSpawnerWindow's DLL): Spawn, Spawn 3, Remove all, Kill nearest
--   End       kills the spawned enemy nearest her (the game's own death)
--   Backspace removes every enemy spawned here
-- Spawning goes through the game's SBNetworkPlayerController:ServerRequest_CreateActor (a CharacterTable ID, a
-- position, a rotation), which runs locally in single player. All of it runs from Eve's own ReceiveTick (actor ticks
-- are on the game thread: this game has no engine tick for UE4SS to hook, and ExecuteInGameThread may run on a worker).
-- The window and this script talk through files in this folder (spawner.list, .cmd, .req, .state: spawner.c).
local VERSION = "1.0.0"
local DIR = "ue4ss/Mods/SBSpawner/"
local LIST, CMD, REQ, STATE, LOG = DIR .. "spawner.list", DIR .. "spawner.cmd", DIR .. "spawner.req", DIR .. "spawner.state", DIR .. "sbspawner.log"
local TICK_FN = "/Game/Art/Character/PC/CH_P_EVE_01/Blueprints/CH_P_EVE_01_Blueprint.CH_P_EVE_01_Blueprint_C:ReceiveTick"
local SPAWN_DISTANCE, SPAWN_SPREAD, SPAWN_LIFT = 450, 160, 30

-- alias (CharacterTable row), id (its ID), label. Any CharacterTable ID can be added here
local KINDS = {
  { alias = "M_SkullSword", label = "Skull, sword", id = 50170 },
  { alias = "M_SkullSpear", label = "Skull, spear", id = 50180 },
  { alias = "M_SkullHammer", label = "Skull, hammer", id = 50160 },
  { alias = "M_SkullGunner", label = "Skull, gunner", id = 50190 },
  { alias = "M_LabMutant", label = "Lab mutant", id = 50350 },
  { alias = "M_StatueA", label = "Statue A", id = 50400 },
  { alias = "M_StatueB", label = "Statue B", id = 50401 },
  { alias = "M_StatueC", label = "Statue C", id = 50402 },
  { alias = "M_LurkerA", label = "Lurker A", id = 50450 },
  { alias = "M_LurkerB", label = "Lurker B", id = 50452 },
  { alias = "N_AirborneSquad", label = "Airborne Squad angel", id = 30030 },
}

local lg = io.open(LOG, "w")
local function log(s)
  local line = string.format("[%s] %s\n", os.date("%H:%M:%S"), s)
  if lg then lg:write(line); lg:flush() end
  print("[SBSpawner] " .. s .. "\n")
end
local function try(f) local ok, r = pcall(f); if ok then return r end end
local function valid(o) return o ~= nil and try(function() return o:IsValid() end) == true end
local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local function vof(v) return v and vec(v.X, v.Y, v.Z) or nil end
local function dist(a, b) local x, y, z = a.X - b.X, a.Y - b.Y, a.Z - b.Z; return math.sqrt(x * x + y * y + z * z) end

local pick = 1
local pending = {}  -- keys pressed (UE4SS's input thread), run on her tick
local expect = {}   -- { at, t }: spawns asked for, waiting for their actor
local born = {}     -- characters made since (NotifyOnNewObject), matched to a request once placed
local mine = {}     -- address -> actor: spawned here
local freed = false -- the mouse given to the window
local pawn, pawnAddr, pawnSeen = nil, nil, 0

local function toast(s)
  local f = io.open(CMD, "w")
  if f then f:write("toast\t" .. s); f:close() end
end
local function write_list()
  local f = io.open(LIST, "w")
  if not f then return end
  for i, k in ipairs(KINDS) do f:write(string.format("%s\t%d. %s\n", k.alias, i, k.label)) end
  f:close()
end

local function controller()
  local pc = try(function() return pawn.Controller end)
  if valid(pc) then return pc end
  pc = try(function() return FindFirstOf("SBNetworkPlayerController") end)
  return valid(pc) and pc or nil
end

-- count of kind k, in a row across in front of her, facing her
local function spawn(k, count)
  local pc = controller()
  if not pc then log("spawn: no player controller"); return end
  local at = try(function() return vof(pawn:K2_GetActorLocation()) end)
  local rot = try(function() return pawn:GetControlRotation() end)
  if not at then log("spawn: no Eve location"); return end
  local yaw = math.rad(rot and rot.Yaw or 0)
  local fx, fy, rx, ry = math.cos(yaw), math.sin(yaw), -math.sin(yaw), math.cos(yaw)
  local sent = 0
  for i = 1, count do
    local off = (i - (count + 1) / 2) * SPAWN_SPREAD
    local p = vec(at.X + fx * SPAWN_DISTANCE + rx * off, at.Y + fy * SPAWN_DISTANCE + ry * off, at.Z + SPAWN_LIFT)
    local ok, err = pcall(function()
      pc:ServerRequest_CreateActor(k.id, p, { Pitch = 0, Yaw = math.deg(yaw) + 180, Roll = 0 }, false, true, 0, 0, 0, FName("None"), false)
    end)
    if ok then sent = sent + 1; expect[#expect + 1] = { at = p, t = os.clock() }
    else log(string.format("spawn %s: ServerRequest_CreateActor failed: %s", k.alias, tostring(err))) end
  end
  log(string.format("spawn: %d %s (CharacterTable %d) asked for, %d sent", count, k.alias, k.id, sent))
end

-- the characters made since a request, once the game has placed them: one near a request's spot is ours
local function match_born()
  local now = os.clock()
  for i = #expect, 1, -1 do if now - expect[i].t > 10 then table.remove(expect, i) end end
  for i = #born, 1, -1 do
    local b = born[i]
    if now - b.t > 10 or #expect == 0 then table.remove(born, i)
    elseif now - b.t > 0.2 then
      local l = valid(b.o) and try(function() return vof(b.o:K2_GetActorLocation()) end)
      if l then
        for j, x in ipairs(expect) do
          if dist(l, x.at) < 800 then
            local a = try(function() return b.o:GetAddress() end)
            if a then mine[a] = b.o end
            table.remove(expect, j)
            break
          end
        end
        table.remove(born, i)
      end
    end
  end
end

local function alive(o) return valid(o) and try(function() return o.bActorIsBeingDestroyed end) == false end

local function remove_all()
  local n = 0
  for a, o in pairs(mine) do
    if alive(o) and try(function() o:K2_DestroyActor(); return true end) then n = n + 1 end
    mine[a] = nil
  end
  expect = {}
  log(string.format("removed %d spawned enemies", n))
  toast(string.format("Removed %d", n))
end

-- the spawned enemy nearest her dies through the game (ClientBroadcast_ActorDead on its guid), else is ragdolled
local function kill_nearest()
  local her = try(function() return vof(pawn:K2_GetActorLocation()) end)
  if not her then return end
  local best, bd
  for a, o in pairs(mine) do
    if not alive(o) then mine[a] = nil
    else
      local p = try(function() return vof(o:K2_GetActorLocation()) end)
      local d = p and dist(p, her)
      if d and (not bd or d < bd) then best, bd = o, d end
    end
  end
  if not best then log("kill: no spawned enemy alive"); toast("No spawned enemy alive"); return end
  local pc = controller()
  local g = try(function() return best.BroadcastSpawnInfo.ActorGuid end)
  local ok = pc and g and pcall(function() pc:ClientBroadcast_ActorDead(0, g, 0, 0, 0, 0, false, false) end)
  if not ok then
    local mesh = try(function() return best.Mesh end)
    try(function() best.CharacterMovement:DisableMovement() end)
    try(function() mesh:SetCollisionProfileName(FName("Ragdoll"), true) end)
    try(function() mesh:SetAllBodiesSimulatePhysics(true) end)
  end
  log(string.format("kill: the nearest, %.0f cm off: %s", bd, ok and string.format("the game's death (guid %d)", g) or "ragdolled (no guid or controller)"))
end

-- while the window shows, the game lets go of the mouse (it kept the cursor captured: nothing could be clicked)
local function free_mouse(on)
  local pc = controller()
  if not pc then return end
  local lib = try(function() return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end)
  try(function() pc.bShowMouseCursor = on end)
  if valid(lib) then
    try(function() if on then lib:SetInputMode_GameAndUIEx(pc, nil, 0, false) else lib:SetInputMode_GameOnly(pc) end end)
  end
  freed = on
  log("window " .. (on and "open: mouse freed" or "closed: mouse back to the game"))
end

local function read_files()
  local f = io.open(STATE, "r")
  if f then
    local on = (f:read("a") or ""):sub(1, 1) == "1"
    f:close()
    if on ~= freed then free_mouse(on) end
  end
  f = io.open(REQ, "r")
  if not f then return end
  local s = f:read("a") or ""
  f:close()
  os.remove(REQ)
  local what, alias, count = s:match("^(%a+)\t?([^\t]*)\t?(%d*)")
  if what == "clear" then remove_all(); return end
  if what == "kill" then kill_nearest(); return end
  if what ~= "spawn" then log("window: unknown request " .. s); return end
  for _, k in ipairs(KINDS) do
    if k.alias == alias then spawn(k, math.max(1, math.min(9, tonumber(count) or 1))); return end
  end
  log("window: no kind " .. tostring(alias))
end

local ACTIONS = {
  spawn = function() spawn(KINDS[pick], 1) end,
  next = function()
    pick = pick % #KINDS + 1
    log(string.format("F5 now spawns %d of %d: %s (%s)", pick, #KINDS, KINDS[pick].label, KINDS[pick].alias))
    toast("F5: " .. KINDS[pick].label)
  end,
  window = function()
    write_list()
    local f = io.open(CMD, "w")
    if f then f:write("toggle"); f:close() end
  end,
  kill = kill_nearest,
  clear = remove_all,
}

-- a key with modifiers fires the plain key's bind too: per key, the bind with the most modifiers wins
local function bind(key, mods, id)
  local cb = function()
    local p = pending[key]
    if not p or #mods > p.n then pending[key] = { n = #mods, id = id } end
  end
  local ok
  if #mods == 0 then ok = pcall(RegisterKeyBind, Key[key], cb)
  else
    local mk = {}
    for _, m in ipairs(mods) do mk[#mk + 1] = ModifierKey[m] end
    ok = pcall(RegisterKeyBind, Key[key], mk, cb)
  end
  if not ok then log("key " .. table.concat(mods, "+") .. (#mods > 0 and "+" or "") .. key .. " not bound") end
end
bind("F5", {}, "spawn")
bind("INS", {}, "next")
bind("BACKSPACE", {}, "clear")
bind("HOME", {}, "window")
bind("END", {}, "kill")

local n = 0
local function tick(ctx)
  local self = try(function() return ctx:get() end)
  local a = self and try(function() return self:GetAddress() end)
  if not a then return end
  local now = os.clock()
  if a ~= pawnAddr then
    -- a death reloads the level: a new Eve ticks, the old one is freed (never touched again)
    if pawnAddr and now - pawnSeen < 1.0 then return end
    if pawnAddr then log("new Eve (the level reloaded)") end
    pawnAddr, pawn, mine, expect, born, freed = a, self, {}, {}, {}, false
  end
  pawnSeen = now
  for key, p in pairs(pending) do
    pending[key] = nil
    local ok, err = pcall(ACTIONS[p.id])
    if not ok then log(p.id .. " failed: " .. tostring(err)) end
  end
  n = n + 1
  if n % 8 == 0 then
    local ok, err = pcall(read_files)
    if not ok then log("window files: " .. tostring(err)) end
    if #expect > 0 or #born > 0 then pcall(match_born) end
  end
end

local ok, err = pcall(NotifyOnNewObject, "/Script/SB.SBCharacter", function(o)
  if #expect > 0 then born[#born + 1] = { o = o, t = os.clock() } end
end)
if not ok then log("NotifyOnNewObject failed: " .. tostring(err) .. " (Remove all and Kill nearest won't find spawns)") end

local hooked = false
local function hook(how)
  if hooked then return true end
  if not valid(try(function() return StaticFindObject(TICK_FN) end)) then return false end
  local okh, e = pcall(RegisterHook, TICK_FN, function(ctx)
    local okt, et = pcall(tick, ctx)
    if not okt then log("tick: " .. tostring(et)) end
  end)
  hooked = okh
  log(string.format("tick hook (%s): %s", how, okh and "ok" or tostring(e)))
  return okh
end
pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function() pcall(hook, "player start") end)
LoopAsync(1000, function() return hooked or hook("loop") end)

write_list()
log("SBSpawner " .. VERSION .. " loaded: F5 spawn, Insert next kind, Backspace remove all, Home window, End kill nearest")
