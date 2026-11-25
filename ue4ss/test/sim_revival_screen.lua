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
local hudChildren = {}
local hud = F.obj("WB_MainHUD_Master_C_0", "WB_MainHUD_Master_C", {
  GetWidgetFromName = function(_, name) return hudChildren[tostring(name)] end,
  IsInViewport = function() return true end,
})
local oldHud = F.obj("WB_MainHUD_Master_C_1", "WB_MainHUD_Master_C")
F.classes.WB_MainHUD_Master_C = { oldHud, hud } -- Both predate the creation watch.
assert(pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua"))
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil)); F.run(16, pawn)
E.s.hp = 0; F.run(0.2, pawn)
local newObject = F.new_object
F.new_object = function() end
E.die(true)
F.new_object = newObject
F.run(0.2, pawn)
local w = E.deadScreen
local initiallyHidden = w.__w.vis == 1
rawset(w, "GetAnimationCurrentTime", function() return 0.1 end)
rawset(w, "SetAnimationCurrentTime", function() end)
local cls = w:GetClass()
cls.Animations:ForEach(function(_, e) rawset(e:get(), "GetEndTime", function() return 4 end) end)
F.press("F4", "SHIFT"); F.run(1, pawn)
local failures = 0
local function check(ok, message) out((ok and "ok   " or "FAIL ") .. message); if not ok then failures = failures + 1 end end
check(initiallyHidden, "On Press holds an immediate death widget even if the creation watch missed it")
check(sounds == 1, "skipped intro plays the game's defeat sound once")
F.fire("/Game/Art/UI/Widget/HUD/WB_MainHUD_Dead.WB_MainHUD_Dead_C:FinishPressAnimation")
E.s.mode = 0 -- the game has not completed its respawn; the death screen and empty bar are still present
F.run(0.2, pawn)
check(hidden[1] == true and pawn.bHidden == true, "recovery hides the transient pose before cleanup")
check(not F.find("death: taken over"), "the old death is not taken over again during respawn")
check(not E.s.sim, "the old death does not start another ragdoll")
F.run(0.6, pawn)
check(hidden[2] == false and pawn.bHidden == false, "the actor becomes visible again")
E.respawn(); F.run(2, pawn)
E.s.hp = 0; F.run(0.2, pawn); E.die(false); F.run(1, pawn)
check(F.find("death: taken over") ~= nil and E.s.sim, "a new death without a ragdoll is still taken over")
E.respawn(); F.run(2, pawn)
E.s.hp = 0; F.run(0.2, pawn)
F.new_object = function() end
E.die(true)
F.new_object = newObject
local lateDeath = E.deadScreen
F.classes.WB_MainHUD_Dead_C = nil
F.run(0.4, pawn) -- Both initial lookups have missed the widgets.
local reviveVisibility, reviveEnabled = 4, true
hudChildren.WB_MainHUD_Dead = lateDeath
hudChildren.WB_MainHUD_ResurrectionItem = F.obj("WB_MainHUD_ResurrectionItem", "WB_MainHUD_ResurrectionItem_C", {
  GetVisibility = function() return reviveVisibility end,
  SetVisibility = function(_, vis) reviveVisibility = vis end,
  SetIsEnabled = function(_, enabled) reviveEnabled = enabled end,
})
F.run(0.25, pawn)
check(lateDeath.__w.vis == 1, "On Press holds a late death widget from the HUD before the later object scan")
check(reviveVisibility == 1 and not reviveEnabled, "On Press also holds a missed resurrection widget from the HUD")
F.press("F4", "SHIFT"); F.run(0.3, pawn)
check(lateDeath.__w.vis == 4 and reviveVisibility == 4 and reviveEnabled, "Hold the Death releases both HUD widgets")
check(#F.errors == 0 and not F.find("tick error"), "no hook or tick errors")
out(failures == 0 and "PASS" or "FAIL")
