-- Enemies attacking her body after her death (enemies.lua tune.enemies.afterDeath, main.lua hits_after). A made-up
-- Naytiba stands 3 m off her: once she is dead its tree's target searches must take a dead target, its "target
-- alive" checks swap, and it must find an attack animation of its own (its mesh's folder: UE4SS has no GetPathName,
-- which left every enemy's mesh "in no monster folder" in the playtests and none ever swung), lunge in and play it.
-- Its weapon, swept through her left arm by the animation, then cuts her (Hits After Death), and a second enemy
-- further off than the nearest one cuts her too (only the nearest one's weapon was watched). At the end of `time` the
-- trees are put back as they were
local F = require("fake")
local E = require("eve")
math.randomseed(3)
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.enemies.afterDeath = { enabled = true, time = 10 }
-- (her death takes a limb, not her head or body: the hits after it then cut more)
s.gore.death = { limb = 100, head = 0, torso = 0, split = 0, moreLimbs = 0 }
return s
]])
f:close()
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"

local function vec(x, y, z) return { X = x, Y = y, Z = z } end
-- ---- the enemies: a Naytiba of CH_M_NA_14 with a blade in its right hand ----
local FOLDER = "/Game/Art/Character/Monster/CH_M_NA_14/"
local anims = {}
for _, nm in ipairs({ "M_NA_14_Attack_01", "M_NA_14_Combo_02", "M_NA_14_Idle", "M_NA_14_Evasion_B" }) do
  anims[#anims + 1] = F.obj(nm, "AnimSequence", {
    GetFullName = function() return "AnimSequence " .. FOLDER .. "Animation/" .. nm .. "." .. nm end,
    IsA = function() return true end,
    GetPlayLength = function() return 1.5 end,
  })
  F.objects[FOLDER .. "Animation/" .. nm .. "." .. nm] = anims[#anims]
end
F.classes.AnimSequence = anims
F.objects["/Script/Engine.AnimSequence"] = F.obj("AnimSequence", "Class")
local BONES = { "Bip001", "Bip001-Pelvis", "Bip001-Spine1", "Bip001-R-Hand", "Weapon_R" }
-- its blade's path in a swing: level, across her at her left upper arm's height, sweeping 260 cm over 0.25 s mid way
local ARM = E.bone("Bip001-L-UpperArm")
local function enemy(name, at)
  local e = { at = at, plays = {}, mode = 0 }
  local mesh
  mesh = F.obj(name .. "_Mesh", "SkeletalMeshComponent", {
    SkeletalMesh = F.obj("SK_CH_M_NA_14", "SkeletalMesh", {
      GetFullName = function() return "SkeletalMesh " .. FOLDER .. "Mesh/SK_CH_M_NA_14.SK_CH_M_NA_14" end,
    }),
    GetNumBones = function() return #BONES end,
    GetBoneName = function(_, i) return F.fname(BONES[i + 1] or "None") end,
    GetSocketLocation = function(_, b)
      local n = b:ToString()
      local p = e.at
      if n == "Weapon_R" and e.play then
        local k = (F.t - e.play.t0) / 1.5
        -- (from its hand out to the arc's start, the arc mid swing: across her arm, Y from -130 to +130 cm round it)
        local a0 = vec(ARM.X, ARM.Y - 130, ARM.Z - 11)
        if k <= 0.4 then
          local h = vec(p.X - 40, p.Y, p.Z + 30)
          local u = k / 0.4
          return vec(h.X + (a0.X - h.X) * u, h.Y + (a0.Y - h.Y) * u, h.Z + (a0.Z - h.Z) * u)
        elseif k < 0.6 then
          return vec(a0.X, a0.Y + 260 * (k - 0.4) / 0.2, a0.Z)
        end
      end
      return vec(p.X - 40, p.Y, p.Z + 30)
    end,
    PlayAnimation = function(_, a, loop)
      e.play = { a = a, t0 = F.t }
      e.plays[#e.plays + 1] = a.__name
      F.event(name .. " plays " .. a.__name)
    end,
    SetAnimationMode = function(_, m) e.mode = m; if m == 0 then e.play = nil end end,
  })
  e.obj = F.obj(name, "CH_M_NA_14_Blueprint_C", {
    Mesh = mesh, bActorIsBeingDestroyed = false, bHidden = false,
    K2_GetActorLocation = function() return vec(e.at.X, e.at.Y, e.at.Z) end,
    K2_SetActorLocation = function(_, l) e.at = vec(l.X, l.Y, l.Z); return true end,
    K2_SetActorRotation = function() return true end,
    GetActorForwardVector = function() return vec(-1, 0, 0) end,
    GetVelocity = function() return vec(0, 0, 0) end,
  })
  e.mesh = mesh
  return e
end
-- (streamed in 30 m off, then come at her)
local near = enemy("CH_M_NA_14_Blueprint_C_1", vec(4000, 2000, 90))
local far = enemy("CH_M_NA_14_Blueprint_C_2", vec(4000, 2420, 90))
F.classes.SBCharacter = { pawn, near.obj, far.obj }
-- their trees' nodes
local det = { F.obj("SbDetectTarget_1", "SBBTTask_SbDetectTarget", { bEnemy = true, bDead = false, TargetCancel = 0 }),
  F.obj("SbMoveToHome_1", "SBBTTask_SbMoveToHome", { bEnemy = true, bDetectTarget = true, bDead = false, TargetCancel = 0 }) }
local alive = { F.obj("SbIsAlive_1", "SBBTDecorator_SbIsAlive", { ActorType = 1, CheckType = 0 }) }
local skills = { F.obj("SbUseSkill_1", "SBBTTask_SbUseSkill", { SkillName = { ForEach = function(_, cb)
  for i, nm in ipairs({ "M_NA_14_S01_RightSwing", "M_NA_14_S02_Dash" }) do cb(i, { get = function() return F.fname(nm) end }) end
end } }) }
F.classes.SBBTTask_SbDetectTarget = { det[1] }
F.classes.SBBTTask_SbMoveToHome = { det[2] }
F.classes.SBBTDecorator_SbIsAlive = alive
F.classes.SBBTTask_SbUseSkill = skills

local ok, err = pcall(dofile, DIR .. "main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function mark() return #F.log_lines() + 1 end
local function dump(from, pat)
  for i, x in ipairs(F.log_lines()) do if i >= from and (not pat or x:find(pat)) then print("  | " .. x:sub(1, 240)) end end
end

check(F.find("after death: trees looked up %(new enemies around%)") ~= nil, "the trees looked up ahead, while she lives")
near.at, far.at = vec(1300, 2000, 90), vec(1000, 2420, 90)
F.run(1, pawn)
local d0 = mark()
E.s.hp = 0
E.die(true)
F.run(4, pawn)
check(det[1].bDead == true and det[1].TargetCancel == 2, "target searches take a dead target, dropped only once destroyed")
check(alive[1].CheckType == 1, "'target alive' checks swapped")
check(F.find("attacks of its own: M_NA_14_Attack_01", d0) ~= nil or F.find("attacks of its own: M_NA_14_Combo_02", d0) ~= nil,
  "its own attack animations found (by its mesh's folder)")
check(not F.find("no monster folder", d0), "no 'in no monster folder'")
check(#near.plays > 0, "the nearest one swings at her body (" .. table.concat(near.plays, ", ") .. ")")
for _, p in ipairs(near.plays) do check(not p:find("Idle") and not p:find("Evasion"), "  an attack: " .. p) end
check(F.find("swings .* at her body 300 cm off, lunging 180 cm in", d0) ~= nil, "it lunged in from 3 m")
check(F.find("after death %(.-%): CH_M_NA_14_Blueprint_C_1's Weapon_R .* passed %d+ cm from her Bip001%-[LR]%-UpperArm", d0) ~= nil,
  "its blade across her arms: a hit after death")
check(F.find("gore: cut Bip001%-[LR]%-UpperArm %(after%)", d0) ~= nil, "  which cut an arm off")
-- the other one (further off) swings now: its blade through her too
F.run(3, pawn)
check(#far.plays > 0, "the second one swings too (" .. table.concat(far.plays, ", ") .. ")")
check(F.find("after death %(.-%): CH_M_NA_14_Blueprint_C_2's", d0) ~= nil, "the second one's blade (not the nearest's) cut her too")
F.run(5, pawn)
check(F.find("after death: over %(time up%)", d0) ~= nil, "over once the time is up")
-- (their blades never slow between swings here, as a combo's hands didn't: each swing still cuts, rearm s after the
-- last; a second hit right after her death cut nothing, playtest)
local hits = 0
for i = d0, #F.log_lines() do if F.log_lines()[i]:find("after death %(") then hits = hits + 1 end end
check(hits >= 4, "a blow a swing, its weapon never slowing in between (" .. hits .. " hits)")
check(det[1].bDead == false and det[1].TargetCancel == 0 and alive[1].CheckType == 0, "the trees put back as they were")
check(near.mode == 0 and far.mode == 0, "their animation Blueprints given back")
if fails > 0 then dump(d0, "after death"); dump(d0, "swing:") end
for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
