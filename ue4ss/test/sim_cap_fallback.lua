-- If procedural mesh creation fails, the reused actor must move from the outline centre to the fitted sphere centre.
local F = require("fake")
local M = dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore.lua")
local print = F.say
local function safe(f) local ok, v = pcall(f); if ok then return v end end
M.init({ tune = { gore = {} }, try = safe, valid = function(x) return x and x:IsValid() end,
  may_load = function() return true end, log = function() end })
for _, path in ipairs({ "/Script/Engine.Default__GameplayStatics", "/Script/Engine.Default__KismetMathLibrary",
  "/Script/Engine.StaticMeshActor", "/Script/ProceduralMeshComponent.ProceduralMeshComponent",
  "/Engine/BasicShapes/Sphere.Sphere" }) do F.objects[path] = F.obj(path, "Object") end
local cap
for i = 1, 100 do
  local name, value = debug.getupvalue(M.stage_caps, i)
  if not name then break end
  if name == "cap" then cap = value end
end
assert(cap, "cap function not found")
local at, sections
local a = F.obj("cap", "Actor", { K2_SetActorLocation = function(_, p) at = p end })
local root = F.obj("root", "StaticMeshComponent")
local pmc = F.obj("lid", "ProceduralMeshComponent", { GetNumSections = function() return sections end })
M.pool_take = function(_, _, p) at = p; return { a = a, root = root, pmc = pmc } end
local function v(x, y, z) return { X = x, Y = y, Z = z } end
local o = { c = v(10, 20, 30), x = v(1, 0, 0), z = v(0, 0, 1), e = v(4, 3, 1),
  p = { v(0, 0, 0), v(1, 0, 0), v(0, 1, 0) } }
local old = v(12, 23, 30)
local built = { old, {}, {}, {}, {}, {}, {} }
local mesh = F.obj("mesh", "SkeletalMeshComponent")
sections = 0
local _, kind = cap(F.obj("pawn", "Actor"), mesh, o, "bone", built)
local fallback = kind == "sphere" and at == o.c
sections = 1
_, kind = cap(F.obj("pawn2", "Actor"), mesh, o, "bone", built)
local lid = kind == "lid 3 points" and at == old
print((fallback and "ok   " or "FAIL ") .. "failed lid: fallback sphere uses fitted centre")
print((lid and "ok   " or "FAIL ") .. "successful lid keeps outline centre")
print(fallback and lid and "PASS" or "FAIL")
