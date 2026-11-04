-- A level reload (a fast travel, a load) with her right arm cut off her alive (Lose Arm at Low HP, Alt+F8). The game
-- makes a new Eve wearing the same mesh asset; the cut's collapsed helper bones (sbslice's sinks: the asset's own
-- inverse bind matrices) outlive the old level, so they must be put back for that asset (sbslice "r<asset>") as the
-- old Eve is dropped, or the new one shows the arm gone with nothing cut. The arm stays off on the new Eve (the
-- level's cutscene showed her whole and the arm back, Nexus report): cut again quietly, her blocks with it, unless her
-- HP bar says a save was loaded (the arm back then)
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.gore.lowArm.enabled = true
return s
]])
f:close()
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"
-- her outfit's mesh asset, the same on the new Eve
local ASSET = F.obj("SK_CH_P_EVE_01", "SkeletalMesh")
rawset(E.mesh, "SkeletalMesh", ASSET)
local ok, err = pcall(dofile, DIR .. "main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function mark() return #F.log_lines() + 1 end

local at = mark()
E.s.hp = 0.3
F.run(0.5, pawn)
F.press("F8", "ALT")
F.run(3, pawn)
check(F.find("her right arm cut off", at) ~= nil, "Alt+F8: her right arm cut off")

-- the level reloads: the old Eve gone (no tick of hers again), a new one ticking
local c0 = #F.cmds
local old = pawn
pawn = E.make(F)
rawset(E.mesh, "SkeletalMesh", ASSET)
old.__dead = true
-- (freed: her watches queued by the old one's last poll held it, and asking it crashed the game, playtest)
old.__freed = true
local r0 = mark()
-- A reload can discard the death widgets while a fade or customized-ragdoll overlay is still pending.
local screen, seen
seen={}
local function scan(fn)
  if type(fn)~="function" or seen[fn] then return end
  seen[fn]=true
  for i=1,math.huge do
    local name,value=debug.getupvalue(fn,i)
    if not name then break end
    if name=="screen" and type(value)=="table" and value.revive then screen=value end
    if name~="_ENV" and type(value)=="function" then scan(value) end
  end
end
for _,callbacks in pairs(F.hooks) do for _,cb in ipairs(callbacks) do scan(cb) end end
check(screen~=nil,"reload screen state found")
if screen then
  local reads={}
  local function widget(name, children)
    local w=F.obj(name,"Widget")
    w.GetChildrenCount=function() reads[name]=(reads[name] or 0)+1; return #(children or {}) end
    w.GetChildAt=function(_,i) return children[i+1] end
    w.GetVisibility=function(self) return self.visibility or 0 end
    w.SetVisibility=function(self,v) self.visibility=v end
    return w
  end
  local death=widget("Dead",{})
  local other=widget("Health",{})
  local inner=widget("Inner",{death,other})
  local outer=widget("Outer",{inner})
  local root=widget("Root",{outer})
  local keeps=screen.hud_keeps
  screen.hud_keeps=function(w) return w.__name=="Dead" end
  local hidden={}
  screen.hud_hide(0,root,hidden)
  screen.hud_keeps=keeps
  check(#hidden==1 and hidden[1].w==other and other.visibility==1 and death.visibility==nil,
    "HUD traversal keeps the death branch and hides its unrelated sibling")
  check((reads.Inner or 0)<=2,"HUD traversal reuses the subtree result")
end
local freed=F.obj("old death screen", "UserWidget")
freed.__freed=true
if screen then screen.fade={w=freed,t=F.t}; screen.rv.ghost={old=freed}; screen.rv.held={w=1} end
local errorsBefore=#F.errors
F.run(9, pawn)
check(not screen or (screen.fade==nil and screen.rv.ghost==nil),"new world drops old fade and revive widget references")
local touched=false
for i=errorsBefore+1,#F.errors do if F.errors[i]:find("old death screen",1,true) then touched=true end end
check(not touched,"reload never reads the freed old screen")
-- (the new level's HP bar reads full till the game sets it, after its cutscene)
E.s.hp = 0.3
F.run(1, pawn)
check(F.find("new Eve .* the level reloaded", r0) ~= nil, "the new Eve adopted")
local want = string.format("r%x", ASSET.__addr)
local put = false
for i = c0 + 1, #F.cmds do if F.cmds[i].s == want or F.cmds[i].s == "r" then put = true end end
check(put, "her cut's helper bones put back for her mesh asset (" .. want .. ")")
check(F.find("level change with Bip001%-R%-UpperArm cut off her alive %(HP bar 0%.300%)", r0) ~= nil, "the arm carried")
check(F.find("Bip001%-R%-UpperArm off %(carried%): .*the piece hidden", r0) ~= nil, "cut again on the new Eve, quietly")
check(F.find("Bip001%-R%-UpperArm off %(low HP", r0) == nil and F.find("piece flies", r0) == nil, "no second piece")
check(F.find("low HP arm: her right arm is off: no sword", r0) ~= nil, "No Sword on the new Eve")
check(F.find("carried: her HP bar at 0%.300 as she had it", r0) ~= nil, "her HP bar as she had it: kept off")
check(F.find("piece settled: %d+ piece", r0) == nil, "no copy of her mesh for the hidden piece (it lies in the old level)")
-- (Alt+F8 does nothing: the arm is still off)
local a2 = mark()
F.press("F8", "ALT")
F.run(2, pawn)
check(F.find("already off", a2) ~= nil, "Alt+F8 on the new Eve: the arm still off")

-- a save loaded (a new Eve, her HP bar full and staying so): the arm back after CARRY_FULL_S
old = pawn
pawn = E.make(F)
rawset(E.mesh, "SkeletalMesh", ASSET)
old.__dead, old.__freed = true, true
E.s.hp = 1.0
local r1 = mark()
F.run(9, pawn)
check(F.find("Bip001%-R%-UpperArm off %(carried%)", r1) ~= nil, "a load: cut again at first")
F.run(62, pawn)
check(F.find("carried: her HP bar full 60 s on, not her 0%.300: a save loaded, the parts back", r1) ~= nil, "her HP bar full: a save, the arm back")
local a3 = mark()
E.s.hp = 0.3
F.press("F8", "ALT")
F.run(3, pawn)
check(F.find("her right arm cut off", a3) ~= nil, "Alt+F8 after the load: cut")

-- a save loaded with her HP bar set to another value: the arm back once it is set
old = pawn
pawn = E.make(F)
rawset(E.mesh, "SkeletalMesh", ASSET)
old.__dead, old.__freed = true, true
local r2 = mark()
F.run(9, pawn)
E.s.hp = 0.7
F.run(1, pawn)
check(F.find("carried: her HP bar set to 0%.700, not her 0%.300: a save loaded, the parts back", r2) ~= nil, "her HP bar set to another value: the arm back")
for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
