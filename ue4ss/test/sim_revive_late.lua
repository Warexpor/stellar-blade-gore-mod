-- The post-respawn movement guard must run for its entire advertised window.
local F, E = require("fake"), require("eve")
local pawn = E.make(F)
local R = require("rag")
R.install(F, E); F.world = R.step
rawset(pawn.CharacterMovement, "SetMovementMode", function(_, mode) E.s.mode = mode end)
assert(pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua"))
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil)); F.run(16, pawn)
E.die(true); F.run(3, pawn)
E.respawn(); F.run(12, pawn)
E.s.mode = 0
F.run(2.5, pawn)
local ok = E.s.mode == 1 and F.find("revived in place: her movement was off") ~= nil
F.say((ok and "ok   " or "FAIL ") .. "movement disabled 12 s after respawn is restored")
F.say(ok and "PASS" or "FAIL")
