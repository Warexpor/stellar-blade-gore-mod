-- screen.sim_bodies (the cloth reset's hair scan): each bone's first Bip001 ancestor is resolved once per mesh
-- asset instead of walking the parent chain on every reset (tens of engine reads on a respawn's tick, playtest).
-- Simulating state is still asked every time; the same bones come out.
local F = require("fake")
local E = require("eve")
local print = F.say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local pawn = E.make(F)

local parentCalls = 0
local sim = { H1 = true, H2 = true, ["Bip001-Head"] = false }
local pa = F.obj("TestPhys", "PhysicsAsset", {
  SkeletalBodySetups = { ForEach = function(_, fn)
    for _, b in ipairs({ "Bip001-Head", "Bip001-Pelvis", "H1", "H2" }) do
      fn(nil, { get = function() return F.obj("BodySetup_" .. b, "BodySetup", { BoneName = F.fname(b) }) end })
    end
  end },
})
local mesh = F.obj("TestMesh", "SkeletalMeshComponent", {
  GetPhysicsAsset = function() return pa end,
  IsSimulatingPhysics = function(_, b) return sim[b and b:ToString()] == true end,
  GetParentBone = function(_, b)
    parentCalls = parentCalls + 1
    local n = b:ToString()
    if n == "H1" then return F.fname("Bip001-Head") end
    if n == "H2" then return F.fname("H1") end
    return F.fname("None")
  end,
})

local ok, err = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(2, pawn)
local function findup(fn, want, seen)
  seen = seen or {}
  if type(fn) ~= "function" or seen[fn] then return nil end
  seen[fn] = true
  for i = 1, 200 do
    local n, v = debug.getupvalue(fn, i)
    if not n then break end
    if n == want then return v end
    if n ~= "_ENV" and type(v) == "function" then
      local x = findup(v, want, seen)
      if x then return x end
    end
  end
end
local tick = F.hooks["/Game/Art/Character/PC/CH_P_EVE_01/Blueprints/CH_P_EVE_01_Blueprint.CH_P_EVE_01_Blueprint_C:ReceiveTick"]
tick = tick and tick[1] or nil
local screen = assert(tick and findup(tick, "screen"), "screen context")
local function names(list)
  local out = {}
  for _, b in ipairs(list) do out[#out + 1] = b end
  table.sort(out)
  return table.concat(out, ",")
end
local first = screen.sim_bodies(mesh)
check(names(first) == "H1,H2" and parentCalls > 0, "hair under a still head resolves (" .. names(first) .. ", " .. parentCalls .. " parent reads)")
local scanned = parentCalls
local second = screen.sim_bodies(mesh)
check(names(second) == names(first) and parentCalls == scanned, "the next reset reuses the ancestors (no new parent reads)")
sim["Bip001-Head"] = true
local third = screen.sim_bodies(mesh)
check(names(third) == "" and parentCalls == scanned, "simulating state is still asked live (head simulating holds both)")
sim["Bip001-Head"] = false
local mesh2 = F.obj("TestMesh2", "SkeletalMeshComponent", {
  GetPhysicsAsset = function() return pa end,
  IsSimulatingPhysics = function(_, b) return sim[b and b:ToString()] == true end,
  GetParentBone = function(_, b)
    parentCalls = parentCalls + 1
    local n = b:ToString()
    if n == "H1" then return F.fname("Bip001-Head") end
    if n == "H2" then return F.fname("H1") end
    return F.fname("None")
  end,
})
screen.sim_bodies(mesh2)
check(parentCalls > scanned, "a new mesh resolves its own ancestors")
-- The collision restore already owns its guarded component list; walking attachments here is unused.
local walk, restore = screen.cloth_meshes, screen.cloth_restore
local walks, restores = 0, 0
screen.cloth_meshes = function(p) walks = walks + 1; return walk(p) end
screen.cloth_restore = function() restores = restores + 1; return 0 end
screen.cloth = { at = os.clock() - 10, i = 2, why = "restore regression" }
screen.cloth_tick(pawn)
check(restores == 1 and screen.cloth == nil, "due collision restore still runs and completes the reset")
check(walks == 0, "collision-only restore performs no unused attachment walk")
screen.cloth_meshes, screen.cloth_restore, screen.autoF8 = walk, restore, nil
for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
