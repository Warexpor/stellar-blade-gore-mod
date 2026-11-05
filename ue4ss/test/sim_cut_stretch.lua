-- Cut stretch warning (slice_response.widest, gore.lua's "cut stretch" line): a cap or lid dozens
-- of cm across is a drawn-out spike, not an opening. Two thigh after-cuts from the November 5 session log
-- both qualify (a 228 cm lid and a 45 cm cap on legs whose calf was already off elsewhere); an ordinary
-- thigh death cut does not, and a response without cap/lid fields gives nil.
local F = require("fake")
local print = F.say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local response = dofile("ue4ss/Mods/StellarBladeGore/Scripts/slice_response.lua")
-- an ordinary thigh death cut: 10.9 cm cap, 10.3 cm lid
local normal = "ok verts=62882 mode=0 limb=5984 seam=186 vanished=0 unsunk=0 reweighted=4727 stuck=0 watched=534 far=1.0 new=2 sinkmoved=2 held=2 active=928/0 pieces=4 be=10.9,9.1,2.9 le=10.3,9.6,3.1"
check(response.widest(normal) and math.abs(response.widest(normal) - 10.9) < 0.01, "ordinary cut: widest is the 10.9 cm cap")
check(not (response.widest(normal) > 40), "ordinary cut: below the 40 cm warning line")
-- the session's R-Thigh after-cut: 41.1 cm cap, 228 cm lid
local spike = "ok verts=62882 mode=0 limb=5676 seam=141 vanished=0 unsunk=0 reweighted=4226 stuck=0 watched=409 far=20.7 new=2 sinkmoved=2 held=6 active=928/1 pieces=6 be=8.7,7.5,41.1 le=228.0,5.0,76.8"
check(response.widest(spike) and math.abs(response.widest(spike) - 228.0) < 0.01, "spike cut: widest is the 228 cm lid")
check(response.widest(spike) > 40, "spike cut: over the 40 cm warning line")
-- the session's L-Thigh after-cut: 45 cm cap, 26.1 cm lid
local spike2 = "ok verts=62882 mode=0 limb=3124 seam=349 vanished=0 unsunk=0 reweighted=4516 stuck=0 watched=185 far=20.6 new=3 sinkmoved=3 held=5 active=928/2 pieces=0 be=17.9,4.5,45.0 le=26.1,18.1,24.4"
check(response.widest(spike2) and math.abs(response.widest(spike2) - 45.0) < 0.01, "second spike: widest is the 45 cm cap")
check(response.widest(spike2) > 40, "second spike: over the 40 cm warning line")
-- the sims' canned response has no cap/lid fields at all
local plain = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 pieces=5"
check(response.widest(plain) == nil, "no cap/lid fields: nil, no warning")
check(response.widest("") == nil, "empty response: nil, no warning")
print(fails == 0 and "PASS" or "FAIL")
