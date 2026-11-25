local F = require("fake")
local fluid = dofile("ue4ss/Mods/StellarBladeGore/Scripts/death_fluid.lua")
local function v(x, y, z) return { X = x, Y = y, Z = z } end
local positions = {
  ["Bip001-Pelvis"] = v(0, 0, 15),
  ["Bip001-Spine"] = v(15, 0, 17),
  ["Bip001-L-Thigh"] = v(0, -8, 14), ["Bip001-R-Thigh"] = v(0, 8, 14),
  ["Bip001-L-Calf"] = v(-25, -8, 10), ["Bip001-R-Calf"] = v(-25, 8, 10),
}
local mesh = F.obj("Eve", "SkeletalMeshComponent", { GetSocketLocation = function(_, bone) return positions[tostring(bone)] end })
local actors = {}
local gs = F.obj("GameplayStatics", "GameplayStatics", {
  BeginDeferredActorSpawnFromClass = function()
    local actor = F.obj("Fluid", "StaticMeshActor")
    actors[#actors + 1] = actor
    actor.AddComponentByClass = function()
      return F.obj("FluidMesh", "ProceduralMeshComponent", {
        CreateMeshSection_LinearColor = function(_, _, verts, tris)
          assert(#verts > 20 and #tris > 20)
          actor.drawn = true
        end,
      })
    end
    actor.K2_DestroyActor = function() actor.__dead = true end
    return actor
  end,
  FinishSpawningActor = function(_, actor) return actor end,
})
local config = { enabled = false, still = 0.5, delay = 1, spray = 1 }
local function try(fn) local ok, a = pcall(fn); if ok then return a end end
local function valid(o) return o and o:IsValid() end
local function alive(h) return h and not h.obj.__freed and valid(h.obj) end
fluid.init({
  try = try, valid = valid, log = function() end,
  keep = function(o) return { obj = o } end, held = alive,
  alive_ask = function(list)
    for _, item in ipairs(list) do item.alive = alive(item) end
    return true
  end,
  tune = { gore = { deathFluid = config } },
  gore = {
    native_ready = function() return true end,
    guarded_asset = function(path)
      if path:find("GameplayStatics", 1, true) then return gs end
      return F.obj(path, "Asset")
    end,
    pool_trace = function(_, from, target)
      if from.Z >= 0 and target.Z <= 0 then return true, v(from.X, from.Y, 0), v(0, 0, 1) end
      return false
    end,
  },
})
local function run(seconds, dead)
  for _ = 1, seconds * 10 do
    F.t = F.t + 0.1
    fluid.tick({}, mesh, dead)
  end
end
run(2, true)
assert(#actors == 0, "disabled effect never spawns")
config.enabled = true
run(2, false)
assert(#actors == 0, "effect never runs while alive")
run(3, true)
assert(#actors == 2 and actors[1].drawn and actors[2].drawn, "stream and puddle draw their own meshes")
actors[2].__freed = true
run(1, false)
assert(actors[1].__dead and #F.errors == 0, "recovery removes the live actor and skips the freed one")
config.spray = 0
run(3, true)
assert(#actors == 3 and actors[3].drawn, "zero duration draws just the puddle")
fluid.forget()
assert(not actors[3].__dead, "world change discards references without touching old objects")
F.say("PASS")
