local T = require("smash_world").boot('s.gore.noSplits = true\ns.gore.bladeJitter = 0\ns.gore.multiCut = { enabled = false }')
local F, E, G, pawn, v = T.F, T.E, T.G, T.pawn, T.v
local out, fail = F.say, 0
local function check(x, msg) out((x and "ok   " or "FAIL ") .. msg); if not x then fail = fail + 1 end end
local function blow(bone, want)
  local n = #F.log_lines() + 1
  local loc = E.bone(bone)
  if bone == "Bip001-Spine2" then loc.Z = loc.Z + 5 end
  local ok = G.blow(pawn, E.mesh, { loc = loc, n = v(0, 1, 0), dir = v(0, 0, -1) }, "death")
  check(ok and F.find("vertical split redirected to " .. want, n), bone .. " redirects to " .. want)
  for _ = 1, 60 do F.step(1/60); G.tick(pawn); G.pump() end
  G.cleanup(pawn, E.mesh)
end
E.s.sim = true
blow("Bip001-Spine1", "torso")
blow("Bip001-Spine2", "head")
local start = #F.log_lines() + 1
local result = G.blow(pawn, E.mesh, { loc = E.bone("Bip001-Spine1"), n = v(0, 1, 0), noSplit = true }, "after")
check(result and F.find("vertical split redirected to torso", start), "after-death hit can redirect when a split is otherwise disallowed")
G.cleanup(pawn, E.mesh)
check(#F.errors == 0 and not F.find("tick error"), "no errors")
out(fail == 0 and "PASS" or "FAIL")
