-- A shared mesh must retain separate sink rules for faced and unfaced owners.
local create = dofile("ue4ss/Mods/StellarBladeGore/Scripts/bone_lists.lua")
local enemy = { faced = {} }
local asset = { address = 100 }
local names = { "Root", "Bip001-Head", "Ab_Helper", "Ab_Hair" }
FName = function(s) return s end
local function str(s) return { ToString = function() return s end } end
local mesh = { SkeletalMesh = asset }
function mesh:GetNumBones() return #names end
function mesh:GetBoneName(i) return str(names[i + 1]) end
function mesh:GetParentBone() return str("Root") end
local function try(f) local ok, v = pcall(f); if ok then return v end end
local M = {}
local function physics(address, bone)
  return {address = address, SkeletalBodySetups = {ForEach = function(_, fn)
    fn(nil, {get = function() return {BoneName = str(bone)} end})
  end}}
end
local pa = physics(200, "Bip001-Head")
local lists = create(M, try, function(x) return x ~= nil end, function(x) return x.address end, enemy,
  function() return {physics_of = function() return pa end} end)
local failed = false
local function check(ok, message)
  print((ok and "ok   " or "FAIL ") .. message)
  if not ok then failed = true end
end
local function faced() enemy.cur = nil; return lists.nosink(mesh) end
local function unfaced() enemy.cur = "enemy"; return lists.nosink(mesh) end
check(faced() == "0,1,2,3" and unfaced() == "0,1,3", "player cache does not hide unfaced enemy helpers")
local oldTrees = M.trees
lists.clear()
check(M.trees ~= oldTrees and next(M.trees) == nil, "world cleanup drops asset-address bone trees")
check(unfaced() == "0,1,3" and faced() == "0,1,2,3", "enemy cache does not expose player helpers")
enemy.cur, enemy.faced.boss = "boss", true
check(lists.nosink(mesh) == "0,1,2,3", "faced enemy retains player-style exclusions")
enemy.cur = nil
local firstBodies = lists.bodies(mesh)
local firstNoCarry = lists.nocarry(mesh)
pa = physics(201, "Ab_Helper")
local secondBodies = lists.bodies(mesh)
local secondNoCarry = lists.nocarry(mesh)
check(firstBodies[1] and not firstBodies[2] and secondBodies[2] and not secondBodies[1],
  "a replacement physics asset gets its own body list")
check(firstNoCarry ~= secondNoCarry and secondNoCarry == "2", "no-carry list follows the replacement physics asset")
pa = nil
check(next(lists.bodies(mesh)) == nil, "missing physics asset gives an empty uncached list")
pa = physics(202, "Bip001-Head")
check(lists.bodies(mesh)[1], "late physics asset is discovered after a missing asset")
print(failed and "FAIL" or "PASS")
