local F, E, R = require("fake"), require("eve"), require("rag")
local pawn = E.make(F)
local out = F.say
rawset(pawn, "bHidden", false)
local hidden = {}
rawset(pawn, "SetActorHiddenInGame", function(self, value) self.bHidden = value; hidden[#hidden + 1] = value end)
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"
R.install(F, E); F.world = R.step
local settings = assert(io.open("ue4ss/Mods/StellarBladeGore/Scripts/settings.lua", "w"))
settings:write('local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua"); s.deathScreen = "key"; return s')
settings:close()
local cue = F.obj("UI_YouDied", "SoundWave")
F.objects["/Game/Sound/UI/UI_YouDied.UI_YouDied"] = cue
local gs = F.obj("Default__GameplayStatics", "GameplayStatics")
F.objects["/Script/Engine.Default__GameplayStatics"] = gs
local sounds = 0
rawset(gs, "PlaySound2D", function(_, _, sound) if sound == cue then sounds = sounds + 1 end end)
assert(pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua"))
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil)); F.run(16, pawn)
E.die(true); F.run(3, pawn)
local w = E.deadScreen
rawset(w, "GetAnimationCurrentTime", function() return 0.1 end)
rawset(w, "SetAnimationCurrentTime", function() end)
local cls = w:GetClass()
cls.Animations:ForEach(function(_, e) rawset(e:get(), "GetEndTime", function() return 4 end) end)
F.press("F4", "SHIFT"); F.run(1, pawn)
local failures = 0
local function check(ok, message) out((ok and "ok   " or "FAIL ") .. message); if not ok then failures = failures + 1 end end
check(sounds == 1, "skipped intro plays the game's defeat sound once")
F.fire("/Game/Art/UI/Widget/HUD/WB_MainHUD_Dead.WB_MainHUD_Dead_C:FinishPressAnimation")
F.run(0.2, pawn)
check(hidden[1] == true and pawn.bHidden == true, "recovery hides the transient pose before cleanup")
F.run(0.6, pawn)
check(hidden[2] == false and pawn.bHidden == false, "the actor becomes visible again")
check(#F.errors == 0 and not F.find("tick error"), "no hook or tick errors")
out(failures == 0 and "PASS" or "FAIL")
