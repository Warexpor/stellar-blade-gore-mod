-- Exercise the registered key and recovery with automatic smash disabled.
local T = require("smash_world").boot('s.gore.smash = { enabled = false, always = false }\ns.gore.blood = false')
local F, E, G, pawn, K = T.F, T.E, T.G, T.pawn, T.ctx.keys
local fails = 0
local function check(ok, what)
  F.say((ok and "ok   " or "FAIL ") .. what)
  if not ok then fails = fails + 1 end
end
check(K.binding("smash") == "F10" and not K.BY_ID.mark, "smash keeps F10 and parked hit mark has no action")
K.uv = true
check(K.binding("smash") == "F10" and not K.BY_ID.mark, "Ultra Violence keeps F10 and the hit mark parked")
K.uv = false
local hits, original = 0, K.handlers.mark
K.handlers.mark = function(...) hits = hits + 1; return original(...) end
for _, kind in ipairs({ "limb", "head", "torso" }) do
  T.ctx.tune.gore.death = { limb = 0, head = 0, torso = 0, split = 100 }
  T.ctx.tune.gore.death[kind] = 100
  check(F.press("F10", ""), kind .. ": plain F10 is registered")
  F.run(1, pawn)
  local n = 0
  for _ in pairs(E.hiddenBones) do n = n + 1 end
  check(E.s.sim and n > 0, kind .. ": random smash ragdolls and hides the part")
  check(#T.world.spheres > 0, kind .. ": meat burst emitted")
  check(hits == 0, kind .. ": F10 did not invoke Hit Mark")
  check(not T.ctx.tune.gore.smash.enabled and not T.ctx.tune.gore.smash.always, "automatic smash settings preserved")
  F.press("F8", "")
  F.run(2, pawn)
  check(not E.s.sim and next(E.hiddenBones) == nil, kind .. ": F8 restores her")
  for _, a in ipairs(T.world.actors) do check(a.__dead, "recovery destroys meat actor") end
end
F.press("F10", "ALT")
F.run(0.2, pawn)
check(hits == 0, "Alt+F10 does not invoke the parked hit mark")
T.ctx.tune.dev = false
local count = #T.world.actors
F.press("F10", "")
F.run(1, pawn)
check(not E.s.sim and #T.world.actors == count, "Developer Keys off blocks smash")
for _, e in ipairs(F.errors) do check(false, "hook: " .. e) end
F.say(fails == 0 and "PASS" or "FAIL")
