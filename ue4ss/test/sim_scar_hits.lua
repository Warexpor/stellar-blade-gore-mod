-- Exercise the living-hit fallback through main.lua with no mesh or skill hit report.
local T = require("smash_world").boot("s.gore.hitMarks.enabled = true")
local F, E, G, pawn, v = T.F, T.E, T.G, T.pawn, T.v
local sw = T.state.sw
local fails = 0
local function check(ok, what)
  F.say((ok and "ok   " or "FAIL ") .. what)
  if not ok then fails = fails + 1 end
end
check(T.ctx.tune.gore.hitMarks.enabled == false, "Hit Scars stays parked with a saved opt-in")
-- Exercise the retained implementation by opting in only inside this simulation.
T.ctx.tune.gore.hitMarks.enabled = true

local marks = {}
G.hit_mark = function(_, _, at, dir, pre)
  marks[#marks + 1] = { at = at, dir = dir, pre = pre }
  return true
end
local chest = E.bone("Bip001-Spine1")
local hand
local claw = F.obj("Claw", "SkeletalMeshComponent", {
  GetSocketLocation = function() return hand end,
})
local enemy = F.obj("Grub", "CH_M_NA_11_Blueprint_C", {
  GetActorForwardVector = function() return v(1, 0, 0) end,
  K2_GetActorLocation = function() return v(0, 0, 0) end,
})
local track = {
  actor = enemy, who = "Grub", mesh = claw, k = T.ctx.keep(enemy),
  bones = { "Bip001-R-Hand" }, weapons = {},
}
sw.next, sw.list = F.t + 60, { track }
local function swipe(offset)
  local t = F.t
  local first = v(chest.X + offset, chest.Y - 90, chest.Z)
  local middle = v(chest.X + offset, chest.Y - 45, chest.Z)
  hand = v(chest.X + offset, chest.Y + 40, chest.Z)
  track.hist = {
    { t = t - 0.10, p = { first }, origin = v(0, 0, 0) },
    { t = t - 0.06, p = { middle }, origin = v(0, 0, 0) },
    { t = t - 0.02, p = { hand }, origin = v(0, 0, 0) },
  }
end

swipe(0)
F.run(0.85, pawn)
check(#marks == 0, "a close sweep with unchanged HP leaves no scar")
swipe(200)
E.s.hp = 0.8
F.run(0.85, pawn)
check(#marks == 0 and F.find("no nearby swing"), "an HP drop with only a distant sweep leaves no scar and logs why")
swipe(0)
E.s.hp = 0.6
F.run(0.6, pawn)
local mark = marks[1]
check(#marks == 1 and mark.pre == 0.8 and mark.dir.Y > 0.99
  and math.abs(mark.at.X - chest.X) < 1 and math.abs(mark.at.Y - chest.Y) < 3,
  "a surviving HP drop places a scar along a nearby claw with no weapon mesh")
swipe(0)
E.s.hp = 0
E.die(true)
F.run(0.6, pawn)
check(#marks == 1, "a killing blow leaves no living-hit scar")
check(#F.errors == 0 and not F.find("her watches: "), "no simulation errors in the living-hit path")
F.say(fails == 0 and "PASS" or "FAIL")
