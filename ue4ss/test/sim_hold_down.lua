-- Hold-down diagnostics: short interruptions, height changes, long getups and disabled tracking.
local T = require("smash_world").boot("s.gore.blood = false")
local F, E, pawn, hm = T.F, T.E, T.pawn, T.state.hm
local fails = 0
local function check(ok, what) F.say((ok and "ok   " or "FAIL ") .. what); if not ok then fails = fails + 1 end end
local stance, z = "Down_Eve", 30
rawset(pawn, "GetCurrentStanceName", function() return F.fname(stance) end)
local mont = F.obj("HitReaction", "AnimMontage")
local ai = F.obj("Animation", "AnimInstance", { GetCurrentActiveMontage = function() return mont end })
rawset(E.mesh, "GetAnimInstance", function() return ai end)
local socket = E.mesh.GetSocketLocation
rawset(E.mesh, "GetSocketLocation", function(self, bone)
  if tostring(bone) == "Bip001-Head" then return { X = 0, Y = 0, Z = z } end
  return socket(self, bone)
end)
local function watch(s, dt) stance = s; F.step(dt or 0.1); hm.guard_watch(pawn, E.mesh) end
local function count(needle)
  local n, last = 0, nil
  for _, line in ipairs(F.log_lines()) do if line:find(needle, 1, true) then n, last = n + 1, line end end
  return n, last
end
watch("Down_Eve")
watch("HitReaction")
watch("HitReaction")
mont = F.obj("LateReaction", "AnimMontage")
watch("HitReaction")
watch("Down_Eve")
local n, line = count("hold down: down broken by")
check(n == 1 and line:find("HitReaction [HitReaction] > HitReaction [LateReaction]", 1, true)
  and not line:find("[HitReaction] > HitReaction [HitReaction]", 1, true),
  "short break records a later montage without duplicating unchanged samples")
z = 130; watch("Down_Eve")
check(count("hold down: head up") == 1, "head-height diagnostic is not suppressed by a recent break log")
watch("Stand")
watch("Stand", 2.1)
watch("Down_Eve")
check(count("hold down: down broken by") == 1, "a long getup does not log a flicker")
T.ctx.tune.holdDown = false
watch("Stand")
T.ctx.tune.holdDown = true
watch("Down_Eve")
check(count("hold down: down broken by") == 1, "disabling the feature discards an old interruption")
check(#F.errors == 0, "no errors")
F.say(fails == 0 and "PASS" or "FAIL")
