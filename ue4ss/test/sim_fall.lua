-- Fall damage deaths (main.lua hm.lethal_watch, hm.take). From 16 m the game's death show gave no ragdoll in two
-- playtests: the mod takes the death over (`death: taken over`), ragdolls her and holds the death screen hidden. The
-- controls: the show's ragdoll key working (the mod's own death as ever, no takeover); a medium fall leaving her at
-- 1 HP (the bar reads 0, no death screen: nothing); a death while swimming with no ragdoll (not taken over, named).
-- A fall damage death cuts nothing; a blow on her mesh as she lands still does
-- Any other death with no ragdoll from its show (an enemy's) is taken over too and cut; a scripted one is left alone
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
local ok, err = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
-- the mod starts 10 s after her start, then needs a moment (sbslice's handshake, its tables)
F.run(16, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function mark() return #F.log_lines() + 1 end
local function dump(from, pat)
  for i, x in ipairs(F.log_lines()) do if i >= from and (not pat or x:find(pat)) then print("  | " .. x) end end
end
local function screen_hidden() local w = E.deadScreen.__w; return w.vis == 1 or w.vis == 2 end
local function next_life() F.run(14, pawn); E.respawn(); F.run(6, pawn) end

-- her outfit's post-process AnimBP: two KawaiiPhysics nodes and a ControlRig one (Raven's suit, CH_P_EVE_11): the
-- KawaiiPhysics ones off (Alpha 0) while she is a ragdoll, back after; the ControlRig one left alone
local kp = { Alpha = 1 }
local kp1 = { Alpha = 0.7 }
local cr = { Alpha = 1 }
local function prop(n, st)
  return { GetFName = function() return F.fname(n) end,
    GetStruct = function() return { GetFName = function() return F.fname(st) end } end }
end
local animInst = F.obj("AnimInstance", "Class", { GetFName = function() return F.fname("AnimInstance") end })
local abp = F.obj("CH_P_EVE_11_AnimBP_C", "Class", {
  GetFName = function() return F.fname("CH_P_EVE_11_AnimBP_C") end,
  ForEachProperty = function(_, cb)
    cb(prop("AnimGraphNode_KawaiiPhysics", "AnimNode_KawaiiPhysics"))
    cb(prop("AnimGraphNode_KawaiiPhysics_1", "AnimNode_KawaiiPhysics"))
    cb(prop("AnimGraphNode_ControlRig", "AnimNode_ControlRig"))
  end,
  GetSuperStruct = function() return animInst end })
local post = F.obj("CH_P_EVE_11_AnimBP_C_0", "CH_P_EVE_11_AnimBP_C", { AnimGraphNode_KawaiiPhysics = kp,
  AnimGraphNode_KawaiiPhysics_1 = kp1, AnimGraphNode_ControlRig = cr, GetClass = function() return abp end })
rawset(E.mesh, "GetPostProcessInstance", function() return post end)

-- 1: the 16 m drop, no ragdoll from the game
local at = mark()
E.fall(1600, 1.8, 0, false)
F.run(0.5, pawn)
local l = F.find("death: taken over", at)
check(l ~= nil, "16 m fall, no ragdoll from its show: taken over")
check(E.s.sim, "her bodies simulate")
check(F.find("ragdoll state at start", at) ~= nil, "the mod's death started")
F.run(3, pawn)
check(F.find("death: fall damage %(%d+ cm drop, taken over%): no cut", at) ~= nil, "fall damage: no cut")
check(not F.find("gore: cut ", at) and not F.find("gore: split", at), "nothing cut off her (playtest: both legs)")
check(screen_hidden(), "the death screen held hidden 3 s in")
F.run(7.5, pawn)
check(not screen_hidden(), "the death screen shown at 10 s")
check(not F.find("death NOT seen", at), "no 'death NOT seen'")
check(kp.Alpha == 0 and kp1.Alpha == 0 and cr.Alpha == 1 and F.find("KawaiiPhysics off %(2 of 2 nodes%)", at) ~= nil,
  "her outfit's KawaiiPhysics off on her ragdoll, its ControlRig on")
if fails > 0 then dump(at, "death") end
next_life()
check(kp.Alpha == 1 and kp1.Alpha == 0.7 and F.find("KawaiiPhysics back on", at) ~= nil, "back on as it was once she is up")

-- 2: the same drop, the show's ragdoll key working
at = mark()
E.fall(1600, 1.8, 0, true)
F.run(1, pawn)
check(F.find("ragdoll state at start", at) ~= nil, "16 m fall, its show's ragdoll working: the mod's death")
check(not F.find("taken over", at), "not taken over")
check(F.find("death: fall damage %(%d+ cm drop%): no cut", at) ~= nil and not F.find("gore: cut ", at), "no cut either")
check(screen_hidden(), "the death screen held hidden")
next_life()

-- 3: a medium fall, 1 HP left (the bar reads 0.000)
at = mark()
E.fall(600, 1.1, 0.0004, nil)
F.run(3, pawn)
check(not F.find("taken over", at) and not F.find("ragdoll state at start", at), "a 6 m fall at 1 HP: no death, no takeover")
check(not E.s.sim, "she isn't ragdolled")
E.s.hp = 0.5
F.run(1, pawn)

-- 4: a death while swimming, no ragdoll from its show
at = mark()
E.s.mode, E.s.hp = 4, 0
F.run(0.2, pawn)
E.die(false)
F.run(1, pawn)
check(not F.find("taken over", at), "a swimming death: not taken over")
check(F.find("death NOT seen.*swimming", at) ~= nil, "named in the log (death NOT seen ..., swimming)")
next_life()

-- 6: the 16 m drop leaving her at 1 HP (the bar reads 0) with the death screen's widget made with the level and reading
-- visible: she lives, her movement on: no takeover, no ragdoll (playtest: ragdolled alive, walking off from her body)
at = mark()
E.dead_widget()
E.fall(1600, 1.8, 0.0004, nil)
F.run(2, pawn)
check(not F.find("taken over", at) and not E.s.sim, "1 HP after a 16 m fall, the death widget up all along: no takeover")
check(F.find("alive at 1 HP so far, watched on", at) ~= nil, "told alive at 1 HP")
-- then her death on that same bar (no ragdoll from its show): still taken over
E.die(false)
F.run(1, pawn)
check(F.find("death: taken over", at) ~= nil and E.s.sim, "her death later on the same bar: taken over")
check(F.find("its intro playing: YouDie", at) ~= nil, "told by the death screen's intro, her movement on (walking)")
F.run(1, pawn)
check(E.s.sim and not F.find("the ragdoll ends", at), "her movement on in the death: the ragdoll stays")
-- the safety net: the player moving her in a taken-over death: the ragdoll ends
E.s.input = 2000
F.run(1, pawn)
check(F.find("but the player moves her %(mode 1, input 2000%): she lives, the ragdoll ends", at) ~= nil, "the player moves her: the ragdoll ends")
check(not E.s.sim, "her bodies off")
if fails > 0 then dump(at, "death") end
next_life()

-- 5: the control: a blow on her mesh as she lands from a 3 m jump kills her: it cuts as any death
at = mark()
E.fall(300, 0.8, 1.0, nil)
local p = E.bone("Bip001-Spine1")
rawset(E.mesh, "PhysicalHitForceVector", { X = -300, Y = 0, Z = 0 })
rawset(E.mesh, "PhysicalHitForceLocation", { X = p.X + 10, Y = p.Y, Z = p.Z })
rawset(E.mesh, "PhysicalHitForceTargetBone", F.fname("Bip001-Spine2"))
F.run(0.1, pawn)
E.s.hp = 0
F.run(0.2, pawn)
E.die(true)
F.run(2, pawn)
check(not F.find("death: fall damage", at), "a blow as she lands: not taken for fall damage")
check(F.find("gore: cut ", at) ~= nil or F.find("gore: split", at) ~= nil, "its death cuts")
if fails > 0 then dump(at, "death") end
next_life()

-- 7: an enemy's kill on the ground whose show gives no ragdoll (0.5.0 report: enemy attacks went straight to the death
-- screen): taken over as a fall's, and cut as any death
local MONT = nil
rawset(E.mesh, "GetAnimInstance", function()
  return F.obj("ABP_Eve", "AnimInstance", { GetCurrentActiveMontage = function()
    return MONT and F.obj(MONT, "AnimMontage") or nil
  end })
end)
at = mark()
MONT = "P_Eve_Grab_Dead"
E.s.hp = 0
F.run(0.2, pawn)
E.die(false, 1000123)
F.run(1, pawn)
check(F.find("death: taken over %(no ragdoll from its show: no drop, .*playing P_Eve_Grab_Dead", at) ~= nil and E.s.sim,
  "an enemy's kill with no ragdoll: taken over")
F.run(2, pawn)
check(not F.find("death: fall damage", at), "not taken for fall damage")
check(F.find("death: last hit .*rolled", at) ~= nil or F.find("death: split rolled", at) ~= nil, "its death rolled as any (cut)")
check(screen_hidden(), "the death screen held hidden")
if fails > 0 then dump(at, "death") end
next_life()

-- 8: a scripted death (the desert's sand hole) with no ragdoll: the game's
at = mark()
MONT = "P_Eve_Dead_DesertHole"
E.s.hp = 0
F.run(0.2, pawn)
E.die(false)
F.run(1, pawn)
check(not F.find("taken over", at) and not E.s.sim, "the sand hole's death: not taken over")
check(F.find("death NOT seen.*a scripted death: DesertHole", at) ~= nil, "named in the log")
if fails > 0 then dump(at, "death") end
MONT = nil
next_life()

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
print(fails == 0 and "PASS" or "FAIL")
