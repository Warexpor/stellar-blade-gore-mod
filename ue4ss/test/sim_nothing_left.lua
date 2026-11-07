-- gore.nothing_left: every cuttable part gone (all limb segments, her head, her upper body) reads true;
-- anything whole reads false. Enemies stop attacking a body with nothing left to hit.
local T = require("smash_world").boot('')
local F, E, G, pawn = T.F, T.E, T.G, T.pawn
local print, fails = F.say, 0
local function check(c, what) print((c and "ok   " or "FAIL ") .. what); if not c then fails = fails + 1 end end
local function run(seconds)
  for _ = 1, math.floor(seconds * 60 + 0.5) do F.step(1/60); G.tick(pawn); G.pump() end
end
E.s.sim = true
check(G.nothing_left(E.mesh) == false, "whole: something left to hit")
-- one arm off: the rest remains
check(G.slice_bone(pawn, E.mesh, "Bip001-L-Forearm", nil, "test"), "forearm cut starts")
run(2)
check(G.nothing_left(E.mesh) == false, "one arm off: the rest remains")
-- the rest, ends first (a hand always leaves with its segment's piece), head and torso last
for _, b in ipairs({ "Bip001-R-Forearm", "Bip001-L-Calf", "Bip001-R-Calf", "Bip001-L-UpperArm",
  "Bip001-R-UpperArm", "Bip001-L-Thigh", "Bip001-R-Thigh", "Bip001-Head", "Bip001-Spine1" }) do
  check(G.slice_bone(pawn, E.mesh, b, nil, "test"), b .. " cut starts")
  run(2)
end
check(G.nothing_left(E.mesh) == true, "everything cut: nothing left to hit")
-- playtest mirror: torso smashed at death, then a blunt leg hit (lower-body remainder). The upper body gone
-- leaves the legs hittable and the loop on; the remainder's full-body entry ends it.
G.cleanup(pawn, E.mesh)
run(0.5)
local function mid(a, b) local A, B = E.bone(a), E.bone(b)
  return { X = (A.X + B.X) / 2, Y = (A.Y + B.Y) / 2, Z = (A.Z + B.Z) / 2 } end
G.aim({ X = 1, Y = 0, Z = 0 })
check(G.smash(pawn, E.mesh, { loc = mid("Bip001-Spine1", "Bip001-Spine2") }, "death"), "torso smash starts")
run(0.6)
check(G.nothing_left(E.mesh) == false, "torso smashed: legs remain, loop stays on")
local whole = {}
for _, s in ipairs(G.cut_state(E.mesh)) do if s:find("=whole", 1, true) then whole[#whole + 1] = s end end
check(#whole > 0, "verdicts name the remaining parts (" .. table.concat(whole, ", ") .. ")")
for _, s in ipairs(G.cut_state(E.mesh)) do
  local b, how = s:match("^(.-)=(.+)$")
  check((how == "whole") == (not G.already_cut(E.mesh, b)), "verdict agrees with already_cut on " .. b)
end
G.aim({ X = 1, Y = 0, Z = 0 })
check(G.smash(pawn, E.mesh, { loc = mid("Bip001-R-Thigh", "Bip001-R-Calf") }, "after"), "remainder: blunt leg hit smashes")
run(0.6)
check(G.nothing_left(E.mesh) == true, "remainder: full-body entry ends the loop")
for _, s in ipairs(G.cut_state(E.mesh)) do check(not s:find("=whole", 1, true), "remainder verdict: " .. s) end
check(#F.errors == 0, "no errors")
G.cleanup(pawn, E.mesh)
print(fails == 0 and "PASS" or "FAIL")
