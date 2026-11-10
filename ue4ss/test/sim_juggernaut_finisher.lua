-- Replay the impact cues of the extracted S09 grab animation through the registered hook.
local T = require("smash_world").boot('s.gore.blood = false\ns.gore.smash.enabled = true')
local F, G, pawn, hm = T.F, T.G, T.pawn, T.state.hm
local print, fails = F.say, 0
local function check(ok, what) print((ok and "ok   " or "FAIL ") .. what); if not ok then fails = fails + 1 end end
local calls, busy = {}, false
local oldSmash, oldBusy = G.smash, G.busy
rawset(pawn, "GetGameTimeSinceCreation", function() return F.t end)
G.busy = function() return busy end
G.smash = function(_, _, hit, why) calls[#calls + 1] = { t = os.clock(), hit = hit, why = why }; return true end
local path = "/Script/SB.SBCharacter:ActorPlayCustomAnimSequence"
local anim = F.obj("Hit_SkullJuggernaut_Beta_Grab", "AnimSequence")
local other = F.obj("Other", "SBCharacter")
check(F.fire(path, F.param(other), F.param(anim)) > 0, "animation hook is registered")
check(hm.juggernaut.run == nil, "another actor does not start the player finisher")
F.fire(path, F.param(pawn), F.param(F.obj("Unrelated", "AnimSequence")))
check(hm.juggernaut.run == nil, "unrelated animation is ignored")
local t = os.clock()
F.fire(path, F.param(pawn), F.param(anim))
check(hm.juggernaut.run ~= nil, "the player grab animation is recognized")
for i = 1, 65 do
  F.step(0.05)
  if i == 2 then F.fire(path, F.param(pawn), F.param(anim)) end
  hm.juggernaut.tick(pawn, T.E.mesh)
end
check(#calls == 3, "three impacts fire once each, despite a duplicate animation callback")
for i, at in ipairs({ 1.565, 2.055, 2.82 }) do
  local c = calls[i]
  check(c and math.abs(c.t - t - at) < 0.06 and c.hit.grabPound and c.why == "grab",
    "impact " .. i .. " uses the asset timing and limb-only smash")
end
-- A recent independently detected pound suppresses the fallback.
calls = {}; hm.poundT = os.clock() + 1.55
F.fire(path, F.param(pawn), F.param(anim))
for _ = 1, 33 do F.step(0.05); hm.juggernaut.tick(pawn, T.E.mesh) end
check(#calls == 0, "a recorded pound suppresses the same animation impact")
hm.poundT, hm.juggernaut.run = nil, nil
-- Once an active custom-animation alpha has been observed, ending it cancels later impacts.
local alpha = 1
rawset(pawn, "GetCurrentCustomAnimAlpha", function() return alpha end)
F.fire(path, F.param(pawn), F.param(anim))
for _ = 1, 10 do F.step(0.05); hm.juggernaut.tick(pawn, T.E.mesh) end
alpha = 0
F.step(0.05); hm.juggernaut.tick(pawn, T.E.mesh)
check(hm.juggernaut.run == nil and #calls == 0, "interrupted animation cancels the fallback")
-- The game's own show slows time without changing the mod's slow-motion flag.
-- Impacts must follow game time, not real time.
rawset(pawn, "GetCurrentCustomAnimAlpha", function() return 1 end)
local gameTime, started = 0, os.clock()
rawset(pawn, "GetGameTimeSinceCreation", function() return gameTime end)
F.fire(path, F.param(pawn), F.param(anim))
for i = 1, 46 do
  F.step(0.05)
  gameTime = gameTime + 0.05 * (i <= 20 and 0.4 or 1)
  hm.juggernaut.tick(pawn, T.E.mesh)
end
check(#calls == 1 and calls[1].t - started > 2.1, "show slow motion delays the impact until its game-time cue")
G.smash, G.busy = oldSmash, oldBusy
check(#F.errors == 0, "no hook errors")
print(fails == 0 and "PASS" or "FAIL")
