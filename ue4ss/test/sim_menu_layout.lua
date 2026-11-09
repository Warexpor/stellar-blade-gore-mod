-- Grouped/classic layout and visual dependencies using the shipped row definitions.
local F=require("fake")
local dir="ue4ss/Mods/StellarBladeGore/Scripts/"
local tune=dofile(dir.."tune.lua")
local defaults=dofile(dir.."settings.default.lua")
local menu=dofile(dir.."gui.lua")
local fails=0
local function check(ok,what) F.say((ok and "ok   " or "FAIL ")..what); if not ok then fails=fails+1 end end
menu.init({tune=tune, log=function() end, try=function(f) local ok,v=pcall(f); if ok then return v end end, valid=function(o) return o~=nil end})
local function index(key)
  for i,r in ipairs(menu.ROWS) do if r.key==key or r.call==key then return i,r end end
end
local function row(key) local _,r=index(key); assert(r,key); return r end
check(tune.gore.smash.enabled and defaults.gore.smash.enabled and not defaults.gore.smash.always,
  "shipped blunt smash enabled and Smash Every Death disabled")
check(index("gore.smash.enabled")==index("gore.enabled")+1,"grouped layout places blunt smash near the master")
check(index("enemies.cutChance")==index("enemies.enabled")+1,"enemy cut chance follows enemy gore")
check(index("reviveAt")==index("deathScreen")+1,"death screen delay follows its mode")
local original={}; for _,r in ipairs(menu.ROWS) do original[r]=true end
local before=#menu.ROWS
local sm=row("gore.smash.always")
tune.gore.smash.enabled=false
check(menu.dimmed(sm),"smash child is visually inactive when parent off")
tune.gore.smash.enabled=true
check(not menu.dimmed(sm),"smash child brightens when parent on")
local range=row("stains.splash.range")
tune.stains.enabled=false; tune.stains.splash.enabled=true
check(menu.dimmed(range),"nested child dims when outer toggle off")
tune.stains.enabled=true; tune.stains.splash.enabled=false
check(menu.dimmed(range),"nested child dims when inner toggle off")
tune.stains.splash.enabled=true
check(not menu.dimmed(range),"nested child brightens when both toggles on")
tune.active.animated=true; tune.gore.headRagdoll=false
check(not menu.dimmed(row("gore.headRagdollChance")),"inverse dependency: chance is active when forced ragdoll is off")
tune.gore.headRagdoll=true
check(menu.dimmed(row("gore.headRagdollChance")),"inverse dependency: chance dims when forced ragdoll is on")
menu.state.sel=index("menuGrouped"); tune.menuGrouped=false; menu.refresh()
check(menu.ROWS[menu.state.sel].key=="menuGrouped","reordering preserves selection")
check(index("gore.smash.enabled")>index("gore.death.limb"),"classic layout restores original order")
check(#menu.ROWS==before,"classic layout keeps all rows")
local same=true; for _,r in ipairs(menu.ROWS) do same=same and original[r]==true end
check(same,"classic layout retains the same settings and buttons")
tune.menuGrouped=true; menu.refresh()
check(index("gore.smash.enabled")==index("gore.enabled")+1,"grouped layout can be restored")
-- key icons resolve from memory, with a DualShock4 twin as fallback; misses are remembered for a later open
local dsb = "DualSense/KeyIcon_DualSense_Gamepad_FaceButton_Bottom"
local dsbfull = menu.ICONS..dsb..".KeyIcon_DualSense_Gamepad_FaceButton_Bottom"
local ds4full = menu.ICONS.."DualShock4/KeyIcon_DualShock4_Gamepad_FaceButton_Bottom.KeyIcon_DualShock4_Gamepad_FaceButton_Bottom"
check(menu.icon_tex(dsb) == nil and menu.missingIcons[dsb] == true, "a missing icon is remembered, not a crash")
F.objects[ds4full] = F.obj("DualShock4 cross", "Texture2D")
check(menu.icon_tex(dsb) == F.objects[ds4full] and menu.missingIcons[dsb] == nil, "the DualShock4 twin fills in for a missing DualSense icon")
F.objects[dsbfull] = F.obj("DualSense cross", "Texture2D")
check(menu.icon_tex(dsb) == F.objects[dsbfull], "the DualSense icon wins when both are in memory")
F.say(fails==0 and "PASS" or "FAIL")
