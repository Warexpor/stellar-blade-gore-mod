local install = dofile('ue4ss/Mods/StellarBladeGore/Scripts/death_hud.lua')
local function check(ok, msg) if not ok then error(msg) end end
local function widget(name, children, visibility)
  local w = { name = name, children = children or {}, visibility = visibility or 0 }
  function w:GetFName() return { ToString = function() return self.name end } end
  function w:GetClass() return { GetFName = function() return { ToString = function() return 'Widget' end } end } end
  function w:GetAddress() return self end
  function w:GetChildrenCount() return #self.children end
  function w:GetChildAt(i) return self.children[i + 1] end
  function w:GetVisibility() return self.visibility end
  function w:SetVisibility(v) self.visibility = v end
  return w
end
local health, dead, revive = widget('Health'), widget('DeadScreen'), widget('ReviveScreen')
local branch = widget('DeathBranch', { dead, revive, widget('Other') })
local root = widget('Root', { health, branch })
local master = widget('Master')
master.WidgetTree = { RootWidget = root }
local state = { active = true, manual = false, tune = {} }
local ctx = { keep = function(o) return { obj = o } end, held = function(k) return k and k.obj ~= nil end }
local screen = {}
local function try(fn) local ok, v = pcall(fn); if ok then return v end end
local dead_hud = { get = function() return nil end }
FindAllOf = function() return { master } end
install(screen, ctx, dead_hud, function(o) return o ~= nil end, try, function() end,
  function() return state.active end, function() return state.manual end, function() return state.tune end)
screen.hud(0.9)
check(health.visibility == 0 and not screen.hudHid, 'HUD hidden too early')
screen.hud(1)
check(health.visibility == 1 and branch.children[3].visibility == 1, 'ordinary HUD must hide')
check(dead.visibility == 0 and revive.visibility == 0, 'death and revive branches must remain visible')
state.active = false
screen.hud(2)
check(health.visibility == 0 and branch.children[3].visibility == 0 and not screen.hudHid, 'recovery must restore HUD')
state.active = true
state.tune.hideHud = false
screen.hud(2)
check(not screen.hudHid, 'reloaded HUD setting must take effect')
state.tune.hideHud = true
state.manual = true
screen.hud(2)
check(not screen.hudHid, 'manual ragdoll must leave HUD visible')
state.manual = false
screen.hud(2)
ctx.held = function() return false end
screen.hud(2)
state.active = false
screen.hud(2)
check(not screen.hudHid and health.visibility == 1, 'stale master must not restore children')
print('PASS')
