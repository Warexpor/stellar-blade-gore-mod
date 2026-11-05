-- a killing blow in a grab: limbs cut at the hit, her head and body wait for her death
-- (a cut opened under the finisher read as reattached once the show moved her on)
local print = require("fake").say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local M = {}
local d = {
  PARTS = {}, SPINE_CHAIN = {}, enemy = {},
  cfg = function() return {} end, log = function() end,
  already_cut = function() return false end,
  bone_tm = function() end, start = function() return true end,
  norm = function(v) return v end, cross = function() end,
  dot = function() return 0 end, vec = function() return {} end,
  add = function() end, sub = function() end, scale = function() end,
  qrot = function(_, v) return v end, qinv = function(q) return q end,
  CUT_AT_DEFAULT = 0.4, SPINE_TOL = 1,
  body_frame = function() end, from_body = function() end, to_body = function() end,
  mark = function() end, v3 = function() return function() return "" end end,
  ctx = function() return {} end,
  queued = function() return {} end, aimed = function() end, set_aimed = function() end,
}
local install = dofile("ue4ss/Mods/StellarBladeGore/Scripts/blade_decision.lua")
install(M, d)
check(type(M.early_waits) == "function", "early wait rule exists")
-- limbs cut at once, grab or not
check(M.early_waits("limb", { early = true, grab = true }) == false, "a limb in a grab cuts at the hit")
check(M.early_waits("limb", { early = true }) == false, "a limb cuts at the hit")
-- her head and body wait in a grab, cut at once otherwise
check(M.early_waits("head", { early = true, grab = true }) == true, "her head in a grab waits for her death")
check(M.early_waits("torso", { early = true, grab = true }) == true, "her body in a grab waits for her death")
check(M.early_waits("head", { early = true }) == false, "her head cuts at the hit")
check(M.early_waits("torso", { early = true }) == false, "her body cuts at the hit")
-- splits always wait, and nothing waits without an early cut
check(M.early_waits("split", { early = true, grab = true }) == true, "a split in a grab waits for her death")
check(M.early_waits("split", { early = true }) == true, "a split waits for her death")
check(M.early_waits("head", {}) == false, "no early cut: nothing waits")
check(M.early_waits("head", nil) == false, "no hit: nothing waits")
print(fails == 0 and "PASS" or "FAIL")
