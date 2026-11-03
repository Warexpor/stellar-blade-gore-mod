-- An outfit mod's mesh worn as the level loads (Lemi21's Latex Nun, Nexus report): its own physics asset has no pelvis,
-- and the complete one it should get (tune.physfix.completeWith) isn't loaded yet while loading is held off after a
-- level load. physfix waits for it (it settled without one, and her deaths never ragdolled), gives it once it may, and
-- the override dropped again later while the mesh asset still holds ours is left alone (re-made every 2-3 s, she
-- twitched as she ran) and put back on her at her death
local F = require("fake")
local print = F.say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local physfix = dofile(DIR .. "physfix.lua")
local lines = {}
local quiet = true
local COMPLETE = "/Game/Art/Character/PC/CH_P_EVE_InnerSuit/CH_P_EVE_InnerSuit_Physics.CH_P_EVE_InnerSuit_Physics"
local function body(b) return { BoneName = { ToString = function() return b end }, DefaultInstance = {} } end
local function asset(nm, addr, bones)
  local bs = {}
  for _, b in ipairs(bones) do bs[#bs + 1] = body(b) end
  return { nm = nm, GetAddress = function() return addr end, GetFName = function() return { ToString = function() return nm end } end,
    SkeletalBodySetups = { ForEach = function(_, cb) for i, b in ipairs(bs) do cb(i, { get = function() return b end }) end end },
    ConstraintSetup = { ForEach = function() end } }
end
local own = asset("LtxNun_Physics", 0x100, { "Bip001-Spine", "Bip001-Spine2", "Bip001-Neck", "Bip001-L-UpperArm", "Bip001-R-UpperArm",
  "Bip001-L-Thigh", "Bip001-L-Calf", "Bip001-R-Thigh", "Bip001-R-Calf" })
local all = {}
for _, b in ipairs({ "Pelvis", "Spine", "Spine1", "Spine2", "Neck", "Head", "L-Clavicle", "R-Clavicle", "L-UpperArm", "R-UpperArm",
  "L-Forearm", "R-Forearm", "L-Hand", "R-Hand", "L-Thigh", "R-Thigh", "L-Calf", "R-Calf", "L-Foot", "R-Foot" }) do all[#all + 1] = "Bip001-" .. b end
local complete = asset("CH_P_EVE_InnerSuit_Physics", 0x200, all)
local loaded = false
StaticFindObject = function(p) if p == COMPLETE and loaded then return complete end end
LoadAsset = function(p) if p == COMPLETE then loaded = true; return complete end end
local sk = { PhysicsAsset = own, GetAddress = function() return 0x900 end, GetFName = function() return { ToString = function() return "MESH_LatexNun_Gold" end } end,
  LODInfo = { { bAllowCPUAccess = true } } }
local override, sets = nil, 0
local mesh = { SkeletalMesh = sk,
  GetPhysicsAsset = function() return override or sk.PhysicsAsset end,
  SetPhysicsAsset = function(_, pa) override = pa; sets = sets + 1 end }
physfix.init({
  try = function(f) local ok, r = pcall(f); if ok then return r end end,
  valid = function(o) return o ~= nil end,
  log = function(s) lines[#lines + 1] = s end,
  tune = { physfix = { steady = false, weldKinematic = false } },
  may_load = function() return not quiet end,
  cpu_forced = true,
  gore = { native_state = function() return "ready" end, command = function() return "err" end },
})
local function said(pat) for _, l in ipairs(lines) do if l:find(pat) then return l end end end

physfix.check(nil, mesh, false)
check(not said("outfit MESH_LatexNun_Gold"), "while loading is held off: no verdict yet")
check(mesh:GetPhysicsAsset() == own, "her own asset left on her meanwhile")
quiet = false
physfix.check(nil, mesh, false)
local l = said("outfit MESH_LatexNun_Gold, physics")
check(l and l:find("gave it") ~= nil, "once it may: given the complete asset (" .. tostring(l) .. ")")
check(mesh:GetPhysicsAsset() == complete and sk.PhysicsAsset == complete, "on her and on the mesh asset")

-- the outfit system drops the component's override (reads none); the mesh asset's own is ours
local before = sets
override = false
mesh.GetPhysicsAsset = function() return override or nil end
for _ = 1, 3 do physfix.check(nil, mesh, false) end
check(sets == before, "the dropped override not re-made while she lives (" .. (sets - before) .. " re-makes)")
-- her death: given back before her bodies simulate
local remakes = physfix.remakes or 0
physfix.start(nil, mesh)
check(override == complete, "put back on her at her death")
check((physfix.remakes or 0) == remakes + 1, "asset reassignment records a physics-body remake")
physfix.start(nil, mesh)
check((physfix.remakes or 0) == remakes + 1, "unchanged asset does not record a physics-body remake")
check(said("at her death: gave her CH_P_EVE_InnerSuit_Physics") ~= nil, "logged")

-- CNS's own assets can have low authored damping without our joint fixes (the wedding dress does).
local cns = asset("CH_P_EVE_02_Physics", 0x300, all)
cns.GetFullName = function() return "PhysicsAsset /Game/CNSRepacked/example/CH_P_EVE_02_Physics.CH_P_EVE_02_Physics" end
cns.SkeletalBodySetups:ForEach(function(_, e) e:get().DefaultInstance.LinearDamping = 0.2 end)
local cnsSk = { PhysicsAsset = cns, GetAddress = function() return 0x901 end,
  GetFName = function() return { ToString = function() return "CH_P_EVE_02_Body" end } end,
  LODInfo = { { bAllowCPUAccess = true } } }
local cnsSets = 0
local cnsMesh = { SkeletalMesh = cnsSk, GetPhysicsAsset = function() return cns end,
  SetPhysicsAsset = function() cnsSets = cnsSets + 1 end }
physfix.check(nil, cnsMesh, false)
check(said("outfit CH_P_EVE_02_Body, physics CH_P_EVE_02_Physics: NOT patched") ~= nil,
  "low-damping CNS asset still gets the runtime physics fix")
check(cnsSets == 1, "CNS bodies remade from the fixed asset")
physfix.check(nil, cnsMesh, false)
check(cnsSets == 1, "CNS bodies are not remade repeatedly")
local function joint(b)
  local p = { ConeLimit = { Swing1Motion = 0, Swing2Motion = 0, Swing1LimitDegrees = 45, Swing2LimitDegrees = 45 },
    TwistLimit = { TwistMotion = 0, TwistLimitDegrees = 45 } }
  return { child = "Bip001-" .. b, t = { DefaultInstance = { ProfileInstance = p } } }, p
end
local spine, ps = joint("Spine1")
local clavicle, pc = joint("L-Clavicle")
local elbow, pe = joint("L-Forearm")
local head, ph = joint("Head")
check(physfix.wedding_limits({spine, clavicle, elbow, head}) == 4, "wedding dress original profiles restored")
check(ps.TwistLimit.TwistMotion == 1 and ps.ConeLimit.Swing1LimitDegrees == 10, "free spine is constrained")
check(pc.TwistLimit.TwistLimitDegrees == 15 and pc.ConeLimit.Swing2LimitDegrees == 5, "clavicle limits restored")
check(pe.ConeLimit.Swing1Motion == 2 and pe.ConeLimit.Swing2Motion == 2, "elbow swings locked")
check(ph.TwistLimit.TwistMotion == 1 and ph.TwistLimit.TwistLimitDegrees == 15, "head twist constrained")

print(fails == 0 and "PASS" or "FAIL")
