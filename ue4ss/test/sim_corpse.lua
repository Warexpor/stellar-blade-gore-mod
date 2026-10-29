-- An enemy corpse cut after cut, and its bits (second Sandbox Bosses playtest):
--   gore.joint: a thigh cut after its calf flew off is laid out along where the calf was on the thigh, not toward the
--     flying calf (Raven's thigh plane lay 100 cm off her, met no skin and changed her weights: stumps misplaced)
--   enemies adopt: a boss spawned here arriving far from where it was asked for is still the one spawned here (Tachy
--     wasn't, and Passive Bosses never stopped her)
--   enemies weapons_on_ragdoll: a weapon on a socket whose bone doesn't simulate goes onto the nearest bone that does
--     (Raven's sword hung in the air)
--   a passive boss's hand by her is no grab
local F = require("fake")
local print = F.say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function v(x, y, z) return { X = x, Y = y, Z = z } end
local function d(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) end
local try = function(f, ...) local o, r = pcall(f, ...); if o then return r end end
local valid = function(x) return x ~= nil and x ~= false end

-- ---- gore.joint ----
local G = dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore.lua")
G.init({ tune = {}, try = try, valid = valid, v3 = function(p) return string.format("%.0f %.0f %.0f", p.X, p.Y, p.Z) end, log = function() end })
-- a thigh at the origin, turned 90 degrees about Z (its X along world Y), the calf 40 cm down its X
local s2 = math.sqrt(0.5)
local q = { X = 0, Y = 0, Z = s2, W = s2 }
local bones = { ["Bip001-R-Thigh"] = v(0, 0, 100), ["Bip001-R-Calf"] = v(0, 40, 100) }
local mesh = F.obj("RavenBody", "SkeletalMeshComponent", { SkeletalMesh = F.obj("CH_M_NA_53", "SkeletalMesh") })
mesh.GetSocketLocation = function(_, b) local p = bones[tostring(b)]; return p and v(p.X, p.Y, p.Z) end
mesh.GetSocketTransform = function(_, b)
  local p = bones[tostring(b)]
  return { Translation = v(p.X, p.Y, p.Z), Rotation = { X = q.X, Y = q.Y, Z = q.Z, W = q.W }, Scale3D = v(1, 1, 1) }
end
mesh.GetParentBone = function(_, b) return F.fname(tostring(b) == "Bip001-R-Calf" and "Bip001-R-Thigh" or "Bip001-Pelvis") end
local gone = false
G.already_cut = function(_, b) return gone and b == "Bip001-R-Calf" end
G.stub_note(mesh, "Bip001-R-Calf")
check(d(G.joint(mesh, "Bip001-R-Calf"), v(0, 40, 100)) < 0.01, "not cut: the calf where it is")
-- cut off and flung 1210 cm/s: 3 m off; the thigh turned another 90 degrees (now its X along world -X) and moved
gone = true
bones["Bip001-R-Calf"] = v(250, -300, 40)
bones["Bip001-R-Thigh"] = v(10, 0, 95)
q = { X = 0, Y = 0, Z = 1, W = 0 }
local j = G.joint(mesh, "Bip001-R-Calf")
check(d(j, v(-30, 0, 95)) < 0.01, string.format("cut off and flung: the calf's joint where it was on the thigh, turned with it (%.1f %.1f %.1f)", j.X, j.Y, j.Z))
-- another mesh asset at the same address (a level change): not the stub
mesh.SkeletalMesh = F.obj("Other", "SkeletalMesh")
check(d(G.joint(mesh, "Bip001-R-Calf"), v(250, -300, 40)) < 0.01, "another mesh asset at its address: its own bone")

-- ---- enemies: adopt, weapon, passive grab ----
local logs = {}
local tune = dofile("ue4ss/Mods/StellarBladeGore/Scripts/tune.lua")
tune.bosses.enabled = true
local chars = {}
local passive = {}
local ctx = { tune = tune, try = try, valid = valid, log = function(s) logs[#logs + 1] = s; print("  | " .. s) end,
  live_chars = function() return chars end, keep = function(o) return { obj = o } end, held = function() return true end,
  bosses = { adopted = function(a, e, mine) logs[#logs + 1] = "adopted " .. tostring(mine) end, is_passive = function(a) return passive[a] == true end,
    tick = function() end, died = function() end },
  newobj = { watch = function() end } }
local E = dofile("ue4ss/Mods/StellarBladeGore/Scripts/enemies.lua")
E.init(ctx)
local function has(p) for _, l in ipairs(logs) do if l:find(p) then return true end end return false end
check(E.BOSS_FAR >= 3000, "bosses matched to their spawn request within " .. E.BOSS_FAR .. " cm")

-- the weapon: Raven's sword on SC_Weapon (SC_WeaponConstraint, no body), under her right hand (simulating)
local sim = { ["Bip001-R-Hand"] = true, ["Bip001-R-Forearm"] = true }
local parent = { SC_WeaponConstraint = "Bip001-R-Hand", ["Bip001-R-Hand"] = "Bip001-R-Forearm" }
local body = F.obj("Body", "SkeletalMeshComponent")
body.IsSimulatingPhysics = function(_, b) return sim[tostring(b)] == true end
body.GetParentBone = function(_, b) return F.fname(parent[tostring(b)] or "None") end
body.GetSocketBoneName = function(_, s) return F.fname(tostring(s) == "SC_Weapon" and "SC_WeaponConstraint" or tostring(s)) end
local attached
local sword = F.obj("Sword", "SBSkeletalMeshComponent", { AttachSocketName = F.fname("SC_Weapon"), SkeletalMesh = F.obj("CH_M_NA_53_Weapon", "SkeletalMesh") })
sword.GetAttachParent = function() return body end
sword.K2_AttachToComponent = function(_, p, sock, l, r, s) attached = { p = p, sock = tostring(sock), l = l } end
local cap = F.obj("Cap", "StaticMeshComponent", { AttachSocketName = F.fname("Ab-R-Calf-Tw1"), StaticMesh = F.obj("SM_Cap", "StaticMesh") })
cap.GetAttachParent = function() return body end
cap.K2_AttachToComponent = function() attached = "cap" end
F.objects["/Script/Engine.SkeletalMeshComponent"] = F.obj("SkeletalMeshComponent", "Class")
F.objects["/Script/Engine.StaticMeshComponent"] = F.obj("StaticMeshComponent", "Class")
local raven = F.obj("CH_M_NA_53_Blueprint_C_1", "CH_M_NA_53_Blueprint_C", { Mesh = body })
raven.K2_GetComponentsByClass = function(_, c) return c.__name == "StaticMeshComponent" and { cap } or { body, sword } end
raven.K2_GetActorLocation = function() return v(0, 0, 100) end
check(E._weapons_on_ragdoll ~= nil, "the weapon step reachable")
if E._weapons_on_ragdoll then
  E._weapons_on_ragdoll({ obj = raven, mesh = body, kind = { alias = "B_Raven" } })
  check(type(attached) == "table" and attached.p == body and attached.sock == "Bip001-R-Hand" and attached.l == 1,
    "Raven's sword on its non-simulated socket bone: onto her right hand, where it is")
  check(attached ~= "cap" and has("its weapon onto its ragdoll: CH_M_NA_53_Weapon on SC_Weapon %(SC_WeaponConstraint%) %-> Bip001%-R%-Hand"), "a cap left alone, logged")
  attached = nil
  sim.SC_WeaponConstraint = true
  E._weapons_on_ragdoll({ obj = raven, mesh = body, kind = { alias = "B_Raven" } })
  check(attached == nil, "its socket's bone simulating: left as it is")
end

-- a passive boss's hand on her neck: no grab
local herMesh = F.obj("EveMesh", "SkeletalMeshComponent")
herMesh.GetSocketLocation = function() return v(0, 0, 150) end
local root = F.obj("EveCapsule", "CapsuleComponent")
root.GetAttachParentActor = function() return nil end
local pawn = F.obj("Eve", "CH_P_EVE_01_Blueprint_C", { Mesh = herMesh, RootComponent = root })
herMesh.GetAnimInstance = function() return { GetCurrentActiveMontage = function() return nil end } end
local rm = F.obj("RavenMesh", "SkeletalMeshComponent")
rm.GetSocketLocation = function() return v(2, 0, 152) end
rm.GetAnimInstance = function() return { GetCurrentActiveMontage = function() return nil end } end
local r2 = F.obj("CH_M_NA_53_Blueprint_C_2", "CH_M_NA_53_Blueprint_C", { Mesh = rm })
r2.K2_GetActorLocation = function() return v(50, 0, 100) end
chars[1] = { obj = r2, addr = r2:GetAddress(), cls = "CH_M_NA_53_Blueprint_C" }
passive[r2:GetAddress()] = true
for _ = 1, 8 do F.t = F.t + 0.1; E.grab_tick(pawn, herMesh) end
check(E.grab_now() == nil, "a passive boss's hand on her neck: no grab")
passive[r2:GetAddress()] = nil
for _ = 1, 8 do F.t = F.t + 0.1; E.grab_tick(pawn, herMesh) end
check(E.grab_now() ~= nil, "the same, fighting: a grab")

-- a Tachy spawned here whose physics asset was just put back (bosses.own_physics): its bodies came simulating, no
-- death; once the hold is over the same is her death (playtest: cut and thrown across the map as she came in)
local B = dofile("ue4ss/Mods/StellarBladeGore/Scripts/bosses.lua")
B.init({ tune = tune, try = try, valid = valid, log = ctx.log })
local dies = 0
ctx.bosses.prepare = function() return nil end
ctx.bosses.adopted = function(a, e, mine) if mine then e.physHold = os.clock() + 1 end end
ctx.bosses.died = function() dies = dies + 1 end
ctx.bosses.kinematic = B.kinematic
tune.enemies.push = 1
local tsim = true
local tm = F.obj("TachyMesh", "SkeletalMeshComponent", { SkeletalMesh = F.obj("CH_M_NA_21_Body", "SkeletalMesh") })
tm.IsSimulatingPhysics = function() return tsim end
tm.SetSimulatePhysics = function(_, x) tsim = x end
tm.SetAllBodiesSimulatePhysics = function(_, x) tsim = x end
tm.GetSocketLocation = function() return v(400, 0, 100) end
local tachy = F.obj("CH_M_NA_21_Blueprint_C_1", "CH_M_NA_21_Blueprint_C", { Mesh = tm, bActorIsBeingDestroyed = false })
tachy.K2_GetActorLocation = function() return v(400, 0, 100) end
pawn.Controller = { ServerRequest_CreateActor = function() end }
pawn.K2_GetActorLocation = function() return v(0, 0, 100) end
pawn.GetControlRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end
local tk
for _, k in ipairs(tune.bosses.kinds) do if k.key == "tachy" then tk = k end end
E.spawn_kind(pawn, tk, 1)
chars[1] = { obj = tachy, addr = tachy:GetAddress(), cls = "CH_M_NA_21_Blueprint_C" }
F.t = F.t + 0.1; E.tick(pawn, herMesh)
F.t = F.t + 0.1; E.tick(pawn, herMesh)
check(dies == 0 and not tsim and has("kinematic again, not its death"), "a boss's bodies simulating right after its physics asset was put back: kinematic again, no death")
F.t = F.t + 1.5; tsim = true; E.tick(pawn, herMesh)
check(dies == 1, "simulating after the hold: its death")

check(#F.errors == 0, "no errors (" .. table.concat(F.errors, "; ") .. ")")
print(fails == 0 and "PASS" or "FAIL")
