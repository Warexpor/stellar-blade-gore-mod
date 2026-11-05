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
check(G.cuts_on(E.mesh) == 0, "after-death cut clears on recovery")
check(#F.errors == 0 and not F.find("tick error"), "no errors")
out(fail == 0 and "PASS" or "FAIL")
