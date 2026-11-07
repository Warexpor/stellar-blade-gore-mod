local T = require("smash_world").boot('s.gore.noSplits = true\ns.gore.bladeJitter = 0\ns.gore.multiCut = { enabled = false }')
local F, E, G, pawn, v = T.F, T.E, T.G, T.pawn, T.v
local out, fail = F.say, 0
local function check(x, msg) out((x and "ok   " or "FAIL ") .. msg); if not x then fail = fail + 1 end end
local function blow(bone, want)
  local loc = E.bone(bone)
  if bone == "Bip001-Spine2" then loc.Z = loc.Z + 5 end
  local ok = G.blow(pawn, E.mesh, { loc = loc, n = v(0, 1, 0), dir = v(0, 0, -1) }, "death")
  check(ok, bone .. " accepts the blow")
  for _ = 1, 60 do F.step(1/60); G.tick(pawn); G.pump() end
  local parts = G.cut_parts(E.mesh)
  local count, split = G.cuts_on(E.mesh)
  local expected = want == "head" and "Bip001-Head" or "Bip001-Spine1"
  check(count == 1 and not split and #parts == 1 and parts[1] == expected,
    bone .. " produces a " .. want .. " cut without a split")
  G.cleanup(pawn, E.mesh)
  check(G.cuts_on(E.mesh) == 0, bone .. " cut clears on recovery")
end
E.s.sim = true
blow("Bip001-Spine1", "torso")
blow("Bip001-Spine2", "head")
local result = G.blow(pawn, E.mesh, { loc = E.bone("Bip001-Spine1"), n = v(0, 1, 0), noSplit = true }, "after")
check(result, "after-death hit accepts a redirected blow")
for _ = 1, 60 do F.step(1/60); G.tick(pawn); G.pump() end
local parts = G.cut_parts(E.mesh)
local count, split = G.cuts_on(E.mesh)
check(count == 1 and not split and #parts == 1 and parts[1] == "Bip001-Spine1",
  "after-death hit produces a torso cut without a split")
G.cleanup(pawn, E.mesh)
check(G.cuts_on(E.mesh) == 0, "recovery clears the after-death cut")
G.slice_bone(pawn, E.mesh, "Bip001-L-UpperArm", nil, "after")
for _ = 1, 60 do F.step(1/60); G.tick(pawn); G.pump() end
check(G.cuts_on(E.mesh) == 1, "limb cut completes first")
local okTorso = G.blow(pawn, E.mesh, { loc = E.bone("Bip001-Spine1"), n = v(0, 1, 0), noSplit = true }, "after")
check(okTorso, "after-death torso blow with a limb already off is accepted")
for _ = 1, 60 do F.step(1/60); G.tick(pawn); G.pump() end
local parts2 = G.cut_parts(E.mesh)
local count2, split2 = G.cuts_on(E.mesh)
local torso = false
for _, p in ipairs(parts2) do if p == "Bip001-Spine1" then torso = true end end
check(count2 == 2 and not split2 and torso and #parts2 == 2,
  "torso cut lands after a limb cut, and still no split")
G.cleanup(pawn, E.mesh)
check(G.cuts_on(E.mesh) == 0, "after-death cut clears on recovery")
check(#F.errors == 0 and not F.find("tick error"), "no errors")
out(fail == 0 and "PASS" or "FAIL")
