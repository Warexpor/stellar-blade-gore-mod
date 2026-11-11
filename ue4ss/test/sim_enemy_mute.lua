-- Basic enemies die silent, bosses keep the cut sound: enemy_cut's mute flag reaches the
-- cut's sound step. Muted: the limb still comes off, the log names the mute, no playback is attempted.
-- Unmuted (a boss): the same cut attempts playback as before.
local T = require("smash_world").boot('s.gore.bladeJitter = 0\ns.gore.multiCut = { enabled = false }')
local F, E, G, pawn, v = T.F, T.E, T.G, T.pawn, T.v
local print, fails = F.say, 0
local function check(c, what) print((c and "ok   " or "FAIL ") .. what); if not c then fails = fails + 1 end end
local function parts() return G.cut_parts(E.mesh) end
E.s.sim = true
local arm = E.bone("Bip001-L-UpperArm")

local got = G.enemy_cut("e-basic", pawn, E.mesh,
  { loc = arm, n = v(0, 1, 0), dir = v(1, 0, 0), fwd = v(0, 1, 0) }, "limb", nil, true, true)
for _ = 1, 60 do F.step(1/60); G.tick(pawn); G.pump() end
local limbs = 0
for _, p in ipairs(parts()) do if p:find("UpperArm") or p:find("Forearm") then limbs = limbs + 1 end end
check(got ~= nil, "muted basic-enemy cut starts (" .. tostring(got) .. ")")
check(limbs >= 1, "muted cut still takes the limb")
check(F.find("muted for a basic enemy") ~= nil, "muted cut logs the mute")
-- (the metal-core skip itself runs at the stubs stage on live opening geometry, which the fake
-- openings don't carry; covered by inspection and the in-game retest below)
check(F.find("attempting playback") == nil, "muted cut attempts no playback")
G.cleanup(pawn, E.mesh)

local got2 = G.enemy_cut("e-boss", pawn, E.mesh,
  { loc = arm, n = v(0, 1, 0), dir = v(1, 0, 0), fwd = v(0, 1, 0) }, "limb", nil, nil, nil)
for _ = 1, 60 do F.step(1/60); G.tick(pawn); G.pump() end
check(got2 ~= nil, "unmuted boss cut starts (" .. tostring(got2) .. ")")
check(F.find("attempting playback") ~= nil, "unmuted cut attempts playback as before")
G.cleanup(pawn, E.mesh)
check(#F.errors == 0 and not F.find("tick error"), "no errors")
print(fails == 0 and "PASS" or "FAIL")
